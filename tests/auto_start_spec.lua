local helpers = require 'tests.helpers'

return {
    {
        name = 'auto_start and llama_cpp provider options default to Qwen2.5-Coder-1.5B on port 8012',
        run = function()
            local root = helpers.setup_root_config()

            local auto = root.config.auto_start
            helpers.expect_equal(auto.cmd, 'llama serve')
            helpers.expect_equal(auto.model, 'ggml-org/Qwen2.5-Coder-1.5B-Q8_0-GGUF')
            helpers.expect_equal(auto.extra_args, {})
            helpers.expect_falsy(auto.kill_on_exit)
            helpers.expect_equal(auto.host, '127.0.0.1')
            helpers.expect_equal(auto.port, 8012)

            local opts = root.config.provider_options.llama_cpp
            helpers.expect_equal(opts.end_point, 'http://127.0.0.1:8012/infill')
            helpers.expect_falsy(opts.api_key)
            helpers.expect_equal(opts.stream, true)
        end,
    },
    {
        name = 'server command builds the llama serve invocation with the extra arguments',
        run = function()
            helpers.setup_root_config()

            local auto_start = helpers.reload 'harmonize.auto_start'
            local original_executable = vim.fn.executable
            vim.fn.executable = function(name)
                return name == 'llama' and 1 or 0
            end

            local ok, err = xpcall(function()
                local cmd = auto_start.server_cmd({
                    cmd = 'llama serve',
                    model = 'ggml-org/Qwen2.5-Coder-1.5B-Q8_0-GGUF',
                    extra_args = { '-ngl', '99', '--ctx-size', '8192' },
                }, '127.0.0.1', 8012)
                helpers.expect_equal(cmd, {
                    'llama',
                    'serve',
                    '-hf',
                    'ggml-org/Qwen2.5-Coder-1.5B-Q8_0-GGUF',
                    '--host', '127.0.0.1',
                    '--port', '8012',
                    '-ngl', '99',
                    '--ctx-size', '8192',
                })

                -- A local model file is passed with --model instead of -hf,
                -- and a function returning a list works for extra_args too.
                cmd = auto_start.server_cmd({
                    cmd = 'llama serve',
                    model = '/models/qwen.gguf',
                    extra_args = function()
                        return { '-fa' }
                    end,
                }, '127.0.0.1', 8012)
                helpers.expect_equal(cmd, {
                    'llama',
                    'serve',
                    '--model',
                    '/models/qwen.gguf',
                    '--host', '127.0.0.1',
                    '--port', '8012',
                    '-fa',
                })

                -- An explicit llama-server binary has no `serve` subcommand.
                vim.fn.executable = function(name)
                    return name == 'llama-server' and 1 or 0
                end
                cmd = auto_start.server_cmd({
                    cmd = 'llama-server',
                    model = 'ggml-org/Qwen2.5-Coder-1.5B-Q8_0-GGUF',
                    extra_args = {},
                }, '127.0.0.1', 8012)
                helpers.expect_equal(cmd, {
                    'llama-server',
                    '-hf',
                    'ggml-org/Qwen2.5-Coder-1.5B-Q8_0-GGUF',
                    '--host', '127.0.0.1',
                    '--port', '8012',
                })
            end, debug.traceback)

            vim.fn.executable = original_executable
            if not ok then
                error(err, 0)
            end
        end,
    },
    {
        name = 'server command gives up when no llama.cpp binary can be resolved',
        run = function()
            helpers.setup_root_config()

            local auto_start = helpers.reload 'harmonize.auto_start'
            local original_executable = vim.fn.executable
            vim.fn.executable = function()
                return 0
            end

            local ok, err = xpcall(function()
                local cmd = auto_start.server_cmd({
                    cmd = 'llama serve',
                    model = 'ggml-org/Qwen2.5-Coder-1.5B-Q8_0-GGUF',
                    extra_args = {},
                }, '127.0.0.1', 8012)
                helpers.expect_falsy(cmd, 'no binary found, so there must be no command')
            end, debug.traceback)

            vim.fn.executable = original_executable
            if not ok then
                error(err, 0)
            end
        end,
    },
}
