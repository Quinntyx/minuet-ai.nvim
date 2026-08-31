local base = require 'harmonize.backends.openai_base'
local utils = require 'harmonize.utils'

local M = {}

M.is_available = function()
    local config = require('harmonize').config
    return utils.get_api_key(config.provider_options.openai.api_key) and true or false
end

if not M.is_available() then
    utils.notify('OpenAI API key is not set', 'error', vim.log.levels.ERROR)
end

M.complete = function(context, callback)
    local config = require('harmonize').config
    local options = vim.deepcopy(config.provider_options.openai)
    options.name = 'OpenAI'

    base.complete_openai_base(options, context, callback)
end

return M
