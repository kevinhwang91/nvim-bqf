local api = vim.api
local fn = vim.fn
local cmd = vim.cmd

local sprior
local sgroup
local sname

---@class QfWinSign
---@field items table<number, number>
local Sign = {}

---
---@return QfWinSign
function Sign:new()
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    obj.items = {}
    return obj
end

---
---@param lnum number|table<number, number>
---@param bufnr number
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

---
---@param lnum number|table<number, number>
---@param bufnr number
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

function Sign:list()
    return self.items
end

---
---@param lnum number|table<number, number>
---@param bufnr number
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

function Sign:reset(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    local p_lnum_list = {}
    local signs = self.items
    self:clear(bufnr)
    for lnum in pairs(signs) do
        table.insert(p_lnum_list, lnum)
    end
    self:place(p_lnum_list, bufnr)
end

function Sign:clear(bufnr)
    self.items = {}
    bufnr = bufnr or api.nvim_get_current_buf()
    fn.sign_unplace(sgroup, {buffer = bufnr})
end

local function init()
    sprior = 20
    sgroup = 'BqfSignGroup'
    sname = 'BqfSign'
    cmd('hi default BqfSign ctermfg=14 guifg=Cyan')
    fn.sign_define('BqfSign', {text = ' ^', texthl = 'BqfSign'})
end

init()

return Sign
