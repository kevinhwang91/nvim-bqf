---@class BqfPreviewExtmark
local M = {}

local api = vim.api

local hlNs
local virtNs

---
---@param bufnr number
function M.clearHighlight(bufnr)
    if hlNs then
        api.nvim_buf_clear_namespace(bufnr, hlNs, 0, -1)
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
            pcall(api.nvim_buf_set_extmark, dstBufnr, hlNs, row, col, {
                end_row = endRow,
                end_col = endCol,
                hl_group = hlGroup,
                priority = priority
            })
        end
    end
end

---
---@param bufnr number
---@param lnum number
---@param chunks table
---@param opts? table
---@return number
function M.setVirtEol(bufnr, lnum, chunks, opts)
    opts = opts or {}
    return api.nvim_buf_set_extmark(bufnr, virtNs, lnum, -1, {
        id = opts.id,
        virt_text = chunks,
        hl_mode = 'combine',
        priority = opts.priority
    })
end

local function init()
    hlNs = api.nvim_create_namespace('')
    virtNs = api.nvim_create_namespace('')
end

init()

return M
