local helpers = require 'tests.helpers'

return {
    {
        name = 'managed llama.cpp options default to Qwen2.5-Coder-1.5B on port 8012',
        run = function()
            local root = helpers.setup_root_config()

            local opts = root.config.provider_options.llama_cpp_managed
            helpers.expect_equal(opts.model, 'ggml-org/Qwen2.5-Coder-1.5B-Q8_0-GGUF')
            helpers.expect_equal(opts.host, '127.0.0.1')
            helpers.expect_equal(opts.port, 8012)
            helpers.expect_equal(opts.llama_cpp_flags, '')
            helpers.expect_falsy(opts.kill_on_exit)
        end,
    },
    {
        name = 'server args build the llama serve invocation and append the user flags',
        run = function()
            helpers.setup_root_config()

            local llama_cpp = helpers.reload 'harmonize.llama_cpp'

            local args = llama_cpp.server_args('llama', {
                model = 'ggml-org/Qwen2.5-Coder-1.5B-Q8_0-GGUF',
                host = '127.0.0.1',
                port = 8012,
                llama_cpp_flags = '-ngl 99 --ctx-size 8192',
            })
            helpers.expect_equal(args, {
                'serve',
                '-hf',
                'ggml-org/Qwen2.5-Coder-1.5B-Q8_0-GGUF',
                '--host', '127.0.0.1',
                '--port', '8012',
                '-ngl', '99',
                '--ctx-size', '8192',
            })

            -- The older llama-server binary has no `serve` subcommand, and a
            -- local GGUF path goes through --model instead of -hf.
            local args2 = llama_cpp.server_args('llama-server', {
                model = '/models/qwen.gguf',
                host = '127.0.0.1',
                port = 8012,
                llama_cpp_flags = '',
            })
            helpers.expect_equal(args2, {
                '--model',
                '/models/qwen.gguf',
                '--host', '127.0.0.1',
                '--port', '8012',
            })
        end,
    },
    {
        name = 'wiring points the FIM provider at the managed server with the Qwen template',
        run = function()
            local root = helpers.setup_root_config()

            local llama_cpp = helpers.reload 'harmonize.llama_cpp'
            local opts = root.config.provider_options.llama_cpp_managed

            llama_cpp.wire_provider(root.config, opts)

            local fim = root.config.provider_options.openai_fim_compatible
            helpers.expect_equal(fim.end_point, 'http://127.0.0.1:8012/v1/completions')
            helpers.expect_equal(fim.api_key, 'TERM')
            helpers.expect_equal(fim.model, 'Qwen2.5-Coder-1.5B-Q8_0-GGUF')
            helpers.expect_equal(root.config.provider, 'openai_fim_compatible')

            -- The Qwen template embeds the FIM special tokens in the prompt.
            helpers.expect_equal(
                fim.template.prompt('BEFORE', 'AFTER', {}),
                '<|fim_prefix|>BEFORE<|fim_suffix|>AFTER<|fim_middle|>'
            )
            helpers.expect_falsy(fim.template.suffix)
        end,
    },
    {
        name = 'a non-Qwen managed model keeps the default FIM template',
        run = function()
            local root = helpers.setup_root_config()

            local llama_cpp = helpers.reload 'harmonize.llama_cpp'
            local default_suffix = root.config.provider_options.openai_fim_compatible.template.suffix

            llama_cpp.wire_provider(root.config, {
                model = '/models/coder.gguf',
                host = '127.0.0.1',
                port = 8012,
                llama_cpp_flags = '',
            })

            local fim = root.config.provider_options.openai_fim_compatible
            helpers.expect_equal(fim.end_point, 'http://127.0.0.1:8012/v1/completions')
            helpers.expect_equal(fim.model, 'coder.gguf')
            helpers.expect_equal(fim.template.suffix, default_suffix)
        end,
    },
}