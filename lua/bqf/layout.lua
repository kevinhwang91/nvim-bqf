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
            local resized_win = fn.winnr('k')
            local resized_hei = fn.winheight(resized_win)
            cmd('winc J')
            cmd(string.format('%dresize %d', resized_win, resized_hei))
            qf_pos = qfpos.get_pos(qf_winid, file_winid)
        end
    end
    return qf_pos
end

local function adjust_width(qf_winid, file_winid, qf_pos)
    local qf_wid = api.nvim_win_get_width(qf_winid)
    if vim.o.winwidth > qf_wid then
        local qf_win, file_win = fn.win_id2win(qf_winid), fn.win_id2win(file_winid)
        if qf_pos[1] == 'right' then
            local width = api.nvim_win_get_width(file_winid) -
                              (vim.o.winwidth - api.nvim_win_get_width(qf_winid))
            cmd(string.format('vert %dresize %d', file_win, width))
        else
            cmd(string.format('vert %dresize %d', qf_win, vim.o.winwidth))
        end
    end
end

local function adjust_height(qf_winid, file_winid, qf_pos)
    local qf_win, file_win = fn.win_id2win(qf_winid), fn.win_id2win(file_winid)
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
        cmd(string.format('%dresize %s%d', qf_win, inc_hei > 0 and '+' or '', inc_hei))
    elseif rel_pos == 'below' then
        vim.wo[qf_winid].winfixheight = false
        cmd(string.format('%dresize %s%d', file_win, inc_hei > 0 and '' or '+', -inc_hei))
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
        wmagic.revert_adjacent_wins(qf_winid, file_winid, qf_pos, true)
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
    local qf_win, file_win = fn.win_id2win(qf_winid), fn.win_id2win(file_winid)
    local qf_win_j, qf_win_l, qf_hei, qf_wid
    utils.win_execute(qf_winid, function()
        qf_win_j, qf_win_l = fn.winnr('j'), fn.winnr('l')
        qf_hei, qf_wid = api.nvim_win_get_height(0), api.nvim_win_get_width(0)
    end)

    if magic_window then
        update_allfixhei(false)
        wmagic.revert_adjacent_wins(qf_winid, file_winid, qf_pos, false)
        update_allfixhei(true)
    end

    local cur_winid = api.nvim_get_current_win()
    if vim.o.equalalways and fn.winnr('$') > 2 then
        -- close quickfix window in tab or floating window can prevent quickfix window make other
        -- windows equal after closing quickfix window
        cmd('noa tabnew')
        cmd(string.format('noa call nvim_win_close(%d, v:false)', qf_winid))
        cmd('noa bw')
    else
        cmd(string.format('noa call nvim_win_close(%d, v:false)', qf_winid))
    end

    if api.nvim_win_is_valid(file_winid) and cur_winid == qf_winid then
        -- current window is a quickfix window, go back file window
        cmd(string.format('noa call nvim_set_current_win(%d)', file_winid))
    else
        cmd(string.format('noa call nvim_set_current_win(%d)', cur_winid))
    end

    local rel_pos = qf_pos[1]
    if rel_pos == 'right' and qf_win_l ~= qf_win then
        cmd(string.format('vert %dresize +%d', file_win, qf_wid + 1))
    elseif rel_pos == 'below' and qf_win_j ~= qf_win then
        cmd(string.format('%dresize +%d', file_win, qf_hei + 1))
    end

    cmd('doautocmd WinEnter')
end

function M.valid_qf_win()
    local win_h, win_j, win_k, win_l = fn.winnr('h'), fn.winnr('j'), fn.winnr('k'), fn.winnr('l')
    return not (win_h == win_j and win_h == win_k and win_h == win_l and win_j == win_k and win_j ==
               win_l and win_k == win_l)
end

setup()

return M
