local reorder = require("fluoride.reorder")
local rename = require("fluoride.rename")

local M = {}

local ns = vim.api.nvim_create_namespace("fluoride_hl")

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
  display = display:gsub("\n", " ")
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

--- Apply syntax highlighting to all lines in the fluoride buffer.
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
--- @param win_config table window configuration from plugin config
--- @return number win window handle
local function open_sidebar(buf, win_config)
  local width, height, row, col

      if vim.o.columns < (win_config.center_breakpoint or 80) then
    -- Centered layout for small terminals
    width = math.floor(vim.o.columns * 0.6)
    height = math.floor(vim.o.lines * 0.6)
    row = math.floor((vim.o.lines - height) / 2)
    col = math.floor((vim.o.columns - width) / 2)
  else
    -- Sidebar layout (default)
    width = math.floor(vim.o.columns * win_config.width)
    height = math.floor(vim.o.lines * win_config.height)
    row = win_config.row
    col = vim.o.columns - width - win_config.col
  end

  -- Clamp dimensions to fit within the editor
  width = math.min(width, vim.o.columns - 2)
  height = math.min(height, vim.o.lines - 2)
  col = math.max(col, 0)
  row = math.max(row, 0)

  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = win_config.border,
  }

  if win_config.title ~= false then
    win_opts.title = " " .. (win_config.title or "Fluoride") .. " "
    win_opts.title_pos = "center"
  end

  local win = vim.api.nvim_open_win(buf, true, win_opts)

  vim.api.nvim_set_option_value("cursorline", true, { win = win })
  vim.api.nvim_set_option_value("number", true, { win = win })
  vim.api.nvim_set_option_value("relativenumber", true, { win = win })
  vim.api.nvim_set_option_value("winhighlight", "Normal:Normal,FloatBorder:Normal,FloatTitle:Normal", { win = win })
  vim.api.nvim_set_option_value("winblend", win_config.winblend, { win = win })

  return win
end

-- Track the current Fluoride window
local active_win = nil
local active_buf = nil

--- Open the Fluoride floating window.
--- @param source_bufnr number the source buffer to operate on
--- @param entries table[] list of code point entries from treesitter module
--- @param lang FluorideLang the language module
--- @param config table plugin configuration
function M.open(source_bufnr, entries, lang, config)
  -- If a Fluoride window is already open, focus it
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
  vim.api.nvim_buf_set_name(buf, "fluoride://reorder")

  -- Open the sidebar
  local win_config = config and config.window or {}
  local km = config and config.keymaps or {}
  local win = open_sidebar(buf, win_config)

  -- Apply initial syntax highlighting
  apply_highlights(buf, highlights, sorted_prefixes)

  -- Add help footer at the bottom of the window (if enabled)
  local show_footer = win_config.footer ~= false
  local footer_ns = vim.api.nvim_create_namespace("fluoride_footer")
  local function update_footer()
    vim.api.nvim_buf_clear_namespace(buf, footer_ns, 0, -1)
    if not show_footer then return end
    local line_count = vim.api.nvim_buf_line_count(buf)
    local win_height = vim.api.nvim_win_get_height(win)
    local pad = win_height - line_count - 1
    local virt_lines = {}
    if pad > 0 then
      for _ = 1, pad do
        table.insert(virt_lines, { { "", "Comment" } })
      end
    end
    local parts = { ":w=submit" }
    if km.close ~= false then table.insert(parts, (km.close or "q") .. "=close") end
    if km.peek ~= false then table.insert(parts, (km.peek or "gd") .. "=peek") end
    if km.hover ~= false then table.insert(parts, (km.hover or "K") .. "=hover") end
    table.insert(virt_lines, { { table.concat(parts, " "), "Comment" } })
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
  local numbertoggle = vim.api.nvim_create_augroup("fluoride_numbertoggle", { clear = true })
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

  -- Helper: find the source window
  local function find_source_win()
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if w ~= win and vim.api.nvim_win_get_buf(w) == source_bufnr then
        return w
      end
    end
    return nil
  end

  -- Close window helper
  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  -- Register keymaps (skip if set to false)
  local function map(key, fn, desc)
    if key ~= false then
      vim.keymap.set("n", key, fn, { buffer = buf, noremap = true, silent = true, desc = desc })
    end
  end

  -- Close
  map(km.close or "q", close, "Close Fluoride window")
  map(km.close_alt or "<C-c>", close, "Close Fluoride window")

  -- Jump to code point
  map(km.jump or "<CR>", function()
    local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
    local map_entry = flat_map[cursor_line]
    if not map_entry then return end

    local source_win = find_source_win()
    if source_win then
      local target_row = map_entry.entry.start_row + 1
      vim.api.nvim_set_current_win(source_win)
      vim.api.nvim_win_set_cursor(source_win, { target_row, 0 })
      vim.fn.winrestview({ topline = target_row })
    end
  end, "Jump to code point")

  -- Peek at code point
  local peek_ns = vim.api.nvim_create_namespace("fluoride_peek")
  map(km.peek or "gd", function()
    local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
    local map_entry = flat_map[cursor_line]
    if not map_entry then return end

    local source_win = find_source_win()
    if source_win then
      local target_row = map_entry.entry.start_row + 1
      vim.api.nvim_win_call(source_win, function()
        vim.api.nvim_win_set_cursor(source_win, { target_row, 0 })
        vim.cmd("normal! zz")
      end)

      vim.api.nvim_buf_clear_namespace(source_bufnr, peek_ns, 0, -1)
      for row = map_entry.entry.start_row, map_entry.entry.end_row do
        vim.api.nvim_buf_add_highlight(source_bufnr, peek_ns, "Visual", row, 0, -1)
      end

      vim.defer_fn(function()
        if vim.api.nvim_buf_is_valid(source_bufnr) then
          vim.api.nvim_buf_clear_namespace(source_bufnr, peek_ns, 0, -1)
        end
      end, 200)
    end
  end, "Peek at code point")

  -- LSP hover
  map(km.hover or "K", function()
    local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
    local map_entry = flat_map[cursor_line]
    if not map_entry then return end

    local source_win = find_source_win()
    if source_win then
      local target_row = map_entry.entry.decl_start_row + 1
      vim.api.nvim_set_current_win(source_win)

      local name = map_entry.entry.name
      local decl_line = vim.api.nvim_buf_get_lines(source_bufnr, target_row - 1, target_row, false)[1] or ""
      local col = 0
      if name and #name > 0 then
        local pattern = "%f[%w_]" .. vim.pesc(name) .. "%f[^%w_]"
        local found = decl_line:find(pattern)
        if found then
          col = found - 1
        end
      end

      vim.api.nvim_win_set_cursor(source_win, { target_row, col })
      vim.lsp.buf.hover()
    end
  end, "LSP hover for code point")

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

        local ok, err, renames, deletions = reorder.apply(source_bufnr, entries, filtered, lang)

        -- Handle deletions: show confirmation if needed
        local did_delete = false
        if not ok and deletions and #deletions > 0 then
          local confirm_delete = config and config.confirm_delete
          if confirm_delete == nil then confirm_delete = true end

          local names = {}
          for _, d in ipairs(deletions) do
            local label = d.display_type .. " " .. d.name
            if d.parent_name then
              label = label .. " (in " .. d.parent_name .. ")"
            end
            table.insert(names, label)
          end

          if not confirm_delete then
            -- Skip confirmation — re-apply with deletions allowed
            ok, err, renames = reorder.apply(source_bufnr, entries, filtered, lang, true)
            did_delete = ok
          else
            local answer = vim.fn.confirm(
              "Delete " .. table.concat(names, ", ") .. "?",
              "&Yes\n&No",
              2
            )
            if answer == 1 then
              ok, err, renames = reorder.apply(source_bufnr, entries, filtered, lang, true)
              did_delete = ok
            else
              return -- user cancelled
            end
          end
        end

        if not ok then
          vim.notify("Fluoride: " .. (err or "unknown error"), vim.log.levels.WARN)
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

        -- Refresh the Fluoride list after changes are applied
        local function refresh()
          format_source()

          -- Re-extract declarations from the updated source buffer
          local treesitter = require("fluoride.treesitter")
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
              "Fluoride: reorder applied, but no LSP client with rename support is attached. "
                .. #renames .. " rename(s) skipped.",
              vim.log.levels.WARN
            )
            refresh()
            return
          end

          vim.notify("Fluoride: reorder applied, processing " .. #renames .. " rename(s)...", vim.log.levels.INFO)
          rename.apply_renames(source_bufnr, renames, function()
            vim.notify("Fluoride: all renames complete", vim.log.levels.INFO)
            refresh()
          end)
        else
          local msg = did_delete and "Fluoride: deletion applied" or "Fluoride: reorder applied"
          vim.notify(msg, vim.log.levels.INFO)
          refresh()
        end
      end)

      if not success then
        vim.notify("Fluoride: " .. tostring(errmsg), vim.log.levels.WARN)
      end
    end,
  })

  -- Track the active window/buffer
  active_win = win
  active_buf = buf

  -- Reposition window when terminal is resized.
  -- Sidebar mode: keep the initial pixel dimensions, only reposition.
  -- Centered mode: recalculate proportionally.
  local sidebar_width = math.floor(vim.o.columns * win_config.width)
  local sidebar_height = math.floor(vim.o.lines * win_config.height)
  local resize_group = vim.api.nvim_create_augroup("fluoride_resize", { clear = true })
  vim.api.nvim_create_autocmd("VimResized", {
    group = resize_group,
    callback = function()
      if not vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_del_augroup_by_id(resize_group)
        return
      end

      local new_width, new_height, new_row, new_col
      if vim.o.columns < (win_config.center_breakpoint or 80) then
        new_width = math.floor(vim.o.columns * 0.6)
        new_height = math.floor(vim.o.lines * 0.6)
        new_row = math.floor((vim.o.lines - new_height) / 2)
        new_col = math.floor((vim.o.columns - new_width) / 2)
      else
        new_width = sidebar_width
        new_height = sidebar_height
        new_row = win_config.row
        new_col = vim.o.columns - new_width - win_config.col
      end

      new_width = math.min(new_width, vim.o.columns - 2)
      new_height = math.min(new_height, vim.o.lines - 2)
      new_col = math.max(new_col, 0)
      new_row = math.max(new_row, 0)

      vim.api.nvim_win_set_config(win, {
        relative = "editor",
        width = new_width,
        height = new_height,
        row = new_row,
        col = new_col,
      })
    end,
  })

  -- Auto-reload code points when the source file is saved
  vim.api.nvim_create_autocmd("BufWritePost", {
    buffer = source_bufnr,
    callback = function()
      if not vim.api.nvim_win_is_valid(win) then return end
      if not vim.api.nvim_buf_is_valid(buf) then return end

      local ok, _ = pcall(function()
        local treesitter = require("fluoride.treesitter")
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
      end)
    end,
  })

  -- Cleanup buffer when window is closed
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      active_win = nil
      active_buf = nil
      pcall(vim.api.nvim_del_augroup_by_id, resize_group)
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end,
  })
end

return M
