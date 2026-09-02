-- Starts a llama.cpp server for the llama_cpp provider when none is running
-- at the configured host and port, so a first-time setup needs no manual
-- server management. The server starts when nvim launches; by default it is
-- left running when nvim exits so the next launch can reuse it, or it can be
-- stopped on exit with kill_on_exit.
local utils = require 'harmonize.utils'

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

---Build the server command from the base command in `opts.cmd`, the model
---(a Hugging Face repo id or a local file), the host and port to listen on,
---and the extra arguments.
---@param opts table the auto_start options
---@param host string
---@param port integer
---@return string[]? cmd nil when the binary could not be resolved
function M.server_cmd(opts, host, port)
    local words = vim.split(opts.cmd, '%s+', { trimempty = true })
    local binary = words[1]

    if vim.fn.executable(binary) ~= 1 then
        -- The binary leading the command is not on PATH; fall back to a
        -- downloaded llama.cpp release.
        binary = M.resolve_binary()
        if not binary then
            return nil
        end
        words[1] = binary
        -- The downloaded `llama` binary needs its `serve` subcommand; an
        -- explicit `llama-server` binary does not.
        if vim.fn.fnamemodify(binary, ':t') == 'llama' and not vim.tbl_contains(words, 'serve') then
            table.insert(words, 2, 'serve')
        end
    end

    if opts.model:match '^[^/]+/[^/]+$' then
        vim.list_extend(words, { '-hf', opts.model })
    else
        vim.list_extend(words, { '--model', opts.model })
    end

    vim.list_extend(words, { '--host', host, '--port', tostring(port) })
    vim.list_extend(words, utils.get_or_eval_value(opts.extra_args) or {})

    return words
end

local function server_health(host, port)
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
        ('http://%s:%d/health'):format(host, port),
    }, { text = true })
    if not ok_handle then
        return false
    end
    local result = handle_or_err:wait(3000)
    -- wait returns nil when the timeout is reached.
    return result ~= nil and result.code == 0
end

local function spawn_server(cmd, opts)
    vim.fn.mkdir(data_dir, 'p')
    local log_file = data_dir .. '/llama-server.log'

    local handle_ok, handle = pcall(vim.system, cmd, { detach = true }, function(out)
        if out.code ~= 0 and not server_health(opts.host, opts.port) then
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
        vim.api.nvim_create_autocmd('VimLeavePre', {
            group = vim.api.nvim_create_augroup('HarmonizeAutoStartServer', { clear = true }),
            callback = function()
                handle:kill 'sigterm'
            end,
            desc = 'stop the auto-started llama.cpp server',
        })
    end

    vim.notify(
        'starting llama.cpp server on port ' .. opts.port .. ' (first start downloads the model)',
        vim.log.levels.INFO
    )
end

local function start_server(opts)
    local cmd = M.server_cmd(opts, opts.host, opts.port)

    if not cmd then
        local version = M.latest_release_tag() or fallback_release
        M.download_binary(version, function()
            local retry = M.server_cmd(opts, opts.host, opts.port)
            if retry then
                spawn_server(retry, opts)
            end
        end)
        return
    end

    spawn_server(cmd, opts)
end

---Make sure the llama.cpp server the llama_cpp provider points at is
---running, starting it when it is not.
---@param config table the merged harmonize config
function M.ensure(config)
    if not config.auto_start then
        return
    end

    -- A partial auto_start table merges over the defaults, so
    -- auto_start = { model = '...' } is a complete setup.
    local opts = vim.tbl_deep_extend('force', M.default_auto_start, config.auto_start)

    if not server_health(opts.host, opts.port) then
        start_server(opts)
    end
end

-- Exposed for tests.
M.fallback_release = fallback_release
M.data_dir = data_dir

return M
