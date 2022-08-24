---@diagnostic disable: undefined-field
---@class BqfWffi
local M = {}

local utils
local C
local ffi

local function findWin(winid)
    local err = ffi.new('Error')
    return C.find_window_by_handle(winid, err)
end

---
---@param winid number
---@param lnum number
---@return number
function M.plinesWin(winid, lnum)
    local wp = findWin(winid)
    return C.plines_win(wp, lnum, true)
end

---
---@param winid number
---@param lnum number
---@param col number
---@return number
function M.plinesWinCol(winid, lnum, col)
    local wp = findWin(winid)
    return C.plines_win_col(wp, lnum, col)
end

---
---@param winid number
---@param lnum number
---@param winheight boolean
---@return number
function M.plinesWinNofill(winid, lnum, winheight)
    local wp = findWin(winid)
    return C.plines_win_nofill(wp, lnum, winheight)
end

local function init()
    ffi = require('ffi')
    setmetatable(M, {__index = ffi})
    C = ffi.C

    utils = require('bqf.utils')
    if utils.has08() then
        ffi.cdef([[
            typedef int32_t linenr_T;
        ]])
    else
        ffi.cdef([[
            typedef long linenr_T;
        ]])
    end
    ffi.cdef([[
        typedef struct window_S win_T;
        typedef struct {} Error;
        int plines_win(win_T *wp, linenr_T lnum, bool winheight);
        int plines_win_col(win_T *wp, linenr_T lnum, long column);
        int plines_win_nofill(win_T *wp, linenr_T lnum, bool winheight);
        win_T *find_window_by_handle(int window, Error *err);
    ]])
end

init()

return M
