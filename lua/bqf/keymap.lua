local M = {}
local api = vim.api

local config = require('bqf.config')

local func_map

local action_funcref = {
    ptogglemode = {mode = 'n', module = 'previewer.handler', funcref = 'toggle_mode()'},
    ptoggleitem = {mode = 'n', module = 'previewer.handler', funcref = 'toggle_item()'},
    ptoggleauto = {mode = 'n', module = 'previewer.handler', funcref = 'toggle()'},
    pscrollup = {mode = 'n', module = 'previewer.handler', funcref = 'scroll(-1)'},
    pscrolldown = {mode = 'n', module = 'previewer.handler', funcref = 'scroll(1)'},
    pscrollorig = {mode = 'n', module = 'previewer.handler', funcref = 'scroll(0)'},
    open = {mode = 'n', module = 'qfwin.handler', funcref = 'open(false)'},
    openc = {mode = 'n', module = 'qfwin.handler', funcref = 'open(true)'},
    split = {mode = 'n', module = 'qfwin.handler', funcref = 'split(false)'},
    vsplit = {mode = 'n', module = 'qfwin.handler', funcref = 'split(true)'},
    tab = {mode = 'n', module = 'qfwin.handler', funcref = 'tabedit(false)'},
    tabb = {mode = 'n', module = 'qfwin.handler', funcref = 'tabedit(true)'},
    prevfile = {mode = '', module = 'qfwin.handler', funcref = 'nav_file(false)'},
    nextfile = {mode = '', module = 'qfwin.handler', funcref = 'nav_file(true)'},
    prevhist = {mode = 'n', module = 'qfwin.handler', funcref = 'nav_history(false)'},
    nexthist = {mode = 'n', module = 'qfwin.handler', funcref = 'nav_history(true)'},
    stoggleup = {mode = 'n', module = 'qfwin.handler', funcref = 'sign_toggle(-1)'},
    stoggledown = {mode = 'n', module = 'qfwin.handler', funcref = 'sign_toggle(1)'},
    stogglevm = {mode = 'x', module = 'qfwin.handler', funcref = 'sign_vm_toggle()'},
    stogglebuf = {mode = 'n', module = 'qfwin.handler', funcref = 'sign_toggle_buf()'},
    sclear = {mode = 'n', module = 'qfwin.handler', funcref = 'sign_clear()'},
    filter = {mode = 'n', module = 'filter.base', funcref = 'run()'},
    filterr = {mode = 'n', module = 'filter.base', funcref = 'run(true)'},
    fzffilter = {mode = 'n', module = 'filter.fzf', funcref = 'run()'}
}

local function funcref_str(tbl_func)
    return ([[<Cmd>lua require('bqf.%s').%s<CR>]]):format(tbl_func.module, tbl_func.funcref)
end

function M.initialize()
    for action, keymap in pairs(func_map) do
        local tbl_func = action_funcref[action]
        if tbl_func and not vim.tbl_isempty(tbl_func) and keymap ~= '' then
            api.nvim_buf_set_keymap(0, tbl_func.mode, keymap, funcref_str(tbl_func), {nowait = true})
        end
    end
end

function M.dispose()
    local function do_unmap(mode, lhs, rhs)
        if rhs:match([[lua require%('bqf%..*'%)]]) then
            api.nvim_buf_del_keymap(0, mode, lhs)
        end
    end

    for _, maparg in pairs(api.nvim_buf_get_keymap(0, 'n')) do
        do_unmap('n', maparg.lhs, maparg.rhs)
    end

    for _, maparg in pairs(api.nvim_buf_get_keymap(0, 'x')) do
        do_unmap('x', maparg.lhs, maparg.rhs)
    end
end

local function init()
    func_map = config.func_map
    vim.validate({func_map = {func_map, 'table'}})
end

init()

return M
