local M = {}

--- Find the (0-indexed line, 0-indexed col) of a symbol name in a buffer
--- by scanning lines within a range for a plain text match.
--- @param bufnr number buffer handle
--- @param name string the symbol name to find
--- @param start_row number 0-indexed start row (inclusive)
--- @param end_row number 0-indexed end row (inclusive)
--- @return number|nil line 0-indexed line, or nil if not found
--- @return number|nil col 0-indexed column, or nil if not found
local function find_symbol_position(bufnr, name, start_row, end_row)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
  for i, line in ipairs(lines) do
    -- Use word-boundary matching to avoid partial matches
    local pattern = "%f[%w_]" .. vim.pesc(name) .. "%f[^%w_]"
    local col_start = line:find(pattern)
    if col_start then
      return start_row + (i - 1), col_start - 1 -- convert to 0-indexed
    end
  end
  return nil, nil
end

--- Check if any LSP client attached to the buffer supports rename.
--- @param bufnr number buffer handle
--- @return boolean
function M.has_rename_support(bufnr)
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  for _, client in ipairs(clients) do
    if client.server_capabilities.renameProvider then
      return true
    end
  end
  return false
end

--- Apply a list of LSP renames sequentially (chained via callbacks).
--- Each rename positions the cursor on the symbol and uses vim.lsp.buf.rename()
--- to correctly handle encoding and protocol details.
--- @param bufnr number source buffer handle
--- @param renames table[] list of { old_name: string, new_name: string }
--- @param on_done fun() callback when all renames are complete
function M.apply_renames(bufnr, renames, on_done)
  if #renames == 0 then
    if on_done then on_done() end
    return
  end

  -- Find the source window for cursor positioning
  local source_win = nil
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == bufnr then
      source_win = w
      break
    end
  end

  local function do_rename(idx)
    if idx > #renames then
      if on_done then on_done() end
      return
    end

    local r = renames[idx]
    local old_name = r.old_name
    local new_name = r.new_name

    -- Use exact position if available, otherwise search the buffer
    local line, col
    if r.rename_line and r.rename_col then
      line = r.rename_line
      col = r.rename_col
    else
      local total_lines = vim.api.nvim_buf_line_count(bufnr)
      line, col = find_symbol_position(bufnr, old_name, 0, total_lines - 1)
    end

    -- For dotted/colon names (e.g., M.greet, M:initialize, Animal.Speak),
    -- extract just the last segment of new_name for the LSP rename.
    -- Only adjust column if rename_col was NOT already set by reorder.lua
    -- (reorder.lua already computes the correct column for the last segment).
    local last_sep = old_name:find("[%.:]([^%.:]*)$")
    if last_sep then
      local last_segment = old_name:sub(last_sep + 1)
      local had_exact_pos = r.rename_line ~= nil and r.rename_col ~= nil
      if not had_exact_pos then
        if line and col then
          -- Found the full name via text search — advance past the prefix
          col = col + last_sep
        else
          -- Full name not in source (e.g., Go's "Animal.Speak" is synthetic).
          -- Search for just the last segment instead.
          local total_lines = vim.api.nvim_buf_line_count(bufnr)
          line, col = find_symbol_position(bufnr, last_segment, 0, total_lines - 1)
        end
      end
      -- Extract just the last segment of new_name
      local new_last_sep = new_name:find("[%.:]([^%.:]*)$")
      if new_last_sep then
        new_name = new_name:sub(new_last_sep + 1)
      end
    end

    if not line or not col then
      vim.notify(
        "Fluoride: could not find symbol '" .. old_name .. "' for rename",
        vim.log.levels.WARN
      )
      vim.schedule(function()
        do_rename(idx + 1)
      end)
      return
    end

    if source_win then
      -- Position cursor in source window and use vim.lsp.buf.rename()
      -- This handles encoding, prepareRename, and all protocol details correctly.
      -- We must set the current window so vim.lsp.buf.rename uses the right context.
      local prev_win = vim.api.nvim_get_current_win()
      vim.api.nvim_set_current_win(source_win)
      vim.api.nvim_win_set_cursor(source_win, { line + 1, col }) -- 1-indexed line, 0-indexed col

      -- Build proper LSP params from the cursor position (handles encoding correctly)
      local clients = vim.lsp.get_clients({ bufnr = bufnr })
      local encoding = "utf-16"
      for _, client in ipairs(clients) do
        if client.server_capabilities.renameProvider then
          encoding = client.offset_encoding or "utf-16"
          break
        end
      end
      local lsp_params = vim.lsp.util.make_position_params(source_win, encoding)
      lsp_params.newName = new_name

      vim.lsp.buf_request(bufnr, "textDocument/rename", lsp_params, function(err, result, ctx)
        if err then
          vim.notify(
            "Fluoride: LSP rename failed for '" .. old_name .. "': " .. tostring(err.message or err),
            vim.log.levels.ERROR
          )
        elseif result then
          local client = vim.lsp.get_client_by_id(ctx.client_id)
          local encoding = client and client.offset_encoding or "utf-16"
          vim.lsp.util.apply_workspace_edit(result, encoding)
          vim.notify(
            "Fluoride: renamed '" .. old_name .. "' -> '" .. new_name .. "'",
            vim.log.levels.INFO
          )
        end

        -- Restore window and continue with next rename
        vim.schedule(function()
          if vim.api.nvim_win_is_valid(prev_win) then
            vim.api.nvim_set_current_win(prev_win)
          end
          do_rename(idx + 1)
        end)
      end)
    else
      -- No source window: use raw LSP request as fallback
      local params = {
        textDocument = { uri = vim.uri_from_bufnr(bufnr) },
        position = { line = line, character = col },
        newName = new_name,
      }

      vim.lsp.buf_request(bufnr, "textDocument/rename", params, function(err, result, ctx)
        if err then
          vim.notify(
            "Fluoride: LSP rename failed for '" .. old_name .. "': " .. tostring(err.message or err),
            vim.log.levels.ERROR
          )
        elseif result then
          local client = vim.lsp.get_client_by_id(ctx.client_id)
          local encoding = client and client.offset_encoding or "utf-16"
          vim.lsp.util.apply_workspace_edit(result, encoding)
          vim.notify(
            "Fluoride: renamed '" .. old_name .. "' -> '" .. new_name .. "'",
            vim.log.levels.INFO
          )
        end

        vim.schedule(function()
          do_rename(idx + 1)
        end)
      end)
    end
  end

  do_rename(1)
end

return M
