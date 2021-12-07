---@diagnostic disable: undefined-field
local M = {}

local C

function M.plines_win(lnum)
    return C.plines_win(C.curwin, lnum, true)
end

function M.plines_win_col(lnum, col)
    return C.plines_win_col(C.curwin, lnum, col)
end

local function init()
    local ffi = require('ffi')
    C = ffi.C
    ffi.cdef([[
        typedef struct window_S win_T;
        win_T *curwin;
        typedef long linenr_T;
        int plines_win(win_T *wp, linenr_T lnum, bool winheight);
        int plines_win_col(win_T *wp, linenr_T lnum, long column);
    ]])
end

init()

return M
