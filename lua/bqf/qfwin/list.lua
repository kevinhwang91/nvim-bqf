local api = vim.api
local fn = vim.fn

local utils = require('bqf.utils')

---@class BqfQfItem
---@field bufnr number
---@field module string
---@field lnum number
---@field end_lnum number
---@field col number
---@field end_col number
---@field vcol number
---@field nr number
---@field pattern string
---@field text string
---@field type string
---@field valid number

---@class BqfQfDict
---@field changedtick? number
---@field context? table
---@field id? number
---@field idx? number
---@field items? BqfQfItem[]
---@field nr? number
---@field size? number
---@field title? number
---@field winid? number
---@field filewinid? number
---@field quickfixtextfunc? string

---@class BqfQfList
---@field private itemsCache BqfQfItemCache
---@field private pool table<string, BqfQfList>
---@field id number
---@field filewinid number
---@field type string
---@field getqflist fun(what?: table): BqfQfDict
---@field setqflist fun(list:BqfQfItem, action?: string, what?: table): number
---@field winView? table
---@field private _changedtick number
---@field private _sign QfWinSign
---@field private _context table
local QfList = {
    ---@class BqfQfItemCache
    ---@field id number
    ---@field items BqfQfItem[]
    itemsCache = {id = 0, items = {}}
}

QfList.pool = setmetatable({}, {
    __index = function(tbl, id0)
        rawset(tbl, id0, QfList:new(id0))
        return tbl[id0]
    end
})

local function splitId(id0)
    local id, filewinid = unpack(vim.split(id0, ':'))
    return tonumber(id), tonumber(filewinid)
end

local function buildId(qid, filewinid)
    return ('%d:%d'):format(qid, filewinid or 0)
end

---
---@param filewinid number
---@return fun(param:table):BqfQfDict
local function getQfList(filewinid)
    return function(what)
        local list = filewinid > 0 and fn.getloclist(filewinid, what) or fn.getqflist(what)
        -- TODO
        -- upstream issue vimscript -> lua, function can't be transformed directly
        -- quickfixtextfunc may be a Funcref value.
        -- get the name of function in vimscript instead of function reference
        local qftf = list.quickfixtextfunc
        if type(qftf) == 'userdata' and qftf == vim.NIL then
            local qftfCmd
            if filewinid > 0 then
                qftfCmd = [[echo getloclist(0, {'quickfixtextfunc': 0}).quickfixtextfunc]]
            else
                qftfCmd = [[echo getqflist({'quickfixtextfunc': 0}).quickfixtextfunc]]
            end
            local funcName = api.nvim_exec(qftfCmd, true)
            local lambdaName = funcName:match('<lambda>%d+')
            if lambdaName then
                funcName = lambdaName
            end
            list.quickfixtextfunc = fn[funcName]
        end
        return list
    end
end

local function setQfList(filewinid)
    return filewinid > 0 and function(...)
        return fn.setloclist(filewinid, ...)
    end or fn.setqflist
end

---
---@param id0 string
---@return BqfQfList
function QfList:new(id0)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    local id, filewinid = splitId(id0)
    obj.id = id
    obj.filewinid = filewinid
    obj.type = filewinid == 0 and 'qf' or 'loc'
    obj.getqflist = getQfList(filewinid)
    obj.setqflist = setQfList(filewinid)
    obj._changedtick = 0
    return obj
end

---
---@param what table
---@return boolean
function QfList:newQfList(what)
    return self.setqflist({}, ' ', what) ~= -1
end

---
---@param what table
---@return boolean
function QfList:setQfList(what)
    return self.setqflist({}, 'r', what) ~= -1
end

---
---@param what table
---@return BqfQfDict
function QfList:getQfList(what)
    return self.getqflist(what)
end

---
---@return number
function QfList:changedtick()
    local cd = self.getqflist({id = self.id, changedtick = 0}).changedtick
    if cd ~= self._changedtick then
        self._context = nil
        self._sign = nil
        QfList.itemsCache = {id = 0, items = {}}
    end
    return cd
end

---
---@return table
function QfList:context()
    local ctx
    local cd = self:changedtick()
    if not self._context then
        local qdict = self.getqflist({id = self.id, context = 0})
        self._changedtick = cd
        local c = qdict.context
        self._context = type(c) == 'table' and c or {}
    end
    ctx = self._context
    return ctx
end

---
---@return QfWinSign
function QfList:sign()
    local sg
    local cd = self:changedtick()
    if not self._sign then
        self._changedtick = cd
        self._sign = require('bqf.qfwin.sign'):new()
    end
    sg = self._sign
    return sg
end

---
---@return BqfQfItem[]
function QfList:items()
    local items
    local c = QfList.itemsCache
    local cId, cItems = c.id, c.items
    local cd = self:changedtick()
    if cd == self._changedtick and cId == self.id then
        items = cItems
    end
    if not items then
        local qdict = self.getqflist({id = self.id, items = 0})
        items = qdict.items
        QfList.itemsCache = {id = self.id, items = items}
    end
    return items
end

---
---@param idx number
---@return BqfQfItem
function QfList:item(idx)
    local cd = self:changedtick()

    local e
    local c = QfList.itemsCache
    if cd == self._changedtick and c.id == self.id then
        e = c.items[idx]
    else
        local items = self.getqflist({id = self.id, idx = idx, items = 0}).items
        if #items == 1 then
            e = items[1]
        end
    end
    return e
end

function QfList:changeIdx(idx)
    local oldIdx = self:getQfList({idx = idx})
    if idx ~= oldIdx then
        self:setQfList({idx = idx})
        self._changedtick = self.getqflist({id = self.id, changedtick = 0}).changedtick
    end
end

---
---@return table
function QfList:getWinView()
    return self.winView
end

---
---@param winView table
function QfList:setWinView(winView)
    self.winView = winView
end

local function verify(pool)
    for id0, o in pairs(pool) do
        if o.getqflist({id = o.id}).id ~= o.id then
            pool[id0] = nil
        end
    end
end

---
---@param qwinid? number
---@param id? number
---@return BqfQfList
function QfList:get(qwinid, id)
    local qid, filewinid
    if not id then
        qwinid = qwinid or api.nvim_get_current_win()
        local what = {id = 0, filewinid = 0}
        local winfo = utils.getWinInfo(qwinid)
        if winfo.quickfix == 1 then
            ---@type BqfQfDict
            local qdict = winfo.loclist == 1 and fn.getloclist(0, what) or fn.getqflist(what)
            qid, filewinid = qdict.id, qdict.filewinid
        else
            return nil
        end
    else
        qid, filewinid = unpack(id)
    end
    verify(self.pool)
    return self.pool[buildId(qid, filewinid or 0)]
end

return QfList
