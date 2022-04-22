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

---
---@param winlayout table
---@param parent table
---@param winid number
---@param level? number
---@param index? number
local function nodeInfo(winlayout, parent, winid, level, index)
    level = level or 0
    index = index or 1
    local indicator = winlayout[1]
    if indicator == 'leaf' then
        if winlayout[2] == winid then
            return parent, level, index
        end
    else
        for i = 1, #winlayout[2] do
            local p, d, idx = nodeInfo(winlayout[2][i], winlayout, winid, level + 1, i)
            if p then
                return p, d, idx
            end
        end
    end
end

local function adjacentWins(winlayout, isBottom)
    local wins = {}
    local ind, tbl = winlayout[1], winlayout[2]
    if ind == 'leaf' then
        wins = {tbl}
    elseif ind == 'col' then
        wins = adjacentWins(tbl[isBottom and #tbl or 1], isBottom)
    else
        for i = 1, #tbl do
            local wins2 = adjacentWins(tbl[i], isBottom)
            for j = 1, #wins2 do
                wins[#wins + 1] = wins2[j]
            end
        end
    end
    return wins
end

---
---@return number[]
function M.findBottomWins()
    return adjacentWins(fn.winlayout(), true)
end

---
---@param winid number
---@param owinid number
---@return number[]
function M.findAdjacentWins(winid, owinid)
    local wins = {}
    local relPos, absPos = unpack(M.getPos(winid, owinid))
    if relPos == POS.ABOVE or relPos == POS.BELOW then
        wins = {owinid}
    elseif absPos == POS.TOP or absPos == POS.BOTTOM then
        local nest = fn.winlayout()[2]
        if absPos == POS.TOP then
            wins = adjacentWins(nest[2], false)
        else
            wins = adjacentWins(nest[#nest - 1], true)
        end
    end
    return wins
end

---
---@param winid number
---@param owinid number
---@return number[]
function M.getPos(winid, owinid)
    local layout = fn.winlayout()
    local nested = layout[2]
    local relPos, absPos = POS.UNKNOWN, POS.UNKNOWN
    if type(nested) ~= 'table' or #nested < 2 then
        return {relPos, absPos}
    end
    local parentLayout, childLevel, childIndex = nodeInfo(layout, nil, winid)

    -- winid doesn't exist in current tabpage
    if not parentLayout or type(parentLayout) ~= 'table' then
        return {relPos, absPos}
    end
    local parentIndicator, childLayout = unpack(parentLayout)
    if childLevel == 1 then
        if childIndex == 1 then
            if parentIndicator == 'col' then
                absPos = POS.TOP
            else
                absPos = POS.LEFT_FAR
            end
        elseif childIndex == #nested then
            if parentIndicator == 'col' then
                absPos = POS.BOTTOM
            else
                absPos = POS.RIGHT_FAR
            end
        end
    end
    for i, wly in ipairs(childLayout) do
        if wly[1] == 'leaf' and wly[2] == owinid then
            local offsetIndex = i - childIndex
            if parentIndicator == 'col' then
                if offsetIndex == 1 then
                    relPos = POS.ABOVE
                elseif offsetIndex == -1 then
                    relPos = POS.BELOW
                end
            elseif parentIndicator == 'row' then
                if offsetIndex == 1 then
                    relPos = POS.LEFT
                elseif offsetIndex == -1 then
                    relPos = POS.RIGHT
                end
            end
        end
    end
    return {relPos, absPos}
end

return M
