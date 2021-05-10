local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local qfs = require('bqf.qfsession')
local qftool = require('bqf.qftool')
local preview = require('bqf.preview')
local layout = require('bqf.layout')
local keymap = require('bqf.keymap')
local sign = require('bqf.sign')

local function setup()
    api.nvim_exec([[
        aug Bqf
            au!
        aug END
    ]], false)
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

    local qf_winid = api.nvim_get_current_win()
    qfs.attach(qf_winid)

    local qf_type = qftool.type(qf_winid)

    local file_winid = qftool.filewinid(qf_winid)

    if vim.bo.bufhidden == 'wipe' then
        qfs[qf_winid].bufhidden = 'wipe'
    end

    vim.wo.number, vim.wo.relativenumber = true, false
    vim.wo.wrap, vim.foldenable = false, false
    vim.wo.foldcolumn, vim.wo.signcolumn = '0', 'number'

    layout.init(qf_winid, file_winid, qf_type)

    local qf_bufnr = api.nvim_win_get_buf(qf_winid)
    sign.reset(qf_bufnr)
    -- some plugins will change the quickfix window, preview window should init later
    vim.defer_fn(function()
        preview.init_window(qf_winid)
    end, 50)

    -- after vim-patch:8.1.0877, quickfix will reuse buffer, below buffer setup is no necessary
    if vim.b.bqf_enabled then
        return
    end

    vim.b.bqf_enabled = true
    preview.buf_event()
    keymap.buf_map()

    api.nvim_exec([[
        aug Bqf
            au! * <buffer>
            au WinEnter <buffer> lua require('bqf.main').kill_alone_qf()
            au WinClosed <buffer> ++nested lua require('bqf.main').close_qf()
        aug END
    ]], false)
end

function M.disable()
    if vim.bo.buftype ~= 'quickfix' then
        return
    end
    local qf_winid = api.nvim_get_current_win()
    preview.close(qf_winid)
    vim.b.bqf_enabled = false
    cmd('au! Bqf')
    cmd('sil! au! BqfPreview * <buffer>')
    cmd('sil! au! BqfFilterFzf * <buffer>')
    cmd('sil! au! BqfMagicWin')
    if qfs[qf_winid].bufhidden then
        vim.bo.bufhidden = qfs[qf_winid].bufhidden
    end
    qfs.release(qf_winid)
end

function M.kill_alone_qf()
    pcall(function()
        qftool.filewinid()
    end)
end

function M.close_qf()
    local winid = fn.expand('<afile>')
    -- upstream bug
    -- https://github.com/neovim/neovim/issues/14512
    winid = tonumber(winid:sub(winid:find('%d+')))

    if qfs[winid].bufhidden then
        local qf_bufnr = api.nvim_win_get_buf(winid)
        vim.bo[qf_bufnr].bufhidden = qfs[winid].bufhidden
    end
    if winid and api.nvim_win_is_valid(winid) then
        layout.close_win(winid)
        qfs.release(winid)
    end
end

setup()

return M
