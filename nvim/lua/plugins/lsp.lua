return {
  {
    'folke/lazydev.nvim',
    ft = 'lua',
    opts = {
      library = {
        { path = 'luvit-meta/library', words = { 'vim%.uv' } },
      },
    },
  },
  { 'Bilal2453/luvit-meta', lazy = true },
  {
    'neovim/nvim-lspconfig',
    event = { 'BufReadPre', 'BufNewFile' },
    dependencies = {
      { 'williamboman/mason.nvim', config = true },
      'williamboman/mason-lspconfig.nvim',
      'WhoIsSethDaniel/mason-tool-installer.nvim',
      { 'j-hui/fidget.nvim', opts = {} },
      'hrsh7th/cmp-nvim-lsp',
    },
    config = function()
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
        callback = function(event)
          local map = function(keys, func, desc, mode)
            mode = mode or 'n'
            vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
          end

          map('gd', function()
            -- In markdown, follow the wikilink/link under the cursor (tailwindcss
            -- attaches here but doesn't support textDocument/definition).
            if vim.bo[event.buf].filetype == 'markdown' and require('obsidian').util.cursor_on_markdown_link(nil, nil, true) then
              return vim.cmd 'ObsidianFollowLink'
            end
            require('telescope.builtin').lsp_definitions()
          end, '[G]oto [D]efinition')
          map('gr', function()
            require('telescope.builtin').lsp_references { prompt_title = 'References: ' .. vim.fn.expand '<cword>' }
          end, '[G]oto [R]eferences')
          map('gI', require('telescope.builtin').lsp_implementations, '[G]oto [I]mplementation')
          map('<leader>D', require('telescope.builtin').lsp_type_definitions, 'Type [D]efinition')
          map('<leader>ds', require('telescope.builtin').lsp_document_symbols, '[D]ocument [S]ymbols')
          map('<leader>ws', require('telescope.builtin').lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')
          map('<leader>rn', vim.lsp.buf.rename, '[R]e[n]ame')
          map('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction', { 'n', 'x' })
          map('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')

          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight) then
            local highlight_augroup = vim.api.nvim_create_augroup('kickstart-lsp-highlight', { clear = false })
            vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.document_highlight,
            })

            vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.clear_references,
            })

            vim.api.nvim_create_autocmd('LspDetach', {
              group = vim.api.nvim_create_augroup('kickstart-lsp-detach', { clear = true }),
              callback = function(event2)
                vim.lsp.buf.clear_references()
                vim.api.nvim_clear_autocmds { group = 'kickstart-lsp-highlight', buffer = event2.buf }
              end,
            })
          end

          if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint) then
            map('<leader>th', function()
              vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf })
            end, '[T]oggle Inlay [H]ints')
          end
        end,
      })

      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('astro-unused-imports-filter', { clear = true }),
        callback = function(args)
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          if client and client.name == 'astro' then
            local ns = vim.lsp.diagnostic.get_namespace(args.data.client_id, 'publishDiagnostics')
            vim.diagnostic.config({
              virtual_text = {
                format = function(diagnostic)
                  if
                    diagnostic.message:match 'is declared but'
                    or diagnostic.message:match 'never used'
                    or diagnostic.code == 6133
                    or diagnostic.code == '6133'
                  then
                    return nil
                  end
                  return diagnostic.message
                end,
              },
              signs = {
                severity = { min = vim.diagnostic.severity.WARN },
              },
            }, ns)
          end
        end,
      })

      -- nvim core enables LSP document-color highlighting by default for any
      -- client with colorProvider (tailwindcss); we render colors ourselves
      -- via tailwind-tools, so turn off core's duplicate highlighting
      vim.lsp.document_color.enable(false)

      local capabilities = vim.lsp.protocol.make_client_capabilities()
      capabilities = vim.tbl_deep_extend('force', capabilities, require('cmp_nvim_lsp').default_capabilities())
      capabilities.general = { positionEncodings = { 'utf-16' } }

      local servers = {
        mdx_analyzer = {},
        astro = {
          init_options = {
            typescript = {
              tsdk = vim.fn.getcwd() .. '/node_modules/typescript/lib',
            },
          },
        },
        gopls = {
          settings = {
            gopls = {
              analyses = {
                unusedparams = true,
                shadow = true,
              },
              staticcheck = true,
              gofumpt = true,
            },
          },
        },
        vtsls = {
          settings = {
            typescript = {
              tsserver = {
                maxTsServerMemory = 12288,
              },
            },
            javascript = {
              tsserver = {
                maxTsServerMemory = 12288,
              },
            },
          },
        },
        ruff = {},
        rust_analyzer = {
          settings = {
            ['rust-analyzer'] = {
              check = { command = 'clippy' },
              cargo = { features = 'all' },
            },
          },
        },
        -- tailwindcss root_dir is overridden via vim.lsp.config below; keep it here
        -- only so it lands in ensure_installed (mason installs the server binary)
        tailwindcss = {},
        -- kotlin is set up via vim.lsp.config below; keep it here only so it
        -- lands in ensure_installed (mason installs the server binary)
        kotlin_language_server = {},
        lua_ls = {
          settings = {
            Lua = {
              completion = {
                callSnippet = 'Replace',
              },
            },
          },
        },
      }

      require('lspconfig').mdx_analyzer.setup { capabilities = capabilities }

      -- vtsls is configured directly via vim.lsp.config (not the mason handler below)
      -- because the legacy lspconfig.setup() shim drops `settings` for vtsls, leaving
      -- tsserver on its 3GB default heap — which crash-loops on the larger codebases
      vim.lsp.config('vtsls', {
        capabilities = capabilities,
        settings = {
          typescript = {
            tsserver = {
              maxTsServerMemory = 12288,
            },
          },
          javascript = {
            tsserver = {
              maxTsServerMemory = 12288,
            },
          },
        },
      })
      vim.lsp.enable 'vtsls'

      -- mason-lspconfig 2.x ignores the `handlers` block below (auto_enable only),
      -- so kotlin must be configured directly. lspconfig's default sets
      -- init_options.storagePath = vim.fs.root(...), which is nil when no
      -- gradle/maven marker is found — an empty table that serializes to JSON `[]`
      -- and crashes the server's gson parser. Pin a concrete cache dir instead.
      vim.lsp.config('kotlin_language_server', {
        capabilities = capabilities,
        init_options = {
          storagePath = vim.fn.stdpath 'cache' .. '/kotlin-language-server',
        },
      })
      vim.lsp.enable 'kotlin_language_server'

      -- mason-lspconfig 2.x auto-enables tailwindcss with nvim-lspconfig's default
      -- config, whose root_dir has a `.git` fallback for tailwind v4. Inside ~/main
      -- (a git repo) that roots the server at ~/main, which can't tie a file to its
      -- nearest tailwind.config, guesses v4, rejects the project's v3 @tailwind
      -- directives, and pops "No Tailwind CSS project" on every save (incl. ~/main/
      -- scratch/*.html). Anchor strictly on the tailwind config so each sub-package
      -- gets its own correctly-rooted client; files with no config nearby just don't
      -- attach (no popup). Uses the new (bufnr, on_dir) signature vim.lsp.config wants.
      vim.lsp.config('tailwindcss', {
        capabilities = capabilities,
        workspace_required = true,
        root_dir = function(bufnr, on_dir)
          local fname = vim.api.nvim_buf_get_name(bufnr)
          local found = vim.fs.find({
            'tailwind.config.ts',
            'tailwind.config.js',
            'tailwind.config.cjs',
            'tailwind.config.mjs',
          }, { path = fname, upward = true })[1]
          if found then
            on_dir(vim.fs.dirname(found))
          end
        end,
      })
      vim.lsp.enable 'tailwindcss'

      require('mason').setup()

      local ensure_installed = vim.tbl_keys(servers or {})
      vim.list_extend(ensure_installed, { 'stylua', 'goimports', 'gofumpt', 'prettier' })
      require('mason-tool-installer').setup { ensure_installed = ensure_installed }

      require('mason-lspconfig').setup {
        handlers = {
          function(server_name)
            -- vtsls is set up directly via vim.lsp.config above; skip the
            -- default handler so it doesn't double-setup with empty settings.
            if server_name == 'vtsls' then
              return
            end
            local server = servers[server_name] or {}
            server.capabilities = vim.tbl_deep_extend('force', {}, capabilities, server.capabilities or {})
            require('lspconfig')[server_name].setup(server)
          end,
        },
      }
    end,
  },
}
