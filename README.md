# nvim-bqf

The goal of nvim-bqf is to make Neovim's quickfix window better.

<https://user-images.githubusercontent.com/17562139/137736502-91d32251-96a2-4c3f-ba74-65cfd336473e.mp4>

---

In today's era of floating windows, are you afraid to toggle quickfix window to make your eyes
uncomfortable? Are you constantly jumping between the edit window and the quickfix window when you
use quickfix window to refactor because of lacking a sustainable preview window? Do you think
quickfix window lacks a fuzzy search function? At present, nvim-bqf can solve the above problems.

You really don't need any search replace plugins, because nvim-bqf with the built-in function of the
quickfix window allows you to easily search and replace targets.

So why not nvim-bqf?

## Table of contents

- [Table of contents](#table-of-contents)
- [Features](#features)
- [TODO](#todo)
- [Quickstart](#quickstart)
  - [Requirements](#requirements)
  - [Installation](#installation)
  - [Minimal configuration](#minimal-configuration)
  - [Usage](#usage)
    - [Filter with signs](#filter-with-signs)
    - [Fzf mode](#fzf-mode)
    - [Filter items with signs demo](#filter-items-with-signs-demo)
    - [Search and replace demo](#search-and-replace-demo)
- [Documentation](#documentation)
  - [Setup and description](#setup-and-description)
  - [Function table](#function-table)
  - [Buffer Commands](#buffer-commands)
  - [Commands](#commands)
  - [API](#api)
  - [Quickfix context](#quickfix-context)
    - [Why use an additional context?](#why-use-an-additional-context)
    - [Supported keys](#supported-keys)
    - [Simple lua tests for understanding](#simple-lua-tests-for-understanding)
  - [Highlight groups](#highlight-groups)
- [Advanced configuration](#advanced-configuration)
  - [Customize configuration](#customize-configuration)
  - [Integrate with other plugins](#integrate-with-other-plugins)
- [Customize quickfix window (Easter egg)](#customize-quickfix-window-easter-egg)
  - [Format new quickfix](#format-new-quickfix)
  - [Rebuild syntax for quickfix](#rebuild-syntax-for-quickfix)
- [Feedback](#feedback)
- [License](#license)

## Features

- Toggle quickfix window with magic window keep your eyes comfortable
- Extend built-in context of quickfix to build an eye friendly highlighting at preview
- Support convenient actions inside quickfix window, see [Function table](#function-table) below
- Optimize the buffer preview under treesitter to get extreme performance
- Using signs to filter the items of quickfix window
- Integrate [fzf](https://github.com/junegunn/fzf) as a picker/filter in quickfix window
- Mouse supported for preview window

## TODO

- [ ] Find a better way to list history and switch to one
- [ ] Use context field to override the existed configuration
- [ ] Add tests

## Quickstart

### Requirements

- [Neovim](https://github.com/neovim/neovim) 0.7.2 or later
- [fzf](https://github.com/junegunn/fzf) (optional, 0.42.0 later)
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) (optional)

### Installation

Install with [Packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {'kevinhwang91/nvim-bqf'}
```

### Minimal configuration

```lua
use {'kevinhwang91/nvim-bqf', ft = 'qf'}

-- optional
use {'junegunn/fzf', run = function()
    vim.fn['fzf#install']()
end
}

-- optional, highly recommended
use {'nvim-treesitter/nvim-treesitter', run = ':TSUpdate'}
```

The nvim-bqf's preview builds upon the buffers. I highly recommended to use queries
provided by [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
to get more accurate syntax highlighting,
because vim's syntax is very lagging and is extremely bad for the user experience in large files.

> nvim-bqf has optimized the preview performance for treesitter

### Usage

1. If you are familiar with quickfix, use quickfix as usual.
2. If you don't know quickfix well, you can run `:vimgrep /\w\+/j % | copen` under a buffer inside
   nvim to get started quickly.
3. If you want to taste quickfix like demo, check out
   [Integrate with other plugins](#integrate-with-other-plugins), and pick up the configuration you
   like.

#### Filter with signs

1. Press `<Tab>` or `<S-Tab>` to toggle the sign of item
2. Press `zn` or `zN` will create new quickfix list

#### Fzf mode

Press `zf` in quickfix window will enter fzf mode.

fzf in nvim-bqf supports `ctrl-t`/`ctrl-x`/`ctrl-v` key bindings that allow you to open up an item
in a new tab, a new horizontal split, or in a new vertical split.

fzf becomes a quickfix filter and create a new quickfix list when multiple items are selected and
accepted.

nvim-bqf also supports `ctrl-q` to toggle items' sign and adapts `preview-half-page-up`,
`preview-half-page-down` and `toggle-preview` fzf's actions for preview.

Please run `man fzf` and check out `KEY/EVENT BINDINGS` section for details.

There're two ways to adapt fzf's actions for preview function, use `ctrl-f`and `ctrl-b` keys as
example.

1. Make `$FZF_DEFAULT_OPTS` contains
   `--bind=ctrl-f:preview-half-page-down,ctrl-b:preview-half-page-up`;
2. Inject `extra_opts = {'--bind', 'ctrl-f:preview-half-page-down,ctrl-b:preview-half-page-up'}` to
   `setup` function;

#### Filter items with signs demo

<https://user-images.githubusercontent.com/17562139/137736623-e436cb3e-af40-4a00-b08a-b7120d41821e.mp4>

> input `^^` in fzf prompt will find all signed items, `ctrl-o` in fzf mode has bind `toggle-all`

#### Search and replace demo

Using external grep-like program to search `display` and replace it to `show`, but exclude
`session.lua` file.

<https://user-images.githubusercontent.com/17562139/137747257-ff8fb5cf-e437-42e3-b4e4-76c72a0273aa.mp4>

> Demonstrating batch undo just show that quickfix has this feature

## Documentation

### Setup and description

```lua
{
    auto_enable = {
        description = [[Enable nvim-bqf in quickfix window automatically]],
        default = true
    },
    magic_window = {
        description = [[Give the window magic, when the window is splited horizontally, keep
            the distance between the current line and the top/bottom border of neovim unchanged.
            It's a bit like a floating window, but the window is indeed a normal window, without
            any floating attributes.]],
        default = true
    },
    auto_resize_height = {
        description = [[Resize quickfix window height automatically.
            Shrink higher height to size of list in quickfix window, otherwise extend height
            to size of list or to default height (10)]],
        default = false
    },
    preview = {
        auto_preview = {
            description = [[Enable preview in quickfix window automatically]],
            default = true
        },
        border = {
            description = [[The border for preview window,
                `:h nvim_open_win() | call search('border:')`]],
            default = 'rounded',
        },
        show_title = {
            description = [[Show the window title]],
            default = true
        },
        show_scroll_bar = {
            description = [[Show the scroll bar]],
            default = true
        },
        delay_syntax = {
            description = [[Delay time, to do syntax for previewed buffer, unit is millisecond]],
            default = 50
        },
        win_height = {
            description = [[The height of preview window for horizontal layout,
                large value (like 999) perform preview window as a "full" mode]],
            default = 15
        },
        win_vheight = {
            description = [[The height of preview window for vertical layout]],
            default = 15
        },
        winblend = {
            description = [[The winblend for preview window, `:h winblend`]],
            default = 12
        }
        wrap = {
            description = [[Wrap the line, `:h wrap` for detail]],
            default = false
        },
        buf_label = {
            description = [[Add label of current item buffer at the end of the item line]],
            default = true
        },
        should_preview_cb = {
            description = [[A callback function to decide whether to preview while switching buffer,
                with (bufnr: number, qwinid: number) parameters]],
            default = nil
        }
    },
    func_map = {
        description = [[The table for {function = key}]],
        default = [[see ###Function table for detail]],
    },
    filter = {
        fzf = {
            action_for = {
                ['ctrl-t'] = {
                    description = [[Press ctrl-t to open up the item in a new tab]],
                    default = 'tabedit'
                },
                ['ctrl-v'] = {
                    description = [[Press ctrl-v to open up the item in a new vertical split]],
                    default = 'vsplit'
                },
                ['ctrl-x'] = {
                    description = [[Press ctrl-x to open up the item in a new horizontal split]],
                    default = 'split'
                },
                ['ctrl-q'] = {
                    description = [[Press ctrl-q to toggle sign for the selected items]],
                    default = 'signtoggle'
                },
                ['ctrl-c'] = {
                    description = [[Press ctrl-c to close quickfix window and abort fzf]],
                    default = 'closeall'
                }
            },
            extra_opts = {
                description = 'Extra options for fzf',
                default = {'--bind', 'ctrl-o:toggle-all'}
            }
        }
    }
}
```

Before loading any modules, `:lua =require('bqf.config')` will show you everything
about current configuration.

### Function table

`Function` only works in the quickfix window, keys can be customized by
`lua require('bqf').setup({func_map = {}})`.

> You can reference [Customize configuration](#customize-configuration) to configure `func_map`.

| Function    | Action                                                     | Def Key   |
| ----------- | ---------------------------------------------------------- | --------- |
| open        | open the item under the cursor                             | `<CR>`    |
| openc       | open the item, and close quickfix window                   | `o`       |
| drop        | use `drop` to open the item, and close quickfix window     | `O`       |
| tabdrop     | use `tab drop` to open the item, and close quickfix window |           |
| tab         | open the item in a new tab                                 | `t`       |
| tabb        | open the item in a new tab, but stay in quickfix window    | `T`       |
| tabc        | open the item in a new tab, and close quickfix window      | `<C-t>`   |
| split       | open the item in horizontal split                          | `<C-x>`   |
| vsplit      | open the item in vertical split                            | `<C-v>`   |
| prevfile    | go to previous file under the cursor in quickfix window    | `<C-p>`   |
| nextfile    | go to next file under the cursor in quickfix window        | `<C-n>`   |
| prevhist    | cycle to previous quickfix list in quickfix window         | `<`       |
| nexthist    | cycle to next quickfix list in quickfix window             | `>`       |
| lastleave   | go to last selected item in quickfix window                | `'"`      |
| stoggleup   | toggle sign and move cursor up                             | `<S-Tab>` |
| stoggledown | toggle sign and move cursor down                           | `<Tab>`   |
| stogglevm   | toggle multiple signs in visual mode                       | `<Tab>`   |
| stogglebuf  | toggle signs for same buffers under the cursor             | `'<Tab>`  |
| sclear      | clear the signs in current quickfix list                   | `z<Tab>`  |
| pscrollup   | scroll up half-page in preview window                      | `<C-b>`   |
| pscrolldown | scroll down half-page in preview window                    | `<C-f>`   |
| pscrollorig | scroll back to original position in preview window         | `zo`      |
| ptogglemode | toggle preview window between normal and max size          | `zp`      |
| ptoggleitem | toggle preview for a quickfix list item                    | `p`       |
| ptoggleauto | toggle auto-preview when cursor moves                      | `P`       |
| filter      | create new list for signed items                           | `zn`      |
| filterr     | create new list for non-signed items                       | `zN`      |
| fzffilter   | enter fzf mode                                             | `zf`      |

Additional mouse supported:

1. `<ScrollWheelUp>` and `<ScrollWheelDown>`: Scroll preview window.
2. `<2-LeftMouse>`:
   - In quickfix window: Type `<CR>`;
   - In preview window: Jump to the location even it has scrolled;

### Buffer Commands

- `BqfEnable`: Enable nvim-bqf in quickfix window
- `BqfDisable`: Disable nvim-bqf in quickfix window
- `BqfToggle`: Toggle nvim-bqf in quickfix window

### Commands

- `BqfAutoToggle`: Toggle nvim-bqf enable automatically

### API

[bqf.lua](./lua/bqf.lua)

### Quickfix context

Vim grant users an ability to stuff a context to quickfix, please run `:help quickfix-context` for
detail.

#### Why use an additional context?

nvim-bqf will use the context to implement missing features of quickfix. To get better highlighting
experience, nvim-bqf processeds the vim regrex pattern and
[lsp range](https://microsoft.github.io/language-server-protocol/specification#range) from the
context additionally.

The context's format that can be processed by nvim-bqf is:

```lua
local context = {context = {bqf = {}}}
```

nvim-bqf only occupies a key of `context`, which makes nvim-bqf get along well with other plugins in
context of the quickfix window.

#### Supported keys

```lua
context = {
    bqf = {
        pattern_hl = {
            description = [[search pattern from current position]],
            type = 'string'
        },
        lsp_ranges_hl = {
            description = [[a list of lsp range. The length of list is equal to the items',
            pairwise correspondence each other]],
            type = 'table'
        }
    }
}
```

#### Simple lua tests for understanding

```lua
local cmd = vim.cmd
local api = vim.api
local fn = vim.fn

local function createQf()
    cmd('enew')
    local bufnr = api.nvim_get_current_buf()
    local lines = {}
    for i = 1, 3 do
        table.insert(lines, ('%d | %s'):format(i, fn.strftime('%F')))
    end
    api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    fn.setqflist({
        {bufnr = bufnr, lnum = 1, col = 5}, {bufnr = bufnr, lnum = 2, col = 10},
        {bufnr = bufnr, lnum = 3, col = 13}
    })
end

function _G.bqfPattern()
    createQf()
    fn.setqflist({}, 'r', {context = {bqf = {pattern_hl = [[\d\+]]}}, title = 'patternHl'})
    cmd('cw')
end

function _G.bqfLspRanges()
    createQf()
    local lspRanges = {}
    table.insert(lspRanges,
        {start = {line = 0, character = 4}, ['end'] = {line = 0, character = 8}})
    table.insert(lspRanges,
        {start = {line = 1, character = 9}, ['end'] = {line = 1, character = 11}})
    table.insert(lspRanges,
        {start = {line = 2, character = 12}, ['end'] = {line = 2, character = 14}})
    fn.setqflist({}, 'r', {context = {bqf = {lsp_ranges_hl = lspRanges}}, title = 'lspRangesHl'})
    cmd('cw')
end

function _G.qfRanges()
    createQf()
    local items = fn.getqflist()
    local it1, it2, it3 = items[1], items[2], items[3]
    it1.end_lnum, it1.end_col = it1.lnum, it1.col + 4
    it2.end_lnum, it2.end_col = it2.lnum, it2.col + 2
    it3.end_lnum, it3.end_col = it3.lnum, it3.col + 2
    fn.setqflist({}, 'r', {items = items, title = 'qfRangesHl'})
    cmd('cw')
end

-- Save and source me(`so %`). Run `:lua bqfPattern()`, `:lua bqfLspRanges()` and `:lua qfRanges()`
```

nvim-bqf actually works with context in
[Integrate with other plugins](#integrate-with-other-plugins).

### Highlight groups

```vim
hi default link BqfPreviewFloat Normal
hi default link BqfPreviewBorder FloatBorder
hi default link BqfPreviewTitle Title
hi default link BqfPreviewThumb PmenuThumb
hi default link BqfPreviewSbar PmenuSbar
hi default link BqfPreviewCursor Cursor
hi default link BqfPreviewCursorLine CursorLine
hi default link BqfPreviewRange IncSearch
hi default link BqfPreviewBufLabel BqfPreviewRange
hi default BqfSign ctermfg=14 guifg=Cyan
```

- `BqfPreviewFloat`: Floating window.
- `BqfPreviewBorder`: Border of floating window.
- `BqfPreviewTitle`: Title of preview window.
- `BqfPreviewThumb`: Thumb of preview window.
- `BqfPreviewSbar`: Scroll bar of preview window, only take effect if the border is missing right.
- `BqfPreviewCursor`: The cursor format `[lnum, col]` in preview window.
- `BqfPreviewCursorLine`: The text line of the cursor in preview window.
- `BqfPreviewRange`: The range format `[lnum, col, range]`, which is produced by
  `pattern_hl`, `lsp_ranges_hl` and quickfix range.
- `BqfPreviewBufLabel`: The index and count of the buffer under the cursor
- `BqfSign`: The sign in quickfix window.

## Advanced configuration

### Customize configuration

```lua
vim.cmd([[
    hi BqfPreviewBorder guifg=#3e8e2d ctermfg=71
    hi BqfPreviewTitle guifg=#3e8e2d ctermfg=71
    hi BqfPreviewThumb guibg=#3e8e2d ctermbg=71
    hi link BqfPreviewRange Search
]])

require('bqf').setup({
    auto_enable = true,
    auto_resize_height = true, -- highly recommended enable
    preview = {
        win_height = 12,
        win_vheight = 12,
        delay_syntax = 80,
        border = {'┏', '━', '┓', '┃', '┛', '━', '┗', '┃'},
        show_title = false,
        should_preview_cb = function(bufnr, qwinid)
            local ret = true
            local bufname = vim.api.nvim_buf_get_name(bufnr)
            local fsize = vim.fn.getfsize(bufname)
            if fsize > 100 * 1024 then
                -- skip file size greater than 100k
                ret = false
            elseif bufname:match('^fugitive://') then
                -- skip fugitive buffer
                ret = false
            end
            return ret
        end
    },
    -- make `drop` and `tab drop` to become preferred
    func_map = {
        drop = 'o',
        openc = 'O',
        split = '<C-s>',
        tabdrop = '<C-t>',
        -- set to empty string to disable
        tabc = '',
        ptogglemode = 'z,',
    },
    filter = {
        fzf = {
            action_for = {['ctrl-s'] = 'split', ['ctrl-t'] = 'tab drop'},
            extra_opts = {'--bind', 'ctrl-o:toggle-all', '--prompt', '> '}
        }
    }
})
```

### Integrate with other plugins

```lua
local fn = vim.fn
local cmd = vim.cmd
local api = vim.api

cmd([[
    packadd nvim-bqf
    packadd fzf
    packadd nvim-treesitter
    packadd vim-grepper
    packadd coc.nvim
]])

-- https://github.com/mhinz/vim-grepper
vim.g.grepper = {tools = {'rg', 'grep'}, searchreg = 1}
cmd(([[
    aug Grepper
        au!
        au User Grepper ++nested %s
    aug END
]]):format([[call setqflist([], 'r', {'context': {'bqf': {'pattern_hl': '\%#' . getreg('/')}}})]]))

-- try `gsiw` under word
cmd([[
    nmap gs  <plug>(GrepperOperator)
    xmap gs  <plug>(GrepperOperator)
]])

-- https://github.com/neoclide/coc.nvim
-- if you use coc-fzf, you should disable its CocLocationsChange event
-- to make bqf work for <Plug>(coc-references)

-- vim.schedule(function()
--     cmd('au! CocFzfLocation User CocLocationsChange')
-- end)
vim.g.coc_enable_locationlist = 0
cmd([[
    aug Coc
        au!
        au User CocLocationsChange lua _G.jumpToLoc()
    aug END
]])

cmd([[
    nmap <silent> gr <Plug>(coc-references)
    nnoremap <silent> <leader>qd <Cmd>lua _G.diagnostic()<CR>
]])

-- just use `_G` prefix as a global function for a demo
-- please use module instead in reality
function _G.jumpToLoc(locs)
    locs = locs or vim.g.coc_jump_locations
    fn.setloclist(0, {}, ' ', {title = 'CocLocationList', items = locs})
    local winid = fn.getloclist(0, {winid = 0}).winid
    if winid == 0 then
        cmd('abo lw')
    else
        api.nvim_set_current_win(winid)
    end
end

function _G.diagnostic()
    fn.CocActionAsync('diagnosticList', '', function(err, res)
        if err == vim.NIL then
            local items = {}
            for _, d in ipairs(res) do
                local text = ('[%s%s] %s'):format((d.source == '' and 'coc.nvim' or d.source),
                    (d.code == vim.NIL and '' or ' ' .. d.code), d.message:match('([^\n]+)\n*'))
                local item = {
                    filename = d.file,
                    lnum = d.lnum,
                    end_lnum = d.end_lnum,
                    col = d.col,
                    end_col = d.end_col,
                    text = text,
                    type = d.severity
                }
                table.insert(items, item)
            end
            fn.setqflist({}, ' ', {title = 'CocDiagnosticList', items = items})

            cmd('bo cope')
        end
    end)
end
-- you can also subscribe User `CocDiagnosticChange` event to reload your diagnostic in quickfix
-- dynamically, enjoy yourself :)
```

## Customize quickfix window (Easter egg)

Quickfix window default UI is extremely outdated and low level aesthetics. However, you can dress up
your personal quickfix window:) Here is the configuration for demo:

> This section is not `nvim-bqf` exclusive, you can use the configuration without `nvim-bqf`

### Format new quickfix

Set `quickfixtextfunc` option and write down corresponding function:

```lua
local fn = vim.fn

function _G.qftf(info)
    local items
    local ret = {}
    -- The name of item in list is based on the directory of quickfix window.
    -- Change the directory for quickfix window make the name of item shorter.
    -- It's a good opportunity to change current directory in quickfixtextfunc :)
    --
    -- local alterBufnr = fn.bufname('#') -- alternative buffer is the buffer before enter qf window
    -- local root = getRootByAlterBufnr(alterBufnr)
    -- vim.cmd(('noa lcd %s'):format(fn.fnameescape(root)))
    --
    if info.quickfix == 1 then
        items = fn.getqflist({id = info.id, items = 0}).items
    else
        items = fn.getloclist(info.winid, {id = info.id, items = 0}).items
    end
    local limit = 31
    local fnameFmt1, fnameFmt2 = '%-' .. limit .. 's', '…%.' .. (limit - 1) .. 's'
    local validFmt = '%s │%5d:%-3d│%s %s'
    for i = info.start_idx, info.end_idx do
        local e = items[i]
        local fname = ''
        local str
        if e.valid == 1 then
            if e.bufnr > 0 then
                fname = fn.bufname(e.bufnr)
                if fname == '' then
                    fname = '[No Name]'
                else
                    fname = fname:gsub('^' .. vim.env.HOME, '~')
                end
                -- char in fname may occur more than 1 width, ignore this issue in order to keep performance
                if #fname <= limit then
                    fname = fnameFmt1:format(fname)
                else
                    fname = fnameFmt2:format(fname:sub(1 - limit))
                end
            end
            local lnum = e.lnum > 99999 and -1 or e.lnum
            local col = e.col > 999 and -1 or e.col
            local qtype = e.type == '' and '' or ' ' .. e.type:sub(1, 1):upper()
            str = validFmt:format(fname, lnum, col, qtype, e.text)
        else
            str = e.text
        end
        table.insert(ret, str)
    end
    return ret
end

vim.o.qftf = '{info -> v:lua._G.qftf(info)}'

-- Adapt fzf's delimiter in nvim-bqf
require('bqf').setup({
    filter = {
        fzf = {
            extra_opts = {'--bind', 'ctrl-o:toggle-all', '--delimiter', '│'}
        }
    }
})
```

### Rebuild syntax for quickfix

Add `qf.vim` under your syntax path, for instance: `~/.config/nvim/syntax/qf.vim`

```vim
if exists('b:current_syntax')
    finish
endif

syn match qfFileName /^[^│]*/ nextgroup=qfSeparatorLeft
syn match qfSeparatorLeft /│/ contained nextgroup=qfLineNr
syn match qfLineNr /[^│]*/ contained nextgroup=qfSeparatorRight
syn match qfSeparatorRight '│' contained nextgroup=qfError,qfWarning,qfInfo,qfNote
syn match qfError / E .*$/ contained
syn match qfWarning / W .*$/ contained
syn match qfInfo / I .*$/ contained
syn match qfNote / [NH] .*$/ contained

hi def link qfFileName Directory
hi def link qfSeparatorLeft Delimiter
hi def link qfSeparatorRight Delimiter
hi def link qfLineNr LineNr
hi def link qfError DiagnosticError
hi def link qfWarning DiagnosticWarn
hi def link qfInfo DiagnosticInfo
hi def link qfNote DiagnosticHint

let b:current_syntax = 'qf'
```

## Feedback

- If you get an issue or come up with an awesome idea, don't hesitate to open an issue in github.
- If you think this plugin is useful or cool, consider rewarding it a star.

## License

The project is licensed under a BSD-3-clause license. See [LICENSE](./LICENSE) file for details.
