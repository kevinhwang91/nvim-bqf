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
local function evaluate_sline(fraction, height, lnum, lines_size)
    local sline = cal_wrow(fraction, height)
    local i = sline
    for j = lnum - 1, math.max(1, lnum - sline), -1 do
        i = i - lines_size[j]
        if i <= 0 then
            if i < 0 then
                sline = sline - lines_size[j] - i
            end
            break
        end
    end
    return sline
end

local function do_filter(tbl_info, height, lnum, lines_size)
    local t = {}
    for _, info in ipairs(tbl_info) do
        local sline = evaluate_sline(info, height, lnum, lines_size)
        if fn.winline() - 1 == sline then
            table.insert(t, info)
        end
    end
    return t
end

-- If the lnum hasn't been changed, even if the window is resized, the fraction is still a constant.
-- And we can use this feature to find out the possible fraction with changing window height.
-- Check out 'void scroll_to_fraction(win_T *wp, int prev_height)' in winodw.c for more details.
local function filter_fraction(tbl_info, lnum, lines_size, max_hei)
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

    while #tbl_info > 1 do
        if h <= min_hei or h > max_hei then
            break
        end
        h = asc and h + 1 or h - 1
        api.nvim_win_set_height(0, h)
        if asc and api.nvim_win_get_height(0) ~= h then
            break
        end
        tbl_info = do_filter(tbl_info, h, lnum, lines_size)
    end
    api.nvim_win_set_height(0, height)
    return tbl_info
end

function M.cal_wrow(fraction, height)
    return cal_wrow(fraction, height)
end

function M.evaluate_fraction(winid, lnum, awrow, aheight, bheight, lbwrow, lfraction)
    -- s_bwrow: the minimum bwrow value
    -- Below formula we can derive from the known conditions
    local s_bwrow = math.ceil(awrow * bheight / aheight - 0.5)
    if s_bwrow < 0 or bheight == aheight then
        return
    end
    -- e_bwrow: the maximum bwrow value
    -- There are not enough conditions to derive e_bwrow, so we have to figure it out by guessing,
    -- and confirm the range of bwrow.
    -- It seems that 10 as a minimum and 1.2 as a scale is good to balance performance and accuracy
    local e_bwrow = math.max(10, math.ceil(awrow * 1.2 * bheight / aheight - 0.25))

    local per_lwidth = api.nvim_win_get_width(winid) - utils.textoff(winid)

    local e_fraction = cal_fraction(e_bwrow, bheight)
    local e_sline = cal_wrow(e_fraction, aheight)

    if lbwrow then
        e_sline = math.max(cal_wrow(lfraction, aheight), e_sline)
    end

    local lines_size = {}
    local wrap = vim.wo[winid].wrap
    -- use 9 as additional compensation
    for i = math.max(1, lnum - e_sline - 9), lnum - 1 do
        lines_size[i] = wrap and math.ceil(math.max(fn.virtcol({i, '$'}) - 1, 1) / per_lwidth) or 1
    end

    if lbwrow and awrow == evaluate_sline(lfraction, aheight, lnum, lines_size) then
        return lfraction
    end

    local t_frac = {}
    for bw = s_bwrow, e_bwrow do
        table.insert(t_frac, cal_fraction(bw, bheight))
    end
    log.debug('before t_frac', t_frac)

    t_frac = filter_fraction(t_frac, lnum, lines_size)

    log.debug('first t_frac:', t_frac)

    t_frac = filter_fraction(t_frac, lnum, lines_size, aheight + 9)

    log.debug('second t_frac:', t_frac)

    if #t_frac > 0 then
        return t_frac[1]
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

    if vim.wo[winid].foldenable then
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
