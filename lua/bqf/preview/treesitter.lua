---@class BqfPreviewTreesitter
local M = {}

local api = vim.api
local treesitter = vim.treesitter

-- Shim function for compatibility
local get_lang
local parsersCache
local parsersLimit
local lru
local initialized

local function injectParserForHighlight(parser, srcBufnr, dstBufnr, loaded)
    if loaded then
        parser._source = dstBufnr
    end

    treesitter.highlighter.new(parser)

    if loaded then
        parser._source = srcBufnr
    end
end

---
---@param bufnr number
function M.disableActive(bufnr)
    if not initialized then
        return
    end
    if treesitter.highlighter.active[bufnr] then
        treesitter.highlighter.active[bufnr] = nil
    end
end

---
---@param srcBufnr number
---@param dstBufnr number
---@param loaded boolean
---@return boolean
function M.tryAttach(srcBufnr, dstBufnr, loaded)
    local ret = false
    if not initialized then
        return ret
    end
    local parser
    if loaded then
        parser = treesitter.get_parser(srcBufnr)
    else
        parser = parsersCache:get(srcBufnr)
        if parser and not api.nvim_buf_is_valid(parser:source()) then
            parser = nil
            parsersCache:set(srcBufnr, nil)
        end
    end
    if parser and treesitter.highlighter.active[srcBufnr] then
        injectParserForHighlight(parser, srcBufnr, dstBufnr, loaded)
        ret = true
    end
    return ret
end

---
---@param srcBufnr number
---@param dstBufnr number
---@param fileType string
---@return boolean
function M.attach(srcBufnr, dstBufnr, fileType)
    local ret = false
    if not initialized then
        return ret
    end
    local lang = get_lang(fileType)
    if not treesitter.highlighter.active[srcBufnr] then
        return ret
    end

    local parser
    local loaded = api.nvim_buf_is_loaded(srcBufnr)

    if loaded then
        -- delete old cache if buffer has loaded
        parsersCache:set(srcBufnr, nil)
        parser = treesitter.get_parser(srcBufnr, lang)
    else
        parser = treesitter.get_parser(dstBufnr, lang)
        -- no need to deepcopy the parser for the cache, upstream only dereference parser and
        -- invalidate it to make self._tree up to date, so we can cache the parser and reuse it
        -- to speed up rendering buffer.
        parsersCache:set(srcBufnr, parser)
    end
    if parser then
        injectParserForHighlight(parser, srcBufnr, dstBufnr, loaded)
        ret = true
    end
    return ret
end

function M.shrinkCache()
    if not initialized then
        return
    end

    -- shrink cache, keep usage of memory proper
    local cnt = parsersLimit / 4
    for bufnr in parsersCache:pairs() do
        if cnt < 1 or api.nvim_buf_is_loaded(bufnr) or not api.nvim_buf_is_valid(bufnr) then
            parsersCache:set(bufnr, nil)
        else
            cnt = cnt - 1
        end
    end
end

local function init()
    local language, parsers
    initialized, language = pcall(require, 'vim.treesitter.language')
    if initialized then
        get_lang = language.get_lang
    else
        initialized, parsers = pcall(require, 'nvim-treesitter.parsers')
        if not initialized then
            return
        end
        get_lang = parsers.ft_to_lang
    end
    lru = require('bqf.struct.lru')

    parsersLimit = 48
    parsersCache = lru:new(parsersLimit)
end

init()

return M
