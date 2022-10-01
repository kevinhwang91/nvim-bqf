--- Singleton
---@class BqfBaseFilter
local M = {}
local api = vim.api

local qfs = require('bqf.qfwin.session')

---
---@param qwinid number
---@param items BqfQfItem[]
function M.filterList(qwinid, items)
    if not items then
        return
    end

    local qs = qfs:get(qwinid)
    local qlist = qs:list()
    local qinfo = qlist:getQfList({size = 0, title = 0, quickfixtextfunc = 0})
    local size = qinfo.size
    if size < 2 then
        return
    end
    local context = qlist:context()
    local title, qftf = qinfo.title, qinfo.quickfixtextfunc
    local lspRanges, newItems = {}, {}
    for i, item in ipairs(items) do
        table.insert(newItems, item)
        if type(context.lsp_ranges_hl) == 'table' then
            table.insert(lspRanges, context.lsp_ranges_hl[i])
        end
    end

    if #newItems == 0 then
        return
    end

    if #lspRanges > 0 then
        context.lsp_ranges_hl = lspRanges
    end

    title = '*' .. title
    qfs:saveWinView(qwinid)
    qlist:newQfList({
        nr = '$',
        context = context,
        title = title,
        items = newItems,
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
    local items = qlist:items()
    local newItems = {}
    if reverse then
        for i in ipairs(items) do
            if not signs[i] then
                table.insert(newItems, items[i])
            end
        end
    else
        local kSigns = vim.tbl_keys(signs)
        table.sort(kSigns)
        for _, i in ipairs(kSigns) do
            table.insert(newItems, items[i])
        end
    end
    M.filterList(qwinid, newItems)
end

return M
