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

local function validate_size(qf_winid)
    local valid = qftool.get({size = 0}, qf_winid).size > 0
    if not valid then
        api.nvim_err_writeln('E42: No Errors')
    end
    return valid
end

local function qf_info(qf_winid, idx)
    idx = idx or api.nvim_win_get_cursor(qf_winid)[1]
    local qf_type = qftool.type(qf_winid)
    local file_winid = qftool.filewinid(qf_winid)
    return idx, qf_type, file_winid
end

function M.open(close, qf_winid, idx0)
    qf_winid = qf_winid or api.nvim_get_current_win()
    if validate_size(qf_winid) then
        local idx, qf_type, file_winid = qf_info(qf_winid, idx0)

        if file_winid and not api.nvim_win_is_valid(file_winid) then
            api.nvim_feedkeys(api.nvim_replace_termcodes('<CR>', true, false, true), 'n', true)
        else

            local suffix = qf_type == 'loc' and 'll' or 'cc'
            local file_w_info = fn.getwininfo(file_winid)[1]
            local topline, botline = file_w_info.topline, file_w_info.botline

            local last_bufnr = api.nvim_win_get_buf(file_winid)
            api.nvim_set_current_win(file_winid)
            if close then
                api.nvim_win_close(qf_winid, true)
            end

            set_opts_around(file_winid, function()
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

function M.close(qf_winid, idx0)
    qf_winid = qf_winid or api.nvim_get_current_win()
    if validate_size(qf_winid) then
        local _, _, file_winid = qf_info(qf_winid, idx0)
        api.nvim_set_current_win(file_winid)
        api.nvim_win_close(qf_winid, true)
    end
end

function M.split(vertical, qf_winid, idx0)
    qf_winid = qf_winid or api.nvim_get_current_win()
    if validate_size(qf_winid) then
        local idx, qf_type, file_winid = qf_info(qf_winid, idx0)
        if qf_type == 'loc' then
            qftool.update({idx = idx}, qf_winid)
        end
        local suffix = qf_type == 'loc' and 'll' or 'cc'
        api.nvim_set_current_win(file_winid)
        api.nvim_win_close(qf_winid, true)

        local bufname = api.nvim_buf_get_name(api.nvim_win_get_buf(file_winid))
        set_opts_around(file_winid, function()
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

function M.tabedit(stay, qf_winid, idx0)
    qf_winid = qf_winid or api.nvim_get_current_win()

    if validate_size(qf_winid) then
        local idx, qf_type, file_winid = qf_info(qf_winid, idx0)
        if qf_type == 'loc' then
            qftool.update({idx = idx}, qf_winid)
        end
        local suffix = qf_type == 'loc' and 'll' or 'cc'

        api.nvim_set_current_win(file_winid)
        local bufname = api.nvim_buf_get_name(api.nvim_win_get_buf(file_winid))
        set_opts_around(file_winid, function()
            if bufname == '' then
                cmd(([[sil exe '%d%s']]):format(idx, suffix))
            else
                cmd(('%s tabedit'):format(stay and 'noa' or ''))
                cmd(([[%s sil exe '%d%s']]):format(stay and 'noa' or '', idx, suffix))
            end
        end)

        utils.zz()
        cmd('noa bw #')

        api.nvim_set_current_win(qf_winid)

        if bufname ~= '' and not stay then
            cmd('tabn')
        end
    end
end

return M
