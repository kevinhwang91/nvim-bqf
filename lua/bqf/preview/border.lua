local api = vim.api
local fn = vim.fn

local utils = require('bqf.utils')

local FloatWin = require('bqf.preview.floatwin')

--- Singleton
---@class BqfPreviewBorder : BqfPreviewFloatWin
---@field floatwin BqfPreviewFloatWin
---@field chars string[]
---@field winid number
---@field bufnr number
local Border = setmetatable({}, {__index = FloatWin})

function Border:build(o)
    o = o or {}
    self.__index = self
    self.floatwin = FloatWin
    self.chars = o.chars
    self.winid = 0
    self.bufnr = 0
    return self
end

function Border:update(pbufnr, idx, size)
    local posStr = ('[%d/%d]'):format(idx, size)
    local bufStr = ('buf %d:'):format(pbufnr)
    local modified = vim.bo[pbufnr].modified and '[+] ' or ''
    local name = fn.bufname(pbufnr):gsub('^' .. vim.env.HOME, '~')
    local width = api.nvim_win_get_width(self.winid)
    local padFit = width - 10 - fn.strwidth(bufStr) - fn.strwidth(posStr)
    if padFit - fn.strwidth(name) < 0 then
        name = fn.pathshorten(name)
        if padFit - fn.strwidth(name) < 0 then
            name = ''
        end
    end
    local title = (' %s %s %s %s'):format(posStr, bufStr, name, modified)
    self:updateTitle(title)
    self:updateScrollBar()
end

function Border:updateBuf(opts)
    local width, height = opts.width, opts.height
    local top = self.chars[5] .. self.chars[3]:rep(width - 2) .. self.chars[6]
    local mid = self.chars[1] .. (' '):rep(width - 2) .. self.chars[2]
    local bot = self.chars[7] .. self.chars[4]:rep(width - 2) .. self.chars[8]
    local lines = {top}
    for _ = 1, height - 2 do
        table.insert(lines, mid)
    end
    table.insert(lines, bot)
    if not utils.isBufLoaded(self.bufnr) then
        local bufnr = fn.bufnr('^BqfPreviewBorder$')
        if bufnr > 0 then
            self.bufnr = bufnr
        else
            self.bufnr = api.nvim_create_buf(false, true)
            api.nvim_buf_set_name(self.bufnr, 'BqfPreviewBorder')
        end
        -- run nvim with `-M` will reset modifiable's default value to false
        vim.bo[self.bufnr].modifiable = true
        vim.bo[self.bufnr].bufhidden = 'hide'
    end
    api.nvim_buf_set_lines(self.bufnr, 0, -1, false, lines)
end

function Border:updateScrollBar()
    local buf = api.nvim_win_get_buf(self.floatwin.winid)
    local lineCount = api.nvim_buf_line_count(buf)

    local winfo = utils.getWinInfo(self.floatwin.winid)
    local topline, height = winfo.topline, winfo.height

    local barSize = math.min(height, math.ceil(height * height / lineCount))

    local barPos = math.ceil(height * topline / lineCount)
    if barPos + barSize > height then
        barPos = height - barSize + 1
    end

    local lines = api.nvim_buf_get_lines(self.bufnr, 1, -2, true)
    for i = 1, #lines do
        local barChar
        if i >= barPos and i < barPos + barSize then
            barChar = self.chars[#self.chars]
        else
            barChar = self.chars[2]
        end
        local line = lines[i]
        lines[i] = fn.strcharpart(line, 0, fn.strwidth(line) - 1) .. barChar
    end
    api.nvim_buf_set_lines(self.bufnr, 1, -2, false, lines)
end

function Border:updateTitle(title)
    local top = api.nvim_buf_get_lines(self.bufnr, 0, 1, 0)[1]
    local prefix = fn.strcharpart(top, 0, 3)
    local suffix = fn.strcharpart(top, fn.strwidth(title) + 3, fn.strwidth(top))
    title = ('%s%s%s'):format(prefix, title, suffix)
    api.nvim_buf_set_lines(self.bufnr, 0, 1, true, {title})
end

function Border:calculateWinOpts()
    local wopts = self._wopts or self.floatwin:calculateWinOpts()
    if vim.tbl_isempty(wopts) then
        return {}
    else
        local anchor, zindex, width, height, col, row = wopts.anchor, wopts.zindex, wopts.width,
                                                        wopts.height, wopts.col, wopts.row
        return vim.tbl_extend('force', wopts, {
            focusable = false,
            anchor = anchor,
            style = 'minimal',
            width = width + 2,
            height = height + 2,
            col = anchor:match('W') and col - 1 or col + 1,
            row = anchor:match('N') and row - 1 or row + 1,
            zindex = zindex - 1
        })
    end
end

function Border:display()
    local wopts = self:calculateWinOpts()

    if vim.tbl_isempty(wopts) then
        return
    end

    if self:validate() then
        self:updateBuf(wopts)
        wopts.noautocmd = nil
        api.nvim_win_set_config(self.winid, wopts)
    else
        self:updateBuf(wopts)
        Border:open(self.bufnr, wopts)
        vim.wo[self.winid].winhl = 'Normal:BqfPreviewBorder'
    end
end

return Border
