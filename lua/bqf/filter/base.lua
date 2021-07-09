local M = {}
local api = vim.api

local wses = require('bqf.wsession')

function M.filter_list(qwinid, co_wrap)
    local qo = wses.qobj(qwinid)
    local items = qo:get_items()
    if not co_wrap or #items < 2 then
        return
    end
    local context = qo:get_context()
    local title = qo:get_qflist({title = 0}, qwinid).title
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
    qo:new_qflist({nr = '$', context = context, title = title, items = new_items})
end

function M.run(reverse)
    local qwinid = api.nvim_get_current_win()
    local qo = wses.qobj(qwinid)
    local items = qo:get_items()
    local signs = qo:get_sign():list()
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
