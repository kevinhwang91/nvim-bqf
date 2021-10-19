local LRU = {Node = {}}

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

function LRU:_after_access(node)
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
        local old_head = self.head
        old_head.prev = node
        node.prev = nil
        node.next = old_head
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
    local first_id, first_obj
    if self.head then
        first_id, first_obj = self.head.id, self.head.obj
    end
    return first_id, first_obj
end

function LRU:last()
    local last_id, last_obj
    if self.tail then
        last_id, last_obj = self.tail.id, self.tail.obj
        self:_after_access(self.tail)
    end
    return last_id, last_obj
end

function LRU:get(id)
    local obj
    local node = self.entries[id]
    if node then
        obj = node.obj
        self:_after_access(node)
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
            self:_after_access(node)
        else
            old = self:_del(id)
        end
    elseif obj then
        local new_node = LRU.Node:_new({prev = nil, next = nil, id = id, obj = obj})
        if self.head then
            local old_head = self.head
            new_node.next = old_head
            old_head.prev = new_node
            self.head = new_node
        else
            self.head = new_node
            self.tail = self.head
        end

        if self.size + 1 > self.limit then
            local old_tail = self.tail
            self.entries[old_tail.id] = nil
            local new_tail = old_tail.prev
            new_tail.next = nil
            self.tail = new_tail
        else
            self.size = self.size + 1
        end
        self.entries[id] = new_node
    end
    return old
end

function LRU:pairs(reverse)
    local node = reverse and self.tail or self.head
    return function()
        local id, obj
        if node then
            id, obj = node.id, node.obj
            if reverse then
                node = node.prev
            else
                node = node.next
            end
        end
        return id, obj
    end
end

return LRU
