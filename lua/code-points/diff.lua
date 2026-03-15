local M = {}

--- Detect the line ending used in a buffer.
--- @param bufnr number buffer handle
--- @return string line_ending "\n" or "\r\n"
local function buf_line_ending(bufnr)
  if vim.bo[bufnr].fileformat == "dos" then
    return "\r\n"
  end
  return "\n"
end

--- Apply new content to a buffer using minimal diffs.
--- Uses vim.diff to compute change hunks, converts them to LSP TextEdit
--- objects, and applies via vim.lsp.util.apply_text_edits. This avoids
--- whole-buffer replacement which causes syntax highlighting flicker.
--- @param bufnr number buffer handle
--- @param new_lines string[] the new buffer content as a list of lines
function M.apply_minimal(bufnr, new_lines)
  local original_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local line_ending = buf_line_ending(bufnr)

  local original_text = table.concat(original_lines, line_ending) .. line_ending
  local new_text = table.concat(new_lines, line_ending) .. line_ending

  -- Fast path: no changes
  if original_text == new_text then
    return
  end

  -- Compute minimal diff hunks
  local indices = vim.diff(original_text, new_text, {
    result_type = "indices",
    algorithm = "histogram",
  })

  if not indices or #indices == 0 then
    return
  end

  -- Convert diff hunks to LSP TextEdit objects.
  -- All edits use full-line ranges to avoid character-level edge cases.
  local text_edits = {}

  for _, idx in ipairs(indices) do
    local orig_start, orig_count, new_start, new_count = unpack(idx)

    local is_insert = orig_count == 0
    local is_delete = new_count == 0

    -- Build the replacement text from the new lines
    local replacement = {}
    if not is_delete then
      for i = new_start, new_start + new_count - 1 do
        table.insert(replacement, new_lines[i])
      end
    end

    local start_line, start_char, end_line, end_char
    local new_text_str

    if is_insert then
      -- Insert at the beginning of the line after orig_start
      start_line = orig_start
      start_char = 0
      end_line = orig_start
      end_char = 0
      new_text_str = table.concat(replacement, line_ending) .. line_ending
    elseif is_delete then
      -- Delete full lines: from start of first line to start of line after last
      start_line = orig_start - 1 -- 0-indexed
      start_char = 0
      end_line = orig_start + orig_count - 1 -- 0-indexed, one past last deleted line
      end_char = 0
      new_text_str = ""
    else
      -- Replace full lines: from start of first line to start of line after last
      start_line = orig_start - 1 -- 0-indexed
      start_char = 0
      end_line = orig_start + orig_count - 1 -- 0-indexed, one past last replaced line
      end_char = 0
      new_text_str = table.concat(replacement, line_ending) .. line_ending
    end

    table.insert(text_edits, {
      range = {
        start = { line = start_line, character = start_char },
        ["end"] = { line = end_line, character = end_char },
      },
      newText = new_text_str,
    })
  end

  -- Apply the minimal edits
  vim.lsp.util.apply_text_edits(text_edits, bufnr, "utf-8")
end

return M
