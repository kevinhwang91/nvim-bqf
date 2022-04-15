# Changelog

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
- Dispose throwed a error from nvim_buf_del_keymap()

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
