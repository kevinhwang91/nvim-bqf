---@class BqfWinPos
local M = {}
local fn = vim.fn

local POS = {
    UNKNOWN = 0,
    ABOVE = 1,
    BELOW = 2,
    TOP = 3,
    BOTTOM = 4,
    LEFT = 5,
    RIGHT = 6,
    LEFT_FAR = 7,
    RIGHT_FAR = 8
}

M.POS = POS

local function node_info(winlayout, parent, winid, level, index)
    level = level or 0
    index = index or 1
    local indicator = winlayout[1]
    if indicator == 'leaf' then
        if winlayout[2] == winid then
            return parent, level, index
        end
    else
        for i = 1, #winlayout[2] do
            local p, d, idx = node_info(winlayout[2][i], winlayout, winid, level + 1, i)
            if p then
                return p, d, idx
            end
        end
    end
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

---
---@return number[]
function M.find_bottom_wins()
    return adjacent_wins(fn.winlayout(), true)
end

---
---@param winid number
---@param owinid number
---@return number[]
function M.find_adjacent_wins(winid, owinid)
    local wins = {}
    local rel_pos, abs_pos = unpack(M.get_pos(winid, owinid))
    if rel_pos == POS.ABOVE or rel_pos == POS.BELOW then
        wins = {owinid}
    elseif abs_pos == POS.TOP or abs_pos == POS.BOTTOM then
        local nest = fn.winlayout()[2]
        if abs_pos == POS.TOP then
            wins = adjacent_wins(nest[2], false)
        else
            wins = adjacent_wins(nest[#nest - 1], true)
        end
    end
    return wins
end

---
---@param winid number
---@param owinid number
---@return number[]
function M.get_pos(winid, owinid)
    local layout = fn.winlayout()
    local nested = layout[2]
    local rel_pos, abs_pos = POS.UNKNOWN, POS.UNKNOWN
    if type(nested) ~= 'table' or #nested < 2 then
        return {rel_pos, abs_pos}
    end
    local parent_layout, child_level, child_index = node_info(layout, nil, winid)

    -- winid doesn't exist in current tabpage
    if not parent_layout or type(parent_layout) ~= 'table' then
        return {rel_pos, abs_pos}
    end
    local parent_indicator, child_layout = unpack(parent_layout)
    if child_level == 1 then
        if child_index == 1 then
            if parent_indicator == 'col' then
                abs_pos = POS.TOP
            else
                abs_pos = POS.LEFT_FAR
            end
        elseif child_index == #nested then
            if parent_indicator == 'col' then
                abs_pos = POS.BOTTOM
            else
                abs_pos = POS.RIGHT_FAR
            end
        end
    end
    for i, wly in ipairs(child_layout) do
        if wly[1] == 'leaf' and wly[2] == owinid then
            local offset_index = i - child_index
            if parent_indicator == 'col' then
                if offset_index == 1 then
                    rel_pos = POS.ABOVE
                elseif offset_index == -1 then
                    rel_pos = POS.BELOW
                end
            elseif parent_indicator == 'row' then
                if offset_index == 1 then
                    rel_pos = POS.LEFT
                elseif offset_index == -1 then
                    rel_pos = POS.RIGHT
                end
            end
        end
    end
    return {rel_pos, abs_pos}
end

return M
