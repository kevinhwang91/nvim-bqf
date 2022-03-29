---@class BqfLRU
---@field size number
---@field limit number
---@field head BqfLRUNode
---@field tail BqfLRUNode
---@field entries table<number, BqfLRUNode>
local LRU = {
    ---@class BqfLRUNode
    ---@field prev BqfLRUNode
    ---@field next BqfLRUNode
    ---@field id number|string
    ---@field obj any
    Node = {}
}

function LRU.Node:_new(o)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    obj.prev = o.prev
    obj.next = o.next
    obj.id = o.id
    obj.obj = o.obj
    return obj
end

function LRU:_afterAccess(node)
    local id = node.id
    if id ~= self.head.id then
        local np = node.prev
        local nn = node.next
        if id == self.tail.id then
            np.next = nil
            self.tail = np
        else
            np.next = nn
            nn.prev = np
        end
        local oldHead = self.head
        oldHead.prev = node
        node.prev = nil
        node.next = oldHead
        self.head = node
    end
end

function LRU:new(limit)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    obj.size = 0
    obj.limit = limit or 15
    obj.head = nil
    obj.tail = nil
    obj.entries = {}
    return obj
end

function LRU:first()
    local firstId, firstObj
    if self.head then
        firstId, firstObj = self.head.id, self.head.obj
    end
    return firstId, firstObj
end

function LRU:last()
    local lastId, lastObj
    if self.tail then
        lastId, lastObj = self.tail.id, self.tail.obj
        self:_afterAccess(self.tail)
    end
    return lastId, lastObj
end

function LRU:get(id)
    local obj
    local node = self.entries[id]
    if node then
        obj = node.obj
        self:_afterAccess(node)
    end
    return obj
end

function LRU:_del(id)
    local old
    local node = self.entries[id]
    if node then
        self.entries[id] = nil
        old = node.obj
        local np = node.prev
        local nn = node.next
        if id == self.head.id then
            self.head = nn
            if self.head then
                self.head.prev = nil
            else
                self.tail = nil
            end
        elseif id == self.tail.id then
            self.tail = np
            if self.tail then
                self.tail.next = nil
            else
                self.head = nil
            end
        else
            np.next = nn
            nn.prev = np
        end
        self.size = self.size - 1
    end
    return old
end

function LRU:set(id, obj)
    local old
    local node = self.entries[id]
    if node then
        if obj then
            old = node.obj
            node.obj = obj
            self:_afterAccess(node)
        else
            old = self:_del(id)
        end
    elseif obj then
        local newNode = LRU.Node:_new({prev = nil, next = nil, id = id, obj = obj})
        if self.head then
            local oldHead = self.head
            newNode.next = oldHead
            oldHead.prev = newNode
            self.head = newNode
        else
            self.head = newNode
            self.tail = self.head
        end

        if self.size + 1 > self.limit then
            local oldTail = self.tail
            self.entries[oldTail.id] = nil
            local newTail = oldTail.prev
            newTail.next = nil
            self.tail = newTail
        else
            self.size = self.size + 1
        end
        self.entries[id] = newNode
    end
    return old
end

function LRU:pairs(reverse)
    local node = reverse and self.tail or self.head
    return function()
        local id, obj
        if node then
            id, obj = node.id, node.obj
            node = reverse and node.prev or node.next
        end
        return id, obj
    end
end

return LRU
