local default_prompt_prefix_first = [[
You are an AI code completion engine. Provide contextually appropriate completions:
- Code completions in code context
- Comment/documentation text in comments
- String content in string literals
- Prose in markdown/documentation files

Input markers:
- `<contextAfterCursor>`: Context after cursor
- `<cursorPosition>`: Current cursor location
- `<contextBeforeCursor>`: Context before cursor
]]

local default_prompt = default_prompt_prefix_first
    .. [[

Note that the user input will be provided in **reverse** order: first the
context after cursor, followed by the context before cursor.
]]

local default_guidelines = [[
Guidelines:
1. Offer completions after the `<cursorPosition>` marker.
2. Make sure you have maintained the user's existing whitespace and indentation.
   This is REALLY IMPORTANT!
3. Provide multiple completion options when possible.
4. Return completions separated by the marker <endCompletion>.
5. The returned message will be further parsed and processed. DO NOT include
   additional comments or markdown code block fences. Return the result directly.
6. Keep each completion option concise, limiting it to a single line or a few lines.
7. Create entirely new code completion that DO NOT REPEAT OR COPY any user's existing code around <cursorPosition>.]]

local default_few_shots = {
    {
        role = 'user',
        content = [[
# language: javascript
<contextAfterCursor>
    return result;
}

const processedData = transformData(rawData, {
    uppercase: true,
    removeSpaces: false
});
<contextBeforeCursor>
function transformData(data, options) {
    const result = [];
    for (let item of data) {
        <cursorPosition>]],
    },
    {
        role = 'assistant',
        content = [[
let processed = item;
        if (options.uppercase) {
            processed = processed.toUpperCase();
        }
        if (options.removeSpaces) {
            processed = processed.replace(/\s+/g, '');
        }
        result.push(processed);
    }
<endCompletion>
if (typeof item === 'string') {
            let processed = item;
            if (options.uppercase) {
                processed = processed.toUpperCase();
            }
            if (options.removeSpaces) {
                processed = processed.replace(/\s+/g, '');
            }
            result.push(processed);
        } else {
            result.push(item);
        }
    }
<endCompletion>
]],
    },
}

local default_few_shots_prefix_first = {
    {
        role = 'user',
        content = [[
# language: javascript
<contextBeforeCursor>
function transformData(data, options) {
    const result = [];
    for (let item of data) {
        <cursorPosition>
<contextAfterCursor>
    return result;
}

const processedData = transformData(rawData, {
    uppercase: true,
    removeSpaces: false
});]],
    },
    default_few_shots[2],
}

local n_completion_template = '8. Provide at most %d completion items.'

-- use {{{ and }}} to wrap placeholders, which will be further processesed in other function
local default_system_template = '{{{prompt}}}\n{{{guidelines}}}\n{{{n_completion_template}}}'

local default_fim_prompt = function(context_before_cursor, _, _)
    local utils = require 'harmonize.utils'
    local language = utils.add_language_comment()
    local tab = utils.add_tab_comment()
    context_before_cursor = language .. '\n' .. tab .. '\n' .. context_before_cursor

    return context_before_cursor
end

local default_fim_suffix = function(_, context_after_cursor, _)
    return context_after_cursor
end

local function default_after_cursor_filter_length()
    local config = require('harmonize').config
    return (config.provider == 'codestral' or config.provider == 'openai_fim_compatible') and 0 or 15
end

local function default_before_cursor_filter_length()
    local config = require('harmonize').config
    return (config.provider == 'codestral' or config.provider == 'openai_fim_compatible') and 0 or 2
end

---@class harmonize.ChatInputExtraInfo
---@field is_incomplete_before boolean
---@field is_incomplete_after boolean

---@alias harmonize.ChatInputFunction fun(context_before_cursor: string, context_after_cursor: string, opts: harmonize.ChatInputExtraInfo): string
---@alias harmonize.FIMTemplateFunction harmonize.ChatInputFunction

--- Configuration for formatting chat input to the LLM
---@class harmonize.ChatInput
---@field template string Template string with placeholders for context parts
---@field language harmonize.ChatInputFunction function to add language comment based on filetype
---@field tab harmonize.ChatInputFunction function to add indentation style comment
---@field context_before_cursor harmonize.ChatInputFunction function to process text before cursor
---@field context_after_cursor harmonize.ChatInputFunction function to process text after cursor

---@type harmonize.ChatInput
local default_chat_input = {
    template = '{{{language}}}\n{{{tab}}}\n<contextAfterCursor>\n{{{context_after_cursor}}}\n<contextBeforeCursor>\n{{{context_before_cursor}}}<cursorPosition>',
    language = function(_, _, _)
        local utils = require 'harmonize.utils'
        return utils.add_language_comment()
    end,
    tab = function(_, _, _)
        local utils = require 'harmonize.utils'
        return utils.add_tab_comment()
    end,
    context_before_cursor = function(context_before_cursor, _, opts)
        if opts.is_incomplete_before then
            -- Remove first line when context is incomplete at start
            local _, rest = context_before_cursor:match '([^\n]*)\n(.*)'
            return rest or context_before_cursor
        end
        return context_before_cursor
    end,
    context_after_cursor = function(_, context_after_cursor, opts)
        if opts.is_incomplete_after then
            -- Remove last line when context is incomplete at end
            local content = context_after_cursor:match '(.*)[\n][^\n]*$'
            return content or context_after_cursor
        end
        return context_after_cursor
    end,
}

---@type harmonize.ChatInput
local default_chat_input_prefix_first = vim.deepcopy(default_chat_input)
default_chat_input_prefix_first.template =
    '{{{language}}}\n{{{tab}}}\n<contextBeforeCursor>\n{{{context_before_cursor}}}<cursorPosition>\n<contextAfterCursor>\n{{{context_after_cursor}}}'

local M = {
    -- Filetypes where automatic completion is enabled, e.g.
    -- { 'python', 'lua' }. Manual completion still works everywhere.
    auto_trigger_ft = {},
    -- Filetypes where automatic completion stays off, useful when
    -- auto_trigger_ft = { '*' }.
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
    -- What the ghost text shows. 'line' shows the rest of the current line,
    -- or the line below the cursor when the completion starts with a
    -- newline. 'chunk' shows only the next chunk, exactly what the
    -- accept keymap will complete.
    ---@type 'line' | 'chunk'
    display = 'line',
    -- When requests fire. 'on_type' requests only after a character was
    -- typed: arrow-key moves and scrolling dismiss the ghost text without
    -- requesting, and entering insert mode alone does not trigger either.
    -- 'on_insert' is the old behavior: any pause in insert mode triggers.
    ---@type 'on_type' | 'on_insert'
    completion_trigger = 'on_type',
    provider = 'openai_fim_compatible',
    -- Only llama_cpp_managed and openai_fim_compatible are tested. Other
    -- providers are kept for compatibility and warn on setup unless this is
    -- true.
    allow_unsupported_providers = false,
    -- the maximum total characters of the context before and after the cursor
    -- 16000 characters typically equate to approximately 4,000 tokens for
    -- LLMs.
    context_window = 16000,
    -- when the total characters exceed the context window, the ratio of
    -- context before cursor and after cursor, the larger the ratio the more
    -- context before cursor will be used. This option should be between 0 and
    -- 1, context_ratio = 0.75 means the ratio will be 3:1.
    context_ratio = 0.75,
    throttle = 0, -- only send the request every x milliseconds, use 0 to disable throttle.
    -- debounce the request in x milliseconds, set to 0 to disable debounce
    debounce = 200,
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
    ---@type string[] | fun(): string[]
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
    after_cursor_filter_length = default_after_cursor_filter_length,
    -- Similar to after_cursor_filter_length but trim the completion item from
    -- prefix instead of suffix.
    before_cursor_filter_length = default_before_cursor_filter_length,
    proxy = nil,
}

M.default_system = {
    template = default_system_template,
    prompt = default_prompt,
    guidelines = default_guidelines,
    n_completion_template = n_completion_template,
}

M.default_system_prefix_first = {
    template = default_system_template,
    prompt = default_prompt_prefix_first,
    guidelines = default_guidelines,
    n_completion_template = n_completion_template,
}

M.default_chat_input = default_chat_input
M.default_chat_input_prefix_first = default_chat_input_prefix_first

M.default_few_shots = default_few_shots
M.default_few_shots_prefix_first = default_few_shots_prefix_first

--- Configuration for FIM template
---@class harmonize.FIMTemplate
---@field prompt harmonize.FIMTemplateFunction
---@field suffix harmonize.FIMTemplateFunction | boolean

---@type harmonize.FIMTemplate
M.default_fim_template = {
    prompt = default_fim_prompt,
    suffix = default_fim_suffix,
}

M.provider_options = {
    llama_cpp_managed = {
        -- The HuggingFace GGUF repo (or a local .gguf file path) hosted by
        -- the managed llama.cpp server.
        model = 'ggml-org/Qwen2.5-Coder-1.5B-Q8_0-GGUF',
        host = '127.0.0.1',
        port = 8012,
        -- Extra flags appended verbatim to the `llama serve` command, for
        -- everything the options above do not cover (GPU offload, context
        -- size, batch sizes, ...), e.g. '-ngl 99 --ctx-size 8192'.
        llama_cpp_flags = '',
        -- Stop the managed server when nvim exits. Off by default so the
        -- server is left running and the next nvim launch reuses it without
        -- reloading the model.
        kill_on_exit = false,
    },
    codestral = {
        model = 'codestral-latest',
        end_point = 'https://codestral.mistral.ai/v1/fim/completions',
        api_key = 'CODESTRAL_API_KEY',
        stream = true,
        template = M.default_fim_template,
        optional = {
            stop = nil, -- the identifier to stop the completion generation
            max_tokens = nil,
        },
        -- a list of functions to transform the endpoint, header, and request body
        transform = {},
        -- Custom function to extract LLM-generated text from JSON output
        get_text_fn = {},
    },
    openai = {
        model = 'gpt-5.6-luna',
        api_key = 'OPENAI_API_KEY',
        end_point = 'https://api.openai.com/v1/chat/completions',
        system = M.default_system_prefix_first,
        few_shots = M.default_few_shots_prefix_first,
        chat_input = M.default_chat_input_prefix_first,
        stream = true,
        optional = {
            stop = nil,
            max_tokens = nil,
        },
        -- a list of functions to transform the endpoint, header, and request body
        transform = {},
    },
    claude = {
        max_tokens = 256,
        api_key = 'ANTHROPIC_API_KEY',
        model = 'claude-haiku-4-5',
        end_point = 'https://api.anthropic.com/v1/messages',
        system = M.default_system,
        chat_input = M.default_chat_input,
        few_shots = M.default_few_shots,
        stream = true,
        optional = {
            stop_sequences = nil,
        },
        -- a list of functions to transform the endpoint, header, and request body
        transform = {},
    },
    openai_compatible = {
        model = 'deepseek/deepseek-v4-flash',
        system = M.default_system_prefix_first,
        chat_input = M.default_chat_input_prefix_first,
        few_shots = M.default_few_shots_prefix_first,
        end_point = 'https://openrouter.ai/api/v1/chat/completions',
        api_key = 'OPENROUTER_API_KEY',
        name = 'Openrouter',
        stream = true,
        optional = {
            stop = nil,
            max_tokens = nil,
        },
        -- a list of functions to transform the endpoint, header, and request body
        transform = {},
    },
    gemini = {
        model = 'gemini-2.0-flash',
        api_key = 'GEMINI_API_KEY',
        end_point = 'https://generativelanguage.googleapis.com/v1beta/models',
        system = M.default_system_prefix_first,
        chat_input = M.default_chat_input_prefix_first,
        few_shots = M.default_few_shots_prefix_first,
        stream = true,
        optional = {},
        -- a list of functions to transform the endpoint, header, and request body
        transform = {},
    },
    openai_fim_compatible = {
        model = 'deepseek-v4-flash',
        end_point = 'https://api.deepseek.com/beta/completions',
        api_key = 'DEEPSEEK_API_KEY',
        name = 'Deepseek',
        stream = true,
        template = M.default_fim_template,
        optional = {
            stop = nil,
            max_tokens = nil,
        },
        -- a list of functions to transform the endpoint, header, and request body
        transform = {},
        -- Custom function to extract LLM-generated text from JSON output
        get_text_fn = {},
    },
}


M.presets = {}

-- **List** of functions to execute. If any function returns `false`, Harmonize
-- will not trigger auto-completion. Manual completion can still be invoked,
-- even if these functions evaluate to `false`, when using virtual text
-- (excluding LSP).
-- Note that this is called each time Harmonize attempts to trigger
-- auto-completion, so ensure the functions in this list are highly efficient.
---@type (fun(): boolean)[]
M.enable_predicates = {}

return M
