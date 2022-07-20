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

local actionFor, extraOpts, isWindows
local ctxActionFor
local version
local headless

local function getVersion()
    local exe = fn['fzf#exec']()
    local msgTbl = fn.systemlist({exe, '--version'})
    local shError = vim.v.shell_error
    local ver
    if shError == 0 and type(msgTbl) == 'table' and #msgTbl > 0 then
        ver = msgTbl[1]:match('[0-9.]+')
    else
        ver = ''
    end
    return ver
end

local function filterActions(actions)
    for key, action in pairs(actions) do
        if type(action) ~= 'string' or action:match('^%s*$') then
            actions[key] = nil
        end
    end
end

local function compareVersion(a, b)
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
    local fnameData = fname .. '_data'
    local fnameSign = fname .. '_sign'
    local fdData = assert(io.open(fnameData, 'w'))
    local fdSign = assert(io.open(fnameSign, 'w'))
    for i, line in ipairs(api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
        fdData:write(('%s\n'):format(line))
        fdSign:write(('%c'):format(signs[i] and 0 or 32))
    end
    fdData:close()
    fdSign:close()
    return fnameData, fnameSign
end

local function sourceList(qwinid, signs, delim)
    local ret = {}
    ---
    ---@param name string
    ---@param str? string
    ---@return string
    local function hlAnsi(name, str)
        if not name then
            return ''
        end
        return headless and headless.hlAnsi[name:upper()] or utils.renderStr(str or '%s', name)
    end

    local hlIdToAnsi = setmetatable({}, {
        __index = function(tbl, id)
            local name = fn.synIDattr(id, 'name')
            local ansiCode = hlAnsi(name)
            rawset(tbl, id, ansiCode)
            return ansiCode
        end
    })

    local bufnr = qwinid and api.nvim_win_get_buf(qwinid) or 0
    local padding = (' '):rep(headless and headless.paddingNr or utils.textoff(qwinid) - 4)
    local signAnsi = hlAnsi('BqfSign', '^')
    local lineFmt = headless and '%d' .. delim .. '%s%s %s\n' or '%d' .. delim .. '%s%s %s'
    if not signs then
        local headlessSignBufnr = fn.bufnr('#')
        signs = api.nvim_buf_get_lines(headlessSignBufnr, 0, 1, false)[1]
    end

    local isKeyword = utils.genIsKeyword(bufnr)

    local ts = vim.bo[bufnr].ts
    qwinid = qwinid and qwinid or 0
    local concealEnabled = vim.wo[qwinid].conceallevel > 0
    local concealHlId
    if concealEnabled then
        concealHlId = fn.hlID('conceal')
    end

    for i, line in ipairs(api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
        local signed = ' '
        if headless then
            if signs:byte(i) == 0 then
                signed = signAnsi
            end
            line = utils.expandtab(line, ts, 3)
        else
            if signs[i] then
                signed = signAnsi
            end
            line = utils.expandtab(line, ts)
        end

        local lineSect = {}
        local lastHlId = 0
        local lastIsKw = false
        local lastCid = 0
        local lastCchar = ''
        local lastCol = 1
        local j = 1
        while j <= #line do
            local byte = line:byte(j)
            local isKw = isKeyword(byte)
            -- TODO the filter is not good enough
            if lastIsKw and isKw and (byte >= 97 and byte <= 122 or byte >= 65 and byte <= 90) then
                local _ = nil
            elseif byte <= 32 then
                lastIsKw = false
            else
                local concealed = false
                if concealEnabled then
                    local concealed0, cchar, cid = unpack(fn.synconcealed(i, j))
                    concealed = concealed0 == 1
                    if lastCid > 0 and cid ~= lastCid then
                        if #lastCchar > 0 then
                            table.insert(lineSect, hlIdToAnsi[concealHlId]:format(lastCchar))
                        end
                        lastCol = j
                        lastCid = 0
                    end
                    if concealed then
                        lastCchar, lastCid = cchar, cid
                    end
                end
                if not concealed then
                    local hlId = fn.synID(i, j, true)
                    if j > lastCol and hlId > 0 and hlId ~= lastHlId then
                        table.insert(lineSect, hlIdToAnsi[lastHlId]:format(line:sub(lastCol, j - 1)))
                        lastCol = j
                    end
                    lastHlId, lastIsKw = hlId, isKw
                end
            end
            j = j + 1
        end
        local hlFmt = lastHlId > 0 and hlIdToAnsi[lastHlId] or '%s'
        table.insert(lineSect, hlFmt:format(line:sub(lastCol, #line):gsub('%c*$', '')))
        local processedLine = lineFmt:format(i, padding, signed, table.concat(lineSect, ''))
        if headless then
            io.write(processedLine)
        else
            table.insert(ret, processedLine)
        end
    end
    return ret
end

local function sourceCmd(qwinid, signs, delim)
    local tname = fn.tempname()
    local fname = fn.fnameescape(tname)
    local sfname = fn.fnameescape(tname .. '.lua')

    local bufnr = api.nvim_win_get_buf(qwinid)
    local fnameData, fnameSign = export4headless(bufnr, signs, fname)
    -- keep spawn process away from inheriting $NVIM_LISTEN_ADDRESS to call server_init()
    -- look like widnows can't clear env in cmdline
    local noListenEnv = isWindows and '' or 'NVIM_LISTEN_ADDRESS='
    local cmds = {
        noListenEnv, vim.v.progpath, '-u NONE -n --headless', '-c', ('so %q'):format(sfname)
    }
    local script = {'pcall(vim.cmd, [['}

    local fd = assert(io.open(sfname, 'w'))

    table.insert(script, 'set hidden')
    local fenc = vim.bo[bufnr].fenc
    table.insert(script, ('e %s'):format(fnameSign))
    table.insert(script, ('e ++enc=%s %s'):format(fenc ~= '' and fenc or 'utf8', fnameData))
    table.insert(script, ('let w:quickfix_title=%q'):format(utils.getwinvar(qwinid, 'quickfix_title', '')))

    local bqfRtp
    local qfFiles = vim.list_extend(api.nvim_get_runtime_file('syntax/qf.vim', true),
                                    api.nvim_get_runtime_file('syntax/qf.lua', true))
    local rtps, sortedQfFiles = {}, {}
    for _, rtp in ipairs(api.nvim_list_runtime_paths()) do
        if not bqfRtp and rtp:find('nvim-bqf', 1, true) then
            bqfRtp = rtp
        end

        for _, f in ipairs(qfFiles) do
            if f:find(rtp, 1, true) then
                table.insert(rtps, rtp)
                if not vim.tbl_contains(sortedQfFiles, f) then
                    table.insert(sortedQfFiles, f)
                end
                break
            end
        end
    end
    assert(bqfRtp, [[Can't find nvim-bqf's runtime path]])
    table.insert(rtps, bqfRtp)

    table.insert(script, ('set rtp+=%s')
        :format(table.concat(vim.tbl_map(function(p)
            return fn.fnameescape(p)
        end, rtps), ',')))

    for _, path in ipairs(sortedQfFiles) do
        table.insert(script, ('so %s'):format(fn.fnameescape(path)))
    end

    local ansiTbl = {[('BqfSign'):upper()] = utils.renderStr('^', 'BqfSign')}
    local conceallevel = vim.wo[qwinid].conceallevel
    if conceallevel > 0 then
        ansiTbl['CONCEAL'] = utils.renderStr('%s', 'Conceal')
    end

    for _, name in ipairs(utils.syntaxList(bufnr)) do
        name = name:upper()
        ansiTbl[name] = utils.renderStr('%s', name)
    end

    table.insert(script, ('set ts=%d'):format(vim.bo[bufnr].ts))
    table.insert(script, ('set conceallevel=%d'):format(conceallevel))

    if not log.isEnabled('debug') then
        table.insert(script, ([[call delete('%s')]]):format(fnameData))
        table.insert(script, ([[call delete('%s')]]):format(fnameSign))
        table.insert(script, ([[call delete('%s')]]):format(sfname))
        table.insert(script, ']])')
    else
        table.insert(script, ']])')
        table.insert(script, [[require('bqf.log').setLevel('debug')]])
    end

    table.insert(script, ([[require('bqf.filter.fzf').headlessRun(%s, %d, %q)]]):format(
        vim.inspect(ansiTbl, {newline = ''}), utils.textoff(qwinid) - 4, delim))

    fd:write(table.concat(script, '\n'))
    fd:close()

    local cout = table.concat(cmds, ' ')

    log.debug('cmdOut:', cout)
    return cout
end

local function setQfCursor(winid, lnum)
    local col = api.nvim_win_get_cursor(winid)[2]
    api.nvim_win_set_cursor(winid, {lnum, col})
end

local function handler(qwinid, lines)
    local key = table.remove(lines, 1)
    local selectedIndex = vim.tbl_map(function(e)
        return tonumber(e:match('%d+'))
    end, lines)
    table.sort(selectedIndex)

    local action = (ctxActionFor or actionFor)[key]
    -- default action is nil, don't skip
    if action == '' then
        return
    end

    local qs = qfs:get(qwinid)
    if action == 'signtoggle' then
        local sign = qs:list():sign()
        for _, i in ipairs(selectedIndex) do
            sign:toggle(i, api.nvim_win_get_buf(qwinid))
        end
        setQfCursor(qwinid, selectedIndex[1])
    elseif action == 'closeall' then
        -- Look fzf have switched back the previous window (qf)
        cmd(('noa call nvim_set_current_win(%d)'):format(qwinid))
        local ok, stl = pcall(api.nvim_win_get_option, qwinid, 'stl')
        cmd([[
            setlocal stl=%#Normal#
            redrawstatus
        ]])
        if ok then
            cmd(('setlocal stl=%s'):format(stl))
        else
            cmd('setlocal stl<')
        end
        api.nvim_win_close(qwinid, true)
    elseif #selectedIndex > 1 then
        local items = qs:list():items()
        base.filterList(qwinid, coroutine.wrap(function()
            for _, i in ipairs(selectedIndex) do
                coroutine.yield(i, items[i])
            end
        end))
    elseif #selectedIndex == 1 then
        local idx = selectedIndex[1]
        qhandler.open(true, action, qwinid, idx)
    end
end

local function watchFile(qwinid, tmpfile)
    local fd
    if isWindows then
        -- two processes can't write same file meanwhile in Windows :(
        io.open(tmpfile, 'w'):close()
        fd = assert(uv.fs_open(tmpfile, 'r', 438))
    else
        fd = assert(uv.fs_open(tmpfile, 'w+', 438))
    end
    local watchEvent = assert(uv.new_fs_event())
    local function release()
        -- watchEvent:stop and :close have the same effect
        watchEvent:close(function(err)
            assert(not err, err)
        end)
        uv.fs_close(fd, function(err)
            assert(not err, err)
        end)
        os.remove(tmpfile)
    end

    watchEvent:start(tmpfile, {}, function(err, filename, events)
        assert(not err, err)
        local _ = filename
        if events.change then
            uv.fs_read(fd, 4 * 1024, -1, function(err2, data)
                if not phandler.autoEnabled() then
                    return
                end
                assert(not err2, err2)
                local idx = isWindows and tonumber(data:match('%d+')) or tonumber(data)
                if idx and idx > 0 then
                    vim.schedule(function()
                        setQfCursor(qwinid, idx)
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

local function keyToLHS(key)
    local lhs
    if key == 'pgup' then
        lhs = 'pageup'
    elseif key == 'pgdn' then
        lhs = 'pagedown'
    elseif key == 'del' then
        lhs = 'delete'
    else
        lhs = key:gsub('ctrl', 'c'):gsub('alt', 'm'):gsub('shift', 's'):gsub('enter', 'cr'):gsub(
            'bspace', 'bs'):gsub('btab', 's-tab')
    end
    return lhs:match('^.$') and lhs or '<' .. lhs .. '>'
end

local function parseBind(options)
    local binds = {}
    local defaultOptions = vim.env.FZF_DEFAULT_OPTS
    if type(defaultOptions) == 'string' then
        for _, sect in ipairs(vim.split(vim.trim(defaultOptions), '%s*%-%-')) do
            local res = sect:match('bind=?%s*(.+)%s*$')
            if res then
                local first, r, last = res:match('^(.)(.*)(.)$')
                if first == last and (first == [[']] or first == [["]]) then
                    res = r
                end
                table.insert(binds, res)
            end
        end
    end
    for i, o in ipairs(options) do
        if type(o) == 'string' and o:match('%-%-bind') and i < #options then
            table.insert(binds, options[i + 1])
        end
    end
    return table.concat(binds, ','):lower()
end

local function parseDelimiter(options)
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

function M.headlessRun(hlAnsi, paddingNr, delim)
    log.debug('hlAnsi:', hlAnsi)
    log.debug('paddingNr:', paddingNr)
    log.debug('delim:', delim)
    if headless then
        headless.hlAnsi, headless.paddingNr = hlAnsi, paddingNr
        sourceList(nil, nil, delim)
        cmd('q!')
    end
end

function M.preHandle(qwinid, size, bind)
    local lineCount = api.nvim_buf_line_count(0)
    api.nvim_win_set_config(0, {
        relative = 'win',
        win = qwinid,
        width = api.nvim_win_get_width(qwinid),
        height = math.min(api.nvim_win_get_height(qwinid) + 1, lineCount + 1),
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

    local actionFmt = {
        ['preview-half-page-up'] = [[<Cmd>lua require('bqf.preview.handler').scroll(-1, %d)<CR>]],
        ['preview-half-page-down'] = [[<Cmd>lua require('bqf.preview.handler').scroll(1, %d)<CR>]],
        ['toggle-preview'] = [[<Cmd>lua require('bqf.preview.handler').toggle(%d)<CR>]]
    }

    local bufnr = api.nvim_get_current_buf()
    for _, sect in ipairs(vim.split(bind, ',')) do
        local key, action = sect:match('([^:]+):([^:]+)')
        local fmt = actionFmt[action]
        if fmt then
            local lhs = keyToLHS(key)
            local rhs = fmt:format(qwinid)
            api.nvim_buf_set_keymap(bufnr, 't', lhs, rhs, {nowait = true})
        end
    end

    if M.postHandle then
        cmd([[
            aug BqfFilterFzf
                au BufWipeout <buffer> lua require('bqf.filter.fzf').postHandle()
            aug END
        ]])
    end
end

function M.run()
    local qwinid = api.nvim_get_current_win()
    local qlist = qfs:get(qwinid):list()
    local prompt = qlist.type == 'loc' and ' Location> ' or ' Quickfix> '
    local size = qlist:getQfList({size = 0}).size
    if size < 2 then
        return
    end
    -- greater than 1000 items is worth using headless as stream to improve user experience
    local source = size > 1000 and sourceCmd or sourceList

    local baseOpt = {}
    if compareVersion(version, '0.25.0') >= 0 then
        table.insert(baseOpt, '--color')
        table.insert(baseOpt, 'gutter:-1')
    end
    if compareVersion(version, '0.27.4') >= 0 then
        table.insert(baseOpt, '--scroll-off')
        table.insert(baseOpt, utils.scrolloff(qwinid))
    end

    -- TODO
    -- ctx.fzf_extra_opts and ctx.fzf_action_for are used by myself, I'm not sure who wants them.
    local ctx = qlist:context().bqf or {}
    ctxActionFor = nil
    if type(ctx.fzf_action_for) == 'table' then
        ctxActionFor = vim.tbl_extend('keep', ctx.fzf_action_for, actionFor)
        filterActions(ctxActionFor)
    end
    local expectKeys = table.concat(vim.tbl_keys(ctxActionFor or actionFor), ',')
    vim.list_extend(baseOpt, {
        '--multi', '--ansi', '--delimiter', [[\|]], '--with-nth', '2..', '--nth', '3..,1,2',
        '--header-lines', 0, '--tiebreak', 'index', '--info', 'inline', '--prompt', prompt,
        '--no-border', '--layout', 'reverse-list', '--expect', expectKeys
    })
    local options = vim.list_extend(baseOpt, ctx.fzf_extra_opts or extraOpts)
    local delimiter = parseDelimiter(options)
    local bind = parseBind(options)
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

    local tmpfile = fn.tempname()
    vim.list_extend(opts.options, {'--preview-window', 0, '--preview', 'echo {1} >> ' .. tmpfile})
    local releaseCallback = watchFile(qwinid, tmpfile)
    M.postHandle = function()
        releaseCallback()
        M.postHandle = nil
    end
    phandler.keepPreview()

    cmd(('au BqfFilterFzf FileType fzf ++once %s'):format(
        ([[lua require('bqf.filter.fzf').preHandle(%d, %d, %q)]]):format(qwinid, size, bind)))

    fn.BqfFzfWrapper(opts)
end

local function init()
    if #api.nvim_list_uis() == 0 then
        headless = {}
        return
    end
    assert(vim.g.loaded_fzf or fn.exists('*fzf#run') == 1,
           'fzf#run function not found. You also need Vim plugin from the main fzf repository')
    version = getVersion()

    config = require('bqf.config')

    local fzfConf = config.filter.fzf
    actionFor, extraOpts = fzfConf.action_for, fzfConf.extra_opts
    vim.validate({
        action_for = {actionFor, 'table'},
        extra_opts = {extraOpts, 'table'},
        version = {version, 'string', 'version string'}
    })

    filterActions(actionFor)

    phandler = require('bqf.preview.handler')
    qhandler = require('bqf.qfwin.handler')
    base = require('bqf.filter.base')
    qfs = require('bqf.qfwin.session')
    isWindows = utils.isWindows()

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
