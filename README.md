# fluoride.nvim

A structural code editor for Neovim. View, reorder, rename, duplicate, delete, and annotate code declarations from a floating window. Powered by Treesitter and LSP.

## Demo

<video src="https://github.com/user-attachments/assets/0c556d53-d05f-487a-86eb-3eddcbacd0d6" controls="controls" width="100%"></video>

## Features

- **View** all declarations (functions, classes, variables, types, structs, enums, etc.) in a floating sidebar
- **Nested declarations** — methods inside classes, fields inside structs, variants inside enums, functions inside impl/trait/namespace blocks (configurable depth via `max_depth`)
- **Reorder** declarations by moving lines with vim motions (`dd` + `p`) — saves back to the source file on `:w` (children are protected from being moved outside their parent)
- **Rename** symbols by editing names — triggers LSP rename across your project
- **Duplicate** code points by copying lines (`yy` + `p`) — auto-generates suffixed names (`_1`, `_2`)
- **Delete** code points by removing lines — confirmation prompt before applying (configurable)
- **Comment** — write `// comment` above any entry to add it to the source file in the language's native syntax (`#` for Python, `--` for Lua, `//` for JS/TS/Go/Rust/C/C++)
- **Jump** (`<CR>`) — jump to the declaration in the source, cursor lands on the symbol name
- **Peek** (`gd`) — center and flash the declaration in the source window without leaving the float
- **Hover** (`K`) — show LSP hover info (type signature, docs) for the code point
- **Arity display** — functions show parameter count (e.g., `function greet/1`)
- **Attached comments** — comments directly above a declaration move with it when reordered
- **LSP format on save** — auto-formats the source buffer after changes if LSP supports it
- **Responsive layout** — sidebar on wide terminals, centered float on narrow ones (configurable breakpoint)
- **Auto-reload** — the code points list refreshes when the source file is saved
- **Graceful error handling** — incomplete syntax is handled by skipping broken nodes; invalid edits show friendly warnings
- **Transparent** — compatible with `transparent.nvim` and `winblend`

## Supported Languages

| Language | Filetypes | Highlights |
|----------|-----------|------------|
| TypeScript | `typescript`, `typescriptreact` | const/let/var, export, declare, abstract class, interface, type, enum, namespace, decorators (skipped), all class/interface/enum members |
| JavaScript | `javascript`, `javascriptreact` | const/let/var, export, generator functions, class with methods/fields/static blocks |
| Python | `python` | def, async def, class with methods, decorators, type alias (3.12), augmented assignment, if/while/for/try/with |
| Lua | `lua` | function, local function, local variables, assignments, if/while/for/do/repeat |
| Go | `go` | func, method (Receiver.Method), type (struct/interface with fields/methods), var, const, embedded types, go/defer/select |
| Rust | `rust` | fn, struct (with fields), enum (with variants), impl, trait, union, mod (nestable), macro_rules!, macro invocations, extern, pub detection |
| C | `c` | function, declaration, typedef, struct/enum/union (nestable with fields/enumerators), #define, forward declaration arity |
| C++ | `cpp` | Everything in C plus: class, namespace (nestable), template, using alias, concept (C++20), friend, static_assert, constructors/destructors, operator overloads, scoped enums (enum class), C++20 modules |

## Requirements

- Neovim >= 0.9
- Treesitter parser installed for your language (`:TSInstall <lang>`)
- LSP server attached (optional — for rename, hover, and format)

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

```vim
set runtimepath+=~/path/to/fluoride
```

## Usage

```vim
:Fluoride
```

Map to a keybinding:

```lua
vim.keymap.set("n", "<leader>cp", "<cmd>Fluoride<cr>", { desc = "Fluoride" })
```

## Configuration

All options are optional. Defaults shown below:

```lua
require("fluoride").setup({
  window = {
    title = "Fluoride",       -- string or false to hide
    border = "single",        -- any nvim_open_win border format
    winblend = 15,            -- transparency (0-100)
    footer = true,            -- show keybinding hints at bottom
    center_breakpoint = 80,   -- switch to centered layout below this width
    sidebar = {               -- right-side floating window (wide terminals)
      width = 0.3,            -- proportion of terminal width (0-1)
      height = 0.85,          -- proportion of terminal height (0-1)
      row = 2,                -- rows from top edge
      col = 2,                -- cols from right edge
    },
    centered = {              -- centered float (narrow terminals)
      width = 0.6,            -- proportion of terminal width (0-1)
      height = 0.6,           -- proportion of terminal height (0-1)
    },
  },
  keymaps = {
    close = "q",              -- close the window
    close_alt = "<C-c>",      -- alternative close (false to disable)
    jump = "<CR>",            -- jump to code point (focus moves to source)
    peek = "gd",              -- peek at code point (center + flash)
    hover = "K",              -- LSP hover on code point
    toggle_children = "<Tab>", -- toggle nested members on/off
    yank = "gy",              -- peek + copy code block to clipboard
  },
  max_depth = 1,              -- nesting depth for children (0=none, 1=direct children, 2+=deeper)
  yank_comments = true,       -- include attached comments in yank (default: true)
  confirm_delete = true,      -- prompt before deleting code points (false to skip)
  highlight = {
    peek_duration = 200,      -- ms for gd peek flash
    rename_duration = 130,    -- ms for rename flash per entry
  },
})
```

### Border

The `border` option accepts any format supported by `nvim_open_win`:

```lua
border = "single"                                          -- preset
border = "rounded"                                         -- preset
border = { "┌", "─", "┐", "│", "┘", "─", "└", "│" }      -- custom chars
border = { "", "", "", "", "", "", "", "│" }                -- left border only
```

## Keybindings

Inside the Fluoride window:

| Key | Action |
|-----|--------|
| `q` / `<C-c>` | Close the window |
| `<CR>` | Jump to code point (cursor on symbol name, focus moves to source) |
| `gd` | Peek — center and flash the code point in source (focus stays in float) |
| `K` | LSP hover — show type signature and docs |
| `:w` | Apply all changes (reorder, rename, duplicate, delete, comments, format) |
| `dd` + `p` | Reorder a code point |
| `yy` + `p` | Duplicate a code point (auto-suffixed name) |
| `dd` | Delete a code point (confirmed on `:w`) |
| `<Tab>` | Cycle nested members depth (0 → 1 → ... → max_depth → 0) |
| `gy` | Peek + copy code block to clipboard (vim register and system clipboard) |

## Workflow

1. Open a supported file and run `:Fluoride`
2. The sidebar shows all declarations with nested children (depth controlled by `max_depth`):
   ```
   const MAX_CONNECTIONS
   interface ServerConfig
     • property host
     • property port
     • property debug
   function createLogger/1
   namespace Services                    -- with max_depth = 2
     • class ConnectionPool
       • method add/1                    -- depth 2 children visible
       • method remove/1
       • method getActive/0
   export function startServer/1
   export const DEFAULT_CONFIG
   ```
3. **Reorder** — move lines with `dd` + `p`
4. **Rename** — edit the name portion of any line (keep the type prefix)
5. **Duplicate** — `yy` + `p` to copy a code point (gets `_1` suffix)
6. **Delete** — `dd` to remove a code point
7. **Comment** — type `// my comment` above any entry
8. **Save** — `:w` applies all changes, formats via LSP, and refreshes the list
9. **Navigate** — `<CR>` to jump, `gd` to peek, `K` to hover

## Adding Language Support

Create `lua/fluoride/langs/<filetype>.lua`:

```lua
local M = {}

M.filetypes = { "mylang" }
M.parsers = { mylang = "mylang" }
M.comment_types = { comment = true }
M.comment_prefix = "//"

M.highlights = {
  ["function"] = { prefix = "Keyword", name = "Function" },
  ["class"]    = { prefix = "Type",    name = "Type" },
}

function M.is_declaration(node)
  return node:type() ~= "comment"
end

function M.get_name(node, bufnr)       -- extract symbol name
end

function M.get_display_type(node, bufnr) -- return display prefix
end

function M.get_arity(node, bufnr)      -- return param count or nil
end

-- Optional: for nested declarations
function M.is_nestable(node)           -- true if node contains children
end

function M.get_body_node(node)         -- return the body node to iterate
end

function M.is_child_declaration(node)  -- true if child should be shown
end

return M
```

The module is auto-discovered on first use — no registration needed.

## License

MIT
