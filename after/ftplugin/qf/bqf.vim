if !has('nvim-0.6.1')
    call v:lua.vim.notify('nvim-bqf failed to initialize, RTFM.')
    finish
endif

com! -buffer BqfEnable lua require('bqf').enable()
com! -buffer BqfDisable lua require('bqf').disable()
com! -buffer BqfToggle lua require('bqf').toggle()

lua require('bqf').bootstrap()
