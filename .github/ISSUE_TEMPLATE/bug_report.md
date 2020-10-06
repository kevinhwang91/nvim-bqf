---
name: Bug report
about: Create a report to help us improve
title: ''
labels: ''
assignees: ''
---

<!-- Before reporting: search existing issues and check the FAQ. -->

- `nvim --version`:
- Operating system/version:

**Describe the bug**
A clear and concise description of what the bug is.

**To Reproduce using `nvim -u mini.vim`**

Example:
`cat mini.vim`

```vim
" use your plugin manager, here is `vim-plug`
call plug#begin('~/.config/nvim/plugged')
Plug 'kevinhwang91/nvim-bqf'
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
call plug#end()
```

Steps to reproduce the behavior:

1.
2.
3.

**Expected behavior**
A clear and concise description of what you expected to happen.

**Screenshots**
If applicable, add screenshots to help explain your problem.

**Additional context**
Add any other context about the problem here.
