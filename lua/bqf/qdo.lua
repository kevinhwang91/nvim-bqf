local M = {}
local fn = vim.fn
local api = vim.api
local cmd = vim.cmd

local wses = require('bqf.wsession')

function M.sign_reset()
    local qwinid = api.nvim_get_current_win()
    local qo = wses.qobj(qwinid)
    local sign = qo:get_sign()
    sign:reset()
end

function M.sign_toggle(rel, lnum, bufnr)
    lnum = lnum or api.nvim_win_get_cursor(0)[1]
    bufnr = bufnr or api.nvim_get_current_buf()
    local qwinid = api.nvim_get_current_win()
    local qo = wses.qobj(qwinid)
    local sign = qo:get_sign()
    sign:toggle(lnum, bufnr)
    if rel ~= 0 then
        cmd(('norm! %s'):format(rel > 0 and 'j' or 'k'))
    end
end

function M.sign_toggle_buf(lnum, bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    lnum = lnum or api.nvim_win_get_cursor(0)[1]
    local qwinid = api.nvim_get_current_win()
    local qo = wses.qobj(qwinid)
    local items = qo:get_items()
    local entry_bufnr = items[lnum].bufnr
    local lnum_list = {}
    for l, entry in ipairs(items) do
        if entry.bufnr == entry_bufnr then
            table.insert(lnum_list, l)
        end
    end
    local sign = qo:get_sign()
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
    fn.execute(('norm! %c'):format(0x1b))
    bufnr = bufnr or api.nvim_get_current_buf()
    local s_lnum = api.nvim_buf_get_mark(bufnr, '<')[1]
    local e_lnum = api.nvim_buf_get_mark(bufnr, '>')[1]
    local lnum_list = {}
    for i = s_lnum, e_lnum do
        table.insert(lnum_list, i)
    end
    local qwinid = api.nvim_get_current_win()
    local qo = wses.qobj(qwinid)
    local sign = qo:get_sign()
    sign:toggle(lnum_list, bufnr)
end

function M.sign_clear(bufnr)
    local qwinid = api.nvim_get_current_win()
    local qo = wses.qobj(qwinid)
    local sign = qo:get_sign()
    sign:clear(bufnr)
end

function M.nav_history(direction)
    local qwinid = api.nvim_get_current_win()
    local qo = wses.qobj(qwinid)
    local prefix = qo.type == 'loc' and 'l' or 'c'
    local cur_nr, last_nr = qo:get_qflist({nr = 0}).nr, qo:get_qflist({nr = '$'}).nr
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

    local qinfo = qo:get_qflist({nr = 0, size = 0, title = 0})
    local nr, size, title = qinfo.nr, qinfo.size, qinfo.title

    api.nvim_echo({
        {'('}, {tostring(nr), 'Identifier'}, {' of '}, {tostring(last_nr), 'Identifier'}, {') ['},
        {tostring(size), 'Type'}, {'] '}, {' >> ' .. title, 'Title'}
    }, false, {})
end

function M.nav_file(next)
    local lnum, col = unpack(api.nvim_win_get_cursor(0))
    local qwinid = api.nvim_get_current_win()
    local qo = wses.qobj(qwinid)
    local items, size = qo:get_items(), qo:get_qflist({size = 0}).size
    local cur_bufnr = items[lnum].bufnr
    local start, stop, step = unpack(next and {lnum + 1, size, 1} or {lnum - 1, 1, -1})

    for i = start, stop, step do
        if items[i].valid == 1 and items[i].bufnr ~= cur_bufnr then
            qo:change_idx(i)
            api.nvim_win_set_cursor(0, {i, col})
            return
        end
    end
    api.nvim_echo({{'No more items', 'WarningMsg'}}, true, {})
end

return M
