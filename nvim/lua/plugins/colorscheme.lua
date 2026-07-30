return {
  'navarasu/onedark.nvim',
  priority = 1000,
  init = function()
    -- Muted markdown palette -- headings/inline-code default to saturated
    -- red/purple/green; pull them toward the text color so they don't shout.
    local md = {
      code = { fg = '#7f9a94' }, -- dim teal-grey inline code
      h1 = { fg = '#b57179', fmt = 'bold' }, -- muted rose
      h2 = { fg = '#9a7fb0', fmt = 'bold' }, -- muted mauve
      h3 = { fg = '#b39a6a', fmt = 'bold' }, -- muted tan
      list = { fg = '#8a94a3' }, -- calm grey list markers
      link = { fg = '#7f97b0' }, -- soft blue links
    }
    require('onedark').setup {
      style = 'dark',
      transparent = true, -- don't paint a bg; let ghostty's opacity show through
      colors = {
        bg0 = '#252A34',
        fg = '#d2d8e0', -- soft near-white body text; onedark default #abb2bf
      },
      highlights = {
        -- treesitter groups (render-markdown / nvim-treesitter)
        ['@markup.raw'] = md.code,
        ['@markup.raw.block'] = md.code,
        ['@markup.heading.1'] = md.h1,
        ['@markup.heading.2'] = md.h2,
        ['@markup.heading.3'] = md.h3,
        ['@markup.heading.4'] = md.h1,
        ['@markup.heading.5'] = md.h2,
        ['@markup.heading.6'] = md.h3,
        ['@markup.link'] = md.link,
        ['@markup.link.label'] = md.link,
        ['@markup.list'] = md.list,
        -- legacy vim-markdown groups (fallback highlighter)
        markdownCode = md.code,
        markdownCodeBlock = md.code,
        markdownH1 = md.h1,
        markdownH2 = md.h2,
        markdownH3 = md.h3,
        markdownH4 = md.h1,
        markdownH5 = md.h2,
        markdownH6 = md.h3,
        markdownLinkText = md.link,
        markdownListMarker = md.list,
        markdownOrderedListMarker = md.list,
      },
    }
    require('onedark').load()
    vim.cmd.hi 'Comment gui=none'
  end,
}
