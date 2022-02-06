---@class BqfPreviewTreesitter
local M = {}

local api = vim.api

local parsers, configs
local parsers_cache
local parsers_limit
local lru
local initialized

local function prepare_context(parser, pbufnr, fbufnr, loaded)
    local cb
    if loaded then
        parser._source = fbufnr
        cb = parser._callbacks
        parser._callbacks = vim.deepcopy(cb)
    end

    local hl_config = configs.get_module('highlight')
    for k, v in pairs(hl_config.custom_captures) do
        vim.treesitter.highlighter.hl_map[k] = v
    end
    local lang = parser:lang()

    vim.treesitter.highlighter.new(parser)

    if loaded then
        parser._source = pbufnr
        parser._callbacks = cb
    end
    local is_table = type(hl_config.additional_vim_regex_highlighting) == 'table'
    if hl_config.additional_vim_regex_highlighting and
        (not is_table or vim.tbl_contains(hl_config.additional_vim_regex_highlighting, lang)) then
        vim.bo[pbufnr].syntax = 'on'
    end
end

---
---@param bufnr number
function M.disable_active(bufnr)
    if not initialized then
        return
    end
    if vim.treesitter.highlighter.active[bufnr] then
        vim.treesitter.highlighter.active[bufnr] = nil
    end
end

---
---@param pbufnr number
---@param fbufnr number
---@return boolean
function M.try_attach(pbufnr, fbufnr)
    local ret = false
    if not initialized then
        return ret
    end
    local loaded = api.nvim_buf_is_loaded(pbufnr)
    local parser
    if loaded then
        parser = parsers.get_parser(pbufnr)
    else
        parser = parsers_cache:get(pbufnr)
        if parser then
            local sbufnr = parser:source()
            if not api.nvim_buf_is_valid(sbufnr) then
                parser = nil
                parsers_cache:set(pbufnr, nil)
            end
        end
    end
    if parser and configs.is_enabled('highlight', parser:lang()) then
        prepare_context(parser, pbufnr, fbufnr, loaded)
        ret = true
    end
    return ret
end

---
---@param pbufnr number
---@param fbufnr number
---@param ft string
---@return boolean
function M.attach(pbufnr, fbufnr, ft)
    local ret = false
    if not initialized then
        return ret
    end
    local lang = parsers.ft_to_lang(ft)
    if not configs.is_enabled('highlight', lang) then
        return ret
    end

    local parser
    local loaded = api.nvim_buf_is_loaded(pbufnr)

    parser = parsers_cache:get(pbufnr)
    if loaded then
        if parser then
            -- delete old cache if buffer has loaded
            parsers_cache:set(pbufnr, nil)
        end
        parser = parsers.get_parser(pbufnr, lang)
    else
        parser = parsers.get_parser(fbufnr, lang)
        parsers_cache:set(pbufnr, parser)
    end
    if parser then
        prepare_context(parser, pbufnr, fbufnr, loaded)
        ret = true
    end
    return ret
end

function M.shrink_cache()
    if not initialized then
        return
    end

    -- shrink cache, keep usage of memory proper
    local cnt = parsers_limit / 4
    for bufnr in parsers_cache:pairs() do
        if api.nvim_buf_is_loaded(bufnr) or not api.nvim_buf_is_valid(bufnr) or cnt < 1 then
            parsers_cache:set(bufnr, nil)
        else
            cnt = cnt - 1
        end
    end
end

local function init()
    initialized, parsers = pcall(require, 'nvim-treesitter.parsers')
    if not initialized then
        return
    end
    initialized = true
    configs = require('nvim-treesitter.configs')
    lru = require('bqf.struct.lru')

    parsers_limit = 48
    parsers_cache = lru:new(parsers_limit)
end

init()

return M
