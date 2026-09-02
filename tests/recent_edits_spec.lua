local helpers = require 'tests.helpers'

local function setup_edits(bufnr)
    helpers.setup_root_config { provider = 'llama_cpp' }

    local edits = helpers.reload 'harmonize.context.recent_edits'
    edits.reset()

    local augroup = vim.api.nvim_create_augroup('harmonize-test-edits', { clear = true })
    edits.setup(augroup)
    return edits
end

return {
    {
        name = 'recent_edits records an edit and expands it with whole lines',
        run = function()
            local bufnr = helpers.create_buffer({ 'l0', 'l1', 'l2', 'l3', 'l4', 'l5', 'l6', 'l7', 'l8', 'l9' })
            vim.bo[bufnr].buftype = ''
            local edits = setup_edits(bufnr)

            vim.api.nvim_buf_set_lines(bufnr, 4, 4, false, { 'inserted' })

            local chunks = edits.snapshot(bufnr)
            helpers.expect_equal(#chunks, 1)
            helpers.expect_equal(chunks[1].bufnr, bufnr)
            -- The region grows to the budget in both directions.
            helpers.expect_truthy(chunks[1].start_row < 4)
            helpers.expect_truthy(chunks[1].end_row > 5)
            helpers.expect_truthy(vim.tbl_contains(chunks[1].lines, 'inserted'))

            helpers.delete_buffer(bufnr)
        end,
    },
    {
        name = 'recent_edits keeps one typing burst as a single region',
        run = function()
            local bufnr = helpers.create_buffer({ 'l0', 'l1', 'l2', 'l3', 'l4', 'l5', 'l6', 'l7', 'l8', 'l9' })
            vim.bo[bufnr].buftype = ''
            local edits = setup_edits(bufnr)

            vim.api.nvim_buf_set_lines(bufnr, 4, 4, false, { 'one' })
            vim.api.nvim_buf_set_lines(bufnr, 5, 5, false, { 'two' })

            local chunks = edits.snapshot(bufnr)
            helpers.expect_equal(#chunks, 1)

            helpers.delete_buffer(bufnr)
        end,
    },
    {
        name = 'recent_edits keeps only the newest max_edits regions',
        run = function()
            local lines = {}
            for i = 0, 49 do
                -- Long lines keep the character-budget expansion from
                -- reaching the previous edit region.
                lines[#lines + 1] = 'line' .. i .. string.rep('x', 44)
            end
            local bufnr = helpers.create_buffer(lines)
            vim.bo[bufnr].buftype = ''
            local edits = setup_edits(bufnr)

            -- Five edits far apart; max_edits is 4 by default and edits within
            -- three lines of each other are merged, so keep the gaps wider.
            vim.api.nvim_buf_set_lines(bufnr, 2, 2, false, { 'e1' })
            vim.api.nvim_buf_set_lines(bufnr, 12, 12, false, { 'e2' })
            vim.api.nvim_buf_set_lines(bufnr, 22, 22, false, { 'e3' })
            vim.api.nvim_buf_set_lines(bufnr, 32, 32, false, { 'e4' })
            vim.api.nvim_buf_set_lines(bufnr, 42, 42, false, { 'e5' })

            local chunks = edits.snapshot(bufnr)
            helpers.expect_equal(#chunks, 4)

            -- The first edit must have been dropped as the oldest.
            for _, c in ipairs(chunks) do
                for _, line in ipairs(c.lines) do
                    helpers.expect_truthy(line ~= 'e1', 'the oldest edit must be dropped')
                end
            end

            helpers.delete_buffer(bufnr)
        end,
    },
    {
        name = 'context.snapshot drops chunks the cursor context already covers',
        run = function()
            helpers.setup_root_config { provider = 'llama_cpp' }

            local bufnr = helpers.create_buffer({ 'local x = 1', 'local y = 2', 'local z = 3' })
            vim.bo[bufnr].buftype = ''
            vim.api.nvim_set_current_buf(bufnr)

            local context = helpers.reload 'harmonize.context'
            local edits = helpers.reload 'harmonize.context.recent_edits'
            edits.reset()
            local augroup = vim.api.nvim_create_augroup('harmonize-test-context', { clear = true })
            edits.setup(augroup)
            context.augroup = augroup

            vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { 'local w = 2.5' })

            -- The edit sits inside the covered range, so nothing may be sent
            -- as extra context for this small buffer.
            local input_extra = context.snapshot(bufnr, {
                covered_lines = { start = 0, end_exclusive = nil },
            })
            helpers.expect_falsy(input_extra)

            -- Narrowing the covered range to line 3 lets the edit region's
            -- first three lines through instead.
            input_extra = context.snapshot(bufnr, {
                covered_lines = { start = 3, end_exclusive = nil },
            })
            helpers.expect_truthy(input_extra)
            helpers.expect_equal(#input_extra, 1)
            helpers.expect_equal(input_extra[1].filename, '[buffer]')
            helpers.expect_truthy(input_extra[1].text:find 'local w = 2.5')

            helpers.delete_buffer(bufnr)
        end,
    },
}
