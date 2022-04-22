---@class BqfMagicWinCore
local M = {}
local api = vim.api
local fn = vim.fn

local LSize = require('bqf.magicwin.lsize')
local utils = require('bqf.utils')
local log = require('bqf.log')

-- Code in this file relates to source code
-- https://github.com/neovim/neovim/blob/master/src/nvim/window.c
-- bfraction: before scroll_to_fraction, afraction: after scroll_to_fraction
-- bfraction = bwrow / bheight and afraction = awrow / aheight
-- bfraction = afraction ==> bwrow / bheight = awrow / aheight

-- FRACTION_MULT = 16384L
-- wp->w_fraction = ((long)wp->w_wrow * FRACTION_MULT + FRACTION_MULT / 2) / (long)wp->w_height_inner;
local function calculateFraction(wrow, height)
    return math.floor((wrow * 16384 + 8192) / height)
end

-- wp->w_wrow = ((long)wp->w_fraction * (long)height - 1L) / FRACTION_MULT;
local function calculateWrow(fraction, height)
    return math.floor((fraction * height - 1) / 16384)
end

--- Check out 'void scroll_to_fraction(win_T *wp, int prev_height)' in window.c for more details.
---@param fraction number
---@param ctx table
---@param lsizeObj BqfLFFI|BqfLNonFFI
---@return number
local function evaluateWrow(fraction, ctx, lsizeObj)
    local height = ctx.height
    local wrow = calculateWrow(fraction, height)
    local winView, lastWinView = ctx.winView, ctx.lastWinView
    local lnum, col = winView.lnum, winView.col + 1
    local lineSize = lsizeObj:posSize(lnum, col) - 1
    local sline = wrow - lineSize
    log.debug('wrow:', wrow, 'sline:', sline, 'lastWinView:', lastWinView)
    if sline >= 0 then
        local rows = lsizeObj:size(lnum)
        if sline > height - rows then
            sline = height - rows
            wrow = wrow - rows + lineSize
        end
    end
    if sline < 0 then
        -- TODO extremely edge case
        wrow = lineSize
    elseif sline > 0 then
        while sline > 0 and lnum > 1 do
            local fs = lsizeObj:foldclosed(lnum)
            if fs ~= -1 then
                lnum = fs
            end
            if lnum == 1 then
                lineSize = 1
                sline = sline - 1
                break
            end
            lnum = lnum - 1
            if lastWinView and lnum == lastWinView.topline then
                lineSize = lsizeObj:nofillSize(lnum) + lastWinView.topfill
            else
                lineSize = lsizeObj:size(lnum)
            end
            log.debug('lnum:', lnum, 'lineSize:', lineSize)
            sline = sline - lineSize
        end

        if sline < 0 then
            wrow = wrow - lineSize - sline
        elseif sline > 0 then
            wrow = wrow - sline
        end
    end
    log.debug('evaluated wrow:', wrow, 'fraction:', fraction, 'height:', height)
    return wrow
end

---
---@param fractionList number[]
---@param ctx table
---@param lsizeObj BqfLFFI|BqfLNonFFI
---@return number[]
local function doFilter(fractionList, ctx, lsizeObj)
    local t = {}
    local winView = ctx.winView
    local topline = winView.topline
    local addFill = lsizeObj:fillSize(topline)
    local loFillWrow = ctx.wrow
    local hiFillWrow = loFillWrow + addFill
    log.debug('loFillWrow:', loFillWrow, 'hiFillWrow:', hiFillWrow, 'addFill:', addFill)
    for _, frac in ipairs(fractionList) do
        local wrow = evaluateWrow(frac, ctx, lsizeObj)
        if wrow >= loFillWrow and wrow <= hiFillWrow then
            table.insert(t, frac)
        end
    end
    return t
end

--- If the lnum hasn't been changed, even if the window is resized, the fraction is still a constant.
--- And we can use this feature to find out the possible fraction with changing window height.
--- Check out 'void scroll_to_fraction(win_T *wp, int prev_height)' in window.c for more details.
---@param fractionList number[]
---@param lsizeObj BqfLFFI|BqfLNonFFI
---@param maxHeight? number
---@return number[]
local function filterFraction(fractionList, lsizeObj, maxHeight)
    local asc
    local height = api.nvim_win_get_height(0)
    local h = height
    local minHeight = math.max(vim.o.wmh, 1)
    if maxHeight then
        asc = true
    else
        asc = false
        maxHeight = vim.o.lines
    end

    local winView
    local lastWrow = fn.winline() - 1
    local lastWinView = fn.winsaveview()
    while #fractionList > 1 and h > minHeight and h < maxHeight do
        h = asc and h + 1 or h - 1
        api.nvim_win_set_height(0, h)
        if asc and api.nvim_win_get_height(0) ~= h then
            break
        end
        local curWrow = fn.winline() - 1
        winView = fn.winsaveview()
        local ctx = {wrow = curWrow, height = h, winView = winView, lastWinView = lastWinView}
        if asc and curWrow >= lastWrow or not asc and curWrow <= lastWrow then
            fractionList = doFilter(fractionList, ctx, lsizeObj)
        else
            log.debug(('current wrow: %d and height: %d have changed, skip!'):format(curWrow, h))
        end
        lastWinView = winView
        lastWrow = curWrow
    end

    if h ~= height then
        api.nvim_win_set_height(0, height)
    end
    return fractionList
end

---
---@param awrow number
---@param aheight number
---@param bheight number
---@return number
function M.evaluate(awrow, aheight, bheight)
    -- loBWrow: the minimum bwrow value
    -- Below formula we can derive from the known conditions
    local loBWrow = math.ceil(awrow * bheight / aheight - 0.5)
    if loBWrow < 0 or bheight == aheight then
        return
    end

    -- expand the lower limit
    -- loBWrow = math.max(0, loBWrow - 2)

    -- hiBWrow: the maximum bwrow value
    -- There are not enough conditions to derive hiBWrow, so we have to figure it out by
    -- guessing, and confirm the range of bwrow. It seems that loBWrow plug 8 as a minimum and
    -- 1.2 as a scale is good to balance performance and accuracy
    local hiBWrow = math.max(loBWrow + 8, math.ceil(awrow * 1.2 * bheight / aheight - 0.25))
    log.debug('loBWrow:', loBWrow, 'hiBWrow:', hiBWrow)

    local lsizeObj = LSize:new()

    local fractionList = {}
    for bw = loBWrow, hiBWrow do
        table.insert(fractionList, calculateFraction(bw, bheight))
    end
    log.debug('before fractionList', fractionList)

    fractionList = filterFraction(fractionList, lsizeObj)
    log.debug('first fractionList:', fractionList)

    fractionList = filterFraction(fractionList, lsizeObj, aheight + 9)
    log.debug('second fractionList:', fractionList)

    if #fractionList > 0 then
        local fraction = fractionList[1]
        return calculateWrow(fraction, bheight)
    end
end

function M.resetView(winView)
    fn.winrestview(winView)
    -- topline may not be changed sometimes without winline()
    fn.winline()
end

---
---@param winid number
---@param topline number
---@param lsizes BqfLFFI|BqfLNonFFI
---@return number, number
function M.tuneTop(winid, topline, lsizes)
    return utils.winExecute(winid, function()
        local iStart, iEnd, iInc, shouldContinue, len
        local foldedOtherLnum

        local lsizeObj = LSize:new()
        if lsizes > 0 then
            iStart, iEnd, iInc = topline - 1, math.max(1, topline - lsizes), -1
            shouldContinue = function(iter)
                return iter >= iEnd
            end
            len = lsizes
            foldedOtherLnum = function(i)
                return lsizeObj:foldclosed(i)
            end
        else
            iStart, iEnd, iInc = topline, topline - lsizes - 1, 1
            shouldContinue = function(iter)
                return iter <= iEnd
            end
            len = -lsizes
            foldedOtherLnum = function(i)
                return lsizeObj:foldclosedEnd(i)
            end
        end

        log.debug(iStart, iEnd, iInc, len)
        log.debug('lsizes:', lsizes)

        local addFill = lsizeObj:fillSize(topline)
        len = len + (lsizes > 0 and -addFill or addFill)
        local lsizeSum = 0
        local i = iStart
        while lsizeSum < len and shouldContinue(i) do
            log.debug('=====================================================')
            log.debug('i:', i, 'iEnd:', iEnd)
            local foLnum = foldedOtherLnum(i)
            if foLnum == -1 then
                local lsize = lsizeObj:size(i)
                log.debug('lsizeSum:', lsizeSum, 'lsize:', lsize, 'lnum:', i)
                lsizeSum = lsizeSum + lsize
            else
                log.debug('foLnum:', foLnum)
                lsizeSum = lsizeSum + 1
                iEnd = iEnd + foLnum - i
                i = foLnum
            end
            log.debug('=====================================================')
            topline = i
            i = i + iInc
        end

        -- extraOff lines is need to be showed near the topline
        local fill
        local extraOff = lsizeSum - len
        log.debug('extraOff:', extraOff, 'len:', len)
        if extraOff > 0 then
            fill = lsizeObj:fillSize(topline)
            if fill < extraOff then
                if lsizes > 0 then
                    topline = topline + 1
                end
            else
                local nofill = lsizeObj:nofillSize(topline)
                fill = lsizes > 0 and fill - extraOff or math.max(0, extraOff - nofill)
            end
        else
            if lsizes < 0 then
                topline = topline + 1
            end
            fill = lsizeObj:fillSize(topline)
        end
        log.debug('topline:', topline, 'fill:', fill)
        return topline, fill
    end)
end

return M
