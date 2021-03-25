local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

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

local function color2csi24b(color_num, fg)
    local r = math.floor(color_num / 2 ^ 16)
    local g = math.floor(math.floor(color_num / 2 ^ 8) % 2 ^ 8)
    local b = math.floor(color_num % 2 ^ 8)
    return string.format('%d;2;%d;%d;%d', fg and 38 or 48, r, g, b)
end

local function color2csi8b(color_num, fg)
    return string.format('%d;5;%d', fg and 38 or 48, color_num)
end

function M.render_str(str, group_name, def_fg)
    local gui = vim.o.termguicolors
    local ok, msg = pcall(api.nvim_get_hl_by_name, group_name, gui)
    if not ok then
        return ''
    end
    local hl = msg
    local fg = hl.reverse and hl.background or hl.foreground
    local bg = hl.reverse and hl.foreground or hl.background
    local escape_prefix = string.format('\x1b[%s%s%s', hl.bold and ';1' or '',
        hl.italic and ';3' or '', hl.underline and ';4' or '')
    local color2csi = gui and color2csi24b or color2csi8b
    local escape_fg = fg and ';' .. color2csi(fg, true) or ansi[def_fg]
    local escape_bg = bg and ';' .. color2csi(fg, true) or ''
    return string.format('%s%s%sm%s\x1b[m', escape_prefix, escape_fg, escape_bg, str)
end

function M.zz()
    local lnum1, lcount = api.nvim_win_get_cursor(0)[1], api.nvim_buf_line_count(0)
    if lnum1 == lcount then
        fn.execute(string.format('keepjumps normal! %dzb', lnum1))
        return
    end
    cmd('normal! zvzz')
    lnum1 = api.nvim_win_get_cursor(0)[1]
    cmd('normal! L')
    local lnum2 = api.nvim_win_get_cursor(0)[1]
    if lnum2 + fn.getwinvar(0, '&scrolloff') >= lcount then
        fn.execute(string.format('keepjumps normal! %dzb', lnum2))
    end
    if lnum1 ~= lnum2 then
        cmd('keepjumps normal! ``')
    end
end

function M.lsp_range2pos_list(lsp_ranges)
    local s_line, s_char, e_line, e_char, s_lnum, e_lnum
    if not pcall(function()
        s_line, s_char = lsp_ranges.start.line, lsp_ranges.start.character
        e_line, e_char = lsp_ranges['end'].line, lsp_ranges['end'].character
    end) then
        return {}
    end
    s_lnum, e_lnum = s_line + 1, e_line + 1
    if s_line > e_line or (s_line == e_line and s_char > e_char) then
        return {}
    end
    if s_line == e_line then
        return {{s_lnum, s_char + 1, e_char - s_char}}
    end
    local pos_list = {{s_lnum, s_char + 1, 999}}
    for i = 1, e_line - s_line - 1 do
        table.insert(pos_list, {s_lnum + i})
    end
    local pos = {e_lnum, 1, e_char}
    table.insert(pos_list, pos)
    return pos_list
end

function M.pattern2pos_list(pattern_hl)
    local s_lnum, s_col, e_lnum, e_col
    if not pcall(function()
        s_lnum, s_col = unpack(fn.searchpos(pattern_hl, 'cn'))
        e_lnum, e_col = unpack(fn.searchpos(pattern_hl, 'cen'))
    end) then
        return {}
    end
    if s_lnum == 0 or s_col == 0 or e_lnum == 0 or e_col == 0 then
        return {}
    end
    if s_lnum == e_lnum then
        return {{s_lnum, s_col, e_col - s_col + 1}}
    end
    local pos_list = {{s_lnum, s_col, 999}}
    for i = 1, e_lnum - s_lnum - 1 do
        table.insert(pos_list, {s_lnum + i})
    end
    local pos = {e_lnum, 1, e_col}
    table.insert(pos_list, pos)
    return pos_list
end

function M.matchaddpos(higroup, pos_list, prior)
    assert(type(higroup) == 'string', 'argument higroup #1 expect a string type')
    assert(type(pos_list) == 'table', 'argument pos_list #2 expect a table type')
    prior = tonumber(prior) or 10
    assert(type(prior) == 'number', 'argument prior #3 expect a number type')

    local ids = {}
    local l = {}
    for i, p in ipairs(pos_list) do
        table.insert(l, p)
        if i % 8 == 0 then
            table.insert(ids, fn.matchaddpos(higroup, l, prior))
            l = {}
        end
    end
    if #l > 0 then
        table.insert(ids, fn.matchaddpos(higroup, l, prior))
    end
    return ids
end

function M.gutter_size(winid, lnum, col)
    assert(type(winid) == 'number', 'argument winid #1 expect a number type')
    if not lnum or not col then
        lnum, col = unpack(api.nvim_win_get_cursor(winid))
    end
    local size
    M.win_execute(winid, function()
        api.nvim_win_set_cursor(winid, {lnum, 0})
        size = fn.wincol() - 1
        api.nvim_win_set_cursor(winid, {lnum, col})
    end)
    return size
end

function M.win_execute(winid, func)
    assert(winid and api.nvim_win_is_valid(winid), 'argument winid #1 expect an available window')
    assert(type(func) == 'function', 'argument func #2 expect a function type')

    local cur_winid = api.nvim_get_current_win()
    if cur_winid ~= winid then
        cmd(string.format('noautocmd call nvim_set_current_win(%d)', winid))
    end
    func()
    if cur_winid ~= winid then
        cmd(string.format('noautocmd call nvim_set_current_win(%d)', cur_winid))
    end
end

return M
