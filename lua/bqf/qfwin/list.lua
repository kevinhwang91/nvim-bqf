local M = {}

local api = vim.api
local fn = vim.fn

local QfList = {item_cache = {id = 0, entryies = {}}}
QfList.pool = setmetatable({}, {
    __index = function(tbl, id0)
        rawset(tbl, id0, QfList:new(id0))
        return tbl[id0]
    end
})

local function split_id(id0)
    local id, filewinid = unpack(vim.split(id0, ':'))
    return tonumber(id), tonumber(filewinid)
end

local function build_id(qid, filewinid)
    return ('%d:%d'):format(qid, filewinid or 0)
end

local function get_qflist(filewinid)
    return filewinid > 0 and function(what)
        return fn.getloclist(filewinid, what)
    end or fn.getqflist
end

local function set_qflist(filewinid)
    return filewinid > 0 and function(...)
        return fn.setloclist(filewinid, ...)
    end or fn.setqflist
end

function QfList:new(id0)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    local id, filewinid = split_id(id0)
    obj.id = id
    obj.filewinid = filewinid
    obj.type = filewinid == 0 and 'qf' or 'loc'
    obj.getqflist = get_qflist(filewinid)
    obj.setqflist = set_qflist(filewinid)
    obj.changedtick = 0
    return obj
end

function QfList:new_qflist(what)
    return self.setqflist({}, ' ', what)
end

function QfList:set_qflist(what)
    return self.setqflist({}, 'r', what)
end

function QfList:get_qflist(what)
    return self.getqflist(what)
end

function QfList:get_changedtick()
    local cd = self.getqflist({id = self.id, changedtick = 0}).changedtick
    if cd ~= self.changedtick then
        self.context = nil
        self.sign = nil
        QfList.item_cache = {id = 0, entryies = {}}
    end
    return cd
end

function QfList:get_context()
    local ctx
    local cd = self:get_changedtick()
    if not self.context then
        local qinfo = self.getqflist({id = self.id, context = 0})
        self.changedtick = cd
        local c = qinfo.context
        self.context = type(c) == 'table' and c or {}
    end
    ctx = self.context
    return ctx
end

function QfList:get_sign()
    local sg
    local cd = self:get_changedtick()
    if not self.sign then
        self.changedtick = cd
        self.sign = require('bqf.qfwin.sign'):new()
    end
    sg = self.sign
    return sg
end

function QfList:get_items()
    local entryies
    local c = QfList.item_cache
    local c_id, c_entryies = c.id, c.entryies
    local cd = self:get_changedtick()
    if cd == self.changedtick and c_id == self.id then
        entryies = c_entryies
    end
    if not entryies then
        local qinfo = self.getqflist({id = self.id, items = 0})
        entryies = qinfo.items
        QfList.item_cache = {id = self.id, entryies = entryies}
    end
    return entryies
end

function QfList:get_entry(idx)
    local cd = self:get_changedtick()

    local e
    local c = QfList.item_cache
    if cd == self.changedtick and c.id == self.id then
        e = c.entryies[idx]
    else
        local items = self.getqflist({id = self.id, idx = idx, items = 0}).items
        if #items == 1 then
            e = items[1]
        end
    end
    return e
end

function QfList:change_idx(idx)
    local old_idx = self:get_qflist({idx = idx})
    if idx ~= old_idx then
        self:set_qflist({idx = idx})
        self.changedtick = self.getqflist({id = self.id, changedtick = 0}).changedtick
    end
end

function M.get(qwinid, id)
    local qid, filewinid
    if not id then
        qwinid = qwinid or api.nvim_get_current_win()
        local what = {id = 0, filewinid = 0}
        local winfo = fn.getwininfo(qwinid)[1]
        if winfo.quickfix == 1 then
            local qinfo = winfo.loclist == 1 and fn.getloclist(0, what) or fn.getqflist(what)
            qid, filewinid = qinfo.id, qinfo.filewinid
        else
            return nil
        end
    else
        qid, filewinid = unpack(id)
    end
    return QfList.pool[build_id(qid, filewinid or 0)]
end

function M.verify()
    for id0, o in pairs(QfList.pool) do
        if o.getqflist({id = o.id}).id ~= o.id then
            QfList.pool[id0] = nil
        end
    end
end

return M
