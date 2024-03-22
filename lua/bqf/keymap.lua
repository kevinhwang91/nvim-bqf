---@class BqfKeyMap
local M = {}
local api = vim.api

local config = require('bqf.config')

local funcMap

local actionFuncref = {
    ptogglemode = {
        mode = 'n',
        module = 'preview.handler',
        funcref = 'toggleMode()',
        desc = 'Toggle preview window between normal and max size',
    },
    ptoggleitem = {
        mode = 'n',
        module = 'preview.handler',
        funcref = 'toggleWindow()',
        desc = 'Toggle preview for a quickfix list item',
    },
    ptoggleauto = {
        mode = 'n',
        module = 'preview.handler',
        funcref = 'toggle()',
        desc = 'Toggle auto-preview when cursor moves',
    },
    pscrollup = {
        mode = 'n',
        module = 'preview.handler',
        funcref = 'scroll(-1)',
        desc = 'Scroll up half-page in preview window',
    },
    pscrolldown = {
        mode = 'n',
        module = 'preview.handler',
        funcref = 'scroll(1)',
        desc = 'Scroll down half-page in preview window',
    },
    pscrollorig = {
        mode = 'n',
        module = 'preview.handler',
        funcref = 'scroll(0)',
        desc = 'Scroll back to original position in preview window',
    },
    open = {mode = 'n', module = 'qfwin.handler', funcref = 'open(false)', desc = 'Open the item under the cursor'},
    openc = {
        mode = 'n',
        module = 'qfwin.handler',
        funcref = 'open(true)',
        desc = 'Open the item, and close quickfix window',
    },
    drop = {
        mode = 'n',
        module = 'qfwin.handler',
        funcref = [[open(true, 'drop')]],
        desc = 'Use `drop` to open the item, and close quickfix window',
    },
    split = {
        mode = 'n',
        module = 'qfwin.handler',
        funcref = [[open(true, 'split')]],
        desc = 'Open the item in horizontal split',
    },
    vsplit = {
        mode = 'n',
        module = 'qfwin.handler',
        funcref = [[open(true, 'vsplit')]],
        desc = 'Open the item in vertical split',
    },
    tab = {mode = 'n', module = 'qfwin.handler', funcref = 'tabedit(false)', desc = 'Open the item in a new tab'},
    tabb = {
        mode = 'n',
        module = 'qfwin.handler',
        funcref = 'tabedit(true)',
        desc = 'Open the item in a new tab, but stay in quickfix window',
    },
    tabc = {
        mode = 'n',
        module = 'qfwin.handler',
        funcref = [[open(true, 'tabedit')]],
        desc = 'Open the item in a new tab, and close quickfix window',
    },
    tabdrop = {
        mode = 'n',
        module = 'qfwin.handler',
        funcref = [[open(true, 'tab drop')]],
        desc = 'Use `tab drop` to open the item, and close quickfix window',
    },
    prevfile = {
        mode = '',
        module = 'qfwin.handler',
        funcref = 'navFile(false)',
        desc = 'Go to previous file under the cursor in quickfix window',
    },
    nextfile = {
        mode = '',
        module = 'qfwin.handler',
        funcref = 'navFile(true)',
        desc = 'Go to next file under the cursor in quickfix window',
    },
    prevhist = {
        mode = 'n',
        module = 'qfwin.handler',
        funcref = 'navHistory(false)',
        desc = 'Cycle to next quickfix list in quickfix window',
    },
    nexthist = {
        mode = 'n',
        module = 'qfwin.handler',
        funcref = 'navHistory(true)',
        desc = 'Cycle to previous quickfix list in quickfix window',
    },
    lastleave = {
        mode = '',
        module = 'qfwin.handler',
        funcref = 'restoreWinView()',
        desc = 'Go to last selected item in quickfix window',
    },
    stoggleup = {
        mode = 'n',
        module = 'qfwin.handler',
        funcref = 'signToggle(-1)',
        desc = 'Toggle sign and move cursor up',
    },
    stoggledown = {
        mode = 'n',
        module = 'qfwin.handler',
        funcref = 'signToggle(1)',
        desc = 'Toggle sign and move cursor down',
    },
    stogglevm = {
        mode = 'x',
        module = 'qfwin.handler',
        funcref = 'signVMToggle()',
        desc = 'Toggle multiple signs in visual mode',
    },
    stogglebuf = {
        mode = 'n',
        module = 'qfwin.handler',
        funcref = 'signToggleBuf()',
        desc = 'Toggle signs for same buffers under the cursor',
    },
    sclear = {
        mode = 'n',
        module = 'qfwin.handler',
        funcref = 'signClear()',
        desc = 'Clear the signs in current quickfix list',
    },
    filter = {mode = 'n', module = 'filter.base', funcref = 'run()', desc = 'Create new list for signed items'},
    filterr = {mode = 'n', module = 'filter.base', funcref = 'run(true)', desc = 'Create new list for non-signed items',},
    fzffilter = {mode = 'n', module = 'filter.fzf', funcref = 'run()', desc = 'Enter fzf mode'},
}

local function funcrefStr(tblFunc)
    return ([[<Cmd>lua require('bqf.%s').%s<CR>]]):format(tblFunc.module, tblFunc.funcref)
end

function M.initialize()
    for action, keymap in pairs(funcMap) do
        local tblFunc = actionFuncref[action]
        if tblFunc and not vim.tbl_isempty(tblFunc) and keymap ~= '' then
            api.nvim_buf_set_keymap(
                0,
                tblFunc.mode,
                keymap,
                funcrefStr(tblFunc),
                {desc = tblFunc.desc, nowait = true}
            )
        end
    end

    if vim.o.mouse:match('[na]') ~= nil and config.enable_mouse then
        api.nvim_buf_set_keymap(
            0,
            'n',
            '<2-LeftMouse>',
            '<CR>',
            {desc = 'Open the item under the cursor', nowait = true, noremap = false}
        )
    end
end

---
---@param bufnr? number
function M.dispose(bufnr)
    local function doUnmap(mode, lhs, rhs)
        if type(rhs) == 'string' and rhs:match([[lua require%('bqf%..*'%)]]) then
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
