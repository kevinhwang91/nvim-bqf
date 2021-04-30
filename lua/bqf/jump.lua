local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local qftool = require('bqf.qftool')
local utils = require('bqf.utils')

local function set_opts_around(func)
    local opts = {
        wrap = vim.wo.wrap,
        cursorline = vim.wo.cursorline,
        number = vim.wo.number,
        relativenumber = vim.wo.relativenumber,
        signcolumn = vim.wo.signcolumn,
        foldcolumn = vim.wo.foldcolumn,
        list = vim.wo.list,
        colorcolumn = vim.wo.colorcolumn,
        winhighlight = vim.wo.winhighlight,
        foldenable = vim.wo.foldenable
    }
    func()
    for opt, val in pairs(opts) do
        vim.wo[opt] = val
    end
end

function M.open(close, qf_winid, idx)
    qf_winid = qf_winid or api.nvim_get_current_win()
    idx = idx or api.nvim_win_get_cursor(qf_winid)[1]

    local file_winid = qftool.filewinid(qf_winid)

    if file_winid and not api.nvim_win_is_valid(file_winid) then
        api.nvim_feedkeys(api.nvim_replace_termcodes('<CR>', true, false, true), 'n', true)
        return
    end

    local suffix = qftool.type(qf_winid) == 'loc' and 'll' or 'cc'
    local file_w_info = fn.getwininfo(file_winid)[1]
    local topline, botline = file_w_info.topline, file_w_info.botline

    local last_bufnr = api.nvim_win_get_buf(file_winid)
    api.nvim_set_current_win(file_winid)
    if close then
        api.nvim_win_close(qf_winid, true)
    end

    cmd(([[sil exe '%d%s']]):format(idx, suffix))

    if last_bufnr ~= api.nvim_get_current_buf() then
        utils.zz()
    else
        local lnum = api.nvim_win_get_cursor(0)[1]
        if lnum < topline or lnum > botline then
            utils.zz()
        end
    end
end

function M.split(vertical, qf_winid, idx)
    qf_winid = qf_winid or api.nvim_get_current_win()
    idx = idx or api.nvim_win_get_cursor(qf_winid)[1]

    local qf_type = qftool.type(qf_winid)
    if qf_type == 'loc' then
        qftool.update({idx = idx}, qf_winid)
    end
    local suffix = qf_type == 'loc' and 'll' or 'cc'
    local file_winid = qftool.filewinid(qf_winid)
    api.nvim_set_current_win(file_winid)
    api.nvim_win_close(qf_winid, true)

    cmd(('%ssp'):format(vertical and 'v' or ''))
    cmd(([[sil exe '%d%s']]):format(idx, suffix))
    utils.zz()
end

function M.tabedit(stay, qf_winid, idx)
    qf_winid = qf_winid or api.nvim_get_current_win()
    idx = idx or api.nvim_win_get_cursor(qf_winid)[1]

    local qf_type = qftool.type(qf_winid)
    if qf_type == 'loc' then
        qftool.update({idx = idx}, qf_winid)
    end
    local suffix = qf_type == 'loc' and 'll' or 'cc'

    local file_winid = qftool.filewinid(qf_winid)
    api.nvim_set_current_win(file_winid)
    local bufname = api.nvim_buf_get_name(api.nvim_win_get_buf(file_winid))
    if bufname == '' then
        cmd(([[sil exe '%d%s']]):format(idx, suffix))
    else
        set_opts_around(function()
            cmd(('%s tabedit'):format(stay and 'noa' or ''))
            cmd(([[%s sil exe '%d%s']]):format(stay and 'noa' or '', idx, suffix))
        end)
    end

    utils.zz()
    cmd('noa bw #')

    api.nvim_set_current_win(qf_winid)

    if bufname ~= '' and not stay then
        cmd('tabn')
    end
end

return M
