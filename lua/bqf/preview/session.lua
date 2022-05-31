local api = vim.api
local cmd = vim.cmd

local floatwin = require('bqf.preview.floatwin')
local border = require('bqf.preview.border')
local extmark = require('bqf.preview.extmark')
local utils = require('bqf.utils')

local namespace
local onKey
local highlightDebounced
local scrollThrottled

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
---@field focusable boolean
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
    obj.focusable = o.focusable or false
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
    extmark.clearHighlight(fbufnr)
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

function PreviewSession.scroll(srcBufnr, loaded)
    border:updateScrollBar()
    PreviewSession.mapBufHighlight(srcBufnr, loaded)
end

function PreviewSession.mapBufHighlight(srcBufnr, loaded)
    if not srcBufnr then
        return
    end
    if loaded == nil then
        loaded = utils.isBufLoaded(srcBufnr)
    end
    if loaded then
        local topline, botline = floatwin:visibleRegion()
        extmark.mapBufHighlight(srcBufnr, PreviewSession.floatBufnr(), topline, botline)
    end
end

function PreviewSession.display()
    floatwin:display()
    border:display()
end

function PreviewSession:validOrBuild(owinid)
    local isValid = self.validate()
    if not isValid then
        floatwin:build({
            qwinid = self.winid,
            pwinid = owinid,
            wrap = self.wrap,
            focusable = self.focusable
        })
        if self.focusable then
            local ctrlW = false
            onKey(function(char)
                local fwinid = self.floatWinid()
                if not utils.isWinValid(fwinid) then
                    onKey(nil, namespace)
                    return
                end
                local b1, b2, b3 = char:byte(1, -1)
                -- 0x17 <C-w>
                -- 0x77 w
                -- 0x80, 0xfd, 0x4b <ScrollWheelUp>
                -- 0x80, 0xfd, 0x4c <ScrollWheelDown>
                if ctrlW and b1 == 0x77 then
                    vim.schedule(function()
                        api.nvim_set_current_win(owinid)
                    end)
                end
                if b1 == 0x80 and b2 == 0xfd then
                    if b3 == 0x4b or b3 == 0x4c then
                        highlightDebounced()
                        scrollThrottled()
                    end
                else
                    ctrlW = b1 == 0x17
                end
            end, namespace)
        end
    end
    if not isValid then
        border:build({chars = self.borderChars})
    end
    if self.full then
        floatwin:setHeight(999, 999)
    else
        floatwin:setHeight(self.winHeight, self.winVHeight)
    end
    return isValid
end

local function init()
    namespace = api.nvim_create_namespace('bqf-preview')
    onKey = vim.on_key and vim.on_key or vim.register_keystroke_callback
    highlightDebounced = require('bqf.debounce')(function()
        PreviewSession.mapBufHighlight((PreviewSession.get() or {}).bufnr)
    end, 50)
    scrollThrottled = require('bqf.throttle')(function()
        border:updateScrollBar()
    end, 80)
end

init()

return PreviewSession
