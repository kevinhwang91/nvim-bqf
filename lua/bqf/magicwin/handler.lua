---@class BqfMagicWinHandler
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

local function registerWinEnter(qwinid)
    local qbufnr = api.nvim_win_get_buf(qwinid)
    cmd(('au BqfMagicWin WinEnter * %s'):format(
        ([[lua require('bqf.magicwin.handler').resetWinView(%d)]]):format(qbufnr)))
    -- check out whether current window is not a quickfix window.
    -- WinEnter event can't be fired if run quickfix command outside the quickfix window.
    vim.schedule(function()
        M.resetWinView(qbufnr)
    end)
end

local function guessBwrow(qwinid, winid)
    log.debug('guessBwrow start')
    local bwrow = utils.winExecute(winid, function()
        local qfHeight, winHeight = api.nvim_win_get_height(qwinid), api.nvim_win_get_height(winid)
        local lineCount = api.nvim_buf_line_count(0)
        local qbufnr = api.nvim_win_get_buf(qwinid)

        -- qf window height might be changed by user adds new qf items or navigates history
        -- we need a cache to store previous state
        local aws = mgws:adjacentWin(qbufnr, winid)
        local bheight, aheight = aws.height or qfHeight + winHeight + 1, winHeight
        local bwrow

        local awrow = fn.winline() - 1

        local topline = fn.line('w0')
        if topline == 1 and lineCount <= winHeight then
            bwrow = awrow
        else
            bwrow = mcore.evaluate(awrow, aheight, bheight) or awrow
            log.debug('awrow:', awrow, 'aheight:', aheight, 'bheight:', bheight)
            log.debug('bwrow:', bwrow)
        end
        return bwrow
    end)
    log.debug('guessBwrow end', '\n')
    return bwrow
end

local function resetWinTop(qwinid, winid, qfPos, bwrow)
    utils.winExecute(winid, function()
        local qbufnr = api.nvim_win_get_buf(qwinid)
        local aws = mgws:adjacentWin(qbufnr, winid)
        local winView = fn.winsaveview()
        local topline, lnum = winView.topline, winView.lnum
        local awrow = fn.winline() - 1
        local deltaLineSize = bwrow - awrow

        local qfHeight, winHeight = api.nvim_win_get_height(qwinid), api.nvim_win_get_height(winid)
        local bheight, aheight = aws.height or qfHeight + winHeight + 1, winHeight
        if qfPos[1] == POS.ABOVE or qfPos[2] == POS.TOP then
            -- botline may be greater than real because one line not always one size
            local botline = fn.line('w$')
            deltaLineSize = deltaLineSize - math.min(bheight - aheight, botline - 1)
        end

        log.debug('before topline:', topline, 'deltaLsize:', deltaLineSize)
        local topfill
        topline, topfill = mcore.tuneTop(winid, topline, deltaLineSize)

        local tuneLnum = LNUM.KEEP
        if deltaLineSize > 0 then
            local reminder = aheight - awrow - 1
            if deltaLineSize > reminder then
                tuneLnum = LNUM.UP
                -- We change lnum temporarily to make sure that topline will be changed successfully
                lnum = topline
            end
        else
            if -deltaLineSize > awrow then
                tuneLnum = LNUM.DOWN
                lnum = topline
            end
        end

        mcore.resetView({topline = topline, topfill = topfill, lnum = lnum})
        local botline = fn.line('w$')
        log.debug('after topline:', topline, 'topfill:', topfill, 'lnum:', lnum, 'tuneLnum:', tuneLnum)
        log.debug('botline:', botline)

        local awsWinView = aws.winView
        log.debug('adjacent winview:', awsWinView)
        local hrtime
        if awsWinView and not vim.tbl_isempty(awsWinView) and aws.tuneLnum ~= LNUM.KEEP then
            if aws.tuneLnum == LNUM.UP and winView.lnum <= awsWinView.lnum then
                mcore.resetView({
                    topline = topline,
                    topfill = topfill,
                    lnum = math.min(botline, awsWinView.lnum)
                })
            elseif aws.tuneLnum == LNUM.DOWN and winView.lnum >= awsWinView.lnum then
                mcore.resetView({
                    topline = topline,
                    topfill = topfill,
                    lnum = math.max(topline, awsWinView.lnum)
                })
            end
        else
            winView.topline, winView.topfill = topline, topfill
            awsWinView = winView
            hrtime = uv.hrtime()
            if tuneLnum ~= LNUM.KEEP then
                if tuneLnum == LNUM.UP then
                    mcore.resetView({topline = topline, topfill = topfill, lnum = botline})
                end
                registerWinEnter(qwinid)
            end
        end

        aws:set({height = aheight, hrtime = hrtime, tuneLnum = tuneLnum, winView = awsWinView})
        log.debug('adjacent window session:', aws)
    end)
end

local function needRevert(qfPos)
    local relPos, absPos = unpack(qfPos)
    return relPos == POS.ABOVE or relPos == POS.BELOW or absPos == POS.TOP or absPos == POS.BOTTOM
end

---
---@param qbufnr number
function M.resetWinView(qbufnr)
    local qwinid = fn.bufwinid(qbufnr)
    if qwinid == api.nvim_get_current_win() then
        return
    else
        local winType = fn.win_gettype()
        if winType == 'popup' or winType == 'quickfix' or winType == 'loclist' then
            return
        end
    end

    vim.schedule(function()
        cmd('au! BqfMagicWin WinEnter')
        if not utils.isWinValid(qwinid) then
            return
        end
        for _, winid in ipairs(api.nvim_tabpage_list_wins(0)) do
            local aws = mgws:adjacentWin(qbufnr, winid)
            if aws and aws.winView then
                utils.winExecute(winid, function()
                    local hrtime = aws.hrtime or 0
                    local winView = aws.winView
                    local lnum, col = winView.lnum, winView.col + 1
                    if uv.hrtime() - hrtime > 100000000 then
                        fn.setpos([['']], {0, lnum, col, 0})
                    else
                        api.nvim_win_set_cursor(0, {lnum, col})
                        cmd(('noa norm! %s'):format(aws.tuneLnum == LNUM.UP and 'zb' or 'zt'))
                    end
                end)
                aws.winView = {}
            end
        end
    end)
end

local function keepContext(func)
    local winWidthBak = vim.o.winwidth
    local winMinWidthBak = vim.o.winminwidth
    local winWidthNeedBak = winWidthBak ~= 1
    local winMinWidthNeedBak = winMinWidthBak > 1
    if winMinWidthNeedBak then
        vim.o.winminwidth = 1
    end
    if winWidthNeedBak then
        vim.o.winwidth = 1
    end

    local lastWinNr = fn.winnr('#')

    pcall(func)

    if lastWinNr ~= fn.winnr('#') then
        local lastWinid = fn.win_getid(lastWinNr)
        local curWinid = api.nvim_get_current_win()
        local noaSetWin = 'noa call nvim_set_current_win(%d)'
        cmd((noaSetWin):format(lastWinid))
        cmd((noaSetWin):format(curWinid))
    end

    if winWidthNeedBak then
        vim.o.winwidth = winWidthBak
    end
    if winMinWidthNeedBak then
        vim.o.winminwidth = winMinWidthBak
    end
end

local function revertOpeningWins(qwinid, pwinid, qfPos, layoutCallback)
    if not needRevert(qfPos) then
        return
    end
    local wfhList = {}
    for _, winid in ipairs(api.nvim_tabpage_list_wins(0)) do
        if vim.wo[winid].winfixheight then
            vim.wo[winid].winfixheight = false
            table.insert(wfhList, winid)
        end
    end
    local bwrows = {}
    keepContext(function()
        for _, winid in ipairs(wpos.findAdjacentWins(qwinid, pwinid)) do
            if utils.isWinValid(winid) then
                local scrollOff = utils.scrolloff(winid)
                if scrollOff ~= 0 then
                    -- turn off scrolloff to prepare for guessing bwrow
                    vim.wo[winid].scrolloff = 0
                    cmd(('au BqfMagicWin WinLeave * ++once %s')
                        :format(([[lua vim.schedule(function() vim.wo[%d].scrolloff = %d end)]])
                            :format(winid, scrollOff)))
                end

                bwrows[winid] = guessBwrow(qwinid, winid)
            end
        end
    end)
    if type(layoutCallback) == 'function' then
        layoutCallback()
    end
    for winid, bwrow in pairs(bwrows) do
        resetWinTop(qwinid, winid, qfPos, bwrow)
    end
    for _, winid in ipairs(wfhList) do
        vim.wo[winid].winfixheight = true
    end
end

local function revertClosingWins(qwinid, pwinid, qfPos, layoutCallback)
    if not needRevert(qfPos) then
        return
    end

    local qbufnr = api.nvim_win_get_buf(qwinid)
    for _, winid in ipairs(wpos.findAdjacentWins(qwinid, pwinid)) do
        local aws = mgws:adjacentWin(qbufnr, winid)
        if aws and aws.winView then
            local winView = utils.winExecute(winid, fn.winsaveview)
            if aws.tuneLnum == LNUM.KEEP then
                aws.winView = {}
            end
            local topline, topfill = winView.topline, winView.topfill
            if qfPos[1] == POS.ABOVE or qfPos[2] == POS.TOP then
                topline, topfill = mcore.tuneTop(winid, topline,
                                                 api.nvim_win_get_height(qwinid) + 1 + topfill)
            end
            aws.winView.topline, aws.winView.topfill = topline, topfill
        end
    end

    if type(layoutCallback) == 'function' then
        layoutCallback()
    end
    for winid, aws in pairs(mgws:get(qbufnr)) do
        if aws and aws.winView and aws.winView.topline and utils.isWinValid(winid) then
            log.debug('revertClosingWins:', aws.winView, '\n')
            utils.winExecute(winid, function()
                mcore.resetView(aws.winView)
            end)
        end
    end
end

local function open(winid, lastWinid, layoutCallback)
    if not enable then
        return
    end
    local pos = wpos.getPos(winid, lastWinid)
    revertOpeningWins(winid, lastWinid, pos, layoutCallback)
end

function M.close(winid, lastWinid, bufnr)
    if not utils.isWinValid(winid) or not enable then
        return
    end

    local pos = wpos.getPos(winid, lastWinid)
    local winnr = fn.win_id2win(winid)
    local winJ, winL
    utils.winExecute(winid, function()
        winJ, winL = fn.winnr('j'), fn.winnr('l')
    end)

    local whei, wwid, phei, pwid
    local relPos = pos[1]
    if relPos == POS.RIGHT and winL ~= winnr then
        wwid, pwid = api.nvim_win_get_width(winid), api.nvim_win_get_width(lastWinid)
    elseif relPos == POS.BELOW and winJ ~= winnr then
        whei, phei = api.nvim_win_get_height(winid), api.nvim_win_get_height(lastWinid)
    end

    revertClosingWins(winid, lastWinid, pos, function()
        local curWinid = api.nvim_get_current_win()

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

            local eiBak = vim.o.ei
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
            vim.o.ei = eiBak
            if ok then
                api.nvim_win_close(winid, false)
                api.nvim_buf_delete(scratch, {})
            end
        else
            api.nvim_win_close(winid, false)
        end

        if utils.isWinValid(lastWinid) and curWinid == winid then
            api.nvim_set_current_win(lastWinid)
        end

        if relPos == POS.RIGHT and winL ~= winnr then
            api.nvim_win_set_width(lastWinid, wwid + pwid + 1)
        elseif relPos == POS.BELOW and winJ ~= winnr then
            api.nvim_win_set_height(lastWinid, whei + phei + 1)
        end
    end)

    M.detach(bufnr)
end

---
---@param winid? number
---@param lastWinid? number
---@param bufnr? number
---@param layoutCallback? fun()
function M.attach(winid, lastWinid, bufnr, layoutCallback)
    if not enable then
        if type(layoutCallback) == 'function' then
            layoutCallback()
        end
        return
    end
    winid = winid or api.nvim_get_current_win()
    lastWinid = lastWinid or fn.win_getid(fn.winnr('#'))
    bufnr = bufnr or api.nvim_win_get_buf(winid)
    open(winid, lastWinid, layoutCallback)
    cmd(([[
        aug BqfMagicWin
            au! * <buffer>
            au WinClosed <buffer> ++nested lua require('bqf.magicwin.handler').close(%d, %d, %d)
        aug END
    ]]):format(winid, lastWinid, bufnr))
end

---
---@param bufnr number
function M.detach(bufnr)
    cmd(([[au! BqfMagicWin * <buffer=%d>]]):format(bufnr))
    mgws:clean(bufnr)
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
