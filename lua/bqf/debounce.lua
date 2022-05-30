local uv = vim.loop

local Debounce = {}

function Debounce:new(fn, wait)
    vim.validate({fn = {fn, 'function'}, wait = {wait, 'number'}})
    local obj = {}
    setmetatable(obj, self)
    obj.timer = nil
    obj.fn = vim.schedule_wrap(fn)
    obj.wait = wait
    return obj
end

function Debounce:call(...)
    local timer = self.timer
    self.args = {...}
    if not timer then
        timer = uv.new_timer()
        self.timer = timer
        local wait = self.wait
        timer:start(wait, wait, function()
            self:flush(unpack(self.args))
        end)
    else
        timer:again()
    end
end

function Debounce:clear()
    local timer = self.timer
    if timer then
        if timer:has_ref() then
            timer:stop()
            if not timer:is_closing() then
                timer:close()
            end
        end
        self.timer = nil
    end
end

function Debounce:flush(...)
    self:clear()
    self.fn(...)
end

Debounce.__index = Debounce
Debounce.__call = Debounce.call

return setmetatable(Debounce, {
    __call = Debounce.new
})
