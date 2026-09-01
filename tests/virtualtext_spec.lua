local helpers = require 'tests.helpers'

-- Drives a real request through the autocommand path: the config is set up,
-- a stub backend serves the suggestion, and typing one character runs the
-- same schedule/trigger chain as a keystroke.
local function with_display_scenario(overrides, backend, scenario)
    helpers.setup_root_config(vim.tbl_deep_extend('force', {
        provider = 'test_display',
        debounce = 0,
        throttle = 0,
        show_on_completion_menu = true,
    }, overrides or {}))

    package.loaded['harmonize.backends.test_display'] = backend

    local virtualtext = helpers.reload 'harmonize.virtualtext'
    virtualtext.setup()

    local bufnr = helpers.create_buffer({ 'local value =' }, { 1, 13 })
    vim.b.harmonize_virtual_text_auto_trigger = true

    local original_mode = vim.fn.mode
    vim.fn.mode = function()
        return 'i'
    end

    local ok, err = xpcall(scenario, debug.traceback, bufnr, virtualtext)

    vim.fn.mode = original_mode
    helpers.delete_buffer(bufnr)
    if not ok then
        error(err, 0)
    end
end

local function type_char(bufnr)
    vim.api.nvim_buf_set_text(bufnr, 0, 12, 0, 12, { 'x' })
    vim.api.nvim_exec_autocmds('TextChangedI', { buffer = bufnr })
end

local function extmark_details(virtualtext, bufnr)
    local mark = vim.api.nvim_buf_get_extmark_by_id(bufnr, virtualtext.ns_id, 1, { details = true })
    return mark[3]
end

return {
    {
        name = 'line display shows only one line below the cursor',
        run = function()
            with_display_scenario({
                display = 'line',
            }, {
                complete = function(_, callback, on_update)
                    on_update '\nfirst line\nsecond line\nthird line'
                    callback { '\nfirst line\nsecond line\nthird line' }
                end,
            }, function(bufnr, virtualtext)
                type_char(bufnr)
                helpers.wait_until(function()
                    return extmark_details(virtualtext, bufnr) ~= nil
                end, 1000, 'the suggestion must be shown')

                local details = extmark_details(virtualtext, bufnr)
                helpers.expect_equal(details.virt_text[1][1], '')
                helpers.expect_equal(#details.virt_lines, 1)
                helpers.expect_equal(details.virt_lines[1][1][1], 'first line')
            end)
        end,
    },
    {
        name = 'chunk display shows exactly what the next accept completes',
        run = function()
            with_display_scenario({
                display = 'chunk',
            }, {
                complete = function(_, callback, on_update)
                    on_update 'foo(bar)\nbaz'
                    callback { 'foo(bar)\nbaz' }
                end,
            }, function(bufnr, virtualtext)
                type_char(bufnr)
                helpers.wait_until(function()
                    return extmark_details(virtualtext, bufnr) ~= nil
                end, 1000, 'the suggestion must be shown')

                local details = extmark_details(virtualtext, bufnr)
                -- 'foo(' is the whole first chunk: the identifier plus the
                -- special characters that follow it.
                helpers.expect_equal(details.virt_text[1][1], 'foo(')
                helpers.expect_falsy(details.virt_lines)
            end)
        end,
    },
    {
        name = 'streamed snapshots replace the ghost instead of repeating prefixes',
        run = function()
            with_display_scenario(nil, {
                complete = function(_, callback, on_update)
                    on_update 'foo'
                    on_update 'foobar'
                    callback { 'foobar' }
                end,
            }, function(bufnr, virtualtext)
                type_char(bufnr)
                helpers.wait_until(function()
                    return extmark_details(virtualtext, bufnr) ~= nil
                end, 1000, 'the suggestion must be shown')

                local details = extmark_details(virtualtext, bufnr)
                helpers.expect_equal(details.virt_text[1][1], 'foobar')
            end)
        end,
    },
}