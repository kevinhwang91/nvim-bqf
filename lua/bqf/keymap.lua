local M = {}
local api = vim.api

local config = require('bqf.config')

local func_map

local def_func_map = {
    open = '<CR>',
    openc = 'o',
    split = '<C-x>',
    vsplit = '<C-v>',
    tab = 't',
    tabb = 'T',
    ptogglemode = 'zp',
    ptoggleitem = 'p',
    ptoggleauto = 'P',
    pscrollup = '<C-b>',
    pscrolldown = '<C-f>',
    pscrollorig = 'zo',
    prevfile = '<C-p>',
    nextfile = '<C-n>',
    prevhist = '<',
    nexthist = '>',
    fzffilter = 'zf'
}

local action_funcref = {
    open = {module = 'jump', funcref = 'open(false)'},
    openc = {module = 'jump', funcref = 'open(true)'},
    split = {module = 'jump', funcref = 'split(false)'},
    vsplit = {module = 'jump', funcref = 'split(true)'},
    tab = {module = 'jump', funcref = 'tabedit(false)'},
    tabb = {module = 'jump', funcref = 'tabedit(true)'},
    ptogglemode = {module = 'preview', funcref = 'toggle_mode()'},
    ptoggleitem = {module = 'preview', funcref = 'toggle_item()'},
    ptoggleauto = {module = 'preview', funcref = 'toggle()'},
    pscrollup = {module = 'preview', funcref = 'scroll(-1)'},
    pscrolldown = {module = 'preview', funcref = 'scroll(1)'},
    pscrollorig = {module = 'preview', funcref = 'scroll(0)'},
    prevfile = {module = 'qftool', funcref = 'file(false)'},
    nextfile = {module = 'qftool', funcref = 'file(true)'},
    prevhist = {module = 'qftool', funcref = 'history(false)'},
    nexthist = {module = 'qftool', funcref = 'history(true)'},
    fzffilter = {module = 'filter.fzf', funcref = 'run()'}
}

local function setup()
    func_map = vim.tbl_deep_extend('force', def_func_map, config.func_map or {})
    assert(type(func_map) == 'table', 'func_map expect a table type')
    config.func_map = func_map
end

local function funcref_str(tbl_func)
    return string.format([[<Cmd>lua require('bqf.%s').%s<CR>]], tbl_func.module, tbl_func.funcref)
end

function M.buf_nmap()
    for action, keymap in pairs(func_map) do
        local tbl_func = action_funcref[action]
        if tbl_func and not vim.tbl_isempty(tbl_func) and keymap ~= '' then
            api.nvim_buf_set_keymap(0, 'n', keymap, funcref_str(tbl_func), {nowait = true})
        end
    end
end

setup()

return M
