local api = vim.api
local fn = vim.fn

local list = require('bqf.qfwin.list')
local utils = require('bqf.utils')

local function isNormalWinType(winid)
    return fn.win_gettype(winid) == ''
end

---
---@param winid number
---@param qlist BqfQfList
---@return number
local function getPwinid(winid, qlist)
    local pwinid
    if qlist.type == 'loc' then
        pwinid = qlist.filewinid > 0 and qlist.filewinid or -1
    else
        local function isValid(wid)
            return wid > 0 and isNormalWinType(wid)
        end

        pwinid = fn.win_getid(fn.winnr('#'))
        if not isValid(pwinid) then
            local tabpage = api.nvim_win_get_tabpage(winid)
            for _, owinid in ipairs(api.nvim_tabpage_list_wins(tabpage)) do
                if isNormalWinType(owinid) then
                    pwinid = owinid
                    break
                end
            end
        end
        if not isValid(pwinid) then
            pwinid = -1
        end
    end
    return pwinid
end

---
---@class BqfQfSession
---@field private pool table<number, BqfQfSession>
---@field private _list BqfQfList
---@field private _pwinid number
---@field winid number
local QfSession = {pool = {}}

function QfSession:list()
    return self._list
end

function QfSession:previousWinid()
    if not utils.isWinValid(self._pwinid) or fn.win_gettype(self._pwinid) ~= '' then
        self._pwinid = getPwinid(self.winid, self._list)
    end
    return utils.isWinValid(self._pwinid) and self._pwinid or -1
end

function QfSession:validate()
    local winType = fn.win_gettype(self.winid)
    return winType == 'quickfix' or winType == 'loclist'
end

---
---@param winid number
---@return BqfQfSession?
function QfSession:new(winid)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    obj.winid = winid
    obj._list = list:get(winid)
    if not obj._list then
        return nil
    end
    obj._list:sign():reset()
    obj._pwinid = getPwinid(winid, obj._list)
    self.pool[winid] = obj
    return obj
end

---
---@param winid? number
---@return BqfQfSession
function QfSession:get(winid)
    winid = winid or api.nvim_get_current_win()
    return self.pool[winid]
end

function QfSession:saveWinView(winid)
    if winid then
        local obj = self.pool[winid]
        local wv = utils.winCall(winid, fn.winsaveview)
        if obj ~= nil then
            obj:list():setWinView(wv)
        end
    end
end

function QfSession:dispose()
    for wId in pairs(self.pool) do
        if not utils.isWinValid(wId) then
            QfSession.pool[wId] = nil
        end
    end
end

return QfSession
