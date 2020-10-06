local M = {}

function M.tbl_kv_map(func, tbl)
    local new_tbl = {}
    for k, v in pairs(tbl) do
        new_tbl[k] = func(k, v)
    end
    return new_tbl
end

function M.tbl_concat(t1, t2)
    for i = 1, #t2 do
        t1[#t1 + 1] = t2[i]
    end
    return t1
end

return M
