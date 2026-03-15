local diff = require("code-points.diff")

local M = {}

-- Child indentation (must match window.lua)
local CHILD_PREFIX = "  • "
local CHILD_PREFIX_LEN = #CHILD_PREFIX

--- Build a sorted list of type prefixes from a lang's highlights table.
--- @param lang CodePointsLang the language module
--- @return string[] type_prefixes
local function build_type_prefixes(lang)
  local prefixes = {}
  if lang and lang.highlights then
    for prefix in pairs(lang.highlights) do
      table.insert(prefixes, prefix)
    end
  end
  table.sort(prefixes, function(a, b) return #a > #b end)
  return prefixes
end

--- Strip the arity suffix (e.g., "/2") from a name.
--- @param name string
--- @return string name_without_arity
local function strip_arity(name)
  return name:match("^(.+)/%d+$") or name
end

--- Translate a comment line from universal // prefix to the language's native syntax.
--- e.g., "// my comment" → "# my comment" for Python, "-- my comment" for Lua.
--- @param line string the comment line starting with //
--- @param lang_prefix string the language's native comment prefix
--- @return string translated comment line
local function translate_comment(line, lang_prefix)
  if lang_prefix == "//" then
    return line -- no translation needed
  end
  -- Strip the // prefix and replace with the native prefix
  local content = line:match("^//(.*)")
  if content then
    return lang_prefix .. content
  end
  return line
end

--- Check if a display line is a child (has indent prefix).
--- @param line string
--- @return boolean is_child
--- @return string content the line content without indent prefix
local function parse_child_prefix(line)
  if line:sub(1, CHILD_PREFIX_LEN) == CHILD_PREFIX then
    return true, line:sub(CHILD_PREFIX_LEN + 1)
  end
  return false, line
end

--- Parse a display line to extract the type prefix and name.
--- @param content string the content (without tree prefix)
--- @param type_prefixes string[] sorted list of known type prefixes
--- @return string|nil prefix
--- @return string|nil name (without arity)
local function parse_display_content(content, type_prefixes)
  local trimmed = vim.trim(content)
  if trimmed == "" then
    return nil, nil
  end

  for _, prefix in ipairs(type_prefixes) do
    if trimmed:sub(1, #prefix) == prefix then
      local rest = trimmed:sub(#prefix + 1)
      rest = vim.trim(rest)
      if rest ~= "" then
        return prefix, strip_arity(rest)
      end
    end
  end

  return nil, strip_arity(trimmed)
end

--- Three-pass matching of parsed items to original entries.
--- @param parsed table[] list of { prefix, name }
--- @param originals table[] list of entries with .name and .display_type
--- @return table matched map of new_index → original_index
--- @return string|nil error
local function match_entries(parsed, originals)
  local matched = {}
  local used = {}

  -- Pass 1: exact name match
  for i, p in ipairs(parsed) do
    for j, entry in ipairs(originals) do
      if not used[j] and p.name == entry.name then
        matched[i] = j
        used[j] = true
        break
      end
    end
  end

  -- Pass 2: match by type prefix
  for i, p in ipairs(parsed) do
    if not matched[i] then
      for j, entry in ipairs(originals) do
        if not used[j] and p.prefix and p.prefix == entry.display_type then
          matched[i] = j
          used[j] = true
          break
        end
      end
    end
  end

  -- Pass 3: fallback
  for i, _ in ipairs(parsed) do
    if not matched[i] then
      for j, _ in ipairs(originals) do
        if not used[j] then
          matched[i] = j
          used[j] = true
          break
        end
      end
    end
  end

  -- Verify
  for i, _ in ipairs(parsed) do
    if not matched[i] then
      return matched, "could not match item " .. i
    end
  end

  return matched, nil
end

--- Check if children order changed compared to original.
--- @param matched table map of new_index → original_index
--- @param count number number of children
--- @return boolean changed
local function children_order_changed(matched, count)
  for i = 1, count do
    if matched[i] ~= i then
      return true
    end
  end
  return false
end

--- Reconstruct a parent entry's lines with reordered children.
--- Decomposes the parent into header/children/footer and reassembles.
--- Preserves gaps between children (which may contain comments).
--- @param parent table the original parent entry
--- @param ordered_children table[] children in new order
--- @param child_matched table map of new_child_index → original_child_index
--- @param child_groups table[]|nil parsed child groups with new_comments
--- @param lang_prefix string|nil the language's native comment prefix
--- @return string[] new_lines
local function reconstruct_parent(parent, ordered_children, child_matched, child_groups, lang_prefix)
  if not ordered_children or #ordered_children == 0 then
    return parent.lines
  end

  local orig_children = parent.children

  -- Find the earliest and latest child rows in the ORIGINAL ordering
  local min_child_row = parent.end_row
  local max_child_row = parent.start_row
  for _, child in ipairs(orig_children) do
    if child.start_row < min_child_row then
      min_child_row = child.start_row
    end
    if child.end_row > max_child_row then
      max_child_row = child.end_row
    end
  end

  -- Header: from parent start to first child start (in original layout)
  local header = {}
  for row = parent.start_row, min_child_row - 1 do
    table.insert(header, parent.lines[row - parent.start_row + 1])
  end

  -- Footer: from after last child end to parent end (in original layout)
  local footer = {}
  for row = max_child_row + 1, parent.end_row do
    table.insert(footer, parent.lines[row - parent.start_row + 1])
  end

  -- Collect trailing gaps between consecutive children (in original order)
  local child_trailing_gaps = {}
  for i = 1, #orig_children do
    child_trailing_gaps[i] = {}
    if i < #orig_children then
      local gap_start = orig_children[i].end_row + 1
      local gap_end = orig_children[i + 1].start_row - 1
      if gap_end >= gap_start then
        for row = gap_start, gap_end do
          table.insert(child_trailing_gaps[i], parent.lines[row - parent.start_row + 1])
        end
      end
    end
  end

  -- Reassemble: header + children (new order) with preserved gaps + footer
  local result = {}
  for _, line in ipairs(header) do
    table.insert(result, line)
  end

  for i, child in ipairs(ordered_children) do
    -- Insert new comments above the child (between existing comments and declaration)
    local child_group = child_groups and child_groups[i]
    local has_child_comments = child_group and child_group.new_comments and #child_group.new_comments > 0
    local child_comment_count = child.decl_start_row - child.start_row

    if has_child_comments and child_comment_count > 0 then
      -- Existing comments first, then new comments, then declaration
      for j = 1, child_comment_count do
        table.insert(result, child.lines[j])
      end
      -- Detect indentation from first declaration line
      local indent = child.lines[child_comment_count + 1]:match("^(%s*)")
      for _, comment_line in ipairs(child_group.new_comments) do
        table.insert(result, indent .. translate_comment(comment_line, lang_prefix or "//"))
      end
      for j = child_comment_count + 1, #child.lines do
        table.insert(result, child.lines[j])
      end
    elseif has_child_comments then
      -- No existing comments — insert new comments with proper indentation, then child
      local indent = child.lines[1]:match("^(%s*)")
      for _, comment_line in ipairs(child_group.new_comments) do
        table.insert(result, indent .. translate_comment(comment_line, lang_prefix or "//"))
      end
      for _, line in ipairs(child.lines) do
        table.insert(result, line)
      end
    else
      -- No new comments — just add child as-is
      for _, line in ipairs(child.lines) do
        table.insert(result, line)
      end
    end

    -- Add the trailing gap from the original child
    local orig_idx = child_matched[i]
    local gap = child_trailing_gaps[orig_idx]
    if gap and #gap > 0 then
      for _, line in ipairs(gap) do
        table.insert(result, line)
      end
    else
      -- No original gap — add a blank line (unless it's the last child)
      if i < #ordered_children then
        table.insert(result, "")
      end
    end
  end

  for _, line in ipairs(footer) do
    table.insert(result, line)
  end

  return result
end

--- Apply reordering (with nested children support) and detect renames.
--- @param source_bufnr number the source buffer handle
--- @param original_entries table[] the original code point entries
--- @param new_display_lines string[] the reordered/edited display lines from the float
--- @param lang CodePointsLang the language module
--- @return boolean ok
--- @return string|nil error
--- @return table[] renames list of { old_name: string, new_name: string }
function M.apply(source_bufnr, original_entries, new_display_lines, lang)
  if #new_display_lines == 0 then
    return false, "no entries in the reorder list", {}
  end

  local type_prefixes = build_type_prefixes(lang)

  -- Parse display lines into a tree structure:
  -- Group consecutive child lines under their preceding parent line.
  -- Lines starting with "//" are new comments to be written to the source file.
  local parsed_groups = {} -- list of { prefix, name, children, new_comments }

  local current_parent = nil
  local pending_comments = {} -- comment lines waiting to be attached to the next entry

  for _, line in ipairs(new_display_lines) do
    local trimmed = vim.trim(line)

    -- Check if this is a new comment line (starts with //)
    if trimmed:sub(1, 2) == "//" then
      table.insert(pending_comments, trimmed)
    else
      local is_child, content = parse_child_prefix(line)
      local prefix, name = parse_display_content(content, type_prefixes)

      if not name then
        return false, "could not parse line: " .. line, {}
      end

      if is_child then
        if not current_parent then
          return false, "child line without parent: " .. line, {}
        end
        table.insert(current_parent.children, {
          prefix = prefix,
          name = name,
          new_comments = pending_comments,
        })
        pending_comments = {}
      else
        current_parent = { prefix = prefix, name = name, children = {}, new_comments = pending_comments }
        pending_comments = {}
        table.insert(parsed_groups, current_parent)
      end
    end
  end

  -- Validate parent count
  if #parsed_groups ~= #original_entries then
    return false, "parent count mismatch: expected " .. #original_entries .. " entries, got " .. #parsed_groups .. ". Do not add or remove top-level entries.", {}
  end

  -- Match top-level parents
  local parent_parsed = {}
  for _, g in ipairs(parsed_groups) do
    table.insert(parent_parsed, { prefix = g.prefix, name = g.name })
  end

  local parent_matched, err = match_entries(parent_parsed, original_entries)
  if err then
    return false, err, {}
  end

  -- Detect top-level renames
  local renames = {}
  for i, p in ipairs(parent_parsed) do
    local entry = original_entries[parent_matched[i]]
    if p.name ~= entry.name then
      table.insert(renames, { old_name = entry.name, new_name = p.name })
    end
  end

  -- Build ordered entries, handling child reordering
  local ordered_entries = {}

  for i, group in ipairs(parsed_groups) do
    local orig_entry = original_entries[parent_matched[i]]

    -- Deep copy entry so we can modify lines if children reordered
    local entry_copy = {
      name = orig_entry.name,
      display_type = orig_entry.display_type,
      arity = orig_entry.arity,
      start_row = orig_entry.start_row,
      decl_start_row = orig_entry.decl_start_row,
      end_row = orig_entry.end_row,
      lines = orig_entry.lines,
      children = orig_entry.children,
    }

    -- If this parent has children, check if they were reordered
    if orig_entry.children and #orig_entry.children > 0 then
      local orig_children = orig_entry.children

      -- Validate child count
      if #group.children ~= #orig_children then
        return false, "child count mismatch for '" .. orig_entry.name .. "': expected " .. #orig_children .. ", got " .. #group.children, {}
      end

      -- Match children
      local child_matched, child_err = match_entries(group.children, orig_children)
      if child_err then
        return false, "in '" .. orig_entry.name .. "': " .. child_err, {}
      end

      -- Build ordered children and detect child renames
      local ordered_children = {}
      for j = 1, #group.children do
        local orig_child = orig_children[child_matched[j]]
        table.insert(ordered_children, orig_child)

        if group.children[j].name ~= orig_child.name then
          table.insert(renames, { old_name = orig_child.name, new_name = group.children[j].name })
        end
      end

      -- Check if any child has new comments
      local has_child_new_comments = false
      for _, child_group in ipairs(group.children) do
        if child_group.new_comments and #child_group.new_comments > 0 then
          has_child_new_comments = true
          break
        end
      end

      -- Reconstruct if children were reordered or have new comments
      if children_order_changed(child_matched, #orig_children) or has_child_new_comments then
        local lp = lang.comment_prefix or "//"
        entry_copy.lines = reconstruct_parent(orig_entry, ordered_children, child_matched, group.children, lp)
      end
    end

    table.insert(ordered_entries, entry_copy)
  end

  -- Collect preamble (everything before the first entry)
  local total_lines = vim.api.nvim_buf_line_count(source_bufnr)
  local first_entry_row = original_entries[1].start_row
  local preamble = {}
  if first_entry_row > 0 then
    preamble = vim.api.nvim_buf_get_lines(source_bufnr, 0, first_entry_row, false)
  end

  -- Collect gaps between consecutive entries (in original order).
  -- Each gap is the content between entry[i].end_row and entry[i+1].start_row.
  -- We attach the gap as trailing content to the entry that precedes it.
  local trailing_gaps = {} -- trailing_gaps[orig_entry_index] = string[]
  for i = 1, #original_entries do
    trailing_gaps[i] = {}
    if i < #original_entries then
      local gap_start = original_entries[i].end_row + 1
      local gap_end = original_entries[i + 1].start_row - 1
      if gap_end >= gap_start then
        trailing_gaps[i] = vim.api.nvim_buf_get_lines(source_bufnr, gap_start, gap_end + 1, false)
      end
    end
  end

  -- Collect postamble (everything after the last entry)
  local last_entry_row = original_entries[#original_entries].end_row
  local postamble = {}
  if last_entry_row + 1 < total_lines then
    postamble = vim.api.nvim_buf_get_lines(source_bufnr, last_entry_row + 1, total_lines, false)
  end

  -- Build a map from ordered entry to its original index (for gap lookup)
  local orig_index_map = {} -- orig_index_map[i] = original index of ordered_entries[i]
  for i, group in ipairs(parsed_groups) do
    orig_index_map[i] = parent_matched[i]
  end

  -- Build new buffer content
  local result = {}

  for _, line in ipairs(preamble) do
    table.insert(result, line)
  end

  local lang_prefix = lang.comment_prefix or "//"

  for i, entry in ipairs(ordered_entries) do
    -- Add a blank line separator before the first entry (if preamble exists)
    if i == 1 and #preamble > 0 then
      if #result > 0 and result[#result] ~= "" then
        table.insert(result, "")
      end
    end

    -- Add the entry's lines, inserting new comments between existing comments and the declaration
    local group = parsed_groups[i]
    local has_new_comments = group.new_comments and #group.new_comments > 0
    local comment_line_count = entry.decl_start_row - entry.start_row

    if has_new_comments and comment_line_count > 0 then
      -- Entry has existing comments: insert existing comments, then new comments, then declaration
      for j = 1, comment_line_count do
        table.insert(result, entry.lines[j])
      end
      for _, comment_line in ipairs(group.new_comments) do
        table.insert(result, translate_comment(comment_line, lang_prefix))
      end
      for j = comment_line_count + 1, #entry.lines do
        table.insert(result, entry.lines[j])
      end
    elseif has_new_comments then
      -- No existing comments: insert new comments, then the entry
      for _, comment_line in ipairs(group.new_comments) do
        table.insert(result, translate_comment(comment_line, lang_prefix))
      end
      for _, line in ipairs(entry.lines) do
        table.insert(result, line)
      end
    else
      -- No new comments: just add the entry as-is
      for _, line in ipairs(entry.lines) do
        table.insert(result, line)
      end
    end

    -- Add the trailing gap from the original entry
    local orig_idx = orig_index_map[i]
    local gap = trailing_gaps[orig_idx]
    if gap and #gap > 0 then
      for _, line in ipairs(gap) do
        table.insert(result, line)
      end
    else
      -- No original gap — add a blank line separator (unless it's the last entry)
      if i < #ordered_entries then
        table.insert(result, "")
      end
    end
  end

  for _, line in ipairs(postamble) do
    table.insert(result, line)
  end

  -- Apply changes using minimal diff
  diff.apply_minimal(source_bufnr, result)

  return true, nil, renames
end

return M
