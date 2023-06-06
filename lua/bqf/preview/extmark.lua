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

function M.setHighlight(bufnr, ns, row, col, endRow, endCol, hlGroup, priority)
    return api.nvim_buf_set_extmark(bufnr, ns, row, col, {
        end_row = endRow,
        end_col = endCol,
        hl_group = hlGroup,
        priority = priority
    })
end

function M.setVirtText(bufnr, ns, row, col, virtText, opts)
    opts = opts or {}
    return api.nvim_buf_set_extmark(bufnr, ns, row, col, {
        id = opts.id,
        virt_text = virtText,
        virt_text_win_col = opts.virt_text_win_col,
        priority = opts.priority or 10,
        hl_mode = opts.hl_mode or 'combine'
    })
end

return M
