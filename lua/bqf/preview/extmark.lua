---@class BqfPreviewExtmark
local M = {}

local api = vim.api

local bqf_ns

---
---@param fbufnr number
function M.clear_highlight(fbufnr)
    if bqf_ns then
        api.nvim_buf_clear_namespace(fbufnr, bqf_ns, 0, -1)
    end
end

---
---@param bufnr number
---@param fbufnr number
---@param topline number
---@param botline number
function M.update_highlight(bufnr, fbufnr, topline, botline)
    M.clear_highlight(fbufnr)
    for _, ns in pairs(api.nvim_get_namespaces()) do
        local extmarks = api.nvim_buf_get_extmarks(bufnr, ns, {topline - 1, 0}, {botline - 1, -1},
            {details = true})
        for _, m in ipairs(extmarks) do
            local _, row, col, details = unpack(m)
            local end_row, end_col = details.end_row, details.end_col
            local hl_group = details.hl_group
            local priority = details.priority
            api.nvim_buf_set_extmark(fbufnr, bqf_ns, row, col, {
                end_row = end_row,
                end_col = end_col,
                hl_group = hl_group,
                priority = priority
            })
        end
    end
end

local function init()
    bqf_ns = api.nvim_create_namespace('bqf-preview-extmark')
end

init()

return M
