local M = {}
local fn = vim.fn

local function node_info(winlayout, winid, p_indicator, level, index)
    level = level or 0
    index = index or 1
    local indicator = winlayout[1]
    if indicator == 'leaf' then
        if winlayout[2] == winid then
            return p_indicator, level, index
        end
    else
        for i = 1, #winlayout[2] do
            local p, d, idx = node_info(winlayout[2][i], winid, indicator, level + 1, i)
            if p then
                return p, d, idx
            end
        end
    end
    return
end

local function adjacent_wins(winlayout, is_bottom)
    local wins = {}
    local ind, tbl = winlayout[1], winlayout[2]
    if ind == 'leaf' then
        wins = {tbl}
    elseif ind == 'col' then
        wins = adjacent_wins(tbl[is_bottom and #tbl or 1], is_bottom)
    else
        for i = 1, #tbl do
            local wins2 = adjacent_wins(tbl[i], is_bottom)
            for j = 1, #wins2 do
                wins[#wins + 1] = wins2[j]
            end
        end
    end
    return wins
end

function M.find_adjacent_wins(qf_winid, file_winid)
    local wins = {}
    local rel_pos, abs_pos = unpack(M.get_pos(qf_winid, file_winid))
    if rel_pos == 'above' or rel_pos == 'below' then
        wins = {file_winid}
    elseif abs_pos == 'top' or abs_pos == 'bottom' then
        local nest = fn.winlayout()[2]
        if abs_pos == 'top' then
            wins = adjacent_wins(nest[2], false)
        else
            wins = adjacent_wins(nest[#nest - 1], true)
        end
    end
    return wins
end

-- get_pos is fast enough, no need to add a cache
function M.get_pos(qf_winid, file_winid)
    local layout = fn.winlayout()
    local nested = layout[2]
    local rel_pos, abs_pos = 'unknown', 'unknown'
    if type(nested) ~= 'table' or #nested < 2 then
        return {rel_pos, abs_pos}
    end
    local qf_p_ind, qf_level, qf_index = node_info(layout, qf_winid)
    if qf_level == 1 then
        if qf_index == 1 then
            if qf_p_ind == 'col' then
                abs_pos = 'top'
            else
                abs_pos = 'left_far'
            end
        elseif qf_index == #nested then
            if qf_p_ind == 'col' then
                abs_pos = 'bottom'
            else
                abs_pos = 'right_far'
            end
        end
    end
    local f_p_ind, f_level, f_index = node_info(layout, file_winid)
    if f_level == qf_level then
        local offset_index = f_index - qf_index
        if f_p_ind == 'col' then
            if offset_index == 1 then
                rel_pos = 'above'
            elseif offset_index == -1 then
                rel_pos = 'below'
            end
        else
            if offset_index == 1 then
                rel_pos = 'left'
            elseif offset_index == -1 then
                rel_pos = 'right'
            end
        end
    end
    return {rel_pos, abs_pos}
end

return M
