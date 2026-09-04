local helpers = require 'tests.helpers'

return {
    {
        name = 'a preset keeps shared config references current and rebuilds config-bound components',
        run = function()
            local app = helpers.new_app {
                keymap = { trigger = '<M-z>' },
                debounce = 20,
                display = 'line',
                presets = {
                    fast = {
                        keymap = { trigger = '<M-x>' },
                        debounce = 5,
                        display = 'chunk',
                        context_sources = {
                            treesitter = { enabled = false },
                        },
                    },
                },
            }
            local config = app.config
            local old_context = app.context

            local ok, err = xpcall(function()
                app:start()
                app:start()
                helpers.expect_equal(#app.bindings.bound_keys, 1, 'start must be idempotent')

                app:change_preset 'fast'

                helpers.expect_truthy(app.config == config, 'the app must preserve config table identity')
                helpers.expect_truthy(app.deps.config == config)
                helpers.expect_truthy(app.controller.config == config)
                helpers.expect_truthy(app.view.config == config)
                helpers.expect_truthy(app.bindings.config == config)
                helpers.expect_truthy(app.deps.transport.config == config)
                helpers.expect_equal(config.debounce, 5)
                helpers.expect_equal(config.display, 'chunk')

                helpers.expect_truthy(app.context ~= old_context, 'the context object must be rebuilt')
                helpers.expect_truthy(app.controller.context == app.context)
                helpers.expect_equal(app.context.options.treesitter.enabled, false)

                helpers.expect_equal(vim.fn.maparg('<M-z>', 'i'), '', 'the old preset keymap must be removed')
                helpers.expect_truthy(vim.fn.maparg('<M-x>', 'i') ~= '', 'the new preset keymap must be installed')
            end, debug.traceback)

            app:close()
            if not ok then
                error(err, 0)
            end
        end,
    },
}
