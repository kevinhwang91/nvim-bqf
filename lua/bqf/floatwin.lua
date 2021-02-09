local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local border_chars, win_height, win_vheight

local preview_winid = -1
local border_winid = -1

local qfpos = require('bqf.qfpos')

cmd('highlight default link BqfPreviewFloat Normal')
cmd('highlight default link BqfPreviewBorder Normal')

local function get_opts(qf_winid, file_winid)
    local rel_pos, abs_pos = unpack(qfpos.get_pos(qf_winid, file_winid))

    local qf_info = fn.getwininfo(qf_winid)[1]
    local opts = {relative = 'win', win = qf_winid, focusable = false, style = 'minimal'}
    local width, height, col, row, anchor
    if rel_pos == 'above' or rel_pos == 'below' or abs_pos == 'top' or abs_pos == 'bottom' then
        local row_pos = qf_info.winrow
        width = qf_info.width - 2
        col = 1
        if rel_pos == 'above' or abs_pos == 'top' then
            anchor = 'NW'
            height = math.min(win_height, vim.o.lines - 4 - row_pos - qf_info.height)
            row = qf_info.height + 2
        else
            anchor = 'SW'
            height = math.min(win_height, row_pos - 4)
            row = -2
        end
    elseif rel_pos == 'left' or rel_pos == 'right' or abs_pos == 'left_far' or abs_pos ==
        'right_far' then
        if abs_pos == 'left_far' then
            width = vim.o.columns - fn.win_screenpos(2)[2] - 1
        elseif abs_pos == 'right_far' then
            width = qf_info.wincol - 4
        else
            width = api.nvim_win_get_width(file_winid) - 2
        end
        height = math.min(win_vheight, qf_info.height - 2)
        local winline = fn.winline()
        row = height >= winline and 1 or winline - height - 1
        if rel_pos == 'left' or abs_pos == 'left_far' then
            anchor = 'NW'
            col = qf_info.width + 2
        else
            anchor = 'NE'
            col = -2
        end
    else
        return {}, {}
    end

    if width < 1 or height < 1 then
        return {}, {}
    end

    local preview_opts = vim.tbl_extend('force', opts, {
        anchor = anchor,
        width = width,
        height = height,
        col = col,
        row = row
    })
    local border_opts = vim.tbl_extend('force', opts, {
        anchor = anchor,
        width = width + 2,
        height = height + 2,
        col = anchor:match('W') and col - 1 or col + 1,
        row = anchor:match('N') and row - 1 or row + 1
    })
    return preview_opts, border_opts
end

local function update_border_buf(border_opts, border_buf)
    local width, height = border_opts.width, border_opts.height
    local top = border_chars[5] .. border_chars[3]:rep(width - 2) .. border_chars[6]
    local mid = border_chars[1] .. string.rep(' ', width - 2) .. border_chars[2]
    local bot = border_chars[7] .. border_chars[4]:rep(width - 2) .. border_chars[8]
    local lines = {top}
    for _ = 1, height - 2 do
        table.insert(lines, mid)
    end
    table.insert(lines, bot)
    if not border_buf then
        border_buf = api.nvim_create_buf(false, true)
        vim.bo[border_buf].bufhidden = 'wipe'
    end
    api.nvim_buf_set_lines(border_buf, 0, -1, 1, lines)
    return border_buf
end

function M.set_win_height(p_hei, p_vhei)
    win_height, win_vheight = p_hei, p_vhei
end

function M.update_scrollbar()
    local buf = fn.winbufnr(preview_winid)
    local border_buf = fn.winbufnr(border_winid)
    local line_count = api.nvim_buf_line_count(buf)

    local win_info = fn.getwininfo(preview_winid)[1]
    local topline, height = win_info.topline, win_info.height

    local bar_size = math.min(height, math.ceil(height * height / line_count))

    local bar_pos = math.ceil(height * topline / line_count)
    if bar_pos + bar_size > height then
        bar_pos = height - bar_size + 1
    end

    local lines = api.nvim_buf_get_lines(border_buf, 1, -2, true)
    for i = 1, #lines do
        local bar_char
        if i >= bar_pos and i < bar_pos + bar_size then
            bar_char = border_chars[#border_chars]
        else
            bar_char = border_chars[2]
        end
        local line = lines[i]
        lines[i] = fn.strcharpart(line, 0, fn.strwidth(line) - 1) .. bar_char
    end
    api.nvim_buf_set_lines(border_buf, 1, -2, 0, lines)
end

function M.update_title(title)
    local border_buf = fn.winbufnr(border_winid)
    local top = api.nvim_buf_get_lines(border_buf, 0, 1, 0)[1]
    local prefix = fn.strcharpart(top, 0, 3)
    local suffix = fn.strcharpart(top, fn.strwidth(title) + 3, fn.strwidth(top))
    title = string.format('%s%s%s', prefix, title, suffix)
    api.nvim_buf_set_lines(border_buf, 0, 1, 1, {title})
end

function M.validate_window()
    return preview_winid > 0 and api.nvim_win_is_valid(preview_winid)
end

function M.winid()
    return preview_winid, border_winid
end

function M.close()
    if M.validate_window() then
        api.nvim_win_close(preview_winid, true)
        api.nvim_win_close(border_winid, true)
    end
end

function M.setup(opts)
    assert(type(opts) == 'table', 'argument opts #1 expect a table type')
    border_chars = opts.border_chars
    win_height = tonumber(opts.win_height)
    win_vheight = tonumber(opts.win_vheight or win_height)
    assert(type(border_chars) == 'table' and #border_chars == 9,
        'border_chars expect a table with 9 chars')
    assert(type(win_height) == 'number', 'win_height expect a number type')
    assert(type(win_vheight) == 'number', 'win_vheight expect a number type')
end

function M.open(bufnr, qf_winid, file_winid)
    local preview_opts, border_opts = get_opts(qf_winid, file_winid)
    if vim.tbl_isempty(preview_opts) or vim.tbl_isempty(border_opts) then
        return -1, -1
    end

    local border_buf
    if M.validate_window() then
        border_buf = fn.winbufnr(border_winid)
        update_border_buf(border_opts, border_buf)
        api.nvim_win_set_config(border_winid, border_opts)
        api.nvim_win_set_config(preview_winid, preview_opts)
        api.nvim_win_set_buf(preview_winid, bufnr)
    else
        preview_winid = api.nvim_open_win(bufnr, false, preview_opts)
        border_buf = update_border_buf(border_opts)
        border_winid = api.nvim_open_win(border_buf, false, border_opts)
    end
    api.nvim_win_set_option(border_winid, 'winhighlight', 'Normal:BqfPreviewBorder')
    api.nvim_win_set_option(preview_winid, 'winhighlight', 'Normal:BqfPreviewFloat')
    return preview_winid, border_winid
end

return M
