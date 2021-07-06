local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local wses = require('bqf.wsession')

local cache = {count = 0}

local function close(winid)
    local ok, msg = pcall(api.nvim_win_close, winid, false)
    if not ok then
        -- Vim:E444: Cannot close last window
        if msg:match('^Vim:E444') then
            cmd('new')
            api.nvim_win_close(winid, true)
        end
    end
end

function M.validate_qf(winid)
    winid = winid or api.nvim_get_current_win()

    -- Invalid window id
    -- Key not found: quickfix_title
    local ret = pcall(function()
        api.nvim_win_get_var(winid, 'quickfix_title')
    end)

    -- quickfix_title is undefined, copen when quickfix list is empty
    if not ret then
        ret = pcall(function()
            ret = fn.getwininfo(winid)[1].quickfix == 1
        end) and ret
    end
    return ret
end

function M.filewinid(winid)
    winid = winid or api.nvim_get_current_win()
    local filewinid = wses[winid].filewinid
    if not filewinid or not api.nvim_win_is_valid(filewinid) then
        if M.type(winid) == 'loc' then
            filewinid = fn.getloclist(winid, {filewinid = 0}).filewinid
        else
            filewinid = fn.win_getid(fn.winnr('#'))
            if filewinid <= 0 and not api.nvim_win_is_valid(filewinid) or
                M.validate_qf(filewinid) then
                local tabpage = api.nvim_win_get_tabpage(winid)
                for _, w_id in ipairs(api.nvim_tabpage_list_wins(tabpage)) do
                    if api.nvim_win_is_valid(w_id) and not M.validate_qf(w_id) and
                        api.nvim_win_get_config(w_id).relative == '' then
                        filewinid = w_id
                        break
                    end
                end
            end
        end
        if filewinid <= 0 or not api.nvim_win_is_valid(filewinid) or M.validate_qf(filewinid) then
            close(winid)
            wses[winid].filewinid = -1
            -- assert(false, 'A valid file window is not found in current tabpage')
        end
        wses[winid].filewinid = filewinid
    end
    return wses[winid].filewinid
end

function M.type(winid)
    winid = winid or api.nvim_get_current_win()

    vim.validate({winid = {winid, M.validate_qf, 'a valid quickfix window'}})

    if not wses[winid].qf_type then
        wses[winid].qf_type = fn.getwininfo(winid)[1].loclist == 1 and 'loc' or 'qf'
    end
    return wses[winid].qf_type
end

function M.get_cache()
    return cache
end

function M.entry(idx, winid)
    local e
    local items = M.get({idx = idx, items = 0}, winid).items
    if #items == 1 then
        e = items[1]
    end
    return e
end

local ctx = {}
function M.context(winid)
    winid = winid or api.nvim_get_current_win()
    local qinfo = M.get({id = 0, changedtick = 0}, winid)
    local id, changedtick = qinfo.id, qinfo.changedtick
    local content
    if ctx.id == id and ctx.changedtick == changedtick then
        content = ctx.content
    else
        content = {}
        local c = M.get({context = 0}, winid).context
        if type(c) == 'table' then
            local bqf_ctx = c.bqf
            if bqf_ctx then
                content.pattern_hl = bqf_ctx.pattern_hl
                content.lsp_ranges_hl = bqf_ctx.lsp_ranges_hl
            end
        end
        ctx.id, ctx.changedtick, ctx.content = id, changedtick, content
    end
    return content
end

local item_list = {}
function M.items(winid)
    winid = winid or api.nvim_get_current_win()
    local qinfo = M.get({id = 0, changedtick = 0}, winid)
    local id, changedtick = qinfo.id, qinfo.changedtick
    local content
    if item_list.id == id and item_list.changedtick == changedtick then
        content = item_list.content
    else
        content = M.get({items = 0}, winid).items
        item_list.id, item_list.changedtick, item_list.content = id, changedtick, content
    end
    return content
end

function M.id_exists(id, filewinid)
    if filewinid and filewinid > 0 then
        return fn.getloclist(filewinid, {id = id}).id == id
    else
        return fn.getqflist({id = id}).id == id
    end
end

function M.get(what, winid)
    local qf_type = M.type(winid)
    winid = winid or api.nvim_get_current_win()
    if not what or type(what) == 'table' and vim.tbl_isempty(what) then
        return qf_type == 'loc' and fn.getloclist(winid) or fn.getqflist()
    else
        return qf_type == 'loc' and fn.getloclist(winid, what) or fn.getqflist(what)
    end
end

function M.set(what, winid)
    local qf_type = M.type(winid)
    if qf_type == 'loc' then
        fn.setloclist(winid or api.nvim_get_current_win(), {}, ' ', what)
    else
        fn.setqflist({}, ' ', what)
    end
end

function M.update(what, winid)
    local qf_type = M.type(winid)
    if qf_type == 'loc' then
        fn.setloclist(winid or api.nvim_get_current_win(), {}, 'r', what)
    else
        fn.setqflist({}, 'r', what)
    end
    local changedtick = M.get({changedtick = 0}, winid).changedtick
    ctx.changedtick = changedtick
    item_list.changedtick = changedtick
end

function M.file(next)
    local lnum, col = unpack(api.nvim_win_get_cursor(0))
    local items, size = M.items(), M.get({size = 0}).size
    local cur_bufnr = items[lnum].bufnr
    local start, stop, step = unpack(next and {lnum + 1, size, 1} or {lnum - 1, 1, -1})

    for i = start, stop, step do
        if items[i].valid == 1 and items[i].bufnr ~= cur_bufnr then
            M.update({idx = i})
            api.nvim_win_set_cursor(0, {i, col})
            return
        end
    end
    api.nvim_echo({{'No more items', 'WarningMsg'}}, true, {})
end

function M.history(direction)
    local prefix = M.type() == 'loc' and 'l' or 'c'
    local cur_nr, last_nr = M.get({nr = 0}).nr, M.get({nr = '$'}).nr
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

    local qf_list = M.get({nr = 0, size = 0, title = 0})
    local nr, size, title = qf_list.nr, qf_list.size, qf_list.title

    api.nvim_echo({
        {'('}, {tostring(nr), 'Identifier'}, {' of '}, {tostring(last_nr), 'Identifier'}, {') ['},
        {tostring(size), 'Type'}, {'] '}, {' >> ' .. title, 'Title'}
    }, false, {})
end

return M
