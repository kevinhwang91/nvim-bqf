local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd
local uv = vim.loop

local preview, jump, supply, qftool, base, config, sign
local utils = require('bqf.utils')
local log = require('bqf.log')

local action_for, extra_opts, has_tail, is_windows
local headless

local function setup()
    if #api.nvim_list_uis() == 0 then
        headless = {}
        return
    end
    assert(vim.g.loaded_fzf or fn.exists('*fzf#run') == 1,
        'fzf#run function not found. You also need Vim plugin from the main fzf repository')

    preview = require('bqf.preview')
    jump = require('bqf.jump')
    supply = require('bqf.supply')
    qftool = require('bqf.qftool')
    base = require('bqf.filter.base')
    config = require('bqf.config')
    sign = require('bqf.sign')

    local fzf_conf = config.filter.fzf
    action_for, extra_opts = fzf_conf.action_for, fzf_conf.extra_opts
    vim.validate({action_for = {action_for, 'table'}, extra_opts = {extra_opts, 'table'}})
    has_tail = fn.executable('tail') == 1
    is_windows = uv.os_uname().sysname == 'Windows_NT'

    if not has_tail then
        -- also need echo :)
        api.nvim_err_writeln([[preview need 'tail' command]])
    end

    cmd([[
        aug BqfFilterFzf
            au!
        aug END
    ]])
end

local function export4headless(bufnr, signs, fname)
    local fd = assert(io.open(fname, 'w'))
    for i, line in pairs(api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
        fd:write(('%c %s\n'):format(signs[i] and 0 or 32, line))
    end
    fd:close()
end

local function source_list(qf_winid, signs)
    local ret = {}
    local function hl_ansi(name, str)
        if not name then
            return ''
        end
        return headless and headless.hl_ansi[name:upper()] or utils.render_str(str or '%s', name)
    end

    local hl_id2ansi = setmetatable({}, {
        __index = function(tbl, id)
            local name = fn.synIDattr(id, 'name')
            local ansi_code = hl_ansi(name)
            rawset(tbl, id, ansi_code)
            return ansi_code
        end
    })

    local bufnr = qf_winid and api.nvim_win_get_buf(qf_winid) or 0
    local padding = (' '):rep(headless and headless.padding_nr or utils.gutter_size(qf_winid) - 4)
    local sign_ansi = hl_ansi('BqfSign', '^')
    local line_fmt = headless and '%d\t%s%s %s\n' or '%d\t%s%s %s'

    local is_keyword = utils.gen_is_keyword(bufnr)

    local start = headless and 3 or 1
    for i, line in pairs(api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
        local signed = ' '
        if headless then
            if line:byte() == 0 then
                signed = sign_ansi
            end
        else
            if signs[i] then
                signed = sign_ansi
            end
        end
        local line_sect = {}
        local last_hl_id = -1
        local last_is_kw = false
        local last_col = start
        local j = start
        while j <= #line do
            local byte = line:byte(j)
            local is_kw = is_keyword(byte)
            if last_is_kw == false or is_kw ~= last_is_kw then
                if utils.is_special(byte) then
                    last_is_kw = false
                else
                    local hl_id = fn.synID(i, j, true)
                    if j > start and hl_id ~= last_hl_id then
                        table.insert(line_sect,
                            hl_id2ansi[last_hl_id]:format(line:sub(last_col, j - 1)))
                        last_col = j
                    end
                    last_hl_id, last_is_kw = hl_id, is_kw
                end
            end
            j = j + 1
        end
        local hl_fmt = last_hl_id and hl_id2ansi[last_hl_id] or '%s'
        table.insert(line_sect, hl_fmt:format(line:sub(last_col, #line):gsub('%c*$', '')))
        local processed_line = line_fmt:format(i, padding, signed, table.concat(line_sect, ''))
        if headless then
            io.write(processed_line)
        else
            table.insert(ret, processed_line)
        end
    end
    return ret
end

local function source_cmd(qf_winid, signs)
    local fname = fn.fnameescape(fn.tempname())
    local bufnr = api.nvim_win_get_buf(qf_winid)
    export4headless(bufnr, signs, fname)
    local cmds = {vim.v.progpath, '--clean -n --headless'}
    local function append_cmd(str)
        table.insert(cmds, '-c')
        table.insert(cmds, ('%q'):format(str))
    end
    append_cmd(('e ++enc=utf8 %s'):format(fname))

    local ansi_tbl = {['BqfSign'] = utils.render_str('^', 'BqfSign')}
    for _, name in ipairs(utils.syntax_list(bufnr)) do
        name = name:upper()
        ansi_tbl[name] = utils.render_str('%s', name)
    end
    for _, path in ipairs(api.nvim_get_runtime_file('syntax/qf.vim', true)) do
        append_cmd(('sil! so %s'):format(fn.fnameescape(path)))
    end
    local bqf_path = vim.tbl_filter(function(p)
        return p:match('nvim%-bqf$')
    end, api.nvim_list_runtime_paths())[1]
    assert(bqf_path, [[can't find nvim-bqf's runtime path]])
    append_cmd(('set rtp+=%s'):format(fn.fnameescape(bqf_path)))

    if not log.is_enabled('debug') then
        append_cmd(([[sil! call delete('%s')]]):format(fname))
    else
        append_cmd([[sil! lua require('bqf.log').set_level('debug')]])
    end
    append_cmd(([[sil! lua require('bqf.filter.fzf').headless_run(%s, %d)]]):format(
        vim.inspect(ansi_tbl), utils.gutter_size(qf_winid) - 4))
    append_cmd('q!')
    local c_out = table.concat(cmds, ' ')

    log.debug('tmp_fname:', fname)
    log.debug('cmd_out:', c_out)
    return c_out
end

local function set_qf_cursor(winid, lnum)
    local col = api.nvim_win_get_cursor(winid)[2]
    api.nvim_win_set_cursor(winid, {lnum, col})
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
            set_qf_cursor(qf_winid, idx)
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
            sign.toggle(0, i, api.nvim_win_get_buf(qf_winid))
        end
        set_qf_cursor(qf_winid, selected_index[1])
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
        if data and data ~= '' then
            local tbl_data = vim.split(data, ',')
            local idx
            while #tbl_data > 0 and not idx do
                idx = tonumber(table.remove(tbl_data))
            end
            if idx and idx > 0 then
                vim.schedule(function()
                    set_qf_cursor(qf_winid, idx)
                    preview.open(qf_winid, idx)
                end)
            end
        end
    end)
    return pid
end

function M.headless_run(hl_ansi, padding_nr)
    log.debug('hl_ansi:', hl_ansi)
    log.debug('padding_nr:', padding_nr)
    log.debug(headless)
    if headless then
        headless.hl_ansi, headless.padding_nr = hl_ansi, padding_nr
        source_list()
    end
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
    -- greater than 1000 items is worth using headless as stream to improve user experience
    -- look like widnows can't spawn process :(
    local source = #items > 1000 and not is_windows and source_cmd or source_list
    local expect_keys = table.concat(vim.tbl_keys(action_for), ',')
    local opts = {
        source = source(qf_winid, signs),
        ['sink*'] = nil,
        options = supply.tbl_concat({
            '--multi', '--ansi', '--tabstop', vim.bo.ts, '--with-nth', '2..', '--delimiter', '\t',
            '--header-lines', 0, '--tiebreak', 'index', '--info', 'inline', '--prompt', prompt,
            '--no-border', '--layout', 'reverse-list', '--expect', expect_keys
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
