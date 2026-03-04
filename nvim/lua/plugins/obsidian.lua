return {
  'epwalsh/obsidian.nvim',
  version = '*',
  lazy = true,
  ft = 'markdown',
  dependencies = { 'nvim-lua/plenary.nvim' },
  opts = {
    -- No workspaces — works globally for any markdown file
    workspaces = {},
    -- Use gf for wikilinks (built-in with obsidian.nvim)
    mappings = {
      ['gd'] = {
        action = function()
          return require('obsidian').util.gf_passthrough()
        end,
        opts = { noremap = false, expr = true, buffer = true },
      },
    },
    -- Don't manage frontmatter automatically
    disable_frontmatter = true,
    -- Wiki-style links
    wiki_link_func = 'use_alias_only',
    -- Where new notes go
    new_notes_location = 'current_dir',
  },
}
