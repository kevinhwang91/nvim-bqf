local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local qfs = require('bqf.qfsession')

local cache = {count = 0}

function M.filewinid(winid)
    winid = winid or api.nvim_get_current_win()
    local file_winid = qfs[winid].file_winid
    if not file_winid or not api.nvim_win_is_valid(file_winid) then
        if M.type(winid) == 'loc' then
            file_winid = fn.getloclist(winid, {filewinid = 0}).filewinid
        else
            file_winid = fn.win_getid(fn.winnr('#'))
        end
        if file_winid <= 0 or not api.nvim_win_is_valid(file_winid) then
            for _, w_id in ipairs(api.nvim_list_wins()) do
                if w_id > 0 and vim.bo[fn.winbufnr(w_id)].buftype ~= 'quickfix' and
                    api.nvim_win_is_valid(w_id) and api.nvim_win_get_config(w_id).relative == '' then
                    file_winid = w_id
                    break
                end
            end
            if file_winid <= 0 or not api.nvim_win_is_valid(file_winid) then
                assert(false, 'A valid file window is not found in current tabpage')
            end
        end
        qfs[winid].file_winid = file_winid
    end
    return qfs[winid].file_winid
end

function M.type(winid)
    local bufnr = winid and fn.winbufnr(winid) or api.nvim_get_current_buf()

    assert(vim.bo[bufnr].buftype == 'quickfix',
        'argument #1 winid or current window is not a quickfix window')

    winid = winid or api.nvim_get_current_win()

    if not qfs[winid].qf_type then
        qfs[winid].qf_type = fn.getwininfo(winid)[1].loclist == 1 and 'loc' or 'qf'
    end
    return qfs[winid].qf_type
end

function M.getall(winid)
    winid = winid or api.nvim_get_current_win()

    local qf_info = M.get({id = 0, changedtick = 0}, winid)
    local qf_all = cache[qf_info.id]
    if qf_all and qf_all.changedtick == qf_info.changedtick then
        return qf_all
    end

    qf_all = M.get({all = 0}, winid)
    if type(qf_all.context) == 'table' then
        local bqf_ctx = qf_all.context.bqf
        if bqf_ctx then
            qf_all.pattern_hl = bqf_ctx.pattern_hl
            qf_all.lsp_ranges_hl = bqf_ctx.lsp_ranges_hl
        end
    end

    cache[qf_all.id] = qf_all

    -- help GC manually
    cache.count = cache.count + 1
    if cache.count == 10 then
        local new_cache = {count = 0}
        for i = 1, M.get({nr = '$'}, winid).nr do
            local id = M.get({nr = i, id = 0}, winid).id
            new_cache[id] = cache[id]
        end
        cache = new_cache
    end

    return qf_all
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
    local qf_all = M.getall(winid)

    local qf_type = M.type(winid)
    if qf_type == 'loc' then
        fn.setloclist(winid or api.nvim_get_current_win(), {}, 'r', what)
    else
        fn.setqflist({}, 'r', what)
    end

    local qf_info = M.get({changedtick = 0}, winid)
    qf_all.changedtick = qf_info.changedtick
end

function M.file(next)
    local cur_idx = api.nvim_win_get_cursor(0)[1]
    local qf_all = M.getall()
    local items, size = qf_all.items, qf_all.size
    local cur_bufnr = items[cur_idx].bufnr
    local start, stop, step = unpack(next and {cur_idx + 1, size, 1} or {cur_idx - 1, 1, -1})

    for i = start, stop, step do
        if items[i].valid == 1 and items[i].bufnr ~= cur_bufnr then
            cmd(tostring(i))
            M.update({idx = i})
            return
        end
    end
    cmd([[echohl WarningMsg | echo 'No more items' | echohl None]])
end

function M.history(direction)
    local prefix = M.type() == 'loc' and 'l' or 'c'
    local cur_nr, last_nr = M.get({nr = 0}).nr, M.get({nr = '$'}).nr
    if last_nr == 1 then
        return
    end

    local ok, msg = pcall(cmd, string.format([[silent execute '%d%s%s']], vim.v.count1, prefix,
        direction and 'newer' or 'older'))
    if not ok then
        if msg:match('^Vim%(%a+%):E380') then
            cmd(string.format([[silent execute '%d%snewer']], last_nr - cur_nr, prefix))
        elseif msg:match('^Vim%(%a+%):E381') then
            cmd(string.format([[silent execute '%d%solder']], last_nr - 1, prefix))
        end
    end

    local qf_list = M.get({nr = 0, size = 0, title = 0})
    local nr, size, title = qf_list.nr, qf_list.size, qf_list.title

    -- delay to cooperate with preview.fix_missing_redraw
    vim.defer_fn(function()
        cmd(string.format([[echon '(' | echohl Identifier | echon %d | echohl None | echon ' of ']],
            nr))
        cmd(string.format([[echohl Identifier | echon %d | echohl None | echon ') ']], last_nr))
        cmd(string.format([[echon '[' | echohl Type | echon %d | echohl None | echon '] ']], size))
        cmd(string.format([[echohl Title | echon ' >> ' . %q | echohl None]], title))
    end, 100)
end

return M
