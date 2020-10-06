local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local qfs = require('bqf.qfsession')
local qftool = require('bqf.qftool')
local preview = require('bqf.preview')
local layout = require('bqf.layout')
local keymap = require('bqf.keymap')

local function setup()
    api.nvim_exec([[
        augroup Bqf
            autocmd!
        augroup END
    ]], false)
end

local function valid_file_winid(file_winid)
    file_winid = file_winid or fn.win_getid(fn.winnr('#'))
    if file_winid > 0 and api.nvim_win_is_valid(file_winid) then
        return file_winid
    end

    for winid in ipairs(api.nvim_list_wins()) do
        if winid > 0 and api.nvim_win_is_valid(winid) and api.nvim_win_get_config(winid).relative ==
            '' then
            return winid
        end
    end
    assert(false, 'A valid file window is not found in current tabpage')
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

    local file_winid
    if qf_type == 'loc' then
        file_winid = fn.getloclist(qf_winid, {filewinid = 0}).filewinid
    else
        file_winid = valid_file_winid(qfs[qf_winid].file_winid)
    end
    qfs[qf_winid].file_winid = file_winid

    if qf_type == 'qf' and vim.bo.bufhidden == 'wipe' then
        qfs[qf_winid].bufhidden = 'wipe'
    end

    vim.wo.number, vim.wo.relativenumber = true, false
    vim.wo.wrap, vim.foldenable = false, false
    vim.wo.foldcolumn = '0'

    layout.init(qf_winid, file_winid, qf_type)

    -- some plugins will change the quickfix window, preview winodw should init later
    vim.defer_fn(function()
        preview.init_window(qf_winid)
    end, 20)

    -- after vim-patch:8.1.0877, quickfix will reuse buffer, below buffer setup is no necessary
    if vim.b.bqf_enabled then
        return
    end

    vim.b.bqf_enabled = true
    preview.buf_event()
    keymap.buf_nmap()

    api.nvim_exec([[
        augroup Bqf
            autocmd! WinEnter,WinLeave,WinClosed <buffer>
            autocmd WinEnter <buffer> lua require('bqf.main').kill_alone_qf()
            autocmd WinClosed <buffer> lua require('bqf.main').close_qf()
        augroup END
    ]], false)
end

function M.disable()
    if vim.bo.buftype ~= 'quickfix' then
        return
    end
    local qf_winid = api.nvim_get_current_win()
    preview.close(qf_winid)
    vim.b.bqf_enabled = false
    cmd('autocmd! Bqf')
    cmd('silent! autocmd! BqfPreview * <buffer>')
    cmd('silent! autocmd! BqfFilterFzf * <buffer>')
    if qfs[qf_winid].bufhidden then
        vim.bo.bufhidden = qfs[qf_winid].bufhidden
    end
    qfs.release(qf_winid)
end

function M.kill_alone_qf()
    local file_winid = qfs[api.nvim_get_current_win()].file_winid
    if file_winid and not api.nvim_win_is_valid(file_winid) then
        cmd('quit')
    end
end

function M.close_qf()
    local winid = tonumber(fn.expand('<afile>'))
    if winid and api.nvim_win_is_valid(winid) then
        layout.close_win(winid)
        qfs.release(winid)
    end
end

setup()

return M
