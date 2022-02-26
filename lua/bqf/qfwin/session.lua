local api = vim.api
local fn = vim.fn

local list = require('bqf.qfwin.list')
local utils = require('bqf.utils')

---
---@return fun(winid: number): boolean
local validate = (function()
    if utils.has_06() then
        return function(winid)
            local win_type = fn.win_gettype(winid)
            return win_type == 'quickfix' or win_type == 'loclist'
        end
    else
        return function(winid)
            winid = winid or api.nvim_get_current_win()
            local ok, ret
            ok = pcall(function()
                ret = fn.getwininfo(winid)[1].quickfix == 1
            end)
            return ok and ret
        end
    end
end)()

local is_normal_win_type = (function()
    if utils.has_06() then
        return function(winid)
            return fn.win_gettype(winid) == ''
        end
    else
        return function(winid)
            return not validate(winid) and fn.win_gettype(winid) == ''
        end
    end
end)()

---
---@param winid number
---@param qlist BqfQfList
---@return number
local function get_pwinid(winid, qlist)
    local pwinid
    if qlist.type == 'loc' then
        pwinid = qlist.filewinid > 0 and qlist.filewinid or -1
    else
        local function is_valid(wid)
            return wid > 0 and is_normal_win_type(wid)
        end
        pwinid = fn.win_getid(fn.winnr('#'))
        if not is_valid(pwinid) then
            local tabpage = api.nvim_win_get_tabpage(winid)
            for _, owinid in ipairs(api.nvim_tabpage_list_wins(tabpage)) do
                if is_normal_win_type(owinid) then
                    pwinid = owinid
                    break
                end
            end
        end
        if not is_valid(pwinid) then
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

function QfSession:pwinid()
    if not utils.is_win_valid(self._pwinid) or fn.win_gettype(self._pwinid) ~= '' then
        self._pwinid = get_pwinid(self.winid, self._list)
    end
    return self._pwinid
end

function QfSession:validate()
    return validate(self.winid)
end

---
---@param winid number
---@return BqfQfSession
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
    obj._pwinid = get_pwinid(winid, obj._list)
    self.pool[winid] = obj
    return obj
end

---
---@param winid number
---@return BqfQfSession
function QfSession:get(winid)
    winid = winid or api.nvim_get_current_win()
    return self.pool[winid]
end

function QfSession:save_winview(winid)
    if winid then
        local obj = self.pool[winid]
        local wv = utils.win_execute(winid, fn.winsaveview)
        obj:list():set_winview(wv)
    end
end

function QfSession:dispose()
    for w_id in pairs(self.pool) do
        if not utils.is_win_valid(w_id) then
            QfSession.pool[w_id] = nil
        end
    end
end

return QfSession
