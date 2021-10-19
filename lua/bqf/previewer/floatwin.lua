-- singleton
local api = vim.api
local fn = vim.fn

local utils = require('bqf.utils')

local FloatWin = {}

function FloatWin:build(o)
    o = o or {}
    self.__index = self
    self.qwinid = o.qwinid
    self.pwinid = o.pwinid
    self.win_height = o.win_height
    self.win_vheight = o.win_vheight
    self.wrap = o.wrap
    self.wpos = require('bqf.wpos')
    self.winid = nil
    self.bufnr = nil
    return self
end

function FloatWin:cal_wopts()
    local POS = self.wpos.POS
    local rel_pos, abs_pos = unpack(self.wpos.get_pos(self.qwinid, self.pwinid))

    local qinfo = fn.getwininfo(self.qwinid)[1]
    local width, height, col, row, anchor
    if rel_pos == POS.ABOVE or rel_pos == POS.BELOW or abs_pos == POS.TOP or abs_pos == POS.BOTTOM then
        local row_pos = qinfo.winrow
        width = qinfo.width - 2
        col = 1
        if rel_pos == POS.ABOVE or abs_pos == POS.TOP then
            anchor = 'NW'
            height = math.min(self.win_height, vim.o.lines - 4 - row_pos - qinfo.height)
            row = qinfo.height + 2
        else
            anchor = 'SW'
            height = math.min(self.win_height, row_pos - 4)
            row = -2
        end
    elseif rel_pos == POS.LEFT or rel_pos == POS.RIGHT or abs_pos == POS.LEFT_FAR or abs_pos ==
        POS.RIGHT_FAR then
        if abs_pos == POS.LEFT_FAR then
            width = vim.o.columns - fn.win_screenpos(2)[2] - 1
        elseif abs_pos == POS.RIGHT_FAR then
            width = qinfo.wincol - 4
        else
            width = api.nvim_win_get_width(self.pwinid) - 2
        end
        height = math.min(self.win_vheight, qinfo.height - 2)
        local winline = fn.winline()
        row = height >= winline and 1 or winline - height - 1
        if rel_pos == POS.LEFT or abs_pos == POS.LEFT_FAR then
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
        focusable = false,
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
    return utils.is_win_valid(self.winid)
end

function FloatWin:open(bufnr, wopts)
    self.winid = api.nvim_open_win(bufnr, false, wopts)
    return self.winid
end

function FloatWin:close()
    if self:validate() then
        api.nvim_win_close(self.winid, true)
    end
end

function FloatWin:display()
    local wopts = self:cal_wopts()
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
