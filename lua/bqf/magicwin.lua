local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local qfs = require('bqf.qfsession')
local qfpos = require('bqf.qfpos')
local utils = require('bqf.utils')

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
local function process_sline(fraction, aheight, lnum, lines_size)
    local sline = cal_wrow(fraction, aheight)
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
        local sline = process_sline(info.fraction, height, lnum, lines_size)
        if fn.winline() - 1 == sline then
            table.insert(t, info)
        end
    end
    return t
end

-- If the lnum hasn't been changed, even if the window is resized, the fraction is still a constant.
-- And we can use this feature to find out the possible bwrows until the window height reach 1.
-- Check out 'void scroll_to_fraction(win_T *wp, int prev_height)' in winodw.c for more details.
local function filter_info(tbl_info, lnum, lines_size)
    local function recursion(t_info)
        -- we are in adjacent window
        local height = api.nvim_win_get_height(0)
        if #t_info < 2 or height == 1 then
            return t_info
        else
            cmd('resize -1')
            local filtered = recursion(do_filter(tbl_info, height - 1, lnum, lines_size))
            cmd('resize +1')
            return filtered
        end
    end
    return recursion(tbl_info)
end

-- TODO ugly code.
-- If window height is small, we may encounter multiple table result, increase window to guess result.
local function filter_info_inc(tbl_info, lnum, lines_size, max_hei)
    local function recursion(t_info)
        local height = api.nvim_win_get_height(0)
        if #t_info < 2 or height == max_hei then
            return t_info
        else
            cmd('resize +1')
            if height == api.nvim_win_get_height(0) then
                return t_info
            end
            local filtered = recursion(do_filter(tbl_info, height + 1, lnum, lines_size))
            cmd('resize -1')
            return filtered
        end
    end
    return recursion(tbl_info)
end

local function guess_info(winid, awrow, aheight, bheight, l_bwrow, l_fraction)
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

    local lnum = api.nvim_win_get_cursor(winid)[1]
    local per_l_wid = api.nvim_win_get_width(winid) - utils.gutter_size(winid, lnum)

    local e_fraction = cal_fraction(e_bwrow, bheight)
    local e_sline = cal_wrow(e_fraction, aheight)

    if l_bwrow then
        e_sline = math.max(cal_wrow(l_fraction, aheight), e_sline)
    end

    local lines_size = {}
    -- use 9 as additional compensation
    for i = math.max(1, lnum - e_sline - 9), lnum - 1 do
        lines_size[i] = math.ceil(math.max(fn.virtcol({i, '$'}) - 1, 1) / per_l_wid)
    end

    if l_bwrow and awrow == process_sline(l_fraction, aheight, lnum, lines_size) then
        return l_bwrow, l_fraction
    end

    local tbl_info = {}
    for bwrow = math.max(s_bwrow, 1), e_bwrow do
        table.insert(tbl_info, {bwrow = bwrow, fraction = cal_fraction(bwrow, bheight)})
    end

    local info = filter_info(tbl_info, lnum, lines_size)
    -- print('info:', vim.inspect(info))

    if #info > 1 and s_bwrow == 0 then
        table.insert(info, 1, {bwrow = 0, fraction = cal_fraction(0, bheight)})
    end
    -- up to 9 recursions
    info = filter_info_inc(info, lnum, lines_size, aheight + 9)
    -- print('after info', vim.inspect(info))
    if #info > 0 then
        return info[1].bwrow, info[1].fraction
    end
end

local function lsize2off(winid, lnum_s, lnum_e, revert)
    local len = lnum_e - lnum_s
    if len == 0 then
        return 0
    end
    local per_l_wid = api.nvim_win_get_width(winid) - utils.gutter_size(winid)
    local iter_start, iter_end, iter_step
    if revert then
        iter_start, iter_end, iter_step = lnum_e, lnum_s, -1
    else
        iter_start, iter_end, iter_step = lnum_s, lnum_e, 1
    end
    local offset, l_size_sum = 0, 0
    for i = iter_start, iter_end, iter_step do
        local per_l_size = math.ceil(math.max(fn.virtcol({i, '$'}) - 1, 1) / per_l_wid)
        -- -- print('============================================')
        -- -- print('l_size_sum:', l_size_sum, 'per_l_size:', per_l_size, 'lnum:', i)
        -- -- print('============================================')
        l_size_sum = l_size_sum + per_l_size
        offset = offset + 1
        if l_size_sum > len then
            return offset
        end
    end
    error('It is impossible to go here')
end

local function resetview(topline)
    fn.winrestview({topline = topline})
    -- topline seemly can't be changed sometimes without winline()
    fn.winline()
end

local function tune_topline(winid, topline, l_size)
    if not vim.wo[winid].wrap or l_size == 0 then
        return topline - l_size
    end
    -- print('before topline:', topline, 'l_size:', l_size)
    local line_offset
    if l_size > 0 then
        local lnum_s = math.max(1, topline - l_size)
        local lnum_e = topline - 1
        line_offset = lsize2off(winid, lnum_s, lnum_e, true)
    else
        local lnum_s = topline
        local lnum_e = topline - l_size - 1
        line_offset = -lsize2off(winid, lnum_s, lnum_e, false)
    end
    -- print('after topline:', topline - line_offset, 'line_offset:', line_offset)
    return math.max(1, topline - line_offset)
end

local function do_enter_revert(qf_winid, winid, qf_pos)
    -- TODO upstream bug
    -- local f_win_so = vim.wo[winid].scrolloff
    -- return a big number like '1.4014575443238e+14' if window option is absent
    -- Use getwinvar to workaround
    local f_win_so = fn.getwinvar(winid, '&scrolloff')
    if f_win_so ~= 0 then
        -- turn off scrolloff and then show us true wrow
        vim.wo[winid].scrolloff = 0
        cmd(string.format('au Bqf WinLeave * ++once %s',
            string.format([[lua vim.wo[%d].scrolloff = %d]], winid, f_win_so)))
    end

    utils.win_execute(winid, function()
        local qf_hei, win_hei = api.nvim_win_get_height(qf_winid), api.nvim_win_get_height(winid)
        local topline = fn.line('w0')
        local line_count = api.nvim_buf_line_count(0)

        -- qf winodw height might be changed by user adds new qf items or navigates history
        -- we need a cache to store previous state
        qfs[qf_winid].magicwin = qfs[qf_winid].magicwin or {}
        local mgw = qfs[qf_winid].magicwin[winid] or {}
        local def_hei = qf_hei + win_hei + 1
        local bheight, aheight = mgw.aheight or def_hei, win_hei
        local l_bwrow, l_fraction = mgw.bwrow, mgw.fraction
        local bwrow, fraction, l_size

        if topline == 1 and line_count <= win_hei then
            l_size = 0
        else
            local awrow = fn.winline() - 1
            if f_win_so >= awrow and awrow > 0 and win_hei > 1 then
                -- get the true wrow
                cmd('resize -1 | resize +1')
                awrow = fn.winline() - 1
                topline = fn.line('w0')
            end

            -- print('awrow:', awrow, 'aheight:', aheight, 'bheight:', bheight)
            -- print('l_bwrow:', l_bwrow, 'l_fraction:', l_fraction)
            bwrow, fraction = guess_info(winid, awrow, aheight, bheight, l_bwrow, l_fraction)
            if not bwrow then
                return
            end
            l_size = bwrow - awrow
        end

        if qf_pos[1] == 'above' or qf_pos[2] == 'top' then
            if l_bwrow == bwrow and l_fraction == fraction then
                bheight = mgw.bheight or def_hei
            end
            l_size = l_size - bheight + aheight
        end

        if l_size == 0 then
            return
        end

        resetview(tune_topline(winid, topline, l_size))

        mgw.bwrow, mgw.fraction, mgw.bheight, mgw.aheight = bwrow, fraction, bheight, aheight
        qfs[qf_winid].magicwin[winid] = mgw
    end)
end

local function prefetch_close_revert_topline(qf_winid, winid, qf_pos)
    local topline
    local ok, msg = pcall(fn.getwininfo, winid)
    if ok then
        topline = msg[1].topline
        if qf_pos[1] == 'above' or qf_pos[2] == 'top' then
            topline = tune_topline(winid, topline, api.nvim_win_get_height(qf_winid) + 1)
        end
    end
    return topline
end

local function need_revert(qf_pos)
    local rel_pos, abs_pos = unpack(qf_pos)
    return rel_pos == 'above' or rel_pos == 'below' or abs_pos == 'top' or abs_pos == 'bottom'
end

function M.revert_enter_adjacent_wins(qf_winid, file_winid, qf_pos)
    if need_revert(qf_pos) then
        for _, winid in ipairs(qfpos.find_adjacent_wins(qf_winid, file_winid)) do
            if api.nvim_win_is_valid(winid) then
                do_enter_revert(qf_winid, winid, qf_pos)
            end
        end
    end
end

function M.revert_close_adjacent_wins(qf_winid, file_winid, qf_pos)
    local defer_data = {}
    if need_revert(qf_pos) then
        for _, winid in ipairs(qfpos.find_adjacent_wins(qf_winid, file_winid)) do
            local topline = prefetch_close_revert_topline(qf_winid, winid, qf_pos)
            if topline then
                table.insert(defer_data, {winid = winid, topline = topline})
            end
        end
    end

    return function()
        for _, info in pairs(defer_data) do
            local winid, topline = info.winid, info.topline
            utils.win_execute(winid, function()
                resetview(topline)
            end)
        end
    end
end

return M
