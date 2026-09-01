# harmonize.nvim

Minimal, streaming-first AI tab completion for Neovim. Install it, point it at
your endpoint, and Tab completes your code in chunks — with the ghost text
revealed line by line and tokens streamed in as the model generates them.

> This is the rewritten plugin formerly known as minuet-ai.nvim. The rewrite
> lives on the `v2` branch of `Quinntyx/minuet-ai.nvim` while the repository is
> being renamed.

## Features

- **Virtual text only.** One frontend, no completion-menu integration to
  configure. Suggestions render inline as ghost text and refresh on every
  streaming token.
- **Chunk-wise Tab.** Tab accepts the completion one chunk at a time — the
  current identifier plus the special characters that follow it. `foo.bar(a,
  b).baz(c)` is accepted as `foo.` `bar(` `a, ` `b).` `baz(` `c)`.
- **Line-by-line reveals.** The single-line view shows only the remainder of
  the current line (or the line below, when the completion starts with a
  newline), and the rest stays cached so you can accept it one visible line at
  a time.
- **Token streaming.** Completions are live character streams: the model
  appends to the back up to the `max_tokens` cap while you take from the
  front by typing or pressing Tab. The first chunk appears almost
  immediately even on slow local models, and a high `max_tokens` no longer
  means a long wait.
- **Typing sync.** When your typed text matches the start of a suggestion, the
  completion tracks your typing instead of being discarded, avoiding
  unnecessary LLM requests.
- **Chat and FIM providers.** OpenAI, Claude, Gemini, Codestral, and any
  OpenAI-compatible chat service, or fill-in-the-middle endpoints (DeepSeek,
  Ollama, llama.cpp, and others). Switch between them at runtime.
- **No background binary.** Just `curl` and your preferred LLM provider.

## Requirements

- Neovim 0.10+
- An API key for at least one supported provider (or a local FIM server such
  as llama.cpp/Ollama)

## Installation

**Lazy.nvim** (repo path pending the GitHub rename):

```lua
{
    'Quinntyx/minuet-ai.nvim',
    branch = 'v2',
    config = function()
        require('harmonize').setup {
            -- your configuration here
        }
    end,
}
```

**Rocks.nvim**: `Rocks install harmonize.nvim`

## Quick Start

The fastest way to try it is the built-in quick start: it downloads a
llama.cpp binary and runs a local server for you (the model is pulled from
HuggingFace on the first start), then points the `openai_fim_compatible`
provider at it.

```lua
require('harmonize').setup {
    quick_start = true,
}
```

That defaults to Qwen2.5-Coder-1.5B (FIM-capable, ~1.6 GB, runs on CPU). Pass
a table to pick another model or tweak the server:

```lua
require('harmonize').setup {
    quick_start = {
        -- any HuggingFace GGUF repo, or a local .gguf path
        model = 'ggml-org/Qwen2.5-Coder-0.6B-Q4_K_M-GGUF',
        port = 8012, -- the endpoint becomes http://127.0.0.1:8012/v1/completions
    },
}
```

`quick_start` only takes over when the `openai_fim_compatible` endpoint is
still the cloud default: configure your own `end_point` and the server is left
to you. If `llama` or `llama-server` is already on PATH, it is used as is. The
first start downloads the model, so the first request may fail until it is
ready.

Prefer your own setup? Point the provider at a server you manage:

```lua
require('harmonize').setup {
    provider = 'openai_fim_compatible',
    context_window = 512, -- small for local inference; raise it if your machine keeps up
    provider_options = {
        openai_fim_compatible = {
            api_key = 'TERM', -- non-null placeholder; local servers ignore it
            name = 'Llama.cpp',
            end_point = 'http://localhost:8012/v1/completions',
            model = 'PLACEHOLDER', -- set by the llama.cpp server at launch
            optional = {
                max_tokens = 256, -- the stream cap; the first chunk arrives fast anyway
                top_p = 0.9,
            },
            -- llama.cpp has no suffix option in FIM, so embed the Qwen2.5-Coder
            -- FIM special tokens directly in the prompt.
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

Tab accepts the next chunk out of the box; see the keymap defaults below.
For cloud providers, see [Providers](#providers) and [API keys](#api-keys).

## Usage

The completion is a character stream: the model keeps appending tokens to the
back while you take from the front. The visible suggestion is always the part
you have not taken yet, and it is redrawn on every token.

- **Tab** (`accept_chunk`) accepts one chunk. A chunk walk consumes
  alphanumeric characters and underscores; the first special character
  switches to terminating mode, in which the next alphanumeric character ends
  the chunk. A newline ends the chunk unless it is the first character (the
  case in which the line below is shown). So `b)\n.c()` is accepted as `b)`,
  then `\n.`, then `c()`.
- By default, requests fire only after you actually type a character:
  arrow-key moves and scrolling only dismiss a stale suggestion, and entering
  insert mode alone does not trigger a request. Set
  `virtualtext.trigger_on_typing = false` for the old behavior.
- Typing the same characters keeps the remaining suggestion in sync; typing
  something different dismisses it and starts a fresh request.
- When a chunk would cross a newline in the middle, it stops first — you never
  accept text the view did not show.
- `accept_line` takes the whole visible line; `accept_n_lines` takes any
  number, prompting for a count.

### Keymaps

Defaults (`virtualtext.keymap`):

| Key | Action |
| --- | --- |
| `<Tab>` | accept one chunk |
| `<M-A>` | accept the whole completion |
| `<M-a>` | accept one line |
| `<M-z>` | accept n lines (prompts for count) |
| `<M-[>` | previous suggestion / manual invoke |
| `<M-]>` | next suggestion / manual invoke |
| `<M-e>` | dismiss |

All of them can be set to `nil` or rebound in `virtualtext.keymap`.

## Configuration

```lua
default_config = {
    virtualtext = {
        -- Filetypes for automatic ghost-text completion. Manual completion
        -- (`<M-[>` / `<M-]>`) still works in any filetype.
        auto_trigger_ft = {},
        -- Filetypes to exclude when auto_trigger_ft = { '*' }
        auto_trigger_ignore_ft = {},
        keymap = {
            accept = nil,
            accept_line = nil,
            accept_chunk = '<Tab>',
            accept_n_lines = nil,
            next = nil,
            prev = nil,
            dismiss = nil,
        },
        -- Keep the ghost text visible while another completion menu is open.
        show_on_completion_menu = false,
        -- Show only the remainder of the current line; when the completion
        -- starts with a newline, show the line below instead.
        display_singleline = true,
        -- Fire a request only after a character was typed. Arrow-key moves
        -- and scrolling dismiss the ghost text but never request, and
        -- entering insert mode alone does not trigger either.
        trigger_on_typing = true,
    },
    provider = 'openai_fim_compatible',
    -- Maximum characters of context before and after the cursor (~4 tokens
    -- per 100 chars for most LLMs).
    context_window = 16000,
    -- When the context exceeds the window, the ratio kept before the cursor.
    context_ratio = 0.75,
    throttle = 1000, -- only request every x ms; 0 disables
    debounce = 400, -- debounce requests by x ms; 0 disables
    -- false, "debug", "verbose", "warn", or "error"
    notify = 'warn',
    -- Request timeout in seconds. With streaming, a timeout cut keeps the
    -- partial text generated so far.
    request_timeout = 3,
    stream = true,
    curl_cmd = 'curl',
    curl_extra_args = {},
    -- Trim completion prefixes/suffixes that duplicate the surrounding text.
    -- 0 for FIM models (they emit intentional whitespace); 15 / 2 for chat.
    after_cursor_filter_length = function() end,
    before_cursor_filter_length = function() end,
    proxy = nil,
    -- A list of predicates; auto-completion fires only while all return true.
    enable_predicates = {},
    provider_options = {
        -- see the Providers section for each provider's defaults
    },
    -- Prompt specs for chat models; see the Prompt section.
    default_system = { ... },
    default_system_prefix_first = { ... },
    default_fim_template = { ... },
    default_few_shots = { ... },
    default_chat_input = { ... },
    default_few_shots_prefix_first = { ... },
    default_chat_input_prefix_first = { ... },
    -- Config sets for the `Harmonize change_preset` command
    presets = {},
    -- Download and run a local llama.cpp server automatically; see the
    -- Quick Start section. `false` disables it.
    quick_start = false,
}
```

## API keys

Set the environment variable named in each provider's `api_key` field:

- `OPENAI_API_KEY` for OpenAI
- `GEMINI_API_KEY` for Gemini
- `ANTHROPIC_API_KEY` for Claude
- `CODESTRAL_API_KEY` for Codestral
- A custom variable for OpenAI-compatible services (as configured)

Pass harmonize the **name** of the environment variable, not the value, or a
function returning the key:

```lua
require('harmonize').setup {
    provider_options = {
        openai_compatible = {
            api_key = 'FIREWORKS_API_KEY', -- reads the environment variable
            -- api_key = function() return 'sk-xxxx' end,
        },
    },
}
```

With Ollama or llama.cpp, assign any non-null environment variable (e.g.
`TERM`) as a placeholder.

## Prompt

See [prompt](./prompt.md) for the default prompts and how to customize them.
Harmonize uses two prompt systems: one for chat-based LLMs (OpenAI,
OpenAI-compatible, Claude, Gemini) and one for fill-in-the-middle models
(Codestral, OpenAI-FIM-compatible).

For chat models there are two construction styles: prefix-first (context
before the cursor first) and suffix-first. The defaults use prefix-first for
OpenAI, Gemini, and OpenAI-compatible, and suffix-first for Claude:

```lua
local config = require 'harmonize.config'

require('harmonize').setup {
    provider_options = {
        openai_compatible = {
            system = config.default_system_prefix_first,
            chat_input = config.default_chat_input_prefix_first,
            few_shots = config.default_few_shots_prefix_first,
        },
    },
}
```

## Providers

Set `provider` in the config; the default is `openai_fim_compatible`.

<details>
<summary>OpenAI</summary>

```lua
provider_options = {
    openai = {
        model = 'gpt-5.6-luna',
        end_point = 'https://api.openai.com/v1/chat/completions',
        stream = true,
        api_key = 'OPENAI_API_KEY',
        optional = {},
        transform = {}, -- functions rewriting the endpoint, headers, and body
    },
}
```

For GPT-5-series models, use `max_completion_tokens` (not `max_tokens`), the
models do not support `top_p`/`temperature`, and disable thinking with
`reasoning_effort = 'none'` (or `'minimal'`).

</details>

<details>
<summary>Claude</summary>

```lua
provider_options = {
    claude = {
        model = 'claude-haiku-4.5',
        end_point = 'https://api.anthropic.com/v1/messages',
        stream = true,
        api_key = 'ANTHROPIC_API_KEY',
        optional = {},
        transform = {},
    },
}
```

</details>

<details>
<summary>Codestral</summary>

Codestral is a completion model, not a chat model, so system prompts and
few-shot examples do not apply. Use `CODESTRAL_API_KEY` (not
`MISTRAL_API_KEY`); to use the Mistral endpoint, change `end_point` and
`api_key` accordingly.

```lua
provider_options = {
    codestral = {
        model = 'codestral-latest',
        end_point = 'https://codestral.mistral.ai/v1/fim/completions',
        api_key = 'CODESTRAL_API_KEY',
        stream = true,
        template = {
            prompt = "See [Prompt] section",
            suffix = "See [Prompt] section",
        },
        optional = {},
    },
}
```

</details>

<details>
<summary>Gemini</summary>

Register via Google AI Studio and get an API key from the [Google API
page](https://makersuite.google.com/app/apikey). Prefer `gemini-2.0-flash`
over the 2.5 series: similar output at significantly lower cost, without the
thinking mode that adds latency for no completion value.

```lua
provider_options = {
    gemini = {
        model = 'gemini-2.0-flash',
        end_point = 'https://generativelanguage.googleapis.com/v1beta/models',
        stream = true,
        api_key = 'GEMINI_API_KEY',
        optional = {},
        transform = {},
    },
}
```

To keep output small and disable thinking on 2.5/3.x models:

```lua
provider_options = {
    gemini = {
        optional = {
            generationConfig = {
                maxOutputTokens = 256,
                thinkingConfig = {
                    thinkingBudget = 0, -- 2.5 models
                    thinkingLevel = 'minimal', -- 3.x models
                },
            },
        },
    },
}
```

</details>

<details>
<summary>OpenAI-compatible</summary>

Any provider compatible with the OpenAI chat-completions API, e.g. Ollama at
`http://localhost:11434/v1/chat/completions`. If your service does not support
streaming, set `stream = false`.

```lua
provider_options = {
    openai_compatible = {
        model = 'deepseek/deepseek-v4-flash',
        end_point = 'https://openrouter.ai/api/v1/chat/completions',
        api_key = 'OPENROUTER_API_KEY',
        name = 'Openrouter',
        stream = true,
        optional = {},
        transform = {},
    },
}
```

Disabling thinking for reasoning models:

| Provider         | Configuration                                              |
| ---------------- | ---------------------------------------------------------- |
| **OpenRouter**   | `reasoning = { effort = 'none' }` (or `'minimal'`)         |
| **DeepSeek API** | `thinking = { type = 'disabled' }`                         |
| **Various**      | `reasoning_effort = 'none'`                                |

</details>

<details>
<summary>OpenAI-FIM-compatible</summary>

Any provider compatible with the OpenAI text `/completions` endpoint (not
`/chat/completions`), so system prompts and few-shot examples do not apply.
Examples: Ollama at `http://localhost:11434/v1/completions`, llama.cpp at
`http://localhost:8012/v1/completions`, DeepSeek's beta completions endpoint.

For Ollama, verify the model template supports FIM: `qwen2.5-coder` does;
`deepseek-coder` does not — use `deepseek-coder-v2` instead.

```lua
provider_options = {
    openai_fim_compatible = {
        model = 'deepseek-v4-flash',
        end_point = 'https://api.deepseek.com/beta/completions',
        api_key = 'DEEPSEEK_API_KEY',
        name = 'Deepseek',
        stream = true,
        template = {
            prompt = "See [Prompt] section for the default value",
            suffix = "See [Prompt] section for the default value",
        },
        transform = {},
        optional = {},
    },
}
```

Special FIM tokens vary by model; the llama.cpp example at the top of this
README uses the Qwen2.5-Coder tokens. For llama.cpp launch scripts tuned to
your hardware, and for FIM providers that are not OpenAI-compatible (such as
DeepInfra), see [recipes.md](./recipes.md).

</details>

## Selecting a provider or model

`gemini-2.0-flash` and `codestral` give high-quality output with free, fast
processing; `deepseek-v4-flash` on the FIM provider is cheap and fast for
remote APIs. Locally, `qwen-2.5-coder` (via Ollama or llama.cpp) is a good
default. Avoid thinking models — the extra latency hurts completion even on
fast models.

Latency (time to first token) matters more than throughput for completion.
Ideally latency stays under ~1s with throughput above ~100 tokens/s. For local
models, llama.cpp supports raw FIM via its `/v1/completions` endpoint.

## Commands

- `Harmonize change_provider <name>` — switch the active provider.
- `Harmonize change_model [provider:model]` — with no argument, opens
  `vim.ui.select` over the models in `modelcard`; otherwise sets
  `provider:model` directly.
- `Harmonize change_preset <preset>` — merge a preset defined at setup into
  the current config.
- `Harmonize virtualtext enable|disable|toggle` — control automatic ghost-text
  completion in the current buffer.

## API

```lua
{
    require('harmonize.virtualtext').action.accept, -- accept whole completion
    require('harmonize.virtualtext').action.accept_line,
    require('harmonize.virtualtext').action.accept_chunk,
    require('harmonize.virtualtext').action.accept_n_lines,
    require('harmonize.virtualtext').action.next,
    require('harmonize.virtualtext').action.prev,
    require('harmonize.virtualtext').action.dismiss,
    require('harmonize.virtualtext').action.is_visible,
}
```

### Events

Harmonize fires `User` events before/after each completion request; statusline
integrations can subscribe to them:

- **HarmonizeRequestStartedPre** — before a request is initiated.
- **HarmonizeRequestStarted** — after a request is dispatched.
- **HarmonizeRequestFinished** — when the request completes.

Each event carries a `data` field with `provider`, `name`, `model`,
`n_requests`, `request_idx` (optional), and `timestamp`.

## FAQ

### Integration with lazyvim

Harmonize's virtual text needs no integration with lazyvim's completion setup:
add the plugin, call `require('harmonize').setup { ... }`, and the ghost text
works alongside lazyvim as-is.

### RAG (experimental)

You can enrich the context sent to the LLM with RAG via the
[VectorCode](https://github.com/Davidyz/VectorCode) package — see
[recipes.md](./recipes.md) for chat (Gemini) and FIM (Qwen-2.5-Coder)
examples.

## Troubleshooting

Most failures come from two things:

1. A misconfigured API key — see [API keys](#api-keys).
2. A model or context window too slow for the request to finish — start with a
   small context window (e.g. `context_window = 768`), a smaller model, and a
   longer `request_timeout` (e.g. 5), then raise them as you measure inference
   speed.

Set `config.notify = "debug"` to diagnose.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Acknowledgement

- [continue.dev](https://www.continue.dev): not a neovim plugin, but a great source of LLM models.
- [copilot.lua](https://github.com/zbirenbaum/copilot.lua): reference for the virtual text frontend.
- [llama.vim](https://github.com/ggml-org/llama.vim): reference for CLI parameters used to launch the llama-cpp server.