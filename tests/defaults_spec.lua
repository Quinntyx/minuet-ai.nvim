local helpers = require 'tests.helpers'

return {
    {
        name = 'a blank config binds no keys and configures no provider',
        run = function()
            local root = helpers.setup_root_config()
            local c = root.config

            helpers.expect_falsy(c.provider, 'no provider must be configured by default')
            for _, key in ipairs { 'accept', 'accept_line', 'dismiss', 'trigger', 'toggle' } do
                helpers.expect_falsy(c.keymap[key], 'keymap.' .. key .. ' must not be bound by default')
            end
            helpers.expect_equal(c.auto_trigger_ft, {})
        end,
    },
    {
        name = 'triggering without a provider stays quiet instead of erroring',
        run = function()
            helpers.setup_root_config()

            local virtualtext = helpers.reload 'harmonize.virtualtext'
            virtualtext.setup()

            local bufnr = helpers.create_buffer({ 'local value =' }, { 1, 13 })
            local original_mode = vim.fn.mode
            vim.fn.mode = function()
                return 'i'
            end

            local ok, err = xpcall(function()
                virtualtext.action.trigger()
                vim.wait(100)
            end, debug.traceback)

            vim.fn.mode = original_mode
            helpers.delete_buffer(bufnr)
            if not ok then
                error(err, 0)
            end

            helpers.expect_falsy(virtualtext.action.is_visible(), 'no ghost text may appear')
        end,
    },
}
