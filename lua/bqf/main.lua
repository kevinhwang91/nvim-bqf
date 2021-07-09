local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local wses = require('bqf.wsession')
local qhelper = require('bqf.qhelper')
local preview = require('bqf.preview')
local layout = require('bqf.layout')
local keymap = require('bqf.keymap')
local qobj = require('bqf.qobj')
local qdo = require('bqf.qdo')

local function setup()
    cmd([[
        aug Bqf
            au!
        aug END
    ]])
end

function M.toggle()
    if vim.b.bqf_enabled then
        M.disable()
    else
        M.enable()
    end
end

function M.enable()
    -- need after vim-patch:8.1.0877
    if not layout.valid_qf_win() then
        return
    end

    assert(vim.bo.buftype == 'quickfix', 'It is not a quickfix window')

    local qwinid = api.nvim_get_current_win()
    wses.acquire(qwinid)

    local qo = wses.bind_qobj(qwinid)
    qo:get_sign():reset()
    qobj.verify()

    local pair_winid = qhelper.pair_winid(qwinid)

    if vim.bo.bufhidden == 'wipe' then
        wses[qwinid].bufhidden = 'wipe'
    end

    vim.wo.number, vim.wo.relativenumber = true, false
    vim.wo.wrap, vim.foldenable = false, false
    vim.wo.foldcolumn, vim.wo.signcolumn = '0', 'number'

    layout.init(qwinid, pair_winid, qo.type)

    -- some plugins will change the quickfix window, preview window should init later
    vim.defer_fn(function()
        preview.init_window(qwinid)
    end, 50)

    -- after vim-patch:8.1.0877, quickfix will reuse buffer, below buffer setup is no necessary
    if vim.b.bqf_enabled then
        return
    end

    vim.b.bqf_enabled = true
    preview.buf_event()
    keymap.buf_map()

    cmd([[
        aug Bqf
            au! * <buffer>
            au WinEnter <buffer> lua require('bqf.main').kill_alone_qf()
            au WinClosed <buffer> ++nested lua require('bqf.main').close_qf()
        aug END
    ]])
end

function M.disable()
    if vim.bo.buftype ~= 'quickfix' then
        return
    end
    local qwinid = api.nvim_get_current_win()
    preview.close(qwinid)
    vim.b.bqf_enabled = false
    cmd('au! Bqf')
    cmd('sil! au! BqfPreview * <buffer>')
    cmd('sil! au! BqfFilterFzf * <buffer>')
    cmd('sil! au! BqfMagicWin')
    if wses[qwinid].bufhidden then
        vim.bo.bufhidden = wses[qwinid].bufhidden
    end
    wses.release(qwinid)
end

function M.kill_alone_qf()
    pcall(function()
        qhelper.pair_winid()
    end)
end

function M.close_qf()
    local winid = tonumber(fn.expand('<afile>'))
    if wses[winid].bufhidden then
        local qf_bufnr = api.nvim_win_get_buf(winid)
        vim.bo[qf_bufnr].bufhidden = wses[winid].bufhidden
    end
    qobj.verify()
    if winid and api.nvim_win_is_valid(winid) then
        preview.close(winid)
        layout.close_win(winid)
        wses.release(winid)
    end
end

setup()

return M
