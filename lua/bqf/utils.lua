---@class BqfUtils
local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd
local uv = vim.loop

---@return fun(): boolean
M.has06 = (function()
    local has06
    return function()
        if has06 == nil then
            has06 = fn.has('nvim-0.6') == 1
        end
        return has06
    end
end)()

---
---@return fun(): boolean
M.has08 = (function()
    local has08
    return function()
        if has08 == nil then
            has08 = fn.has('nvim-0.8') == 1
        end
        return has08
    end
end)()

---@return fun(): boolean
M.isWindows = (function()
    local isWin
    return function()
        if isWin == nil then
            isWin = uv.os_uname().sysname == 'Windows_NT'
        end
        return isWin
    end
end)()

---@return fun(): boolean
M.jitEnabled = (function()
    local enabled
    return function()
        if enabled == nil then
            enabled = jit ~= nil and (not M.isWindows() or M.has06())
        end
        return enabled
    end
end)()

local function colorToCSI24b(colorNum, fg)
    local r = math.floor(colorNum / 2 ^ 16)
    local g = math.floor(math.floor(colorNum / 2 ^ 8) % 2 ^ 8)
    local b = math.floor(colorNum % 2 ^ 8)
    return ('%d;2;%d;%d;%d'):format(fg and 38 or 48, r, g, b)
end

local function colorToCSI8b(colorNum, fg)
    return ('%d;5;%d'):format(fg and 38 or 48, colorNum)
end

---
---@param bufnr number
---@return string[]
function M.syntaxList(bufnr)
    local list = {}
    local synInfo = api.nvim_buf_call(bufnr, function()
        return api.nvim_exec('syn', true)
    end)
    for line in vim.gsplit(synInfo, '\n') do
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
---@param groupName string
---@param defaultFg? string
---@param defaultBg? string
---@return string
function M.renderStr(str, groupName, defaultFg, defaultBg)
    vim.validate({
        str = {str, 'string'},
        groupName = {groupName, 'string'},
        defaultFg = {defaultFg, 'string', true},
        defaultBg = {defaultBg, 'string', true}
    })
    local gui = vim.o.termguicolors
    local ok, hl = pcall(api.nvim_get_hl_by_name, groupName, gui)
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
    local escapePrefix = ('\027[%s%s%s'):format(hl.bold and ';1' or '', hl.italic and ';3' or '',
                                                hl.underline and ';4' or '')

    local colorToCSI = gui and colorToCSI24b or colorToCSI8b
    local escapeFg, escapeBg = '', ''
    if fg and type(fg) == 'number' then
        escapeFg = ';' .. colorToCSI(fg, true)
    elseif defaultFg and ansi[defaultFg] then
        escapeFg = ansi[defaultFg]
    end
    if bg and type(bg) == 'number' then
        escapeFg = ';' .. colorToCSI(bg, false)
    elseif defaultBg and ansi[defaultBg] then
        escapeFg = ansi[defaultBg]
    end

    return ('%s%s%sm%s\027[m'):format(escapePrefix, escapeFg, escapeBg, str)
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
---@param name? string
---@param off? number
---@return boolean
function M.isUnNameBuf(bufnr, name, off)
    name = name or api.nvim_buf_get_name(bufnr)
    off = off or api.nvim_buf_get_offset(bufnr, 1)
    return name == '' and off <= 0
end

local function rangeToPosList(lnum, col, endLnum, endCol)
    if lnum > endLnum or (lnum == endCol and col >= endCol) then
        return {}
    end
    if lnum == endLnum then
        return {{lnum, col, endCol - col}}
    end
    local posList = {{lnum, col, 999}}
    for i = 1, endLnum - lnum - 1 do
        table.insert(posList, {lnum + i})
    end
    local pos = {endLnum, 1, endCol - 1}
    table.insert(posList, pos)
    return posList
end

---
---@param lnum number
---@param col number
---@param endLnum number
---@param endCol number
---@return table[]
function M.qfRangeToPosList(lnum, col, endLnum, endCol)
    return rangeToPosList(lnum, col, endLnum, endCol)
end

---
---@param range table
---@return table[]
function M.lspRangeToPosList(range)
    local startLine, startChar, endLine, endChar
    if not pcall(function()
        startLine, startChar = range.start.line, range.start.character
        endLine, endChar = range['end'].line, range['end'].character
    end) then
        return {}
    end
    local lnum, endLnum = startLine + 1, endLine + 1
    local col, endCol = startChar + 1, endChar + 1
    return rangeToPosList(lnum, col, endLnum, endCol)
end

---
---@param pattern string
---@return table[]
function M.patternToPosList(pattern)
    local lnum, col, endLnum, endCol
    if not pcall(function()
        lnum, col = unpack(fn.searchpos(pattern, 'cn'))
        endLnum, endCol = unpack(fn.searchpos(pattern, 'cen'))
        endCol = endCol + 1
    end) then
        return {}
    end
    return rangeToPosList(lnum, col, endLnum, endCol)
end

---
---@param hl string
---@param plist table[]
---@param prior? number
---@return number[]
function M.matchAddPos(hl, plist, prior)
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
---@return table
function M.getWinInfo(winid)
    local winfos = fn.getwininfo(winid)
    assert(type(winfos) == 'table' and #winfos == 1,
           '`getwininfo` expected 1 table with single element.')
    return winfos[1]
end

---
---@param winid number
---@return number
function M.textoff(winid)
    vim.validate({winid = {winid, 'number'}})
    local textoff
    if M.has06() then
        textoff = M.getWinInfo(winid).textoff
    end

    if not textoff then
        M.winExecute(winid, function()
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
function M.isWinValid(winid)
    if winid then
        return type(winid) == 'number' and winid > 0 and api.nvim_win_is_valid(winid)
    else
        return false
    end
end

---
---@param bufnr number
---@return boolean
function M.isBufLoaded(bufnr)
    return bufnr and type(bufnr) == 'number' and bufnr > 0 and api.nvim_buf_is_loaded(bufnr)
end

---
---@param winid number
---@param func fun(): any[]
---@vararg any
---@return any
function M.winExecute(winid, func, ...)
    vim.validate({
        winid = {winid, M.isWinValid, 'a valid window'},
        func = {func, 'function'}
    })

    local curWinid = api.nvim_get_current_win()
    local noaSetWin = 'noa call nvim_set_current_win(%d)'
    if curWinid ~= winid then
        cmd(noaSetWin:format(winid))
    end
    local r = {pcall(func, ...)}
    if curWinid ~= winid then
        cmd(noaSetWin:format(curWinid))
    end
    return unpack(r, 2)
end

local function synKeyword(bufnr)
    local synInfo = api.nvim_buf_call(bufnr, function()
        return api.nvim_exec('syn iskeyword', true)
    end)
    local isKeyword = synInfo:match('^syntax iskeyword (.+)')
    if not isKeyword or isKeyword == '' or isKeyword == 'not set' then
        isKeyword = vim.bo[bufnr].iskeyword
    end
    return isKeyword
end

---
---@param bufnr number
---@return fun(b: number): boolean
function M.genIsKeyword(bufnr)
    local str = synKeyword(bufnr)
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

    ---
    ---@param bs number
    ---@param be? number
    local function insertTbl(bs, be)
        if be then
            for i = bs, be do
                tbl[i] = not exclusive
            end
        else
            tbl[bs] = not exclusive
        end
    end

    local function process(s)
        local function toByte(char)
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
            insertTbl(('a'):byte(), ('z'):byte())
            insertTbl(('A'):byte(), ('Z'):byte())
            ok = true
        elseif #s == 1 or s:match('^%d+$') then
            insertTbl(toByte(s))
            ok = true
        else
            local rangeStart, rangeEnd = s:match('([^-]+)%-([^-]+)')
            rangeStart, rangeEnd = toByte(rangeStart), toByte(rangeEnd)
            if rangeStart and rangeEnd then
                if rangeEnd == rangeStart and rangeStart == ('@'):byte() then
                    insertTbl(rangeStart)
                    ok = true
                elseif rangeEnd > rangeStart then
                    insertTbl(rangeStart, rangeEnd)
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
                insertTbl(('^'):byte())
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
--- local scrollOff = vim.wo[winid].scrolloff
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
    if M.has06() then
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
function M.transferBuf(from, to)
    local function transferFile(rb, wb)
        local ePath = fn.fnameescape(api.nvim_buf_get_name(rb))
        local ok, msg = pcall(api.nvim_buf_call, wb, function()
            cmd(([[
                noa call deletebufline(%d, 1, '$')
                noa sil 0read %s
                noa call deletebufline(%d, '$')
            ]]):format(wb, ePath, wb))
        end)
        return ok, msg
    end

    local fromLoaded = api.nvim_buf_is_loaded(from)
    if fromLoaded then
        if vim.bo[from].modified then
            local lines = api.nvim_buf_get_lines(from, 0, -1, false)
            api.nvim_buf_set_lines(to, 0, -1, false, lines)
        else
            if not transferFile(from, to) then
                local lines = api.nvim_buf_get_lines(from, 0, -1, false)
                api.nvim_buf_set_lines(to, 0, -1, false, lines)
            end
        end
    else
        local ok, msg = transferFile(from, to)
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
---@param start? number
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
