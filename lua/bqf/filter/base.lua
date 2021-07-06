local M = {}
local api = vim.api

local qftool = require('bqf.qftool')
local sign = require('bqf.sign')

function M.filter_list(qwinid, co_wrap)
    local items = qftool.items(qwinid)
    if not co_wrap or #items < 2 then
        return
    end
    local context = qftool.context(qwinid)
    local title = qftool.get({title = 0}, qwinid).title
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
    qftool.set({nr = '$', context = context, title = title, items = new_items}, qwinid)
end

function M.run(reverse)
    local qwinid = api.nvim_get_current_win()
    local items = qftool.items(qwinid)
    local signs = sign.get()
    if reverse and vim.tbl_isempty(signs) then
        return
    end
    M.filter_list(qwinid, coroutine.wrap(function()
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
