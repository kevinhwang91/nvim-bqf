local api = vim.api
local cmd = vim.cmd

local floatwin = require('bqf.preview.floatwin')
local border = require('bqf.preview.border')
local utils = require('bqf.utils')

---
---@class BqfPreviewSession
---@field private pool table<number, BqfPreviewSession>
---@field winid number
---@field winHeight number
---@field winVHeight number
---@field wrap boolean
---@field borderChars string[]
---@field bufnr number
---@field syntax boolean
---@field full boolean
local PreviewSession = {pool = {}}

---
---@param winid number
---@param o table
---@return BqfPreviewSession
function PreviewSession:new(winid, o)
    o = o or {}
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    obj.winid = winid
    obj.winHeight = o.winHeight
    obj.winVHeight = o.winVHeight
    obj.wrap = o.wrap
    obj.borderChars = o.borderChars
    obj.bufnr = nil
    obj.syntax = nil
    obj.full = false
    self:clean()
    self.pool[winid] = obj
    return obj
end

---
---@param winid? number
---@return BqfPreviewSession
function PreviewSession.get(winid)
    winid = winid or api.nvim_get_current_win()
    return PreviewSession.pool[winid]
end

function PreviewSession.clean()
    for winid in pairs(PreviewSession.pool) do
        if not utils.isWinValid(winid) then
            PreviewSession.pool[winid] = nil
        end
    end
end

function PreviewSession.floatBufReset()
    local fwinid = floatwin.winid
    local fbufnr = floatwin.bufnr
    local bbufnr = border.bufnr

    -- 1. make ml_flags empty
    -- 2. treesitter can't clean parser cache until to unload buffer
    -- https://github.com/neovim/neovim/pull/14995
    cmd(('noa call nvim_win_set_buf(%d, %d)'):format(fwinid, bbufnr))
    cmd(('noa bun %d'):format(fbufnr))
    cmd(('noa call nvim_win_set_buf(%d, %d)'):format(fwinid, fbufnr))

end

function PreviewSession.floatWinExec(func)
    if PreviewSession.validate() then
        utils.winExecute(floatwin.winid, func)
    end
end

function PreviewSession.floatBufnr()
    return floatwin.bufnr
end

function PreviewSession.borderBufnr()
    return border.bufnr
end

function PreviewSession.floatWinid()
    return floatwin.winid
end

function PreviewSession.borderWinid()
    return border.winid
end

function PreviewSession.close()
    floatwin:close()
    border:close()
end

function PreviewSession.validate()
    return floatwin:validate() and border:validate()
end

function PreviewSession.updateBorder(pbufnr, qidx, size)
    border:update(pbufnr, qidx, size)
end

function PreviewSession.updateScrollBar()
    border:updateScrollBar()
end

function PreviewSession.visibleRegion()
    return floatwin:visibleRegion()
end

function PreviewSession.display()
    floatwin:display()
    border:display()
end

function PreviewSession:validOrBuild(owinid)
    if not floatwin:validate() then
        floatwin:build({qwinid = self.winid, pwinid = owinid, wrap = self.wrap})
    end
    if not border:validate() then
        border:build({chars = self.borderChars})
    end
    if self.full then
        floatwin:setHeight(999, 999)
    else
        floatwin:setHeight(self.winHeight, self.winVHeight)
    end
end

return PreviewSession
