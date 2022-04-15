---@class BqfLayout
local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local qfs = require('bqf.qfwin.session')
local wpos = require('bqf.wpos')
local config = require('bqf.config')

local autoResizeHeight
local POS

local function fixDefaultQf(qwinid, pwinid, qfType, qfPos)
    local qfWin = fn.win_id2win(qwinid)
    if qfType == 'qf' and fn.winnr('$') == qfWin then
        if qfPos[1] == POS.UNKNOWN and qfPos[2] == POS.UNKNOWN then
            local aboveWinid = fn.win_getid(fn.winnr('k'))
            local heifixTbl = {}
            for _, winid in ipairs(wpos.findBottomWins()) do
                if winid ~= qwinid then
                    heifixTbl[winid] = vim.wo[winid].winfixheight
                    vim.wo[winid].winfixheight = true
                end
            end
            local aboveHeight = api.nvim_win_get_height(aboveWinid)
            cmd('winc J')
            for winid, value in pairs(heifixTbl) do
                vim.wo[winid].winfixheight = value
            end
            api.nvim_win_set_height(aboveWinid, aboveHeight)
            qfPos = wpos.getPos(qwinid, pwinid)
        end
    end
    return qfPos
end

local function adjustWidth(qwinid, pwinid, qfPos)
    local qfWidth = api.nvim_win_get_width(qwinid)
    if vim.o.winwidth > qfWidth then
        if qfPos[1] == POS.RIGHT then
            local width = api.nvim_win_get_width(pwinid) - (vim.o.winwidth - qfWidth)
            api.nvim_win_set_width(pwinid, width)
        else
            api.nvim_win_set_width(qwinid, vim.o.winwidth)
        end
    end
end

local function adjustHeight(qwinid, pwinid, qfPos)
    local qlist = qfs:get(qwinid):list()
    local size = math.max(qlist:getQfList({size = 0}).size, 1)
    local qfHeight = api.nvim_win_get_height(qwinid)
    local incHeight = 0
    local ok, initHeight = pcall(api.nvim_win_get_var, qwinid, 'initHeight')
    if not ok then
        initHeight = qfHeight
        api.nvim_win_set_var(qwinid, 'initHeight', initHeight)
    end
    if qfHeight < initHeight then
        incHeight = initHeight - qfHeight
        qfHeight = initHeight
    end

    if size < qfHeight then
        incHeight = incHeight + size - qfHeight
    end

    if incHeight == 0 then
        return
    end

    local relPos, absPos = unpack(qfPos)
    if relPos == POS.ABOVE or absPos == POS.TOP or absPos == POS.BOTTOM then
        api.nvim_win_set_height(qwinid, api.nvim_win_get_height(qwinid) + incHeight)
    elseif relPos == POS.BELOW then
        vim.wo[qwinid].winfixheight = false
        api.nvim_win_set_height(pwinid, api.nvim_win_get_height(pwinid) - incHeight)
        vim.wo[qwinid].winfixheight = true
    end
end

---
---@param qwinid number
---@return fun()
function M.initialize(qwinid)
    local qs = qfs:get(qwinid)
    local qlist = qs:list()
    local pwinid = qs:previousWinid()
    local qfPos = wpos.getPos(qwinid, pwinid)
    qfPos = fixDefaultQf(qwinid, pwinid, qlist.type, qfPos)
    adjustWidth(qwinid, pwinid, qfPos)
    return autoResizeHeight and function()
        adjustHeight(qwinid, pwinid, qfPos)
    end or nil
end

---
---@return boolean
function M.validQfWin()
    local winH, winJ, winK, winL = fn.winnr('h'), fn.winnr('j'), fn.winnr('k'), fn.winnr('l')
    return not (winH == winJ and winH == winK and winH == winL and
        winJ == winK and winJ == winL and winK == winL)
end

local function init()
    autoResizeHeight = config.auto_resize_height
    POS = wpos.POS
end

init()

return M
