---@class Bqf
local M = {}
local api = vim.api
local initialized = false
local autoEnable

---@param opts? BqfConfig
function M.setup(opts)
    if initialized then
        return
    end

    opts = opts or {}
    if opts.auto_enable == false then
        autoEnable = false
    else
        autoEnable = true
    end
    -- M._config will become nil latter
    M._config = opts
    initialized = true
end

function M.bootstrap()
    M.setup()
    if autoEnable then
        M.enable()
    else
        M.disable()
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

function M.toggleAuto()
    autoEnable = autoEnable ~= true
    if autoEnable then
        api.nvim_echo({{'Enable nvim-bqf automatically', 'WarningMsg'}}, true, {})
    else
        api.nvim_echo({{'Disable nvim-bqf automatically', 'WarningMsg'}}, true, {})
    end
end

return M
