local helpers = require 'tests.helpers'

local function with_mocked_job(run)
    local common = require 'harmonize.backends.common'
    local original = common.start_job
    local captured

    common.start_job = function(_, args, value)
        captured = { args = args, handlers = value }
        return {}
    end

    local ok, err = xpcall(function()
        run(function()
            return captured
        end)
    end, debug.traceback)

    common.start_job = original

    if not ok then
        error(err, 0)
    end
end

local context = {
    lines_before = 'function add(a, b) {',
    lines_after = '\n}',
}

---The request body goes through a temp file referenced as `-d @<file>`.
local function request_body(args)
    for i, arg in ipairs(args) do
        if arg == '-d' then
            local data_file = args[i + 1]:sub(2) -- strip '@'
            return vim.json.decode(vim.fn.readfile(data_file)[1])
        end
    end
    error('the request body must be passed to curl')
end

return {
    {
        name = 'llama_cpp streaming sends input_prefix and input_suffix to /infill and accumulates the stream',
        run = function()
            helpers.setup_root_config {
                before_cursor_filter_length = 0,
                after_cursor_filter_length = 0,
            }

            with_mocked_job(function(get)
                local backend = helpers.reload 'harmonize.backends.llama_cpp'
                local updates = {}
                local result

                backend.complete(context, function(items)
                    result = items
                end, function(text)
                    table.insert(updates, text)
                end)

                local captured = get()
                local body = request_body(captured.args)
                helpers.expect_equal(body.input_prefix, context.lines_before)
                helpers.expect_equal(body.input_suffix, context.lines_after)
                helpers.expect_equal(body.stream, true)
                -- The native endpoint builds the FIM prompt on the server:
                -- no template keys and no model are sent.
                helpers.expect_falsy(body.prompt)
                helpers.expect_falsy(body.suffix)
                helpers.expect_falsy(body.model)

                -- The provider endpoint is passed through as-is.
                local end_point_seen = false
                for _, arg in ipairs(captured.args) do
                    if arg == 'http://127.0.0.1:8012/infill' then
                        end_point_seen = true
                    end
                end
                helpers.expect_truthy(end_point_seen, 'the /infill endpoint must be requested')

                local handlers = captured.handlers
                helpers.expect_truthy(handlers.on_stdout)
                handlers.on_stdout(nil, 'data: {"content":"turn","stop":false}\r\n')
                handlers.on_stdout(nil, 'data: {"content":" a + b;","stop":true}\r\n')
                handlers.on_exit({}, { code = 0 })

                helpers.expect_equal(updates, { 'turn', 'turn a + b;' })
                helpers.expect_equal(result, { 'turn a + b;' })
            end)
        end,
    },
    {
        name = 'llama_cpp non-streaming reads the content field from the response',
        run = function()
            helpers.setup_root_config {
                before_cursor_filter_length = 0,
                after_cursor_filter_length = 0,
                provider_options = {
                    llama_cpp = { stream = false },
                },
            }

            with_mocked_job(function(get)
                local backend = helpers.reload 'harmonize.backends.llama_cpp'
                local result

                backend.complete(context, function(items)
                    result = items
                end)

                local handlers = get().handlers
                helpers.expect_falsy(handlers.on_stdout)
                handlers.on_exit({}, {
                    code = 0,
                    stdout = '{"content":"plain"}',
                })

                helpers.expect_equal(result, { 'plain' })
            end)
        end,
    },
}
