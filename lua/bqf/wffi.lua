---@diagnostic disable: undefined-field
local M = {}

local utils
local C
local ffi

local function curwin()
    local cur_win
    if utils.is_windows() then
        local err = ffi.new('Error')
        cur_win = C.find_window_by_handle(0, err)
    else
        cur_win = C.curwin
    end
    return cur_win
end

function M.plines_win(lnum)
    return C.plines_win(curwin(), lnum, true)
end

function M.plines_win_col(lnum, col)
    return C.plines_win_col(curwin(), lnum, col)
end

function M.plines_win_nofill(lnum, winheight)
    return C.plines_win_nofill(curwin(), lnum, winheight)
end

local function init()
    ffi = require('ffi')
    setmetatable(M, {__index = ffi})
    C = ffi.C
    ffi.cdef([[
        typedef struct window_S win_T;
        win_T *curwin;
        typedef long linenr_T;
        int plines_win(win_T *wp, linenr_T lnum, bool winheight);
        int plines_win_col(win_T *wp, linenr_T lnum, long column);
        int plines_win_nofill(win_T *wp, linenr_T lnum, bool winheight);
    ]])

    utils = require('bqf.utils')
    if utils.is_windows() then
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
