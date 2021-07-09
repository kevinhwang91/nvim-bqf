local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local qhelper = require('bqf.qhelper')
local qobj = require('bqf.qobj')
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

local function validate_size(qo)
    local valid = qo:get_qflist({size = 0}).size > 0
    if not valid then
        api.nvim_err_writeln('E42: No Errors')
    end
    return valid
end

function M.open(close, qwinid, idx)
    local qo = qobj.get(qwinid)
    qwinid = qwinid or api.nvim_get_current_win()
    if validate_size(qo) then
        idx = idx or api.nvim_win_get_cursor(qwinid)[1]
        local pair_winid = qhelper.pair_winid(qwinid)

        if pair_winid and not api.nvim_win_is_valid(pair_winid) then
            api.nvim_feedkeys(api.nvim_replace_termcodes('<CR>', true, false, true), 'n', true)
        else

            local suffix = qo.type == 'loc' and 'll' or 'cc'
            local file_w_info = fn.getwininfo(pair_winid)[1]
            local topline, botline = file_w_info.topline, file_w_info.botline

            local last_bufnr = api.nvim_win_get_buf(pair_winid)
            api.nvim_set_current_win(pair_winid)
            if close then
                api.nvim_win_close(qwinid, true)
            end

            set_opts_around(pair_winid, function()
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

function M.split(vertical, qwinid, idx)
    local qo = qobj.get(qwinid)
    qwinid = qwinid or api.nvim_get_current_win()
    if validate_size(qo) then
        idx = idx or api.nvim_win_get_cursor(qwinid)[1]
        local pair_winid = qhelper.pair_winid(qwinid)
        if qo.type == 'loc' then
            qo:change_idx(idx)
        end
        local suffix = qo.type == 'loc' and 'll' or 'cc'
        api.nvim_set_current_win(pair_winid)
        api.nvim_win_close(qwinid, true)

        local bufname = api.nvim_buf_get_name(api.nvim_win_get_buf(pair_winid))
        set_opts_around(pair_winid, function()
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

function M.tabedit(stay, qwinid, idx)
    local qo = qobj.get(qwinid)
    qwinid = qwinid or api.nvim_get_current_win()
    if validate_size(qo) then
        idx = idx or api.nvim_win_get_cursor(qwinid)[1]
        local pair_winid = qhelper.pair_winid(qwinid)
        if qo.type == 'loc' then
            qo:change_idx(idx)
        end
        local suffix = qo.type == 'loc' and 'll' or 'cc'

        api.nvim_set_current_win(pair_winid)
        local bufname = api.nvim_buf_get_name(api.nvim_win_get_buf(pair_winid))
        set_opts_around(pair_winid, function()
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
