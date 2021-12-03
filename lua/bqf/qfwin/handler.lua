local M = {}
local api = vim.api
local cmd = vim.cmd
local fn = vim.fn

local qfs = require('bqf.qfwin.session')
local utils = require('bqf.utils')

function M.sign_reset()
    local qwinid = api.nvim_get_current_win()
    local qs = qfs.get(qwinid)
    local qlist = qs:list()
    local sign = qlist:get_sign()
    sign:reset()
end

function M.sign_toggle(rel, lnum, bufnr)
    lnum = lnum or api.nvim_win_get_cursor(0)[1]
    bufnr = bufnr or api.nvim_get_current_buf()
    local qwinid = api.nvim_get_current_win()
    local qs = qfs.get(qwinid)
    local qlist = qs:list()
    local sign = qlist:get_sign()
    sign:toggle(lnum, bufnr)
    if rel ~= 0 then
        cmd(('norm! %s'):format(rel > 0 and 'j' or 'k'))
    end
end

function M.sign_toggle_buf(lnum, bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    lnum = lnum or api.nvim_win_get_cursor(0)[1]
    local qwinid = api.nvim_get_current_win()
    local qs = qfs.get(qwinid)
    local qlist = qs:list()
    local items = qlist:get_items()
    local entry_bufnr = items[lnum].bufnr
    local lnum_list = {}
    for l, entry in ipairs(items) do
        if entry.bufnr == entry_bufnr then
            table.insert(lnum_list, l)
        end
    end
    local sign = qlist:get_sign()
    sign:toggle(lnum_list, bufnr)
end

-- only work under map with <Cmd>
function M.sign_vm_toggle(bufnr)
    local mode = api.nvim_get_mode().mode
    vim.validate({
        mode = {
            mode, function(m)
                -- ^V = 0x16
                return m:lower() == 'v' or m == ('%c'):format(0x16)
            end, 'visual mode'
        }
    })
    -- ^[ = 0x1b
    cmd(('norm! %c'):format(0x1b))
    bufnr = bufnr or api.nvim_get_current_buf()
    local s_lnum = api.nvim_buf_get_mark(bufnr, '<')[1]
    local e_lnum = api.nvim_buf_get_mark(bufnr, '>')[1]
    local lnum_list = {}
    for i = s_lnum, e_lnum do
        table.insert(lnum_list, i)
    end
    local qwinid = api.nvim_get_current_win()
    local qs = qfs.get(qwinid)
    local qlist = qs:list()
    local sign = qlist:get_sign()
    sign:toggle(lnum_list, bufnr)
end

function M.sign_clear(bufnr)
    local qwinid = api.nvim_get_current_win()
    local qs = qfs.get(qwinid)
    local qlist = qs:list()
    local sign = qlist:get_sign()
    sign:clear(bufnr)
end

function M.restore_winview()
    local qwinid = api.nvim_get_current_win()
    local qs = qfs.get(qwinid)
    local qlist = qs:list()
    local wv = qlist:get_winview()
    if wv then
        fn.winrestview(wv)
    end
end

function M.nav_history(direction)
    local qwinid = api.nvim_get_current_win()
    local qs = qfs.get(qwinid)
    local qlist = qs:list()
    qlist:set_winview(fn.winsaveview())

    local prefix = qlist.type == 'loc' and 'l' or 'c'
    local cur_nr, last_nr = qlist:get_qflist({nr = 0}).nr, qlist:get_qflist({nr = '$'}).nr
    if last_nr <= 1 then
        return
    end

    local ok, msg = pcall(cmd, ([[sil exe '%d%s%s']]):format(vim.v.count1, prefix,
        direction and 'newer' or 'older'))
    if not ok then
        if msg:match(':E380: At bottom') then
            cmd(([[sil exe '%d%snewer']]):format(last_nr - cur_nr, prefix))
        elseif msg:match(':E381: At top') then
            cmd(([[sil exe '%d%solder']]):format(last_nr - 1, prefix))
        end
    end

    local qinfo = qlist:get_qflist({nr = 0, size = 0, title = 0})
    local nr, size, title = qinfo.nr, qinfo.size, qinfo.title

    api.nvim_echo({
        {'('}, {tostring(nr), 'Identifier'}, {' of '}, {tostring(last_nr), 'Identifier'}, {') ['},
        {tostring(size), 'Type'}, {'] '}, {' >> ' .. title, 'Title'}
    }, false, {})
end

function M.nav_file(next)
    local lnum, col = unpack(api.nvim_win_get_cursor(0))
    local qwinid = api.nvim_get_current_win()
    local qs = qfs.get(qwinid)
    local qlist = qs:list()
    local items, size = qlist:get_items(), qlist:get_qflist({size = 0}).size
    local cur_bufnr = items[lnum].bufnr
    local start, stop, step = unpack(next and {lnum + 1, size, 1} or {lnum - 1, 1, -1})

    for i = start, stop, step do
        if items[i].valid == 1 and items[i].bufnr ~= cur_bufnr then
            qlist:change_idx(i)
            api.nvim_win_set_cursor(0, {i, col})
            return
        end
    end
    api.nvim_echo({{'No more items', 'WarningMsg'}}, true, {})
end

local function validate_size(qlist)
    local valid = qlist:get_qflist({size = 0}).size > 0
    if not valid then
        api.nvim_err_writeln('E42: No Errors')
    end
    return valid
end

local function do_edit(qwinid, idx, close, action)
    qwinid = qwinid or api.nvim_get_current_win()
    local qs = qfs.get(qwinid)
    local pwinid = qs:pwinid()
    assert(utils.is_win_valid(pwinid), 'file window is invalid')

    local qlist = qs:list()
    if not validate_size(qlist) then
        return false
    end

    idx = idx or api.nvim_win_get_cursor(qwinid)[1]
    qlist:change_idx(idx)
    local entry = qlist:get_entry(idx)
    local bufnr, lnum, col = entry.bufnr, entry.lnum, entry.col

    if close then
        api.nvim_win_close(qwinid, true)
    end

    api.nvim_set_current_win(pwinid)

    local last_bufnr = api.nvim_get_current_buf()
    local last_bufname = api.nvim_buf_get_name(last_bufnr)
    local last_bufoff = api.nvim_buf_get_offset(0, 1)
    if action and not utils.is_unname_buf(last_bufnr, last_bufname, last_bufoff) then
        action(bufnr)
    else
        api.nvim_set_current_buf(bufnr)
    end

    vim.bo.buflisted = true
    pcall(api.nvim_win_set_cursor, 0, {lnum, math.max(0, col - 1)})

    if vim.wo.foldenable and vim.o.fdo:match('quickfix') then
        cmd('norm! zv')
    end
    utils.zz()

    if utils.is_unname_buf(last_bufnr, last_bufname, last_bufoff) then
        api.nvim_buf_delete(last_bufnr, {})
    end
    return true
end

function M.open(close, jump_cmd, qwinid, idx)
    do_edit(qwinid, idx, close, function(bufnr)
        if jump_cmd then
            local fname = fn.fnameescape(api.nvim_buf_get_name(bufnr))
            if jump_cmd == 'drop' then
                local buf_info = fn.getbufinfo(bufnr)
                if #buf_info == 1 and #buf_info[1].windows == 0 then
                    api.nvim_set_current_buf(bufnr)
                else
                    cmd(('%s %s'):format(jump_cmd, fname))
                end
            else
                cmd(('%s %s'):format(jump_cmd, fname))
            end
        else
            api.nvim_set_current_buf(bufnr)
        end
    end)
end

function M.tabedit(stay, qwinid, idx)
    local last_tp = api.nvim_get_current_tabpage()
    qwinid = qwinid or api.nvim_get_current_win()
    local unname_buf = true
    if do_edit(qwinid, idx, false, function(bufnr)
        unname_buf = false
        local fname = fn.fnameescape(api.nvim_buf_get_name(bufnr))
        cmd(('tabedit %s'):format(fname))
    end) then
        local cur_tp = api.nvim_get_current_tabpage()
        if not unname_buf then
            api.nvim_set_current_win(qwinid)
        end

        if last_tp ~= cur_tp and not stay then
            api.nvim_set_current_tabpage(cur_tp)
        end
    end
end

return M
