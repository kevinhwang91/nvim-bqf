# Changelog

## [1.1.1] - 2024-02-20

### Features

#### Miscellaneous

- Add mapping descriptions (#124)

#### Preview

- **Breaking:** Rework preview module (#98)
    1. Add `show_scroll_bar` option;
    2. Add `border` option;
    3. Add `winblend` option;
    4. Delete `border_chars` option;
    5. Change `BqfPreviewBorder` link to `FloatBorder`;
    6. Add `BqfPreviewTitle` highlight;
    7. Add `BqfPreviewThumb` highlight;
    8. Add `BqfPreviewSbar` highlight;

### Bug Fixes

#### Miscellaneous

- Reload qf if enter qf window (#134)

## [1.1.0] - 2023-02-20

### Features

#### Preview

- Add `BqfPreviewCursorLine` to make CursorLine configurable (#97)
- Add `hidePreviewWindow` and `showPreviewWindow` API (#100)

### Bug Fixes

#### Preview

- Convert vcol to byte col

#### FZF

- Correct to expand tab for line in headless mode

#### Miscellaneous

- Disable bqf correctly
- `nvim -q` make changedtick of qf euqal to 0 (#104)

## [1.0.0] - 2023-01-05

### Features

#### Preview

- Add show_title option (#75)
- Add buf_label to the buffer under cursor and option
- Disable syntax if delay_syntax < 0 (#89)

### Bug Fixes

#### Preview

- Fix invalid window id error on updateScrollBar (#80)

#### FZF

- Fix E974: Expected a Number or a String, Blob found
- Set `--no-separator` after 0.35.0

#### Qfwin

- Toggle sign should support v:count

#### MagicWin

- Validate winView before reset

#### Miscellaneous

- Restore last window if exec cmd in other window (#91)
- Rhs maybe missing after nvim 0.8 (#77)
- Use w:bqf_enabled instead of b:bqf_enabled
- Be compatible with splitkeep
- Be compatible with winbar (#81)
- Be compatible with cmdheight=0
- [**breaking**] Bump Neovim to 0.6.1

## [0.9.9] - 2022-08-25

### Bug Fixes

#### MagicWin

- Qf at top/above should check botline

#### FZF

- Render highlighting is wrong for source syntax
- Handle empty str for capturing iskeyword (#64)

#### Preview

- Should pass srcBufnr to nvim-treesitter (#63)
- Get winline() from quickfix win
- Close preview window if qf buffer is hidden (#70)

#### Qfwin

- Qf window Can't drop empty buffer name
- Can't close location if previous window is invalid

#### Miscellaneous

- Debounce args should be changed
- Upstream changed the C type in nightly
- Can't split a window while closing another in nightly

### Features

#### Preview

- Support mouse scroll and double click for preview window

### Performance

#### Preview

- Prefer to use loaded buffer filetype

## [0.3.3] - 2022-04-16

### Bug Fixes

#### MagicWin

- Refresh winview if position changed

## [0.3.2] - 2022-04-15

### Bug Fixes

#### FZF

- Restore local stl option for qf window

#### MagicWin

- Call layout_cb even if magic_window = false (#58)
- Refresh winview if cache is invalid

#### Miscellaneous

- Correct sysname for Windows
- Compatible with PUC Lua 5.1

### Features

#### FZF

- Adapt fzf's actions for preview

#### Preview

- Support extmarks for all non-anonymous namespaces

## [0.3.1] - 2022-02-26

### Bug Fixes

#### FZF

- Support conceal (#56)
- Add w:quickfix_title as a context/id for spawning headless
- Clean up tmpfile for preview

#### MagicWin

- Correct the validation of adjacent win session

## [0.3.0] - 2022-02-21

### Bug Fixes

#### FZF

- Should respect UTF-8 as the default value
- Winbl option should set according by winid

#### MagicWin

- Lose last window cause jumping unexpected window
- WinClosed in main can't be fired
- More intelligent

#### Preview

- Should reset scrolling horizontally
- Switch tabpage can't fire cursor move

#### Qfwin

- Wrong condition to get previous window
- Winminwidth must smaller than winwidth (#44)
- Keep jumplist for jump with drop
- No error for wiped buffer while jumping
- Quickfixtextfunc field in list should be supported
- Avoid extra error while switching list
- Dispose threw a error from nvim_buf_del_keymap()

### Documentation

- Add link for integrated plugins
- Add `:h bqf`
- Tell you how to make your pretty quickfix window :)
- Show how to disable fugitive preview automatically
- Large value for win_height perform full mode (#55)

### Features

#### FFI

- Add ffi module

#### FZF

- Support preview for Windows
- Support --scroll-off
- Support --nth=3..,1,2
- Add `closeall` action
- Support fzf_extra_opts and fzf_action_for to context
- Less flicker when start/stop fzf

#### MagicWin

- Support virt_lines

#### Qfwin

- [**breaking**] Change default value of auto_resize_height to `false`
- [**breaking**] `<` or `>` will jump last leaving position automatically
- Add last leaving position
- Add new jump commands (#45)

### Performance

- Cache parsers to speed up preview with treesitter
