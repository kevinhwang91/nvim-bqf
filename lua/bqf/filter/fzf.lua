local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd
local uv = vim.loop

local preview = require('bqf.preview')
local jump = require('bqf.jump')
local utils = require('bqf.utils')
local supply = require('bqf.supply')
local qftool = require('bqf.qftool')
local config = require('bqf.config')

local def_config = {
    action_for = {['ctrl-t'] = 'tabedit', ['ctrl-x'] = 'split', ['ctrl-v'] = 'vsplit'},
    extra_opts = {'--bind', 'ctrl-o:toggle-all'}
}

local action_for, extra_opts, has_tail

local function setup()
    assert(fn.exists('*fzf#run') == 1,
        'fzf#run function not found. You also need Vim plugin from the main fzf repository')
    local filter_conf = config.filter or {}
    filter_conf.fzf = vim.tbl_deep_extend('force', def_config, filter_conf.fzf or {})
    action_for, extra_opts = filter_conf.fzf.action_for, filter_conf.fzf.extra_opts
    assert(type(action_for) == 'table', 'fzf.action_for expect a table type')
    assert(type(extra_opts) == 'table', 'fzf.extra_opts expect a table type')
    config.filter = filter_conf
    has_tail = fn.executable('tail') == 1

    api.nvim_exec([[
        augroup BqfFilterFzf
            autocmd!
        augroup END
    ]], false)
end

local function fzf_handler(qf_winid, ret)
    if #ret < 2 then
        return
    end

    local key = table.remove(ret, 1)
    local selected_index = vim.tbl_map(function(e)
        return tonumber(e:match('%d+'))
    end, ret)
    table.sort(selected_index)

    local idx
    if #selected_index == 1 then
        idx = selected_index[1]
        local action = action_for[key]
        if action == 'tabedit' then
            jump.tabedit(false, qf_winid, idx)
        elseif action == 'split' then
            jump.split(false, qf_winid, idx)
        elseif action == 'vsplit' then
            jump.split(true, qf_winid, idx)
        else
            jump.open(true, qf_winid, idx)

        end
        return
    end

    local qf_all = qftool.getall(qf_winid)
    local context, title, old_items = qf_all.context, qf_all.title, qf_all.items
    local lsp_ranges, items = {}, {}
    for _, index in ipairs(selected_index) do
        table.insert(items, old_items[index])
        if qf_all.lsp_ranges_hl then
            table.insert(lsp_ranges, qf_all.lsp_ranges_hl[index])
        end
    end

    if #lsp_ranges > 0 then
        context.bqf.lsp_ranges_hl = lsp_ranges
    end

    local qf_hei = api.nvim_win_get_height(qf_winid)
    title = '*' .. title
    qftool.set({nr = '$', context = context, title = title, items = items}, qf_winid)
    if qf_hei > #selected_index then
        preview.redraw_win(qf_winid)
    end
end

local function create_job(qf_winid, tmpfile)
    io.open(tmpfile, 'w'):close()
    local stdout = uv.new_pipe(false)
    local handle, pid
    handle, pid = uv.spawn('tail', {args = {'-f', tmpfile}, stdio = {nil, stdout}}, function()
        stdout:close()
        handle:close()
        os.remove(tmpfile)
    end)
    stdout:read_start(function(_, data)
        if not data or data == '' then
            return
        end

        local tbl_data = vim.split(data, ',')
        local idx
        while #tbl_data > 0 and not idx do
            idx = tonumber(table.remove(tbl_data))
        end
        if idx < 1 then
            return
        end
        vim.schedule(function()
            local col = api.nvim_win_get_cursor(qf_winid)[2]
            api.nvim_win_set_cursor(qf_winid, {idx, col})
            preview.open(qf_winid, idx)
        end)
    end)
    return pid
end

function M.prepare(qf_winid, pid)
    local row, col = unpack(api.nvim_win_get_position(qf_winid))
    local line_count = api.nvim_buf_line_count(fn.winbufnr(qf_winid))
    api.nvim_win_set_config(false, {
        relative = 'editor',
        width = api.nvim_win_get_width(qf_winid),
        height = math.min(api.nvim_win_get_height(qf_winid) + 1, line_count + 1),
        col = col,
        row = row
    })

    if pid then
        cmd('augroup BqfFilterFzf')
        cmd(string.format('autocmd BufWipeout <buffer> %s',
            string.format('lua vim.loop.kill(%d, 15)', pid)))
        cmd('augroup END')
    end
end

function M.run()
    local fzf_existed = fn.exists('*fzf#run') == 1
    if not fzf_existed then
        return
    end

    local qf_winid = api.nvim_get_current_win()
    local qf_type = qftool.type()
    local items, prompt
    if qf_type == 'loc' then
        items = fn.getloclist(0)
        prompt = 'Location> '
    else
        items = fn.getqflist()
        prompt = 'Quickfix> '
    end
    if #items < 2 then
        return
    end

    local padding = utils.gutter_size(qf_winid) - 2
    local expect_keys = table.concat(vim.tbl_keys(action_for), ',')
    local escape_filename = utils.render_str('%s', 'qfFileName', 'blue')
    local escape_linenr = utils.render_str('%d col %d', 'qfLineNr', 'black')
    local escape_seqarator = utils.render_str('|', 'qfSeparator', 'white')
    local escape_error = utils.render_str('%s', 'qfError', 'red')
    local fmt = string.format('%%d\t%s%s%s%s%s %%s', string.rep(' ', padding), escape_filename,
        escape_seqarator, escape_linenr, escape_seqarator)
    local fmt_e = string.format('%%d\t%s%s%s%s %s%s %%s', string.rep(' ', padding), escape_filename,
        escape_seqarator, escape_linenr, escape_error, escape_seqarator)
    local opts = {
        source = supply.tbl_kv_map(function(key, val)
            local ret
            if not val.type or val.type == '' then
                ret = string.format(fmt, key, fn.bufname(val.bufnr), val.lnum, val.col,
                    vim.trim(val.text))
            else
                ret = string.format(fmt_e, key, fn.bufname(val.bufnr), val.lnum, val.col,
                    val.type == 'E' and 'error' or val.type, vim.trim(val.text))
            end
            return ret
        end, items),
        ['sink*'] = nil,
        options = supply.tbl_concat({
            '--multi', '--ansi', '--with-nth', '2..', '--delimiter', '\t', '--header-lines', 0,
            '--tiebreak', 'index', '--info', 'inline', '--prompt', prompt, '--no-border',
            '--layout', 'reverse-list', '--expect', expect_keys
        }, extra_opts),
        window = {width = 2, height = 2, xoffset = 1, yoffset = 0, border = 'none'}
    }

    local pid
    if has_tail then
        if preview.auto_enabled() then
            local tmpfile = fn.tempname()
            supply.tbl_concat(opts.options,
                {'--preview-window', 0, '--preview', 'echo -n {1}, >> ' .. tmpfile})
            pid = create_job(qf_winid, tmpfile)
            preview.keep_preview()
        end
    else
        -- also need echo :)
        api.nvim_err_writeln([[preview need 'tail' command]])
    end

    cmd(string.format('autocmd BqfFilterFzf FileType fzf ++once %s', string.format(
        [[lua require('bqf.filter.fzf').prepare(%d, %s)]], qf_winid, tostring(pid))))

    -- TODO lua can't translate nested table data to vimscript
    local fzf_wrap = fn['fzf#wrap'](opts)
    fzf_wrap['sink*'] = function(ret)
        return fzf_handler(qf_winid, ret)
    end
    fn['fzf#run'](fzf_wrap)
end

setup()

return M
