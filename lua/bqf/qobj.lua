local M = {}

local api = vim.api
local fn = vim.fn

local pool

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

local function from_pool(qwinid, id)
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
    return pool[build_id(qid, filewinid or 0)]
end

local Qobj = {item_cache = {id = 0, entryies = {}}}

function Qobj.new(id0)
    local self = Qobj
    local o = {}
    setmetatable(o, self)
    self.__index = self
    local id, filewinid = split_id(id0)
    o.id = id
    o.filewinid = filewinid
    o.type = filewinid == 0 and 'qf' or 'loc'
    o.getqflist = get_qflist(filewinid)
    o.setqflist = set_qflist(filewinid)
    o.changedtick = 0
    return o
end

function Qobj:new_qflist(what)
    return self.setqflist({}, ' ', what)
end

function Qobj:set_qflist(what)
    return self.setqflist({}, 'r', what)
end

function Qobj:get_qflist(what)
    return self.getqflist(what)
end

function Qobj:get_changedtick()
    local cd = self.getqflist({id = self.id, changedtick = 0}).changedtick
    if cd ~= self.changedtick then
        self.context = nil
        self.sign = nil
        Qobj.item_cache = {id = 0, entryies = {}}
    end
    return cd
end

function Qobj:get_context()
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

function Qobj:get_sign()
    local sg
    local cd = self:get_changedtick()
    if not self.sign then
        self.changedtick = cd
        self.sign = require('bqf.sign').new()
    end
    sg = self.sign
    return sg
end

function Qobj:get_items()
    local entryies
    local c = Qobj.item_cache
    local c_id, c_entryies = c.id, c.entryies
    local cd = self:get_changedtick()
    if cd == self.changedtick and c_id > 0 and c_id == self.id then
        entryies = c_entryies
    end
    if not entryies then
        local qinfo = self.getqflist({id = self.id, items = 0})
        entryies = qinfo.items
        Qobj.item_cache = {id = self.id, entryies = entryies}
    end
    return entryies
end

function Qobj:get_entry(idx)
    local qinfo = self.getqflist({id = self.id, changedtick = 0})
    local changedtick = qinfo.changedtick
    if changedtick ~= self.changedtick then
        self:reset_field()
    end

    local e
    local items = self.getqflist({id = self.id, idx = idx, items = 0}).items
    if #items == 1 then
        e = items[1]
    end
    return e
end

function Qobj:change_idx(idx)
    self:set_qflist({idx = idx})
    self.changedtick = self.getqflist({id = self.id, changedtick = 0}).changedtick
end

function M.get(qwinid, id)
    return from_pool(qwinid, id)
end

function M.verify()
    for id0, o in pairs(pool) do
        if o.getqflist({id = o.id}).id ~= o.id then
            pool[id0] = nil
        end
    end
end

local function init()
    pool = setmetatable({}, {
        __index = function(tbl, id0)
            rawset(tbl, id0, Qobj.new(id0))
            return tbl[id0]
        end
    })
end

init()

return M
