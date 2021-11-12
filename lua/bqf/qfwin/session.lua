local api = vim.api
local fn = vim.fn

local list = require('bqf.qfwin.list')
local utils = require('bqf.utils')

local validate = (function()
    if fn.has('nvim-0.6') == 1 then
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
    if fn.has('nvim-0.6') == 1 then
        return function(winid)
            return fn.win_gettype(winid) == ''
        end
    else
        return function(winid)
            return not validate(winid) and fn.win_gettype(winid) == ''
        end
    end
end)()

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

local QfSession = {pool = {}}

function QfSession:new(winid)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    obj.winid = winid
    obj._list = list.get(winid)
    if not obj._list then
        return nil
    end
    obj._list:get_sign():reset()
    obj._pwinid = get_pwinid(winid, obj._list)
    self.pool[winid] = obj
    return obj
end

function QfSession.get(winid)
    winid = winid or api.nvim_get_current_win()
    return QfSession.pool[winid]
end

function QfSession:list()
    return self._list
end

function QfSession:validate()
    return validate(self.winid)
end

function QfSession:pwinid()
    if not utils.is_win_valid(self._pwinid) or fn.win_gettype(self._pwinid) ~= '' then
        self._pwinid = get_pwinid(self.winid, self._list)
    end
    return self._pwinid
end

function QfSession:dispose()
    for w_id in pairs(self.pool) do
        if not utils.is_win_valid(w_id) then
            self.pool[w_id] = nil
        end
    end
end

return QfSession
