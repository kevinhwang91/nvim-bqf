---@class BqfKeyMap
local M = {}
local api = vim.api

local config = require('bqf.config')

local funcMap

local actionFuncref = {
    ptogglemode = {mode = 'n', module = 'preview.handler', funcref = 'toggleMode()'},
    ptoggleitem = {mode = 'n', module = 'preview.handler', funcref = 'toggleItem()'},
    ptoggleauto = {mode = 'n', module = 'preview.handler', funcref = 'toggle()'},
    pscrollup = {mode = 'n', module = 'preview.handler', funcref = 'scroll(-1)'},
    pscrolldown = {mode = 'n', module = 'preview.handler', funcref = 'scroll(1)'},
    pscrollorig = {mode = 'n', module = 'preview.handler', funcref = 'scroll(0)'},
    open = {mode = 'n', module = 'qfwin.handler', funcref = 'open(false)'},
    openc = {mode = 'n', module = 'qfwin.handler', funcref = 'open(true)'},
    drop = {mode = 'n', module = 'qfwin.handler', funcref = [[open(true, 'drop')]]},
    split = {mode = 'n', module = 'qfwin.handler', funcref = [[open(true, 'split')]]},
    vsplit = {mode = 'n', module = 'qfwin.handler', funcref = [[open(true, 'vsplit')]]},
    tab = {mode = 'n', module = 'qfwin.handler', funcref = 'tabedit(false)'},
    tabb = {mode = 'n', module = 'qfwin.handler', funcref = 'tabedit(true)'},
    tabc = {mode = 'n', module = 'qfwin.handler', funcref = [[open(true, 'tabedit')]]},
    tabdrop = {mode = 'n', module = 'qfwin.handler', funcref = [[open(true, 'tab drop')]]},
    prevfile = {mode = '', module = 'qfwin.handler', funcref = 'navFile(false)'},
    nextfile = {mode = '', module = 'qfwin.handler', funcref = 'navFile(true)'},
    prevhist = {mode = 'n', module = 'qfwin.handler', funcref = 'navHistory(false)'},
    nexthist = {mode = 'n', module = 'qfwin.handler', funcref = 'navHistory(true)'},
    lastleave = {mode = '', module = 'qfwin.handler', funcref = 'restoreWinView()'},
    stoggleup = {mode = 'n', module = 'qfwin.handler', funcref = 'signToggle(-1)'},
    stoggledown = {mode = 'n', module = 'qfwin.handler', funcref = 'signToggle(1)'},
    stogglevm = {mode = 'x', module = 'qfwin.handler', funcref = 'signVMToggle()'},
    stogglebuf = {mode = 'n', module = 'qfwin.handler', funcref = 'signToggleBuf()'},
    sclear = {mode = 'n', module = 'qfwin.handler', funcref = 'signClear()'},
    filter = {mode = 'n', module = 'filter.base', funcref = 'run()'},
    filterr = {mode = 'n', module = 'filter.base', funcref = 'run(true)'},
    fzffilter = {mode = 'n', module = 'filter.fzf', funcref = 'run()'}
}

local function funcrefStr(tblFunc)
    return ([[<Cmd>lua require('bqf.%s').%s<CR>]]):format(tblFunc.module, tblFunc.funcref)
end

function M.initialize()
    for action, keymap in pairs(funcMap) do
        local tblFunc = actionFuncref[action]
        if tblFunc and not vim.tbl_isempty(tblFunc) and keymap ~= '' then
            api.nvim_buf_set_keymap(0, tblFunc.mode, keymap, funcrefStr(tblFunc), {nowait = true})
        end
    end
    api.nvim_buf_set_keymap(0, 'n', '<2-LeftMouse>', '<CR>', {nowait = true, noremap = false})
end

---
---@param bufnr? number
function M.dispose(bufnr)
    local function doUnmap(mode, lhs, rhs)
        if rhs:match([[lua require%('bqf%..*'%)]]) then
            api.nvim_buf_del_keymap(bufnr or 0, mode, lhs)
        end
    end

    for _, maparg in ipairs(api.nvim_buf_get_keymap(0, 'n')) do
        doUnmap('n', maparg.lhs, maparg.rhs)
    end

    for _, maparg in ipairs(api.nvim_buf_get_keymap(0, 'x')) do
        doUnmap('x', maparg.lhs, maparg.rhs)
    end
end

local function init()
    funcMap = config.func_map
    vim.validate({funcMap = {funcMap, 'table'}})
end

init()

return M
