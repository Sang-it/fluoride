local diff = require("fluoride.diff")

local M = {}

-- Child indentation (must match window.lua)
local CHILD_PREFIX = "  • "
local CHILD_PREFIX_LEN = #CHILD_PREFIX

--- Build a sorted list of type prefixes from a lang's highlights table.
--- @param lang FluorideLang the language module
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

--- Generate the next available suffixed name (e.g., greet_1, greet_2).
--- @param base_name string the original name
--- @param existing_names table<string, boolean> set of names already in use
--- @return string suffixed name
local function next_suffix_name(base_name, existing_names)
  local n = 1
  while existing_names[base_name .. "_" .. n] do
    n = n + 1
  end
  return base_name .. "_" .. n
end

--- Rename the first occurrence of old_name in a list of lines using word-boundary matching.
--- @param lines string[] source lines
--- @param old_name string name to find
--- @param new_name string replacement name
--- @return string[] new lines with the rename applied
local function rename_in_lines(lines, old_name, new_name)
  local copied = {}
  local renamed = false
  for _, line in ipairs(lines) do
    if not renamed then
      local pattern = "%f[%w_]" .. vim.pesc(old_name) .. "%f[^%w_]"
      local new_line, count = line:gsub(pattern, new_name, 1)
      if count > 0 then
        table.insert(copied, new_line)
        renamed = true
      else
        table.insert(copied, line)
      end
    else
      table.insert(copied, line)
    end
  end
  return copied
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

  -- Fallback: split at the first space to handle unrecognized display types
  -- e.g., "if (condition)" → prefix="if", name="(condition)"
  local fallback_prefix, fallback_rest = trimmed:match("^(%S+)%s+(.+)$")
  if fallback_prefix and fallback_rest then
    return fallback_prefix, strip_arity(fallback_rest)
  end

  return nil, strip_arity(trimmed)
end

--- Four-pass matching of parsed items to original entries.
--- @param parsed table[] list of { prefix, name }
--- @param originals table[] list of entries with .name and .display_type
--- @return table matched map of new_index → original_index
--- @return string|nil error
local function match_entries(parsed, originals)
  local matched = {}
  local used = {}

  -- Pass 1: exact name + prefix match (disambiguates struct Foo vs impl Foo)
  for i, p in ipairs(parsed) do
    for j, entry in ipairs(originals) do
      if not used[j] and p.name == entry.name and p.prefix and p.prefix == entry.display_type then
        matched[i] = j
        used[j] = true
        break
      end
    end
  end

  -- Pass 2: exact name match (for entries with unique names)
  for i, p in ipairs(parsed) do
    if not matched[i] then
      for j, entry in ipairs(originals) do
        if not used[j] and p.name == entry.name then
          matched[i] = j
          used[j] = true
          break
        end
      end
    end
  end

  -- Pass 3: match by type prefix (for renamed entries)
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

  -- Pass 4: fallback
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

  -- Note: unmatched items are OK — they may be duplicates
  return matched, nil
end

--- Check if a gap table contains any non-empty content.
--- @param gap table|nil gap lines table
--- @return boolean true if gap has at least one non-empty line
local function has_gap_content(gap)
  if not gap or #gap == 0 then
    return false
  end
  for _, line in ipairs(gap) do
    if line and #line > 0 then
      return true
    end
  end
  return false
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
--- @param ordered_children table[] children in new order (filtered, may exclude deleted)
--- @param child_matched table map of new_child_index → original_child_index
--- @param child_groups table[]|nil parsed child groups with new_comments
--- @param lang_prefix string|nil the language's native comment prefix
--- @param active_orig_children table[]|nil the filtered original children (after deletions). If nil, uses parent.children.
--- @return string[] new_lines
local function reconstruct_parent(parent, ordered_children, child_matched, child_groups, lang_prefix, active_orig_children)
  if not ordered_children or #ordered_children == 0 then
    return parent.lines
  end

  local all_orig_children = parent.children
  local orig_children = active_orig_children or all_orig_children

  -- Find the earliest and latest child rows in the FULL original ordering
  local min_child_row = parent.end_row
  local max_child_row = parent.start_row
  for _, child in ipairs(all_orig_children) do
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

  -- Build a set of deleted child row ranges (for gap filtering)
  local deleted_child_rows = {}
  if orig_children ~= all_orig_children then
    local surviving = {}
    for _, child in ipairs(orig_children) do
      surviving[child.start_row] = true
    end
    for _, child in ipairs(all_orig_children) do
      if not surviving[child.start_row] then
        for row = child.start_row, child.end_row do
          deleted_child_rows[row] = true
        end
      end
    end
  end

  -- Collect trailing gaps between consecutive FILTERED children
  local child_trailing_gaps = {}
  for i = 1, #orig_children do
    child_trailing_gaps[i] = {}
    if i < #orig_children then
      local gap_start = orig_children[i].end_row + 1
      local gap_end = orig_children[i + 1].start_row - 1
      if gap_end >= gap_start then
        for row = gap_start, gap_end do
          if not deleted_child_rows[row] then
            table.insert(child_trailing_gaps[i], parent.lines[row - parent.start_row + 1])
          end
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
    if has_gap_content(gap) then
      for _, line in ipairs(gap) do
        table.insert(result, line)
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
--- @param lang FluorideLang the language module
--- @return boolean ok
--- @return string|nil error
--- @return table[] renames list of { old_name: string, new_name: string }
--- @return table[]|nil deletions list of { name, display_type } if deletions detected but not allowed
function M.apply(source_bufnr, original_entries, new_display_lines, lang, allow_deletions)
  if #new_display_lines == 0 then
    return false, "no entries in the reorder list", {}, nil, nil, false
  end

  local type_prefixes = build_type_prefixes(lang)
  local changes_made = false

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
        return false, "could not parse line: " .. line, {}, nil, nil
      end

      if is_child then
        if not current_parent then
          return false, "child line without parent: " .. line, {}, nil, nil
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

  -- Re-attribute misplaced children to their correct parents.
  -- When a top-level entry is moved between a parent and its children,
  -- the positional grouping assigns children to the wrong parent.
  -- Uses display_type + name as a unique key to handle cases like
  -- struct Counter and impl Counter having the same name.
  local original_child_parent = {} -- child_name → parent_key (display_type + " " + name)
  for _, entry in ipairs(original_entries) do
    if entry.children then
      local parent_key = entry.display_type .. " " .. entry.name
      for _, child in ipairs(entry.children) do
        original_child_parent[child.name] = parent_key
      end
    end
  end

  -- Build a parent_key → group index map for quick lookup
  local group_by_key = {}
  for idx, group in ipairs(parsed_groups) do
    local key = (group.prefix or "") .. " " .. group.name
    group_by_key[key] = idx
  end

  -- Scan each group's children and re-attribute misplaced ones
  for i = #parsed_groups, 1, -1 do
    local group = parsed_groups[i]
    local group_key = (group.prefix or "") .. " " .. group.name
    local correct_children = {}
    local misplaced = {}

    for _, child in ipairs(group.children) do
      local orig_parent_key = original_child_parent[child.name]
      if orig_parent_key == nil or orig_parent_key == group_key then
        -- Correct parent or new child (duplicate) — keep it
        table.insert(correct_children, child)
      else
        -- Misplaced — collect for re-attribution
        table.insert(misplaced, child)
      end
    end

    group.children = correct_children

    -- Re-attach misplaced children to their correct parent group
    for _, child in ipairs(misplaced) do
      local orig_parent_key = original_child_parent[child.name]
      local target_idx = group_by_key[orig_parent_key]
      if target_idx then
        table.insert(parsed_groups[target_idx].children, child)
      end
    end
  end

  -- Match top-level parents (only match against original entries)
  local parent_parsed = {}
  for _, g in ipairs(parsed_groups) do
    table.insert(parent_parsed, { prefix = g.prefix, name = g.name })
  end

  -- Keep the full original list for preamble/postamble/gap calculations
  local all_original_entries = original_entries

  local parent_matched, err = match_entries(parent_parsed, original_entries)

  -- Detect deletions: original entries that no parsed group matched
  if #parsed_groups < #original_entries then
    local matched_originals = {}
    for _, orig_idx in pairs(parent_matched) do
      matched_originals[orig_idx] = true
    end

    local deletions = {}
    for j, entry in ipairs(original_entries) do
      if not matched_originals[j] then
        table.insert(deletions, { name = entry.name, display_type = entry.display_type })
      end
    end

    if #deletions > 0 and not allow_deletions then
      -- Return deletions for the caller to confirm
      return false, nil, {}, deletions, nil
    end

    -- If deletions are allowed, filter original_entries to exclude deleted ones
    if allow_deletions and #deletions > 0 then
      local filtered_originals = {}
      for j, entry in ipairs(original_entries) do
        if matched_originals[j] then
          table.insert(filtered_originals, entry)
        end
      end
      original_entries = filtered_originals

      -- Re-run matching with the filtered originals
      parent_matched, err = match_entries(parent_parsed, original_entries)
    end
  end

  -- Detect top-level renames, reorders, and build a set of existing names
  local renames = {}
  local affected_names = {}
  local existing_names = {}
  for _, entry in ipairs(original_entries) do
    existing_names[entry.name] = true
  end

  for i, p in ipairs(parent_parsed) do
    if parent_matched[i] then
      local entry = original_entries[parent_matched[i]]
      -- Detect rename
      if p.name ~= entry.name then
        table.insert(renames, { old_name = entry.name, new_name = p.name })
        existing_names[p.name] = true
        affected_names[p.name] = true
      end
      -- Detect top-level reorder
      if parent_matched[i] ~= i then
        changes_made = true
      end
    end
  end

  -- Build ordered entries, handling child reordering and duplicates
  local ordered_entries = {}

  for i, group in ipairs(parsed_groups) do
    local entry_copy

    if parent_matched[i] then
      -- Matched to an original entry
      local orig_entry = original_entries[parent_matched[i]]
      entry_copy = {
        name = orig_entry.name,
        display_type = orig_entry.display_type,
        arity = orig_entry.arity,
        start_row = orig_entry.start_row,
        decl_start_row = orig_entry.decl_start_row,
        end_row = orig_entry.end_row,
        lines = orig_entry.lines,
        children = orig_entry.children,
      }
    else
      -- Unmatched — this is a duplicate. Find the template entry.
      -- Look at the entry directly above in parsed_groups that has the same prefix.
      local template = nil
      for j = i - 1, 1, -1 do
        if parent_matched[j] and parsed_groups[j].prefix == group.prefix then
          template = original_entries[parent_matched[j]]
          break
        end
      end
      -- If not found above, look below
      if not template then
        for j = i + 1, #parsed_groups do
          if parent_matched[j] and parsed_groups[j].prefix == group.prefix then
            template = original_entries[parent_matched[j]]
            break
          end
        end
      end
      -- If still no template, try any matched entry with same prefix
      if not template then
        for j, entry in ipairs(original_entries) do
          if entry.display_type == group.prefix then
            template = entry
            break
          end
        end
      end

      if not template then
        return false, "could not find a template for duplicate entry: " .. (group.prefix or "") .. " " .. (group.name or ""), {}, nil, nil
      end

      -- Generate a suffixed name
      local new_name = next_suffix_name(template.name, existing_names)
      existing_names[new_name] = true

      -- Copy the template's lines with the name replaced
      local new_lines = rename_in_lines(template.lines, template.name, new_name)

      entry_copy = {
        name = new_name,
        display_type = template.display_type,
        arity = template.arity,
        start_row = template.start_row,
        decl_start_row = template.decl_start_row,
        end_row = template.end_row,
        lines = new_lines,
        children = template.children and vim.deepcopy(template.children) or nil,
        is_duplicate = true,
      }
      changes_made = true
    end

    -- If this parent has children, check if they were reordered (skip for duplicates)
    local orig_entry = parent_matched[i] and original_entries[parent_matched[i]] or nil
    if not entry_copy.is_duplicate and orig_entry and orig_entry.children and #orig_entry.children > 0 then
      local orig_children = orig_entry.children

      -- Match children
      local child_matched, child_err = match_entries(group.children, orig_children)

      -- Detect child deletions
      if #group.children < #orig_children then
        local matched_child_originals = {}
        for _, orig_idx in pairs(child_matched) do
          matched_child_originals[orig_idx] = true
        end

        local child_deletions = {}
        for cj, child in ipairs(orig_children) do
          if not matched_child_originals[cj] then
            table.insert(child_deletions, {
              name = child.name,
              display_type = child.display_type,
              parent_name = orig_entry.name,
            })
          end
        end

        if #child_deletions > 0 and not allow_deletions then
          -- Return child deletions for the caller to confirm
          return false, nil, {}, child_deletions, nil
        end

        -- If deletions allowed, filter out deleted children and re-match
        if allow_deletions and #child_deletions > 0 then
          local filtered_children = {}
          for cj, child in ipairs(orig_children) do
            if matched_child_originals[cj] then
              table.insert(filtered_children, child)
            end
          end
          orig_children = filtered_children
          child_matched, child_err = match_entries(group.children, orig_children)
        end
      end

      -- Build ordered children, detect renames, and handle duplicates
      local ordered_children = {}
      local child_existing_names = {}
      for _, c in ipairs(orig_children) do
        child_existing_names[c.name] = true
      end

      local has_child_duplicates = false
      for j = 1, #group.children do
        if child_matched[j] then
          -- Matched to an original child
          local orig_child = orig_children[child_matched[j]]
          table.insert(ordered_children, orig_child)

          if group.children[j].name ~= orig_child.name then
            table.insert(renames, { old_name = orig_child.name, new_name = group.children[j].name })
            child_existing_names[group.children[j].name] = true
            affected_names[group.children[j].name] = true
          end
        else
          -- Unmatched — this is a duplicate child
          has_child_duplicates = true
          changes_made = true

          -- Find template: look at the child directly above with the same prefix
          local template_child = nil
          for k = j - 1, 1, -1 do
            if child_matched[k] and group.children[k].prefix == group.children[j].prefix then
              template_child = orig_children[child_matched[k]]
              break
            end
          end
          if not template_child then
            for k = j + 1, #group.children do
              if child_matched[k] and group.children[k].prefix == group.children[j].prefix then
                template_child = orig_children[child_matched[k]]
                break
              end
            end
          end
          if not template_child then
            for _, c in ipairs(orig_children) do
              if c.display_type == group.children[j].prefix then
                template_child = c
                break
              end
            end
          end

          if template_child then
            local new_child_name = next_suffix_name(template_child.name, child_existing_names)
            child_existing_names[new_child_name] = true

            local new_child_lines = rename_in_lines(template_child.lines, template_child.name, new_child_name)
            table.insert(ordered_children, {
              name = new_child_name,
              display_type = template_child.display_type,
              arity = template_child.arity,
              start_row = template_child.start_row,
              decl_start_row = template_child.decl_start_row,
              end_row = template_child.end_row,
              lines = new_child_lines,
            })
          end
        end
      end

      -- Check if any child has new comments
      local has_child_new_comments = false
      for _, child_group in ipairs(group.children) do
        if child_group.new_comments and #child_group.new_comments > 0 then
          has_child_new_comments = true
          changes_made = true
          break
        end
      end

      -- Reconstruct if children were reordered, duplicated, deleted, or have new comments
      local has_child_deletions = #orig_children ~= #(orig_entry.children or {})
      if has_child_deletions then
        changes_made = true
      end
      if children_order_changed(child_matched, #orig_children) then
        changes_made = true
      end
      if has_child_duplicates or has_child_deletions or children_order_changed(child_matched, #orig_children) or has_child_new_comments then
        local lp = lang.comment_prefix or "//"
        entry_copy.lines = reconstruct_parent(orig_entry, ordered_children, child_matched, group.children, lp, orig_children)
      end
    end

    table.insert(ordered_entries, entry_copy)
  end

  -- Collect preamble (everything before the first entry in the FULL original list)
  local total_lines = vim.api.nvim_buf_line_count(source_bufnr)
  local first_entry_row = all_original_entries[1].start_row
  local preamble = {}
  if first_entry_row > 0 then
    preamble = vim.api.nvim_buf_get_lines(source_bufnr, 0, first_entry_row, false)
  end

  -- Build a set of deleted row ranges to exclude from gaps
  local deleted_rows = {}
  if all_original_entries ~= original_entries then
    local surviving = {}
    for _, entry in ipairs(original_entries) do
      surviving[entry.start_row] = true
    end
    for _, entry in ipairs(all_original_entries) do
      if not surviving[entry.start_row] then
        for row = entry.start_row, entry.end_row do
          deleted_rows[row] = true
        end
      end
    end
  end

  -- Collect gaps between consecutive FILTERED entries (in original order).
  -- Exclude lines that belong to deleted entries.
  local trailing_gaps = {}
  for i = 1, #original_entries do
    trailing_gaps[i] = {}
    if i < #original_entries then
      local gap_start = original_entries[i].end_row + 1
      local gap_end = original_entries[i + 1].start_row - 1
      if gap_end >= gap_start then
        local gap_lines = vim.api.nvim_buf_get_lines(source_bufnr, gap_start, gap_end + 1, false)
        -- Filter out lines belonging to deleted entries
        local filtered_gap = {}
        for row_offset, line in ipairs(gap_lines) do
          local actual_row = gap_start + row_offset - 1
          if not deleted_rows[actual_row] then
            table.insert(filtered_gap, line)
          end
        end
        trailing_gaps[i] = filtered_gap
      end
    end
  end

  -- Collect postamble (everything after the last entry in the FULL original list)
  local last_entry_row = all_original_entries[#all_original_entries].end_row
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
    if has_new_comments then
      changes_made = true
    end
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

  -- Convert affected_names set to list
  local affected_list = {}
  for name in pairs(affected_names) do
    table.insert(affected_list, name)
  end

  return true, nil, renames, nil, affected_list, changes_made
end

return M
