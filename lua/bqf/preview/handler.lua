---@class BqfPreviewHandler
local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local autoPreview, delaySyntax
local shouldPreviewCallBack
local keepPreview, origPos
local winHeight, winVHeight
local wrap, borderChars
local lastIdx
local PLACEHOLDER_TBL

local config = require('bqf.config')
local qfs = require('bqf.qfwin.session')
local pvs = require('bqf.preview.session')
local ts = require('bqf.preview.treesitter')
local extmark = require('bqf.preview.extmark')
local utils = require('bqf.utils')

local function execPreview(item, lspRangeHl, patternHl)
    local lnum, col, pattern = item.lnum, item.col, item.pattern

    if lnum < 1 then
        api.nvim_win_set_cursor(0, {1, 0})
        if pattern ~= '' then
            fn.search(pattern, 'c')
        end
    elseif not pcall(api.nvim_win_set_cursor, 0, {lnum, math.max(0, col - 1)}) then
        return
    end

    utils.zz()
    origPos = api.nvim_win_get_cursor(0)

    -- scrolling horizontally reset
    cmd('norm! ze')

    fn.clearmatches()

    local posList = {}
    if lspRangeHl and not vim.tbl_isempty(lspRangeHl) then
        posList = utils.lspRangeToPosList(lspRangeHl)
    elseif patternHl and patternHl ~= '' then
        posList = utils.patternToPosList(patternHl)
    elseif utils.has06() then
        local endLnum, endCol = item.end_lnum, item.end_col
        posList = utils.qfRangeToPosList(lnum, col, endLnum, endCol)
    end

    if not vim.tbl_isempty(posList) then
        utils.matchAddPos('BqfPreviewRange', posList)
    else
        if lnum < 1 then
            fn.matchadd('BqfPreviewRange', pattern)
        elseif col < 1 then
            utils.matchAddPos('BqfPreviewRange', {{lnum}})
        end
    end

    if lnum > 0 then
        utils.matchAddPos('BqfPreviewCursor', {{lnum, math.max(1, col)}}, 11)
    end
end

local function previewSession(qwinid)
    qwinid = qwinid or api.nvim_get_current_win()
    return pvs.get(qwinid) or PLACEHOLDER_TBL
end

local function doSyntax(qwinid, idx, pbufnr)
    local ps = previewSession(qwinid)
    if ps == PLACEHOLDER_TBL or idx ~= lastIdx or (pbufnr == ps.bufnr and ps.syntax) then
        return
    end

    local fbufnr = ps.floatBufnr()

    -- https://github.com/nvim-treesitter/nvim-treesitter/issues/898
    -- fuxx min.js!
    local lcount = api.nvim_buf_line_count(fbufnr)
    local bytes = api.nvim_buf_get_offset(fbufnr, lcount)
    -- bytes / lcount < 500 LGTM :)
    if bytes / lcount < 500 then
        local eiBak = vim.o.ei
        local ok, ft = pcall(api.nvim_buf_call, fbufnr, function()
            vim.o.ei = 'FileType'
            vim.bo.ft = 'bqfpreview'
            cmd(('do filetypedetect BufRead %s'):format(
                fn.fnameescape(api.nvim_buf_get_name(ps.bufnr))))
            return vim.bo.ft
        end)
        vim.o.ei = eiBak

        if ok and ft ~= 'bqfpreview' then
            ps.syntax = ts.attach(pbufnr, fbufnr, ft)
            if not ps.syntax then
                vim.bo[fbufnr].syntax = ft
                ps.syntax = true
            end
        end
    end
end

function M.autoEnabled()
    return autoPreview
end

function M.keepPreview()
    keepPreview = true
end

function M.toggleMode(qwinid)
    local ps = previewSession(qwinid)
    if ps == PLACEHOLDER_TBL then
        return
    end

    ps.full = ps.full ~= true
    lastIdx = -1
    M.open(qwinid, nil, true)
end

function M.close(qwinid)
    if keepPreview then
        keepPreview = nil
        return
    end

    lastIdx = -1
    pvs.close()

    ts.shrinkCache()

    qwinid = qwinid or api.nvim_get_current_win()
    local ps = previewSession(qwinid)
    if ps then
        ps.bufnr = nil
    end
end

function M.open(qwinid, qidx, force)
    qwinid = qwinid or api.nvim_get_current_win()
    local qs = qfs:get(qwinid)
    local qlist = qs:list()
    local pwinid = qs:previousWinid()
    local ps = previewSession(qwinid)

    if ps == PLACEHOLDER_TBL or api.nvim_tabpage_list_wins(0) == 1 or fn.win_gettype(pwinid) ~= '' then
        return
    end

    qidx = qidx or api.nvim_win_get_cursor(qwinid)[1]
    if not force and qidx == lastIdx then
        return
    end

    lastIdx = qidx

    local item = qlist:item(qidx)
    if not item then
        M.close(qwinid)
        return
    end

    local pbufnr = item.bufnr

    if pbufnr == 0 or not api.nvim_buf_is_valid(pbufnr) then
        M.close(qwinid)
        return
    end

    if ps.bufnr ~= pbufnr and not force and shouldPreviewCallBack and
        not shouldPreviewCallBack(pbufnr, qwinid) then
        M.close(qwinid)
        return
    end

    ps:validOrBuild(pwinid)

    pvs.display()

    local fbufnr = pvs.floatBufnr()
    if not fbufnr then
        return
    end

    local loaded = api.nvim_buf_is_loaded(pbufnr)
    if force or ps.bufnr ~= pbufnr then
        pvs.floatBufReset()
        ts.disableActive(fbufnr)

        extmark.clearHighlight(fbufnr)
        utils.transferBuf(pbufnr, fbufnr)
        ps.bufnr = pbufnr
        ps.syntax = ts.tryAttach(pbufnr, fbufnr, loaded)
    end

    if not ps.syntax then
        vim.defer_fn(function()
            doSyntax(qwinid, qidx, pbufnr)
        end, delaySyntax)
    end

    local ctx = qlist:context().bqf or {}
    local lspRangeHlList, patternl = ctx.lsp_ranges_hl, ctx.pattern_hl
    local lspRangeHl
    if type(lspRangeHlList) == 'table' then
        lspRangeHl = lspRangeHlList[qidx]
    end

    pvs.floatWinExec(function()
        execPreview(item, lspRangeHl, patternl)
        if loaded then
            local topline, botline = pvs.visibleRegion()
            extmark.updateHighlight(pbufnr, fbufnr, topline, botline)
        end
        cmd(('noa call nvim_set_current_win(%d)'):format(pwinid))
    end)

    local size = qlist:getQfList({size = 0}).size
    pvs.updateBorder(pbufnr, qidx, size)
end

function M.scroll(direction, qwinid)
    if pvs.validate() and direction then
        qwinid = qwinid or api.nvim_get_current_win()
        local qs = qfs:get(qwinid)
        local pwinid = qs:previousWinid()
        pvs.floatWinExec(function()
            if direction == 0 then
                api.nvim_win_set_cursor(0, origPos)
            else
                -- ^D = 0x04, ^U = 0x15
                cmd(('norm! %c'):format(direction > 0 and 0x04 or 0x15))
            end
            utils.zz()
            local ps = previewSession(qwinid)
            local loaded = api.nvim_buf_is_loaded(ps.bufnr)
            if loaded then
                local topline, botline = pvs.visibleRegion()
                extmark.updateHighlight(ps.bufnr, ps.floatBufnr(), topline, botline)
            end
            cmd(('noa call nvim_set_current_win(%d)'):format(pwinid))
        end)
        pvs.updateScrollBar()
    end
end

function M.toggle(qwinid)
    qwinid = qwinid or api.nvim_get_current_win()
    local ps = previewSession(qwinid)
    if ps == PLACEHOLDER_TBL then
        return
    end
    autoPreview = autoPreview ~= true
    if autoPreview then
        api.nvim_echo({{'Enable preview automatically', 'WarningMsg'}}, true, {})
        M.open(qwinid)
    else
        api.nvim_echo({{'Disable preview automatically', 'WarningMsg'}}, true, {})
        M.close(qwinid)
    end
end

function M.toggleItem(qwinid)
    if pvs.validate() then
        M.close(qwinid)
    else
        M.open(qwinid, nil, true)
    end
end

function M.moveCursor()
    local qwinid = api.nvim_get_current_win()
    local ps = previewSession(qwinid)
    if ps == PLACEHOLDER_TBL then
        return
    end

    if autoPreview then
        M.open(qwinid)
    else
        if api.nvim_win_get_cursor(qwinid)[1] ~= lastIdx then
            M.close(qwinid)
        end
    end
end

function M.redrawWin()
    if pvs.validate() then
        local bufnr = tonumber(fn.expand('<abuf>')) or api.nvim_get_current_buf()
        local qwinid = fn.bufwinid(bufnr)
        M.close(qwinid)
        M.open(qwinid)
    end
end

function M.initialize(qwinid)
    cmd([[
        aug BqfPreview
            au! * <buffer>
            au VimResized <buffer> lua require('bqf.preview.handler').redrawWin()
            au CursorMoved,WinEnter <buffer> lua require('bqf.preview.handler').moveCursor()
            au WinLeave,BufWipeout <buffer> lua require('bqf.preview.handler').close()
        aug END
    ]])

    pvs:new(qwinid, {
        winHeight = winHeight,
        winVHeight = winVHeight,
        wrap = wrap,
        borderChars = borderChars
    })

    -- some plugins will change the quickfix window, preview window should init later
    vim.defer_fn(function()
        lastIdx = -1
        -- delayed called, qwinid maybe invalid
        if not utils.isWinValid(qwinid) then
            return
        end

        if autoPreview and api.nvim_get_current_win() == qwinid then
            M.open(qwinid)
        end
    end, 50)
end

local function init()
    local pconf = config.preview
    vim.validate({preview = {pconf, 'table'}})
    autoPreview = pconf.auto_preview
    delaySyntax = tonumber(pconf.delay_syntax)
    wrap = pconf.wrap
    shouldPreviewCallBack = pconf.should_preview_cb
    borderChars = pconf.border_chars
    winHeight = tonumber(pconf.win_height)
    winVHeight = tonumber(pconf.win_vheight or winHeight)
    vim.validate({
        auto_preview = {autoPreview, 'boolean'},
        delay_syntax = {delaySyntax, 'number'},
        wrap = {wrap, 'boolean'},
        should_preview_cb = {shouldPreviewCallBack, 'function', true},
        border_chars = {
            borderChars, function(chars)
                return type(chars) == 'table' and #chars == 9
            end, 'a table with 9 chars'
        },
        win_height = {winHeight, 'number'},
        win_vheight = {winVHeight, 'number'}
    })

    cmd([[
        hi default link BqfPreviewFloat Normal
        hi default link BqfPreviewBorder Normal
        hi default link BqfPreviewCursor Cursor
        hi default link BqfPreviewRange IncSearch

        aug BqfPreview
            au!
        aug END
    ]])

    PLACEHOLDER_TBL = {}
end

init()

return M
