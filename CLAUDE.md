# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Environment

- Platform: Windows (MSYS2/bash shell), Neovim 0.11.x
- NvChad v2.5 on top of lazy.nvim
- Plugin data: `C:/Users/User/AppData/Local/nvim-data/lazy/`
- Lua bytecode cache: `C:/Users/User/AppData/Local/Temp/nvim/luac/` (delete all if seeing `attempt to index a boolean` errors at startup)
- Formatter: StyLua (`.stylua.toml`: 120 col, spaces, AutoPreferDouble quotes)

## Architecture

Entry point is `init.lua` (root). Load order:

1. `init.lua` — sets `vim.g.base46_cache`, bootstraps lazy.nvim, calls `require("lazy").setup()` with NvChad + `lua/plugins/`
2. `lua/chadrc.lua` — NvChad UI overrides (theme, statusline modules, terminal float size)
3. `lua/options.lua` — vim options (treesitter folding enabled but `foldenable=false`)
4. `lua/autocmds.lua` — autocommands
5. `lua/mappings.lua` — keybindings (loaded via `vim.schedule` after UI init)

Config files under `lua/configs/`:
- `lazy.lua` — lazy.nvim options, `disabled_plugins` list
- `lspconfig.lua` — Pyright via `vim.lsp.config` (Neovim 0.11+ native API), auto-detects `.venv`
- `mason.lua` — ensure_installed: pyright, black, isort, debugpy
- `conform.lua` — formatter setup (black + isort for Python)
- `telescope.lua` — custom `file_ignore_patterns`, image preview via chafa
- `dap.lua` — nvim-dap + dapui setup, loads `.vscode/launch.json` automatically
- `image_preview.lua` — Telescope image browser using chafa at `C:\msys64_2\ucrt64\bin\chafa.exe`

## Key Design Decisions

### Statusline (chadrc.lua)
Custom module overrides in `M.ui.statusline.modules`. Priority (highest to lowest):
- `mode`: never hidden; `%<` appended so Vim never truncates left of it
- `file`: truncated to 18 chars preserving extension (e.g. `multi_cam….py`)
- `cwd`: hidden when `vim.o.columns < 80`
- `git`: hidden when `vim.o.columns < 95`
- `diagnostics`: hidden when `vim.o.columns < 115`

### LSP (lspconfig.lua)
Uses Neovim 0.11+ `vim.lsp.config` / `vim.lsp.enable()` API (not the old `lspconfig.pyright.setup()`). Pyright uses `diagnosticMode = "openFilesOnly"` to save resources.

### nvim-tree (plugins/init.lua)
`H` key overridden to toggle gitignore filter (default NvChad `H` toggles dotfiles). Useful because `.venv/` and `logs/` are gitignored but not dotfiles.

### DAP (configs/dap.lua)
Uses nvim-dap-python + nvim-dap-ui with default layouts. Auto-loads `.vscode/launch.json` via `dap.ext.vscode.load_launchjs()`.

## Important Keybindings Added

| Key | Action |
|-----|--------|
| `<leader>fF` | Telescope find files (no gitignore, hidden) |
| `<leader>fW` | Telescope live grep (no gitignore) |
| `<leader>fp` | Image browser (chafa preview) |
| `<leader>o` | LSP document symbols |
| `<leader>O` | LSP workspace symbols |
| `<leader>ci` | LSP incoming calls (who calls me) |
| `<leader>co` | LSP outgoing calls (who I call) |
| `gI` / `gr` | LSP find references |
| `<F5>` | DAP continue/start |
| `<F10/11/12>` | DAP step over/into/out |
| `<leader>db` | DAP toggle breakpoint |
| `<leader>du` | DAP toggle UI |
| `<A-1..9>` | Switch to buffer 1-9 |
| `;` | Enter command mode (normal) |
| `jk` | Escape (insert mode) |

## Common Pitfalls

- **`attempt to index a boolean` at startup**: Stale luac cache. Delete all files in `C:/Users/User/AppData/Local/Temp/nvim/luac/`.
- **Keybinding conflicts**: `gh` = Neovim Select mode (avoid `gh*` prefixes). `<leader>ch` = NvChad Cheatsheet (avoid `<leader>ch*`).
- **Pyright not finding packages**: Check `.venv` exists at project root. `on_new_config` notifies which Python path is used.
- **Treesitter folding**: `foldenable=false` by default. Use `zM`/`zR`/`za` to fold/unfold.
