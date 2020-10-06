local M = {}
local cmd = vim.cmd
local initialized = false
local config = require('bqf.config')
local auto_enable = true

function M.setup(opts)
    if initialized then
        return
    end

    opts = opts or {}
    if opts.auto_enable == false then
        auto_enable = false
    end
    opts.auto_enable = auto_enable
    config.auto_enable = auto_enable
    config.set_user_config(opts)
    initialized = true
end

function M.bootstrap()
    if auto_enable then
        require('bqf.main').enable()
    end
end

function M.enable()
    require('bqf.main').enable()
end

function M.disable()
    require('bqf.main').disable()
end

function M.toggle()
    require('bqf.main').toggle()
end

function M.toggle_auto()
    auto_enable = auto_enable ~= true
    if auto_enable then
        cmd([[echohl WarningMsg | echo 'Enable nvim-bqf automatically' | echohl None]])
    else
        cmd([[echohl WarningMsg | echo 'Disable nvim-bqf automatically' | echohl None]])
    end
end

return M
