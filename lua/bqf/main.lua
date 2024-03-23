---@class BqfMain
local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local qfs = require('bqf.qfwin.session')
local preview = require('bqf.preview.handler')
local layout = require('bqf.layout')
local magicwin = require('bqf.magicwin.handler')
local keymap = require('bqf.keymap')

function M.toggle()
    if vim.w.bqf_enabled then
        M.disable()
    else
        M.enable()
    end
end

function M.enable()
    -- need after vim-patch:8.1.0877
    if not layout.validQfWin() then
        return false
    end

    local qwinid = api.nvim_get_current_win()
    local qs = qfs:new(qwinid)
    assert(qs, 'It is not a quickfix window')
    local qlist = qs:list()
    if qlist:changedtick() == 0 and vim.w.bqf_enabled then
        return
    end

    local adjustHeightCallback = layout.initialize(qwinid)
    preview.initialize(qwinid)
    keymap.initialize()

    local pwinid = qs:previousWinid()
    cmd([[
        aug Bqf
            au! * <buffer>
            au WinEnter <buffer> ++nested lua require('bqf.main').enterQf()
            au WinClosed <buffer> ++nested lua require('bqf.main').closeQf()
            au WinLeave <buffer> lua require('bqf.main').saveWinView()
        aug END
    ]])
    -- TODO
    -- After WinClosed callback in magic window, WinClosed in main can't be fired.
    -- WinClosed event in magic window must after in main
    magicwin.attach(qwinid, pwinid, nil, adjustHeightCallback)
    vim.w.bqf_enabled = true
    return true
end

function M.disable()
    if vim.bo.buftype ~= 'quickfix' then
        return false
    end
    vim.w.bqf_enabled = false
    local qwinid = api.nvim_get_current_win()
    preview.close(qwinid)
    keymap.dispose()
    cmd('au! Bqf')
    cmd('sil! au! BqfPreview * <buffer>')
    cmd('sil! au! BqfFilterFzf * <buffer>')
    cmd('sil! au! BqfMagicWin')
    qfs:dispose()
    return true
end

local function close(winid)
    local ok, msg = pcall(api.nvim_win_close, winid, false)
    if not ok then
        -- Vim:E444: Cannot close last window
        ---@diagnostic disable-next-line: need-check-nil
        if msg:match('^Vim:E444') then
            local function closeLastWin()
                cmd('new')
                api.nvim_win_close(winid, true)
            end

            -- after nvim 0.7+ Vim:E242 Can't split a window while closing another
            if not pcall(closeLastWin) then
                -- less redraw
                cmd('noa enew')
                local bufnr = api.nvim_get_current_buf()
                vim.schedule(function()
                    closeLastWin()
                    cmd('noa bw ' .. bufnr)
                end)
            end
        end
    end
end

function M.saveWinView()
    local winid = api.nvim_get_current_win()
    qfs:saveWinView(winid)
end

function M.enterQf()
    local winid = api.nvim_get_current_win()
    local qs = qfs:get(winid)
    if qs then
        if qs:previousWinid() < 0 then
            close(winid)
        else
            local qlist = qs:list()
            local qinfo = qlist:getQfList({id = 0})
            if qinfo.id ~= qlist.id then
                qfs:new(winid)
            end
        end
    end
end

function M.closeQf()
    local winid = tonumber(fn.expand('<afile>'))
    if winid and api.nvim_win_is_valid(winid) then
        qfs:dispose()
        preview.close(winid)
    end
end

local function init()
    cmd([[
        aug Bqf
            au!
        aug END
    ]])
end

init()

return M
