--- Singleton
---@class BqfBaseFilter
local M = {}
local api = vim.api

local qfs = require('bqf.qfwin.session')

---
---@param qwinid number
---@param co_wrap fun(): number, BqfQfItem
function M.filter_list(qwinid, co_wrap)
    if not co_wrap then
        return
    end

    local qs = qfs:get(qwinid)
    local qlist = qs:list()
    local qinfo = qlist:get_qflist({size = 0, title = 0, quickfixtextfunc = 0})
    local size = qinfo.size
    if size < 2 then
        return
    end
    local context = qlist:context()
    local title, qftf = qinfo.title, qinfo.quickfixtextfunc
    local lsp_ranges, new_items = {}, {}
    for i, item in co_wrap do
        table.insert(new_items, item)
        if type(context.lsp_ranges_hl) == 'table' then
            table.insert(lsp_ranges, context.lsp_ranges_hl[i])
        end
    end

    if #new_items == 0 then
        return
    end

    if #lsp_ranges > 0 then
        context.lsp_ranges_hl = lsp_ranges
    end

    title = '*' .. title
    qfs:save_winview(qwinid)
    qlist:new_qflist({
        nr = '$',
        context = context,
        title = title,
        items = new_items,
        quickfixtextfunc = qftf
    })
end

function M.run(reverse)
    local qwinid = api.nvim_get_current_win()
    local qs = qfs:get(qwinid)
    local qlist = qs:list()
    local signs = qlist:sign():list()
    if reverse and vim.tbl_isempty(signs) then
        return
    end
    M.filter_list(qwinid, coroutine.wrap(function()
        local items = qlist:items()
        if reverse then
            for i in ipairs(items) do
                if not signs[i] then
                    coroutine.yield(i, items[i])
                end
            end
        else
            local k_signs = vim.tbl_keys(signs)
            table.sort(k_signs)
            for _, i in ipairs(k_signs) do
                coroutine.yield(i, items[i])
            end
        end
    end))
end

return M
