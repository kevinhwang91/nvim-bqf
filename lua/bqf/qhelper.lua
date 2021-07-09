local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local wses = require('bqf.wsession')

local function close(winid)
    local ok, msg = pcall(api.nvim_win_close, winid, false)
    if not ok then
        -- Vim:E444: Cannot close last window
        if msg:match('^Vim:E444') then
            cmd('new')
            api.nvim_win_close(winid, true)
        end
    end
end

function M.validate_qf(winid)
    winid = winid or api.nvim_get_current_win()

    -- Invalid window id
    -- Key not found: quickfix_title
    local ret = pcall(function()
        api.nvim_win_get_var(winid, 'quickfix_title')
    end)

    -- quickfix_title is undefined, copen when quickfix list is empty
    if not ret then
        ret = pcall(function()
            ret = fn.getwininfo(winid)[1].quickfix == 1
        end) and ret
    end
    return ret
end

function M.pair_winid(winid)
    winid = winid or api.nvim_get_current_win()
    local qo = wses.qobj(winid)
    local pair_winid = wses[winid].pair_winid
    if not pair_winid or not api.nvim_win_is_valid(pair_winid) then
        if qo.type == 'loc' then
            pair_winid = fn.getloclist(winid, {filewinid = 0}).filewinid
        else
            pair_winid = fn.win_getid(fn.winnr('#'))
            if pair_winid <= 0 and not api.nvim_win_is_valid(pair_winid) or
                M.validate_qf(pair_winid) then
                local tabpage = api.nvim_win_get_tabpage(winid)
                for _, w_id in ipairs(api.nvim_tabpage_list_wins(tabpage)) do
                    if api.nvim_win_is_valid(w_id) and not M.validate_qf(w_id) and
                        api.nvim_win_get_config(w_id).relative == '' then
                        pair_winid = w_id
                        break
                    end
                end
            end
        end
        if pair_winid <= 0 or not api.nvim_win_is_valid(pair_winid) or M.validate_qf(pair_winid) then
            close(winid)
            wses[winid].pair_winid = -1
            -- assert(false, 'A valid file window is not found in current tabpage')
        end
        wses[winid].pair_winid = pair_winid
    end
    return wses[winid].pair_winid
end

return M
