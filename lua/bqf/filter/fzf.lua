--- Singleton
---@class BqfFzfFilter
local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd
local uv = vim.loop

local phandler, qhandler, base, config, qfs
local utils = require('bqf.utils')
local log = require('bqf.log')

local action_for, extra_opts, is_windows
local ctx_action_for
local version
local headless

local function get_version()
    local exe = fn['fzf#exec']()
    local msg_tbl = fn.systemlist({exe, '--version'})
    local sh_error = vim.v.shell_error
    local ver
    if sh_error == 0 and type(msg_tbl) == 'table' and #msg_tbl > 0 then
        ver = msg_tbl[1]:match('[0-9.]+')
    else
        ver = ''
    end
    return ver
end

local function filter_actions(actions)
    for key, action in pairs(actions) do
        if type(action) ~= 'string' or action:match('^%s*$') then
            actions[key] = nil
        end
    end
end

local function compare_version(a, b)
    local asecs = vim.split(a, '%.')
    local bsecs = vim.split(b, '%.')
    for i = 1, math.max(#asecs, #bsecs) do
        local n1 = tonumber(asecs[i]) or -1
        local n2 = tonumber(bsecs[i]) or -1
        if n1 < n2 then
            return -1
        elseif n1 > n2 then
            return 1
        end
    end
    return 0
end

local function export4headless(bufnr, signs, fname)
    local fname_data = fname .. '_data'
    local fname_sign = fname .. '_sign'
    local fd_data = assert(io.open(fname_data, 'w'))
    local fd_sign = assert(io.open(fname_sign, 'w'))
    for i, line in pairs(api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
        fd_data:write(('%s\n'):format(line))
        fd_sign:write(('%c'):format(signs[i] and 0 or 32))
    end
    fd_data:close()
    fd_sign:close()
    return fname_data, fname_sign
end

local function source_list(qwinid, signs, delim)
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

    local bufnr = qwinid and api.nvim_win_get_buf(qwinid) or 0
    local padding = (' '):rep(headless and headless.padding_nr or utils.textoff(qwinid) - 4)
    local sign_ansi = hl_ansi('BqfSign', '^')
    local line_fmt = headless and '%d' .. delim .. '%s%s %s\n' or '%d' .. delim .. '%s%s %s'
    if not signs then
        local headless_sign_bufnr = fn.bufnr('#')
        signs = api.nvim_buf_get_lines(headless_sign_bufnr, 0, 1, false)[1]
    end

    local is_keyword = utils.gen_is_keyword(bufnr)

    local ts = vim.bo[bufnr].ts
    qwinid = qwinid and qwinid or 0
    local conceal_enabled = vim.wo[qwinid].conceallevel > 0
    local conceal_hl_id
    if conceal_enabled then
        conceal_hl_id = fn.hlID('conceal')
    end

    for i, line in pairs(api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
        local signed = ' '
        if headless then
            if signs:byte(i) == 0 then
                signed = sign_ansi
            end
            line = utils.expandtab(line, ts, 3)
        else
            if signs[i] then
                signed = sign_ansi
            end
            line = utils.expandtab(line, ts)
        end

        local line_sect = {}
        local last_hl_id = 0
        local last_is_kw = false
        local last_cid = 0
        local last_cchar = ''
        local last_col = 1
        local j = 1
        while j <= #line do
            local byte = line:byte(j)
            local is_kw = is_keyword(byte)
            -- TODO the filter is not good enough
            if last_is_kw and is_kw and (byte >= 97 and byte <= 122 or byte >= 65 and byte <= 90) then
                goto continue
            end

            if byte <= 32 then
                last_is_kw = false
                goto continue
            end

            if conceal_enabled then
                local concealed, cchar, cid = unpack(fn.synconcealed(i, j))
                concealed = concealed == 1
                if last_cid > 0 and cid ~= last_cid then
                    if #last_cchar > 0 then
                        table.insert(line_sect, hl_id2ansi[conceal_hl_id]:format(last_cchar))
                    end
                    last_col = j
                    last_cid = 0
                end

                if concealed then
                    last_cchar, last_cid = cchar, cid
                    goto continue
                end
            end

            do
                -- use do...end to skip `<goto continue> jumps into the scope of local` error
                local hl_id = fn.synID(i, j, true)
                if j > last_col and last_hl_id > 0 and hl_id ~= last_hl_id then
                    table.insert(line_sect, hl_id2ansi[last_hl_id]:format(line:sub(last_col, j - 1)))
                    last_col = j
                end
                last_hl_id, last_is_kw = hl_id, is_kw
            end

            ::continue::
            j = j + 1
        end
        local hl_fmt = last_hl_id > 0 and hl_id2ansi[last_hl_id] or '%s'
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

local function source_cmd(qwinid, signs, delim)
    local tname = fn.tempname()
    local fname = fn.fnameescape(tname)
    local sfname = fn.fnameescape(tname .. '.lua')

    local bufnr = api.nvim_win_get_buf(qwinid)
    local fname_data, fname_sign = export4headless(bufnr, signs, fname)
    -- keep spawn process away from inheriting $NVIM_LISTEN_ADDRESS to call server_init()
    -- look like widnows can't clear env in cmdline
    local no_listen_env = is_windows and '' or 'NVIM_LISTEN_ADDRESS='
    local cmds = {
        no_listen_env, vim.v.progpath, '--clean -n --headless', '-c', ('so %q'):format(sfname)
    }
    local script = {'pcall(vim.cmd, [['}

    local fd = assert(io.open(sfname, 'w'))

    table.insert(script, 'set hidden')
    local fenc = vim.bo[bufnr].fenc
    table.insert(script, ('e %s'):format(fname_sign))
    table.insert(script, ('e ++enc=%s %s'):format(fenc ~= '' and fenc or 'utf8', fname_data))

    local bqf_rtp
    local qf_files = vim.tbl_extend('keep', api.nvim_get_runtime_file('syntax/qf.vim', true),
        api.nvim_get_runtime_file('syntax/qf.lua', true))
    local rtps, sorted_qf_files = {}, {}
    for _, rtp in ipairs(api.nvim_list_runtime_paths()) do
        if not bqf_rtp and rtp:find('nvim-bqf', 1, true) then
            bqf_rtp = rtp
        end

        for _, f in ipairs(qf_files) do
            if f:find(rtp, 1, true) then
                table.insert(rtps, rtp)
                if not vim.tbl_contains(sorted_qf_files, f) then
                    table.insert(sorted_qf_files, f)
                end
                break
            end
        end
    end
    assert(bqf_rtp, [[Can't find nvim-bqf's runtime path]])
    table.insert(rtps, bqf_rtp)

    table.insert(script, ('set rtp+=%s'):format(table.concat(
        vim.tbl_map(function(p)
            return fn.fnameescape(p)
        end, rtps), ',')))

    for _, path in ipairs(sorted_qf_files) do
        table.insert(script, ('so %s'):format(fn.fnameescape(path)))
    end

    local ansi_tbl = {[('BqfSign'):upper()] = utils.render_str('^', 'BqfSign')}
    local conceallevel = vim.wo[qwinid].conceallevel
    if conceallevel > 0 then
        ansi_tbl['CONCEAL'] = utils.render_str('%s', 'Conceal')
    end

    for _, name in ipairs(utils.syntax_list(bufnr)) do
        name = name:upper()
        ansi_tbl[name] = utils.render_str('%s', name)
    end

    table.insert(script, ('set ts=%d'):format(vim.bo[bufnr].ts))
    table.insert(script, ('set conceallevel=%d'):format(conceallevel))

    if not log.is_enabled('debug') then
        table.insert(script, ([[call delete('%s')]]):format(fname_data))
        table.insert(script, ([[call delete('%s')]]):format(fname_sign))
        table.insert(script, ([[call delete('%s')]]):format(sfname))
        table.insert(script, ']])')
    else
        table.insert(script, ']])')
        table.insert(script, [[require('bqf.log').set_level('debug')]])
    end

    table.insert(script, ([[require('bqf.filter.fzf').headless_run(%s, %d, %q)]]):format(
        vim.inspect(ansi_tbl, {newline = ''}), utils.textoff(qwinid) - 4, delim))

    fd:write(table.concat(script, '\n'))
    fd:close()

    local cout = table.concat(cmds, ' ')

    log.debug('cmd_out:', cout)
    return cout
end

local function set_qf_cursor(winid, lnum)
    local col = api.nvim_win_get_cursor(winid)[2]
    api.nvim_win_set_cursor(winid, {lnum, col})
end

local function handler(qwinid, lines)
    local key = table.remove(lines, 1)
    local selected_index = vim.tbl_map(function(e)
        return tonumber(e:match('%d+'))
    end, lines)
    table.sort(selected_index)

    local action = (ctx_action_for or action_for)[key]
    -- default action is nil, don't skip
    if action == '' then
        return
    end

    local qs = qfs:get(qwinid)
    if action == 'signtoggle' then
        local sign = qs:list():sign()
        for _, i in ipairs(selected_index) do
            sign:toggle(i, api.nvim_win_get_buf(qwinid))
        end
        set_qf_cursor(qwinid, selected_index[1])
    elseif action == 'closeall' then
        -- Look fzf have switched back the previous window (qf)
        cmd(('noa call nvim_set_current_win(%d)'):format(qwinid))
        cmd([[
            setlocal stl=%#Normal#
            redrawstatus
            close
        ]])
    elseif #selected_index > 1 then
        local items = qs:list():items()
        base.filter_list(qwinid, coroutine.wrap(function()
            for _, i in ipairs(selected_index) do
                coroutine.yield(i, items[i])
            end
        end))
    elseif #selected_index == 1 then
        local idx = selected_index[1]
        qhandler.open(true, action, qwinid, idx)
    end
end

local function watch_file(qwinid, tmpfile)
    local fd
    if is_windows then
        -- two processes can't write same file meanwhile in Windows :(
        io.open(tmpfile, 'w'):close()
        fd = assert(uv.fs_open(tmpfile, 'r', 438))
    else
        fd = assert(uv.fs_open(tmpfile, 'w+', 438))
    end
    local watch_ev = assert(uv.new_fs_event())
    local function release()
        -- watch_ev:stop and :close have the same effect
        watch_ev:close(function(err)
            assert(not err, err)
        end)
        uv.fs_close(fd, function(err)
            assert(not err, err)
        end)
        os.remove(tmpfile)
    end
    watch_ev:start(tmpfile, {}, function(err, filename, events)
        assert(not err, err)
        local _ = filename
        if events.change then
            uv.fs_read(fd, 4 * 1024, -1, function(err2, data)
                assert(not err2, err2)
                local idx = is_windows and tonumber(data:match('%d+')) or tonumber(data)
                if idx and idx > 0 then
                    vim.schedule(function()
                        set_qf_cursor(qwinid, idx)
                        phandler.open(qwinid, idx)
                    end)
                end
            end)
        else
            release()
        end
    end)
    return release
end

local function parse_delimiter(options)
    local delim
    for i = #options, 1, -1 do
        local o = options[i]
        if o == '-d' or o == '--delimiter' then
            delim = options[i + 1]
            if delim then
                delim = vim.trim(delim)
                if delim == [[\|]] then
                    delim = '|'
                    -- delim = '[\t| │]'
                elseif delim:match('^%[[^%[%]]+%]$') then
                    -- get second char of [chars], Lua can't handle unicode, use Vimscript instead
                    delim = fn.strcharpart(delim, 1, 1)
                end
                break
            end
        end
    end
    return delim or '|'
end

function M.headless_run(hl_ansi, padding_nr, delim)
    log.debug('hl_ansi:', hl_ansi)
    log.debug('padding_nr:', padding_nr)
    log.debug('delim:', delim)
    if headless then
        headless.hl_ansi, headless.padding_nr = hl_ansi, padding_nr
        source_list(nil, nil, delim)
        cmd('q!')
    end
end

function M.pre_handle(qwinid, size)
    local line_count = api.nvim_buf_line_count(0)
    api.nvim_win_set_config(0, {
        relative = 'win',
        win = qwinid,
        width = api.nvim_win_get_width(qwinid),
        height = math.min(api.nvim_win_get_height(qwinid) + 1, line_count + 1),
        row = 0,
        col = 0
    })

    -- keep fzf term away from dithering
    if vim.o.termguicolors then
        local winid = api.nvim_get_current_win()
        local winbl = vim.wo[winid].winbl
        -- https://github.com/neovim/neovim/issues/14670
        cmd('setlocal winbl=100')
        local stl
        local ok, msg = pcall(api.nvim_win_get_option, qwinid, 'stl')
        if ok then
            stl = msg
        end
        vim.wo[qwinid].stl = '%#Normal#'
        vim.defer_fn(function()
            pcall(api.nvim_win_set_option, qwinid, 'stl', stl)
            pcall(api.nvim_win_set_option, winid, 'winbl', winbl)
        end, size > 1000 and 100 or 50)
    end

    if M.post_handle then
        cmd([[
            aug BqfFilterFzf')
                au BufWipeout <buffer> lua require('bqf.filter.fzf').post_handle()
            aug END
        ]])
    end
end

function M.run()
    local qwinid = api.nvim_get_current_win()
    local qlist = qfs:get(qwinid):list()
    local prompt = qlist.type == 'loc' and ' Location> ' or ' Quickfix> '
    local size = qlist:get_qflist({size = 0}).size
    if size < 2 then
        return
    end
    -- greater than 1000 items is worth using headless as stream to improve user experience
    local source = size > 1000 and source_cmd or source_list

    local base_opt = {}
    if compare_version(version, '0.25.0') >= 0 then
        table.insert(base_opt, '--color')
        table.insert(base_opt, 'gutter:-1')
    end
    if compare_version(version, '0.27.4') >= 0 then
        table.insert(base_opt, '--scroll-off')
        table.insert(base_opt, utils.scrolloff(qwinid))
    end

    -- TODO
    -- ctx.fzf_extra_opts and ctx.fzf_action_for are used by myself, I'm not sure who wants them.
    local ctx = qlist:context().bqf or {}
    ctx_action_for = nil
    if type(ctx.fzf_action_for) == 'table' then
        ctx_action_for = vim.tbl_extend('keep', ctx.fzf_action_for, action_for)
        filter_actions(ctx_action_for)
    end
    local expect_keys = table.concat(vim.tbl_keys(ctx_action_for or action_for), ',')
    vim.list_extend(base_opt, {
        '--multi', '--ansi', '--delimiter', [[\|]], '--with-nth', '2..', '--nth', '3..,1,2',
        '--header-lines', 0, '--tiebreak', 'index', '--info', 'inline', '--prompt', prompt,
        '--no-border', '--layout', 'reverse-list', '--expect', expect_keys
    })
    local options = vim.list_extend(base_opt, ctx.fzf_extra_opts or extra_opts)
    local delimiter = parse_delimiter(options)
    local opts = {
        options = options,
        source = source(qwinid, qlist:sign():list(), delimiter),
        ['sink*'] = function(lines)
            return handler(qwinid, lines)
        end,
        window = {
            width = api.nvim_win_get_width(qwinid),
            height = api.nvim_win_get_height(qwinid) + 1,
            xoffset = 0,
            yoffset = 0,
            border = 'none'
        }
    }

    if phandler.auto_enabled() then
        local tmpfile = fn.tempname()
        vim.list_extend(opts.options,
            {'--preview-window', 0, '--preview', 'echo {1} >> ' .. tmpfile})
        local release_cb = watch_file(qwinid, tmpfile)
        M.post_handle = function()
            release_cb()
            M.post_handle = nil
        end
        phandler.keep_preview()
    end

    cmd(('au BqfFilterFzf FileType fzf ++once %s'):format(
        ([[lua require('bqf.filter.fzf').pre_handle(%d, %d)]]):format(qwinid, size)))

    fn.BqfFzfWrapper(opts)
end

local function init()
    if #api.nvim_list_uis() == 0 then
        headless = {}
        return
    end
    assert(vim.g.loaded_fzf or fn.exists('*fzf#run') == 1,
        'fzf#run function not found. You also need Vim plugin from the main fzf repository')
    version = get_version()

    config = require('bqf.config')

    local fzf_conf = config.filter.fzf
    action_for, extra_opts = fzf_conf.action_for, fzf_conf.extra_opts
    vim.validate({
        action_for = {action_for, 'table'},
        extra_opts = {extra_opts, 'table'},
        version = {version, 'string', 'version string'}
    })

    filter_actions(action_for)

    phandler = require('bqf.preview.handler')
    qhandler = require('bqf.qfwin.handler')
    base = require('bqf.filter.base')
    qfs = require('bqf.qfwin.session')
    is_windows = utils.is_windows()

    cmd([[
        aug BqfFilterFzf
            au!
        aug END

        function! BqfFzfWrapper(opts) abort
            call fzf#run(fzf#wrap(a:opts))
        endfunction
    ]])
end

init()

return M
