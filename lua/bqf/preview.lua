local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local auto_preview, delay_syntax
local keep_preview, orig_pos

local config = require('bqf.config')
local qfs = require('bqf.qfsession')
local qftool = require('bqf.qftool')
local floatwin = require('bqf.floatwin')
local utils = require('bqf.utils')

local function setup()
    local pconf = config.preview
    vim.validate({preview = {pconf, 'table'}})
    floatwin.setup({
        win_height = pconf.win_height,
        win_vheight = pconf.win_vheight,
        border_chars = pconf.border_chars
    })
    auto_preview = pconf.auto_preview
    delay_syntax = tonumber(pconf.delay_syntax)
    vim.validate({auto_preview = {auto_preview, 'boolean'}, delay_syntax = {delay_syntax, 'number'}})

    api.nvim_exec([[
        aug BqfPreview
            au!
        aug END
    ]], false)

    cmd('hi default link BqfPreviewCursor Cursor')
    cmd('hi default link BqfPreviewRange Search')
end

local function update_border(border_width, qf_items, idx)
    local pos_str = string.format('[%d/%d]', idx, #qf_items)
    local pbufnr = qf_items[idx].bufnr
    local buf_str = string.format('buf %d:', pbufnr)
    local name = fn.bufname(pbufnr):gsub('^' .. vim.env.HOME, '~')
    local pad_fit = border_width - 8 - fn.strwidth(buf_str) - fn.strwidth(pos_str)
    if pad_fit - fn.strwidth(name) < 0 then
        name = fn.pathshorten(name)
        if pad_fit - fn.strwidth(name) < 0 then
            name = ''
        end
    end
    local title = string.format(' %s %s %s ', pos_str, buf_str, name)
    floatwin.update_title(title)
    floatwin.update_scrollbar()
end

local function update_mode(qf_winid)
    qf_winid = qf_winid or api.nvim_get_current_win()
    local ps = qfs[qf_winid].preview
    if ps.full then
        floatwin.set_win_height(999, 999)
    else
        local conf = config.preview
        floatwin.set_win_height(conf.win_height, conf.win_vheight)
    end
end

local function exec_preview(qf_all, idx, file_winid)
    local entry = qf_all.items[idx]
    if not entry then
        return
    end

    local lnum, col, pattern = entry.lnum, entry.col, entry.pattern
    vim.wo.wrap, vim.wo.foldenable = false, false
    vim.wo.number, vim.wo.relativenumber = true, false
    vim.wo.cursorline, vim.wo.signcolumn = true, 'no'
    vim.wo.foldmethod = 'manual'

    if lnum < 1 then
        api.nvim_win_set_cursor(0, {1, 0})
        if pattern ~= '' then
            fn.search(pattern, 'c')
        end
    else
        if not pcall(api.nvim_win_set_cursor, 0, {lnum, math.max(0, col - 1)}) then
            return
        end
    end

    utils.zz()
    orig_pos = api.nvim_win_get_cursor(0)

    fn.clearmatches()

    local lsp_ranges_hl = qf_all.lsp_ranges_hl and not vim.tbl_isempty(qf_all.lsp_ranges_hl) and
                              qf_all.lsp_ranges_hl[idx] or {}
    local pattern_hl = qf_all.pattern_hl

    local range_ids
    if not vim.tbl_isempty(lsp_ranges_hl) then
        local pos_list = utils.lsp_range2pos_list(lsp_ranges_hl)
        if not vim.tbl_isempty(pos_list) then
            range_ids = utils.matchaddpos('BqfPreviewRange', pos_list)
        end
    elseif pattern_hl and pattern_hl ~= '' then
        local pos_list = utils.pattern2pos_list(pattern_hl)
        if not vim.tbl_isempty(pos_list) then
            range_ids = utils.matchaddpos('BqfPreviewRange', pos_list)
        end
    end
    if lnum > 0 then
        fn.matchaddpos('BqfPreviewCursor', {{lnum, math.max(1, col)}}, 11)
    end
    if not range_ids then
        if lnum < 1 then
            fn.matchadd('BqfPreviewRange', pattern)
        elseif col < 1 then
            fn.matchaddpos('BqfPreviewRange', {{lnum}})
        end
    end
    cmd(string.format('noa call nvim_set_current_win(%d)', file_winid))
end

local function do_syntax(qf_winid, idx)
    local ps = qfs[qf_winid].preview
    if not ps then
        return
    end
    local last_idx = ps.idx or -1
    if idx ~= last_idx then
        return
    end

    if not ps.buf_loaded and vim.bo[ps.bufnr].filetype == '' then
        local preview_winid = floatwin.winid()
        if fn.bufwinid(ps.bufnr) == preview_winid then
            -- https://github.com/nvim-treesitter/nvim-treesitter/issues/898
            -- fuxx min.js!
            local lcount = api.nvim_buf_line_count(ps.bufnr)
            local bytes = api.nvim_buf_get_offset(ps.bufnr, lcount)
            -- bytes / lcount < 1000 LGTM :)
            if bytes / lcount < 1000 then
                -- nvim_buf_call is less side-effects than changing window
                -- make sure that buffer in preview window must not in normal window
                api.nvim_buf_call(ps.bufnr, function()
                    cmd('filetype detect')
                end)
            end
        end
    end
end

local function clean_preview_buf(bufnr, loaded_before)
    if not bufnr then
        return
    end
    if not loaded_before and api.nvim_buf_is_loaded(bufnr) and fn.buflisted(bufnr) == 0 then
        cmd('bd! ' .. bufnr)
    end
end

-- https://github.com/neovim/neovim/issues/11525
-- buffers inherit last closed window option if the buffer is loaded
local function fire_restore_buf_opts(bufnr, loaded_before, fwin_opts)
    if not bufnr or vim.tbl_isempty(fwin_opts) then
        return
    end
    if loaded_before and fn.bufwinid(bufnr) == -1 then
        if not pcall(api.nvim_buf_get_var, bufnr, 'bqf_fwin_opts') then
            api.nvim_buf_set_var(bufnr, 'bqf_fwin_opts', fwin_opts)
            cmd(string.format('au Bqf BufWinEnter <buffer=%d> ++once %s', bufnr,
                string.format([[lua require('bqf.layout').restore_fwin_opts()]])))
        end
    end
end

-- upstream bug
-- https://github.com/neovim/neovim/issues/11597
local function fix_missing_redraw(qf_winid)
    M.open(qf_winid)
    vim.defer_fn(function()
        cmd('mode')
    end, 20)
end

local function reopen(qf_winid)
    qf_winid = qf_winid or api.nvim_get_current_win()
    M.close(qf_winid)
    M.open(qf_winid)
end

function M.auto_enabled()
    return auto_preview
end

function M.keep_preview()
    keep_preview = true
end

function M.toggle_mode()
    local qf_winid = api.nvim_get_current_win()
    local ps = qfs[qf_winid].preview
    ps.full = ps.full ~= true
    ps.idx = -1
    fix_missing_redraw(qf_winid)
end

function M.close(qf_winid)
    qf_winid = qf_winid or api.nvim_get_current_win()
    local ps = qfs[qf_winid].preview
    if not ps or keep_preview then
        keep_preview = nil
        return
    end

    floatwin.close()
    clean_preview_buf(ps.bufnr, ps.buf_loaded)
    fire_restore_buf_opts(ps.bufnr, ps.buf_loaded, qfs[qf_winid].fwin_opts)
    ps.idx = -1
end

function M.open(qf_winid, qf_idx)
    qf_winid = qf_winid or api.nvim_get_current_win()
    local file_winid = qftool.filewinid(qf_winid)

    local ps = qfs[qf_winid].preview
    if not ps or fn.winnr('$') == 1 or api.nvim_win_get_config(file_winid).relative ~= '' then
        return
    end

    local last_idx = ps.idx or -1

    qf_idx = qf_idx or api.nvim_win_get_cursor(qf_winid)[1]
    if qf_idx == last_idx then
        return
    end

    ps.idx = qf_idx

    local qf_all = qftool.getall(qf_winid)

    local qf_items = qf_all.items
    if #qf_items == 0 then
        M.close(qf_winid)
        return
    end

    local entry = qf_items[qf_idx]
    if not entry then
        return
    end

    local pbufnr, valid = entry.bufnr, entry.valid

    if not valid or not api.nvim_buf_is_valid(pbufnr) then
        M.close(qf_winid)
        return
    end

    local pbuf_loaded = api.nvim_buf_is_loaded(pbufnr)

    update_mode(qf_winid)
    local preview_winid, border_winid = floatwin.open(pbufnr, qf_winid, file_winid)
    if preview_winid < 0 or border_winid < 0 then
        return
    end

    if ps.bufnr ~= pbufnr then
        clean_preview_buf(ps.bufnr, ps.buf_loaded)
        fire_restore_buf_opts(ps.bufnr, ps.buf_loaded, qfs[qf_winid].fwin_opts)
        ps.bufnr, ps.buf_loaded = pbufnr, pbuf_loaded
    end

    utils.win_execute(preview_winid, function()
        exec_preview(qf_all, qf_idx, file_winid)
    end)

    update_border(api.nvim_win_get_width(preview_winid), qf_items, qf_idx)

    vim.defer_fn(function()
        do_syntax(qf_winid, qf_idx)
    end, delay_syntax)
end

function M.init_window(qf_winid)
    -- delayed called, qf_winid maybe invalid
    if not api.nvim_win_is_valid(qf_winid) then
        return
    end

    qfs[qf_winid].preview = qfs[qf_winid].preview or {full = false}
    qfs[qf_winid].preview.idx = -1
    if auto_preview and api.nvim_get_current_win() == qf_winid then
        -- bufhidden=hide after vim-patch:8.1.0877
        if qftool.type(qf_winid) == 'qf' and vim.bo.bufhidden == 'wipe' then
            vim.bo.bufhidden = 'hide'
        end

        if qfs[qf_winid].preview.full then
            fix_missing_redraw(qf_winid)
        else
            M.open(qf_winid)
        end
    end
end

function M.scroll(direction)
    local preview_winid = floatwin.winid()
    if preview_winid < 0 or not direction then
        return
    end
    local file_winid = qftool.filewinid()
    utils.win_execute(preview_winid, function()
        if direction == 0 then
            api.nvim_win_set_cursor(preview_winid, orig_pos)
        else
            -- ^D = 0x04, ^U = 0x15
            fn.execute(string.format('norm! %c', direction > 0 and 0x04 or 0x15))
        end
        utils.zz()
        cmd(string.format('noa call nvim_set_current_win(%d)', file_winid))
    end)
    floatwin.update_scrollbar()
end

function M.toggle()
    auto_preview = auto_preview ~= true
    if auto_preview then
        api.nvim_echo({{'Enable preview automatically', 'WarningMsg'}}, true, {})
        M.open()
    else
        api.nvim_echo({{'Disable preview automatically', 'WarningMsg'}}, true, {})
        M.close()
    end
end

function M.toggle_item()
    if floatwin.validate_window() then
        M.close()
    else
        M.open()
    end
end

function M.move_cursor()
    local qf_winid = api.nvim_get_current_win()
    local ps = qfs[qf_winid].preview
    if not ps then
        return
    end
    if auto_preview then
        M.open()
    else
        local last_idx = ps.idx
        if api.nvim_win_get_cursor(qf_winid)[1] ~= last_idx then
            M.close()
        end
    end
end

function M.tabenter_event()
    if qftool.validate_qf() and auto_preview then
        M.open()
    end
end

function M.redraw_win(qf_winid)
    if floatwin.validate_window() then
        reopen(qf_winid)
    end
end

-- Enabling preview and executing cpfile or cnfile or cfdo hits previewed buffer may cause
-- quickfix window enter the entry buffer, it only produces in quickfix not for location.
function M.fix_qf_jump(qf_bufnr)
    local qf_winid = api.nvim_get_current_win()
    local ok, msg = pcall(qftool.filewinid, qf_winid)
    if ok then
        local file_winid = msg
        local buf_entered = api.nvim_get_current_buf()
        api.nvim_win_set_buf(qf_winid, qf_bufnr)
        api.nvim_set_current_win(file_winid)
        api.nvim_win_set_buf(file_winid, buf_entered)
    else
        -- no need after vim-patch:8.1.0877
        api.nvim_buf_delete(qf_bufnr, {})
    end
end

function M.buf_event()
    -- I hate these autocmd string!!!!!!!!!!!!!!!!!!!!!
    local bufnr = api.nvim_get_current_buf()
    api.nvim_exec([[
        aug BqfPreview
            au! * <buffer>
            au VimResized <buffer> lua require('bqf.preview').redraw_win()
            au TabEnter <buffer> lua require('bqf.preview').tabenter_event()
            au CursorMoved <buffer> lua require('bqf.preview').move_cursor()
    ]], false)
    cmd(string.format('au BufLeave,WinLeave <buffer> %s', string.format(
        [[lua require('bqf.preview').close(vim.fn.bufwinid(%d))]], bufnr)))
    if qftool.type() == 'qf' then
        cmd(string.format('au BufHidden <buffer> exe "%s %s"',
            'au BqfPreview BufEnter * ++once ++nested',
            string.format([[lua require('bqf.preview').fix_qf_jump(%d)]], bufnr)))

        -- bufhidden=hide after vim-patch:8.1.0877
        if vim.bo.bufhidden == 'wipe' then
            cmd('au QuitPre <buffer> ++nested bw')
            cmd([[au BufEnter <buffer> lua vim.bo.bufhidden = 'hide']])
            cmd(string.format('au BufLeave <buffer> exe "%s %s"', 'au BqfPreview BufEnter * ++once',
                string.format([[sil! lua vim.bo[%d].bufhidden = 'wipe']], bufnr)))
        end
    end
    cmd('aug END')
end

setup()

return M
