local api = vim.api
local fn = vim.fn
local wffi
local utils = require('bqf.utils')

local LSize

local LBase = {}

function LBase:new(sizes)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    obj.foldenable = vim.wo.foldenable
    obj.fold_close_pairs = {}
    obj.sizes = sizes
    return obj
end

function LBase:size(lnum)
    return self.sizes[lnum]
end

function LBase:foldclosed(lnum)
    if not self.foldenable then
        return -1
    end
    local fpair = self.fold_close_pairs[lnum] or {}
    local s = fpair[1]
    if not s then
        s = fn.foldclosed(lnum)
        if s == -1 then
            fpair = {-1, -1}
        else
            fpair = {s, nil}
        end
    end
    self.fold_close_pairs[lnum] = fpair
    return s
end

function LBase:foldclosed_end(lnum)
    if not self.foldenable then
        return -1
    end
    local fpair = self.fold_close_pairs[lnum] or {}
    local e = fpair[2]
    if not e then
        e = fn.foldclosedend(lnum)
        if e == -1 then
            fpair = {-1, -1}
        else
            fpair = {nil, e}
        end
    end
    self.fold_close_pairs[lnum] = fpair
    return e
end

local LFFI = setmetatable({}, {__index = LBase})

function LFFI:new()
    local obj = LBase:new(setmetatable({}, {
        __index = function(t, i)
            local v = wffi.plines_win(i)
            rawset(t, i, v)
            return v
        end
    }))
    setmetatable(obj, self)
    self.__index = self
    return obj
end

function LFFI:nofill_size(lnum, winheight)
    winheight = winheight or true
    return wffi.plines_win_nofill(lnum, winheight)
end

function LFFI:fill_size(lnum)
    return self:size(lnum) - self:nofill_size(lnum, true)
end

function LFFI:pos_size(lnum, col)
    return wffi.plines_win_col(lnum, col)
end

local LNonFFI = setmetatable({}, {__index = LBase})

function LNonFFI:new()
    local winid = api.nvim_get_current_win()
    local wrap = vim.wo[winid].wrap
    local per_lwidth = api.nvim_win_get_width(winid) - utils.textoff(winid)
    local obj = LBase:new(setmetatable({}, {
        __index = function(t, i)
            local v
            if wrap then
                v = math.ceil(math.max(fn.virtcol({i, '$'}) - 1, 1) / per_lwidth)
            else
                v = 1
            end
            rawset(t, i, v)
            return v
        end
    }))
    obj.per_lwidth = per_lwidth
    setmetatable(obj, self)
    self.__index = self
    return obj
end

LNonFFI.nofill_size = LNonFFI.size

function LNonFFI:fill_size(_)
    return 0
end

function LNonFFI:pos_size(lnum, col)
    return math.ceil(math.max(fn.virtcol({lnum, col}) - 1, 1) / self.per_lwidth)
end

local function init()
    if utils.jit_enabled() then
        wffi = require('bqf.wffi')
        LSize = LFFI
    else
        LSize = LNonFFI
    end
end

init()

return LSize
