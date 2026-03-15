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

--- Parse a display line to extract the entry name.
--- Display format: "<type_prefix> <name>"
--- We need to match back to original entries by name.
--- @param line string the display line from the float buffer
--- @return string|nil name the extracted name, or nil if unparseable
local function parse_display_line(line)
  local trimmed = vim.trim(line)
  if trimmed == "" then
    return nil
  end

  -- Try to strip known type prefixes (longest first)
  for _, prefix in ipairs(TYPE_PREFIXES) do
    if trimmed:sub(1, #prefix) == prefix then
      local rest = trimmed:sub(#prefix + 1)
      rest = vim.trim(rest)
      if rest ~= "" then
        return rest
      end
    end
  end

  -- Fallback: return everything (for expression statements or unknown types)
  return trimmed
end

--- Build an index mapping from entry name to entry (for fast lookup).
--- If there are duplicate names, they are stored in order.
--- @param entries table[] original entries
--- @return table<string, table[]> name_to_entries
local function build_name_index(entries)
  local index = {}
  for _, entry in ipairs(entries) do
    if not index[entry.name] then
      index[entry.name] = {}
    end
    table.insert(index[entry.name], entry)
  end
  return index
end

--- Apply reordering to the source buffer.
--- @param source_bufnr number the source buffer handle
--- @param original_entries table[] the original code point entries
--- @param new_display_lines string[] the reordered display lines from the float
--- @return boolean ok, string|nil error
function M.apply(source_bufnr, original_entries, new_display_lines)
  if #new_display_lines == 0 then
    return false, "no entries in the reorder list"
  end

  -- Parse new ordering from display lines
  local new_order_names = {}
  for _, line in ipairs(new_display_lines) do
    local name = parse_display_line(line)
    if name then
      table.insert(new_order_names, name)
    else
      return false, "could not parse line: " .. line
    end
  end

  -- Build index of original entries by name
  local name_index = build_name_index(original_entries)

  -- Track which entries have been consumed (for duplicates)
  local consumed = {}

  -- Resolve new ordering to actual entries
  local ordered_entries = {}
  for _, name in ipairs(new_order_names) do
    local candidates = name_index[name]
    if not candidates or #candidates == 0 then
      return false, "unknown code point: " .. name
    end

    -- Find the first unconsumed entry with this name
    local found = false
    for i, entry in ipairs(candidates) do
      local key = name .. ":" .. i
      if not consumed[key] then
        consumed[key] = true
        table.insert(ordered_entries, entry)
        found = true
        break
      end
    end

    if not found then
      return false, "duplicate reference to: " .. name
    end
  end

  -- Collect all content that is NOT part of any original entry (imports, comments, gaps).
  -- We'll preserve everything before the first entry and between/after entries that
  -- is not part of a declaration (i.e., imports and comments stay in place at the top).
  local total_lines = vim.api.nvim_buf_line_count(source_bufnr)

  -- Build a set of all line ranges covered by original entries
  local covered = {}
  for _, entry in ipairs(original_entries) do
    for row = entry.start_row, entry.end_row do
      covered[row] = true
    end
  end

  -- Everything before the first entry's start_row is "preamble" (imports, comments, etc.)
  local first_entry_row = original_entries[1].start_row
  local preamble = {}
  if first_entry_row > 0 then
    preamble = vim.api.nvim_buf_get_lines(source_bufnr, 0, first_entry_row, false)
  end

  -- Everything after the last entry's end_row is "postamble"
  local last_entry_row = original_entries[#original_entries].end_row
  local postamble = {}
  if last_entry_row + 1 < total_lines then
    postamble = vim.api.nvim_buf_get_lines(source_bufnr, last_entry_row + 1, total_lines, false)
  end

  -- Build new buffer content
  local result = {}

  -- Add preamble (imports, leading comments, etc.)
  for _, line in ipairs(preamble) do
    table.insert(result, line)
  end

  -- Add reordered entries with blank line separators
  for i, entry in ipairs(ordered_entries) do
    -- Add a blank line separator between entries (and after preamble if it exists)
    if i == 1 and #preamble > 0 then
      -- Ensure there's a blank line between preamble and first entry
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

  return true, nil
end

return M
