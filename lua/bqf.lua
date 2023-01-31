---@class Bqf
local M = {}
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
    return require('bqf.main').enable()
end

function M.disable()
    return require('bqf.main').disable()
end

function M.toggle()
    require('bqf.main').toggle()
end

function M.showPreviewWindow()
    return require('bqf.preview.handler').showWindow()
end

function M.hidePreviewWindow()
    return require('bqf.preview.handler').hideWindow()
end

function M.toggleAuto()
    autoEnable = autoEnable ~= true
    if autoEnable then
        require('bqf.utils').warn('Enable nvim-bqf automatically')
    else
        require('bqf.utils').warn('Disable nvim-bqf automatically')
    end
end

return M
