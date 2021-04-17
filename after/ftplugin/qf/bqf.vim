if !has('nvim-0.5')
    call nvim_echo([['nvim-bqf failed to initialize, RTFM.', 'ErrorMsg']], v:true, {})
    finish
endif

com! -buffer BqfEnable lua require('bqf').enable()
com! -buffer BqfDisable lua require('bqf').disable()
com! -buffer BqfToggle lua require('bqf').toggle()

lua require('bqf').bootstrap()
