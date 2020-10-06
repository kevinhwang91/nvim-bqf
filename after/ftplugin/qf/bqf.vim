if !has('nvim-0.5')
    echohl ErrorMsg | echo 'nvim-bqf failed to initialize, RTFM.' | echohl None
    finish
endif

command! -buffer BqfEnable lua require('bqf').enable()
command! -buffer BqfDisable lua require('bqf').disable()
command! -buffer BqfToggle lua require('bqf').toggle()

lua require('bqf').bootstrap()
