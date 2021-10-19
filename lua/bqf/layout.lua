local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local qfs = require('bqf.qfwin.session')
local wpos = require('bqf.wpos')
local config = require('bqf.config')

local auto_resize_height
local POS

local function fix_default_qf(qwinid, pwinid, qf_type, qf_pos)
    local qf_win = fn.win_id2win(qwinid)
    if qf_type == 'qf' and fn.winnr('$') == qf_win then
        if qf_pos[1] == POS.UNKNOWN and qf_pos[2] == POS.UNKNOWN then
            local above_winid = fn.win_getid(fn.winnr('k'))
            local heifix_tbl = {}
            for _, winid in ipairs(wpos.find_bottom_wins()) do
                if winid ~= qwinid then
                    heifix_tbl[winid] = vim.wo[winid].winfixheight
                    vim.wo[winid].winfixheight = true
                end
            end
            local above_hei = api.nvim_win_get_height(above_winid)
            cmd('winc J')
            for winid, value in pairs(heifix_tbl) do
                vim.wo[winid].winfixheight = value
            end
            api.nvim_win_set_height(above_winid, above_hei)
            qf_pos = wpos.get_pos(qwinid, pwinid)
        end
    end
    return qf_pos
end

local function adjust_width(qwinid, pwinid, qf_pos)
    local qf_wid = api.nvim_win_get_width(qwinid)
    if vim.o.winwidth > qf_wid then
        if qf_pos[1] == POS.RIGHT then
            local width = api.nvim_win_get_width(pwinid) - (vim.o.winwidth - qf_wid)
            api.nvim_win_set_width(pwinid, width)
        else
            api.nvim_win_set_width(qwinid, vim.o.winwidth)
        end
    end
end

local function adjust_height(qwinid, pwinid, qf_pos)
    local qlist = qfs.get(qwinid):list()
    local size = math.max(qlist:get_qflist({size = 0}).size, 1)
    local qf_hei = api.nvim_win_get_height(qwinid)
    local inc_hei = 0
    local ok, init_height = pcall(api.nvim_win_get_var, qwinid, 'init_height')
    if not ok then
        init_height = qf_hei
        api.nvim_win_set_var(qwinid, 'init_height', init_height)
    end
    if qf_hei < init_height then
        inc_hei = init_height - qf_hei
        qf_hei = init_height
    end

    if size < qf_hei then
        inc_hei = inc_hei + size - qf_hei
    end

    if inc_hei == 0 then
        return
    end

    local rel_pos, abs_pos = unpack(qf_pos)
    if rel_pos == POS.ABOVE or abs_pos == POS.TOP or abs_pos == POS.BOTTOM then
        api.nvim_win_set_height(qwinid, api.nvim_win_get_height(qwinid) + inc_hei)
    elseif rel_pos == POS.BELOW then
        vim.wo[qwinid].winfixheight = false
        api.nvim_win_set_height(pwinid, api.nvim_win_get_height(pwinid) - inc_hei)
        vim.wo[qwinid].winfixheight = true
    end
end

function M.initialize(qwinid)
    local qs = qfs.get(qwinid)
    local qlist = qs:list()
    local pwinid = qs:pwinid()
    local qf_pos = wpos.get_pos(qwinid, pwinid)
    qf_pos = fix_default_qf(qwinid, pwinid, qlist.qf_type, qf_pos)
    adjust_width(qwinid, pwinid, qf_pos)
    if auto_resize_height then
        adjust_height(qwinid, pwinid, qf_pos)
    end
end

function M.valid_qf_win()
    local win_h, win_j, win_k, win_l = fn.winnr('h'), fn.winnr('j'), fn.winnr('k'), fn.winnr('l')
    return not (win_h == win_j and win_h == win_k and win_h == win_l and win_j == win_k and win_j ==
               win_l and win_k == win_l)
end

local function init()
    auto_resize_height = config.auto_resize_height
    POS = wpos.POS
end

init()

return M
