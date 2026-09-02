-- Extra completion context coordinator. Sources cache their chunks in the
-- background; snapshot() composes the cached chunks into llama.cpp's
-- input_extra: deduplicated, trimmed against what the cursor context already
-- covers, and capped to the configured character budgets.
local M = {}

M.augroup = nil

-- Sources ordered from most stable to most volatile so the server-side
-- prompt prefix cache survives typing.
local source_order = { 'treesitter', 'jumplist', 'recent_edits' }

---@class harmonize.ContextChunk
---@field source string
---@field bufnr? integer
---@field filename? string
---@field start_row integer 0-based, inclusive
---@field end_row integer 0-based, exclusive
---@field lines string[]

local function chunk_chars(chunk)
    local chars = 0
    for _, line in ipairs(chunk.lines) do
        chars = chars + vim.fn.strchars(line) + 1
    end
    return chars
end

--- Drop the part of a chunk that the cursor context already covers. The
--- larger remaining side wins; ties keep the lines before the covered range.
---@param chunk harmonize.ContextChunk
---@param covered { start: integer, end_exclusive: integer? }
function M.trim_covered(chunk, covered)
    local covered_end = covered.end_exclusive or math.huge
    if chunk.end_row <= covered.start or chunk.start_row >= covered_end then
        return { chunk }
    end

    local overlap_start = math.max(chunk.start_row, covered.start)
    local overlap_end = math.min(chunk.end_row, covered_end)
    local before_count = overlap_start - chunk.start_row
    local after_count = chunk.end_row - overlap_end

    if before_count >= after_count then
        -- Keep the lines before the covered range.
        chunk.lines = vim.list_slice(chunk.lines, 1, before_count)
        chunk.end_row = overlap_start
    else
        -- Keep the lines after the covered range.
        chunk.lines = vim.list_slice(chunk.lines, (overlap_end - chunk.start_row) + 1)
        chunk.start_row = overlap_end
    end

    if chunk.start_row >= chunk.end_row or #chunk.lines == 0 then
        return {}
    end
    return { chunk }
end

--- Merge chunks from the same file when their ranges overlap, re-reading the
--- lines from the buffer so the merged chunk is contiguous.
---@param chunks harmonize.ContextChunk[]
---@return harmonize.ContextChunk[]
local function merge_overlaps(chunks)
    local by_file = {}
    for _, chunk in ipairs(chunks) do
        by_file[chunk.filename] = by_file[chunk.filename] or {}
        table.insert(by_file[chunk.filename], chunk)
    end

    local merged = {}
    for _, file_chunks in pairs(by_file) do
        table.sort(file_chunks, function(a, b)
            return a.start_row < b.start_row
        end)
        for _, chunk in ipairs(file_chunks) do
            local last = merged[#merged]
            if
                last
                and last.filename == chunk.filename
                and last.end_row >= chunk.start_row
                and last.bufnr
                and chunk.bufnr
                and last.bufnr == chunk.bufnr
                and vim.api.nvim_buf_is_loaded(chunk.bufnr)
            then
                local end_row = math.max(last.end_row, chunk.end_row)
                last.lines = vim.api.nvim_buf_get_lines(chunk.bufnr, last.start_row, end_row, true)
                last.end_row = end_row
            else
                table.insert(merged, chunk)
            end
        end
    end
    return merged
end

--- Compose cached source chunks into input_extra entries.
---@param source_chunks table<string, harmonize.ContextChunk[]> chunks per source
---@param covered { start: integer, end_exclusive: integer? } buffer lines already sent around the cursor
---@param current_bufnr integer buffer the completion runs in
---@return string[]? input_extra { filename, text } entries, nil when empty
function M.compose(source_chunks, covered, current_bufnr)
    local config = require('harmonize').config.context_sources
    local total = 0
    local input_extra = {}

    for _, source in ipairs(source_order) do
        local chunks = source_chunks[source]
        if chunks and #chunks > 0 and config[source].enabled then
            for _, chunk in ipairs(chunks) do
                -- The filename identifies the chunk to the model; fall back to
                -- the buffer name for chunks without one.
                chunk.filename = chunk.filename
                    or (chunk.bufnr and vim.api.nvim_buf_get_name(chunk.bufnr) or '')
                if chunk.filename == '' then
                    chunk.filename = '[buffer]'
                end
                chunk.filename = vim.fn.fnamemodify(chunk.filename, ':.')
            end

            table.sort(chunks, function(a, b)
                if a.filename ~= b.filename then
                    return a.filename < b.filename
                end
                return a.start_row < b.start_row
            end)

            -- Drop duplicates and trim what the cursor context covers.
            local unique = {}
            local seen = {}
            for _, chunk in ipairs(chunks) do
                chunk.bufnr = chunk.bufnr or current_bufnr
                local key = chunk.filename .. ':' .. chunk.start_row .. ':' .. chunk.end_row
                if not seen[key] then
                    seen[key] = true
                    if chunk.bufnr == current_bufnr then
                        vim.list_extend(unique, M.trim_covered(chunk, covered))
                    else
                        unique[#unique + 1] = chunk
                    end
                end
            end

            chunks = merge_overlaps(unique)

            for _, chunk in ipairs(chunks) do
                local chars = chunk_chars(chunk)
                if chars > 0 and total + chars <= config.max_chars then
                    total = total + chars
                    input_extra[#input_extra + 1] = {
                        filename = chunk.filename,
                        text = table.concat(chunk.lines, '\n'),
                    }
                end
            end
        end
    end

    if #input_extra == 0 then
        return nil
    end
    return input_extra
end

function M.setup()
    local config = require('harmonize').config

    if M.augroup then
        vim.api.nvim_del_augroup_by_id(M.augroup)
        M.augroup = nil
    end

    -- Passive tracking is only useful once a provider sends requests.
    if not config.provider or config.provider == '' then
        return
    end

    M.augroup = vim.api.nvim_create_augroup('harmonize-context', { clear = true })
    require('harmonize.context.treesitter').setup(M.augroup)
    require('harmonize.context.jumplist').setup(M.augroup)
    require('harmonize.context.recent_edits').setup(M.augroup)
end

--- Compose the cached context for a completion request. Reads cached state
--- and buffer lines only: no parsing, filesystem access, or network.
---@param bufnr integer
---@param cursor_context table result of utils.get_context
---@return string[]? input_extra
function M.snapshot(bufnr, cursor_context)
    if not M.augroup then
        return nil
    end

    local source_chunks = {}
    for _, source in ipairs(source_order) do
        local ok, chunks = pcall(require('harmonize.context.' .. source).snapshot, bufnr)
        source_chunks[source] = ok and chunks or {}
    end

    return M.compose(source_chunks, cursor_context.covered_lines or { start = 0, end_exclusive = nil }, bufnr)
end

--- Test hook: drop all cached source state.
function M.reset()
    require('harmonize.context.treesitter')
    require('harmonize.context.jumplist').reset()
    require('harmonize.context.recent_edits').reset()
end

return M
