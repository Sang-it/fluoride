local diff = require("fluoride.diff")

local M = {}

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

--- Append an entry's lines to a result list, inserting new comments between
--- existing comments and the declaration.
--- @param result string[] accumulator for output lines
--- @param entry_lines string[] the entry's source lines
--- @param comment_line_count number number of existing comment lines before declaration
--- @param new_comments string[]|nil new comment lines to insert (starting with //)
--- @param lang_prefix string the language's native comment prefix
local function insert_lines_with_comments(result, entry_lines, comment_line_count, new_comments, lang_prefix)
  local has_comments = new_comments and #new_comments > 0

  if has_comments and comment_line_count > 0 then
    -- Existing comments first, then new comments, then declaration
    for j = 1, comment_line_count do
      table.insert(result, entry_lines[j])
    end
    local indent = entry_lines[comment_line_count + 1]:match("^(%s*)")
    for _, comment_line in ipairs(new_comments) do
      table.insert(result, indent .. translate_comment(comment_line, lang_prefix))
    end
    for j = comment_line_count + 1, #entry_lines do
      table.insert(result, entry_lines[j])
    end
  elseif has_comments then
    -- No existing comments — insert new comments with proper indentation, then entry
    local indent = entry_lines[1]:match("^(%s*)")
    for _, comment_line in ipairs(new_comments) do
      table.insert(result, indent .. translate_comment(comment_line, lang_prefix))
    end
    for _, line in ipairs(entry_lines) do
      table.insert(result, line)
    end
  else
    -- No new comments — just add entry as-is
    for _, line in ipairs(entry_lines) do
      table.insert(result, line)
    end
  end
end

--- Extract the last segment of a dotted/colon name for symbol search.
--- e.g., "Animal.Speak" → "Speak", "M:initialize" → "initialize", "foo" → "foo"
--- @param name string
--- @return string last_segment
local function get_search_name(name)
  local sep_pos = name:find("[%.:]([^%.:]*)$")
  if sep_pos then
    return name:sub(sep_pos + 1)
  end
  return name
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

--- Parse a display line's nesting depth and extract content.
--- Depth 0 = top-level, depth 1 = child, depth 2 = grandchild, etc.
--- @param line string
--- @return number depth nesting depth
--- @return string content the line content without indent prefix
local function parse_line_depth(line)
  -- Check for nested child indent prefixes at any depth
  -- Each depth level: 2 spaces + "• " at the innermost level
  local bullet_pos = line:find("• ", 1, true)
  if bullet_pos then
    local leading = line:sub(1, bullet_pos - 1)
    if leading:match("^%s*$") and #leading > 0 and #leading % 2 == 0 then
      local depth = #leading / 2
      local content = line:sub(bullet_pos + #("• "))
      return depth, content
    end
  end
  return 0, line
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
--- @return table child_offsets map of child_index → {start_offset, decl_offset} (0-indexed offsets within new_lines)
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

  -- Check if children have access specifiers (C/C++ public/protected/private)
  local has_access_specifiers = false
  for _, child in ipairs(orig_children) do
    if child.access then
      has_access_specifiers = true
      break
    end
  end

  -- Header: from parent start to first child start (in original layout)
  -- Strip access specifier lines from header if present (they'll be re-inserted during reassembly)
  local header = {}
  for row = parent.start_row, min_child_row - 1 do
    local line = parent.lines[row - parent.start_row + 1]
    local stripped = line and vim.trim(line) or ""
    if has_access_specifiers and (stripped == "public:" or stripped == "protected:" or stripped == "private:"
      or stripped == "public" or stripped == "protected" or stripped == "private") then
      -- Skip — will be re-inserted by the reassembly loop
    else
      table.insert(header, line)
    end
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

  -- Collect trailing gaps between consecutive FILTERED children.
  -- If children have access specifiers, filter out access specifier lines from gaps
  -- so they don't travel with reordered children.
  local child_trailing_gaps = {}
  for i = 1, #orig_children do
    child_trailing_gaps[i] = {}
    if i < #orig_children then
      local gap_start = orig_children[i].end_row + 1
      local gap_end = orig_children[i + 1].start_row - 1
      if gap_end >= gap_start then
        for row = gap_start, gap_end do
          if not deleted_child_rows[row] then
            local line = parent.lines[row - parent.start_row + 1]
            -- Skip access specifier lines (e.g., "    public:", "    protected:", "    private:")
            local stripped = line and vim.trim(line) or ""
            if has_access_specifiers and (stripped == "public:" or stripped == "protected:" or stripped == "private:"
              or stripped == "public" or stripped == "protected" or stripped == "private") then
              -- Don't include access specifier lines in gaps
            else
              table.insert(child_trailing_gaps[i], line)
            end
          end
        end
      end
    end
  end

  -- Determine access specifier indentation from the original source (for re-insertion)
  local access_indent = ""
  if has_access_specifiers then
    -- Find the first access specifier line in the parent's lines to get indentation
    for _, line in ipairs(parent.lines) do
      local indent = line:match("^(%s*)public%s*:?%s*$")
        or line:match("^(%s*)protected%s*:?%s*$")
        or line:match("^(%s*)private%s*:?%s*$")
      if indent then
        access_indent = indent
        break
      end
    end
  end

  -- Reassemble: header + children (new order) with preserved gaps + footer
  local result = {}
  local child_offsets = {} -- child_index → { start_offset, decl_offset } (0-indexed)
  for _, line in ipairs(header) do
    table.insert(result, line)
  end

  local last_access = nil
  for i, child in ipairs(ordered_children) do
    -- Insert access specifier line when the access section changes
    if has_access_specifiers and child.access and child.access ~= last_access then
      table.insert(result, access_indent .. child.access .. ":")
    end
    last_access = child.access
    -- Track where this child's lines start in the result (0-indexed offset)
    local child_start = #result

    -- Insert child lines with any new comments
    local child_group = child_groups and child_groups[i]
    local child_new_comments = child_group and child_group.new_comments or nil
    local child_comment_count = child.decl_start_row - child.start_row
    insert_lines_with_comments(result, child.lines, child_comment_count, child_new_comments, lang_prefix or "//")

    -- Record this child's declaration position within the reconstructed lines
    local new_comment_count = (child_new_comments and #child_new_comments > 0) and #child_new_comments or 0
    child_offsets[i] = {
      start_offset = child_start,
      decl_offset = child_start + child_comment_count + new_comment_count,
    }

    -- Add the trailing gap from the original child (skip for last child)
    if i < #ordered_children then
      local orig_idx = child_matched[i]
      local gap = child_trailing_gaps[orig_idx]
      local is_compact = parent.display_type and (
        parent.display_type:match("enum") ~= nil
        or parent.display_type:match("struct") ~= nil
        or parent.display_type:match("union") ~= nil
        or parent.display_type:match("interface") ~= nil
        or parent.display_type == "type"
      ) or false
      if is_compact then
        -- Compact types (enums, structs, unions): only emit gaps with real content (comments)
        if has_gap_content(gap) then
          for _, line in ipairs(gap) do
            table.insert(result, line)
          end
        end
      else
        -- Non-compact: preserve blank line spacing
        if gap and #gap > 0 then
          for _, line in ipairs(gap) do
            table.insert(result, line)
          end
        else
          table.insert(result, "")
        end
      end
    end
  end

  for _, line in ipairs(footer) do
    table.insert(result, line)
  end

  return result, child_offsets
end

--- Display types that should not be renamed (expressions, call signatures, etc.)
local CHILD_NON_RENAMEABLE = {
  ["expression"] = true, ["call"] = true, ["index"] = true,
  ["static block"] = true, ["static_assert"] = true,
}

--- Top-level display types that should not be renamed (control flow, expressions).
--- Their display names are descriptive text, not symbol identifiers.
local NON_RENAMEABLE = {
  ["if"] = true, ["while"] = true, ["for"] = true, ["switch"] = true,
  ["try"] = true, ["do"] = true, ["with"] = true, ["select"] = true,
  ["assert"] = true, ["expression"] = true, ["call"] = true,
  ["go"] = true, ["defer"] = true, ["repeat"] = true,
}

--- Recursive function to process children at any depth.
--- Modifies entry_copy.lines via reconstruct_parent when children changed.
--- @param entry_copy table working copy of the entry
--- @param orig_entry table the original entry
--- @param group table parsed group from display lines
--- @param state table mutable state: { renames, allow_deletions, lang, changes_made }
--- @return table|nil error table { ok, err, renames, deletions, affected } on failure, nil on success
local function process_children_recursive(entry_copy, orig_entry, group, state)
  if not orig_entry.children or #orig_entry.children == 0 then
    return nil
  end
  if not group.children or #group.children == 0 then
    -- No children in parsed group. This could mean:
    -- 1. Children were hidden by max_depth (display never showed them) -> skip, leave unchanged
    -- 2. User actually deleted all children -> treat as deletion
    -- We can't distinguish these here, so we skip processing entirely.
    -- Users must have children visible (via Tab/max_depth) to delete them.
    return nil
  end

  local orig_children = orig_entry.children

  -- Match children
  local child_matched = match_entries(group.children, orig_children)

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

    if #child_deletions > 0 and not state.allow_deletions then
      return { ok = false, err = nil, renames = {}, deletions = child_deletions, affected = nil }
    end

    -- If deletions allowed, filter out deleted children and re-match
    if state.allow_deletions and #child_deletions > 0 then
      local filtered_children = {}
      for cj, child in ipairs(orig_children) do
        if matched_child_originals[cj] then
          table.insert(filtered_children, child)
        end
      end
      orig_children = filtered_children
      child_matched = match_entries(group.children, orig_children)
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
      -- Copy so we can modify lines without affecting the original
      local child_copy = {
        name = orig_child.name,
        display_type = orig_child.display_type,
        arity = orig_child.arity,
        start_row = orig_child.start_row,
        decl_start_row = orig_child.decl_start_row,
        end_row = orig_child.end_row,
        lines = orig_child.lines, -- will be replaced by reconstruct_parent if sub-children changed
        children = orig_child.children,
        access = orig_child.access,
      }

      -- Update access if the user moved the child to a different access section
      if group.children[j].access then
        if child_copy.access ~= group.children[j].access then
          child_copy.access = group.children[j].access
          state.changes_made = true
        end
      end

      -- Recurse FIRST: process this child's own children (bottom-up)
      -- This may replace child_copy.lines with reconstructed content.
      if orig_child.children and #orig_child.children > 0 then
        local sub_result = process_children_recursive(child_copy, orig_child, group.children[j], state)
        if sub_result then
          return sub_result
        end
      end

      -- Detect rename AFTER recursion so child_copy has final lines
      if group.children[j].name ~= orig_child.name and not CHILD_NON_RENAMEABLE[orig_child.display_type] then
        local rename_entry = { old_name = orig_child.name, new_name = group.children[j].name, child_index = j }
        table.insert(state.renames, rename_entry)
        child_existing_names[group.children[j].name] = true
        -- Position (rename_line/rename_col) will be set after reconstruct_parent
      end

      table.insert(ordered_children, child_copy)
    else
      -- Unmatched — this is a duplicate child
      has_child_duplicates = true
      state.changes_made = true

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
          access = template_child.access,
        })
      end
    end
  end

  -- Check if any child has new comments, and track annotated children for highlighting
  local has_child_new_comments = false
  for ci, child_group in ipairs(group.children) do
    if child_group.new_comments and #child_group.new_comments > 0 then
      has_child_new_comments = true
      state.changes_made = true
      if child_matched[ci] then
        local child = ordered_children[ci]
        if child then
          table.insert(state.annotated, { name = child.name, child_index = ci, owner_entry = entry_copy })
        end
      end
    end
  end

  -- Reconstruct if children were reordered, duplicated, deleted, or have new comments
  local has_child_deletions = #orig_children ~= #(orig_entry.children or {})
  if has_child_deletions then
    state.changes_made = true
  end
  if children_order_changed(child_matched, #orig_children) then
    state.changes_made = true
  end

  -- Check if any sub-child was reconstructed (lines differ from original)
  local sub_children_changed = false
  for j, oc in ipairs(ordered_children) do
    if child_matched[j] then
      local orig_child = orig_children[child_matched[j]]
      if oc.lines ~= orig_child.lines then
        sub_children_changed = true
        break
      end
    end
  end

  -- Check if any child's access specifier changed
  local access_changed = false
  for j, oc in ipairs(ordered_children) do
    if child_matched[j] then
      local orig_child = orig_children[child_matched[j]]
      if oc.access ~= orig_child.access then
        access_changed = true
        state.changes_made = true
        break
      end
    end
  end

  local did_reconstruct = has_child_duplicates or has_child_deletions or children_order_changed(child_matched, #orig_children) or has_child_new_comments or sub_children_changed or access_changed
  local child_offsets = nil
  if did_reconstruct then
    local lp = state.lang.comment_prefix or "//"
    entry_copy.lines, child_offsets = reconstruct_parent(orig_entry, ordered_children, child_matched, group.children, lp, orig_children)
  end

  -- Annotate renames with positions from child_offsets.
  -- For renames created at this level, compute their declaration row as
  -- an offset within entry_copy.lines. Tag with the entry_copy reference
  -- so the caller can resolve to absolute position.
  for _, r in ipairs(state.renames) do
    if r.child_index and not r.rename_line then
      local decl_line_text
      local decl_row_in_parent

      if child_offsets and child_offsets[r.child_index] then
        decl_row_in_parent = child_offsets[r.child_index].decl_offset
        decl_line_text = entry_copy.lines[decl_row_in_parent + 1]
      else
        local child = ordered_children[r.child_index]
        if child then
          decl_row_in_parent = child.decl_start_row - entry_copy.start_row
          decl_line_text = entry_copy.lines[decl_row_in_parent + 1]
        end
      end

      if decl_line_text and decl_row_in_parent then
        -- For dotted/colon names (e.g., Animal.Speak, M.greet), search for the last segment
        local search_name = get_search_name(r.old_name)
        local pattern = "%f[%w_]" .. vim.pesc(search_name) .. "%f[^%w_]"
        local col = decl_line_text:find(pattern)
        if col then
          r.rename_line = decl_row_in_parent
          r.rename_col = col - 1
          r.owner_entry = entry_copy
        end
      end
      r.child_index = nil
    end
  end

  -- Adjust sub-child renames: any rename whose owner_entry is one of the
  -- ordered_children needs its offset adjusted to be relative to entry_copy.lines.
  for _, r in ipairs(state.renames) do
    if r.owner_entry and r.rename_line then
      for ci, oc in ipairs(ordered_children) do
        if r.owner_entry == oc then
          local child_start_in_parent
          if child_offsets and child_offsets[ci] then
            child_start_in_parent = child_offsets[ci].start_offset
          else
            child_start_in_parent = oc.start_row - entry_copy.start_row
          end
          r.rename_line = child_start_in_parent + r.rename_line
          r.owner_entry = entry_copy
          break
        end
      end
    end
  end

  -- Resolve annotated child positions relative to entry_copy.lines
  for _, a in ipairs(state.annotated) do
    if a.child_index and a.owner_entry == entry_copy then
      -- Compute decl_row as offset within entry_copy.lines
      local ci = a.child_index
      if child_offsets and child_offsets[ci] then
        a.decl_row = child_offsets[ci].decl_offset
      else
        local child = ordered_children[ci]
        if child then
          a.decl_row = child.decl_start_row - entry_copy.start_row
        end
      end
      a.child_index = nil
    end
    -- Adjust sub-child annotations: if owner_entry is one of the ordered_children,
    -- shift offset to be relative to entry_copy
    if a.owner_entry and a.decl_row then
      for ci, oc in ipairs(ordered_children) do
        if a.owner_entry == oc then
          local child_start_in_parent
          if child_offsets and child_offsets[ci] then
            child_start_in_parent = child_offsets[ci].start_offset
          else
            child_start_in_parent = oc.start_row - entry_copy.start_row
          end
          a.decl_row = child_start_in_parent + a.decl_row
          a.owner_entry = entry_copy
          break
        end
      end
    end
  end

  return nil
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

  -- Parse display lines into a recursive tree structure:
  -- Lines at depth 0 are top-level groups. Lines at depth N are children of
  -- the most recent entry at depth N-1. Uses a stack to track parents at each depth.
  -- Lines starting with "//" are new comments to be written to the source file.
  local parsed_groups = {} -- list of { prefix, name, children, new_comments }

  -- Stack of entries at each depth: stack[depth] = most recent entry at that depth
  local stack = {} -- stack[0] = nil (top-level entries go to parsed_groups)
  local pending_comments = {} -- comment lines waiting to be attached to the next entry
  local access_at_depth = {} -- track current access specifier per depth level

  for _, line in ipairs(new_display_lines) do
    local trimmed = vim.trim(line)

    -- Track access specifier separator lines (-- public, -- protected, -- private)
    local access_spec = trimmed:match("^%-%- (%w+)$")
    if access_spec then
      -- Determine the depth of this separator from indentation
      local depth = 0
      local leading = line:match("^(%s*)")
      if leading and #leading > 0 and #leading % 2 == 0 then
        depth = #leading / 2
      end
      access_at_depth[depth] = access_spec

    -- Check if this is a new comment line (starts with //)
    elseif trimmed:sub(1, 2) == "//" then
      table.insert(pending_comments, trimmed)
    else
      local depth, content = parse_line_depth(line)
      local prefix, name = parse_display_content(content, type_prefixes)

      if not name then
        return false, "could not parse line: " .. line, {}, nil, nil
      end

      local node = { prefix = prefix, name = name, children = {}, new_comments = pending_comments, access = access_at_depth[depth] }
      pending_comments = {}

      -- Clear access specifiers at deeper depths (new parent resets child access)
      for d = depth + 1, #access_at_depth do
        access_at_depth[d] = nil
      end

      if depth == 0 then
        -- Also clear access at depth 0 for new top-level entries
        access_at_depth[0] = nil
        table.insert(parsed_groups, node)
        stack = { [0] = node }
      else
        local parent = stack[depth - 1]
        if not parent then
          return false, "child line without parent at depth " .. depth .. ": " .. line, {}, nil, nil
        end
        table.insert(parent.children, node)
        stack[depth] = node
        -- Clear deeper stack entries (they're no longer current)
        for d = depth + 1, #stack do
          stack[d] = nil
        end
      end
    end
  end

  -- Validate that no child was moved outside its parent.
  -- Build a map of child_name → set of allowed parent keys (display_type + " " + name).
  -- A child at depth 0 has no parent (parent_key = nil).
  -- Then walk the parsed tree and check that each entry appears under an allowed parent.
  local allowed_parents = {} -- child_name → { parent_key = true, ... }
  local function build_allowed_parents(entry_list, parent_key)
    for _, entry in ipairs(entry_list) do
      local key = entry.display_type .. " " .. entry.name
      if not allowed_parents[entry.name] then
        allowed_parents[entry.name] = {}
      end
      allowed_parents[entry.name][parent_key or ""] = true
      if entry.children then
        build_allowed_parents(entry.children, key)
      end
    end
  end
  build_allowed_parents(original_entries, nil)

  -- Build original child count per parent for validation
  local orig_child_counts = {} -- parent_key → count
  local function build_child_counts(entry_list)
    for _, entry in ipairs(entry_list) do
      if entry.children then
        local key = entry.display_type .. " " .. entry.name
        orig_child_counts[key] = #entry.children
        build_child_counts(entry.children)
      end
    end
  end
  build_child_counts(original_entries)

  local function validate_parents(group_list, parent_key)
    for _, group in ipairs(group_list) do
      local allowed = allowed_parents[group.name]
      if allowed and not allowed[parent_key or ""] then
        -- This name exists in the original tree under a different parent.
        -- Only flag if the current parent has MORE children than it originally had
        -- (indicating a child was actually moved in, not just renamed to a colliding name).
        local expected_count = orig_child_counts[parent_key or ""] or #group_list
        if #group_list > expected_count then
          return false, "cannot move '" .. (group.prefix or "") .. " " .. group.name
            .. "' outside its parent"
        end
      end
      if group.children and #group.children > 0 then
        local key = (group.prefix or "") .. " " .. group.name
        local ok, err = validate_parents(group.children, key)
        if not ok then return ok, err end
      end
    end
    return true, nil
  end
  local parent_ok, parent_err = validate_parents(parsed_groups, nil)
  if not parent_ok then
    return false, parent_err, {}, nil, nil, false
  end

  -- Re-attribute misplaced children to their correct parents (recursive).
  -- When a top-level entry is moved between a parent and its children,
  -- the positional grouping assigns children to the wrong parent.
  -- Uses display_type + name as a unique key to handle cases like
  -- struct Counter and impl Counter having the same name.

  -- Build child→parent mapping recursively from original entries.
  -- If a child name appears in multiple parents, mark it as ambiguous (nil)
  -- so re-attribution skips it.
  local original_child_parent = {} -- child_name → parent_key or nil (ambiguous)
  local ambiguous_children = {} -- child_name → true if name appears in multiple parents
  local function build_child_parent_map(entry_list)
    for _, entry in ipairs(entry_list) do
      if entry.children then
        local parent_key = entry.display_type .. " " .. entry.name
        for _, child in ipairs(entry.children) do
          if ambiguous_children[child.name] then
            -- Already ambiguous, skip
          elseif original_child_parent[child.name] and original_child_parent[child.name] ~= parent_key then
            -- Name exists under a different parent — mark as ambiguous
            ambiguous_children[child.name] = true
            original_child_parent[child.name] = nil
          else
            original_child_parent[child.name] = parent_key
          end
        end
        build_child_parent_map(entry.children)
      end
    end
  end
  build_child_parent_map(original_entries)

  -- Build a parent_key → group map for quick lookup (recursive)
  local all_groups_by_key = {} -- key → group reference
  local function index_groups(group_list)
    for _, group in ipairs(group_list) do
      local key = (group.prefix or "") .. " " .. group.name
      all_groups_by_key[key] = group
      if group.children then
        index_groups(group.children)
      end
    end
  end
  index_groups(parsed_groups)

  -- Re-attribute misplaced children (recursive).
  -- Only re-attribute when the current parent has MORE children than expected
  -- AND the target parent has FEWER (indicating positional mis-grouping).
  -- This avoids false positives from renames that happen to match a name
  -- in a different parent.
  local function reattribute_children(group_list)
    for i = #group_list, 1, -1 do
      local group = group_list[i]
      local group_key = (group.prefix or "") .. " " .. group.name
      local expected_count = orig_child_counts[group_key] or 0

      -- Only attempt re-attribution if this parent has more children than expected
      if #group.children > expected_count then
        local correct_children = {}
        local misplaced = {}

        for _, child in ipairs(group.children) do
          local orig_parent_key = original_child_parent[child.name]
          if orig_parent_key == nil or orig_parent_key == group_key then
            table.insert(correct_children, child)
          else
            -- Only re-attribute if the target parent has fewer children than expected
            local target_group = all_groups_by_key[orig_parent_key]
            local target_count = target_group and #target_group.children or 0
            local target_expected = orig_child_counts[orig_parent_key] or 0
            if target_count < target_expected then
              table.insert(misplaced, child)
            else
              table.insert(correct_children, child)
            end
          end
        end

        group.children = correct_children

        for _, child in ipairs(misplaced) do
          local orig_parent_key = original_child_parent[child.name]
          local target_group = all_groups_by_key[orig_parent_key]
          if target_group then
            table.insert(target_group.children, child)
          end
        end
      end

      -- Recurse into children
      if #group.children > 0 then
        reattribute_children(group.children)
      end
    end
  end
  reattribute_children(parsed_groups)

  -- Match top-level parents (only match against original entries)
  local parent_parsed = {}
  for _, g in ipairs(parsed_groups) do
    table.insert(parent_parsed, { prefix = g.prefix, name = g.name })
  end

  -- Keep the full original list for preamble/postamble/gap calculations
  local all_original_entries = original_entries

  local parent_matched = match_entries(parent_parsed, original_entries)

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
      changes_made = true

      -- Re-run matching with the filtered originals
      parent_matched = match_entries(parent_parsed, original_entries)
    end
  end

  -- Detect top-level renames, reorders, and build a set of existing names
  local renames = {}
  local affected_rows = {} -- populated after rename positions are computed
  local existing_names = {}
  for _, entry in ipairs(original_entries) do
    existing_names[entry.name] = true
  end

  for i, p in ipairs(parent_parsed) do
    if parent_matched[i] then
      -- Detect top-level reorder (renames are detected later, after children are processed)
      if parent_matched[i] ~= i then
        changes_made = true
      end
    end
  end

  local annotated = {} -- children with new // comments, tracked for highlight after save
  local state = { renames = renames, annotated = annotated, allow_deletions = allow_deletions, lang = lang, changes_made = changes_made }

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
      state.changes_made = true
    end

    -- Recursively process children at all depths (skip for duplicates)
    local orig_entry = parent_matched[i] and original_entries[parent_matched[i]] or nil
    if not entry_copy.is_duplicate and orig_entry then
      local child_result = process_children_recursive(entry_copy, orig_entry, group, state)
      if child_result then
        return child_result.ok, child_result.err, child_result.renames or {}, child_result.deletions, child_result.affected
      end
    end

    -- Detect top-level rename AFTER children are processed so entry_copy has final lines
    if parent_matched[i] then
      local p = parent_parsed[i]
      if p.name ~= entry_copy.name and not NON_RENAMEABLE[entry_copy.display_type] then
        table.insert(renames, { old_name = entry_copy.name, new_name = p.name, top_level_index = i })
        existing_names[p.name] = true
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
  local entry_start_rows = {} -- entry_start_rows[i] = 0-indexed start row in result for ordered_entries[i]
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

    -- Track this entry's start position in result (0-indexed)
    entry_start_rows[i] = #result

    -- Add the entry's lines, inserting new comments between existing comments and the declaration
    local group = parsed_groups[i]
    local has_new_comments = group.new_comments and #group.new_comments > 0
    if has_new_comments then
      state.changes_made = true
    end
    local comment_line_count = entry.decl_start_row - entry.start_row
    insert_lines_with_comments(result, entry.lines, comment_line_count, group.new_comments, lang_prefix)

    -- Add the trailing gap from the original entry (skip for last entry to avoid trailing whitespace)
    if i < #ordered_entries then
      local orig_idx = orig_index_map[i]
      local gap = trailing_gaps[orig_idx]
      if gap and #gap > 0 then
        for _, line in ipairs(gap) do
          table.insert(result, line)
        end
      else
        table.insert(result, "")
      end
    end
  end

  for _, line in ipairs(postamble) do
    table.insert(result, line)
  end

  -- Resolve rename positions.
  -- When state.changes_made is true, positions are relative to `result` (the reconstructed buffer).
  -- When state.changes_made is false, use original entry positions directly (result may differ from source).
  for _, r in ipairs(renames) do
    if r.owner_entry and r.rename_line then
      -- Child rename: owner_entry should be a top-level ordered_entry after
      -- offset adjustments propagated up through process_children_recursive.
      if state.changes_made then
        -- Find which top-level entry it is and add its base row from result.
        for ei, oe in ipairs(ordered_entries) do
          if r.owner_entry == oe then
            r.rename_line = entry_start_rows[ei] + r.rename_line
            break
          end
        end
      else
        -- No changes: use original entry's start_row directly
        r.rename_line = r.owner_entry.start_row + r.rename_line
      end
      r.owner_entry = nil
    elseif r.top_level_index then
      -- Top-level rename
      local ei = r.top_level_index
      local entry = ordered_entries[ei]
      if entry then
        local decl_line_text
        if state.changes_made then
          local base = entry_start_rows[ei]
          local new_comment_count = 0
          local group = parsed_groups[ei]
          if group.new_comments and #group.new_comments > 0 then
            new_comment_count = #group.new_comments
          end
          local decl_offset = entry.decl_start_row - entry.start_row
          r.rename_line = base + decl_offset + new_comment_count
          decl_line_text = result[r.rename_line + 1]
        else
          -- No changes: use original position directly
          r.rename_line = entry.decl_start_row
          local source_lines = vim.api.nvim_buf_get_lines(source_bufnr, entry.decl_start_row, entry.decl_start_row + 1, false)
          decl_line_text = source_lines[1]
        end
        if decl_line_text then
          -- For dotted/colon names, search for the last segment
          local search_name = get_search_name(r.old_name)
          local pattern = "%f[%w_]" .. vim.pesc(search_name) .. "%f[^%w_]"
          local col = decl_line_text:find(pattern)
          if col then
            r.rename_col = col - 1
          end
        end
      end
      r.top_level_index = nil
    end
  end

  -- Build affected_rows from annotated renames — use exact row positions
  for _, r in ipairs(renames) do
    if r.rename_line then
      table.insert(affected_rows, { new_name = r.new_name, decl_row = r.rename_line })
    end
  end

  -- Include entries that received new // comment annotations (top-level and children)
  for i, entry in ipairs(ordered_entries) do
    local group = parsed_groups[i]
    if group.new_comments and #group.new_comments > 0 then
      local decl_row
      if state.changes_made then
        local base = entry_start_rows[i]
        local comment_line_count = entry.decl_start_row - entry.start_row
        local new_comment_count = #group.new_comments
        decl_row = base + comment_line_count + new_comment_count
      else
        decl_row = entry.decl_start_row
      end
      table.insert(affected_rows, { new_name = entry.name, decl_row = decl_row })
    end
  end

  -- Resolve child annotation positions to absolute rows
  for _, a in ipairs(annotated) do
    if a.owner_entry and a.decl_row then
      if state.changes_made then
        for ei, oe in ipairs(ordered_entries) do
          if a.owner_entry == oe then
            a.decl_row = entry_start_rows[ei] + a.decl_row
            break
          end
        end
      else
        a.decl_row = a.owner_entry.start_row + a.decl_row
      end
      table.insert(affected_rows, { new_name = a.name, decl_row = a.decl_row })
    end
  end

  -- Apply changes using minimal diff (only if changes were detected)
  if state.changes_made then
    diff.apply_minimal(source_bufnr, result)
  end

  return true, nil, renames, nil, affected_rows, state.changes_made
end

return M
