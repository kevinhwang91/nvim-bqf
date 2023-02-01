---@class Bqf
local M = {}
local initialized = false
local autoEnable

---Enable bqf in quickfix window
---@return boolean
function M.enable()
    return require('bqf.main').enable()
end

---Disable bqf in quickfix window
---@return boolean
function M.disable()
    return require('bqf.main').disable()
end

---Toggle bqf in quickfix window
function M.toggle()
    require('bqf.main').toggle()
end

---Show preview window
---return true implies preview window was hidden before.
---@return boolean
function M.showPreviewWindow()
    return require('bqf.preview.handler').showWindow()
end

---Hide preview window
---return true implies preview window was showed before.
---@return boolean
function M.hidePreviewWindow()
    return require('bqf.preview.handler').hideWindow()
end

---Toggle bqf automatically
function M.toggleAuto()
    autoEnable = autoEnable ~= true
    if autoEnable then
        require('bqf.utils').warn('Enable nvim-bqf automatically')
    else
        require('bqf.utils').warn('Disable nvim-bqf automatically')
    end
end

---Boot bqf when quickfix is initialized
function M.bootstrap()
    M.setup()
    if autoEnable then
        M.enable()
    else
        M.disable()
    end
end

---Setup configuration bqf
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

return M
