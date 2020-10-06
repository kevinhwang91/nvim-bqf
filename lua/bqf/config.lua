-- just a public table, reduce startup time and don't want to use any vimscript variables.
-- less than 1 ms is super easy

local user_config
local config = {}
local M = setmetatable(config, {
    __index = function(_, k)
        return user_config[k]
    end
})

function M.set_user_config(u_config)
    user_config = u_config
end

return M
