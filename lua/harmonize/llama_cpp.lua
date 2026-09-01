-- Runs a local llama.cpp server for the llama_cpp_managed provider, so a
-- first-time setup needs no manual server management. The server starts when
-- nvim launches; by default it is left running when nvim exits so the next
-- launch can reuse it, or it can be stopped on exit with kill_on_exit.
local M = {}

local data_dir = vim.fn.stdpath('data') .. '/harmonize'

-- Release tags before the v0.x scheme published one zip per platform; the
-- v0.x tags carry no binary assets. When the GitHub API is unreachable this
-- pinned tag is used instead.
local fallback_release = 'b4600'

local function has_curl()
    return vim.fn.executable 'curl' == 1
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

---Build the server command: unified `llama serve` vs `llama-server`, the
---HF repo vs a local GGUF file for the model, then the user's extra flags.
---@param binary string
---@param opts table the provider_options.llama_cpp_managed options
---@return string[]
function M.server_args(binary, opts)
    local args = {}
    if vim.fn.fnamemodify(binary, ':t') == 'llama' then
        table.insert(args, 'serve')
    end

    if opts.model:match '^[^/]+/[^/]+$' then
        table.insert(args, '-hf')
        table.insert(args, opts.model)
    else
        table.insert(args, '--model')
        table.insert(args, opts.model)
    end

    table.insert(args, '--host')
    table.insert(args, opts.host)
    table.insert(args, '--port')
    table.insert(args, tostring(opts.port))

    for flag in opts.llama_cpp_flags:gmatch '%S+' do
        table.insert(args, flag)
    end

    return args
end

---Point the openai_fim_compatible options at the managed server. Qwen models
---have no server-side suffix option in FIM, so their special tokens are
---embedded in the prompt instead.
---@param config table the merged harmonize config
---@param opts table the provider_options.llama_cpp_managed options
function M.wire_provider(config, opts)
    local fim = config.provider_options.openai_fim_compatible
    fim.end_point = ('http://%s:%d/v1/completions'):format(opts.host, opts.port)
    fim.api_key = 'TERM'
    fim.model = opts.model:match '[^/]+$'
    if opts.model:lower():find 'qwen' then
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
end

local function server_health(opts)
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
        ('http://%s:%d/health'):format(opts.host, opts.port),
    }, { text = true })
    if not ok_handle then
        return false
    end
    local result = handle_or_err:wait(3000)
    -- wait returns nil when the timeout is reached.
    return result ~= nil and result.code == 0
end

local function start_server(opts)
    local binary = M.resolve_binary()

    if not binary then
        local version = M.latest_release_tag() or fallback_release
        M.download_binary(version, function()
            local fresh_binary = M.resolve_binary()
            if fresh_binary then
                start_server(opts)
            end
        end)
        return
    end

    vim.fn.mkdir(data_dir, 'p')
    local log_file = data_dir .. '/llama-server.log'
    local cmd = { binary }
    vim.list_extend(cmd, M.server_args(binary, opts))

    local handle_ok, handle = pcall(vim.system, cmd, { detach = true }, function(out)
        if out.code ~= 0 and not server_health(opts) then
            vim.notify(
                'llama server exited (code ' .. out.code .. '); see ' .. log_file,
                vim.log.levels.ERROR
            )
        end
    end)
    if not handle_ok then
        vim.notify('failed to start the llama server: ' .. tostring(handle), vim.log.levels.ERROR)
        return
    end

    if opts.kill_on_exit then
        api.nvim_create_autocmd('VimLeavePre', {
            group = api.nvim_create_augroup('HarmonizeManagedServer', { clear = true }),
            callback = function()
                handle:kill 'sigterm'
            end,
            desc = 'stop the managed llama.cpp server',
        })
    end

    vim.notify(
        'starting llama.cpp server on port ' .. opts.port .. ' (first start downloads the model)',
        vim.log.levels.INFO
    )
end

---Point the provider at the managed server and make sure it is running.
---@param config table the merged harmonize config
function M.ensure(config)
    local opts = config.provider_options.llama_cpp_managed
    M.wire_provider(config, opts)

    if not server_health(opts) then
        start_server(opts)
    end
end

-- Exposed for tests.
M.fallback_release = fallback_release
M.data_dir = data_dir

return M
