local api = vim.api
local fn = vim.fn

local utils = require('bqf.utils')

--- Singleton
---@class BqfPreviewFloatWin
---@field wpos BqfWinPos
---@field qwinid number
---@field pwinid number
---@field winHeight number
---@field winVHeight number
---@field wrap boolean
---@field winid number
---@field bufnr number
---@field private _wopts table
local FloatWin = {wpos = require('bqf.wpos')}

function FloatWin:build(o)
    o = o or {}
    self.__index = self
    self.qwinid = o.qwinid
    self.pwinid = o.pwinid
    self.winHeight = o.winHeight
    self.winVHeight = o.winHheight
    self.wrap = o.wrap
    self.focusable = o.focusable or false
    self.winid = nil
    self.bufnr = nil
    return self
end

function FloatWin:setHeight(winHeight, winVHeight)
    self.winHeight = winHeight
    self.winVHeight = winVHeight
end

function FloatWin:calculateWinOpts()
    local POS = self.wpos.POS
    local relPos, absPos = unpack(self.wpos.getPos(self.qwinid, self.pwinid))

    local qinfo = utils.getWinInfo(self.qwinid)
    local width, height, col, row, anchor
    if relPos == POS.ABOVE or relPos == POS.BELOW or absPos == POS.TOP or absPos == POS.BOTTOM then
        local rowPos = qinfo.winrow
        width = qinfo.width - 2
        col = 1
        if relPos == POS.ABOVE or absPos == POS.TOP then
            anchor = 'NW'
            height = math.min(self.winHeight, vim.o.lines - 4 - rowPos - qinfo.height)
            row = qinfo.height + 2
        else
            anchor = 'SW'
            height = math.min(self.winHeight, rowPos - 4)
            row = -2
        end
    elseif relPos == POS.LEFT or relPos == POS.RIGHT or absPos == POS.LEFT_FAR or absPos ==
        POS.RIGHT_FAR then
        if absPos == POS.LEFT_FAR then
            width = vim.o.columns - fn.win_screenpos(2)[2] - 1
        elseif absPos == POS.RIGHT_FAR then
            width = qinfo.wincol - 4
        else
            width = api.nvim_win_get_width(self.pwinid) - 2
        end
        height = math.min(self.winVHeight, qinfo.height - 2)
        local winline = utils.winExecute(self.qwinid, fn.winline)
        row = height >= winline and 1 or winline - height - 1
        if relPos == POS.LEFT or absPos == POS.LEFT_FAR then
            anchor = 'NW'
            col = qinfo.width + 2
        else
            anchor = 'NE'
            col = -2
        end
    else
        return {}
    end

    if width < 1 or height < 1 then
        return {}
    end

    return {
        relative = 'win',
        win = self.qwinid,
        focusable = self.focusable,
        anchor = anchor,
        width = width,
        height = height,
        col = col,
        row = row,
        noautocmd = true,
        zindex = 52
    }
end

function FloatWin:validate()
    return utils.isWinValid(self.winid)
end

function FloatWin:open(bufnr, wopts)
    self.winid = api.nvim_open_win(bufnr, false, wopts)
    return self.winid
end

function FloatWin:visibleRegion()
    local winfo = utils.getWinInfo(self.winid)
    return winfo.topline, winfo.botline
end

function FloatWin:close()
    if self:validate() then
        api.nvim_win_close(self.winid, true)
    end
end

function FloatWin:display()
    local wopts = self:calculateWinOpts()
    self._wopts = wopts

    if vim.tbl_isempty(wopts) then
        return
    end

    if self:validate() then
        wopts.noautocmd = nil
        api.nvim_win_set_config(self.winid, wopts)
    else
        local bufnr = fn.bufnr('^BqfPreviewFloatWin$')
        if bufnr > 0 then
            self.bufnr = bufnr
        else
            self.bufnr = api.nvim_create_buf(false, true)
            api.nvim_buf_set_name(self.bufnr, 'BqfPreviewFloatWin')
        end
        vim.bo[self.bufnr].bufhidden = 'hide'
        self:open(self.bufnr, wopts)
        local lwo = vim.wo[self.winid]
        lwo.wrap = self.wrap
        lwo.spell, lwo.list = false, false
        lwo.nu, lwo.rnu = true, false
        lwo.fen, lwo.fdm, lwo.fdc = false, 'manual', '0'
        lwo.cursorline = true
        lwo.signcolumn, lwo.colorcolumn = 'no', ''
        lwo.winhl = 'Normal:BqfPreviewFloat'
    end
end

return FloatWin
