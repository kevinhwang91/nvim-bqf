local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd
local uv = vim.loop

local mgws = require('bqf.magicwin.session')
local wpos = require('bqf.wpos')
local POS
local utils = require('bqf.utils')
local log = require('bqf.log')
local mcore = require('bqf.magicwin.core')
local config = require('bqf.config')

local enable

local LNUM = {KEEP = 0, UP = 1, DOWN = 2}

local function register_winenter(qwinid)
    local qbufnr = api.nvim_win_get_buf(qwinid)
    cmd(('au BqfMagicWin WinEnter * ++once %s'):format(
        ([[lua require('bqf.magicwin.handler').clear_winview(%d)]]):format(qbufnr)))
end

local function do_enter_revert(qwinid, winid, qf_pos)
    log.debug('do_enter_revert start')
    -- TODO upstream bug
    -- local f_win_so = vim.wo[winid].scrolloff
    -- return a big number like '1.4014575443238e+14' if window option is absent
    -- Use getwinvar to workaround
    local f_win_so = fn.getwinvar(winid, '&scrolloff')
    if f_win_so ~= 0 then
        -- turn off scrolloff and then show us true wrow
        vim.wo[winid].scrolloff = 0
        cmd(('au BqfMagicWin WinLeave * ++once %s'):format(
            ([[lua vim.wo[%d].scrolloff = %d]]):format(winid, f_win_so)))
    end

    utils.win_execute(winid, function()
        local qf_hei, win_hei = api.nvim_win_get_height(qwinid), api.nvim_win_get_height(winid)
        local wv = fn.winsaveview()
        local topline, lnum, col = wv.topline, wv.lnum, wv.col + 1
        local line_count = api.nvim_buf_line_count(0)
        local qbufnr = api.nvim_win_get_buf(qwinid)

        -- qf winodw height might be changed by user adds new qf items or navigates history
        -- we need a cache to store previous state
        local aws = mgws.adjacent_win(qbufnr, winid)
        local def_hei = qf_hei + win_hei + 1
        local bheight, aheight = aws.aheight or def_hei, win_hei
        local lbwrow, lfraction = aws.bwrow, aws.fraction
        local bwrow, fraction, delta_lsize

        local awrow = fn.winline() - 1

        if topline == 1 and line_count <= win_hei then
            delta_lsize = 0
        else
            if f_win_so >= awrow and awrow > 0 and win_hei > 1 then
                -- get the true wrow
                cmd('resize -1 | resize +1')
                awrow = fn.winline() - 1
                topline = fn.line('w0')
            end

            fraction, bwrow = mcore.evaluate(winid, {lnum, col}, awrow, aheight, bheight, lbwrow,
                lfraction)
            log.debug('awrow:', awrow, 'aheight:', aheight, 'bheight:', bheight)
            log.debug('lbwrow:', lbwrow, 'lfraction:', lfraction)
            log.debug('fraction:', fraction)

            if not fraction then
                return
            end
            log.debug('bwrow:', bwrow)
            delta_lsize = bwrow - awrow
        end

        if qf_pos[1] == POS.ABOVE or qf_pos[2] == POS.TOP then
            delta_lsize = delta_lsize - bheight + aheight
        end

        if delta_lsize == 0 then
            return
        end

        log.debug('before topline:', topline, 'delta_lsize:', delta_lsize)

        local line_offset = mcore.tune_line(winid, topline, delta_lsize)
        topline = math.max(1, topline - line_offset)
        local tune_lnum = LNUM.KEEP
        if delta_lsize > 0 then
            local reminder = aheight - awrow - 1
            if delta_lsize > reminder then
                tune_lnum = LNUM.UP
                lnum = topline
            end
        else
            if -delta_lsize > awrow then
                tune_lnum = LNUM.DOWN
                lnum = topline
            end
        end

        mcore.resetview(topline, lnum)

        local wv_info = aws.wv
        if tune_lnum ~= LNUM.KEEP then
            wv_info = wv_info or {wv.lnum, wv.col, wv.curswant, uv.hrtime(), tune_lnum}
            if tune_lnum == LNUM.UP then
                mcore.resetview(topline, fn.line('w$'))
            end
            log.debug('wv_info:', wv_info)
            register_winenter(qwinid)
        end

        aws:set({
            bwrow = bwrow,
            bheight = bheight,
            aheight = aheight,
            fraction = fraction,
            wv = wv_info
        })
    end)

    log.debug('do_enter_revert end', '\n')
end

local function prefetch_close_revert_topline(qwinid, winid, qf_pos)
    local topline
    local ok, msg = pcall(fn.getwininfo, winid)
    if ok then
        topline = msg[1].topline
        if qf_pos[1] == POS.ABOVE or qf_pos[2] == POS.TOP then
            topline = topline - mcore.tune_line(winid, topline, api.nvim_win_get_height(qwinid) + 1)
        end
    end
    return topline
end

local function need_revert(qf_pos)
    local rel_pos, abs_pos = unpack(qf_pos)
    return rel_pos == POS.ABOVE or rel_pos == POS.BELOW or abs_pos == POS.TOP or abs_pos ==
               POS.BOTTOM
end

function M.clear_winview(qbufnr)
    vim.schedule(function()
        local qwinid = fn.bufwinid(qbufnr)
        if utils.is_win_valid(qwinid) then
            for _, winid in ipairs(api.nvim_tabpage_list_wins(0)) do
                local aws = mgws.adjacent_win(qbufnr, winid)
                if aws and aws.wv then
                    local lnum, col, _, hrtime, tune_lnum = unpack(aws.wv)
                    utils.win_execute(winid, function()
                        if uv.hrtime() - hrtime > 100000000 then
                            fn.setpos([['']], {0, lnum, col + 1, 0})
                        else
                            api.nvim_win_set_cursor(0, {lnum, col})
                            if tune_lnum == LNUM.UP then
                                cmd('noa norm! zb')
                            else
                                cmd('noa norm! zt')
                            end
                        end
                    end)
                    aws.wv = nil
                end
            end
        end
    end)
end

local function keep_context(func)
    local ww_bak = vim.o.winwidth
    local wmw_bak = vim.o.winminwidth
    local ww_need_bak = ww_bak ~= 1
    local wmw_need_bak = wmw_bak > 1
    if wmw_need_bak then
        vim.o.winminwidth = 1
    end
    if ww_need_bak then
        vim.o.winwidth = 1
    end

    local last_winnr = fn.winnr('#')

    pcall(func)

    if last_winnr ~= fn.winnr('#') then
        local last_winid = fn.win_getid(last_winnr)
        local cur_winid = api.nvim_get_current_win()
        local noa_set_win = 'noa call nvim_set_current_win(%d)'
        cmd((noa_set_win):format(last_winid))
        cmd((noa_set_win):format(cur_winid))
    end

    if ww_need_bak then
        vim.o.winwidth = ww_bak
    end
    if wmw_need_bak then
        vim.o.winminwidth = wmw_bak
    end
end

local function revert_enter_adjacent_wins(qwinid, pwinid, qf_pos)
    if need_revert(qf_pos) then
        local wfh_tbl = {}
        for _, winid in ipairs(api.nvim_tabpage_list_wins(0)) do
            if vim.wo[winid].winfixheight then
                vim.wo[winid].winfixheight = false
                table.insert(wfh_tbl, winid)
            end
        end
        keep_context(function()
            for _, winid in ipairs(wpos.find_adjacent_wins(qwinid, pwinid)) do
                if utils.is_win_valid(winid) then
                    do_enter_revert(qwinid, winid, qf_pos)
                end
            end
        end)
        for _, winid in ipairs(wfh_tbl) do
            vim.wo[winid].winfixheight = true
        end
    end
end

local function revert_close_adjacent_wins(qwinid, pwinid, qf_pos)
    if need_revert(qf_pos) then
        local defer_data = {}
        local qbufnr = api.nvim_win_get_buf(qwinid)
        local cur_bufnr = api.nvim_get_current_buf()
        for _, winid in ipairs(wpos.find_adjacent_wins(qwinid, pwinid)) do
            local topline = prefetch_close_revert_topline(qwinid, winid, qf_pos)
            if topline then
                local info = {winid = winid, topline = topline}
                local aws = mgws.adjacent_win(qbufnr, winid)
                if aws and aws.wv and cur_bufnr ~= api.nvim_win_get_buf(winid) then
                    info.lnum, info.col, info.curswant = unpack(aws.wv)
                end
                table.insert(defer_data, info)
            end
        end

        return #defer_data > 0 and function()
            keep_context(function()
                for _, info in ipairs(defer_data) do
                    local winid, topline, lnum, col, curswant = info.winid, info.topline, info.lnum,
                        info.col, info.curswant
                    log.debug('revert_callback:', info, '\n')
                    utils.win_execute(winid, function()
                        mcore.resetview(topline, lnum, col, curswant)
                    end)
                end
            end)
        end or nil
    end
end

local function open(winid, last_winid)
    if not enable then
        return
    end
    local pos = wpos.get_pos(winid, last_winid)
    revert_enter_adjacent_wins(winid, last_winid, pos)
end

function M.close(winid, last_winid, bufnr)
    if not utils.is_win_valid(winid) or not enable then
        return
    end

    local pos = wpos.get_pos(winid, last_winid)
    local winnr = fn.win_id2win(winid)
    local win_j, win_l
    utils.win_execute(winid, function()
        win_j, win_l = fn.winnr('j'), fn.winnr('l')
    end)

    local whei, wwid, phei, pwid
    local rel_pos = pos[1]
    if rel_pos == POS.RIGHT and win_l ~= winnr then
        wwid, pwid = api.nvim_win_get_width(winid), api.nvim_win_get_width(last_winid)
    elseif rel_pos == POS.BELOW and win_j ~= winnr then
        whei, phei = api.nvim_win_get_height(winid), api.nvim_win_get_height(last_winid)
    end

    local wmagic_defer_cb = revert_close_adjacent_wins(winid, last_winid, pos)

    local cur_winid = api.nvim_get_current_win()

    local wins = vim.tbl_filter(function(id)
        return fn.win_gettype(id) ~= 'popup'
    end, api.nvim_tabpage_list_wins(0))

    if vim.o.equalalways and #wins > 2 then
        -- closing window in other tab or floating window can prevent nvim make windows equal
        -- after closing target window, but in other tab can't run
        -- 'win_enter_ext(wp, false, true, false, true, true)' which will triggers 'WinEnter', 'BufEnter'
        -- and 'CursorMoved' events. Search 'do_autocmd_winclosed' in src/nvim/window.c for details.
        local scratch = api.nvim_create_buf(false, true)

        local ei_bak = vim.o.ei
        vim.o.ei = 'all'
        local ok = pcall(api.nvim_open_win, scratch, true, {
            relative = 'win',
            width = 1,
            height = 1,
            row = 0,
            col = 0,
            style = 'minimal',
            noautocmd = true
        })
        vim.o.ei = ei_bak
        if ok then
            api.nvim_win_close(winid, false)
            api.nvim_buf_delete(scratch, {})
        end
    else
        api.nvim_win_close(winid, false)
    end

    if utils.is_win_valid(last_winid) and cur_winid == winid then
        api.nvim_set_current_win(last_winid)
    end

    if rel_pos == POS.RIGHT and win_l ~= winnr then
        api.nvim_win_set_width(last_winid, wwid + pwid + 1)
    elseif rel_pos == POS.BELOW and win_j ~= winnr then
        api.nvim_win_set_height(last_winid, whei + phei + 1)
    end

    if wmagic_defer_cb then
        wmagic_defer_cb()
    end
    M.detach(bufnr)
end

function M.attach(winid, last_winid, bufnr)
    winid = winid or api.nvim_get_current_win()
    last_winid = last_winid or fn.win_getid(fn.winnr('#'))
    bufnr = bufnr or api.nvim_win_get_buf(winid)
    open(winid, last_winid)
    cmd(([[
        aug BqfMagicWin
            au! * <buffer>
            au WinClosed <buffer> ++nested lua require('bqf.magicwin.handler').close(%d, %d, %d)
        aug END
    ]]):format(winid, last_winid, bufnr))
end

function M.detach(bufnr)
    cmd(([[au! BqfMagicWin * <buffer=%d>]]):format(bufnr))
    mgws.clean(bufnr)
end

local function init()
    cmd([[
        aug BqfMagicWin
            au!
        aug END
    ]])
    POS = wpos.POS
    enable = config.magic_window
end

init()

return M
