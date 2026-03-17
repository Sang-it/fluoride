# fluoride.nvim

A Neovim plugin that lets you view, reorder, and rename top-level code declarations through a floating window. Powered by Treesitter and LSP.

## Features

- **View** all top-level declarations (functions, classes, variables, types, etc.) in a floating window
- **Reorder** declarations by moving lines in the float — saves back to the source file on `:w`
- **Rename** symbols by editing names in the float — triggers LSP rename across your project
- **Jump** to any code point by pressing `<CR>` on its line
- **Syntax highlighting** with type-aware colors (keywords, functions, types, identifiers)
- **Arity display** for functions (e.g., `function greet/1`)
- **Relative line numbers** with smart toggle (relative in normal mode, absolute in insert mode)

## Supported Languages

| Language | Filetypes | Features |
|----------|-----------|----------|
| TypeScript | `typescript`, `typescriptreact` | const/let/var, export wrapping, interface, type, enum |
| JavaScript | `javascript`, `javascriptreact` | const/let/var, export wrapping, arrow functions |
| Python | `python` | def, async def, class, decorators, excludes self/cls from arity |
| Lua | `lua` | local function vs function, assignments |
| Go | `go` | func, method (Receiver.Method), type, var, const |
| Rust | `rust` | fn, struct, enum, impl, trait, pub detection, macro_rules! |
| C/C++ | `c`, `cpp` | function, struct, enum, union, typedef, #define, class, namespace, template |

## Requirements

- Neovim >= 0.9
- Treesitter parser installed for your language (`:TSInstall <lang>`)
- LSP server attached for rename support (optional)

## Installation

### lazy.nvim

```lua
{
  "Sang-it/fluoride",
  config = function()
    require("fluoride").setup()
  end,
}
```

### Manual

Clone this repo and add it to your runtimepath:

```vim
set runtimepath+=~/path/to/fluoride
```

## Usage

```vim
:Fluoride
```

Or map it to a keybinding:

```lua
vim.keymap.set("n", "<leader>cp", "<cmd>Fluoride<cr>", { desc = "Open Fluoride" })
```

### Configuration

```lua
require("fluoride").setup({
  window = {
    title = "Fluoride",        -- string or false to disable
    width = 0.3,              -- proportion of terminal width (0-1)
    height = 0.85,            -- proportion of terminal height (0-1)
    row = 2,                  -- fixed rows from top edge
    col = 2,                  -- fixed cols from right edge
    border = "single",        -- border style (see below)
    winblend = 15,            -- transparency (0-100)
    footer = true,            -- show/hide help footer
    center_breakpoint = 80,   -- switch to centered layout below this width
  },
  keymaps = {
    close = "q",              -- close the window
    close_alt = "<C-c>",      -- alternative close (set false to disable)
    jump = "<CR>",            -- jump to code point
    peek = "gd",              -- peek at code point (center + flash)
    hover = "K",              -- LSP hover on code point
  },
})
```

#### Border Options

The `border` option accepts any format supported by `nvim_open_win`:

```lua
-- String presets
border = "single"     -- thin lines
border = "double"     -- double lines
border = "rounded"    -- rounded corners
border = "solid"      -- solid block
border = "none"       -- no border

-- Custom characters (8-element array):
-- { top-left, top, top-right, right, bottom-right, bottom, bottom-left, left }
border = { "┌", "─", "┐", "│", "┘", "─", "└", "│" }

-- Only left border
border = { "", "", "", "", "", "", "", "│" }

-- With highlight groups
border = {
  { "┌", "Comment" }, { "─", "Comment" }, { "┐", "Comment" },
  { "│", "Comment" }, { "┘", "Comment" }, { "─", "Comment" },
  { "└", "Comment" }, { "│", "Comment" },
}
```

### Keybindings (inside the float)

| Key | Action |
|-----|--------|
| `q` / `<C-c>` | Close the window |
| `<CR>` | Jump to the code point (focus moves to source) |
| `gd` | Peek at code point (center + flash, focus stays) |
| `K` | LSP hover on the code point |
| `:w` | Apply changes (reorder, rename, format) |

### Workflow

1. Open a supported file and run `:Fluoride`
2. A floating window appears listing all top-level declarations:
   ```
   const MAX_RETRIES
   interface UserConfig
   function greet/1
   class UserService
   export function formatUser/1
   ```
3. **Reorder**: move lines with `dd` + `p` (or any Vim motion)
4. **Rename**: edit the name portion of any line (keep the type prefix)
5. **Save**: hit `:w` — the source file is updated and LSP renames are applied
6. **Jump**: press `<CR>` on any line to close the float and jump to that declaration

## Adding Language Support

Create a file at `lua/fluoride/langs/<filetype>.lua` that exports:

```lua
local M = {}

M.filetypes = { "mylang" }           -- Neovim filetypes this module handles
M.parsers = { mylang = "mylang" }    -- filetype → treesitter parser name

M.highlights = {                     -- display prefix → highlight groups
  ["function"] = { prefix = "Keyword", name = "Function" },
  ["class"]    = { prefix = "Type",    name = "Type" },
}

function M.is_declaration(node)      -- filter top-level nodes
  return node:type() ~= "comment"
end

function M.get_name(node, bufnr)     -- extract symbol name
  -- ...
end

function M.get_display_type(node, bufnr)  -- return display prefix string
  -- ...
end

function M.get_arity(node, bufnr)    -- return param count or nil
  -- ...
end

return M
```

The module is auto-discovered on first use — no registration needed.

## License

MIT
