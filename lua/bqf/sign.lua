local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local qftool = require('bqf.qftool')

local function setup()
    cmd('hi default BqfSign ctermfg=14 guifg=Cyan')
    fn.sign_define('BqfSign', {text = ' ^', texthl = 'BqfSign'})
end

local function place(bufnr, lnum)
    bufnr = bufnr or api.nvim_get_current_buf()
    lnum = lnum or api.nvim_win_get_cursor(0)[1]
    local id = fn.sign_place(lnum, 'BqfSignGroup', 'BqfSign', bufnr, {lnum = lnum, priority = 20})
    local qf_all = qftool.getall()
    if not qf_all.signs or type(qf_all.signs) ~= 'table' then
        qf_all.signs = {[lnum] = id}
    else
        qf_all.signs[lnum] = id
    end
end

local function unplace(bufnr, id)
    fn.sign_unplace('BqfSignGroup', {buffer = bufnr, id = id})
    local qf_all = qftool.getall()
    if qf_all.signs then
        if not id then
            qf_all.signs = nil
        else
            for lnum, id0 in pairs(qf_all.signs) do
                if id == id0 then
                    qf_all.signs[lnum] = nil
                    break
                end
            end
        end
    end
end

function M.toggle(rel, bufnr, lnum)
    bufnr = bufnr or api.nvim_get_current_buf()
    lnum = lnum or api.nvim_win_get_cursor(0)[1]
    local signs = fn.sign_getplaced(bufnr, {group = 'BqfSignGroup', lnum = lnum})[1].signs
    if signs and #signs > 0 then
        unplace(bufnr, signs[1].id)
    else
        place(bufnr, lnum)
    end
    if rel ~= 0 then
        cmd(('norm! %s'):format(rel > 0 and 'j' or 'k'))
    end
end

-- only work under map with <Cmd>
function M.vm_toggle(bufnr)
    local mode = api.nvim_get_mode().mode
    vim.validate({
        mode = {
            mode, function(m)
                -- ^V = 0x16
                return m:lower() == 'v' or m == ('%c'):format(0x16)
            end, 'visual mode'
        }
    })
    -- ^[ = 0x1b
    fn.execute(('norm! %c'):format(0x1b))
    bufnr = bufnr or api.nvim_get_current_buf()
    local s_linenr = api.nvim_buf_get_mark(bufnr, '<')[1]
    local e_linenr = api.nvim_buf_get_mark(bufnr, '>')[1]
    for lnum = s_linenr, e_linenr do
        M.toggle(0, bufnr, lnum)
    end
end

function M.reset(bufnr)
    fn.sign_unplace('BqfSignGroup', {buffer = bufnr})
    local qf_all = qftool.getall()
    for lnum in pairs(qf_all.signs or {}) do
        place(bufnr, lnum)
    end
end

function M.clear(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    fn.sign_unplace('BqfSignGroup', {buffer = bufnr})
    local qf_all = qftool.getall()
    qf_all.signs = nil
end

setup()

return M
