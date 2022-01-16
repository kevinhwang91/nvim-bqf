local utils = require('bqf.utils')

local Win = {}

function Win:new(winid)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    obj.winid = winid
    obj.height = nil
    obj.hrtime = nil
    obj.pos = nil
    obj.tune_lnum = nil
    obj.wv = nil
    return obj
end

function Win:set(o)
    self.height = o.height
    self.hrtime = o.hrtime
    self.pos = o.pos
    self.tune_lnum = o.tune_lnum
    self.wv = o.wv
end

local MagicWinSession = {pool = {}}

function MagicWinSession.get(qbufnr)
    if not MagicWinSession.pool[qbufnr] then
        MagicWinSession.pool[qbufnr] = setmetatable({}, {
            __index = function(tbl, winid)
                rawset(tbl, winid, Win:new(winid))
                return tbl[winid]
            end
        })
    end
    return MagicWinSession.pool[qbufnr]
end

function MagicWinSession.adjacent_win(qbufnr, winid)
    return MagicWinSession.get(qbufnr)[winid]
end

function MagicWinSession.pairs(qbufnr)
    return pairs(MagicWinSession.get(qbufnr))
end

function MagicWinSession.clean(qbufnr)
    for bufnr in pairs(MagicWinSession.pool) do
        if not utils.is_buf_loaded(bufnr) then
            MagicWinSession.pool[bufnr] = nil
        end
    end
    if qbufnr then
        MagicWinSession.pool[qbufnr] = nil
    end
end

return MagicWinSession
