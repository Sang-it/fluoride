local reorder = require("code-points.reorder")
local rename = require("code-points.rename")

local M = {}

local ns = vim.api.nvim_create_namespace("code_points_hl")

-- Child indentation
local CHILD_PREFIX = "  • " -- 2 spaces + bullet + space
local CHILD_PREFIX_LEN = #CHILD_PREFIX

--- Build a sorted list of prefixes from a highlights table (longest first).
--- @param highlights table<string, table> map of display_type → { prefix, name }
--- @return string[] sorted_prefixes
local function build_sorted_prefixes(highlights)
  local prefixes = {}
  for prefix in pairs(highlights) do
    table.insert(prefixes, prefix)
  end
  table.sort(prefixes, function(a, b) return #a > #b end)
  return prefixes
end

--- Build a single display string for an entry (without tree prefix).
--- @param entry table code point entry
--- @return string display
local function entry_display(entry)
  local display = entry.display_type .. " " .. entry.name
  if entry.arity then
    display = display .. "/" .. entry.arity
  end
  return display
end

--- Build display lines and a flat entry map from code point entries.
--- The flat_map maps each 1-indexed buffer line to its entry (parent or child).
--- @param entries table[] list of code point entries from treesitter module
--- @return string[] display_lines
--- @return table[] flat_map list of { entry, parent_index, child_index }
local function build_display_lines(entries)
  local lines = {}
  local flat_map = {}

  for i, entry in ipairs(entries) do
    table.insert(lines, entry_display(entry))
    table.insert(flat_map, { entry = entry, parent_index = i, child_index = nil })

    if entry.children and #entry.children > 0 then
      for j, child in ipairs(entry.children) do
        table.insert(lines, CHILD_PREFIX .. entry_display(child))
        table.insert(flat_map, { entry = child, parent_index = i, child_index = j })
      end
    end
  end

  return lines, flat_map
end

--- Apply syntax highlighting to all lines in the code points buffer.
--- Handles both top-level lines and indented child lines with tree chars.
--- @param buf number buffer handle
--- @param highlights table<string, table> map of display_type → { prefix, name }
--- @param sorted_prefixes string[] prefixes sorted by length descending
local function apply_highlights(buf, highlights, sorted_prefixes)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  for i, line in ipairs(lines) do
    local lnum = i - 1 -- 0-indexed

    -- Check if this is a user-written comment line (starts with //)
    local trimmed = vim.trim(line)
    if trimmed:sub(1, 2) == "//" then
      vim.api.nvim_buf_add_highlight(buf, ns, "Comment", lnum, 0, -1)
      goto continue
    end

    -- Detect indentation (tree chars or spaces)
    local content_start = 0
    local is_child = false

    -- Check for child indent prefix
    if line:sub(1, CHILD_PREFIX_LEN) == CHILD_PREFIX then
      content_start = CHILD_PREFIX_LEN
      is_child = true
      -- Highlight the bullet as Comment
      vim.api.nvim_buf_add_highlight(buf, ns, "Comment", lnum, 0, CHILD_PREFIX_LEN)
    end

    local content = line:sub(content_start + 1)

    -- Find the matching type prefix (longest match first)
    local matched_prefix = nil
    for _, prefix in ipairs(sorted_prefixes) do
      if content:sub(1, #prefix) == prefix and content:sub(#prefix + 1, #prefix + 1) == " " then
        matched_prefix = prefix
        break
      end
    end

    local hl_prefix_group, hl_name_group
    local prefix_len

    if matched_prefix then
      local hl = highlights[matched_prefix]
      hl_prefix_group = hl.prefix
      hl_name_group = hl.name
      prefix_len = #matched_prefix
    else
      -- Fallback: split at first space for unrecognized display types
      local fallback_prefix = content:match("^(%S+)%s")
      if fallback_prefix then
        hl_prefix_group = "Keyword"
        hl_name_group = "Identifier"
        prefix_len = #fallback_prefix
      end
    end

    if prefix_len then
      local prefix_start = content_start
      local prefix_end = content_start + prefix_len

      -- Highlight the type prefix
      vim.api.nvim_buf_add_highlight(buf, ns, hl_prefix_group, lnum, prefix_start, prefix_end)

      -- Highlight the symbol name and arity
      local after_prefix = content:sub(prefix_len + 2)
      local name_start = prefix_end + 1 -- after the space

      local name_part, arity_part = after_prefix:match("^(.+)(/%d+)$")
      if name_part and arity_part then
        local name_end = name_start + #name_part
        vim.api.nvim_buf_add_highlight(buf, ns, hl_name_group, lnum, name_start, name_end)
        vim.api.nvim_buf_add_highlight(buf, ns, "Comment", lnum, name_end, name_end + #arity_part)
      else
        vim.api.nvim_buf_add_highlight(buf, ns, hl_name_group, lnum, name_start, -1)
      end
    end
    ::continue::
  end
end

--- Create a floating window positioned on the right side with padding.
--- @param buf number buffer handle
--- @param title string window title
--- @return number win window handle
local function open_sidebar(buf, title)
  local width = math.floor(vim.o.columns * 0.3)
  local height = vim.o.lines - 6 -- leave padding top and bottom
  local row = 2
  local col = vim.o.columns - width - 2 -- padding from right edge

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "single",
    title = " " .. title .. " ",
    title_pos = "center",
  })

  vim.api.nvim_set_option_value("cursorline", true, { win = win })
  vim.api.nvim_set_option_value("number", true, { win = win })
  vim.api.nvim_set_option_value("relativenumber", true, { win = win })

  return win
end

-- Track the current code points window
local active_win = nil
local active_buf = nil

--- Open the code points floating window.
--- @param source_bufnr number the source buffer to operate on
--- @param entries table[] list of code point entries from treesitter module
--- @param lang CodePointsLang the language module
function M.open(source_bufnr, entries, lang)
  -- If a code points window is already open, focus it
  if active_win and vim.api.nvim_win_is_valid(active_win) then
    vim.api.nvim_set_current_win(active_win)
    return
  end

  -- Build highlight data from the language module
  local highlights = lang.highlights or {}
  local sorted_prefixes = build_sorted_prefixes(highlights)

  -- Create a scratch buffer with acwrite so :w triggers BufWriteCmd
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("buftype", "acwrite", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })

  -- Populate the buffer with display lines
  local display_lines, flat_map = build_display_lines(entries)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, display_lines)

  -- Mark the buffer as unmodified after initial population
  vim.api.nvim_set_option_value("modified", false, { buf = buf })

  -- Give it a name so :w doesn't complain about no file name
  vim.api.nvim_buf_set_name(buf, "code-points://reorder")

  -- Open the sidebar
  local win = open_sidebar(buf, "Code Points")

  -- Apply initial syntax highlighting
  apply_highlights(buf, highlights, sorted_prefixes)

  -- Add help footer at the bottom of the window
  local footer_ns = vim.api.nvim_create_namespace("code_points_footer")
  local function update_footer()
    vim.api.nvim_buf_clear_namespace(buf, footer_ns, 0, -1)
    local line_count = vim.api.nvim_buf_line_count(buf)
    local win_height = vim.api.nvim_win_get_height(win)
    local pad = win_height - line_count - 1
    local virt_lines = {}
    if pad > 0 then
      for _ = 1, pad do
        table.insert(virt_lines, { { "", "Comment" } })
      end
    end
    table.insert(virt_lines, { { ":w=submit q=close gd=peek K=hover", "Comment" } })
    vim.api.nvim_buf_set_extmark(buf, footer_ns, line_count - 1, 0, {
      virt_lines = virt_lines,
      virt_lines_above = false,
    })
  end
  update_footer()

  -- Refresh highlights and footer when buffer text changes
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = buf,
    callback = function()
      apply_highlights(buf, highlights, sorted_prefixes)
      update_footer()
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

  -- Map <CR> to jump to the code point under cursor (without closing the window)
  vim.keymap.set("n", "<CR>", function()
    local cursor_line = vim.api.nvim_win_get_cursor(win)[1] -- 1-indexed
    local map_entry = flat_map[cursor_line]
    if not map_entry then return end

    local target_row = map_entry.entry.start_row + 1 -- 1-indexed

    -- Find the window displaying the source buffer
    local source_win = nil
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if w ~= win and vim.api.nvim_win_get_buf(w) == source_bufnr then
        source_win = w
        break
      end
    end

    if source_win then
      -- Switch focus to source window and jump to the code point
      vim.api.nvim_set_current_win(source_win)
      vim.api.nvim_win_set_cursor(source_win, { target_row, 0 })
      vim.fn.winrestview({ topline = target_row })
    end
  end, { buffer = buf, noremap = true, silent = true, desc = "Jump to code point" })

  -- Map gd to peek at the code point (scroll source buffer without leaving)
  vim.keymap.set("n", "gd", function()
    local cursor_line = vim.api.nvim_win_get_cursor(win)[1] -- 1-indexed
    local map_entry = flat_map[cursor_line]
    if not map_entry then return end

    local target_row = map_entry.entry.start_row + 1 -- 1-indexed

    -- Find the window displaying the source buffer
    local source_win = nil
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if w ~= win and vim.api.nvim_win_get_buf(w) == source_bufnr then
        source_win = w
        break
      end
    end

    if source_win then
      -- Move the cursor and scroll so the code point is at the top of the source window
      vim.api.nvim_win_call(source_win, function()
        vim.api.nvim_win_set_cursor(source_win, { target_row, 0 })
        vim.cmd("normal! zz")
      end)
    end
  end, { buffer = buf, noremap = true, silent = true, desc = "Peek at code point (gd)" })

  -- Map K to show LSP hover for the code point under cursor
  vim.keymap.set("n", "K", function()
    local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
    local map_entry = flat_map[cursor_line]
    if not map_entry then return end

    local target_row = map_entry.entry.decl_start_row + 1

    local source_win = nil
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if w ~= win and vim.api.nvim_win_get_buf(w) == source_bufnr then
        source_win = w
        break
      end
    end

    if source_win then
      -- Focus source window, position cursor on the symbol name, trigger hover
      vim.api.nvim_set_current_win(source_win)

      -- Find the column of the symbol name on the declaration line
      local name = map_entry.entry.name
      local decl_line = vim.api.nvim_buf_get_lines(source_bufnr, target_row - 1, target_row, false)[1] or ""
      local col = 0
      if name and #name > 0 then
        local pattern = "%f[%w_]" .. vim.pesc(name) .. "%f[^%w_]"
        local found = decl_line:find(pattern)
        if found then
          col = found - 1 -- 0-indexed
        end
      end

      vim.api.nvim_win_set_cursor(source_win, { target_row, col })
      vim.lsp.buf.hover()
    end
  end, { buffer = buf, noremap = true, silent = true, desc = "LSP hover for code point" })

  -- Handle :w — intercept the save and apply reordering + renames
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      local success, errmsg = pcall(function()
        local new_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

        -- Filter out empty lines
        local filtered = {}
        for _, line in ipairs(new_lines) do
          local trimmed = vim.trim(line)
          if trimmed ~= "" then
            table.insert(filtered, line) -- keep original line (with tree chars)
          end
        end

        local ok, err, renames = reorder.apply(source_bufnr, entries, filtered, lang)
        if not ok then
          vim.notify("CodePoints: " .. (err or "unknown error"), vim.log.levels.WARN)
          return
        end

        vim.api.nvim_set_option_value("modified", false, { buf = buf })

        -- Format via LSP if available (without closing the window)
        local function format_source()
          -- Find the source window to run format in its context
          local source_win = nil
          for _, w in ipairs(vim.api.nvim_list_wins()) do
            if w ~= win and vim.api.nvim_win_get_buf(w) == source_bufnr then
              source_win = w
              break
            end
          end

          if source_win then
            vim.api.nvim_win_call(source_win, function()
              local clients = vim.lsp.get_clients({ bufnr = source_bufnr })
              local has_formatter = false
              for _, client in ipairs(clients) do
                if client.server_capabilities.documentFormattingProvider then
                  has_formatter = true
                  break
                end
              end
              if has_formatter then
                vim.lsp.buf.format({ async = false, bufnr = source_bufnr, timeout_ms = 5000 })
              end
            end)
          end
        end

        -- Refresh the code points list after changes are applied
        local function refresh()
          format_source()

          -- Re-extract code points from the updated source buffer
          local treesitter = require("code-points.treesitter")
          local new_entries, _ = treesitter.get_code_points(source_bufnr)
          if #new_entries > 0 then
            entries = new_entries
            local new_display_lines, new_flat_map = build_display_lines(entries)
            flat_map = new_flat_map
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_display_lines)
            vim.api.nvim_set_option_value("modified", false, { buf = buf })
            apply_highlights(buf, highlights, sorted_prefixes)
            update_footer()
          end
        end

        -- Apply LSP renames if any names were changed
        if renames and #renames > 0 then
          if not rename.has_rename_support(source_bufnr) then
            vim.notify(
              "CodePoints: reorder applied, but no LSP client with rename support is attached. "
                .. #renames .. " rename(s) skipped.",
              vim.log.levels.WARN
            )
            refresh()
            return
          end

          vim.notify("CodePoints: reorder applied, processing " .. #renames .. " rename(s)...", vim.log.levels.INFO)
          rename.apply_renames(source_bufnr, renames, function()
            vim.notify("CodePoints: all renames complete", vim.log.levels.INFO)
            refresh()
          end)
        else
          vim.notify("CodePoints: reorder applied", vim.log.levels.INFO)
          refresh()
        end
      end)

      if not success then
        vim.notify("CodePoints: " .. tostring(errmsg), vim.log.levels.WARN)
      end
    end,
  })

  -- Track the active window/buffer
  active_win = win
  active_buf = buf

  -- Cleanup buffer when window is closed
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      active_win = nil
      active_buf = nil
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end,
  })
end

return M
