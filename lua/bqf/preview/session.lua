local api = vim.api
local cmd = vim.cmd

local floatwin = require('bqf.preview.floatwin')
local border = require('bqf.preview.border')
local utils = require('bqf.utils')

---
---@class BqfPreviewSession
---@field private pool table<number, BqfPreviewSession>
---@field winid number
---@field win_height number
---@field win_vheight number
---@field wrap boolean
---@field border_chars string[]
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
    obj.win_height = o.win_height
    obj.win_vheight = o.win_vheight
    obj.wrap = o.wrap
    obj.border_chars = o.border_chars
    obj.bufnr = nil
    obj.syntax = nil
    obj.full = false
    self:clean()
    self.pool[winid] = obj
    return obj
end

---
---@param winid number
---@return BqfPreviewSession
function PreviewSession.get(winid)
    winid = winid or api.nvim_get_current_win()
    return PreviewSession.pool[winid]
end

function PreviewSession.clean()
    for winid in pairs(PreviewSession.pool) do
        if not utils.is_win_valid(winid) then
            PreviewSession.pool[winid] = nil
        end
    end
end

function PreviewSession.floatbuf_reset()
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

function PreviewSession.floatwin_exec(func)
    if PreviewSession.validate() then
        utils.win_execute(floatwin.winid, func)
    end
end

function PreviewSession.float_bufnr()
    return floatwin.bufnr
end

function PreviewSession.border_bufnr()
    return border.bufnr
end

function PreviewSession.float_winid()
    return floatwin.winid
end

function PreviewSession.border_winid()
    return border.winid
end

function PreviewSession.close()
    floatwin:close()
    border:close()
end

function PreviewSession.validate()
    return floatwin:validate() and border:validate()
end

function PreviewSession.update_border(pbufnr, qidx, size)
    border:update(pbufnr, qidx, size)
end

function PreviewSession.update_scrollbar()
    border:update_scrollbar()
end

function PreviewSession.display()
    floatwin:display()
    border:display()
end

function PreviewSession:valid_or_build(owinid)
    if not floatwin:validate() then
        floatwin:build({qwinid = self.winid, pwinid = owinid, wrap = self.wrap})
    end
    if not border:validate() then
        border:build({chars = self.border_chars})
    end
    if self.full then
        floatwin.win_height, floatwin.win_vheight = 999, 999
    else
        floatwin.win_height, floatwin.win_vheight = self.win_height, self.win_vheight
    end
end

return PreviewSession
