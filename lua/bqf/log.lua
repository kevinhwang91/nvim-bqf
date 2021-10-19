-- Singleton
local M = {}
local fn = vim.fn

local levels
local level_nr
local level_default
local log_file
local log_date_fmt

local function get_level_nr(l)
    local nr
    if type(l) == 'number' then
        nr = l
    elseif type(l) == 'string' then
        nr = levels[l:upper()]
    else
        nr = level_default
    end
    return nr
end

function M.set_level(l)
    level_nr = get_level_nr(l)
end

function M.is_enabled(l)
    return get_level_nr(l) >= level_nr
end

function M.level()
    for l, nr in pairs(levels) do
        if nr == level_nr then
            return l
        end
    end
    return 'UNDEFINED'
end

local function inspect(v)
    local s
    local t = type(v)
    if t == 'nil' then
        s = 'nil'
    elseif t ~= 'string' then
        s = vim.inspect(v, {indent = '', newline = ' '})
    else
        s = tostring(v)
    end
    return s
end

local function path_sep()
    return vim.loop.os_uname().sysname == 'Windows' and [[\]] or '/'
end

local function init()
    local log_dir = fn.stdpath('cache')
    fn.mkdir(log_dir, 'p')
    levels = {TRACE = 0, DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4}
    level_default = 3
    M.set_level(vim.env.BQF_LOG)

    log_file = table.concat({log_dir, 'bqf.log'}, path_sep())
    log_date_fmt = '%y-%m-%d %T'

    for l in pairs(levels) do
        M[l:lower()] = function(...)
            local argc = select('#', ...)
            if argc == 0 or levels[l] < level_nr then
                return
            end
            local msg_tbl = {}
            for i = 1, argc do
                local arg = select(i, ...)
                table.insert(msg_tbl, inspect(arg))
            end
            local msg = table.concat(msg_tbl, ' ')
            local info = debug.getinfo(2, 'Sl')
            local linfo = info.short_src:match('[^/]*$') .. ':' .. info.currentline

            local fp = assert(io.open(log_file, 'a+'))
            local str = string.format('[%s] [%s] %s : %s\n', os.date(log_date_fmt), l, linfo, msg)
            fp:write(str)
            fp:close()
        end
    end
end

init()

return M
