---@class BqfPreviewSemanticToken
local M = {}

local api = vim.api

local coc_initialized
local coc_ns
local ns

local function coc_enabled()
    if coc_initialized == nil then
        local initialized = vim.g.coc_service_initialized
        if type(initialized) == 'number' then
            coc_initialized = initialized == 1
        end
    end
    return coc_initialized
end

function M.clear_highlight(fbufnr)
    if ns then
        api.nvim_buf_clear_namespace(fbufnr, ns, 0, -1)
    end
end

---
---@param bufnr number
---@param fbufnr number
---@param topline number
---@param botline number
function M.update_highlight(bufnr, fbufnr, topline, botline)
    if not coc_enabled() then
        return
    end

    if not ns or not coc_ns then
        coc_ns = api.nvim_create_namespace('coc-semanticTokens')
        ns = api.nvim_create_namespace('bqf-semanticTokens')
    end

    local extmarks = api.nvim_buf_get_extmarks(bufnr, coc_ns, {topline - 1, 0}, {botline - 1, -1},
        {details = true})
    M.clear_highlight(fbufnr)
    for _, m in ipairs(extmarks) do
        local _, row, col, details = unpack(m)
        local end_row, end_col = details.end_row, details.end_col
        local hl_group = details.hl_group
        local priority = details.priority
        api.nvim_buf_set_extmark(fbufnr, ns, row, col, {
            end_row = end_row,
            end_col = end_col,
            hl_group = hl_group,
            priority = priority
        })
    end
end

return M
