---@class BqfPreviewExtmark
local M = {}

local api = vim.api

local namespace

---
---@param bufnr number
function M.clearHighlight(bufnr)
    if namespace then
        api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
    end
end

---
---@param srcBufnr number
---@param dstBufnr number
---@param topline number
---@param botline number
function M.mapBufHighlight(srcBufnr, dstBufnr, topline, botline)
    M.clearHighlight(dstBufnr)
    for _, ns in pairs(api.nvim_get_namespaces()) do
        local extmarks = api.nvim_buf_get_extmarks(srcBufnr, ns, {topline - 1, 0}, {botline - 1, -1},
                                                   {details = true})
        for _, m in ipairs(extmarks) do
            local _, row, col, details = unpack(m)
            local endRow, endCol = details.end_row, details.end_col
            local hlGroup = details.hl_group
            local priority = details.priority
            api.nvim_buf_set_extmark(dstBufnr, namespace, row, col, {
                end_row = endRow,
                end_col = endCol,
                hl_group = hlGroup,
                priority = priority
            })
        end
    end
end

local function init()
    namespace = api.nvim_create_namespace('bqf-preview')
end

init()

return M
