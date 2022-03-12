---@class BqfPreviewHandler
local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local auto_preview, delay_syntax
local should_preview_cb
local keep_preview, orig_pos
local win_height, win_vheight
local wrap, border_chars
local last_idx
local PLACEHOLDER_TBL

local config = require('bqf.config')
local qfs = require('bqf.qfwin.session')
local pvs = require('bqf.preview.session')
local ts = require('bqf.preview.treesitter')
local extmark = require('bqf.preview.extmark')
local utils = require('bqf.utils')

local function exec_preview(item, lsp_range_hl, pattern_hl)
    local lnum, col, pattern = item.lnum, item.col, item.pattern

    if lnum < 1 then
        api.nvim_win_set_cursor(0, {1, 0})
        if pattern ~= '' then
            fn.search(pattern, 'c')
        end
    elseif not pcall(api.nvim_win_set_cursor, 0, {lnum, math.max(0, col - 1)}) then
        return
    end

    utils.zz()
    orig_pos = api.nvim_win_get_cursor(0)

    -- scrolling horizontally reset
    cmd('norm! ze')

    fn.clearmatches()

    local pos_list = {}
    if lsp_range_hl and not vim.tbl_isempty(lsp_range_hl) then
        pos_list = utils.lsp_range2pos_list(lsp_range_hl)
    elseif pattern_hl and pattern_hl ~= '' then
        pos_list = utils.pattern2pos_list(pattern_hl)
    elseif utils.has_06() then
        local end_lnum, end_col = item.end_lnum, item.end_col
        pos_list = utils.qf_range2pos_list(lnum, col, end_lnum, end_col)
    end

    if not vim.tbl_isempty(pos_list) then
        utils.matchaddpos('BqfPreviewRange', pos_list)
    else
        if lnum < 1 then
            fn.matchadd('BqfPreviewRange', pattern)
        elseif col < 1 then
            fn.matchaddpos('BqfPreviewRange', {{lnum}})
        end
    end

    if lnum > 0 then
        fn.matchaddpos('BqfPreviewCursor', {{lnum, math.max(1, col)}}, 11)
    end
end

local function preview_session(qwinid)
    qwinid = qwinid or api.nvim_get_current_win()
    return pvs.get(qwinid) or PLACEHOLDER_TBL
end

local function do_syntax(qwinid, idx, pbufnr)
    local ps = preview_session(qwinid)
    if ps == PLACEHOLDER_TBL or idx ~= last_idx or (pbufnr == ps.bufnr and ps.syntax) then
        return
    end

    local fbufnr = ps.float_bufnr()

    -- https://github.com/nvim-treesitter/nvim-treesitter/issues/898
    -- fuxx min.js!
    local lcount = api.nvim_buf_line_count(fbufnr)
    local bytes = api.nvim_buf_get_offset(fbufnr, lcount)
    -- bytes / lcount < 500 LGTM :)
    if bytes / lcount < 500 then
        local ei_bak = vim.o.ei
        local ok, ft = pcall(api.nvim_buf_call, fbufnr, function()
            vim.o.ei = 'FileType'
            vim.bo.ft = 'bqfpreview'
            cmd(('do filetypedetect BufRead %s'):format(
                fn.fnameescape(api.nvim_buf_get_name(ps.bufnr))))
            return vim.bo.ft
        end)
        vim.o.ei = ei_bak

        if ok and ft ~= 'bqfpreview' then
            ps.syntax = ts.attach(pbufnr, fbufnr, ft)
            if not ps.syntax then
                vim.bo[fbufnr].syntax = ft
                ps.syntax = true
            end
        end
    end
end

function M.auto_enabled()
    return auto_preview
end

function M.keep_preview()
    keep_preview = true
end

function M.toggle_mode()
    local qwinid = api.nvim_get_current_win()
    local ps = preview_session(qwinid)
    if ps == PLACEHOLDER_TBL then
        return
    end

    ps.full = ps.full ~= true
    last_idx = -1
    M.open(qwinid, nil, true)
end

function M.close(qwinid)
    if keep_preview then
        keep_preview = nil
        return
    end

    last_idx = -1
    pvs.close()

    ts.shrink_cache()

    qwinid = qwinid or api.nvim_get_current_win()
    local ps = preview_session(qwinid)
    if ps then
        ps.bufnr = nil
    end
end

function M.open(qwinid, qidx, force)
    qwinid = qwinid or api.nvim_get_current_win()
    local qs = qfs:get(qwinid)
    local qlist = qs:list()
    local pwinid = qs:pwinid()
    local ps = preview_session(qwinid)

    if ps == PLACEHOLDER_TBL or api.nvim_tabpage_list_wins(0) == 1 or fn.win_gettype(pwinid) ~= '' then
        return
    end

    qidx = qidx or api.nvim_win_get_cursor(qwinid)[1]
    if qidx == last_idx then
        return
    end

    last_idx = qidx

    local item = qlist:item(qidx)
    if not item then
        M.close(qwinid)
        return
    end

    local pbufnr = item.bufnr

    if pbufnr == 0 or not api.nvim_buf_is_valid(pbufnr) then
        M.close(qwinid)
        return
    end

    if ps.bufnr ~= pbufnr and not force and should_preview_cb and not should_preview_cb(pbufnr) then
        M.close(qwinid)
        return
    end

    ps:valid_or_build(pwinid)

    pvs.display()

    local fbufnr = pvs.float_bufnr()
    if not fbufnr then
        return
    end

    local loaded = api.nvim_buf_is_loaded(pbufnr)
    if ps.bufnr ~= pbufnr then
        pvs.floatbuf_reset()
        ts.disable_active(fbufnr)

        extmark.clear_highlight(fbufnr)
        utils.transfer_buf(pbufnr, fbufnr)
        ps.bufnr = pbufnr
        ps.syntax = ts.try_attach(pbufnr, fbufnr, loaded)
    end

    if not ps.syntax then
        vim.defer_fn(function()
            do_syntax(qwinid, qidx, pbufnr)
        end, delay_syntax)
    end

    local ctx = qlist:context().bqf or {}
    local lsp_ranges_hl, pattern_hl = ctx.lsp_ranges_hl, ctx.pattern_hl
    local lsp_range_hl
    if type(lsp_ranges_hl) == 'table' then
        lsp_range_hl = lsp_ranges_hl[qidx]
    end

    pvs.floatwin_exec(function()
        exec_preview(item, lsp_range_hl, pattern_hl)
        if loaded then
            local topline, botline = pvs.visible_region()
            extmark.update_highlight(pbufnr, fbufnr, topline, botline)
        end
        cmd(('noa call nvim_set_current_win(%d)'):format(pwinid))
    end)

    local size = qlist:get_qflist({size = 0}).size
    pvs.update_border(pbufnr, qidx, size)
end

function M.scroll(direction)
    if pvs.validate() and direction then
        local qwinid = api.nvim_get_current_win()
        local qs = qfs:get(qwinid)
        local pwinid = qs:pwinid()
        pvs.floatwin_exec(function()
            if direction == 0 then
                api.nvim_win_set_cursor(0, orig_pos)
            else
                -- ^D = 0x04, ^U = 0x15
                cmd(('norm! %c'):format(direction > 0 and 0x04 or 0x15))
            end
            utils.zz()
            local ps = preview_session(qwinid)
            local loaded = api.nvim_buf_is_loaded(ps.bufnr)
            if loaded then
                local topline, botline = pvs.visible_region()
                extmark.update_highlight(ps.bufnr, ps.float_bufnr(), topline, botline)
            end
            cmd(('noa call nvim_set_current_win(%d)'):format(pwinid))
        end)
        pvs.update_scrollbar()
    end
end

function M.toggle()
    local ps = preview_session()
    if ps == PLACEHOLDER_TBL then
        return
    end
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
    if pvs.validate() then
        M.close()
    else
        M.open(nil, nil, true)
    end
end

function M.move_cursor()
    local qwinid = api.nvim_get_current_win()
    local ps = preview_session(qwinid)
    if ps == PLACEHOLDER_TBL then
        return
    end

    if auto_preview then
        M.open()
    else
        if api.nvim_win_get_cursor(qwinid)[1] ~= last_idx then
            M.close()
        end
    end
end

function M.redraw_win()
    if pvs.validate() then
        M.close()
        M.open()
    end
end

function M.initialize(qwinid)
    cmd([[
        aug BqfPreview
            au! * <buffer>
            au VimResized <buffer> lua require('bqf.preview.handler').redraw_win()
            au CursorMoved,WinEnter <buffer> lua require('bqf.preview.handler').move_cursor()
            au WinLeave,BufWipeout <buffer> lua require('bqf.preview.handler').close()
        aug END
    ]])

    pvs:new(qwinid, {
        win_height = win_height,
        win_vheight = win_vheight,
        wrap = wrap,
        border_chars = border_chars
    })

    -- some plugins will change the quickfix window, preview window should init later
    vim.defer_fn(function()
        last_idx = -1
        -- delayed called, qwinid maybe invalid
        if not utils.is_win_valid(qwinid) then
            return
        end

        if auto_preview and api.nvim_get_current_win() == qwinid then
            M.open(qwinid)
        end
    end, 50)
end

local function init()
    local pconf = config.preview
    vim.validate({preview = {pconf, 'table'}})
    auto_preview = pconf.auto_preview
    delay_syntax = tonumber(pconf.delay_syntax)
    wrap = pconf.wrap
    should_preview_cb = pconf.should_preview_cb
    border_chars = pconf.border_chars
    win_height = tonumber(pconf.win_height)
    win_vheight = tonumber(pconf.win_vheight or win_height)
    vim.validate({
        auto_preview = {auto_preview, 'boolean'},
        delay_syntax = {delay_syntax, 'number'},
        wrap = {wrap, 'boolean'},
        should_preview_cb = {should_preview_cb, 'function', true},
        border_chars = {
            border_chars, function(chars)
                return type(chars) == 'table' and #chars == 9
            end, 'a table with 9 chars'
        },
        win_height = {win_height, 'number'},
        win_vheight = {win_vheight, 'number'}
    })

    cmd([[
        hi default link BqfPreviewFloat Normal
        hi default link BqfPreviewBorder Normal
        hi default link BqfPreviewCursor Cursor
        hi default link BqfPreviewRange IncSearch

        aug BqfPreview
            au!
        aug END
    ]])

    PLACEHOLDER_TBL = {}
end

init()

return M
