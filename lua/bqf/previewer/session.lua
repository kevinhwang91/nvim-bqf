local api = vim.api
local cmd = vim.cmd

local floatwin = require('bqf.previewer.floatwin')
local border = require('bqf.previewer.border')
local utils = require('bqf.utils')

local PreviewerSession = {pool = {}}

function PreviewerSession:new(winid, o)
    o = o or {}
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    obj.winid = winid
    obj.win_height = o.win_height
    obj.win_vheight = o.win_vheight
    obj.wrap = o.wrap
    obj.border_chars = o.border_chars
    obj.bufnr = nil
    obj.syntax = nil
    obj.full = false
    self.pool[winid] = obj
    return obj
end

function PreviewerSession.get(winid)
    winid = winid or api.nvim_get_current_win()
    return PreviewerSession.pool[winid]
end

function PreviewerSession.clean()
    for w_id in pairs(PreviewerSession.pool) do
        if not utils.is_win_valid(w_id) then
            PreviewerSession.pool[w_id] = nil
        end
    end
end

function PreviewerSession.floatbuf_reset()
    local fwinid = floatwin.winid
    local fbufnr = floatwin.bufnr
    local bbufnr = border.bufnr

    -- 1. make ml_flags empty
    -- 2. treesitter can't clean parser cache until to unload buffer
    -- https://github.com/neovim/neovim/pull/14995
    cmd(('noa call nvim_win_set_buf(%d, %d)'):format(fwinid, bbufnr))
    cmd(('noa bun %d'):format(fbufnr))
    cmd(('noa call nvim_win_set_buf(%d, %d)'):format(fwinid, fbufnr))

end

function PreviewerSession.floatwin_exec(func)
    if PreviewerSession.validate() then
        utils.win_execute(floatwin.winid, func)
    end
end

function PreviewerSession.float_bufnr()
    return floatwin.bufnr
end

function PreviewerSession.border_bufnr()
    return border.bufnr
end

function PreviewerSession.float_winid()
    return floatwin.winid
end

function PreviewerSession.border_winid()
    return border.winid
end

function PreviewerSession.close()
    floatwin:close()
    border:close()
end

function PreviewerSession.validate()
    return floatwin:validate() and border:validate()
end

function PreviewerSession.update_border(pbufnr, qidx, size)
    border:update(pbufnr, qidx, size)
end

function PreviewerSession.update_scrollbar()
    border:update_scrollbar()
end

function PreviewerSession.display()
    floatwin:display()
    border:display()
end

function PreviewerSession:valid_or_build(owinid)
    if not floatwin:validate() then
        floatwin:build({qwinid = self.winid, pwinid = owinid, wrap = self.wrap})
    end
    if not border:validate() then
        border:build({chars = self.border_chars})
    end
    if self.full then
        floatwin.win_height, floatwin.win_vheight = 999, 999
    else
        floatwin.win_height, floatwin.win_vheight = self.win_height, self.win_vheight
    end
end

return PreviewerSession
