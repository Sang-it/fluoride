local reorder = require("fluoride.reorder")
local rename = require("fluoride.rename")

local M = {}

local ns = vim.api.nvim_create_namespace("fluoride_hl")
local fold_ns = vim.api.nvim_create_namespace("fluoride_fold")

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

--- Build the indentation prefix for a given nesting depth.
--- @param depth number nesting depth (0 = top-level, 1 = child, 2 = grandchild, etc.)
--- @return string prefix
local function depth_prefix(depth)
  if depth == 0 then
    return ""
  end
  -- Each depth level: 2 spaces of indent per level, then bullet + space
  return string.rep("  ", depth) .. "• "
end

--- Recursively add display lines for an entry and its children.
--- @param lines string[] accumulator for display lines
--- @param flat_map table[] accumulator for flat entry map
--- @param entry table code point entry
--- @param depth number current nesting depth (0 = top-level)
--- @param max_depth number maximum depth to display children
--- @param path number[] ancestor indices path
--- @param collapsed table|nil set of entries whose children are folded
local function add_entry_lines(lines, flat_map, entry, depth, max_depth, path, collapsed)
  local prefix = depth_prefix(depth)
  table.insert(lines, prefix .. entry_display(entry))
  table.insert(flat_map, { entry = entry, depth = depth, path = vim.deepcopy(path) })

  local is_collapsed = collapsed and collapsed[entry]
  if depth < max_depth and entry.children and #entry.children > 0 and not is_collapsed then
    local last_access = nil
    for j, child in ipairs(entry.children) do
      -- Insert access specifier separator when access changes (C/C++ public/protected/private)
      if child.access and child.access ~= last_access then
        local sep_prefix = string.rep("  ", depth + 1)
        table.insert(lines, sep_prefix .. "-- " .. child.access)
        table.insert(flat_map, { entry = nil, depth = depth + 1, path = nil, is_separator = true })
      end
      last_access = child.access

      local child_path = vim.deepcopy(path)
      table.insert(child_path, j)
      add_entry_lines(lines, flat_map, child, depth + 1, max_depth, child_path, collapsed)
    end
  end
end

--- Build display lines and a flat entry map from code point entries.
--- The flat_map maps each 1-indexed buffer line to its entry with depth and path.
--- @param entries table[] list of code point entries from treesitter module
--- @param max_depth number maximum nesting depth to display (0 = no children)
--- @param collapsed table|nil set of entries whose children are folded
--- @return string[] display_lines
--- @return table[] flat_map list of { entry, depth, path }
local function build_display_lines(entries, max_depth, collapsed)
  local lines = {}
  local flat_map = {}

  for i, entry in ipairs(entries) do
    add_entry_lines(lines, flat_map, entry, 0, max_depth, { i }, collapsed)
  end

  return lines, flat_map
end

--- Apply fold indicators (▸/▾) as virtual text on entries that have children.
--- @param buf number buffer handle
--- @param flat_map table[] flat entry map
--- @param max_depth number current max depth
--- @param collapsed table set of collapsed entries
local function apply_fold_indicators(buf, flat_map, max_depth, collapsed)
  vim.api.nvim_buf_clear_namespace(buf, fold_ns, 0, -1)
  for i, map_entry in ipairs(flat_map) do
    local entry = map_entry.entry
    if entry and entry.children and #entry.children > 0 then
      local indicator = (collapsed[entry] or map_entry.depth >= max_depth) and " ▸" or " ▾"
      vim.api.nvim_buf_set_extmark(buf, fold_ns, i - 1, 0, {
        virt_text = { { indicator, "Comment" } },
        virt_text_pos = "eol",
      })
    end
  end
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

    -- Check if this is an access specifier separator (-- public, -- protected, -- private)
    local trimmed = vim.trim(line)
    if trimmed:match("^%-%- %w+$") then
      vim.api.nvim_buf_add_highlight(buf, ns, "Comment", lnum, 0, -1)
      goto continue
    end

    -- Check if this is a user-written comment line (starts with //)
    if trimmed:sub(1, 2) == "//" then
      vim.api.nvim_buf_add_highlight(buf, ns, "Comment", lnum, 0, -1)
      goto continue
    end

    -- Detect indentation depth by counting leading "  " units before "• "
    local content_start = 0
    local depth = 0

    -- Check for nested child indent prefixes at any depth
    local bullet_pos = line:find("• ", 1, true)
    if bullet_pos then
      -- All characters before the bullet should be spaces (2 per depth level)
      local leading = line:sub(1, bullet_pos - 1)
      if leading:match("^%s*$") and #leading > 0 and #leading % 2 == 0 then
        depth = #leading / 2
        content_start = bullet_pos + #("• ") - 1 -- after "• " (bullet is multi-byte)
        -- Highlight the indent + bullet as Comment
        vim.api.nvim_buf_add_highlight(buf, ns, "Comment", lnum, 0, content_start)
      end
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

--- Compute sidebar geometry, avoiding the source window when splits exist.
--- @param source_win number|nil source window handle
--- @param win_config table window configuration from plugin config
--- @return number width, number height, number row, number col
local function compute_sidebar_geometry(source_win, win_config)
  local sidebar = win_config.sidebar or {}
  local centered = win_config.centered or {}
  local width, height, row, col

  if vim.o.columns < (win_config.center_breakpoint or 80) then
    -- Centered layout for small terminals
    width = math.floor(vim.o.columns * (centered.width or 0.6))
    height = math.floor(vim.o.lines * (centered.height or 0.6))
    row = math.floor((vim.o.lines - height) / 2)
    col = math.floor((vim.o.columns - width) / 2)
  else
    -- Sidebar dimensions from editor proportions
    width = math.floor(vim.o.columns * (sidebar.width or 0.3))
    height = math.floor(vim.o.lines * (sidebar.height or 0.85))
    row = sidebar.row or 2

    -- Place on the far edge that doesn't overlap the focused source window
    local far_right = vim.o.columns - width - (sidebar.col or 2)
    local far_left = sidebar.col or 2

    if source_win and vim.api.nvim_win_is_valid(source_win) then
      local src_pos = vim.api.nvim_win_get_position(source_win)
      local src_col = src_pos[2]
      local src_width = vim.api.nvim_win_get_width(source_win)
      local src_end = src_col + src_width

      -- Check if far right overlaps the source window
      local right_overlaps = far_right < src_end and (far_right + width) > src_col
      -- Check if far left overlaps the source window
      local left_overlaps = far_left < src_end and (far_left + width) > src_col

      if not right_overlaps then
        col = far_right
      elseif not left_overlaps then
        col = far_left
      else
        -- Fallback: single window, default to far right
        col = far_right
      end
    else
      col = far_right
    end
  end

  -- Clamp to editor bounds
  width = math.max(math.min(width, vim.o.columns - 2), 1)
  height = math.max(math.min(height, vim.o.lines - 2), 1)
  col = math.max(math.min(col, vim.o.columns - width - 1), 0)
  row = math.max(math.min(row, vim.o.lines - height - 1), 0)

  return width, height, row, col
end

--- Create a floating window positioned relative to the source window.
--- @param buf number buffer handle
--- @param win_config table window configuration from plugin config
--- @param source_win number|nil source window handle
--- @return number win window handle
local function open_sidebar(buf, win_config, source_win)
  local width, height, row, col = compute_sidebar_geometry(source_win, win_config)

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

  -- Populate the buffer with display lines (placeholder, repopulated after config is read)
  local display_lines, flat_map = build_display_lines(entries, 0)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, display_lines)

  -- Mark the buffer as unmodified after initial population
  vim.api.nvim_set_option_value("modified", false, { buf = buf })

  -- Give it a name so :w doesn't complain about no file name
  vim.api.nvim_buf_set_name(buf, "fluoride://reorder")

  -- Open the sidebar
  local win_config = config and config.window or {}
  local km = config and config.keymaps or {}
  local hl_config = config and config.highlight or {}
  local peek_duration = hl_config.peek_duration or 200
  local rename_duration = hl_config.rename_duration or 130
  local configured_max_depth = config and config.max_depth or 1
  local current_depth = configured_max_depth
  local collapsed = {} -- per-entry fold state (entry reference -> true)
  local current_source_win = vim.api.nvim_get_current_win()
  local win = open_sidebar(buf, win_config, current_source_win)

  -- Repopulate with correct depth state
  display_lines, flat_map = build_display_lines(entries, current_depth, collapsed)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, display_lines)
  vim.api.nvim_set_option_value("modified", false, { buf = buf })

  -- Apply initial syntax highlighting and fold indicators
  apply_highlights(buf, highlights, sorted_prefixes)
  apply_fold_indicators(buf, flat_map, current_depth, collapsed)

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
    table.insert(parts, "<Tab>=fold")
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

  -- Helper: find the 0-indexed column of a symbol name on a buffer line
  local function find_symbol_col(name, row)
    if not name or #name == 0 then return 0 end
    local line = vim.api.nvim_buf_get_lines(source_bufnr, row, row + 1, false)[1] or ""
    local pattern = "%f[%w_]" .. vim.pesc(name) .. "%f[^%w_]"
    local found = line:find(pattern)
    return found and (found - 1) or 0
  end

  -- Helper: find the source window
  local function find_source_win()
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if w ~= win and vim.api.nvim_win_get_buf(w) == source_bufnr then
        return w
      end
    end
    return nil
  end

  -- Reposition sidebar relative to the current source window
  local function reposition_sidebar()
    if not vim.api.nvim_win_is_valid(win) then return end
    local src_win = current_source_win
    if not src_win or not vim.api.nvim_win_is_valid(src_win) then
      src_win = find_source_win()
    end
    if not src_win then return end
    local width, height, row, col = compute_sidebar_geometry(src_win, win_config)
    vim.api.nvim_win_set_config(win, {
      relative = "editor",
      width = width,
      height = height,
      row = row,
      col = col,
    })
  end

  -- Close window helper
  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  -- Peek/flash namespace (shared by peek and yank keymaps)
  local peek_ns = vim.api.nvim_create_namespace("fluoride_peek")

  -- Flash an entry range in the source window, clearing after peek_duration ms
  local function flash_entry_range(entry)
    vim.api.nvim_buf_clear_namespace(source_bufnr, peek_ns, 0, -1)
    for row = entry.start_row, entry.end_row do
      pcall(vim.api.nvim_buf_add_highlight, source_bufnr, peek_ns, "Visual", row, 0, -1)
    end
    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(source_bufnr) then
        vim.api.nvim_buf_clear_namespace(source_bufnr, peek_ns, 0, -1)
      end
    end, peek_duration)
  end

  -- Register all keymaps for the Fluoride buffer
  local function setup_keymaps()
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
      if not map_entry or not map_entry.entry then return end

      local source_win = find_source_win()
      if source_win then
        local target_row = map_entry.entry.decl_start_row + 1
        vim.api.nvim_set_current_win(source_win)
        local col = find_symbol_col(map_entry.entry.name, target_row - 1)
        vim.api.nvim_win_set_cursor(source_win, { target_row, col })
        vim.cmd("normal! zz")
      end
    end, "Jump to code point")

    -- Peek at code point
    map(km.peek or "gd", function()
      local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
      local map_entry = flat_map[cursor_line]
      if not map_entry or not map_entry.entry then return end

      local source_win = find_source_win()
      if source_win then
        local target_row = map_entry.entry.start_row + 1
        vim.api.nvim_win_call(source_win, function()
          vim.api.nvim_win_set_cursor(source_win, { target_row, 0 })
          vim.cmd("normal! zz")
        end)
        flash_entry_range(map_entry.entry)
      end
    end, "Peek at code point")

    -- LSP hover
    map(km.hover or "K", function()
      local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
      local map_entry = flat_map[cursor_line]
      if not map_entry or not map_entry.entry then return end

      local source_win = find_source_win()
      if source_win then
        local target_row = map_entry.entry.decl_start_row + 1
        vim.api.nvim_set_current_win(source_win)
        local col = find_symbol_col(map_entry.entry.name, target_row - 1)
        vim.api.nvim_win_set_cursor(source_win, { target_row, col })
        vim.cmd("normal! zz")
        vim.lsp.buf.hover()
      end
    end, "LSP hover for code point")

    -- Cycle global depth visibility
    local function cycle_global_depth()
      -- Compute the actual max depth present in the entries so we don't
      -- cycle through depths that produce no visible difference
      local function get_max_depth(entry_list, depth)
        local max_d = depth
        for _, e in ipairs(entry_list) do
          if e.children and #e.children > 0 then
            local child_d = get_max_depth(e.children, depth + 1)
            if child_d > max_d then max_d = child_d end
          end
        end
        return max_d
      end
      local effective_max = math.min(configured_max_depth, get_max_depth(entries, 0))

      if current_depth >= effective_max then
        current_depth = 0
      else
        current_depth = current_depth + 1
      end

      -- Reset per-entry folds when cycling global depth
      collapsed = {}

      local new_display_lines, new_flat_map = build_display_lines(entries, current_depth, collapsed)
      flat_map = new_flat_map
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_display_lines)
      vim.api.nvim_set_option_value("modified", false, { buf = buf })
      apply_highlights(buf, highlights, sorted_prefixes)
      apply_fold_indicators(buf, flat_map, current_depth, collapsed)
      update_footer()
    end

    -- Toggle fold for entry under cursor, or cycle global depth for non-containers
    map(km.toggle_children or "<Tab>", function()
      local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
      local map_entry = flat_map[cursor_line]
      if not map_entry or not map_entry.entry then return end

      local entry = map_entry.entry
      local has_children = entry.children and #entry.children > 0

      -- Non-container entries: fall back to global depth cycling
      if not has_children then
        cycle_global_depth()
        return
      end

      -- If children aren't visible yet (current_depth too low), bump depth
      -- and collapse everything else so only this container expands
      if map_entry.depth >= current_depth then
        current_depth = map_entry.depth + 1
        local function collapse_all(entry_list)
          for _, e in ipairs(entry_list) do
            if e.children and #e.children > 0 then
              collapsed[e] = true
              collapse_all(e.children)
            end
          end
        end
        collapse_all(entries)
        collapsed[entry] = nil
      else
        -- Normal toggle
        if collapsed[entry] then
          collapsed[entry] = nil
        else
          collapsed[entry] = true
        end
      end

      -- Rebuild display
      local new_display_lines, new_flat_map = build_display_lines(entries, current_depth, collapsed)
      flat_map = new_flat_map
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_display_lines)
      vim.api.nvim_set_option_value("modified", false, { buf = buf })
      apply_highlights(buf, highlights, sorted_prefixes)
      apply_fold_indicators(buf, flat_map, current_depth, collapsed)
      update_footer()

      -- Keep cursor on the same entry
      for j, m in ipairs(flat_map) do
        if m.entry == entry then
          vim.api.nvim_win_set_cursor(win, { j, 0 })
          break
        end
      end
    end, "Toggle fold for entry under cursor")

    map(km.cycle_depth or "<S-Tab>", cycle_global_depth, "Cycle global depth")

    -- Peek + copy code block
    local yank_comments = config and config.yank_comments ~= false
    map(km.yank or "gy", function()
      local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
      local map_entry = flat_map[cursor_line]
      if not map_entry or not map_entry.entry then return end

      local source_win = find_source_win()
      if source_win then
        local target_row = map_entry.entry.start_row + 1

        -- Center + flash (same as gd)
        vim.api.nvim_win_call(source_win, function()
          vim.api.nvim_win_set_cursor(source_win, { target_row, 0 })
          vim.cmd("normal! zz")
        end)
        flash_entry_range(map_entry.entry)

        -- Copy the code block
        local copy_start = map_entry.entry.start_row
        if not yank_comments then
          copy_start = map_entry.entry.decl_start_row
        end
        local lines = vim.api.nvim_buf_get_lines(source_bufnr, copy_start, map_entry.entry.end_row + 1, false)
        local text = table.concat(lines, "\n")
        vim.fn.setreg('"', text, "l")
        vim.fn.setreg("+", text, "l")
        vim.notify("Fluoride: copied " .. #lines .. " lines", vim.log.levels.INFO)
      end
    end, "Peek and copy code block")
  end

  setup_keymaps()

  -- Build a stable identity key for an entry based on its position in the tree.
  -- Uses display_type + name at each ancestor level to survive re-parsing.
  local function entry_key(entry, parent_keys)
    local key = (entry.display_type or "") .. ":" .. (entry.name or "")
    if parent_keys then
      return parent_keys .. "/" .. key
    end
    return key
  end

  -- Collect keys of all collapsed entries from the current entry tree.
  local function collect_collapsed_keys(entry_list, parent_keys)
    local keys = {}
    for _, e in ipairs(entry_list) do
      local k = entry_key(e, parent_keys)
      if collapsed[e] then
        keys[k] = true
      end
      if e.children and #e.children > 0 then
        local child_keys = collect_collapsed_keys(e.children, k)
        for ck, v in pairs(child_keys) do
          keys[ck] = v
        end
      end
    end
    return keys
  end

  -- Restore collapsed state on new entries by matching keys.
  local function restore_collapsed(entry_list, saved_keys, parent_keys)
    for _, e in ipairs(entry_list) do
      local k = entry_key(e, parent_keys)
      if saved_keys[k] then
        collapsed[e] = true
      end
      if e.children and #e.children > 0 then
        restore_collapsed(e.children, saved_keys, k)
      end
    end
  end

  -- Per-buffer state storage for split support
  local buf_states = {}

  local function save_current_state()
    buf_states[source_bufnr] = {
      collapsed_keys = collect_collapsed_keys(entries, nil),
      current_depth = current_depth,
    }
  end

  local function rebuild_display()
    local new_display_lines, new_flat_map = build_display_lines(entries, current_depth, collapsed)
    flat_map = new_flat_map
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_display_lines)
    vim.api.nvim_set_option_value("modified", false, { buf = buf })
    apply_highlights(buf, highlights, sorted_prefixes)
    apply_fold_indicators(buf, flat_map, current_depth, collapsed)
    update_footer()
  end

  local function switch_source(new_bufnr)
    if new_bufnr == source_bufnr then return end
    if not vim.api.nvim_buf_is_valid(new_bufnr) then return end

    -- Don't switch if Fluoride buffer has unsaved reorder changes
    if vim.api.nvim_get_option_value("modified", { buf = buf }) then return end

    -- Try to parse the new buffer
    local treesitter = require("fluoride.treesitter")
    local new_entries, new_lang = treesitter.get_code_points(new_bufnr)
    if not new_lang or #new_entries == 0 then return end

    -- Save current buffer state
    save_current_state()

    -- Switch to new buffer
    source_bufnr = new_bufnr
    entries = new_entries
    lang = new_lang
    highlights = new_lang.highlights or {}
    sorted_prefixes = build_sorted_prefixes(highlights)

    -- Restore saved state or use defaults
    local saved = buf_states[new_bufnr]
    if saved then
      current_depth = saved.current_depth
      collapsed = {}
      restore_collapsed(entries, saved.collapsed_keys, nil)
    else
      current_depth = configured_max_depth
      collapsed = {}
    end

    rebuild_display()

    -- Reposition sidebar next to the new source window
    current_source_win = find_source_win()
    reposition_sidebar()
  end

  -- Refresh the Fluoride display from the source buffer
  local function refresh_display()
    local treesitter = require("fluoride.treesitter")
    local new_entries, _ = treesitter.get_code_points(source_bufnr)
    if #new_entries > 0 then
      -- Preserve fold state across re-parse by matching on entry identity
      local saved_keys = collect_collapsed_keys(entries, nil)
      entries = new_entries
      collapsed = {}
      restore_collapsed(entries, saved_keys, nil)

      local new_display_lines, new_flat_map = build_display_lines(entries, current_depth, collapsed)
      flat_map = new_flat_map
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_display_lines)
      vim.api.nvim_set_option_value("modified", false, { buf = buf })
      apply_highlights(buf, highlights, sorted_prefixes)
      apply_fold_indicators(buf, flat_map, current_depth, collapsed)
      update_footer()
    end
  end

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

        local ok, err, renames, deletions, affected_names, changes_made = reorder.apply(source_bufnr, entries, filtered, lang)

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
            ok, err, renames, _, affected_names, changes_made = reorder.apply(source_bufnr, entries, filtered, lang, true)
            did_delete = ok
          else
            local answer = vim.fn.confirm(
              "Delete " .. table.concat(names, ", ") .. "?",
              "&Yes\n&No",
              2
            )
            if answer == 1 then
              ok, err, renames, _, affected_names, changes_made = reorder.apply(source_bufnr, entries, filtered, lang, true)
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
          local source_win = find_source_win()
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

        -- Flash affected entries sequentially in the source window
        local flash_ns = vim.api.nvim_create_namespace("fluoride_save_flash")
        local function flash_affected(affected)
          if not affected or #affected == 0 then return end

          local source_win = find_source_win()
          if not source_win then return end

          -- Find affected entries by matching name + declaration row.
          -- Each affected item has { new_name, decl_row } from the result buffer.
          -- After LSP rename, rows may shift slightly, so find the entry with
          -- matching name whose decl_start_row is closest to decl_row.
          local to_flash = {}

          local function collect_affected(entry_list)
            for _, entry in ipairs(entry_list) do
              for ai, a in ipairs(affected) do
                if entry.name == a.new_name then
                  -- Check if this entry's position is close to the expected row
                  local dist = math.abs(entry.decl_start_row - a.decl_row)
                  if not a.best_entry or dist < a.best_dist then
                    a.best_entry = entry
                    a.best_dist = dist
                  end
                end
              end
              if entry.children then
                collect_affected(entry.children)
              end
            end
          end
          collect_affected(entries)

          -- Collect the best matches
          for _, a in ipairs(affected) do
            if a.best_entry then
              table.insert(to_flash, a.best_entry)
            end
          end

          if #to_flash == 0 then return end

          local index = 1
          local function flash_next()
            if index > #to_flash then
              -- Clear the last flash
              vim.defer_fn(function()
                if vim.api.nvim_buf_is_valid(source_bufnr) then
                  vim.api.nvim_buf_clear_namespace(source_bufnr, flash_ns, 0, -1)
                end
              end, rename_duration)
              return
            end

            -- Clear previous
            vim.api.nvim_buf_clear_namespace(source_bufnr, flash_ns, 0, -1)

            local entry = to_flash[index]

            -- Scroll source window to center the entry
            if vim.api.nvim_win_is_valid(source_win) then
              pcall(function()
                vim.api.nvim_win_call(source_win, function()
                  vim.api.nvim_win_set_cursor(source_win, { entry.start_row + 1, 0 })
                  vim.cmd("normal! zz")
                end)
              end)
            end

            -- Highlight the entry
            for row = entry.start_row, entry.end_row do
              pcall(vim.api.nvim_buf_add_highlight, source_bufnr, flash_ns, "Visual", row, 0, -1)
            end

            index = index + 1
            vim.defer_fn(flash_next, rename_duration)
          end

          flash_next()
        end

        -- Refresh the Fluoride list after changes are applied
        local function refresh(affected)
          format_source()
          refresh_display()
          flash_affected(affected)
        end

        -- Apply LSP renames if any names were changed
        if renames and #renames > 0 then
          if not rename.has_rename_support(source_bufnr) then
            vim.notify(
              "Fluoride: no LSP client with rename support attached. "
                .. #renames .. " rename(s) skipped.",
              vim.log.levels.WARN
            )
            refresh(affected_names)
            return
          end

          vim.notify("Fluoride: processing " .. #renames .. " rename(s)...", vim.log.levels.INFO)
          rename.apply_renames(source_bufnr, renames, function()
            vim.notify("Fluoride: " .. #renames .. " rename(s) complete", vim.log.levels.INFO)
            refresh(affected_names)
          end)
        else
          -- Show reorder/deletion message only if changes were actually made
          if changes_made then
            local msg = did_delete and "Fluoride: deletion applied" or "Fluoride: reorder applied"
            vim.notify(msg, vim.log.levels.INFO)
          end
          refresh(affected_names)
        end
      end)

      if not success then
        vim.notify("Fluoride: " .. tostring(errmsg), vim.log.levels.WARN)
      end
    end,
  })

  -- Track the active window
  active_win = win

  -- Reposition sidebar when terminal or splits are resized
  local resize_group = vim.api.nvim_create_augroup("fluoride_resize", { clear = true })
  vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    group = resize_group,
    callback = function()
      if not vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_del_augroup_by_id(resize_group)
        return
      end
      reposition_sidebar()
    end,
  })

  -- Auto-reload code points when the current source file is saved
  local source_group = vim.api.nvim_create_augroup("fluoride_source", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = source_group,
    callback = function(ev)
      if not vim.api.nvim_win_is_valid(win) then return end
      if not vim.api.nvim_buf_is_valid(buf) then return end
      if ev.buf ~= source_bufnr then return end

      pcall(refresh_display)
    end,
  })

  -- Switch source when user enters a different split or changes buffer
  vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
    group = source_group,
    callback = function()
      if not vim.api.nvim_win_is_valid(win) then return end
      local entered_win = vim.api.nvim_get_current_win()
      if entered_win == win then return end
      local new_bufnr = vim.api.nvim_win_get_buf(entered_win)
      if new_bufnr == buf then return end

      current_source_win = entered_win
      if new_bufnr ~= source_bufnr then
        switch_source(new_bufnr)
      else
        -- Same buffer in a different window — just reposition
        reposition_sidebar()
      end
    end,
  })

  -- Cleanup buffer when window is closed
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      active_win = nil
      pcall(vim.api.nvim_del_augroup_by_id, resize_group)
      pcall(vim.api.nvim_del_augroup_by_id, source_group)
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end,
  })
end

return M
