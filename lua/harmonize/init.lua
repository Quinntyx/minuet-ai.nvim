local M = {}

function M.setup(config)
    local default_config = require 'harmonize.config'

    M.presets = config.presets or {}
    M.presets.original = config

    if config.enabled then
        vim.deprecate('harmonize.config.enabled', 'harmonize.config.enable_predicates', 'next release', 'harmonize', false)
        config.enable_predicates = config.enable_predicates or config.enabled
    end

    config.presets = nil

    M.config = vim.tbl_deep_extend('force', default_config, config or {})

    if M.config.quick_start then
        require('harmonize.quickstart').ensure(M.config, M.config.quick_start)
    end
    require('harmonize.virtualtext').setup()
end


local function complete_change_model_options()
    local modelcard = require 'harmonize.modelcard'
    local choices = {}

    -- Build the list of available models
    for provider, models in pairs(modelcard.models) do
        if provider == 'openai_compatible' or provider == 'openai_fim_compatible' then
            -- Handle subproviders for compatible APIs
            local subprovider = M.config.provider_options[provider]
                and string.lower(M.config.provider_options[provider].name)
            if subprovider and models[subprovider] then
                for _, model in ipairs(models[subprovider]) do
                    table.insert(choices, provider .. ':' .. model)
                end
            end
        elseif type(models) == 'table' then
            -- Handle regular providers
            for _, model in ipairs(models) do
                table.insert(choices, provider .. ':' .. model)
            end
        end
    end

    return choices
end

function M.change_model(provider_model)
    if not M.config then
        vim.notify 'Harmonize config is not set up yet, please call the setup function firstly.'
        return
    end

    -- If no provider_model is provided, use vim.ui.select to choose one
    if not provider_model then
        local choices = complete_change_model_options()

        vim.ui.select(choices, {
            prompt = 'Select a model:',
            format_item = function(item)
                return item
            end,
        }, function(choice)
            if choice then
                M.change_model(choice)
            end
        end)
        return
    end

    local provider, model = provider_model:match '([^:]+):(.+)'
    if not provider or not model then
        vim.notify('Invalid format. Use format provider:model (e.g., openai:gpt-4o)', vim.log.levels.ERROR)
        return
    end

    if not M.config.provider_options[provider] then
        vim.notify(
            'The provider is not supported, please refer to harmonize.nvim document for more information.',
            vim.log.levels.ERROR
        )
        return
    end

    M.config.provider = provider
    M.config.provider_options[provider].model = model
    vim.notify(string.format('Harmonize model changed to: %s (%s)', model, provider), vim.log.levels.INFO)
end

function M.change_provider(provider)
    if not M.config then
        vim.notify 'Harmonize config is not set up yet, please call the setup function firstly.'
        return
    end

    if not M.config.provider_options[provider] then
        vim.notify(
            'The provider is not supported, please refer to harmonize.nvim document for more information.',
            vim.log.levels.ERROR
        )
        return
    end

    M.config.provider = provider
    vim.notify('Harmonize Provider changed to: ' .. provider, vim.log.levels.INFO)
end

function M.change_preset(preset)
    if not M.config then
        vim.notify 'Harmonize config is not set up yet, please call the setup function firstly.'
        return
    end

    if not M.presets[preset] then
        vim.notify('The preset is not supported.', vim.log.levels.ERROR)
        return
    end

    local preset_config = M.presets[preset]

    -- deep extend the config with preset_config
    M.config = vim.tbl_deep_extend('force', M.config, preset_config)
    vim.notify('Harmonize Preset changed to: ' .. preset, vim.log.levels.INFO)
end

local function harmonize_complete(arglead, cmdline, _)
    if not M.config then
        vim.notify 'Harmonize config is not set up yet, please call the setup function firstly.'
        return
    end

    local completions = {
        virtualtext = { enable = true, disable = true, toggle = true },
        change_model = complete_change_model_options,
        change_provider = function()
            local providers = {}
            for k, _ in pairs(M.config.provider_options) do
                table.insert(providers, k)
            end
            return providers
        end,
        change_preset = function()
            local presets = {}
            for k, _ in pairs(M.presets) do
                table.insert(presets, k)
            end
            return presets
        end,
    }

    cmdline = cmdline or ''
    local parts = vim.split(vim.trim(cmdline), '%s+')

    ---@type table|function
    local node = completions

    -- The current part may be partial, so keep `node` at the parent level
    -- and filter by prefix.
    local n_fully_typed_parts = #parts
    if arglead ~= '' and #parts > 0 then
        n_fully_typed_parts = n_fully_typed_parts - 1
    end

    for i = 2, n_fully_typed_parts do
        local part = parts[i]
        if type(node) ~= 'table' or node[part] == nil then
            return {}
        end
        node = node[part]
    end

    if type(node) == 'function' then
        return vim.tbl_filter(function(item)
            return vim.startswith(item, arglead)
        end, node())
    elseif type(node) == 'table' then
        return vim.tbl_filter(function(item)
            return vim.startswith(item, arglead)
        end, vim.tbl_keys(node))
    end

    return {}
end

vim.api.nvim_create_user_command('Harmonize', function(args)
    if not M.config then
        vim.notify 'Harmonize config is not set up yet, please call the setup function firstly.'
        return
    end

    local fargs = args.fargs

    local actions = {}


    actions.virtualtext = {
        enable = require('harmonize.virtualtext').action.enable_auto_trigger,
        disable = require('harmonize.virtualtext').action.disable_auto_trigger,
        toggle = require('harmonize.virtualtext').action.toggle_auto_trigger,
    }

    actions.change_provider = setmetatable({}, {
        __index = function(_, key)
            return function()
                M.change_provider(key)
            end
        end,
    })

    local command = fargs[1]

    if command == 'change_model' then
        M.change_model(fargs[2])
    elseif command == 'change_preset' then
        M.change_preset(fargs[2])
    else
        local action_group = actions[command]
        if not action_group then
            vim.notify('Invalid Harmonize command: ' .. tostring(command), vim.log.levels.ERROR)
            return
        end

        -- For commands like `lsp`, the action_group may contain nested
        -- sub-groups (e.g. `lsp completion enable_auto_trigger`).
        -- Walk one level deeper when fargs[2] resolves to a table.
        local action_name = fargs[2]
        if type(action_group[action_name]) == 'table' then
            action_group = action_group[action_name]
            action_name = fargs[3]
        end

        local action_fn = action_group[action_name]
        if not action_fn then
            vim.notify('Harmonize ' .. command .. ' requires a valid action', vim.log.levels.ERROR)
            return
        end

        action_fn()
    end
end, {
    nargs = '+',
    complete = harmonize_complete,
})

return M
