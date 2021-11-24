local M = {}
local api = vim.api
local fn = vim.fn

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
local function evaluate_wrow(fraction, height, lines_size)
    local wv = fn.winsaveview()
    local lnum = wv.lnum
    local wrow = cal_wrow(fraction, height)
    local line_size = lines_size[0] - 1
    local sline = wrow - line_size
    log.debug('wrow:', wrow, 'sline:', sline)
    if sline >= 0 then
        local rows = lines_size[lnum]
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
            lnum = lnum - 1
            if lnum == wv.topline then
                line_size = lines_size[lnum] + wv.topfill
            else
                line_size = lines_size[lnum]
            end
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

local function do_filter(frac_list, height, lines_size)
    local t = {}
    local true_wrow = fn.winline() - 1
    log.debug('true_wrow:', true_wrow)
    for _, frac in ipairs(frac_list) do
        local wrow = evaluate_wrow(frac, height, lines_size)
        if true_wrow == wrow then
            table.insert(t, frac)
        end
    end
    return t
end

-- If the lnum hasn't been changed, even if the window is resized, the fraction is still a constant.
-- And we can use this feature to find out the possible fraction with changing window height.
-- Check out 'void scroll_to_fraction(win_T *wp, int prev_height)' in winodw.c for more details.
local function filter_fraction(frac_list, lines_size, max_hei)
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

    while #frac_list > 1 and h >= min_hei and h <= max_hei do
        frac_list = do_filter(frac_list, h, lines_size)
        h = asc and h + 1 or h - 1
        api.nvim_win_set_height(0, h)
        if asc and api.nvim_win_get_height(0) ~= h then
            break
        end
    end

    if h ~= height then
        api.nvim_win_set_height(0, height)
    end
    return frac_list
end

-- TODO line_size can't handle virt_lines and diff filter
local function line_size(expr, per_lwidth)
    return math.ceil(math.max(fn.virtcol(expr) - 1, 1) / per_lwidth)
end

function M.evaluate(winid, pos, awrow, aheight, bheight, lbwrow, lfraction)
    -- s_bwrow: the minimum bwrow value
    -- Below formula we can derive from the known conditions
    local s_bwrow = math.ceil(awrow * bheight / aheight - 0.5)
    if s_bwrow < 0 or bheight == aheight then
        return
    end
    -- e_bwrow: the maximum bwrow value
    -- There are not enough conditions to derive e_bwrow, so we have to figure it out by
    -- guessing, and confirm the range of bwrow. It seems that s_bwrow plug 5 as a minimum and
    -- 1.2 as a scale is good to balance performance and accuracy
    local e_bwrow = math.max(s_bwrow + 5, math.ceil(awrow * 1.2 * bheight / aheight - 0.25))

    local per_lwidth = api.nvim_win_get_width(winid) - utils.textoff(winid)
    local wrap = vim.wo[winid].wrap
    -- current line number size may greater than 1, must be consider its value after wrappered, use
    -- 0 as index in lines_size
    local lines_size = setmetatable({}, {
        __index = function(tbl, i)
            if i == 0 then
                rawset(tbl, i, wrap and line_size(pos, per_lwidth) or 1)
            else
                rawset(tbl, i, wrap and line_size({i, '$'}, per_lwidth) or 1)
            end
            return tbl[i]
        end
    })

    if lbwrow and awrow == evaluate_wrow(lfraction, aheight, lines_size) then
        return lfraction, awrow
    end

    local frac_list = {}
    for bw = s_bwrow, e_bwrow do
        table.insert(frac_list, cal_fraction(bw, bheight))
    end
    log.debug('before frac_list', frac_list)

    frac_list = filter_fraction(frac_list, lines_size)

    log.debug('first frac_list:', frac_list)

    frac_list = filter_fraction(frac_list, lines_size, aheight + 9)

    log.debug('second frac_list:', frac_list)

    if #frac_list > 0 then
        local fraction = frac_list[1]
        return fraction, evaluate_wrow(fraction, bheight, lines_size)
    end
end

function M.resetview(topline, lnum, col, curswant)
    fn.winrestview({topline = topline, lnum = lnum, col = col, curswant = curswant})
    -- topline may not be changed sometimes without winline()
    fn.winline()
end

function M.tune_line(winid, topline, lsizes)
    if not vim.wo[winid].wrap or lsizes == 0 then
        return lsizes
    end

    log.debug('lsizes:', lsizes)

    local i_start, i_end, i_inc, should_continue, len
    local folded_other_lnum
    local function neg_one(i)
        local _ = i
        return -1
    end

    if lsizes > 0 then
        i_start, i_end, i_inc = topline - 1, math.max(1, topline - lsizes), -1
        should_continue = function(iter)
            return iter >= i_end
        end
        len = lsizes
        folded_other_lnum = fn.foldclosed
    else
        i_start, i_end, i_inc = topline, topline - lsizes - 1, 1
        should_continue = function(iter)
            return iter <= i_end
        end
        len = -lsizes
        folded_other_lnum = fn.foldclosedend
    end

    if not vim.wo[winid].foldenable then
        folded_other_lnum = neg_one
    end
    log.debug(i_start, i_end, i_inc, len)

    return utils.win_execute(winid, function()
        local per_lwidth = api.nvim_win_get_width(winid) - utils.textoff(winid)
        local loff, lsize_sum = 0, 0
        local i = i_start
        while should_continue(i) do
            log.debug('=====================================================')
            log.debug('i:', i, 'i_end:', i_end)
            local fo_lnum = folded_other_lnum(i)
            if fo_lnum == -1 then
                local per_l_size = math.ceil(math.max(fn.virtcol({i, '$'}) - 1, 1) / per_lwidth)
                log.debug('lsize_sum:', lsize_sum, 'per_l_size:', per_l_size, 'lnum:', i)
                lsize_sum = lsize_sum + per_l_size
                loff = loff + 1
            else
                log.debug('fo_lnum:', fo_lnum)
                lsize_sum = lsize_sum + 1
                loff = loff + math.abs(fo_lnum - i) + 1
                i_end = i_end + fo_lnum - i
                i = fo_lnum
            end
            log.debug('loff:', loff)
            log.debug('=====================================================')
            i = i + i_inc
            if lsize_sum >= len then
                break
            end
        end
        loff = lsizes > 0 and loff or -loff
        log.debug('line_offset:', loff)
        return loff
    end)
end

return M
