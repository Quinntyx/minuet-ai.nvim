-- Talks to llama.cpp's native /infill endpoint. The server constructs the
-- fill-in-the-middle prompt from input_prefix and input_suffix with the
-- model's own FIM tokens, so no per-model template is needed.
local common = require 'harmonize.backends.common'
local utils = require 'harmonize.utils'

local M = {}

M.is_available = function()
    local config = require('harmonize').config
    local options = config.provider_options.llama_cpp
    if not options.api_key then
        return true
    end
    return utils.get_api_key(options.api_key) and true or false
end

function M.get_text_fn(json)
    return json.content
end

M.complete = function(context, callback, on_update)
    local config = require('harmonize').config

    common.terminate_all_jobs()

    local options = vim.deepcopy(config.provider_options.llama_cpp)

    local data = {
        input_prefix = context.lines_before,
        input_suffix = context.lines_after,
        stream = options.stream,
    }
    data = vim.tbl_deep_extend('force', data, options.optional or {})

    local headers = {
        ['Content-Type'] = 'application/json',
        ['Accept'] = 'application/json',
    }
    local api_key = options.api_key and utils.get_api_key(options.api_key) or nil
    if api_key then
        headers.Authorization = 'Bearer ' .. api_key
    end

    local transformed_data = common.apply_transforms(options.transform, options.end_point, headers, data)

    local data_file = utils.make_tmp_file(transformed_data.body)

    if data_file == nil then
        return
    end

    local args = utils.make_curl_args(transformed_data.end_point, transformed_data.headers, data_file)

    local provider_name = 'llama_cpp'
    local timestamp = os.time()

    utils.run_event('HarmonizeRequestStartedPre', {
        provider = provider_name,
        name = options.name,
        model = options.model,
        n_requests = 1,
        timestamp = timestamp,
    })

    -- The raw text accumulated from the stream so far. Each update sends the
    -- complete snapshot so rendering does not depend on how curl splits
    -- stdout into chunks.
    local accumulated = ''
    local raw_buffer = ''
    local received_tokens = false

    local function consume_line(line)
        line = line:gsub('\r$', '')
        local stripped = line:match('^data:%s*(.*)$') or line
        if stripped == '' or stripped == '[DONE]' then
            return
        end

        local success, json = pcall(vim.json.decode, stripped)
        if success and json then
            local ok, text = pcall(M.get_text_fn, json)
            if ok and type(text) == 'string' and text ~= '' then
                accumulated = accumulated .. text
                if on_update then
                    on_update(accumulated)
                end
            end
        end
    end

    local new_job = common.start_job(config.curl_cmd, args, {
        on_stdout = options.stream and function(_, data)
            if not data or #data == 0 then
                return
            end
            raw_buffer = raw_buffer .. data
            while true do
                local nl = raw_buffer:find('\n', 1, true)
                if not nl then
                    break
                end
                local line = raw_buffer:sub(1, nl - 1)
                raw_buffer = raw_buffer:sub(nl + 1)
                consume_line(line)
            end
            received_tokens = #accumulated > 0
        end or nil,
        on_exit = function(_, out)
            utils.run_event('HarmonizeRequestFinished', {
                provider = provider_name,
                name = options.name,
                model = options.model,
                n_requests = 1,
                request_idx = 1,
                timestamp = timestamp,
            })

            -- A trailing line may arrive without a trailing newline.
            if #raw_buffer > 0 then
                consume_line(raw_buffer)
                raw_buffer = ''
            end
            received_tokens = #accumulated > 0

            local result

            if received_tokens then
                -- The stream already delivered the text token by token.
                vim.uv.fs_unlink(data_file)
                result = accumulated
            elseif options.stream then
                result = utils.stream_decode(out, data_file, options.name, M.get_text_fn)
            else
                result = utils.no_stream_decode(out, data_file, options.name, M.get_text_fn)
            end

            local items = {}
            if result then
                table.insert(items, result)
            end

            items = common.filter_context_sequences_in_items(items, context)
            items = vim.tbl_filter(function(x)
                return type(x) == 'string' and x:find '%S' ~= nil
            end, items)

            callback(items)
        end,
        on_spawn_error = function()
            vim.uv.fs_unlink(data_file)
            utils.run_event('HarmonizeRequestFinished', {
                provider = provider_name,
                name = options.name,
                model = options.model,
                n_requests = 1,
                request_idx = 1,
                timestamp = timestamp,
            })
            callback({})
        end,
    })

    if new_job then
        utils.run_event('HarmonizeRequestStarted', {
            provider = provider_name,
            name = options.name,
            model = options.model,
            n_requests = 1,
            request_idx = 1,
            timestamp = timestamp,
        })
    end
end

return M
