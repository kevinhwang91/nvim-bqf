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
local base = require('bqf.filter.base')
local config = require('bqf.config')
local sign = require('bqf.sign')

local action_for, extra_opts, has_tail

local qf_types

local function setup()
    assert(vim.g.loaded_fzf or fn.exists('*fzf#run') == 1,
        'fzf#run function not found. You also need Vim plugin from the main fzf repository')
    local fzf_conf = config.filter.fzf
    action_for, extra_opts = fzf_conf.action_for, fzf_conf.extra_opts
    vim.validate({action_for = {action_for, 'table'}, extra_opts = {extra_opts, 'table'}})
    has_tail = fn.executable('tail') == 1

    local w, i, n, e = 'warning', 'info', 'note', 'error'
    qf_types = {w = w, W = w, i = i, I = i, n = n, N = n, e = e, E = e}
    api.nvim_exec([[
        aug BqfFilterFzf
            au!
        aug END
    ]], false)
end

local function handler(qf_winid, ret)
    local key = table.remove(ret, 1)
    local selected_index = vim.tbl_map(function(e)
        return tonumber(e:match('%d+'))
    end, ret)
    table.sort(selected_index)

    local idx
    local action = action_for[key]
    if #selected_index == 1 then
        idx = selected_index[1]
        if action == 'tabedit' then
            local col = api.nvim_win_get_cursor(qf_winid)[2]
            api.nvim_win_set_cursor(qf_winid, {idx, col})
            jump.tabedit(false, qf_winid, idx)
        elseif action == 'split' then
            jump.split(false, qf_winid, idx)
        elseif action == 'vsplit' then
            jump.split(true, qf_winid, idx)
        elseif not action then
            jump.open(true, qf_winid, idx)
        end
    end

    if action == 'signtoggle' then
        for _, i in ipairs(selected_index) do
            sign.toggle(0, api.nvim_win_get_buf(qf_winid), i)
        end
    else
        if #selected_index == 1 then
            return
        end
        local qf_all = qftool.getall(qf_winid)
        base.filter_list(qf_winid, coroutine.wrap(function()
            for _, i in ipairs(selected_index) do
                coroutine.yield(i, qf_all.items[i])
            end
        end))
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
    local line_count = api.nvim_buf_line_count(api.nvim_win_get_buf(qf_winid))
    api.nvim_win_set_config(0, {
        relative = 'win',
        win = qf_winid,
        width = api.nvim_win_get_width(qf_winid),
        height = math.min(api.nvim_win_get_height(qf_winid) + 1, line_count + 1),
        row = 0,
        col = 0
    })

    if pid then
        cmd('aug BqfFilterFzf')
        cmd(('au BufWipeout <buffer> %s'):format(('lua vim.loop.kill(%d, 15)'):format(pid)))
        cmd('aug END')
    end
end

function M.run()
    local qf_winid = api.nvim_get_current_win()
    local qf_type = qftool.type()
    local prompt = qf_type == 'loc' and ' Location> ' or ' Quickfix> '
    local qf_all = qftool.getall(qf_winid)
    local items, signs = qf_all.items, qf_all.signs or {}
    if #items < 2 then
        return
    end

    local padding = (' '):rep(utils.gutter_size(qf_winid) - 4)
    local expect_keys = table.concat(vim.tbl_keys(action_for), ',')
    local escape_sign = utils.render_str('^', 'BqfSign', 'cyan')
    local escape_filename = utils.render_str('%s', 'qfFileName', 'blue')
    local escape_linenr = utils.render_str('%d col %d', 'qfLineNr', 'black')
    local escape_seqarator = utils.render_str('|', 'qfSeparator', 'white')
    local escape_error = utils.render_str('%s', 'qfError', 'red')
    local fmt = ('%%d\t%s%%s %s%s%s%s %%s'):format(padding, escape_filename, escape_seqarator,
        escape_linenr, escape_seqarator)
    local fmt_e = ('%%d\t%s%%s %s%s%s %s%s %%s'):format(padding, escape_filename, escape_seqarator,
        escape_linenr, escape_error, escape_seqarator)
    local opts = {
        source = supply.tbl_kv_map(function(key, val)
            local ret
            if not val.type or val.type == '' then
                ret = fmt:format(key, signs[key] and escape_sign or ' ',
                    fn.bufname(val.bufnr), val.lnum, val.col, vim.trim(val.text))
            else
                ret = fmt_e:format(key, signs[key] and escape_sign or ' ',
                    fn.bufname(val.bufnr), val.lnum, val.col,
                    qf_types[val.type] or val.type, vim.trim(val.text))
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

    cmd(('au BqfFilterFzf FileType fzf ++once %s'):format(
        ([[lua require('bqf.filter.fzf').prepare(%d, %s)]]):format(qf_winid, tostring(pid))))

    -- TODO lua can't translate nested table data to vimscript
    local fzf_wrap = fn['fzf#wrap'](opts)
    fzf_wrap['sink*'] = function(ret)
        return handler(qf_winid, ret)
    end
    fn['fzf#run'](fzf_wrap)
end

setup()

return M
