-- Treesitter-based extra context: imports and the headers of the
-- declarations enclosing the cursor. Parsing happens on buffer events, never
-- while building a completion request; snapshot() only reads cached text.
local api = vim.api

local M = {}

-- Node types whose header is sent as context, per language. Used when the
-- language has no harmonize query file.
local scope_node_types = {
    lua = { 'function_declaration', 'function_definition' },
    rust = {
        'function_item',
        'function_signature_item',
        'impl_item',
        'struct_item',
        'enum_item',
        'trait_item',
        'mod_item',
    },
}

local max_header_chars = 240
local debounce_ms = 250

local state = {
    bufnr = nil,
    lang = nil,
    tree = nil,
    -- Rendered chunks: imports as one buffer-line range, scopes as one
    -- single-line chunk per declaration header.
    chunks = {},
    -- Node ids of the current scopes, to skip re-rendering on cursor moves
    -- that stay inside the same declarations.
    scope_ids = nil,
    cursor_row = nil,
    debounce_timer = nil,
}

---@return boolean true when the buffer is a normal file buffer
local function is_normal_buffer(bufnr)
    return api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buftype == ''
end

--- Text between two byte positions, as buffer lines.
---@param bufnr integer
---@param srow integer 0-based start row
---@param scol integer 0-based start column in bytes
---@param erow integer 0-based end row
---@param ecol integer 0-based end column in bytes
---@return string
local function text_between(bufnr, srow, scol, erow, ecol)
    local lines = api.nvim_buf_get_lines(bufnr, srow, erow + 1, true)
    if #lines == 0 then
        return ''
    end
    if srow == erow then
        return (lines[1] or ''):sub(scol + 1, ecol)
    end
    local parts = { (lines[1] or ''):sub(scol + 1) }
    for i = 2, #lines - 1 do
        parts[#parts + 1] = lines[i]
    end
    parts[#parts + 1] = (lines[#lines] or ''):sub(1, ecol)
    return table.concat(parts, '\n')
end

--- Header of a declaration node: everything before its body starts, or the
--- whole node text capped when the grammar has no body field.
---@param node table treesitter node
---@param bufnr integer
---@return string
local function scope_header(node, bufnr)
    local srow, scol = node:start()
    local ok, body = pcall(node.field, node, 'body')
    if ok and body and body[1] then
        local brow, bcol = body[1]:start()
        if brow > srow or bcol > scol then
            return (text_between(bufnr, srow, scol, brow, bcol):gsub('%s+$', ''))
        end
    end
    return (vim.treesitter.get_node_text(node, bufnr):gsub('%s+$', ''):sub(1, max_header_chars))
end

local render_scopes ---@type fun(bufnr: integer)

local function reset_state(bufnr)
    state.bufnr = bufnr
    state.lang = nil
    state.tree = nil
    state.chunks = {}
    state.scope_ids = nil
end

local function parse(bufnr)
    if not is_normal_buffer(bufnr) then
        reset_state(nil)
        return
    end

    local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
    local parse_ok, trees
    if ok then
        parse_ok, trees = pcall(parser.parse, parser)
    end
    if not ok or not parse_ok or not trees or not trees[1] then
        reset_state(bufnr)
        return
    end

    state.bufnr = bufnr
    state.lang = parser:lang()
    state.tree = trees[1]
    state.scope_ids = nil
    render_scopes(bufnr)
end

--- Re-render the cached chunks from the current tree and cursor row. Cheap:
--- no parsing.
render_scopes = function(bufnr)
    if not state.tree or state.bufnr ~= bufnr then
        return
    end

    local ok, query = pcall(vim.treesitter.query.get, state.lang, 'harmonize')
    local types = scope_node_types[state.lang]
    if (not ok or not query) and not types then
        state.chunks = {}
        state.scope_ids = {}
        return
    end

    -- Collect the declarations enclosing the cursor. Prefer the query file
    -- when present; otherwise fall back to walking the tree.
    local found = {}
    if ok and query then
        for id, node in query:iter_captures(state.tree:root(), bufnr) do
            if query.captures[id] == 'harmonize.scope' then
                local srow, _, erow = node:range()
                if not state.cursor_row or (srow <= state.cursor_row and state.cursor_row <= erow) then
                    found[#found + 1] = node
                end
            end
        end
    else
        local function walk(node)
            local srow, _, erow = node:range()
            if
                state.cursor_row
                and srow <= state.cursor_row
                and state.cursor_row <= erow
                and vim.tbl_contains(types, node:type())
            then
                found[#found + 1] = node
            end
            for child in node:iter_children() do
                walk(child)
            end
        end
        walk(state.tree:root())
    end
    table.sort(found, function(a, b)
        return a:start() < b:start()
    end)

    -- Node ids change when the file is reparsed, so this skips only cursor
    -- movement within one parse generation.
    local ids = {}
    for _, node in ipairs(found) do
        ids[#ids + 1] = tostring(node:id())
    end
    if vim.deep_equal(ids, state.scope_ids) then
        return
    end
    state.scope_ids = ids

    local chunks = {}
    for _, node in ipairs(found) do
        local header = scope_header(node, bufnr)
        if header ~= '' then
            chunks[#chunks + 1] = {
                source = 'treesitter',
                bufnr = bufnr,
                start_row = node:start(),
                end_row = node:start() + 1,
                lines = { header },
            }
        end
    end

    -- Imports become one chunk covering the real buffer lines, so the
    -- compositor can drop them when the cursor context already includes them.
    if ok and query then
        local first_row, last_row
        local texts = {}
        for id, node in query:iter_captures(state.tree:root(), bufnr) do
            if query.captures[id] == 'harmonize.import' then
                local srow, _, erow = node:range()
                first_row = math.min(first_row or srow, srow)
                last_row = math.max(last_row or erow, erow)
                texts[vim.treesitter.get_node_text(node, bufnr)] = true
            end
        end
        if first_row and #vim.tbl_keys(texts) > 0 then
            chunks[#chunks + 1] = {
                source = 'treesitter',
                bufnr = bufnr,
                start_row = first_row,
                end_row = last_row + 1,
                lines = api.nvim_buf_get_lines(bufnr, first_row, last_row + 1, true),
            }
        end
    end

    state.chunks = chunks
end

function M.refresh(bufnr)
    if not M.augroup then
        return
    end
    if bufnr == api.nvim_get_current_buf() then
        state.cursor_row = api.nvim_win_get_cursor(0)[1] - 1
    end
    parse(bufnr)
    render_scopes(bufnr)
end

local function schedule_refresh(bufnr)
    if state.debounce_timer then
        state.debounce_timer:again()
        return
    end
    state.debounce_timer = vim.uv.new_timer()
    state.debounce_timer:start(debounce_ms, 0, vim.schedule_wrap(function()
        state.debounce_timer = nil
        M.refresh(bufnr)
    end))
end

function M.setup(augroup)
    M.augroup = augroup
    local group = { group = augroup }

    api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'FileType' }, vim.tbl_extend('force', group, {
        callback = function(args)
            M.refresh(args.buf)
        end,
        desc = 'harmonize treesitter context refresh',
    }))

    api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, vim.tbl_extend('force', group, {
        callback = function(args)
            schedule_refresh(args.buf)
        end,
        desc = 'harmonize treesitter context reparse',
    }))

    api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, vim.tbl_extend('force', group, {
        callback = function(args)
            state.cursor_row = api.nvim_win_get_cursor(0)[1] - 1
            render_scopes(args.buf)
        end,
        desc = 'harmonize treesitter context scope update',
    }))

    api.nvim_create_autocmd('BufWipeout', vim.tbl_extend('force', group, {
        callback = function(args)
            if state.bufnr == args.buf then
                if state.debounce_timer then
                    state.debounce_timer:stop()
                    state.debounce_timer = nil
                end
                reset_state(nil)
            end
        end,
        desc = 'harmonize treesitter context cleanup',
    }))
end

--- Cached chunks for the buffer. Never parses.
---@param bufnr integer
---@return table[] chunks
function M.snapshot(bufnr)
    if state.bufnr ~= bufnr then
        return {}
    end
    return vim.deepcopy(state.chunks)
end

function M.reset()
    if state.debounce_timer then
        state.debounce_timer:stop()
        state.debounce_timer = nil
    end
    reset_state(nil)
end

return M
