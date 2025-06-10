---@class BqfPreviewTreesitter
local M = {}

local api = vim.api

local treesitter = vim.treesitter
local parsersCache
local parsersLimit
local lru

---@param lang string
---@return boolean
local function hasHighlightQuery(lang)
    return treesitter.query.get(lang, "highlights") ~= nil
end

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
    if parser and hasHighlightQuery(parser:lang()) then
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
    local lang = treesitter.language.get_lang(fileType)
    if not hasHighlightQuery(lang) then
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
    lru = require("bqf.struct.lru")

    parsersLimit = 48
    parsersCache = lru:new(parsersLimit)
end

init()

return M
