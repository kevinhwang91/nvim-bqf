local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local qftool = require('bqf.qftool')
local utils = require('bqf.utils')

local function set_opts_around(winid, func, ...)
    local opts = {
        wrap = vim.wo[winid].wrap,
        cursorline = vim.wo[winid].cursorline,
        number = vim.wo[winid].number,
        relativenumber = vim.wo[winid].relativenumber,
        signcolumn = vim.wo[winid].signcolumn,
        foldcolumn = vim.wo[winid].foldcolumn,
        list = vim.wo[winid].list,
        colorcolumn = vim.wo[winid].colorcolumn,
        winhighlight = vim.wo[winid].winhighlight,
        foldenable = vim.wo[winid].foldenable
    }
    func(...)
    for opt, val in pairs(opts) do
        vim.wo[opt] = val
    end
end

local function validate_size(qwinid)
    local valid = qftool.get({size = 0}, qwinid).size > 0
    if not valid then
        api.nvim_err_writeln('E42: No Errors')
    end
    return valid
end

local function qinfo(qwinid, idx)
    idx = idx or api.nvim_win_get_cursor(qwinid)[1]
    local qf_type = qftool.type(qwinid)
    local filewinid = qftool.filewinid(qwinid)
    return idx, qf_type, filewinid
end

function M.open(close, qwinid, idx0)
    qwinid = qwinid or api.nvim_get_current_win()
    if validate_size(qwinid) then
        local idx, qf_type, filewinid = qinfo(qwinid, idx0)

        if filewinid and not api.nvim_win_is_valid(filewinid) then
            api.nvim_feedkeys(api.nvim_replace_termcodes('<CR>', true, false, true), 'n', true)
        else

            local suffix = qf_type == 'loc' and 'll' or 'cc'
            local file_w_info = fn.getwininfo(filewinid)[1]
            local topline, botline = file_w_info.topline, file_w_info.botline

            local last_bufnr = api.nvim_win_get_buf(filewinid)
            api.nvim_set_current_win(filewinid)
            if close then
                api.nvim_win_close(qwinid, true)
            end

            set_opts_around(filewinid, function()
                cmd(([[sil exe '%d%s']]):format(idx, suffix))
            end)

            if vim.wo.foldenable and vim.o.fdo:match('quickfix') then
                cmd('norm! zv')
            end

            if last_bufnr ~= api.nvim_get_current_buf() then
                utils.zz()
            else
                local lnum = api.nvim_win_get_cursor(0)[1]
                if lnum < topline or lnum > botline then
                    utils.zz()
                end
            end
        end
    end
end

function M.split(vertical, qwinid, idx0)
    qwinid = qwinid or api.nvim_get_current_win()
    if validate_size(qwinid) then
        local idx, qf_type, filewinid = qinfo(qwinid, idx0)
        if qf_type == 'loc' then
            qftool.update({idx = idx}, qwinid)
        end
        local suffix = qf_type == 'loc' and 'll' or 'cc'
        api.nvim_set_current_win(filewinid)
        api.nvim_win_close(qwinid, true)

        local bufname = api.nvim_buf_get_name(api.nvim_win_get_buf(filewinid))
        set_opts_around(filewinid, function()
            if bufname == '' then
                cmd(([[sil exe '%d%s']]):format(idx, suffix))
            else
                cmd(('%ssp'):format(vertical and 'v' or ''))
                cmd(([[sil exe '%d%s']]):format(idx, suffix))
            end
        end)
        utils.zz()
    end
end

function M.tabedit(stay, qwinid, idx0)
    qwinid = qwinid or api.nvim_get_current_win()

    if validate_size(qwinid) then
        local idx, qf_type, filewinid = qinfo(qwinid, idx0)
        if qf_type == 'loc' then
            qftool.update({idx = idx}, qwinid)
        end
        local suffix = qf_type == 'loc' and 'll' or 'cc'

        api.nvim_set_current_win(filewinid)
        local bufname = api.nvim_buf_get_name(api.nvim_win_get_buf(filewinid))
        set_opts_around(filewinid, function()
            if bufname == '' then
                cmd(([[sil exe '%d%s']]):format(idx, suffix))
            else
                cmd(('%s tabedit'):format(stay and 'noa' or ''))
                cmd(([[%s sil exe '%d%s']]):format(stay and 'noa' or '', idx, suffix))
            end
        end)

        utils.zz()
        cmd('noa bw #')

        api.nvim_set_current_win(qwinid)

        if bufname ~= '' and not stay then
            cmd('tabn')
        end
    end
end

return M
