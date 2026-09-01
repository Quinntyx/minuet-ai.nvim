local helpers = require 'tests.helpers'

return {
    {
        name = 'quickstart defaults to Qwen2.5-Coder-1.5B on the llama.cpp host/port',
        run = function()
            helpers.setup_root_config()

            local quickstart = helpers.reload 'harmonize.quickstart'

            local qs = quickstart.normalize(true)
            helpers.expect_equal(qs.model, 'ggml-org/Qwen2.5-Coder-1.5B-Q8_0-GGUF')
            helpers.expect_equal(qs.port, 8012)
            helpers.expect_equal(qs.host, '127.0.0.1')

            -- User overrides win, unspecified fields keep their defaults.
            local qs2 = quickstart.normalize { model = 'ggml-org/Qwen2.5-Coder-0.6B-GGUF' }
            helpers.expect_equal(qs2.model, 'ggml-org/Qwen2.5-Coder-0.6B-GGUF')
            helpers.expect_equal(qs2.port, 8012)
        end,
    },
    {
        name = 'quickstart server args match the reference llama serve invocation',
        run = function()
            helpers.setup_root_config()

            local quickstart = helpers.reload 'harmonize.quickstart'
            local qs = quickstart.normalize(true)

            local args = quickstart.server_args('llama', qs)
            helpers.expect_equal(args, {
                'serve',
                '-hf',
                'ggml-org/Qwen2.5-Coder-1.5B-Q8_0-GGUF',
                '--host', '127.0.0.1',
                '--port', '8012',
                '-ngl', '99',
                '--ctx-size', '0',
                '-b', '1024',
                '-ub', '1024',
                '--cache-reuse', '256',
            })

            -- A local GGUF file goes through --model instead of -hf, and the
            -- older llama-server binary has no `serve` subcommand.
            local args2 = quickstart.server_args('llama-server', quickstart.normalize {
                model = '/models/qwen.gguf',
            })
            helpers.expect_equal(args2[1], '--model')
            helpers.expect_equal(args2[2], '/models/qwen.gguf')
        end,
    },
    {
        name = 'quickstart wires the provider to the local server when the endpoint is untouched',
        run = function()
            local root = helpers.setup_root_config()

            local quickstart = helpers.reload 'harmonize.quickstart'
            local qs = quickstart.normalize(true)

            local wired = quickstart.wire_provider(root.config, qs)
            helpers.expect_truthy(wired)

            local fim = root.config.provider_options.openai_fim_compatible
            helpers.expect_equal(fim.end_point, 'http://127.0.0.1:8012/v1/completions')
            helpers.expect_equal(fim.api_key, 'TERM')
            helpers.expect_equal(fim.model, 'Qwen2.5-Coder-1.5B-Q8_0-GGUF')
            helpers.expect_equal(root.config.provider, 'openai_fim_compatible')

            -- The Qwen template embeds the FIM special tokens in the prompt.
            local rendered = fim.template.prompt('BEFORE', 'AFTER', {})
            helpers.expect_equal(rendered, '<|fim_prefix|>BEFORE<|fim_suffix|>AFTER<|fim_middle|>')
            helpers.expect_falsy(fim.template.suffix)
        end,
    },
    {
        name = 'quickstart leaves a user-configured endpoint alone',
        run = function()
            local root = helpers.setup_root_config {
                provider_options = {
                    openai_fim_compatible = {
                        end_point = 'http://localhost:9000/v1/completions',
                    },
                },
            }

            local quickstart = helpers.reload 'harmonize.quickstart'
            local qs = quickstart.normalize(true)

            helpers.expect_falsy(quickstart.wire_provider(root.config, qs))
            helpers.expect_equal(
                root.config.provider_options.openai_fim_compatible.end_point,
                'http://localhost:9000/v1/completions'
            )
        end,
    },
}