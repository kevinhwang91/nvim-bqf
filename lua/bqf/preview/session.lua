local api = vim.api
local cmd = vim.cmd

---@type BqfPreviewTitle
local title
local scrollbar = require('bqf.preview.scrollbar')
local floatwin = require('bqf.preview.floatwin')
local extmark = require('bqf.preview.extmark')
local utils = require('bqf.utils')
local debounce = require('bqf.lib.debounce')
local throttle = require('bqf.lib.throttle')

---
---@class BqfPreviewSession
---@field private pool table<number, BqfPreviewSession>
---@field ns number
---@field winid number
---@field bufnr number
---@field syntax boolean
---@field full boolean
---@field focusable boolean
---@field labelId? number
---@field enableTitle boolean
---@field enableScrollBar boolean
---@field highlightDebounced BqfDebounce
---@field scrollThrottled BqfThrottle
local PreviewSession = {pool = {}}
PreviewSession.__index = PreviewSession

---
---@param winid number
---@param focusable boolean
---@return BqfPreviewSession
function PreviewSession:new(winid, focusable)
    local o = self == PreviewSession and setmetatable({}, self) or self
    o.winid = winid
    o.bufnr = nil
    o.syntax = nil
    o.full = false
    o.focusable = focusable or false
    self:clean()
    self.pool[winid] = o
    return o
end

---
---@param winid? number
---@return BqfPreviewSession
function PreviewSession:get(winid)
    winid = winid or api.nvim_get_current_win()
    return self.pool[winid]
end

function PreviewSession.clean()
    for winid in pairs(PreviewSession.pool) do
        if not utils.isWinValid(winid) then
            PreviewSession.pool[winid] = nil
        end
    end
end

function PreviewSession:floatBufReset()
    local fwinid = floatwin.winid
    local fbufnr = floatwin:getBufnr()
    local tbufnr = scrollbar:getBufnr()

    -- 1. make ml_flags empty
    -- 2. treesitter can't clean parser cache until to unload buffer
    -- https://github.com/neovim/neovim/pull/14995
    cmd(('noa call nvim_win_set_buf(%d, %d)'):format(fwinid, tbufnr))
    cmd(('noa bun %d'):format(fbufnr))
    cmd(('noa call nvim_win_set_buf(%d, %d)'):format(fwinid, fbufnr))
    extmark.clearHighlight(fbufnr, self.ns)
end

function PreviewSession:floatWinExec(func)
    if self:validate() then
        utils.winCall(floatwin.winid, func)
    end
end

function PreviewSession:floatBufnr()
    return floatwin.bufnr
end

function PreviewSession:floatWinid()
    return floatwin.winid
end

function PreviewSession:close()
    floatwin:close()
    if title and self.enableTitle then
        title:close()
    end
    scrollbar:close()
end

function PreviewSession:validate()
    local res = floatwin:validate()
    if res and self.enableScrollBar and floatwin.showScrollBar then
        res = res and scrollbar:validate()
    end
    return res
end

function PreviewSession:scroll(loaded)
    floatwin:refreshTopline()
    if self.enableScrollBar then
        scrollbar:update()
    end
    self:mapBufHighlight(loaded)
end

function PreviewSession:showCountLabel(text, hlGroup)
    local lnum = api.nvim_win_get_cursor(self:floatWinid())[1]
    self.labelId = extmark.setVirtText(self:floatBufnr(), self.ns, lnum - 1, -1, {{text, hlGroup}}, {id = self.labelId})
end

function PreviewSession:mapBufHighlight(loaded)
    if not self.bufnr then
        return
    end
    if loaded == nil then
        loaded = utils.isBufLoaded(self.bufnr)
    end
    if loaded then
        local topline, botline = floatwin:visibleRegion()
        extmark.mapBufHighlight(self.bufnr, self:floatBufnr(), self.ns, topline, botline)
    end
end

function PreviewSession:transferBuf(srcBufnr)
    floatwin:transferBuf(srcBufnr)
    self.bufnr = srcBufnr
end

function PreviewSession:display(pwinid, pbufnr, idx, size, handler)
    if not self:validate() then
        if self.focusable then
            local ctrlW = false
            vim.on_key(function(char)
                local fwinid = self:floatWinid()
                if not utils.isWinValid(fwinid) then
                    vim.on_key(nil, self.ns)
                    return
                end
                local b1, b2, b3 = char:byte(1, -1)
                -- 0x17 <C-w>
                -- 0x77 w
                -- 0x80, 0xfd, 0x4b <ScrollWheelUp>
                -- 0x80, 0xfd, 0x4c <ScrollWheelDown>
                if ctrlW and b1 == 0x77 then
                    vim.schedule(function()
                        api.nvim_set_current_win(pwinid)
                    end)
                end
                if b1 == 0x80 and b2 == 0xfd then
                    if b3 == 0x4b or b3 == 0x4c then
                        self.highlightDebounced()
                        self.scrollThrottled()
                    end
                else
                    ctrlW = b1 == 0x17
                end
            end, self.ns)
        end
    end
    local titleOpts
    if self.enableTitle then
        titleOpts = {
            bufnr = pbufnr,
            idx = idx,
            size = size
        }
    end
    local hasShowedScrollBar = floatwin.showScrollBar
    local res = floatwin:display(self.winid, pwinid, self.focusable, self.full, handler, titleOpts)
    if res then
        if self.enableTitle and self:missingTitle() then
            local text = floatwin:generateTitle(pbufnr, idx, size)
            title:display(text)
        end
        if self.enableScrollBar then
            scrollbar:display()
            -- TODO
            -- upstream bug, can't render terminal correctly if create preview component
            -- like scrollbar, clear screen manually.
            if hasShowedScrollBar == false and floatwin.showScrollBar == true and utils.has10() and
                api.nvim_get_mode().mode == 't' then
                -- ^L = 0x0c
                api.nvim_feedkeys(('%c'):format(0x0c), 'it', false)
            end
        end
    end
end

function PreviewSession:missingTitle()
    return title and not floatwin.getConfig().title
end

function PreviewSession:initialize(o)
    self.ns = api.nvim_create_namespace('bqf-preview')
    floatwin:initialize(self.ns, o.border, o.wrap, o.winHeight, o.winVHeight, o.winblend)
    self.enableTitle = o.showTitle
    self.enableScrollBar = o.showScrollBar
    if self.enableScrollBar then
        title = require('bqf.preview.title')
        title:initialize()
    end
    scrollbar:initialize()
    self.scrollThrottled = self.enableScrollBar and throttle(function()
        if self:validate() then
            floatwin:refreshTopline()
            scrollbar:update()
        end
    end, 80) or function()
    end
    self.highlightDebounced = debounce(function()
        self:mapBufHighlight()
    end, 50)
end

return PreviewSession
