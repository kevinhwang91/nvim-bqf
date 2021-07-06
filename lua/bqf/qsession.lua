local M = {}

local qftool = require('bqf.qftool')

local Qsession = {}

function Qsession:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    o.id = o.id
    o.changedtick = o.changedtick
    o.items = {}
    return o
end

function Qsession:may_reset(id, changedtick)
    if self.id ~= id or self.changedtick ~= changedtick then
        self.changedtick = changedtick
        self.items = {}
    end
end

function Qsession:get(idx)
    return self.items[idx]
end

function Qsession:set(idx, new)
    local old = self.items[idx]
    self.items[idx] = new
    return old
end

return M
