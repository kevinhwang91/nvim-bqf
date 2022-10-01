local uv = vim.loop

---@class BqfThrottle
---@field timer userdata
---@field fn function
---@field pendingArgs? table
---@field limit number
---@field leading? boolean
---@field trailing? boolean
---@overload fun(fn: function, limit: number, noLeading?: boolean, noTrailing?: boolean): BqfThrottle
local Throttle = {}

---
---@param fn function
---@param limit number
---@param noLeading? boolean
---@param noTrailing? boolean
---@return BqfThrottle
function Throttle:new(fn, limit, noLeading, noTrailing)
    vim.validate({fn = {fn, 'function'}, limit = {limit, 'number'},
                  noLeading = {noLeading, 'boolean', true},
                  noTrailing = {noTrailing, 'boolean', true}})
    assert(not (noLeading and noTrailing),
           [[The values of noLeading and noTrailing can't be all true]])
    local o = setmetatable({}, self)
    o.timer = nil
    o.fn = vim.schedule_wrap(fn)
    o.pendingArgs = nil
    o.limit = limit
    o.leading = not noLeading
    o.trailing = not noTrailing
    return o
end

function Throttle:call(...)
    local timer = self.timer
    if not timer then
        ---@type userdata
        timer = uv.new_timer()
        self.timer = timer
        local limit = self.limit
        timer:start(limit, 0, function()
            if self.pendingArgs then
                self.fn(unpack(self.pendingArgs))
            end
            self:cancel()
        end)
        if self.leading then
            self.fn(...)
        else
            self.pendingArgs = {...}
        end
    else
        if self.trailing then
            self.pendingArgs = {...}
        end
    end
end

function Throttle:cancel()
    local timer = self.timer
    if timer then
        if timer:has_ref() and not timer:is_closing() then
            timer:close()
        end
    end
    self.timer = nil
    self.pendingArgs = nil
end

Throttle.__index = Throttle
Throttle.__call = Throttle.call

return setmetatable(Throttle, {
    __call = Throttle.new
})
