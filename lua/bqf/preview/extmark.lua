---@class BqfPreviewExtmark
local M = {}

local api = vim.api

local bqfNameSpace

---
---@param fbufnr number
function M.clearHighlight(fbufnr)
    if bqfNameSpace then
        api.nvim_buf_clear_namespace(fbufnr, bqfNameSpace, 0, -1)
    end
end

---
---@param bufnr number
---@param fbufnr number
---@param topline number
---@param botline number
function M.updateHighlight(bufnr, fbufnr, topline, botline)
    M.clearHighlight(fbufnr)
    for _, ns in pairs(api.nvim_get_namespaces()) do
        local extmarks = api.nvim_buf_get_extmarks(bufnr, ns, {topline - 1, 0}, {botline - 1, -1},
                                                   {details = true})
        for _, m in ipairs(extmarks) do
            local _, row, col, details = unpack(m)
            local endRow, endCol = details.end_row, details.end_col
            local hlGroup = details.hl_group
            local priority = details.priority
            api.nvim_buf_set_extmark(fbufnr, bqfNameSpace, row, col, {
                end_row = endRow,
                end_col = endCol,
                hl_group = hlGroup,
                priority = priority
            })
        end
    end
end

local function init()
    bqfNameSpace = api.nvim_create_namespace('bqf-preview-extmark')
end

init()

return M
