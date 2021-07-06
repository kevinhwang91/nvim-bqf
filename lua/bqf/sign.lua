local M = {}
local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local qftool = require('bqf.qftool')
local sign_tbl
local sprior
local sgroup
local sname
local Sign = {}

function Sign:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    o.items = {}
    return o
end

function Sign:place(lnum, bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    if type(lnum) == 'table' then
        local lnum_off_i = 1
        local function place(p_list)
            local ids = fn.sign_placelist(p_list)
            for i = 1, #ids do
                self.items[lnum[lnum_off_i]] = ids[i]
                lnum_off_i = lnum_off_i + 1
            end
        end
        local count, cycle = 0, 100
        local place_list = {}
        for _, l in ipairs(lnum) do
            table.insert(place_list, {
                id = 0,
                group = sgroup,
                name = sname,
                buffer = bufnr,
                lnum = l,
                priority = sprior
            })
            count = count + 1
            if count % cycle == 0 then
                place(place_list)
                count = 0
                place_list = {}
            end
        end
        if count > 0 then
            place(place_list)
        end
    else
        local id = fn.sign_place(0, sgroup, sname, bufnr, {lnum = lnum, priority = sprior})
        self.items[lnum] = id
    end
end

function Sign:unplace(lnum, bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    if type(lnum) == 'table' then
        local count, cycle = 0, 100
        local unplace_list = {}
        for _, l in ipairs(lnum) do
            local id = self.items[l]
            if id then
                table.insert(unplace_list, {id = id, group = sgroup, buffer = bufnr})
                self.items[l] = nil
                count = count + 1
                if count % cycle == 0 then
                    fn.sign_unplacelist(unplace_list)
                    count = 0
                    unplace_list = {}
                end
            end
        end
        if count > 0 then
            fn.sign_unplacelist(unplace_list)
        end
    else
        local id = self.items[lnum]
        if id then
            fn.sign_unplace(sgroup, {buffer = bufnr, id = id})
            self.items[lnum] = nil
        end
    end

end

function Sign:toggle(lnum, bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    if type(lnum) == 'table' then
        local p_lnum_list, up_lnum_list = {}, {}
        for _, l in pairs(lnum) do
            if self.items[l] then
                table.insert(up_lnum_list, l)
            else
                table.insert(p_lnum_list, l)
            end
        end
        self:place(p_lnum_list, bufnr)
        self:unplace(up_lnum_list, bufnr)
    else
        if self.items[lnum] then
            self:unplace(lnum, bufnr)
        else
            self:place(lnum, bufnr)
        end
    end
end

function Sign:clear(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    fn.sign_unplace(sgroup, {buffer = bufnr})
end

local function get_from_pool(qf_id, filewinid)
    if not qf_id or filewinid then
        local qinfo = qftool.get({id = 0, filewinid = 0})
        qf_id, filewinid = qinfo.id, qinfo.filewinid
    end
    return sign_tbl[('%d:%d'):format(qf_id, filewinid or 0)]
end

function M.get()
    return get_from_pool().items
end

function M.clean_pool()
    for id in pairs(sign_tbl) do
        local qf_id, filewinid = unpack(vim.split(id, ':'))
        if not qftool.id_exists(tonumber(qf_id), tonumber(filewinid)) then
            sign_tbl[id] = nil
        end
    end
end

-- debug
function M.get_signs()
    return sign_tbl
end

function M.toggle(rel, lnum, bufnr)
    lnum = lnum or api.nvim_win_get_cursor(0)[1]
    bufnr = bufnr or api.nvim_get_current_buf()
    local sign_obj = get_from_pool()
    sign_obj:toggle(lnum, bufnr)
    if rel ~= 0 then
        cmd(('norm! %s'):format(rel > 0 and 'j' or 'k'))
    end
end

function M.toggle_buf(lnum, bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    lnum = lnum or api.nvim_win_get_cursor(0)[1]
    local items = qftool.items()
    local entry_bufnr = items[lnum].bufnr
    local lnum_list = {}
    for l, entry in ipairs(items) do
        if entry.bufnr == entry_bufnr then
            table.insert(lnum_list, l)
        end
    end
    local sign_obj = get_from_pool()
    sign_obj:toggle(lnum_list, bufnr)
end

-- only work under map with <Cmd>
function M.vm_toggle(bufnr)
    local mode = api.nvim_get_mode().mode
    vim.validate({
        mode = {
            mode, function(m)
                -- ^V = 0x16
                return m:lower() == 'v' or m == ('%c'):format(0x16)
            end, 'visual mode'
        }
    })
    -- ^[ = 0x1b
    fn.execute(('norm! %c'):format(0x1b))
    bufnr = bufnr or api.nvim_get_current_buf()
    local s_lnum = api.nvim_buf_get_mark(bufnr, '<')[1]
    local e_lnum = api.nvim_buf_get_mark(bufnr, '>')[1]
    local lnum_list = {}
    for i = s_lnum, e_lnum do
        table.insert(lnum_list, i)
    end
    local sign_obj = get_from_pool()
    sign_obj:toggle(lnum_list, bufnr)
end

function M.reset(bufnr)
    local sign_obj = get_from_pool()
    local p_lnum_list = {}
    sign_obj:clear()
    for lnum in pairs(sign_obj.items) do
        table.insert(p_lnum_list, lnum)
    end
    sign_obj:place(p_lnum_list, bufnr)
end

function M.clear(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    local sign_obj = get_from_pool()
    sign_obj:clear(bufnr)
    M.clean_pool()
end

local function init()
    sign_tbl = setmetatable({}, {
        __index = function(tbl, id)
            rawset(tbl, id, Sign:new())
            return tbl[id]
        end
    })
    sprior = 20
    sgroup = 'BqfSignGroup'
    sname = 'BqfSign'
    cmd('hi default BqfSign ctermfg=14 guifg=Cyan')
    fn.sign_define('BqfSign', {text = ' ^', texthl = 'BqfSign'})
end

init()

return M
