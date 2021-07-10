local M = {}
local api = vim.api
local fn = vim.fn

local wses = require('bqf.wsession')

function M.validate_qf(winid)
    winid = winid or api.nvim_get_current_win()
    local ok, ret
    ok = pcall(function()
        ret = fn.getwininfo(winid)[1].quickfix == 1
    end)
    return ok and ret
end

function M.pair_winid(winid)
    winid = winid or api.nvim_get_current_win()
    local pair_winid = wses[winid].pair_winid
    if not pair_winid or not api.nvim_win_is_valid(pair_winid) then
        local qo = wses.qobj(winid)
        if qo.type == 'loc' then
            pair_winid = qo.filewinid
        else
            pair_winid = fn.win_getid(fn.winnr('#'))
            if pair_winid <= 0 and not api.nvim_win_is_valid(pair_winid) or
                M.validate_qf(pair_winid) then
                local tabpage = api.nvim_win_get_tabpage(winid)
                for _, w_id in ipairs(api.nvim_tabpage_list_wins(tabpage)) do
                    if api.nvim_win_is_valid(w_id) and not M.validate_qf(w_id) and
                        fn.win_gettype(w_id) ~= '' then
                        pair_winid = w_id
                        break
                    end
                end
            end
        end
        if pair_winid <= 0 or not api.nvim_win_is_valid(pair_winid) or M.validate_qf(pair_winid) then
            pair_winid = -1
        end
        wses[winid].pair_winid = pair_winid
    end
    return wses[winid].pair_winid
end

return M
