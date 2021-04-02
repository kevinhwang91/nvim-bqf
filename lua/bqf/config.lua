local config = {}

local function setup()
    local bqf = require('bqf')
    config = vim.tbl_deep_extend('keep', bqf._config or {}, {
        auto_enable = true,
        magic_window = true,
        auto_resize_height = true,
        preview = {
            auto_preview = true,
            border_chars = {'│', '│', '─', '─', '╭', '╮', '╰', '╯', '█'},
            delay_syntax = 50,
            win_height = 15,
            win_vheight = 15
        },
        func_map = {
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
            stoggleup = '<S-Tab>',
            stoggledown = '<Tab>',
            stogglevm = '<Tab>',
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
                    ['ctrl-q'] = 'signtoggle'
                },
                extra_opts = {'--bind', 'ctrl-o:toggle-all'}
            }
        }
    })
    bqf._config = nil
end

setup()

return config
