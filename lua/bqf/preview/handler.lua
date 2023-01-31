---@class BqfPreviewHandler
local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local autoPreview
local clicked
local shouldPreviewCallback
local keepPreview, origPos
local winHeight, winVHeight
local wrap, borderChars
local showTitle
local bufLabel
local lastIdx
local PLACEHOLDER_TBL

local config = require('bqf.config')
local qfs = require('bqf.qfwin.session')
local pvs = require('bqf.preview.session')
local ts = require('bqf.preview.treesitter')
local utils = require('bqf.utils')
local debounce = require('bqf.lib.debounce')

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

    origPos = api.nvim_win_get_cursor(0)

    -- scrolling horizontally reset
    cmd('norm! ze')

    fn.clearmatches()

    local posList = {}
    if lspRangeHl and not vim.tbl_isempty(lspRangeHl) then
        posList = utils.lspRangeToPosList(lspRangeHl)
    elseif patternHl and patternHl ~= '' then
        posList = utils.patternToPosList(patternHl)
    else
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

---
---@param qwinid? number
---@return BqfPreviewSession|table
local function previewSession(qwinid)
    qwinid = qwinid or api.nvim_get_current_win()
    return pvs.get(qwinid) or PLACEHOLDER_TBL
end

local function doSyntax(qwinid)
    local ps = previewSession(qwinid)
    if ps == PLACEHOLDER_TBL or ps.syntax then
        return
    end

    local ft = 'bqfpreview'
    local fbufnr = ps.floatBufnr()
    local loaded = utils.isBufLoaded(ps.bufnr)
    if loaded then
        ft = vim.bo[ps.bufnr].ft
    else
        -- https://github.com/nvim-treesitter/nvim-treesitter/issues/898
        -- fuxx min.js!
        local lcount = api.nvim_buf_line_count(fbufnr)
        local bytes = api.nvim_buf_get_offset(fbufnr, lcount)
        -- bytes / lcount < 500 LGTM :)
        if bytes / lcount < 500 then
            local eiBak = vim.o.ei
            local ok, res = pcall(api.nvim_buf_call, fbufnr, function()
                vim.o.ei = 'FileType'
                vim.bo.ft = ft
                cmd(('do filetypedetect BufRead %s'):format(
                fn.fnameescape(api.nvim_buf_get_name(ps.bufnr))))
                return vim.bo.ft
            end)
            vim.o.ei = eiBak
            if ok then
                ft = res
            end
        end
    end
    if ft ~= 'bqfpreview' then
        ps.syntax = ts.attach(ps.bufnr, fbufnr, ft)
        if not ps.syntax then
            vim.bo[fbufnr].syntax = ft
            ps.syntax = true
        end
    end
end

local function showCountLabel(qlist, idx)
    local items = qlist:items()
    local curBufnr = items[idx].bufnr
    local lo, hi = idx, idx
    for i = idx - 1, 1, -1 do
        if items[i].bufnr == curBufnr then
            lo = i
        else
            break
        end
    end
    for i = idx + 1, #items do
        if items[i].bufnr == curBufnr then
            hi = i
        else
            break
        end
    end
    local cur = idx - lo + 1
    local cnt = hi - lo + 1
    pvs:showCountLabel(('[%d/%d]'):format(cur, cnt), 'BqfPreviewBufLabel')
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

---
---@param qwinid? number
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

---
---@param qwinid number
---@param qidx? number
---@param force? boolean
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

    if ps.bufnr ~= pbufnr and not force and shouldPreviewCallback and
        not shouldPreviewCallback(pbufnr, qwinid) then
        M.close(qwinid)
        return
    end

    ps:validOrBuild(pwinid)

    pvs.display()

    local fbufnr = pvs.floatBufnr()
    if not fbufnr then
        return
    end

    local loaded = utils.isBufLoaded(pbufnr)
    if force or ps.bufnr ~= pbufnr then
        pvs.floatBufReset()
        ts.disableActive(fbufnr)

        utils.transferBuf(pbufnr, fbufnr)
        ps.bufnr = pbufnr
        ps.syntax = ts.tryAttach(pbufnr, fbufnr, loaded)
    end

    if not ps.syntax then
        M.doSyntax(qwinid)
    end

    local ctx = qlist:context().bqf or {}
    local lspRangeHlList, patternHl = ctx.lsp_ranges_hl, ctx.pattern_hl
    local lspRangeHl
    if type(lspRangeHlList) == 'table' then
        lspRangeHl = lspRangeHlList[qidx]
    end

    local size = qlist:getQfList({size = 0}).size
    pvs.updateBorder(pbufnr, qidx, size)

    pvs.floatWinExec(function()
        execPreview(item, lspRangeHl, patternHl)
        utils.zz()
        pvs.scroll(pbufnr, loaded)
    end)
    if bufLabel then
        if size < 1000 or qlist:itemsCached() then
            showCountLabel(qlist, qidx)
        else
            vim.defer_fn(function()
                if utils.isWinValid(qwinid) and qlist.id == qfs:get(qwinid):list().id and
                    qidx == api.nvim_win_get_cursor(qwinid)[1] then
                    showCountLabel(qlist, qidx)
                end
            end, 50)
        end
    end
end

---
---@param direction number
---@param qwinid? number
function M.scroll(direction, qwinid)
    if pvs.validate() and direction then
        qwinid = qwinid or api.nvim_get_current_win()
        pvs.floatWinExec(function()
            if direction == 0 then
                api.nvim_win_set_cursor(0, origPos)
            else
                -- ^D = 0x04, ^U = 0x15
                cmd(('norm! %c'):format(direction > 0 and 0x04 or 0x15))
            end
            utils.zz()
            local ps = previewSession(qwinid)
            pvs.scroll(ps.bufnr)
        end)
    end
end

---
---@param qwinid? number
function M.toggle(qwinid)
    qwinid = qwinid or api.nvim_get_current_win()
    local ps = previewSession(qwinid)
    if ps == PLACEHOLDER_TBL then
        return
    end
    autoPreview = autoPreview ~= true
    if autoPreview then
        utils.warn('Enable preview automatically')
        M.open(qwinid)
    else
        utils.warn('Disable preview automatically')
        M.close(qwinid)
    end
end

---
---@param qwinid? number
---@return boolean
function M.showWindow(qwinid)
    local res = false
    if not pvs.validate() then
        M.open(qwinid, nil, true)
        res = true
    end
    return res
end

---
---@param qwinid? number
---@return boolean
function M.hideWindow(qwinid)
    local res = false
    if pvs.validate() then
        M.close(qwinid)
        res = true
    end
    return res
end

function M.toggleWindow(qwinid)
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

local function checkClicked()
    fn.getchar()
    local winid = vim.v.mouse_winid
    clicked = pvs.floatWinid() == winid
    return winid
end

function M.clicked()
    local res = clicked
    clicked = false
    return res
end

function M.mouseClick(mode)
    local clickedWinid = checkClicked()
    if not clicked then
        api.nvim_set_current_win(clickedWinid)
        cmd(('norm! %dgg%d|'):format(vim.v.mouse_lnum, vim.v.mouse_col))
    else
        if mode == 't' then
            cmd('startinsert')
        end
    end
end

function M.mouseDoubleClick(mode)
    local clickedWinid = checkClicked()
    if api.nvim_get_current_win() == clickedWinid then
        -- ^M = 0x0d
        cmd(('norm! %c'):format(0x0d))
    elseif clicked then
        if mode == 't' then
            cmd('startinsert')
            api.nvim_feedkeys(('%c'):format(0x0d), 'it', false)
        else
            local lnum, vcol = vim.v.mouse_lnum, vim.v.mouse_col
            local col
            if utils.has08() then
                col = math.max(0, fn.virtcol2col(clickedWinid, lnum, vcol) - 1)
            end
            cmd(('norm %c'):format(0x0d))
            if col then
                api.nvim_win_set_cursor(0, {lnum, col})
            else
                cmd(('keepj norm! %dgg%d|'):format(lnum, vcol))
            end
            utils.zz()
        end
    end
end

function M.initialize(qwinid)
    cmd([[
        aug BqfPreview
            au! * <buffer>
            au VimResized <buffer> lua require('bqf.preview.handler').redrawWin()
            au CursorMoved,WinEnter <buffer> lua require('bqf.preview.handler').moveCursor()
            au WinLeave,BufWipeout,BufHidden <buffer> lua require('bqf.preview.handler').close()
        aug END
    ]])

    local mouseEnabled = vim.o.mouse:match('[na]') ~= nil

    pvs:new(qwinid, {
        winHeight = winHeight,
        winVHeight = winVHeight,
        wrap = wrap,
        borderChars = borderChars,
        showTitle = showTitle,
        focusable = mouseEnabled
    })
    -- some plugins will change the quickfix window, preview window should init later
    vim.defer_fn(function()
        lastIdx = -1
        -- delayed called, qwinid maybe invalid
        if not utils.isWinValid(qwinid) then
            return
        end

        if mouseEnabled then
            local qbufnr = api.nvim_win_get_buf(qwinid)
            api.nvim_buf_set_keymap(qbufnr, '', '<LeftMouse>',
                                    [[<Cmd>lua require('bqf.preview.handler').mouseClick()<CR>]],
                                    {nowait = true, noremap = false})
            api.nvim_buf_set_keymap(qbufnr, 'n', '<2-LeftMouse>',
                                    [[<Cmd>lua require('bqf.preview.handler').mouseDoubleClick()<CR>]],
                                    {nowait = true, noremap = false})
        end

        if autoPreview and api.nvim_get_current_win() == qwinid then
            M.open(qwinid)
        end
    end, 50)
end

local function init()
    local pconf = config.preview
    vim.validate({preview = {pconf, 'table'}})
    local delaySyntax = tonumber(pconf.delay_syntax)
    autoPreview = pconf.auto_preview
    wrap = pconf.wrap
    shouldPreviewCallback = pconf.should_preview_cb
    borderChars = pconf.border_chars
    showTitle = pconf.show_title
    winHeight = tonumber(pconf.win_height)
    winVHeight = tonumber(pconf.win_vheight or winHeight)
    bufLabel = pconf.buf_label
    vim.validate({
        auto_preview = {autoPreview, 'boolean'},
        delay_syntax = {delaySyntax, 'number'},
        wrap = {wrap, 'boolean'},
        should_preview_cb = {shouldPreviewCallback, 'function', true},
        border_chars = {
            borderChars, function(chars)
                return type(chars) == 'table' and #chars == 9
            end, 'a table with 9 chars'
        },
        show_title = {showTitle, 'boolean'},
        win_height = {winHeight, 'number'},
        win_vheight = {winVHeight, 'number'},
        buf_label = {bufLabel, 'boolean'}
    })

    cmd([[
        hi default link BqfPreviewFloat Normal
        hi default link BqfPreviewBorder Normal
        hi default link BqfPreviewCursor Cursor
        hi default link BqfPreviewCursorLine CursorLine
        hi default link BqfPreviewRange IncSearch
        hi default link BqfPreviewBufLabel BqfPreviewRange

        aug BqfPreview
            au!
        aug END
    ]])
    clicked = false

    PLACEHOLDER_TBL = {}
    -- Damn it! someone wants to disable syntax :(
    -- https://github.com/kevinhwang91/nvim-bqf/issues/89
    ---@diagnostic disable-next-line: unused-local
    M.doSyntax = delaySyntax >= 0 and debounce(doSyntax, delaySyntax) or function(qwinid) end
end

init()

return M
