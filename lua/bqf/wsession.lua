local M = {}
local holder = {}

local qobj

local api = vim.api

setmetatable(M, {
    __index = function(_, k)
        if type(k) ~= 'number' then
            return nil
        end
        -- TODO some events inside non-quickfix window will require a quickfix session,
        -- return empty table that holder never maintain.
        return holder[k] or {}
    end
})

function M.acquire(winid)
    if not holder[winid] then
        holder[winid] = {}
    end
    return holder[winid]
end

function M.release(winid)
    if winid then
        holder[winid] = nil
    end
    for w_id in pairs(holder) do
        if not api.nvim_win_is_valid(w_id) then
            holder[w_id] = nil
        end
    end
end

function M.holder()
    return holder
end

function M.bind_qobj(winid)
    local ws = holder[winid]
    qobj = require('bqf.qobj')
    local qo = qobj.get(winid)
    ws.qobj = qo
    return ws.qobj
end

function M.qobj(winid)
    local ws = holder[winid]
    qobj = require('bqf.qobj')
    if not ws.qobj then
        local qo = qobj.get(winid)
        ws.qobj = qo
    end
    return ws.qobj
end

return M
