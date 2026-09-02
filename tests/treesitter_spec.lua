local helpers = require 'tests.helpers'

local function refresh(bufnr)
    helpers.setup_root_config { provider = 'llama_cpp' }

    local treesitter = helpers.reload 'harmonize.context.treesitter'
    treesitter.reset()

    local augroup = vim.api.nvim_create_augroup('harmonize-test-treesitter', { clear = true })
    treesitter.setup(augroup)
    vim.api.nvim_set_current_buf(bufnr)
    treesitter.refresh(bufnr)
    return treesitter
end

local parser_available = pcall(vim.treesitter.language.add, 'lua')

return {
    {
        name = 'treesitter captures imports and enclosing scope headers',
        run = function()
            if not parser_available then
                return -- skip: no lua parser in this environment
            end

            local bufnr = helpers.create_buffer({
                'local M = {}',
                'local utils = require "harmonize.utils"',
                '',
                'function M.run(a)',
                '  return utils',
                'end',
            })
            vim.bo[bufnr].buftype = ''
            vim.bo[bufnr].ft = 'lua'

            -- Put the cursor inside the function so it counts as enclosing.
            vim.api.nvim_win_set_cursor(0, { 5, 0 })
            local treesitter = refresh(bufnr)
            local chunks = treesitter.snapshot(bufnr)

            local texts = {}
            for _, c in ipairs(chunks) do
                texts[#texts + 1] = table.concat(c.lines, '\n')
            end

            helpers.expect_truthy(
                vim.tbl_contains(texts, 'local utils = require "harmonize.utils"'),
                'the import line must be captured'
            )
            helpers.expect_truthy(
                vim.tbl_contains(texts, 'function M.run(a)'),
                'the enclosing scope header must be captured without its body'
            )
            for _, text in ipairs(texts) do
                helpers.expect_falsy(text:find 'return utils', 'scope headers must not include the body')
            end

            helpers.delete_buffer(bufnr)
        end,
    },
    {
        name = 'treesitter snapshot returns nothing without a tracked buffer',
        run = function()
            if not parser_available then
                return -- skip: no lua parser in this environment
            end

            local bufnr = helpers.create_buffer({ 'local x = 1' })
            vim.bo[bufnr].buftype = ''
            vim.bo[bufnr].ft = 'lua'
            local treesitter = refresh(bufnr)

            -- Another buffer has no cached state.
            local other = helpers.create_buffer({ 'local y = 2' })
            vim.bo[bufnr].buftype = ''
            helpers.expect_equal(treesitter.snapshot(other), {})

            helpers.delete_buffer(bufnr)
            helpers.delete_buffer(other)
        end,
    },
}
