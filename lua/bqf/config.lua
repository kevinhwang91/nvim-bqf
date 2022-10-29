---@class BqfConfig
---@field auto_enable boolean
---@field magic_window boolean
---@field auto_resize_height boolean
---@field preview BqfConfigPreview
---@field func_map table<string, string>
---@field filter BqfConfigFilter
local def = {
    auto_enable = true,
    magic_window = true,
    auto_resize_height = false,
    previous_winid_ft_skip = {},
    preview = {
        auto_preview = true,
        border_chars = {'│', '│', '─', '─', '╭', '╮', '╰', '╯', '█'},
        show_title = true,
        delay_syntax = 50,
        win_height = 15,
        win_vheight = 15,
        win_width = 1.0,
        win_vwidth = 1.0,
        wrap = false,
        should_preview_cb = nil
    },
    func_map = {
        open = '<CR>',
        openc = 'o',
        drop = 'O',
        split = '<C-x>',
        vsplit = '<C-v>',
        tab = 't',
        tabb = 'T',
        tabc = '<C-t>',
        tabdrop = '',
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
        lastleave = [['"]],
        stoggleup = '<S-Tab>',
        stoggledown = '<Tab>',
        stogglevm = '<Tab>',
        stogglebuf = [['<Tab>]],
        sclear = 'z<Tab>',
        filter = 'zn',
        filterr = 'zN',
        fzffilter = 'zf'
    },
    filter = {
        fzf = {
            action_for = {
                ['ctrl-t'] = 'tabedit',
                ['ctrl-v'] = 'vsplit',
                ['ctrl-x'] = 'split',
                ['ctrl-q'] = 'signtoggle',
                ['ctrl-c'] = 'closeall'
            },
            extra_opts = {'--bind', 'ctrl-o:toggle-all'}
        }
    }
}
---@class BqfConfigPreview
---@field auto_preview boolean
---@field border_chars string[]
---@field show_title boolean
---@field delay_syntax number
---@field win_height number
---@field win_vheight number
---@field win_width number
---@field win_vwidth number
---@field wrap boolean
---@field should_preview_cb fun(bufnr: number, qwinid: number): boolean

---@class BqfConfigFilter
---@field fzf BqfConfigFilterFzf

---@class BqfConfigFilterFzf
---@field action_for table<string, string>
---@field extra_opts string[]


---@type BqfConfig
local Config = {}

local function init()
    local bqf = require('bqf')
    Config = vim.tbl_deep_extend('keep', bqf._config or {}, def)
    vim.validate({
        auto_enable = {Config.auto_enable, 'boolean'},
        magic_window = {Config.magic_window, 'boolean'},
        auto_resize_height = {Config.auto_resize_height, 'boolean'},
        preview = {Config.preview, 'table'},
        func_map = {Config.func_map, 'table'},
        filter = {Config.filter, 'table'}
    })
    bqf._config = nil
end

init()

return Config
