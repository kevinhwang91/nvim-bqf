local api = vim.api

local FloatWin = require('bqf.preview.floatwin')

--- Singleton
---@class BqfPreviewTitle : BqfPreviewFloatWin
---@field winid number
---@field bufnr number
---@field bufferName string
local Title = setmetatable({}, {__index = FloatWin})

function Title:build()
    local config = FloatWin.getConfig()
    assert(config, 'Need build floating window component first!')
    local row, col, height = config.row, config.col, config.height
    local anchor, zindex = config.anchor, config.zindex
    if anchor == 'SW' then
        row = row - height - (self:borderHasBottomLine() and 2 or 1)
    end
    return vim.tbl_extend('force', config, {
        anchor = 'NW',
        height = 1,
        row = row,
        col = self:borderHasLeftLine() and col + 1 or col,
        style = 'minimal',
        noautocmd = true,
        focusable = false,
        border = 'none',
        zindex = zindex + 1
    })
end

function Title:display(text)
    if not self:borderHasUpLine() then
        return
    end
    local wopts = self:build()
    wopts.width = #text
    if self:validate() then
        wopts.noautocmd = nil
        api.nvim_win_set_config(self.winid, wopts)
    else
        Title:open(wopts)
        local wo = vim.wo[self.winid]
        wo.winhl = 'Normal:BqfPreviewTitle'
        -- wo.winblend = self.winblend
    end
    api.nvim_buf_set_lines(self.bufnr, 0, -1, false, {text})
    return self.winid
end

function Title:initialize()
    self.bufferName = 'BqfPreviewTitle'
    return self
end

return Title
