# harmonize.nvim

Streaming AI tab completion for Neovim, rewritten from
[minuet-ai.nvim](https://github.com/milanglacier/minuet-ai.nvim). Point it at
an endpoint and Tab completes in chunks, with the ghost text revealed line by
line as the model generates tokens.

## Features

- Virtual text frontend: suggestions render as ghost text inline and refresh
  on every streaming token. No completion-menu integration to configure.
- Chunk-wise acceptance: Tab accepts one chunk at a time (the current
  identifier plus the special characters that follow it), so long completions
  arrive in reviewable steps.
- Single-line display: the ghost shows the rest of the current line (or the
  line below when the completion starts with a newline); the rest stays
  cached for further acceptance.
- Token streaming: the completion is a character stream — the model appends
  to the back while typing and Tab take from the front, so the first chunk
  appears quickly even on slow local models.
- Typing sync: when typed text matches the start of the suggestion, the
  suggestion advances instead of being discarded and re-requested.
- `llama_cpp` provider for llama.cpp's native `/infill` endpoint, with
  optional automatic server startup, and `openai_fim_compatible` for any
  OpenAI FIM-compatible service. Other providers inherited from
  minuet-ai.nvim are present but untested.

## Requirements

- Neovim 0.10+
- `curl`
- A completion backend: a llama.cpp server (the `llama_cpp` provider can
  start one for you) or an OpenAI FIM-compatible endpoint

## Installation

**lazy.nvim**:

```lua
{
    'Quinntyx/harmonize.nvim',
    config = function()
        require('harmonize').setup {
            -- see the sample config below
        }
    end,
}
```

## Quick Start

The fastest way to get a local model running is the `llama_cpp` provider with
`auto_start`: it downloads a llama.cpp binary if needed, starts `llama serve`
for you (the model is pulled from HuggingFace on the first start), and points
the provider's `/infill` endpoint at it.

```lua
require('harmonize').setup {
    provider = 'llama_cpp',
}
```

That defaults to Qwen2.5-Coder-1.5B (FIM-capable, ~1.6 GB) on
`127.0.0.1:8012`. The server is configured on `auto_start`:

```lua
require('harmonize').setup {
    provider = 'llama_cpp',
    auto_start = {
        -- any HuggingFace GGUF repo, or a local .gguf path
        model = 'ggml-org/Qwen2.5-Coder-0.6B-Q4_K_M-GGUF',
        host = '127.0.0.1',
        port = 8012,
        -- extra arguments in the style of curl_extra_args (GPU offload,
        -- context size, ...)
        extra_args = { '-ngl', '99', '--ctx-size', '8192' },
    },
}
```

Keep `provider_options.llama_cpp.end_point` in sync with the host and port;
the defaults already agree.

If `llama` or `llama-server` is already on PATH, it is used as is; otherwise
one is downloaded. The first start downloads the model, so the first request
may fail until it is ready.

By default the server keeps running after nvim exits, so the next launch
reuses it without reloading the model. Set `kill_on_exit = true` on
`auto_start` to stop it when nvim exits — but with
several nvim instances sharing one server, the first one to exit would kill
it for everyone.

Prefer your own setup? Set `auto_start = nil` and point the provider at a
server you manage — you still get llama.cpp's native `/infill` endpoint,
which constructs the FIM prompt from the model's own tokens (no per-model
template needed):

```lua
require('harmonize').setup {
    provider = 'llama_cpp',
    auto_start = nil,
    provider_options = {
        llama_cpp = {
            end_point = 'http://localhost:8012/infill',
            optional = {
                n_predict = 256, -- the stream cap; the first chunk arrives fast anyway
                top_p = 0.9,
            },
        },
    },
}
```

Tab accepts the next chunk out of the box; see the keymap defaults below.
For cloud providers, see [Providers](#providers) and [API keys](#api-keys).

## Sample config

A complete llama.cpp setup. Every field is filled in, so edit the values
rather than starting from scratch — harmonize deep-merges your config over
its defaults, so omitting a field keeps the default.

```lua
require('harmonize').setup {
    provider = 'llama_cpp',

    -- What the ghost text shows: 'line' shows the rest of the current line
    -- (or the line below when the completion starts with a newline);
    -- 'chunk' shows exactly the next chunk Tab will accept.
    display = 'line',
    -- When requests fire: 'on_type' only after a character is typed,
    -- 'on_insert' on any pause in insert mode.
    completion_trigger = 'on_type',
    -- Filetypes where auto-completion fires; use { '*' } for all. Manual
    -- completion (keymap.trigger) works everywhere either way.
    auto_trigger_ft = { 'lua', 'python', 'rust' },
    -- Filetypes to skip when auto_trigger_ft contains '*'.
    auto_trigger_ignore_ft = {},

    keymap = {
        accept = '<Tab>',      -- accept one chunk
        accept_line = '<M-a>', -- accept the visible line
        dismiss = '<M-e>',     -- dismiss the ghost text
        trigger = '<M-]>',     -- request a completion now
        toggle = '<M-c>',      -- toggle auto-completion on and off
    },

    -- Server startup for the llama_cpp provider: when nothing answers at
    -- host:port, harmonize runs the command below with the model and leaves
    -- the server running when nvim exits. Set auto_start = nil to run the
    -- server yourself and keep provider_options.llama_cpp.end_point pointed
    -- at it.
    auto_start = {
        cmd = 'llama serve', -- binary looked up on PATH; downloaded when missing
        model = 'ggml-org/Qwen2.5-Coder-1.5B-Q8_0-GGUF', -- HF repo or local .gguf path
        extra_args = { '-ngl', '99', '--ctx-size', '8192' },
        kill_on_exit = false,
        host = '127.0.0.1', -- keep end_point in sync with these two
        port = 8012,
    },

    provider_options = {
        llama_cpp = {
            end_point = 'http://127.0.0.1:8012/infill',
            -- api_key = 'LLAMA_API_KEY', -- only for servers run with --api-key
            name = 'llama.cpp',
            stream = true,
            -- Extra JSON fields for the /infill request body.
            optional = { n_predict = 256, top_p = 0.9 },
            transform = {},
        },
    },

    -- Maximum characters of context before and after the cursor
    -- (~4000 tokens at 16000 characters).
    context_window = 16000,
    -- When the context exceeds the window, the share kept before the cursor
    -- (0.75 means a 3:1 before/after split).
    context_ratio = 0.75,
    -- Minimum milliseconds between requests; 0 disables.
    throttle = 0,
    -- Milliseconds to wait after typing stops before requesting; 0 disables.
    debounce = 200,
    -- Request timeout in seconds. With streaming, a timeout cut keeps the
    -- partial text generated so far.
    request_timeout = 3,
    -- false, "debug", "verbose", "warn", or "error".
    notify = 'warn',
    curl_cmd = 'curl',
    curl_extra_args = {},
    -- A proxy URL passed to curl as --proxy, or nil.
    proxy = nil,
    -- Auto-completion fires only while every predicate returns true.
    enable_predicates = {},
    -- llama_cpp and openai_fim_compatible are the tested providers; others
    -- warn on setup unless this is true.
    allow_unsupported_providers = false,
}
```

## Usage

The completion is a character stream: the model keeps appending tokens to the
back while you take from the front. The visible suggestion is always the part
you have not taken yet, and it is redrawn on every token.

- **Tab** (`accept`) accepts one chunk. A chunk walk consumes
  alphanumeric characters and underscores; the first special character
  switches to terminating mode, in which the next alphanumeric character ends
  the chunk. A newline ends the chunk unless it is the first character (the
  case in which the line below is shown). So `b)\n.c()` is accepted as `b)`,
  then `\n.`, then `c()`.
- By default, requests fire only after you actually type a character:
  arrow-key moves and scrolling only dismiss a stale suggestion, and entering
  insert mode alone does not trigger a request. Set
  `completion_trigger = 'on_insert'` for the old behavior.
- `display = 'chunk'` shows only the next chunk in the ghost text — exactly
  what Tab will complete — instead of the rest of the current line.
- Typing the same characters keeps the remaining suggestion in sync; typing
  something different dismisses it and starts a fresh request.
- When a chunk would cross a newline in the middle, it stops first — you never
  accept text the view did not show.
- `accept_line` takes the whole visible line.
- A `toggle` keymap switches automatic completion on and off (same as
  `:Harmonize virtualtext toggle`).
- `action.trigger` requests a completion on demand — useful in `'on_type'`
  mode after navigating somewhere; bind it in `keymap` if you want a key.

### Keymaps

Only `<Tab>` is bound by default — it accepts one chunk. The other actions
are unbound and can be wired through `keymap`: `accept_line` (accept the
visible line), `dismiss`, `trigger` (manually request a completion), and
`toggle` (toggle auto-completion).

## Configuration

```lua
default_config = {
    -- Filetypes for automatic ghost-text completion. Manual completion
    -- still works in any filetype.
    auto_trigger_ft = {},
    -- Filetypes to exclude when auto_trigger_ft = { '*' }
    auto_trigger_ignore_ft = {},
    keymap = {
        -- accept one chunk: the current identifier plus the special
        -- characters that follow it
        accept = '<Tab>',
        -- accept the visible line
        accept_line = nil,
        -- dismiss the ghost text
        dismiss = nil,
        -- manually request a completion
        trigger = nil,
        -- toggle auto-completion on and off
        toggle = nil,
    },
    -- What the ghost text shows: 'line' shows the rest of the current line
    -- shows only the next chunk, exactly what the accept keymap will
    -- complete.
    display = 'line',
    -- When requests fire: 'on_type' only after a character was typed,
    -- 'on_insert' on any pause in insert mode.
    completion_trigger = 'on_type',
    provider = 'openai_fim_compatible',
    -- Only llama_cpp and openai_fim_compatible are tested. Other
    -- providers warn on setup unless this is true.
    allow_unsupported_providers = false,
    -- Maximum characters of context before and after the cursor (~4 tokens
    -- per 100 chars for most LLMs).
    context_window = 16000,
    -- When the context exceeds the window, the ratio kept before the cursor.
    context_ratio = 0.75,
    throttle = 0, -- only request every x ms; 0 disables
    debounce = 200, -- debounce requests by x ms; 0 disables
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
    -- Start (or reuse) a llama.cpp server for the llama_cpp provider;
    -- see the Quick Start section. Set to nil to run the server yourself.
    auto_start = { ... },
    provider_options = {
        -- see the Quick Start section for llama_cpp and the Providers
        -- section for the other providers' defaults
        llama_cpp = { ... },
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

With Ollama, assign any non-null environment variable (e.g. `TERM`) as a
placeholder. The `llama_cpp` provider needs no API key; set `api_key` only
when your server runs with `--api-key`.

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

Only `llama_cpp` (see [Quick Start](#quick-start)) and
`openai_fim_compatible` are tested and maintained. The providers below are
kept for compatibility with minuet-ai.nvim configs but are untested, because
their paid APIs are not available for testing; using one shows a warning on
setup unless `allow_unsupported_providers = true`.

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
Examples: Ollama at `http://localhost:11434/v1/completions`, DeepSeek's beta
completions endpoint. For llama.cpp prefer the native `llama_cpp` provider
(see [Quick Start](#quick-start)), which uses the `/infill` endpoint.

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
models, the `llama_cpp` provider uses llama.cpp's native `/infill` endpoint.

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
    require('harmonize.virtualtext').action.accept, -- accept one chunk
    require('harmonize.virtualtext').action.accept_line,
    require('harmonize.virtualtext').action.dismiss,
    require('harmonize.virtualtext').action.trigger, -- manually request a completion
    require('harmonize.virtualtext').action.toggle_auto_trigger, -- toggle auto-completion
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