local reorder = require("code-points.reorder")

local M = {}

local ns = vim.api.nvim_create_namespace("code_points_hl")

-- Maps type prefix → { prefix_hl, name_hl }
local HIGHLIGHT_MAP = {
  ["function"]         = { prefix = "Keyword",  name = "Function" },
  ["export function"]  = { prefix = "Keyword",  name = "Function" },
  ["variable"]         = { prefix = "Keyword",  name = "Identifier" },
  ["export variable"]  = { prefix = "Keyword",  name = "Identifier" },
  ["class"]            = { prefix = "Type",     name = "Type" },
  ["export class"]     = { prefix = "Type",     name = "Type" },
  ["interface"]        = { prefix = "Type",     name = "Type" },
  ["export interface"] = { prefix = "Type",     name = "Type" },
  ["type"]             = { prefix = "Type",     name = "Type" },
  ["export type"]      = { prefix = "Type",     name = "Type" },
  ["enum"]             = { prefix = "Type",     name = "Type" },
  ["export enum"]      = { prefix = "Type",     name = "Type" },
  ["export"]           = { prefix = "Keyword",  name = "Identifier" },
  ["expression"]       = { prefix = "Keyword",  name = "Identifier" },
}

-- Sorted by length descending so we match two-word prefixes before one-word
local SORTED_PREFIXES = {}
for prefix in pairs(HIGHLIGHT_MAP) do
  table.insert(SORTED_PREFIXES, prefix)
end
table.sort(SORTED_PREFIXES, function(a, b) return #a > #b end)

--- Apply syntax highlighting to all lines in the code points buffer.
--- Each line has the format: <type_prefix> <name>
--- @param buf number buffer handle
local function apply_highlights(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  for i, line in ipairs(lines) do
    local lnum = i - 1 -- 0-indexed

    -- Find the matching type prefix (longest match first)
    local matched_prefix = nil
    for _, prefix in ipairs(SORTED_PREFIXES) do
      if line:sub(1, #prefix) == prefix and line:sub(#prefix + 1, #prefix + 1) == " " then
        matched_prefix = prefix
        break
      end
    end

    if matched_prefix then
      local hl = HIGHLIGHT_MAP[matched_prefix]

      -- Highlight the type prefix
      vim.api.nvim_buf_add_highlight(buf, ns, hl.prefix, lnum, 0, #matched_prefix)

      -- Highlight the symbol name (everything after the prefix)
      local name_start = #matched_prefix + 1 -- byte after the space
      vim.api.nvim_buf_add_highlight(buf, ns, hl.name, lnum, name_start, -1)
    end
  end
end

--- Build display lines from code point entries.
--- Format: "type name"
--- @param entries table[] list of code point entries from treesitter module
--- @return string[] display_lines
local function build_display_lines(entries)
  local lines = {}
  for _, entry in ipairs(entries) do
    local display = entry.display_type .. " " .. entry.name
    table.insert(lines, display)
  end
  return lines
end

--- Create a centered floating window.
--- @param buf number buffer handle
--- @param title string window title
--- @return number win window handle
local function open_centered_float(buf, title)
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "center",
  })

  vim.api.nvim_set_option_value("cursorline", true, { win = win })
  vim.api.nvim_set_option_value("number", true, { win = win })
  vim.api.nvim_set_option_value("relativenumber", true, { win = win })

  return win
end

--- Open the code points floating window.
--- @param source_bufnr number the source buffer to operate on
--- @param entries table[] list of code point entries from treesitter module
function M.open(source_bufnr, entries)
  -- Create a scratch buffer with acwrite so :w triggers BufWriteCmd
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "acwrite", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })

  -- Populate the buffer with display lines
  local display_lines = build_display_lines(entries)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, display_lines)

  -- Mark the buffer as unmodified after initial population
  vim.api.nvim_set_option_value("modified", false, { buf = buf })

  -- Give it a name so :w doesn't complain about no file name
  vim.api.nvim_buf_set_name(buf, "code-points://reorder")

  -- Open the float
  local win = open_centered_float(buf, "Code Points")

  -- Apply initial syntax highlighting
  apply_highlights(buf)

  -- Refresh highlights when buffer text changes (e.g., after dd+p to move lines)
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = buf,
    callback = function()
      apply_highlights(buf)
    end,
  })

  -- Toggle relative line numbers based on mode and focus
  local numbertoggle = vim.api.nvim_create_augroup("code_points_numbertoggle", { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "FocusGained", "InsertLeave", "WinEnter" }, {
    group = numbertoggle,
    buffer = buf,
    callback = function()
      if vim.api.nvim_win_is_valid(win) and vim.wo[win].nu and vim.fn.mode() ~= "i" then
        vim.wo[win].rnu = true
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufLeave", "FocusLost", "InsertEnter", "WinLeave" }, {
    group = numbertoggle,
    buffer = buf,
    callback = function()
      if vim.api.nvim_win_is_valid(win) and vim.wo[win].nu then
        vim.wo[win].rnu = false
      end
    end,
  })

  -- Map 'q' to close the window (normal mode)
  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, noremap = true, silent = true, desc = "Close Code Points window" })

  -- Handle :w — intercept the save and apply reordering
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      local new_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

      -- Filter out empty lines
      local filtered = {}
      for _, line in ipairs(new_lines) do
        local trimmed = vim.trim(line)
        if trimmed ~= "" then
          table.insert(filtered, trimmed)
        end
      end

      local ok, err = reorder.apply(source_bufnr, entries, filtered)
      if ok then
        vim.api.nvim_set_option_value("modified", false, { buf = buf })
        vim.notify("CodePoints: reorder applied", vim.log.levels.INFO)

        -- Close the window after successful save
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
      else
        vim.notify("CodePoints: " .. (err or "unknown error"), vim.log.levels.ERROR)
      end
    end,
  })

  -- Cleanup buffer when window is closed
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end,
  })
end

return M
