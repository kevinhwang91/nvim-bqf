---@class BqfQfWinHandler
local M = {}
local api = vim.api
local cmd = vim.cmd
local fn = vim.fn

local qfs = require('bqf.qfwin.session')
local utils = require('bqf.utils')

function M.signReset()
    local qwinid = api.nvim_get_current_win()
    local qs = qfs:get(qwinid)
    local qlist = qs:list()
    local sign = qlist:sign()
    sign:reset()
end

---
---@param rel number
---@param lnum? number
---@param bufnr? number
function M.signToggle(rel, lnum, bufnr)
    lnum = lnum or api.nvim_win_get_cursor(0)[1]
    bufnr = bufnr or api.nvim_get_current_buf()
    local qwinid = api.nvim_get_current_win()
    local qs = qfs:get(qwinid)
    local qlist = qs:list()
    local sign = qlist:sign()
    sign:toggle(lnum, bufnr)
    if rel ~= 0 then
        cmd(('norm! %s'):format(rel > 0 and 'j' or 'k'))
    end
end

---
---@param lnum? number
---@param bufnr? number
function M.signToggleBuf(lnum, bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    lnum = lnum or api.nvim_win_get_cursor(0)[1]
    local qwinid = api.nvim_get_current_win()
    local qs = qfs:get(qwinid)
    local qlist = qs:list()
    local items = qlist:items()
    local entryBufnr = items[lnum].bufnr
    local lnumList = {}
    for l, entry in ipairs(items) do
        if entry.bufnr == entryBufnr then
            table.insert(lnumList, l)
        end
    end
    local sign = qlist:sign()
    sign:toggle(lnumList, bufnr)
end

--- only work under map with <Cmd>
---@param bufnr? number
function M.signVMToggle(bufnr)
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
    local startLnum = api.nvim_buf_get_mark(bufnr, '<')[1]
    local endLnum = api.nvim_buf_get_mark(bufnr, '>')[1]
    local lnumList = {}
    for i = startLnum, endLnum do
        table.insert(lnumList, i)
    end
    local qwinid = api.nvim_get_current_win()
    local qs = qfs:get(qwinid)
    local qlist = qs:list()
    local sign = qlist:sign()
    sign:toggle(lnumList, bufnr)
end

---
---@param bufnr number
function M.signClear(bufnr)
    local qwinid = api.nvim_get_current_win()
    local qs = qfs:get(qwinid)
    local qlist = qs:list()
    local sign = qlist:sign()
    sign:clear(bufnr)
end

function M.restoreWinView()
    local qwinid = api.nvim_get_current_win()
    local qs = qfs:get(qwinid)
    local qlist = qs:list()
    local wv = qlist:getWinView()
    if wv then
        fn.winrestview(wv)
    end
end

---
---@param next boolean
function M.navHistory(next)
    local qwinid = api.nvim_get_current_win()
    local qs = qfs:get(qwinid)
    local qlist = qs:list()
    qlist:setWinView(fn.winsaveview())

    local prefix = qlist.type == 'loc' and 'l' or 'c'
    local curNr, lastNr = qlist:getQfList({nr = 0}).nr, qlist:getQfList({nr = '$'}).nr
    if lastNr <= 1 then
        return
    end

    local count = vim.v.count1
    local histNum = (curNr - 1 + (next and count or lastNr - count)) % lastNr + 1

    cmd(([[sil exe '%d%shi']]):format(histNum, prefix))
    cmd([[norm! m']])
    M.restoreWinView()

    local qinfo = qlist:getQfList({nr = 0, size = 0, title = 0})
    local nr, size, title = qinfo.nr, qinfo.size, qinfo.title

    api.nvim_echo({
        {'('}, {tostring(nr), 'Identifier'}, {' of '}, {tostring(lastNr), 'Identifier'}, {') ['},
        {tostring(size), 'Type'}, {'] '}, {' >> ' .. title, 'Title'}
    }, false, {})
end

---
---@param next boolean
function M.navFile(next)
    local lnum, col = unpack(api.nvim_win_get_cursor(0))
    local qwinid = api.nvim_get_current_win()
    local qs = qfs:get(qwinid)
    local qlist = qs:list()
    local items, size = qlist:items(), qlist:getQfList({size = 0}).size
    local curBufnr = items[lnum].bufnr
    local start, stop, step = unpack(next and {lnum + 1, size, 1} or {lnum - 1, 1, -1})

    for i = start, stop, step do
        if items[i].valid == 1 and items[i].bufnr ~= curBufnr then
            qlist:changeIdx(i)
            api.nvim_win_set_cursor(0, {i, col})
            return
        end
    end
    api.nvim_echo({{'No more items', 'WarningMsg'}}, true, {})
end

local function validateSize(qlist)
    local valid = qlist:getQfList({size = 0}).size > 0
    if not valid then
        api.nvim_err_writeln('E42: No Errors')
    end
    return valid
end

local function doEdit(qwinid, idx, close, action)
    qwinid = qwinid or api.nvim_get_current_win()
    local qs = qfs:get(qwinid)
    local pwinid = qs:previousWinid()
    assert(utils.isWinValid(pwinid), 'file window is invalid')

    local qlist = qs:list()
    if not validateSize(qlist) then
        return false
    end

    idx = idx or api.nvim_win_get_cursor(qwinid)[1]
    qlist:changeIdx(idx)
    local entry = qlist:item(idx)
    local bufnr, lnum, col = entry.bufnr, entry.lnum, entry.col
    if bufnr == 0 then
        api.nvim_err_writeln('Buffer not found')
        return
    end

    if close then
        api.nvim_win_close(qwinid, true)
    end

    api.nvim_set_current_win(pwinid)

    local lastBufnr = api.nvim_get_current_buf()
    local lastBufname = api.nvim_buf_get_name(lastBufnr)
    local lastBufoff = api.nvim_buf_get_offset(0, 1)
    if action and not utils.isUnNameBuf(lastBufnr, lastBufname, lastBufoff) then
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

    if utils.isUnNameBuf(lastBufnr, lastBufname, lastBufoff) then
        api.nvim_buf_delete(lastBufnr, {})
    end
    return true
end

---
---@param close boolean
---@param jumpCmd boolean
---@param qwinid number
---@param idx number
function M.open(close, jumpCmd, qwinid, idx)
    doEdit(qwinid, idx, close, function(bufnr)
        if jumpCmd then
            local fname = fn.fnameescape(api.nvim_buf_get_name(bufnr))
            if jumpCmd == 'drop' then
                local bufInfo = fn.getbufinfo(bufnr)
                if fname == '' or #bufInfo == 1 and #bufInfo[1].windows == 0 then
                    api.nvim_set_current_buf(bufnr)
                    return
                end
            end
            cmd(('%s %s'):format(jumpCmd, fname))
        else
            api.nvim_set_current_buf(bufnr)
        end
    end)
end

---
---@param stay boolean
---@param qwinid? number
---@param idx number
function M.tabedit(stay, qwinid, idx)
    local lastTabPage = api.nvim_get_current_tabpage()
    qwinid = qwinid or api.nvim_get_current_win()
    local unnameBuf = true
    if doEdit(qwinid, idx, false, function(bufnr)
        unnameBuf = false
        local fname = fn.fnameescape(api.nvim_buf_get_name(bufnr))
        cmd(('tabedit %s'):format(fname))
    end) then
        local curTabPage = api.nvim_get_current_tabpage()
        if not unnameBuf then
            api.nvim_set_current_win(qwinid)
        end

        if lastTabPage ~= curTabPage and not stay then
            api.nvim_set_current_tabpage(curTabPage)
        end
    end
end

return M
