local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd
local uv = vim.loop

local mgws = require('bqf.magicwin.session')
local wpos = require('bqf.wpos')
local utils = require('bqf.utils')
local log = require('bqf.log')
local mcore = require('bqf.magicwin.core')
local config = require('bqf.config')

local enable

local POS = wpos.POS
local LNUM = {KEEP = 0, UP = 1, DOWN = 2}

local function register_winenter(qwinid)
    local qbufnr = api.nvim_win_get_buf(qwinid)
    cmd(('au BqfMagicWin WinEnter * %s'):format(
        ([[lua require('bqf.magicwin.handler').reset_lnum4wv(%d)]]):format(qbufnr)))
    -- check out whether current window is not a quickfix window.
    -- WinEnter event can't be fired if run quickfix command outside the quickfix window.
    vim.schedule(function()
        M.reset_lnum4wv(qbufnr)
    end)
end

local function guess_bwrow(qwinid, winid)
    log.debug('guess_bwrow start')
    local bwrow = utils.win_execute(winid, function()
        local qf_hei, win_hei = api.nvim_win_get_height(qwinid), api.nvim_win_get_height(winid)
        local line_count = api.nvim_buf_line_count(0)
        local qbufnr = api.nvim_win_get_buf(qwinid)

        -- qf winodw height might be changed by user adds new qf items or navigates history
        -- we need a cache to store previous state
        local aws = mgws.adjacent_win(qbufnr, winid)
        local bheight, aheight = aws.height or qf_hei + win_hei + 1, win_hei
        local bwrow

        local awrow = fn.winline() - 1

        local topline = fn.line('w0')
        if topline == 1 and line_count <= win_hei then
            bwrow = awrow
        else
            bwrow = mcore.evaluate(awrow, aheight, bheight) or awrow
            log.debug('awrow:', awrow, 'aheight:', aheight, 'bheight:', bheight)
            log.debug('bwrow:', bwrow)
            return bwrow
        end
    end)
    log.debug('guess_bwrow end', '\n')
    return bwrow
end

local function reset_win_top(qwinid, winid, qf_pos, bwrow)
    utils.win_execute(winid, function()
        local qbufnr = api.nvim_win_get_buf(qwinid)
        local aws = mgws.adjacent_win(qbufnr, winid)
        local wv = fn.winsaveview()
        local topline, lnum = wv.topline, wv.lnum
        local awrow = fn.winline() - 1
        local delta_lsize = bwrow - awrow

        local qf_hei, win_hei = api.nvim_win_get_height(qwinid), api.nvim_win_get_height(winid)
        local bheight, aheight = aws.height or qf_hei + win_hei + 1, win_hei
        if qf_pos[1] == POS.ABOVE or qf_pos[2] == POS.TOP then
            delta_lsize = delta_lsize - bheight + aheight
        end

        log.debug('before topline:', topline, 'delta_lsize:', delta_lsize)
        local topfill
        topline, topfill = mcore.tune_top(winid, topline, delta_lsize)

        local tune_lnum = LNUM.KEEP
        if delta_lsize > 0 then
            local reminder = aheight - awrow - 1
            if delta_lsize > reminder then
                tune_lnum = LNUM.UP
                -- We change lnum temporarily to make sure that topline will be changed successfully
                lnum = topline
            end
        else
            if -delta_lsize > awrow then
                tune_lnum = LNUM.DOWN
                lnum = topline
            end
        end

        mcore.resetview({topline = topline, topfill = topfill, lnum = lnum})
        local botline = fn.line('w$')
        log.debug('after topline:', topline, 'topfill:', topfill, 'lnum:', lnum, 'tune_lnum:',
            tune_lnum)

        local awv = aws.wv
        local hrtime
        if awv and awv.tune_lnum ~= LNUM.KEEP then
            if awv.tune_lnum == LNUM.UP and wv.lnum <= awv.lnum then
                mcore.resetview({
                    topline = topline,
                    topfill = topfill,
                    lnum = math.min(botline, awv.lnum)
                })
            elseif awv.tune_lnum == LNUM.DOWN and wv.lnum >= awv.lnum then
                mcore.resetview({
                    topline = topline,
                    topfill = topfill,
                    lnum = math.max(topline, awv.lnum)
                })
            end
        else
            wv.topline, wv.topfill = topline, topfill
            awv = wv
            hrtime = uv.hrtime()
            if tune_lnum ~= LNUM.KEEP then
                if tune_lnum == LNUM.UP then
                    mcore.resetview({topline = topline, topfill = topfill, lnum = botline})
                end
                register_winenter(qwinid)
            end
        end

        aws:set({
            height = aheight,
            hrtime = hrtime,
            tune_lnum = tune_lnum,
            wv = awv
        })
        log.debug('aws:', aws)
    end)
end

local function need_revert(qf_pos)
    local rel_pos, abs_pos = unpack(qf_pos)
    return rel_pos == POS.ABOVE or rel_pos == POS.BELOW or abs_pos == POS.TOP or abs_pos ==
               POS.BOTTOM
end

function M.reset_lnum4wv(qbufnr)
    local win_type = fn.win_gettype()
    if win_type == 'popup' or win_type == 'quickfix' or win_type == 'loclist' then
        return
    end

    vim.schedule(function()
        cmd('au! BqfMagicWin WinEnter')
        local qwinid = fn.bufwinid(qbufnr)
        if not utils.is_win_valid(qwinid) then
            return
        end
        for _, winid in ipairs(api.nvim_tabpage_list_wins(0)) do
            local aws = mgws.adjacent_win(qbufnr, winid)
            if aws and aws.wv then
                utils.win_execute(winid, function()
                    local hrtime = aws.hrtime or 0
                    local wv = aws.wv
                    local lnum, col = wv.lnum, wv.col + 1
                    if uv.hrtime() - hrtime > 100000000 then
                        fn.setpos([['']], {0, lnum, col, 0})
                    else
                        api.nvim_win_set_cursor(0, {lnum, col})
                        cmd(('noa norm! %s'):format(aws.tune_lnum == LNUM.UP and 'zb' or 'zt'))
                    end
                end)
                aws.wv.lnum = nil
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

local function revert_opening_wins(qwinid, pwinid, qf_pos, layout_cb)
    if not need_revert(qf_pos) then
        return
    end
    local wfhs = {}
    for _, winid in ipairs(api.nvim_tabpage_list_wins(0)) do
        if vim.wo[winid].winfixheight then
            vim.wo[winid].winfixheight = false
            table.insert(wfhs, winid)
        end
    end
    local bwrows = {}
    keep_context(function()
        for _, winid in ipairs(wpos.find_adjacent_wins(qwinid, pwinid)) do
            if utils.is_win_valid(winid) then
                local f_win_so = utils.scrolloff(winid)
                if f_win_so ~= 0 then
                    -- turn off scrolloff to prepare for guessing bwrow
                    vim.wo[winid].scrolloff = 0
                    cmd(('au BqfMagicWin WinLeave * ++once %s'):format(
                        ([[lua vim.schedule(function() vim.wo[%d].scrolloff = %d end)]]):format(
                            winid, f_win_so)))
                end

                bwrows[winid] = guess_bwrow(qwinid, winid)
            end
        end
    end)
    if type(layout_cb) == 'function' then
        layout_cb()
    end
    for winid, bwrow in pairs(bwrows) do
        reset_win_top(qwinid, winid, qf_pos, bwrow)
    end
    for _, winid in ipairs(wfhs) do
        vim.wo[winid].winfixheight = true
    end
end

local function revert_closing_wins(qwinid, pwinid, qf_pos, layout_cb)
    if not need_revert(qf_pos) then
        return
    end

    local qbufnr = api.nvim_win_get_buf(qwinid)
    for _, winid in ipairs(wpos.find_adjacent_wins(qwinid, pwinid)) do
        local aws = mgws.adjacent_win(qbufnr, winid)
        if aws and aws.wv then
            local wv = utils.win_execute(winid, fn.winsaveview)
            local topline, topfill = wv.topline, wv.topfill
            if qf_pos[1] == POS.ABOVE or qf_pos[2] == POS.TOP then
                topline, topfill = mcore.tune_top(winid, topline,
                    api.nvim_win_get_height(qwinid) + 1 + topfill)
            end
            aws.wv.topline, aws.wv.topfill = topline, topfill
        end
    end

    if type(layout_cb) == 'function' then
        layout_cb()
    end
    for winid, aws in mgws.pairs(qbufnr) do
        if aws and aws.wv then
            log.debug('revert_closing_wins:', aws.wv, '\n')
            utils.win_execute(winid, function()
                mcore.resetview(aws.wv)
            end)
        end
    end
end

local function open(winid, last_winid, layout_cb)
    if not enable then
        return
    end
    local pos = wpos.get_pos(winid, last_winid)
    revert_opening_wins(winid, last_winid, pos, layout_cb)
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

    revert_closing_wins(winid, last_winid, pos, function()
        local cur_winid = api.nvim_get_current_win()

        local wins = vim.tbl_filter(function(id)
            return fn.win_gettype(id) ~= 'popup'
        end, api.nvim_tabpage_list_wins(0))

        if vim.o.equalalways and #wins > 2 then
            -- closing window in other tab or floating window can prevent nvim make windows equal
            -- after closing target window, but in other tab can't run
            -- 'win_enter_ext(wp, false, true, false, true, true)' which will triggers 'WinEnter',
            -- 'BufEnter' and 'CursorMoved' events. Search 'do_autocmd_winclosed' in
            -- src/nvim/window.c for details.
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
    end)

    M.detach(bufnr)
end

function M.attach(winid, last_winid, bufnr, layout_cb)
    winid = winid or api.nvim_get_current_win()
    last_winid = last_winid or fn.win_getid(fn.winnr('#'))
    bufnr = bufnr or api.nvim_win_get_buf(winid)
    open(winid, last_winid, layout_cb)
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
    enable = config.magic_window
end

init()

return M
