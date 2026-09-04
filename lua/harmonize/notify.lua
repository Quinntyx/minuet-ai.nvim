--- Notification helper with a configurable minimum level.
local M = {
    level = 'warn',
}

local levels = {
    debug = 0,
    verbose = 1,
    warn = 2,
    error = 3,
}

---@param level string|false minimum level that reaches vim.notify, or false to stay quiet
function M.set_level(level)
    if level == false then
        M.level = nil
    else
        M.level = level or 'warn'
    end
end

---@param msg string
---@param harmonize_level string one of 'debug', 'verbose', 'warn', 'error'
---@param vim_level integer vim.log.levels value
function M.notify(msg, harmonize_level, vim_level)
    if not M.level then
        return
    end
    if levels[harmonize_level] >= levels[M.level] then
        vim.notify(msg, vim_level)
    end
end

return M