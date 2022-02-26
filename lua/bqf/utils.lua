---@class BqfUtils
local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd
local uv = vim.loop

---@return fun(): boolean
M.has_06 = (function()
    local has_06
    return function()
        if has_06 == nil then
            has_06 = fn.has('nvim-0.6') == 1
        end
        return has_06
    end
end)()

---@return fun(): boolean
M.is_windows = (function()
    local is_win
    return function()
        if is_win == nil then
            is_win = uv.os_uname().sysname == 'Windows_NT'
        end
        return is_win
    end
end)()

---@return fun(): boolean
M.jit_enabled = (function()
    local enabled
    return function()
        if enabled == nil then
            enabled = jit and (not M.is_windows() or M.has_06())
        end
        return enabled
    end
end)()

local function color2csi24b(color_num, fg)
    local r = math.floor(color_num / 2 ^ 16)
    local g = math.floor(math.floor(color_num / 2 ^ 8) % 2 ^ 8)
    local b = math.floor(color_num % 2 ^ 8)
    return ('%d;2;%d;%d;%d'):format(fg and 38 or 48, r, g, b)
end

local function color2csi8b(color_num, fg)
    return ('%d;5;%d'):format(fg and 38 or 48, color_num)
end

---
---@param bufnr number
---@return string[]
function M.syntax_list(bufnr)
    local list = {}
    local syn_info = api.nvim_buf_call(bufnr, function()
        return api.nvim_exec('syn', true)
    end)
    for line in vim.gsplit(syn_info, '\n') do
        local name = line:match('^(%a+)%s*xxx ')
        if name then
            table.insert(list, name)
        end
    end
    return list
end

local ansi = {
    black = 30,
    red = 31,
    green = 32,
    yellow = 33,
    blue = 34,
    magenta = 35,
    cyan = 36,
    white = 37
}

---
---@param str string
---@param group_name string
---@param def_fg string
---@param def_bg string
---@return string
function M.render_str(str, group_name, def_fg, def_bg)
    vim.validate({
        str = {str, 'string'},
        group_name = {group_name, 'string'},
        def_fg = {def_fg, 'string', true},
        def_bg = {def_bg, 'string', true}
    })
    local gui = vim.o.termguicolors
    local ok, hl = pcall(api.nvim_get_hl_by_name, group_name, gui)
    if not ok or
        not (hl.foreground or hl.background or hl.reverse or hl.bold or hl.italic or hl.underline) then
        return str
    end
    local fg, bg
    if hl.reverse then
        fg = hl.background ~= nil and hl.background or nil
        bg = hl.foreground ~= nil and hl.foreground or nil
    else
        fg = hl.foreground
        bg = hl.background
    end
    local escape_prefix = ('\x1b[%s%s%s'):format(hl.bold and ';1' or '', hl.italic and ';3' or '',
        hl.underline and ';4' or '')

    local color2csi = gui and color2csi24b or color2csi8b
    local escape_fg, escape_bg = '', ''
    if fg and type(fg) == 'number' then
        escape_fg = ';' .. color2csi(fg, true)
    elseif def_fg and ansi[def_fg] then
        escape_fg = ansi[def_fg]
    end
    if bg and type(bg) == 'number' then
        escape_fg = ';' .. color2csi(bg, false)
    elseif def_bg and ansi[def_bg] then
        escape_fg = ansi[def_bg]
    end

    return ('%s%s%sm%s\x1b[m'):format(escape_prefix, escape_fg, escape_bg, str)
end

function M.zz()
    local lnum1, lcount = api.nvim_win_get_cursor(0)[1], api.nvim_buf_line_count(0)
    local zb = 'keepj norm! %dzb'
    if lnum1 == lcount then
        cmd(zb:format(lnum1))
        return
    end
    cmd('norm! zvzz')
    lnum1 = api.nvim_win_get_cursor(0)[1]
    cmd('norm! L')
    local lnum2 = api.nvim_win_get_cursor(0)[1]
    if lnum2 + fn.getwinvar(0, '&scrolloff') >= lcount then
        cmd(zb:format(lnum2))
    end
    if lnum1 ~= lnum2 then
        cmd('keepj norm! ``')
    end
end

---
---@param bufnr number
---@param name string
---@param off number
---@return boolean
function M.is_unname_buf(bufnr, name, off)
    name = name or api.nvim_buf_get_name(bufnr)
    off = off or api.nvim_buf_get_offset(bufnr, 1)
    return name == '' and off <= 0
end

local function range2pos_list(lnum, col, end_lnum, end_col)
    if lnum > end_lnum or (lnum == end_col and col >= end_col) then
        return {}
    end
    if lnum == end_lnum then
        return {{lnum, col, end_col - col}}
    end
    local pos_list = {{lnum, col, 999}}
    for i = 1, end_lnum - lnum - 1 do
        table.insert(pos_list, {lnum + i})
    end
    local pos = {end_lnum, 1, end_col - 1}
    table.insert(pos_list, pos)
    return pos_list
end

---
---@param lnum number
---@param col number
---@param end_lnum number
---@param end_col number
---@return table[]
function M.qf_range2pos_list(lnum, col, end_lnum, end_col)
    return range2pos_list(lnum, col, end_lnum, end_col)
end

---
---@param range table
---@return table[]
function M.lsp_range2pos_list(range)
    local s_line, s_char, e_line, e_char
    if not pcall(function()
        s_line, s_char = range.start.line, range.start.character
        e_line, e_char = range['end'].line, range['end'].character
    end) then
        return {}
    end
    local lnum, end_lnum = s_line + 1, e_line + 1
    local col, end_col = s_char + 1, e_char + 1
    return range2pos_list(lnum, col, end_lnum, end_col)
end

---
---@param pattern string
---@return table[]
function M.pattern2pos_list(pattern)
    local lnum, col, end_lnum, end_col
    if not pcall(function()
        lnum, col = unpack(fn.searchpos(pattern, 'cn'))
        end_lnum, end_col = unpack(fn.searchpos(pattern, 'cen'))
        end_col = end_col + 1
    end) then
        return {}
    end
    return range2pos_list(lnum, col, end_lnum, end_col)
end

---
---@param hl string
---@param plist table[]
---@param prior number
---@return number[]
function M.matchaddpos(hl, plist, prior)
    vim.validate({hl = {hl, 'string'}, plist = {plist, 'table'}, prior = {prior, 'number', true}})
    prior = prior or 10

    local ids = {}
    local l = {}
    for i, p in ipairs(plist) do
        table.insert(l, p)
        if i % 8 == 0 then
            table.insert(ids, fn.matchaddpos(hl, l, prior))
            l = {}
        end
    end
    if #l > 0 then
        table.insert(ids, fn.matchaddpos(hl, l, prior))
    end
    return ids
end

---
---@param winid number
---@return number
function M.textoff(winid)
    vim.validate({winid = {winid, 'number'}})
    local textoff
    if M.has_06() then
        textoff = fn.getwininfo(winid)[1].textoff
    end

    if not textoff then
        M.win_execute(winid, function()
            local wv = fn.winsaveview()
            api.nvim_win_set_cursor(winid, {wv.lnum, 0})
            textoff = fn.wincol() - 1
            fn.winrestview(wv)
        end)
    end
    return textoff
end

---
---@param winid number
---@return boolean
function M.is_win_valid(winid)
    return winid and type(winid) == 'number' and winid > 0 and api.nvim_win_is_valid(winid)
end

---
---@param bufnr number
---@return boolean
function M.is_buf_loaded(bufnr)
    return bufnr and type(bufnr) == 'number' and bufnr > 0 and api.nvim_buf_is_loaded(bufnr)
end

---
---@param winid number
---@param func fun(): any[]
---@vararg any
---@return any
function M.win_execute(winid, func, ...)
    vim.validate({
        winid = {
            winid, function(w)
                return M.is_win_valid(w)
            end, 'a valid window'
        },
        func = {func, 'function'}
    })

    local cur_winid = api.nvim_get_current_win()
    local noa_set_win = 'noa call nvim_set_current_win(%d)'
    if cur_winid ~= winid then
        cmd(noa_set_win:format(winid))
    end
    local r = {pcall(func, ...)}
    if cur_winid ~= winid then
        cmd(noa_set_win:format(cur_winid))
    end
    table.remove(r, 1)
    return unpack(r)
end

local function syn_keyword(bufnr)
    local syn_info = api.nvim_buf_call(bufnr, function()
        return api.nvim_exec('syn iskeyword', true)
    end)
    local is_keyword = syn_info:match('^syntax iskeyword (.+)')
    if is_keyword == 'not set' then
        is_keyword = vim.bo[bufnr].iskeyword
    end
    return is_keyword
end

---
---@param bufnr number
---@return fun(b: number): boolean
function M.gen_is_keyword(bufnr)
    local str = syn_keyword(bufnr)
    -- :h isfname get the edge cases
    -- ^a-z,#,^
    -- _,-,128-140,#-43
    -- @,^a-z
    -- a-z,A-Z,@-@
    -- 48-57,,,_
    -- -~,^,,9
    local len = #str
    local tbl = {}
    local exclusive = false

    local function insert_tbl(bs, be)
        if be then
            for i = bs, be do
                tbl[i] = not exclusive
            end
        else
            tbl[bs] = not exclusive
        end
    end

    local function process(s)
        local function to_byte(char)
            local b
            if char then
                b = tonumber(char)
                if not b then
                    b = char:byte()
                end
            end
            return b
        end

        local ok = false
        if s == '@' then
            insert_tbl(('a'):byte(), ('z'):byte())
            insert_tbl(('A'):byte(), ('Z'):byte())
            ok = true
        elseif #s == 1 or s:match('^%d+$') then
            insert_tbl(to_byte(s))
            ok = true
        else
            local range_s, range_e = s:match('([^-]+)%-([^-]+)')
            range_s, range_e = to_byte(range_s), to_byte(range_e)
            if range_s and range_e then
                if range_e == range_s and range_s == ('@'):byte() then
                    insert_tbl(range_s)
                    ok = true
                elseif range_e > range_s then
                    insert_tbl(range_s, range_e)
                    ok = true
                end
            end
        end
        return ok
    end

    for i = 0, 255 do
        tbl[i] = false
    end

    local start = 1
    local i = 1
    while i <= len do
        local c = str:sub(i, i)
        if c == '^' then
            if i == len then
                insert_tbl(('^'):byte())
                start = start + 1
            elseif i == start then
                start = start + 1
                exclusive = true
            end
        elseif c == ',' then
            if process(str:sub(start, i - 1)) then
                start = i + 1
                exclusive = false
            end
        end
        i = i + 1
    end
    process(str:sub(start))
    return function(b)
        return tbl[b]
    end
end

--- TODO upstream bug
--- local f_win_so = vim.wo[winid].scrolloff
--- return a big number like '1.4014575443238e+14' if window option is absent
--- Use getwinvar to workaround
---@param winid number
---@return number
function M.scrolloff(winid)
    return fn.getwinvar(winid, '&scrolloff')
end

---@param winid number
---@param name string
---@param def any
function M.getwinvar(winid, name, def)
    if M.has_06() then
        if name:match('^&') then
            return vim.wo[winid][name:sub(2)]
        else
            return vim.w[winid][name] or def
        end
    else
        return fn.getwinvar(winid, name, def)
    end
end

--- 1. use uv read file will cause much cpu usage and memory usage
--- 2. type of result returned by read is string, it must convert to table first
--- 3. nvim_buf_set_lines is expensive for flushing all buffers
---@param from number
---@param to number
function M.transfer_buf(from, to)
    local function transfer_file(rb, wb)
        local e_path = fn.fnameescape(api.nvim_buf_get_name(rb))
        local ok, msg = pcall(api.nvim_buf_call, wb, function()
            cmd(([[
                noa call deletebufline(%d, 1, '$')
                noa sil 0read %s
                noa call deletebufline(%d, '$')
            ]]):format(wb, e_path, wb))
        end)
        return ok, msg
    end
    local from_loaded = api.nvim_buf_is_loaded(from)
    if from_loaded then
        if vim.bo[from].modified then
            local lines = api.nvim_buf_get_lines(from, 0, -1, false)
            api.nvim_buf_set_lines(to, 0, -1, false, lines)
        else
            if not transfer_file(from, to) then
                local lines = api.nvim_buf_get_lines(from, 0, -1, false)
                api.nvim_buf_set_lines(to, 0, -1, false, lines)
            end
        end
    else
        local ok, msg = transfer_file(from, to)
        if not ok then
            if msg:match([[:E484: Can't open file]]) then
                cmd(('noa call bufload(%d)'):format(from))
                local lines = api.nvim_buf_get_lines(from, 0, -1, false)
                cmd(('noa bun %d'):format(from))
                api.nvim_buf_set_lines(to, 0, -1, false, lines)
            end

        end
    end
    vim.bo[to].modified = false
end

---
---@param str string
---@param ts number
---@param start number
---@return string
function M.expandtab(str, ts, start)
    start = start or 1
    local new = str:sub(1, start - 1)
    -- without check type to improve performance
    -- if str and type(str) == 'string' then
    local pad = ' '
    local ti = start - 1
    local i = start
    while true do
        i = str:find('\t', i, true)
        if not i then
            if ti == 0 then
                new = str
            else
                new = new .. str:sub(ti + 1)
            end
            break
        end
        if ti + 1 == i then
            new = new .. pad:rep(ts)
        else
            local append = str:sub(ti + 1, i - 1)
            new = new .. append .. pad:rep(ts - api.nvim_strwidth(append) % ts)
        end
        ti = i
        i = i + 1
    end
    -- end
    return new
end

return M
