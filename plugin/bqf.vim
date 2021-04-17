if exists('g:loaded_bqf')
    finish
endif

let g:loaded_bqf = 1

lua require('bqf').setup()

com! BqfAutoToggle lua require('bqf').toggle_auto()
