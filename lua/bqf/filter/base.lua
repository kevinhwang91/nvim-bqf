local M = {}
local api = vim.api

local qftool = require('bqf.qftool')

function M.filter_list(qf_winid, co_wrap)
    local qf_all = qftool.getall(qf_winid)
    local items = qf_all.items
    if #items < 2 then
        return
    end
    local context, title = qf_all.context, qf_all.title
    local lsp_ranges, new_items = {}, {}
    for i, item in co_wrap or 0 do
        table.insert(new_items, item)
        if qf_all.lsp_ranges_hl then
            table.insert(lsp_ranges, qf_all.lsp_ranges_hl[i])
        end
    end

    if #new_items == 0 then
        return
    end

    if #lsp_ranges > 0 then
        context.bqf.lsp_ranges_hl = lsp_ranges
    end

    title = '*' .. title
    qftool.set({nr = '$', context = context, title = title, items = new_items}, qf_winid)
end

function M.run(reverse)
    local qf_winid = api.nvim_get_current_win()
    local qf_all = qftool.getall(qf_winid)
    local items, signs = qf_all.items, qf_all.signs or {}
    if reverse and #signs == 0 then
        return
    end
    M.filter_list(qf_winid, coroutine.wrap(function()
        if reverse then
            for i in ipairs(items) do
                if not signs[i] then
                    coroutine.yield(i, items[i])
                end
            end
        else
            local k_signs = vim.tbl_keys(signs)
            table.sort(k_signs)
            for _, i in pairs(k_signs) do
                coroutine.yield(i, items[i])
            end
        end
    end))
end

return M
