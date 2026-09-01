-- Downloads and runs a local llama.cpp server for the openai_fim_compatible
-- provider, so a first-time setup needs no manual server management.
--
-- Enabled with `quick_start = true` (or a table with overrides) in setup.
-- This module only manages the server when the provider still points at the
-- cloud default endpoint: as soon as you configure your own end_point, the
-- server is left to you and nothing here touches it.
local M = {}

local data_dir = vim.fn.stdpath('data') .. '/harmonize'

local defaults = {
    -- HuggingFace repo (or a local GGUF file path) passed to llama.cpp.
    model = 'ggml-org/Qwen2.5-Coder-1.5B-Q8_0-GGUF',
    host = '127.0.0.1',
    port = 8012,
    context_size = 0, -- 0 = model default (all of it)
    n_gpu_layers = 99,
    batch = 1024,
    ubatch = 1024,
    cache_reuse = 256,
    -- llama.cpp release tag for the downloaded binaries. nil resolves the
    -- newest tag still shipping Linux binaries.
    release = nil,
}

-- Release tags before the v0.x scheme published one zip per platform; the
-- v0.x tags carry no binary assets. When the GitHub API is unreachable this
-- pinned tag is used instead.
local fallback_release = 'b4600'

function M.normalize(qs)
    if qs == true then
        qs = {}
    end
    qs = vim.tbl_deep_extend('force', defaults, qs or {})
    return qs
end

-- The llama.cpp binary: an installed one wins, otherwise the downloaded
-- release in the data directory.
function M.resolve_binary()
    for _, name in ipairs { 'llama', 'llama-server' } do
        if vim.fn.executable(name) == 1 then
            return name
        end
    end
    for _, rel in ipairs { '/llama.cpp/*/bin/llama', '/llama.cpp/*/bin/llama-server' } do
        local match = vim.fn.glob(data_dir .. rel)
        if match ~= '' then
            return match
        end
    end
    return nil
end

local function has_curl()
    return vim.fn.executable 'curl' == 1
end

-- Newest tag whose Ubuntu x64 asset still exists; `nil` when the API cannot
-- be reached (the caller falls back to the pinned tag).
function M.latest_release_tag()
    if not has_curl() then
        return nil
    end
    local ok_handle, handle_or_err = pcall(vim.system, {
        'curl',
        '-fsSL',
        '--max-time',
        '10',
        'https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=20',
    }, { text = true })
    if not ok_handle then
        return nil
    end
    local result = handle_or_err:wait()
    if result.code ~= 0 then
        return nil
    end
    local ok_parse, releases = pcall(vim.json.decode, result.stdout)
    if not ok_parse or type(releases) ~= 'table' then
        return nil
    end
    for _, release in ipairs(releases) do
        local tag = release.tag_name
        if type(tag) == 'string' and tag:match '^b%d+$' then
            for _, asset in ipairs(release.assets or {}) do
                if type(asset.name) == 'string' and asset.name:match '^llama%-b%d+%-bin%-ubuntu%-x64%.zip$' then
                    return tag
                end
            end
        end
    end
    return nil
end

-- Downloads the llama.cpp release zip and unpacks it into the data
-- directory, then calls `then_fn`.
function M.download_binary(version, then_fn)
    local dest_dir = data_dir .. '/llama.cpp/' .. version
    local zip_path = vim.fn.tempname() .. '.zip'

    if vim.fn.filereadable(dest_dir .. '/llama') == 1 then
        then_fn()
        return
    end

    if vim.fn.executable 'unzip' ~= 1 then
        vim.notify('llama.cpp not found and `unzip` is missing; install it or put `llama` on PATH', vim.log.levels.ERROR)
        return
    end

    if not has_curl() then
        vim.notify(
            'llama.cpp not found and `curl` is missing; install it or put `llama` on PATH',
            vim.log.levels.ERROR
        )
        return
    end

    local url = ('https://github.com/ggml-org/llama.cpp/releases/download/%s/llama-%s-bin-ubuntu-x64.zip')
        :format(version, version)

    vim.notify('Downloading llama.cpp ' .. version .. ' (' .. url .. ')', vim.log.levels.INFO)
    vim.system({ 'curl', '-fL', '--retry', '2', '-o', zip_path, url }, nil, function(out)
        if out.code ~= 0 then
            vim.notify('llama.cpp download failed (' .. out.code .. '); remove ' .. zip_path .. ' on retry', vim.log.levels.ERROR)
            return
        end
        vim.system({ 'unzip', '-q', '-o', zip_path, '-d', dest_dir }, nil, function(unzip_out)
            vim.uv.fs_unlink(zip_path)
            if unzip_out.code ~= 0 then
                vim.notify('llama.cpp download failed to unzip', vim.log.levels.ERROR)
                return
            end
            vim.notify('llama.cpp ' .. version .. ' installed in ' .. dest_dir, vim.log.levels.INFO)
            then_fn()
        end)
    end)
end

---Build the server command: unified `llama serve` vs `llama-server`, and the
---HF repo vs a local GGUF file for the model.
---@param binary string
---@param qs table normalized quick_start options
---@return string[]
function M.server_args(binary, qs)
    local args = {}
    if vim.fn.fnamemodify(binary, ':t') == 'llama' then
        table.insert(args, 'serve')
    end

    if qs.model:match '^[^/]+/[^/]+$' then
        table.insert(args, '-hf')
        table.insert(args, qs.model)
    else
        table.insert(args, '--model')
        table.insert(args, qs.model)
    end

    table.insert(args, '--host')
    table.insert(args, qs.host)
    table.insert(args, '--port')
    table.insert(args, tostring(qs.port))
    table.insert(args, '-ngl')
    table.insert(args, tostring(qs.n_gpu_layers))
    table.insert(args, '--ctx-size')
    table.insert(args, tostring(qs.context_size))
    table.insert(args, '-b')
    table.insert(args, tostring(qs.batch))
    table.insert(args, '-ub')
    table.insert(args, tostring(qs.ubatch))
    table.insert(args, '--cache-reuse')
    table.insert(args, tostring(qs.cache_reuse))
    return args
end

---@param config table the merged harmonize config
---@param qs table normalized quick_start options
---@return boolean? true when the provider was pointed at the local server
function M.wire_provider(config, qs)
    local fim = config.provider_options.openai_fim_compatible
    local pristine = vim.deepcopy(require 'harmonize.config')
        .provider_options.openai_fim_compatible

    if fim.end_point ~= pristine.end_point then
        -- A custom endpoint means the user runs their own server.
        return false
    end

    fim.end_point = ('http://%s:%d/v1/completions'):format(qs.host, qs.port)
    fim.api_key = 'TERM'
    fim.model = qs.model:match '[^/]+$'
    if qs.model:lower():find 'qwen' then
        -- llama.cpp has no suffix option in FIM; embed the Qwen2.5-Coder
        -- special tokens directly in the prompt.
        fim.template = {
            prompt = function(context_before_cursor, context_after_cursor, _)
                return '<|fim_prefix|>'
                    .. context_before_cursor
                    .. '<|fim_suffix|>'
                    .. context_after_cursor
                    .. '<|fim_middle|>'
            end,
            suffix = false,
        }
    end
    config.provider = 'openai_fim_compatible'
    return true
end

local function server_health(qs)
    if not has_curl() then
        -- Without a probe we assume the server is down and try to start it;
        -- the failure message then tells the user why that could not work.
        return false
    end
    local ok_handle, handle_or_err = pcall(vim.system, {
        'curl',
        '-fsS',
        '--max-time',
        '2',
        ('http://%s:%d/health'):format(qs.host, qs.port),
    }, { text = true })
    if not ok_handle then
        return false
    end
    local result = handle_or_err:wait(3000)
    -- wait returns nil when the timeout is reached.
    return result ~= nil and result.code == 0
end

local function start_server(qs)
    local binary = M.resolve_binary()

    if not binary then
        local version = M.latest_release_tag() or fallback_release
        M.download_binary(version, function()
            local fresh_binary = M.resolve_binary()
            if fresh_binary then
                start_server(qs)
            end
        end)
        return
    end

    vim.fn.mkdir(data_dir, 'p')
    local log_file = data_dir .. '/llama-server.log'
    local cmd = { binary }
    vim.list_extend(cmd, M.server_args(binary, qs))

    local handle_ok, handle = pcall(vim.system, cmd, { detach = true }, function(out)
        if out.code ~= 0 and not server_health(qs) then
            vim.notify(
                'llama server exited (code ' .. out.code .. '); see ' .. log_file,
                vim.log.levels.ERROR
            )
        end
    end)
    if not handle_ok and handle ~= nil then
        vim.notify('failed to start the llama server: ' .. tostring(handle), vim.log.levels.ERROR)
        return
    end
    vim.notify('starting llama.cpp server on port ' .. qs.port .. ' (first start downloads the model)', vim.log.levels.INFO)
end

function M.ensure(config, quick_start)
    local qs = M.normalize(quick_start)

    if not M.wire_provider(config, qs) then
        -- The user manages the endpoint; the server is theirs.
        return false
    end

    if not server_health(qs) then
        start_server(qs)
    end
    return true
end

-- Exposed for tests.
M.defaults = defaults
M.fallback_release = fallback_release
M.data_dir = data_dir

return M