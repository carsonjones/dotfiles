return {
  {
    'nvim-telescope/telescope.nvim',
    branch = '0.1.x',
    cmd = 'Telescope',
    dependencies = {
      'nvim-lua/plenary.nvim',
      {
        'nvim-telescope/telescope-fzf-native.nvim',
        build = 'make',
        cond = function()
          return vim.fn.executable 'make' == 1
        end,
      },
      { 'nvim-telescope/telescope-ui-select.nvim' },
      { 'nvim-tree/nvim-web-devicons', enabled = vim.g.have_nerd_font },
    },
    keys = {
      {
        '<leader>sh',
        function()
          require('telescope.builtin').help_tags()
        end,
        desc = '[S]earch [H]elp',
      },
      {
        '<leader>sk',
        function()
          require('telescope.builtin').keymaps()
        end,
        desc = '[S]earch [K]eymaps',
      },
      {
        '<leader>sf',
        function()
          require('telescope.builtin').find_files()
        end,
        desc = '[S]earch [F]iles',
      },
      {
        '<leader>ss',
        function()
          require('telescope.builtin').builtin()
        end,
        desc = '[S]earch [S]elect Telescope',
      },
      {
        '<leader>sw',
        function()
          require('telescope.builtin').grep_string()
        end,
        desc = '[S]earch current [W]ord',
      },
      {
        '<leader>sg',
        function()
          require('telescope.builtin').live_grep { cwd = vim.fn.getcwd() }
        end,
        desc = '[S]earch by [G]rep',
      },
      {
        '<leader>sa',
        function()
          require('telescope.builtin').live_grep { cwd = vim.fn.getcwd(), file_ignore_patterns = {} }
        end,
        desc = '[S]earch [A]ll (no filters)',
      },
      {
        '<leader>sd',
        function()
          require('telescope.builtin').diagnostics { layout_config = { horizontal = { preview_width = 0.35 } } }
        end,
        desc = '[S]earch [D]iagnostics',
      },
      {
        '<leader>sr',
        function()
          require('telescope.builtin').resume()
        end,
        desc = '[S]earch [R]esume',
      },
      {
        '<leader>s.',
        function()
          require('telescope.builtin').oldfiles()
        end,
        desc = '[S]earch Recent Files ("." for repeat)',
      },
      {
        '<leader><leader>',
        function()
          local git_status = {}
          for _, l in ipairs(vim.fn.systemlist 'git status --porcelain 2>/dev/null' or {}) do
            local xy, f = l:match '^(..) (.+)$'
            if f then
              git_status[f:match '-> (.+)' or f] = xy
            end
          end
          local ic = { M = '●', A = '+', D = '✗' }
          local hl = { M = 'DiagnosticWarn', A = 'DiagnosticOk', D = 'DiagnosticError' }
          local bufs = vim.tbl_filter(function(b)
            return vim.api.nvim_buf_is_loaded(b)
          end, vim.api.nvim_list_bufs())
          local bufnr_width = #tostring(#bufs > 0 and math.max(unpack(bufs)) or 1)
          local gen = require('telescope.make_entry').gen_from_buffer { bufnr_width = bufnr_width }
          require('telescope.builtin').buffers {
            entry_maker = function(n)
              local e = gen(n)
              if not e then
                return
              end
              local orig = e.display
              e.display = function(x)
                local s, h = orig(x)
                local rel = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(x.bufnr), ':.')
                local xy = git_status[rel]
                if not xy then
                  return s, h
                end
                local c = xy:sub(1, 1) ~= ' ' and xy:sub(1, 1) or xy:sub(2, 2)
                local icon = ic[c] or c
                local off = #icon + 1
                h = h or {}
                for _, hi in ipairs(h) do
                  hi[1][1] = hi[1][1] + off
                  hi[1][2] = hi[1][2] + off
                end
                table.insert(h, 1, { { 0, #icon }, hl[c] or 'Normal' })
                return icon .. ' ' .. s, h
              end
              return e
            end,
          }
        end,
        desc = '[ ] Find existing buffers',
      },
      { '<leader>fb', ':Telescope file_browser path=%:p:h select_buffer=true<CR>', desc = 'File [B]rowser' },
      {
        '<leader>/',
        function()
          require('telescope.builtin').current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
            winblend = 10,
            previewer = false,
          })
        end,
        desc = '[/] Fuzzily search in current buffer',
      },
      {
        '<leader>s/',
        function()
          require('telescope.builtin').live_grep {
            grep_open_files = true,
            prompt_title = 'Live Grep in Open Files',
          }
        end,
        desc = '[S]earch [/] in Open Files',
      },
      {
        '<leader>sn',
        function()
          require('telescope.builtin').find_files { cwd = vim.fn.stdpath 'config' }
        end,
        desc = '[S]earch [N]eovim files',
      },
      {
        '<leader>sF',
        function()
          local query = vim.fn.input 'Files containing: '
          if query == '' then return end
          local cwd = vim.fn.getcwd()
          local pickers = require 'telescope.pickers'
          local finders = require 'telescope.finders'
          local conf = require('telescope.config').values
          local actions = require 'telescope.actions'
          local action_state = require 'telescope.actions.state'
          local make_entry = require 'telescope.make_entry'
          pickers.new({}, {
            prompt_title = 'Files containing: ' .. query,
            finder = finders.new_oneshot_job(
              { 'rg', '--files-with-matches', '--', query, cwd },
              { entry_maker = make_entry.gen_from_file { cwd = cwd } }
            ),
            sorter = conf.file_sorter {},
            previewer = conf.file_previewer {},
            attach_mappings = function(prompt_bufnr)
              actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local entry = action_state.get_selected_entry()
                if not entry then return end
                local filepath = entry.path or entry.value
                local result = vim.fn.systemlist { 'rg', '-n', '--', query, filepath }
                local lnum = 1
                if result[1] then
                  local n = result[1]:match '^(%d+):'
                  if n then lnum = tonumber(n) end
                end
                vim.cmd('edit ' .. vim.fn.fnameescape(filepath))
                vim.api.nvim_win_set_cursor(0, { lnum, 0 })
                vim.cmd 'normal! zz'
              end)
              return true
            end,
          }):find()
        end,
        desc = '[S]earch [F]iles containing pattern (one per file)',
      },
    },
    config = function()
      require('telescope').setup {
        defaults = {
          dynamic_preview_title = true,
          path_display = { 'truncate' },
          mappings = {
            i = { ['<C-t>'] = function(...) return require('trouble.sources.telescope').open(...) end },
            n = { ['<C-t>'] = function(...) return require('trouble.sources.telescope').open(...) end },
          },
          file_ignore_patterns = { '%.stories%.', '%.mock%.', '%.mocks%.', '__mocks__/', 'mocks/', '%.test%.', '%.spec%.', '__snapshots__/', '%.generated%.' },
          layout_config = {
            width = 0.9,
            height = 0.85,
            horizontal = {
              preview_width = 0.5,
            },
          },
          preview = {
            wrap = true,
            mime_hook = function(filepath, bufnr, opts)
              local image_exts = { png = true, jpg = true, jpeg = true, gif = true, webp = true, avif = true }
              local ext = filepath:match '%.(%w+)$'
              local api = require 'image'
              for _, img in ipairs(api.get_images { window = opts.winid }) do
                img:clear()
              end
              if ext and image_exts[ext:lower()] then
                local img = api.from_file(filepath, { window = opts.winid, buffer = bufnr, with_virtual_padding = true })
                if img then
                  img:render()
                end
              else
                require('telescope.previewers.utils').set_preview_message(bufnr, opts.winid, 'Binary cannot be previewed')
              end
            end,
          },
        },
        pickers = {
          lsp_references = { fname_width = 60 },
          lsp_definitions = { fname_width = 60 },
          lsp_implementations = { fname_width = 60 },
        },
        extensions = {
          ['ui-select'] = {
            require('telescope.themes').get_dropdown(),
          },
          file_browser = {
            theme = 'ivy',
            hijack_netrw = false,
            hidden = true,
            layout_config = {
              horizontal = {
                preview_width = 0.65,
              },
            },
          },
        },
      }

      vim.api.nvim_create_autocmd('User', {
        pattern = 'TelescopePreviewerLoaded',
        callback = function()
          local ok, api = pcall(require, 'image')
          if not ok then
            return
          end
          for _, img in ipairs(api.get_images()) do
            img:clear()
          end
        end,
      })

      pcall(require('telescope').load_extension, 'fzf')
      pcall(require('telescope').load_extension, 'ui-select')
      pcall(require('telescope').load_extension, 'file_browser')
    end,
  },
  {
    'nvim-telescope/telescope-file-browser.nvim',
    dependencies = { 'nvim-telescope/telescope.nvim', 'nvim-lua/plenary.nvim' },
  },
}
