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
---@param bufnr? number
function Sign:place(lnum, bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    if type(lnum) == 'table' then
        local lnumOffsetIndex = 1
        local function place(p_list)
            local ids = fn.sign_placelist(p_list)
            for i = 1, #ids do
                self.items[lnum[lnumOffsetIndex]] = ids[i]
                lnumOffsetIndex = lnumOffsetIndex + 1
            end
        end

        local count, cycle = 0, 100
        local placeList = {}
        for _, l in ipairs(lnum) do
            table.insert(placeList, {
                id = 0,
                group = sgroup,
                name = sname,
                buffer = bufnr,
                lnum = l,
                priority = sprior
            })
            count = count + 1
            if count % cycle == 0 then
                place(placeList)
                count = 0
                placeList = {}
            end
        end
        if count > 0 then
            place(placeList)
        end
    else
        local id = fn.sign_place(0, sgroup, sname, bufnr, {lnum = lnum, priority = sprior})
        self.items[lnum] = id
    end
end

---
---@param lnum number|table<number, number>
---@param bufnr? number
function Sign:unplace(lnum, bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    if type(lnum) == 'table' then
        local count, cycle = 0, 100
        local unplaceList = {}
        for _, l in ipairs(lnum) do
            local id = self.items[l]
            if id then
                table.insert(unplaceList, {id = id, group = sgroup, buffer = bufnr})
                self.items[l] = nil
                count = count + 1
                if count % cycle == 0 then
                    fn.sign_unplacelist(unplaceList)
                    count = 0
                    unplaceList = {}
                end
            end
        end
        if count > 0 then
            fn.sign_unplacelist(unplaceList)
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
---@param lnum number|number[]
---@param bufnr? number
function Sign:toggle(lnum, bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    if type(lnum) == 'table' then
        local placeLnumList, uplaceLnumList = {}, {}
        for _, l in pairs(lnum) do
            if self.items[l] then
                table.insert(uplaceLnumList, l)
            else
                table.insert(placeLnumList, l)
            end
        end
        self:place(placeLnumList, bufnr)
        self:unplace(uplaceLnumList, bufnr)
    else
        if self.items[lnum] then
            self:unplace(lnum, bufnr)
        else
            self:place(lnum, bufnr)
        end
    end
end

---
---@param bufnr? number
function Sign:reset(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()
    local placeLnumList = {}
    local signs = self.items
    self:clear(bufnr)
    for lnum in pairs(signs) do
        table.insert(placeLnumList, lnum)
    end
    self:place(placeLnumList, bufnr)
end

---
---@param bufnr? number
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
