- [Minuet](#minuet)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
  - [Virtual Text Setup](#virtual-text-setup)
  - [LLM Provider Examples](#llm-provider-examples)
    - [Openrouter deepseek-v4-flash](#openrouter-deepseek-v4-flash)
    - [Opencode Go deepseek-v4-flash](#opencode-go-deepseek-v4-flash)
    - [Deepseek deepseek-v4-flash](#deepseek-deepseek-v4-flash)
    - [Ollama Qwen-2.5-coder:7b](#ollama-qwen-25-coder7b)
    - [Llama.cpp Qwen-2.5-coder:1.5b](#llamacpp-qwen-25-coder15b)
- [Selecting a Provider or Model](#selecting-a-provider-or-model)
  - [Understanding Model Speed](#understanding-model-speed)
- [Configuration](#configuration)
- [API Keys](#api-keys)
- [Prompt](#prompt)
  - [Prefix-First vs. Suffix-First](#prefix-first-vs-suffix-first)
- [Providers](#providers)
  - [OpenAI](#openai)
  - [Claude](#claude)
  - [Codestral](#codestral)
  - [Mercury Coder](#mercury-coder)
  - [Gemini](#gemini)
  - [OpenAI-compatible](#openai-compatible)
  - [OpenAI-FIM-compatible](#openai-fim-compatible)
    - [Non-OpenAI-FIM-Compatible APIs](#non-openai-fim-compatible-apis)
- [Commands](#commands)
  - [`Minuet change_provider`, `Minuet change_model`](#minuet-change_provider-minuet-change_model)
  - [`Minuet change_preset`](#minuet-change_preset)
  - [`Minuet virtualtext`](#minuet-virtualtext)
- [API](#api)
  - [Virtual Text](#virtual-text)
  - [Minuet Event](#minuet-event)
    - [Standard Completion Events](#standard-completion-events)
    - [Event Data](#event-data)
- [FAQ](#faq)
  - [Integration with `lazyvim`](#integration-with-lazyvim)
- [Enhancement](#enhancement)
  - [RAG (Experimental)](#rag-experimental)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [Acknowledgement](#acknowledgement)

# Minuet

Minuet: Dance with Intelligence in Your Code 💃.

`Minuet` brings the grace and harmony of a minuet to your coding process.
Just as dancers move during a minuet.

# Features

- AI-powered code completion with dual modes:
  - Specialized prompts and various enhancements for chat-based LLMs on code completion tasks.
  - Fill-in-the-middle (FIM) completion for compatible models (DeepSeek,
    Codestral, Qwen, and others).
- Support for multiple AI providers (OpenAI, Claude, Gemini, Codestral, Ollama,
  Llama-cpp, and OpenAI-compatible services).
- Customizable configuration options.
- Streaming support to enable completion delivery even with slower LLMs.
- No proprietary binary running in the background. Just curl and your preferred LLM provider.
- Support the `virtual-text` frontend.

- Accept multi-line suggestions line-by-line, so longer suggestions can be
  pulled in incrementally in your own pace.
- When your typed text matches the start of a suggestion, Minuet keeps the
  completion in sync of your typed text rather than discarding it, to reduce
  unnecessary LLM requests and conserving resources.



**With builtin completion frontend** (requires nvim 0.11+):

![example-builtin-completion](./assets/example-builtin-completion.jpg)

**With virtual text frontend**:

![example-virtual-text](./assets/example-virtual-text.png)

https://github.com/user-attachments/assets/e0c4f2bd-0361-45b4-8eb4-0f49356bd7d9

<!-- The link above is a showcase video for the virtual text feature, hosted -->
<!-- externally on GitHub. -->
# Requirements

- Neovim 0.10+.
- An API key for at least one of the supported AI providers
- An API key for at least one of the supported AI providers
- ~~[plenary.nvim](https://github.com/nvim-lua/plenary.nvim)~~ Minuet now uses
  the builtin `vim.system` and no longer requires plenary.

# Installation

**Lazy.nvim**:

```lua
specs = {
    {
        'milanglacier/minuet-ai.nvim',
        config = function()
            require('minuet').setup {
                -- Your configuration options here
            }
        end,
        end,
    },
}
```
}
```

**Rocks.nvim**:

`Minuet` is available on luarocks.org. Simply run `Rocks install minuet-ai.nvim` to install it like any other luarocks package.

# Quick Start

## Virtual Text Setup

```lua
require('minuet').setup {
    virtualtext = {
        auto_trigger_ft = {},
        keymap = {
            -- accept whole completion
            accept = '<A-A>',
            -- accept one line
            accept_line = '<A-a>',
            -- accept one chunk (current identifier plus the special
            -- characters that follow it)
            accept_chunk = '<A-c>',
            -- accept n lines (prompts for number)
            -- e.g. "A-z 2 CR" will accept 2 lines
            accept_n_lines = '<A-z>',
            -- Cycle to prev completion item, or manually invoke completion
            prev = '<A-[>',
            -- Cycle to next completion item, or manually invoke completion
            next = '<A-]>',
            dismiss = '<A-e>',
        },
    },
}
```

## LLM Provider Examples

### Openrouter deepseek-v4-flash

<details>

```lua
require('minuet').setup {
    provider = 'openai_compatible',
    request_timeout = 2.5,
    throttle = 1500, -- Increase to reduce costs and avoid rate limits
    debounce = 600, -- Increase to reduce costs and avoid rate limits
    provider_options = {
        openai_compatible = {
            api_key = 'OPENROUTER_API_KEY',
            end_point = 'https://openrouter.ai/api/v1/chat/completions',
            model = 'deepseek/deepseek-v4-flash',
            name = 'Openrouter',
            optional = {
                max_tokens = 56,
                top_p = 0.9,
                provider = {
                     -- Prioritize throughput for faster completion
                    sort = 'throughput',
                },
                -- disable thinking to avoid first token latency
                reasoning_effort = 'none'
            },
        },
    },
}
```

</details>

### Opencode Go deepseek-v4-flash

<details>

```lua
require('minuet').setup {
    provider = 'openai_compatible',
    request_timeout = 2.5,
    throttle = 1500, -- Increase to reduce costs and avoid rate limits
    debounce = 600, -- Increase to reduce costs and avoid rate limits
    provider_options = {
        openai_compatible = {
            api_key = 'OPENCODE_GO_API_KEY',
            end_point = 'https://opencode.ai/zen/go/v1/chat/completions',
            model = 'deepseek-v4-flash',
            name = 'Opencode',
            optional = {
                max_tokens = 56,
                top_p = 0.9,
                -- disable thinking to avoid first token latency
                thinking = { type = 'disabled' },
            },
        },
    },
}
```

</details>

### Deepseek deepseek-v4-flash

<details>

```lua
require('minuet').setup {
    provider = 'openai_fim_compatible',
    provider_options = {
        openai_fim_compatible = {
            api_key = 'DEEPSEEK_API_KEY',
            name = 'deepseek',
            optional = {
                max_tokens = 256,
                top_p = 0.9,
            },
        },
    },
}
```

</details>

### Ollama Qwen-2.5-coder:7b

<details>

```lua
require('minuet').setup {
    provider = 'openai_fim_compatible',
    -- I recommend beginning with a small context window size and incrementally
    -- expanding it, depending on your local computing power. A context window
    -- of 512, serves as an good starting point to estimate your computing
    -- power. Once you have a reliable estimate of your local computing power,
    -- you should adjust the context window to a larger value.
    context_window = 512,
    provider_options = {
        openai_fim_compatible = {
            -- For Windows users, TERM may not be present in environment variables.
            -- Consider using APPDATA instead.
            api_key = 'TERM',
            name = 'Ollama',
            end_point = 'http://localhost:11434/v1/completions',
            model = 'qwen2.5-coder:7b',
            optional = {
                max_tokens = 56,
                top_p = 0.9,
            },
        },
    },
}
```

</details>

### Llama.cpp Qwen-2.5-coder:1.5b

<details>

First, launch the `llama-server` with your chosen model.

Here's an example of a bash script to start the server if your system has less
than 8GB of VRAM:

```bash
llama-server \
    -hf ggml-org/Qwen2.5-Coder-1.5B-Q8_0-GGUF \
    --port 8012 -ngl 99 -fa -ub 1024 -b 1024 \
    --ctx-size 0 --cache-reuse 256
```

```lua
require('minuet').setup {
    provider = 'openai_fim_compatible',
    -- I recommend beginning with a small context window size and incrementally
    -- expanding it, depending on your local computing power. A context window
    -- of 512, serves as an good starting point to estimate your computing
    -- power. Once you have a reliable estimate of your local computing power,
    -- you should adjust the context window to a larger value.
    context_window = 512,
    provider_options = {
        openai_fim_compatible = {
            -- For Windows users, TERM may not be present in environment variables.
            -- Consider using APPDATA instead.
            api_key = 'TERM',
            name = 'Llama.cpp',
            end_point = 'http://localhost:8012/v1/completions',
            -- The model is set by the llama-cpp server and cannot be altered
            -- post-launch.
            model = 'PLACEHOLDER',
            optional = {
                max_tokens = 56,
                top_p = 0.9,
            },
            -- Llama.cpp does not support the `suffix` option in FIM completion.
            -- Therefore, we must disable it and manually populate the special
            -- tokens required for FIM completion.
            template = {
                prompt = function(context_before_cursor, context_after_cursor, _)
                    return '<|fim_prefix|>'
                        .. context_before_cursor
                        .. '<|fim_suffix|>'
                        .. context_after_cursor
                        .. '<|fim_middle|>'
                end,
                suffix = false,
            },
        },
    },
}
```

**NOTE**: Special tokens such as `<|fim_prefix|>` vary across different models.
The example code provided uses the tokens specific to `Qwen-2.5-coder`. If you
intend to use a different model, ensure the `llama-cpp` template is updated to
reflect the corresponding special tokens for your chosen model.

For additional example bash scripts to run llama.cpp based on your local
computing power, please refer to [recipes.md](./recipes.md).

</details>

# Selecting a Provider or Model

The `gemini-2.0-flash` and `codestral` models offer high-quality output with
free and fast processing. The `deepseek-v4-flash` model, used with the
`openai_fim_compatible` provider, is an alternative for low-cost APIs and fast
inference. For local LLM inference, you can deploy either `qwen-2.5-coder` or
`deepseek-coder-v2` through Ollama using the `openai-fim-compatible` provider.

We **do not** recommend using thinking models, as this mode significantly
increases latency—even with the fastest models. However, if you choose to use
thinking models, please ensure that their thinking capabilities are disabled.
Refer to the following examples for guidance on how to disable the thinking
feature.

## Understanding Model Speed

For cloud-based providers,
[Openrouter](https://openrouter.ai/google/gemini-2.0-flash-001/providers)
offers a valuable resource for comparing the speed of both closed-source and
open-source models hosted by various cloud inference providers.

When assessing model speed, two key metrics are latency (time to first token)
and throughput (tokens per second). Latency is often a more critical factor
than throughput.

Ideally, one would aim for a latency of less than 1 second and a throughput
exceeding 100 tokens per second.

For local LLM,
[llama.cpp#4167](https://github.com/ggml-org/llama.cpp/discussions/4167)
provides valuable data on model speed for 7B models running on Apple M-series
chips. The two crucial metrics are `Q4_0 PP [t/s]`, which measures latency
(tokens per second to process the KV cache, equivalent to the time to generate
the first token), and `Q4_0 TG [t/s]`, which indicates the tokens per second
generation speed.

# Configuration

Minuet AI comes with the following defaults:

default_config = {
    virtualtext = {
        -- Specify the filetypes to enable automatic virtual text completion,
        -- e.g., { 'python', 'lua' }. Note that you can still invoke manual
        -- completion even if the filetype is not on your auto_trigger_ft list.
        auto_trigger_ft = {},
        -- specify file types where automatic virtual text completion should be
        -- disabled. This option is useful when auto-completion is enabled for
        -- all file types i.e., when auto_trigger_ft = { '*' }
        auto_trigger_ignore_ft = {},
        keymap = {
            accept = nil,
            accept_line = nil,
            accept_chunk = nil,
            accept_n_lines = nil,
            -- Cycle to next completion item, or manually invoke completion
            next = nil,
            -- Cycle to prev completion item, or manually invoke completion
            prev = nil,
            dismiss = nil,
        },
        -- Whether to show virtual text suggestion when a
        -- completion menu is visible.
        show_on_completion_menu = false,
        -- Show only the remainder of the current line of the completion.
        -- When the completion starts with a newline, the current line is
        -- already complete, so show the line below instead. The rest of the
        -- completion stays available for further acceptance, which lets you
        -- accept the completion one visible line at a time.
        display_singleline = false,
    },
    provider = 'codestral',
    -- the maximum total characters of the context before and after the cursor
    -- 16000 characters typically equate to approximately 4,000 tokens for
    -- LLMs.
    context_window = 16000,
    -- when the total characters exceed the context window, the ratio of
    -- context before cursor and after cursor, the larger the ratio the more
    -- context before cursor will be used. This option should be between 0 and
    -- 1, context_ratio = 0.75 means the ratio will be 3:1.
    context_ratio = 0.75,
    throttle = 1000, -- only send the request every x milliseconds, use 0 to disable throttle.
    -- debounce the request in x milliseconds, set to 0 to disable debounce
    debounce = 400,
    -- Control notification display for request status
    -- Notification options:
    -- false: Disable all notifications (use boolean false, not string "false")
    -- "debug": Display all notifications (comprehensive debugging)
    -- "verbose": Display most notifications
    -- "warn": Display warnings and errors only
    -- "error": Display errors only
    notify = 'warn',
    -- The request timeout, measured in seconds. When streaming is enabled
    -- (stream = true), setting a shorter request_timeout allows for faster
    -- retrieval of completion items, albeit potentially incomplete.
    -- Conversely, with streaming disabled (stream = false), a timeout
    -- occurring before the LLM returns results will yield no completion items.
    request_timeout = 3,
    -- Command used to make HTTP requests.
    curl_cmd = 'curl',
    -- Extra arguments passed to curl (list of strings, or a function returning a list of strings).
    curl_extra_args = {},
    -- Length of context after cursor used to filter completion text.
    --
    -- This setting helps prevent the language model from generating redundant
    -- text.  When filtering completions, the system compares the suffix of a
    -- completion candidate with the text immediately following the cursor.
    --
    -- If the length of the longest common substring between the end of the
    -- candidate and the beginning of the post-cursor context exceeds this
    -- value, that common portion is trimmed from the candidate.
    --
    -- For example, if the value is 15, and a completion candidate ends with a
    -- 20-character string that exactly matches the 20 characters following the
    -- cursor, the candidate will be truncated by those 20 characters before
    -- being delivered.

    -- The default is 0 for FIM model, and 15 for chat model
    after_cursor_filter_length = function() end,
    -- Similar to after_cursor_filter_length but trim the completion item from
    -- prefix instead of suffix.
    --
    -- Note: FIM completions do not strip surrounding whitespace by default.
    -- Their default filter lengths are 0 because FIM models emit intentional
    -- leading/trailing whitespace. Setting positive filter lengths keeps
    -- duplicate context filtering enabled for FIM completions.
    --
    -- The default is 0 for FIM model, and 2 for chat model
    before_cursor_filter_length = function() end,
    -- proxy port to use
    proxy = nil,
    -- **List** of functions to execute. If any function returns `false`, Minuet
    -- will not trigger auto-completion. Manual completion can still be invoked,
    -- even if these functions evaluate to `false`, when using virtual text.
    -- When this list is empty (the default), it always evaluates to `true`.
    -- Note that this is called each time Minuet attempts to trigger
    -- auto-completion, so ensure the functions in this list are highly efficient.
    enable_predicates = {},
    provider_options = {
        -- see the documentation in each provider in the following part.
    },
    -- see the documentation in the `Prompt` section
    default_system = {
        template = '...',
        prompt = '...',
        guidelines = '...',
        n_completion_template = '...',
    },
    default_system_prefix_first = {
        template = '...',
        prompt = '...',
        guidelines = '...',
        n_completion_template = '...',
    },
    default_fim_template = {
        prompt = '...',
        suffix = '...',
    },
    default_few_shots = { '...' },
    default_chat_input = { '...' },
    default_few_shots_prefix_first = { '...' },
    default_chat_input_prefix_first = { '...' },
    -- Config options for `Minuet change_preset` command
    presets = {}
}
```

# API Keys

Minuet AI requires API keys to function. Set the following environment variables:

- `OPENAI_API_KEY` for OpenAI
- `GEMINI_API_KEY` for Gemini
- `ANTHROPIC_API_KEY` for Claude
- `CODESTRAL_API_KEY` for Codestral
- Custom environment variable for OpenAI-compatible services (as specified in your configuration)

**Note:** Provide the name of the environment variable to Minuet, not the
actual value. For instance, pass `OPENAI_API_KEY` to Minuet, not the value
itself (e.g., `sk-xxxx`).

If using Ollama, you need to assign an arbitrary, non-null environment variable
as a placeholder for it to function.

Alternatively, you can provide a function that returns the API key. This
function should return the result instantly as it will be called for each
completion request.

```lua
require('minuet').setup {
    provider_options = {
        openai_compatible = {
            -- good
            api_key = 'FIREWORKS_API_KEY', -- will read the environment variable FIREWORKS_API_KEY
            -- good
            api_key = function() return 'sk-xxxx' end,
            -- bad
            api_key = 'sk-xxxx',
        }
    }
}
```

# Prompt

See [prompt](./prompt.md) for the default prompt used by `minuet` and
instructions on customization.

Note that `minuet` employs two distinct prompt systems:

1. A system designed for chat-based LLMs (OpenAI, OpenAI-Compatible, Claude,
   and Gemini)
2. A separate system designed for Codestral and OpenAI-FIM-compatible models

## Prefix-First vs. Suffix-First

When use chat-based LLMs, there are two ways for constructing the prompt:
placing the prefix (context before the cursor) before the suffix (context after
the cursor), or placing the suffix before the prefix.

By default, `minuet` uses the **prefix-first** style for the OpenAI, Gemini,
and OpenAI-Compatible (with `deepseek-v4-flash` as the default model)
providers, and the **suffix-first** style for Claude providers. It is
recommended that you experiment with both strategies to determine which yields
the best results, particularly if you are using an OpenAI-compatible provider
with various models.

Below is an example code snippet demonstrating how to switch between these two
prompt construction methods:

<details>

```lua
local mc = require 'minuet.config'

-- Prefix-first style
require('minuet').setup {
    provider_options = {
        openai_compatible = {
            system = mc.default_system_prefix_first,
            chat_input = mc.default_chat_input_prefix_first,
            few_shots = mc.default_few_shots_prefix_first,
        },
    },
}

-- Suffix-first style
require('minuet').setup {
    provider_options = {
        openai_compatible = {
            system = mc.default_system,
            few_shots = mc.default_few_shots,
            chat_input = mc.default_chat_input,
        },
    },
}
```

</details>

# Providers

You need to set the field `provider` in the config, the default provider is
`codestral`. For example:

```lua
require('minuet').setup {
    provider = 'gemini'
}
```

## OpenAI

<details>

the following is the default configuration for OpenAI:

```lua
provider_options = {
    openai = {
        model = 'gpt-5.6-luna',
        end_point = 'https://api.openai.com/v1/chat/completions',
        system = "see [Prompt] section for the default value",
        few_shots = "see [Prompt] section for the default value",
        chat_input = "See [Prompt Section for default value]",
        stream = true,
        api_key = 'OPENAI_API_KEY',
        optional = {
            -- pass any additional parameters you want to send to OpenAI request,
            -- e.g.
            -- stop = { 'end' },
            -- max_completion_tokens = 256,
            -- top_p = 0.9,
            -- reasoning_effort = 'none'
        },
        -- a list of functions to transform the endpoint, header, and request body
        transform = {},
    },
}
```

The following configuration is not the default, but recommended to prevent
request timeout from outputing too many tokens.

```lua
provider_options = {
	openai = {
		optional = {
			max_completion_tokens = 128,
			-- for thinking models
			reasoning_effort = 'none'
			-- reasoning_effort = "minimal",
			-- Set to "minimal" if your chosen model doesn't support "none"
		},
	},
}
```

Note: If you intend to use GPT-5 series models (e.g., `gpt-5-mini` or
`gpt-5.6-luna`), keep the following points in mind:

1. Use `max_completion_tokens` instead of `max_tokens`.
2. These models do not support `top_p` or `temperature` adjustments.
3. Disable thinking by setting `reasoning_effort` to `none`, or use `minimal`
   if your chosen model does not support `none`.

</details>

## Claude

<details>

the following is the default configuration for Claude:

```lua
provider_options = {
    claude = {
        max_tokens = 256,
        model = 'claude-haiku-4.5',
        system = "see [Prompt] section for the default value",
        few_shots = "see [Prompt] section for the default value",
        chat_input = "See [Prompt Section for default value]",
        stream = true,
        api_key = 'ANTHROPIC_API_KEY',
        end_point = 'https://api.anthropic.com/v1/messages',
        optional = {
            -- pass any additional parameters you want to send to claude request,
            -- e.g.
            -- stop_sequences = nil,
        },
        -- a list of functions to transform the endpoint, header, and request body
        transform = {},
    },
}
```

</details>

## Codestral

<details>

Codestral is a text completion model, not a chat model, so the system prompt
and few shot examples does not apply. Note that you should use the
`CODESTRAL_API_KEY`, not the `MISTRAL_API_KEY`, as they are using different
endpoint. To use the Mistral endpoint, simply modify the `end_point` and
`api_key` parameters in the configuration.

the following is the default configuration for Codestral:

```lua
provider_options = {
    codestral = {
        model = 'codestral-latest',
        end_point = 'https://codestral.mistral.ai/v1/fim/completions',
        api_key = 'CODESTRAL_API_KEY',
        stream = true,
        template = {
            prompt = "See [Prompt Section for default value]",
            suffix = "See [Prompt Section for default value]",
        },
        optional = {
            stop = nil, -- the identifier to stop the completion generation
            max_tokens = nil,
        },
    },
}
```

The following configuration is not the default, but recommended to prevent
request timeout from outputing too many tokens.

```lua
provider_options = {
    codestral = {
        optional = {
            max_tokens = 256,
            stop = { '\n\n' },
        },
    },
}
```

</details>

## Mercury Coder

Developed by Inception, Mercury Coder is described as a diffusion-based large
language model that accelerates code generation through iterative refinement
rather than autoregressive token prediction. According to the claim, this
approach is intended to deliver faster and more efficient code completions. To
begin, obtain an API key from the Inception Platform and configure it as the
`INCEPTION_API_KEY` environment variable.

<details>

You can access Mercury Coder via the OpenAI compatible FIM endpoint using the
following configuration:

```lua
provider_options = {
    openai_fim_compatible = {
        model = "mercury-coder",
        end_point = "https://api.inceptionlabs.ai/v1/fim/completions",
        api_key = "INCEPTION_API_KEY", -- environment variable name
        stream = true,
    },
}
```

</details>

## Gemini

You should register the account and use the service from Google AI Studio
instead of Google Cloud. You can get an API key via their
[Google API page](https://makersuite.google.com/app/apikey).

<details>

The following config is the default.

```lua
provider_options = {
    gemini = {
        model = 'gemini-2.0-flash',
        system = "see [Prompt] section for the default value",
        few_shots = "see [Prompt] section for the default value",
        chat_input = "See [Prompt Section for default value]",
        stream = true,
        api_key = 'GEMINI_API_KEY',
        end_point = 'https://generativelanguage.googleapis.com/v1beta/models',
        optional = {},
        -- a list of functions to transform the endpoint, header, and request body
        transform = {},
    },
}
```

The following configuration is not the default, but recommended to prevent
request timeout from outputing too many tokens. You can also adjust the safety
settings following the example:

```lua
provider_options = {
    gemini = {
        optional = {
            generationConfig = {
                maxOutputTokens = 256,
                thinkingConfig = {
                    -- Disable thinking for gemini 2.5 models
                    thinkingBudget = 0,
                    -- Disable thinking for gemini 3.x models
                    thinkingLevel = 'minimal',
                    -- Setting only one of the above options is sufficient.
                },
            },
            safetySettings = {
                {
                    -- HARM_CATEGORY_HATE_SPEECH,
                    -- HARM_CATEGORY_HARASSMENT
                    -- HARM_CATEGORY_SEXUALLY_EXPLICIT
                    category = 'HARM_CATEGORY_DANGEROUS_CONTENT',
                    -- BLOCK_NONE
                    threshold = 'BLOCK_ONLY_HIGH',
                },
            },
        },
    },
}
```

We recommend using `gemini-2.0-flash` over `gemini-2.5-flash`, as the 2.0
version offers significantly lower costs with comparable performance. The
primary improvement in version 2.5 lies in its extended thinking mode, which
provides minimal value for code completion scenarios. Furthermore, the thinking
mode substantially increases latency, so we recommend disabling it entirely.

</details>

## OpenAI-compatible

Use any providers compatible with OpenAI's chat completion API.

For example, you can set the `end_point` to
`http://localhost:11434/v1/chat/completions` to use `ollama`.

<details>

Note that not all openAI compatible services has streaming support, you should
change `stream=false` to disable streaming in case your services do not support
it.

The following config is the default.

```lua
provider_options = {
    openai_compatible = {
        model = 'deepseek/deepseek-v4-flash',
        system = "see [Prompt] section for the default value",
        few_shots = "see [Prompt] section for the default value",
        chat_input = "See [Prompt Section for default value]",
        stream = true,
        end_point = 'https://openrouter.ai/api/v1/chat/completions',
        api_key = 'OPENROUTER_API_KEY',
        name = 'Openrouter',
        optional = {
            stop = nil,
            max_tokens = nil,
        },
        -- a list of functions to transform the endpoint, header, and request body
        transform = {},
    }
}
```

**Disabling thinking for reasoning models:**

| Provider             | Configuration                                                              |
| -------------------- | -------------------------------------------------------------------------- |
| **OpenRouter**       | `reasoning = { effort = 'none' }` (or `'minimal'`, depending on the model) |
| **DeepSeek API**     | `thinking = { type = 'disabled' }`                                         |
| **Various Provider** | `reasoning_effort = 'none'`                                                |

```lua
provider_options = {
    openai_compatible = {
        optional = {
            -- Disable thinking for reasoning models
            reasoning = { effort = 'none' }, -- or "minimal", depending on the model (OpenRouter)
            -- reasoning_effort = 'none', -- or "minimal", depending on the model (various providers)
            -- thinking = { type = 'disabled' } -- DeepSeek API
        },
    },
}
```

</details>

## OpenAI-FIM-compatible

Use any provider compatible with OpenAI's completion API. This request uses the
text `/completions` endpoint, **not** `/chat/completions` endpoint, so system
prompts and few-shot examples are not applicable.

For example, you can set the `end_point` to
`http://localhost:11434/v1/completions` to use `ollama`,
`http://localhost:8012/v1/completions` to use `llama.cpp`.

Cmdline completion is available for models supported by these providers:
`deepseek`, `ollama`, and `siliconflow`.

<details>

Refer to the [Completions
Legacy](https://platform.openai.com/docs/api-reference/completions) section of
the OpenAI documentation for details.

Please note that not all OpenAI-compatible services support streaming. If your
service does not support streaming, you should set `stream=false` to disable
it.

Additionally, for Ollama users, it is essential to verify whether the model's
template supports FIM completion. For example, qwen2.5-coder offers FIM
support, as suggested in its
[template](https://ollama.com/library/qwen2.5-coder/blobs/e94a8ecb9327).
However it may come as a surprise to some users that, `deepseek-coder` does not
support the FIM template, and you should use `deepseek-coder-v2` instead.

For example bash scripts to run llama.cpp based on your local
computing power, please refer to [recipes.md](./recipes.md). Note
that the model for `llama.cpp` must be determined when you launch the
`llama.cpp` server and cannot be changed thereafter.

```lua
provider_options = {
    openai_fim_compatible = {
        model = 'deepseek-v4-flash',
        end_point = 'https://api.deepseek.com/beta/completions',
        api_key = 'DEEPSEEK_API_KEY',
        name = 'Deepseek',
        stream = true,
        template = {
            prompt = "See [Prompt Section for default value]",
            suffix = "See [Prompt Section for default value]",
        },
        -- a list of functions to transform the endpoint, header, and request body
        transform = {},
        -- Custom function to extract LLM-generated text from JSON output
        get_text_fn = {}
        optional = {
            stop = nil,
            max_tokens = nil,
        },
    }
}
```

The following configuration is not the default, but recommended to prevent
request timeout from outputing too many tokens.

```lua
provider_options = {
    openai_fim_compatible = {
        optional = {
            max_tokens = 256,
            stop = { '\n\n' },
        },
    },
}
```

</details>

### Non-OpenAI-FIM-Compatible APIs

For providers like **DeepInfra FIM**
(`https://api.deepinfra.com/v1/inference/`), refer to
[recipes.md](./recipes.md) for advanced configuration instructions.

# Commands

## `Minuet change_provider`, `Minuet change_model`

The `change_provider` command allows you to change the provider after `Minuet`
has been setup.

Example usage: `Minuet change_provider claude`

The `change_model` command allows you to change both the provider and model in
one command. When called without arguments, it will open an interactive
selection menu using `vim.ui.select` to choose from available models. When
called with an argument, the format is `provider:model`.

Example usage:

- `Minuet change_model` - Opens interactive model selection
- `Minuet change_model gemini:gemini-1.5-pro-latest` - Directly sets the model

Note: For `openai_compatible` and `openai_fim_compatible` providers, the model
completions in cmdline are determined by the `name` field in your
configuration. For example, if you configured:

```lua
provider_options.openai_compatible.name = 'Fireworks'
```

When entering `Minuet change_model openai_compatible:` in the cmdline,
you'll see model completions specific to the Fireworks provider.

## `Minuet change_preset`

The `change_preset` command allows you to switch between config presets that
were defined during initial setup. Presets provide a convenient way to toggle
between different config sets. This is particularly useful when you need to:

- Switch between different cloud providers (such as Fireworks or Groq) for the
  `openai_compatible` provider
- Apply different throttle and debounce settings for different providers

When called, the command merges the selected preset with the current config
table to create an updated configuration.

Usage syntax: `Minuet change_preset preset_1`

Presets can be configured during the initial setup process.

<details>

```lua
require('minuet').setup {
    presets = {
        preset_1 = {
            -- Configuration for cloud-based requests with large context window
            context_window = 20000,
            request_timeout = 4,
            throttle = 3000,
            debounce = 1000,
            provider = 'openai_compatible',
            provider_options = {
                openai_compatible = {
                    model = 'llama-3.3-70b-versatile',
                    api_key = 'GROQ_API_KEY',
                    name = 'Groq'
                }
            }
        },
        preset_2 = {
            -- Configuration for local model with smaller context window
            provider = 'openai_fim_compatible',
            context_window = 2000,
            throttle = 400,
            debounce = 100,
            provider_options = {
                openai_fim_compatible = {
                    api_key = 'TERM',
                    name = 'Ollama',
                    end_point = 'http://localhost:11434/v1/completions',
                    model = 'qwen2.5-coder:7b',
                    optional = {
                        max_tokens = 256,
                        top_p = 0.9
                    }
                }
            }
        }
    }
}
```

</details>

## `Minuet virtualtext`

Enable or disable the automatic display of `virtual-text` completion in the
**current buffer**.

Example usage: `Minuet virtualtext toggle`, `Minuet virtualtext enable`,
`Minuet virtualtext disable`.

# API

## Virtual Text

`minuet-ai.nvim` offers the following functions to customize your key mappings:

```lua
{
    -- accept whole completion
    require('minuet.virtualtext').action.accept,
    -- accept by line
    require('minuet.virtualtext').action.accept_line,
    -- accept one chunk (current identifier plus the special characters that
    -- follow it)
    require('minuet.virtualtext').action.accept_chunk,
    -- accept n lines (prompts for number)
    require('minuet.virtualtext').action.accept_n_lines,
    require('minuet.virtualtext').action.next,
    require('minuet.virtualtext').action.prev,
    require('minuet.virtualtext').action.dismiss,
    -- whether the virtual text is visible in current buffer
    require('minuet.virtualtext').action.is_visible,
}
```

## Minuet Event

### Standard Completion Events

- **MinuetRequestStartedPre**: Triggered before a completion request is
  initiated. This allows for pre-request operations, such as logging or updating
  the user interface.
- **MinuetRequestStarted**: Triggered immediately after the completion request
  is dispatched, signaling that the request is in progress.
- **MinuetRequestFinished**: Triggered upon completion of the request.

### Event Data

Each event includes a `data` field containing the following properties:

- `provider`: A string indicating the provider type (e.g.,
  'openai_compatible').
- `name`: A string specifying the provider's name (e.g., 'OpenAI', 'Groq',
  'Ollama').
- `model`: A string containing the model name (e.g., 'gemini-2.0-flash').
- `n_requests`: The number of requests encompassed in this completion cycle.
- `request_idx` (optional): The index of the current request, applicable when
  providers make multiple requests.
- `timestamp`: A Unix timestamp representing the start of the request cycle
  (corresponding to the `MinuetRequestStartedPre` event).

# FAQ

## Integration with `lazyvim`

Minuet's virtual text frontend needs no integration with lazyvim's completion
setup: add the plugin, call `require('minuet').setup { ... }`, and the ghost
text works alongside lazyvim as-is.

# Enhancement

## RAG (Experimental)

You can enhance the content sent to the LLM for code completion by leveraging
RAG support through the [VectorCode](https://github.com/Davidyz/VectorCode)
package.

VectorCode contains two main components. The first is a standalone CLI program
written in Python, available for installation via PyPI. This program is
responsible for creating the vector database and processing RAG queries. The
second component is a Neovim plugin that provides utility functions to send
queries and manage buffer-related RAG information within Neovim.

We offer two example recipes demonstrating VectorCode integration: one for
chat-based LLMs (Gemini) and another for the FIM model (Qwen-2.5-Coder),
available in [recipes.md](./recipes.md).

For detailed instructions on setting up and using VectorCode, please refer to the
[official VectorCode
documentation](https://github.com/Davidyz/VectorCode/tree/main/docs/neovim).

# Troubleshooting

If your setup failed, there are two most likely reasons:

1. You may set the API key incorrectly. Checkout the [API Key](#api-keys)
   section to see how to correctly specify the API key.
2. You are using a model or a context window that is too large, causing
   completion items to timeout before returning any tokens. This is
   particularly common with local LLM. It is recommended to start with the
   following settings to have a better understanding of your provider's inference
   speed.
   - Begin by testing with manual completions.
   - Use a smaller context window (e.g., `config.context_window = 768`)
   - Use a smaller model
   - Set a longer request timeout (e.g., `config.request_timeout = 5`)

To diagnose issues, set `config.notify = debug` and examine the output.

# Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

# Acknowledgement

- [continue.dev](https://www.continue.dev): not a neovim plugin, but I find a lot LLM models from here.
- [copilot.lua](https://github.com/zbirenbaum/copilot.lua): Reference for the virtual text frontend.
- [llama.vim](https://github.com/ggml-org/llama.vim): Reference for CLI parameters used to launch the llama-cpp server.
