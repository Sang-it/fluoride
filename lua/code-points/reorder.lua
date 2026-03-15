local M = {}

--- Known type prefixes used in display lines (longest first for greedy matching).
local TYPE_PREFIXES = {
  "export function",
  "export variable",
  "export class",
  "export interface",
  "export type",
  "export enum",
  "export",
  "function",
  "variable",
  "class",
  "interface",
  "type",
  "enum",
  "expression",
}

--- Strip the arity suffix (e.g., "/2") from a name.
--- @param name string
--- @return string name_without_arity
local function strip_arity(name)
  return name:match("^(.+)/%d+$") or name
end

--- Parse a display line to extract the type prefix and name.
--- Display format: "<type_prefix> <name>" or "<type_prefix> <name>/<arity>"
--- @param line string the display line from the float buffer
--- @return string|nil prefix the type prefix, or nil if unparseable
--- @return string|nil name the extracted name (without arity), or nil if unparseable
local function parse_display_line(line)
  local trimmed = vim.trim(line)
  if trimmed == "" then
    return nil, nil
  end

  -- Try to strip known type prefixes (longest first)
  for _, prefix in ipairs(TYPE_PREFIXES) do
    if trimmed:sub(1, #prefix) == prefix then
      local rest = trimmed:sub(#prefix + 1)
      rest = vim.trim(rest)
      if rest ~= "" then
        return prefix, strip_arity(rest)
      end
    end
  end

  -- Fallback: no recognized prefix
  return nil, strip_arity(trimmed)
end

--- Build an index mapping from display_type to entries (for matching by type prefix).
--- If there are duplicate types, they are stored in order.
--- @param entries table[] original entries
--- @return table<string, table[]> type_to_entries
local function build_type_index(entries)
  local index = {}
  for _, entry in ipairs(entries) do
    if not index[entry.display_type] then
      index[entry.display_type] = {}
    end
    table.insert(index[entry.display_type], entry)
  end
  return index
end

--- Apply reordering and detect renames.
--- @param source_bufnr number the source buffer handle
--- @param original_entries table[] the original code point entries
--- @param new_display_lines string[] the reordered/edited display lines from the float
--- @return boolean ok
--- @return string|nil error
--- @return table[] renames list of { old_name: string, new_name: string }
function M.apply(source_bufnr, original_entries, new_display_lines)
  if #new_display_lines == 0 then
    return false, "no entries in the reorder list", {}
  end

  if #new_display_lines ~= #original_entries then
    return false, "line count mismatch: expected " .. #original_entries .. " entries, got " .. #new_display_lines .. ". Do not add or remove lines.", {}
  end

  -- Parse each new display line into { prefix, name }
  local parsed_lines = {}
  for _, line in ipairs(new_display_lines) do
    local prefix, name = parse_display_line(line)
    if not name then
      return false, "could not parse line: " .. line, {}
    end
    table.insert(parsed_lines, { prefix = prefix, name = name })
  end

  -- Match each parsed line to an original entry by display_type (type prefix).
  -- The type prefix is immutable — if the user changed it, we use the original
  -- type prefix for matching by ignoring prefix changes.
  --
  -- Strategy: for each parsed line, find the best matching original entry:
  --   1. Exact match (same prefix AND same name) — consumed first
  --   2. Name-only match (different prefix but same name) — treat as prefix edit (ignored)
  --   3. Prefix-only match (same prefix but different name) — this is a rename
  --
  -- We do this in two passes to prioritize exact matches.

  local matched = {}       -- matched[i] = original entry index matched to new line i
  local used = {}          -- used[j] = true if original entry j has been claimed

  -- Pass 1: exact matches (same name)
  for i, parsed in ipairs(parsed_lines) do
    for j, entry in ipairs(original_entries) do
      if not used[j] and parsed.name == entry.name then
        matched[i] = j
        used[j] = true
        break
      end
    end
  end

  -- Pass 2: remaining unmatched lines — match by display_type prefix
  -- These are the rename candidates
  for i, parsed in ipairs(parsed_lines) do
    if not matched[i] then
      -- Try matching by the parsed prefix first (user kept the prefix)
      for j, entry in ipairs(original_entries) do
        if not used[j] and parsed.prefix and parsed.prefix == entry.display_type then
          matched[i] = j
          used[j] = true
          break
        end
      end
    end
  end

  -- Pass 3: any still unmatched — match to any remaining unused entry
  for i, _ in ipairs(parsed_lines) do
    if not matched[i] then
      for j, _ in ipairs(original_entries) do
        if not used[j] then
          matched[i] = j
          used[j] = true
          break
        end
      end
    end
  end

  -- Verify all lines are matched
  for i, _ in ipairs(parsed_lines) do
    if not matched[i] then
      return false, "could not match line " .. i .. " to any original entry", {}
    end
  end

  -- Build ordered entries and detect renames
  local ordered_entries = {}
  local renames = {}

  for i, parsed in ipairs(parsed_lines) do
    local entry = original_entries[matched[i]]
    table.insert(ordered_entries, entry)

    if parsed.name ~= entry.name then
      table.insert(renames, {
        old_name = entry.name,
        new_name = parsed.name,
      })
    end
  end

  -- Collect preamble (imports, comments, etc. before first entry)
  local total_lines = vim.api.nvim_buf_line_count(source_bufnr)

  local first_entry_row = original_entries[1].start_row
  local preamble = {}
  if first_entry_row > 0 then
    preamble = vim.api.nvim_buf_get_lines(source_bufnr, 0, first_entry_row, false)
  end

  -- Collect postamble (content after last entry)
  local last_entry_row = original_entries[#original_entries].end_row
  local postamble = {}
  if last_entry_row + 1 < total_lines then
    postamble = vim.api.nvim_buf_get_lines(source_bufnr, last_entry_row + 1, total_lines, false)
  end

  -- Build new buffer content
  local result = {}

  -- Add preamble
  for _, line in ipairs(preamble) do
    table.insert(result, line)
  end

  -- Add reordered entries with blank line separators
  for i, entry in ipairs(ordered_entries) do
    if i == 1 and #preamble > 0 then
      if #result > 0 and result[#result] ~= "" then
        table.insert(result, "")
      end
    elseif i > 1 then
      table.insert(result, "")
    end

    for _, line in ipairs(entry.lines) do
      table.insert(result, line)
    end
  end

  -- Add postamble
  for _, line in ipairs(postamble) do
    table.insert(result, line)
  end

  -- Replace the entire source buffer
  vim.api.nvim_buf_set_lines(source_bufnr, 0, -1, false, result)

  return true, nil, renames
end

return M
