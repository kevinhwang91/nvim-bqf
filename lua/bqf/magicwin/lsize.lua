local api = vim.api
local fn = vim.fn
local utils = require('bqf.utils')

local LSize

---
---@class BqfLBase
---@field winid number
---@field foldenable boolean
---@field foldClosePairs table<number, number[]>
---@field sizes table<number, number>
local LBase = {}

---
---@param winid number
---@return BqfLBase
function LBase:new(winid)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.winid = winid
    o.foldenable = vim.wo.foldenable
    o.foldClosePairs = {}
    return o
end

---
---@param lnum number
---@return number
function LBase:size(lnum)
    return self.sizes[lnum]
end

---
---@param lnum number
---@return number
function LBase:foldclosed(lnum)
    if not self.foldenable then
        return -1
    end
    local fpair = self.foldClosePairs[lnum] or {}
    local s = fpair[1]
    if not s then
        s = fn.foldclosed(lnum)
        if s == -1 then
            fpair = {-1, -1}
        else
            fpair = {s, nil}
        end
    end
    self.foldClosePairs[lnum] = fpair
    return s
end

---
---@param lnum number
---@return number
function LBase:foldclosedEnd(lnum)
    if not self.foldenable then
        return -1
    end
    local fpair = self.foldClosePairs[lnum] or {}
    local e = fpair[2]
    if not e then
        e = fn.foldclosedend(lnum)
        if e == -1 then
            fpair = {-1, -1}
        else
            fpair = {nil, e}
        end
    end
    self.foldClosePairs[lnum] = fpair
    return e
end

---
---@class BqfLFFI : BqfLBase
---@field private _wffi BqfWffi
local LFFI = setmetatable({}, {__index = LBase})

---
---@param winid number
---@return BqfLFFI
function LFFI:new(winid)
    local super = LBase:new(winid)
    local o = setmetatable(super, self)
    o.sizes = setmetatable({}, {
        __index = function(t, i)
            local v = self._wffi.plinesWin(winid, i)
            rawset(t, i, v)
            return v
        end
    })
    self.__index = self
    return o
end

---
---@param lnum number
---@param winheight number
---@return number
function LFFI:nofillSize(lnum, winheight)
    winheight = winheight or true
    return self._wffi.plinesWinNofill(self.winid, lnum, winheight)
end

---
---@param lnum number
---@return number
function LFFI:fillSize(lnum)
    return self:size(lnum) - self:nofillSize(lnum, true)
end

---
---@param lnum number
---@param col number
---@return number
function LFFI:posSize(lnum, col)
    return self._wffi.plinesWinCol(self.winid, lnum, col)
end

---
---@class BqfLNonFFI : BqfLBase
---@field perLineWidth number
local LNonFFI = setmetatable({}, {__index = LBase})

---
---@param winid number
---@return BqfLNonFFI
function LNonFFI:new(winid)
    local wrap = vim.wo[winid].wrap
    local super = LBase:new(winid)
    local o = setmetatable(super, self)
    local perLineWidth = api.nvim_win_get_width(winid) - utils.textoff(winid)
    super.perLineWidth = perLineWidth
    o.sizes = setmetatable({}, {
        __index = function(t, i)
            local v
            if wrap then
                v = math.ceil(math.max(fn.virtcol({i, '$'}) - 1, 1) / perLineWidth)
            else
                v = 1
            end
            rawset(t, i, v)
            return v
        end
    })
    self.__index = self
    return o
end

LNonFFI.nofillSize = LNonFFI.size

---
---@param _ any
---@return number
function LNonFFI.fillSize(_)
    return 0
end

---
---@param lnum number
---@param col number
---@return number
function LNonFFI:posSize(lnum, col)
    return math.ceil(math.max(fn.virtcol({lnum, col}) - 1, 1) / self.perLineWidth)
end

local function init()
    if utils.jitEnabled() then
        LFFI._wffi = require('bqf.wffi')
        LSize = LFFI
    else
        LSize = LNonFFI
    end
end

init()

return LSize
