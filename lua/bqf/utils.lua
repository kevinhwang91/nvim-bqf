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
    return ('%d;2;%d;%d;%d'):format(fg and 38 or 48, r, g, b)
end

local function color2csi8b(color_num, fg)
    return ('%d;5;%d'):format(fg and 38 or 48, color_num)
end

function M.render_str(str, group_name, def_fg, def_bg)
    vim.validate({
        str = {str, 'string'},
        group_name = {group_name, 'string'},
        def_fg = {def_fg, 'string', true},
        def_bg = {def_bg, 'string', true}
    })
    local gui = vim.o.termguicolors
    local ok, hl = pcall(api.nvim_get_hl_by_name, group_name, gui)
    if not ok then
        return ''
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
        fn.execute(zb:format(lnum1))
        return
    end
    cmd('norm! zvzz')
    lnum1 = api.nvim_win_get_cursor(0)[1]
    cmd('norm! L')
    local lnum2 = api.nvim_win_get_cursor(0)[1]
    if lnum2 + fn.getwinvar(0, '&scrolloff') >= lcount then
        fn.execute(zb:format(lnum2))
    end
    if lnum1 ~= lnum2 then
        cmd('keepj norm! ``')
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

function M.gutter_size(winid, lnum)
    vim.validate({winid = {winid, 'number'}, lnum = {lnum, 'number', true}})
    lnum = lnum or api.nvim_win_get_cursor(winid)[1]
    return fn.screenpos(winid, lnum, 1).curscol - fn.win_screenpos(winid)[2]
end

function M.win_execute(winid, func)
    vim.validate({
        winid = {
            winid, function(w)
                return w and api.nvim_win_is_valid(w)
            end, 'a valid window'
        },
        func = {func, 'function'}
    })

    local cur_winid = api.nvim_get_current_win()
    local noa_set_win = 'noa call nvim_set_current_win(%d)'
    if cur_winid ~= winid then
        cmd(noa_set_win:format(winid))
    end
    local ret = func()
    if cur_winid ~= winid then
        cmd(noa_set_win:format(cur_winid))
    end
    return ret
end

return M
