if exists('g:loaded_bqf')
    finish
endif

let g:loaded_bqf = 1

com! BqfAutoToggle lua require('bqf').toggleAuto()
