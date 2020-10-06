if exists('g:loaded_bqf')
    finish
endif

let g:loaded_bqf = 1

lua require('bqf').setup()

command! BqfAutoToggle lua require('bqf').toggle_auto()
