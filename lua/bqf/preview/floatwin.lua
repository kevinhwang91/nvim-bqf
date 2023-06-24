local api = vim.api
local fn = vim.fn

local utils = require('bqf.utils')

--- Singleton
---@class BqfPreviewFloatWin
---@field ns number
---@field qwinid number
---@field pwinid number
---@field winid number
---@field bufnr number
---@field bufferName string
---@field winConfig table
---@field winblend number
---@field width number
---@field height number
---@field vHeight number
---@field defualtWinHeight number
---@field defualtVHeight number
---@field wrap boolean
---@field showTitle boolean
---@field showScrollBar boolean
---@field topline number
---@field hasTitle boolean
---@field border string|'none'|'single'|'double'|'rounded'|'solid'|'shadow'|string[]
---@field rawBorder string[]
local FloatWin = {wpos = require('bqf.wpos')}

local defaultBorder = {
    none    = {'', '', '', '', '', '', '', ''},
    single  = {'┌', '─', '┐', '│', '┘', '─', '└', '│'},
    double  = {'╔', '═', '╗', '║', '╝', '═', '╚', '║'},
    rounded = {'╭', '─', '╮', '│', '╯', '─', '╰', '│'},
    solid   = {' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '},
    shadow  = {'', '', {' ', 'FloatShadowThrough'}, {' ', 'FloatShadow'},
        {' ', 'FloatShadow'}, {' ', 'FloatShadow'}, {' ', 'FloatShadowThrough'}, ''},
}

local function borderHasLine(border, index)
    local s = border[index]
    if type(s) == 'string' then
        return s ~= ''
    else
        return s[1] ~= ''
    end
end

function FloatWin:borderHasUpLine()
    return borderHasLine(self.border, 2)
end

function FloatWin:borderHasRightLine()
    return borderHasLine(self.border, 4)
end

function FloatWin:borderHasBottomLine()
    return borderHasLine(self.border, 6)
end

function FloatWin:borderHasLeftLine()
    return borderHasLine(self.border, 8)
end

function FloatWin:build(hHeight, vHeight)
    self.height, self.width = 0, 0
    self.border = vim.deepcopy(self.rawBorder)
    local POS = self.wpos.POS
    local relPos, absPos = unpack(self.wpos.getPos(self.qwinid, self.pwinid))

    local qinfo = utils.getWinInfo(self.qwinid)
    local width, height, col, row, anchor
    if relPos == POS.ABOVE or relPos == POS.BELOW or absPos == POS.TOP or absPos == POS.BOTTOM then
        local rowPos = qinfo.winrow
        width = qinfo.width
        col = 1
        if relPos == POS.ABOVE or absPos == POS.TOP then
            anchor = 'NW'
            height = math.min(hHeight, vim.o.lines - 2 - vim.o.cmdheight - rowPos - qinfo.height)
            row = qinfo.height + 1
        else
            anchor = 'SW'
            local minHeight = rowPos - 2
            if self:borderHasUpLine() then
                minHeight = minHeight - 1
            end
            if self:borderHasBottomLine() then
                minHeight = minHeight - 1
            end
            height = math.min(hHeight, minHeight)
            row = -1 - (utils.hasWinBar(self.qwinid) and 1 or 0)
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
        height = math.min(vHeight, qinfo.height - 2)
        local winline = utils.winCall(self.qwinid, fn.winline)
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
    self.height = height
    self.width = width
    return {
        relative = 'win',
        win = self.qwinid,
        focusable = self.focusable,
        border = self.border,
        anchor = anchor,
        width = self.width,
        height = self.height,
        col = col,
        row = row,
        noautocmd = true,
        zindex = 52
    }
end

function FloatWin:validate()
    return utils.isWinValid(rawget(self, 'winid'))
end

function FloatWin.getConfig()
    return FloatWin.winConfig
end

function FloatWin:open(wopts)
    self.winid = api.nvim_open_win(self:getBufnr(), false, wopts)
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

function FloatWin:getBufnr()
    if utils.isBufLoaded(rawget(self, 'bufnr')) then
        return self.bufnr
    end
    local bufnr = fn.bufnr('^' .. self.bufferName .. '$')
    if bufnr > 0 then
        self.bufnr = bufnr
    else
        self.bufnr = api.nvim_create_buf(false, true)
        api.nvim_buf_set_name(self.bufnr, self.bufferName)
        vim.bo[self.bufnr].bufhidden = 'hide'
    end
    return self.bufnr
end

function FloatWin:transferBuf(srcBufnr)
    local bufnr = self:getBufnr()
    utils.transferBuf(srcBufnr, bufnr)
    self.lineCount = api.nvim_buf_line_count(bufnr)
    self.showScrollBar = self.lineCount > self.height
    self:refreshTopline()
end

function FloatWin:generateTitle(srcBufnr, idx, size)
    local posStr = ('[%d/%d]'):format(idx, size)
    local bufStr = ('buf %d:'):format(srcBufnr)
    local modified = vim.bo[srcBufnr].modified and '[+] ' or ''
    local name = fn.bufname(srcBufnr):gsub('^' .. vim.env.HOME, '~')
    local width = self.width
    local limit = width - fn.strwidth(bufStr) - fn.strwidth(posStr)
    if limit - fn.strwidth(name) < 15 then
        name = fn.pathshorten(name)
        if limit - fn.strwidth(name) < 15 then
            name = ''
        end
    end
    return (' %s %s %s %s'):format(posStr, bufStr, name, modified)
end

function FloatWin:display(qwinid, pwinid, focusable, full, postHandle, titleOpts)
    self.qwinid = qwinid
    self.pwinid = pwinid
    self.focusable = focusable or false
    local wopts = self:build(full and 999 or self.defaultHeight, full and 999 or self.defualtVHeight)
    if vim.tbl_isempty(wopts) then
        return
    end

    local title
    if self.hasTitle and titleOpts then
        title = self:generateTitle(titleOpts.bufnr, titleOpts.idx, titleOpts.size)
        wopts.title = {{self.border[2], 'BqfPreviewBorder'}, {title, 'BqfPreviewTitle'}}
    end

    if self:validate() then
        wopts.noautocmd = nil
        api.nvim_win_set_config(self.winid, wopts)
    else
        self:open(wopts)
        local wo = vim.wo[self.winid]
        wo.wrap = self.wrap
        wo.spell, wo.list = false, false
        wo.nu, wo.rnu = true, false
        wo.fen, wo.fdm, wo.fdc = false, 'manual', '0'
        wo.cursorline = true
        wo.signcolumn, wo.colorcolumn = 'no', ''
        wo.winhl = 'Normal:BqfPreviewFloat,CursorLine:BqfPreviewCursorLine,' ..
            'FloatBorder:BqfPreviewBorder,FloatTitle:BqfPreviewTitle'
        wo.winblend = self.winblend
    end
    self.winConfig = wopts
    if type(postHandle) == 'function' then
        postHandle()
    end
    return self.winid
end

function FloatWin:refreshTopline()
    self.topline = fn.line('w0', self.winid)
end

function FloatWin:initialize(ns, border, wrap, winHeight, winVHeight, winblend)
    self.ns = ns
    local tBorder = type(border)
    if tBorder == 'string' then
        if not defaultBorder[border] then
            error(([[border string must be one of {%s}]])
                :format(table.concat(vim.tbl_keys(defaultBorder), ',')))
        end
    elseif tBorder == 'table' then
        assert(#border == 8, 'only support 8 chars for the border')
    else
        error('error border config')
    end
    self.bufferName = 'BqfPreviewFloatWin'
    self.rawBorder = type(border) == 'string' and defaultBorder[border] or border
    self.wrap = wrap
    self.winblend = vim.o.termguicolors and winblend or 0
    self.defaultHeight = winHeight
    self.defaultWinVHeight = winVHeight
    self.hasTitle = utils.has09()
end

return FloatWin
