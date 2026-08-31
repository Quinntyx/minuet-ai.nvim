local helpers = require 'tests.helpers'

local function with_mocked_job(run)
    local common = require 'harmonize.backends.common'
    local original = common.start_job
    local handlers

    common.start_job = function(_, _, value)
        handlers = value
        return {}
    end

    local ok, err = xpcall(function()
        run(function()
            return handlers
        end)
    end, debug.traceback)
    common.start_job = original

    if not ok then
        error(err, 0)
    end
end

local function options(stream)
    return {
        model = 'test-model',
        name = 'Test',
        stream = stream,
        optional = {},
        transform = {},
        end_point = 'http://127.0.0.1/completions',
        api_key = 'TERM',
        template = {
            prompt = function()
                return 'prompt'
            end,
            suffix = false,
        },
    }
end

local context = {
    lines_before = '',
    lines_after = '',
    opts = {},
}

return {
    {
        name = 'openai FIM streaming emits complete snapshots without duplicating chunks',
        run = function()
            helpers.setup_root_config {
                before_cursor_filter_length = 0,
                after_cursor_filter_length = 0,
            }

            with_mocked_job(function(get_handlers)
                local base = helpers.reload 'harmonize.backends.openai_base'
                local updates = {}
                local result

                base.complete_openai_fim_base(options(true), function(json)
                    return json.choices[1].text
                end, context, function(items)
                    result = items
                end, function(text)
                    table.insert(updates, text)
                end)

                local handlers = assert(get_handlers())
                helpers.expect_truthy(handlers.on_stdout)

                handlers.on_stdout(nil, 'data: {"choices":[{"text":"foo"}]}\r')
                handlers.on_stdout(nil, '\ndata: {"choices":[{"text":"bar"}]}\r\n')
                handlers.on_stdout(nil, 'data: [DONE]\r\n')
                handlers.on_exit({}, { code = 0 })

                helpers.expect_equal(updates, { 'foo', 'foobar' })
                helpers.expect_equal(result, { 'foobar' })
            end)
        end,
    },
    {
        name = 'openai FIM non-streaming leaves stdout collection to vim.system',
        run = function()
            helpers.setup_root_config {
                before_cursor_filter_length = 0,
                after_cursor_filter_length = 0,
            }

            with_mocked_job(function(get_handlers)
                local base = helpers.reload 'harmonize.backends.openai_base'
                local result

                base.complete_openai_fim_base(options(false), function(json)
                    return json.choices[1].text
                end, context, function(items)
                    result = items
                end)

                local handlers = assert(get_handlers())
                helpers.expect_falsy(handlers.on_stdout)
                handlers.on_exit({}, {
                    code = 0,
                    stdout = '{"choices":[{"text":"plain"}]}',
                })

                helpers.expect_equal(result, { 'plain' })
            end)
        end,
    },
}
