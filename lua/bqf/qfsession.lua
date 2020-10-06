local M = {}
local holder = {}

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

function M.attach(winid)
    if not holder[winid] then
        holder[winid] = {}
    end
    return holder[winid]
end

function M.release(winid)
    if winid then
        holder[winid] = nil
    end
end

function M.holder()
    return holder
end

return M
