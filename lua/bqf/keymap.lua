local M = {}
local api = vim.api

local config = require('bqf.config')

local func_map

local action_funcref = {
    open = {mode = 'n', module = 'jump', funcref = 'open(false)'},
    openc = {mode = 'n', module = 'jump', funcref = 'open(true)'},
    split = {mode = 'n', module = 'jump', funcref = 'split(false)'},
    vsplit = {mode = 'n', module = 'jump', funcref = 'split(true)'},
    tab = {mode = 'n', module = 'jump', funcref = 'tabedit(false)'},
    tabb = {mode = 'n', module = 'jump', funcref = 'tabedit(true)'},
    ptogglemode = {mode = 'n', module = 'preview', funcref = 'toggle_mode()'},
    ptoggleitem = {mode = 'n', module = 'preview', funcref = 'toggle_item()'},
    ptoggleauto = {mode = 'n', module = 'preview', funcref = 'toggle()'},
    pscrollup = {mode = 'n', module = 'preview', funcref = 'scroll(-1)'},
    pscrolldown = {mode = 'n', module = 'preview', funcref = 'scroll(1)'},
    pscrollorig = {mode = 'n', module = 'preview', funcref = 'scroll(0)'},
    prevfile = {mode = 'n', module = 'qftool', funcref = 'file(false)'},
    nextfile = {mode = 'n', module = 'qftool', funcref = 'file(true)'},
    prevhist = {mode = 'n', module = 'qftool', funcref = 'history(false)'},
    nexthist = {mode = 'n', module = 'qftool', funcref = 'history(true)'},
    stoggleup = {mode = 'n', module = 'sign', funcref = 'toggle(-1)'},
    stoggledown = {mode = 'n', module = 'sign', funcref = 'toggle(1)'},
    stogglevm = {mode = 'x', module = 'sign', funcref = 'vm_toggle()'},
    sclear = {mode = 'n', module = 'sign', funcref = 'clear()'},
    filter = {mode = 'n', module = 'filter.base', funcref = 'run()'},
    filterr = {mode = 'n', module = 'filter.base', funcref = 'run(true)'},
    fzffilter = {mode = 'n', module = 'filter.fzf', funcref = 'run()'}
}

local function setup()
    func_map = config.func_map
    assert(type(func_map) == 'table', 'func_map expect a table type')
end

local function funcref_str(tbl_func)
    return string.format([[<Cmd>lua require('bqf.%s').%s<CR>]], tbl_func.module, tbl_func.funcref)
end

function M.buf_map()
    for action, keymap in pairs(func_map) do
        local tbl_func = action_funcref[action]
        if tbl_func and not vim.tbl_isempty(tbl_func) and keymap ~= '' then
            api.nvim_buf_set_keymap(0, tbl_func.mode, keymap, funcref_str(tbl_func), {nowait = true})
        end
    end
end

setup()

return M
