local helpers = require 'tests.helpers'

local function get_upvalue(fn, wanted)
    local index = 1
    while true do
        local name, value = debug.getupvalue(fn, index)
        if not name then
            error('missing upvalue: ' .. wanted)
        end
        if name == wanted then
            return value
        end
        index = index + 1
    end
end

return {
    {
        name = 'virtual text single-line viewport shows only one line below the cursor',
        run = function()
            helpers.setup_root_config {
                virtualtext = {
                    display_singleline = true,
                    show_on_completion_menu = true,
                },
            }

            local virtualtext = helpers.reload 'harmonize.virtualtext'
            local advance = get_upvalue(virtualtext.action.next, 'advance')
            local update_preview = get_upvalue(advance, 'update_preview')
            local bufnr = helpers.create_buffer({ 'local value =' }, { 1, 13 })
            local original_mode = vim.fn.mode
            vim.fn.mode = function()
                return 'i'
            end

            local ok, err = xpcall(function()
                update_preview {
                    suggestions = { '\nfirst line\nsecond line\nthird line' },
                    choice = 1,
                    shown_choices = {},
                }

                local mark = vim.api.nvim_buf_get_extmark_by_id(bufnr, virtualtext.ns_id, 1, { details = true })
                local details = mark[3]
                helpers.expect_truthy(details)
                helpers.expect_equal(details.virt_text[1][1], '')
                helpers.expect_equal(#details.virt_lines, 1)
                helpers.expect_equal(details.virt_lines[1][1][1], 'first line')
            end, debug.traceback)

            vim.fn.mode = original_mode
            helpers.delete_buffer(bufnr)
            if not ok then
                error(err, 0)
            end
        end,
    },
    {
        name = 'virtual text replaces streamed snapshots instead of repeating their prefixes',
        run = function()
            helpers.setup_root_config {
                provider = 'test_stream',
                virtualtext = {
                    show_on_completion_menu = true,
                },
            }

            package.loaded['harmonize.backends.test_stream'] = {
                complete = function(_, callback, on_update)
                    on_update 'foo'
                    on_update 'foobar'
                    callback { 'foobar' }
                end,
            }

            local virtualtext = helpers.reload 'harmonize.virtualtext'
            local trigger = get_upvalue(virtualtext.action.next, 'trigger')
            local bufnr = helpers.create_buffer({ '' }, { 1, 0 })
            local original_mode = vim.fn.mode
            vim.fn.mode = function()
                return 'i'
            end

            local ok, err = xpcall(function()
                trigger(bufnr)

                local mark = vim.api.nvim_buf_get_extmark_by_id(bufnr, virtualtext.ns_id, 1, { details = true })
                local details = mark[3]
                helpers.expect_truthy(details)
                helpers.expect_equal(details.virt_text[1][1], 'foobar')
            end, debug.traceback)

            vim.fn.mode = original_mode
            helpers.delete_buffer(bufnr)
            if not ok then
                error(err, 0)
            end
        end,
    },
}
