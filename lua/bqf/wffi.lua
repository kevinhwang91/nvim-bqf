---@diagnostic disable: undefined-field
---@class BqfWffi
local M = {}

local utils
local C
local ffi

local function curWinid()
    local curWin
    if utils.isWindows() then
        local err = ffi.new('Error')
        curWin = C.find_window_by_handle(0, err)
    else
        curWin = C.curwin
    end
    return curWin
end

---
---@param lnum number
---@return number
function M.plinesWin(lnum)
    return C.plines_win(curWinid(), lnum, true)
end

---
---@param lnum number
---@param col number
---@return number
function M.plinesWinCol(lnum, col)
    return C.plines_win_col(curWinid(), lnum, col)
end

---
---@param lnum number
---@param winheight number
---@return number
function M.plinesWinNofill(lnum, winheight)
    return C.plines_win_nofill(curWinid(), lnum, winheight)
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
        win_T *curwin;
        int plines_win(win_T *wp, linenr_T lnum, bool winheight);
        int plines_win_col(win_T *wp, linenr_T lnum, long column);
        int plines_win_nofill(win_T *wp, linenr_T lnum, bool winheight);
    ]])

    if utils.isWindows() then
        ffi.cdef([[
            typedef struct {} Error;
            win_T *find_window_by_handle(int window, Error *err);
        ]])
    else
        ffi.cdef([[
            win_T *curwin;
        ]])
    end
end

init()

return M
