local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local auto_resize_height
local magic_window

local qfs = require('bqf.qfsession')
local qfpos = require('bqf.qfpos')
local qftool = require('bqf.qftool')
local config = require('bqf.config')
local wmagic = require('bqf.magicwin')
local utils = require('bqf.utils')

local function setup()
    magic_window = config.magic_window
    auto_resize_height = config.auto_resize_height
end

local function store_fwin_opts(qf_winid, file_winid)
    local fwin_o = vim.wo[file_winid]
    qfs[qf_winid].fwin_opts = {
        wrap = fwin_o.wrap,
        cursorline = fwin_o.cursorline,
        number = fwin_o.number,
        relativenumber = fwin_o.relativenumber,
        signcolumn = fwin_o.signcolumn,
        foldcolumn = fwin_o.foldcolumn,
        list = fwin_o.list,
        colorcolumn = fwin_o.colorcolumn,
        winhighlight = fwin_o.winhighlight,
        foldenable = fwin_o.foldenable
    }
end

local function fix_default_qf(qf_winid, file_winid, qf_type, qf_pos)
    local qf_win = fn.win_id2win(qf_winid)
    if qf_type == 'qf' and fn.winnr('$') == qf_win then
        if qf_pos[1] == 'unknown' and qf_pos[2] == 'unknown' then
            local above_winid = fn.win_getid(fn.winnr('k'))
            local hei = api.nvim_win_get_height(above_winid)
            cmd('winc J')
            api.nvim_win_set_height(above_winid, hei)
            qf_pos = qfpos.get_pos(qf_winid, file_winid)
        end
    end
    return qf_pos
end

local function adjust_width(qf_winid, file_winid, qf_pos)
    local qf_wid = api.nvim_win_get_width(qf_winid)
    if vim.o.winwidth > qf_wid then
        if qf_pos[1] == 'right' then
            local width = api.nvim_win_get_width(file_winid) - (vim.o.winwidth - qf_wid)
            api.nvim_win_set_width(file_winid, width)
        else
            api.nvim_win_set_width(qf_winid, vim.o.winwidth)
        end
    end
end

local function adjust_height(qf_winid, file_winid, qf_pos)
    local size = math.max(qftool.get({size = 0}).size, 1)
    local qf_hei = api.nvim_win_get_height(qf_winid)
    local inc_hei = 0
    qfs[qf_winid].init_height = qfs[qf_winid].init_height or qf_hei
    if qf_hei < qfs[qf_winid].init_height then
        inc_hei = qfs[qf_winid].init_height - qf_hei
        qf_hei = qfs[qf_winid].init_height
    end

    if size < qf_hei then
        inc_hei = inc_hei + size - qf_hei
    end

    if inc_hei == 0 then
        return
    end

    local rel_pos, abs_pos = unpack(qf_pos)
    if rel_pos == 'above' or abs_pos == 'top' or abs_pos == 'bottom' then
        api.nvim_win_set_height(qf_winid, api.nvim_win_get_height(qf_winid) + inc_hei)
    elseif rel_pos == 'below' then
        vim.wo[qf_winid].winfixheight = false
        api.nvim_win_set_height(file_winid, api.nvim_win_get_height(file_winid) - inc_hei)
        vim.wo[qf_winid].winfixheight = true
    end
end

local function update_allfixhei(wfh)
    local holder = qfs.holder()
    local cur_tab_wins = api.nvim_tabpage_list_wins(0)
    for winid in pairs(holder) do
        if winid and vim.tbl_contains(cur_tab_wins, winid) then
            vim.wo[winid].winfixheight = wfh
        end
    end
end

function M.init(qf_winid, file_winid, qf_type)
    local qf_pos = qfpos.get_pos(qf_winid, file_winid)
    qf_pos = fix_default_qf(qf_winid, file_winid, qf_type, qf_pos)
    adjust_width(qf_winid, file_winid, qf_pos)
    if auto_resize_height then
        adjust_height(qf_winid, file_winid, qf_pos)
    end

    if magic_window then
        update_allfixhei(false)
        wmagic.revert_enter_adjacent_wins(qf_winid, file_winid, qf_pos)
        update_allfixhei(true)
    end
    -- store file winodw's options for subsequent use
    store_fwin_opts(qf_winid, file_winid)
end

function M.restore_fwin_opts()
    local opts = vim.b.bqf_fwin_opts
    vim.b.bqf_fwin_opts = nil
    if not opts or vim.tbl_isempty(opts) then
        return
    end

    -- TODO why can't set currentline directly?
    local cursorline = opts.cursorline
    local winid = api.nvim_get_current_win()
    vim.defer_fn(function()
        vim.wo[winid].cursorline = cursorline
    end, 100)
    opts.cursorline = nil
    for opt, val in pairs(opts) do
        if vim.wo[opt] ~= val then
            vim.wo[opt] = val
        end
    end
end

function M.close_win(qf_winid)
    if qf_winid < 0 or not api.nvim_win_is_valid(qf_winid) then
        return
    end

    local file_winid = qftool.filewinid(qf_winid)
    local qf_pos = qfpos.get_pos(qf_winid, file_winid)
    local qf_win = fn.win_id2win(qf_winid)
    local qf_win_j, qf_win_l
    utils.win_execute(qf_winid, function()
        qf_win_j, qf_win_l = fn.winnr('j'), fn.winnr('l')
    end)

    local qf_hei, qf_wid, f_hei, f_wid
    local rel_pos = qf_pos[1]
    if rel_pos == 'right' and qf_win_l ~= qf_win then
        qf_wid, f_wid = api.nvim_win_get_width(qf_winid), api.nvim_win_get_width(file_winid)
    elseif rel_pos == 'below' and qf_win_j ~= qf_win then
        qf_hei, f_hei = api.nvim_win_get_height(qf_winid), api.nvim_win_get_height(file_winid)
    end

    local wmagic_defer_cb
    if magic_window then
        update_allfixhei(false)
        wmagic_defer_cb = wmagic.revert_close_adjacent_wins(qf_winid, file_winid, qf_pos)
        update_allfixhei(true)
    end

    local cur_winid = api.nvim_get_current_win()

    if vim.o.equalalways and fn.winnr('$') > 2 then
        -- close quickfix window in other tab or floating window can prevent nvim make windows equal
        -- after closing quickfix window, but in other tab can't run
        -- 'win_enter_ext(wp, false, true, false, true, true)' which triggers 'WinEnter', 'BufEnter'
        -- and 'CursorMoved' events. Search 'do_autocmd_winclosed' in src/nvim/window.c for details.
        local scratch = api.nvim_create_buf(false, true)
        api.nvim_open_win(scratch, true, {
            relative = 'win',
            width = 1,
            height = 1,
            row = 0,
            col = 0,
            style = 'minimal'
        })
        api.nvim_win_close(qf_winid, false)
        cmd(('noa bw %d'):format(scratch))
    else
        api.nvim_win_close(qf_winid, false)
    end

    if api.nvim_win_is_valid(file_winid) and cur_winid == qf_winid then
        -- current window is a quickfix window, go back file window
        api.nvim_set_current_win(file_winid)
    end

    if rel_pos == 'right' and qf_win_l ~= qf_win then
        api.nvim_win_set_width(file_winid, qf_wid + f_wid + 1)
    elseif rel_pos == 'below' and qf_win_j ~= qf_win then
        api.nvim_win_set_height(file_winid, qf_hei + f_hei + 1)
    end

    if wmagic_defer_cb then
        wmagic_defer_cb()
    end
end

function M.valid_qf_win()
    local win_h, win_j, win_k, win_l = fn.winnr('h'), fn.winnr('j'), fn.winnr('k'), fn.winnr('l')
    return not (win_h == win_j and win_h == win_k and win_h == win_l and win_j == win_k and win_j ==
               win_l and win_k == win_l)
end

setup()

return M
