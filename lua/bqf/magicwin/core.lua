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
local function cal_fraction(wrow, height)
    return math.floor((wrow * 16384 + 8192) / height)
end

-- wp->w_wrow = ((long)wp->w_fraction * (long)height - 1L) / FRACTION_MULT;
local function cal_wrow(fraction, height)
    return math.floor((fraction * height - 1) / 16384)
end

-- Check out 'void scroll_to_fraction(win_T *wp, int prev_height)' in winodw.c for more details.
local function evaluate_wrow(fraction, ctx, lsize_obj)
    local height = ctx.height
    local wrow = cal_wrow(fraction, height)
    local wv, last_wv = ctx.wv, ctx.last_wv
    local lnum, col = wv.lnum, wv.col + 1
    local line_size = lsize_obj:pos_size(lnum, col) - 1
    local sline = wrow - line_size
    log.debug('wrow:', wrow, 'sline:', sline, 'last_wv:', last_wv)
    if sline >= 0 then
        local rows = lsize_obj:size(lnum)
        if sline > height - rows then
            sline = height - rows
            wrow = wrow - rows + line_size
        end
    end
    if sline < 0 then
        -- TODO extremely edge case
        wrow = line_size
    elseif sline > 0 then
        while sline > 0 and lnum > 1 do
            local fs = lsize_obj:foldclosed(lnum)
            if fs ~= -1 then
                lnum = fs
            end
            if lnum == 1 then
                line_size = 1
                sline = sline - 1
                break
            end
            lnum = lnum - 1
            if last_wv and lnum == last_wv.topline then
                line_size = lsize_obj:nofill_size(lnum) + last_wv.topfill
            else
                line_size = lsize_obj:size(lnum)
            end
            log.debug('lnum:', lnum, 'line_size:', line_size)
            sline = sline - line_size
        end

        if sline < 0 then
            wrow = wrow - line_size - sline
        elseif sline > 0 then
            wrow = wrow - sline
        end
    end
    log.debug('evaluated wrow:', wrow, 'fraction:', fraction, 'height:', height)
    return wrow
end

local function do_filter(frac_list, ctx, lsize_obj)
    local t = {}
    local wv = ctx.wv
    local topline = wv.topline
    local add_fill = lsize_obj:fill_size(topline)
    local lo_fil_wrow = ctx.wrow
    local hi_fil_wrow = lo_fil_wrow + add_fill
    log.debug('lo_fil_wrow:', lo_fil_wrow, 'hi_fil_wrow:', hi_fil_wrow, 'add_fill:', add_fill)
    for _, frac in ipairs(frac_list) do
        local wrow = evaluate_wrow(frac, ctx, lsize_obj)
        if wrow >= lo_fil_wrow and wrow <= hi_fil_wrow then
            table.insert(t, frac)
        end
    end
    return t
end

-- If the lnum hasn't been changed, even if the window is resized, the fraction is still a constant.
-- And we can use this feature to find out the possible fraction with changing window height.
-- Check out 'void scroll_to_fraction(win_T *wp, int prev_height)' in winodw.c for more details.
local function filter_fraction(frac_list, lsize_obj, max_hei)
    local asc
    local height = api.nvim_win_get_height(0)
    local h = height
    local min_hei = math.max(vim.o.wmh, 1)
    if max_hei then
        asc = true
    else
        asc = false
        max_hei = vim.o.lines
    end

    local wv
    local last_wrow = fn.winline() - 1
    local last_wv = fn.winsaveview()
    while #frac_list > 1 and h > min_hei and h < max_hei do
        h = asc and h + 1 or h - 1
        api.nvim_win_set_height(0, h)
        if asc and api.nvim_win_get_height(0) ~= h then
            break
        end
        local cur_wrow = fn.winline() - 1
        wv = fn.winsaveview()
        local ctx = {wrow = cur_wrow, height = h, wv = wv, last_wv = last_wv}
        if asc and cur_wrow >= last_wrow or not asc and cur_wrow <= last_wrow then
            frac_list = do_filter(frac_list, ctx, lsize_obj)
        else
            log.debug(('current wrow: %d and height: %d have changed, skip!'):format(cur_wrow, h))
        end
        last_wv = wv
        last_wrow = cur_wrow
    end

    if h ~= height then
        api.nvim_win_set_height(0, height)
    end
    return frac_list
end

function M.evaluate(awrow, aheight, bheight)
    -- s_bwrow: the minimum bwrow value
    -- Below formula we can derive from the known conditions
    local lo_bwrow = math.ceil(awrow * bheight / aheight - 0.5)
    if lo_bwrow < 0 or bheight == aheight then
        return
    end

    -- expand the lower limit
    -- lo_bwrow = math.max(0, lo_bwrow - 2)

    -- hi_bwrow: the maximum bwrow value
    -- There are not enough conditions to derive hi_bwrow, so we have to figure it out by
    -- guessing, and confirm the range of bwrow. It seems that lo_bwrow plug 8 as a minimum and
    -- 1.2 as a scale is good to balance performance and accuracy
    local hi_bwrow = math.max(lo_bwrow + 8, math.ceil(awrow * 1.2 * bheight / aheight - 0.25))
    log.debug('lo_bwrow:', lo_bwrow, 'hi_bwrow:', hi_bwrow)

    local lsize_obj = LSize:new()

    local frac_list = {}
    for bw = lo_bwrow, hi_bwrow do
        table.insert(frac_list, cal_fraction(bw, bheight))
    end
    log.debug('before frac_list', frac_list)

    frac_list = filter_fraction(frac_list, lsize_obj)
    log.debug('first frac_list:', frac_list)

    frac_list = filter_fraction(frac_list, lsize_obj, aheight + 9)
    log.debug('second frac_list:', frac_list)

    if #frac_list > 0 then
        local fraction = frac_list[1]
        return cal_wrow(fraction, bheight)
    end
end

function M.resetview(wv)
    fn.winrestview(wv)
    -- topline may not be changed sometimes without winline()
    fn.winline()
end

function M.tune_top(winid, topline, lsizes)
    return utils.win_execute(winid, function()
        local i_start, i_end, i_inc, should_continue, len
        local folded_other_lnum

        local lsize_obj = LSize:new()
        if lsizes > 0 then
            i_start, i_end, i_inc = topline - 1, math.max(1, topline - lsizes), -1
            should_continue = function(iter)
                return iter >= i_end
            end
            len = lsizes
            folded_other_lnum = function(i)
                return lsize_obj:foldclosed(i)
            end
        else
            i_start, i_end, i_inc = topline, topline - lsizes - 1, 1
            should_continue = function(iter)
                return iter <= i_end
            end
            len = -lsizes
            folded_other_lnum = function(i)
                return lsize_obj:foldclosed_end(i)
            end
        end

        log.debug(i_start, i_end, i_inc, len)
        log.debug('lsizes:', lsizes)

        local add_fill = lsize_obj:fill_size(topline)
        len = len + (lsizes > 0 and -add_fill or add_fill)
        local lsize_sum = 0
        local i = i_start
        while lsize_sum < len and should_continue(i) do
            log.debug('=====================================================')
            log.debug('i:', i, 'i_end:', i_end)
            local fo_lnum = folded_other_lnum(i)
            if fo_lnum == -1 then
                local lsize = lsize_obj:size(i)
                log.debug('lsize_sum:', lsize_sum, 'lsize:', lsize, 'lnum:', i)
                lsize_sum = lsize_sum + lsize
            else
                log.debug('fo_lnum:', fo_lnum)
                lsize_sum = lsize_sum + 1
                i_end = i_end + fo_lnum - i
                i = fo_lnum
            end
            log.debug('=====================================================')
            topline = i
            i = i + i_inc
        end

        -- extra_off lines is need to be showed near the topline
        local fill
        local extra_off = lsize_sum - len
        log.debug('extra_off:', extra_off, 'len:', len)
        if extra_off > 0 then
            fill = lsize_obj:fill_size(topline)
            if fill < extra_off then
                if lsizes > 0 then
                    topline = topline + 1
                end
            else
                local nofill = lsize_obj:nofill_size(topline)
                fill = lsizes > 0 and fill - extra_off or math.max(0, extra_off - nofill)
            end
        else
            if lsizes < 0 then
                topline = topline + 1
            end
            fill = lsize_obj:fill_size(topline)
        end
        log.debug('topline:', topline, 'fill:', fill)
        return topline, fill
    end)
end

return M
