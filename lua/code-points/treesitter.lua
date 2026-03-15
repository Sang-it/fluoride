local M = {}

--- Registry of language modules, keyed by filetype.
--- @type table<string, CodePointsLang>
local lang_registry = {}

--- Filetype aliases for auto-loading (e.g., typescriptreact → typescript module).
local FT_ALIASES = {
  typescriptreact = "typescript",
  javascriptreact = "javascript",
}

--- Register a language module for all its filetypes.
--- @param lang_module CodePointsLang
function M.register(lang_module)
  for _, ft in ipairs(lang_module.filetypes) do
    lang_registry[ft] = lang_module
  end
end

--- Get the language module for a filetype, with lazy auto-loading.
--- @param ft string Neovim filetype
--- @return CodePointsLang|nil
function M.get_lang(ft)
  -- Return from registry if already loaded
  if lang_registry[ft] then
    return lang_registry[ft]
  end

  -- Try to auto-load by filetype name, then by alias
  local names_to_try = { ft }
  if FT_ALIASES[ft] then
    table.insert(names_to_try, FT_ALIASES[ft])
  end

  for _, name in ipairs(names_to_try) do
    local ok, lang = pcall(require, "code-points.langs." .. name)
    if ok and lang and lang.filetypes then
      M.register(lang)
      if lang_registry[ft] then
        return lang_registry[ft]
      end
    end
  end

  return nil
end

--- Extract all top-level code points from a buffer using the appropriate language module.
--- @param bufnr number buffer handle
--- @return table[] entries list of { name, display_type, arity, start_row, end_row, lines }
--- @return CodePointsLang|nil lang the language module used
function M.get_code_points(bufnr)
  local ft = vim.bo[bufnr].filetype
  local lang = M.get_lang(ft)
  if not lang then
    vim.notify("CodePoints: unsupported filetype: " .. ft, vim.log.levels.WARN)
    return {}, nil
  end

  -- Resolve the treesitter parser name
  local parser_name = lang.parsers and lang.parsers[ft] or ft

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, parser_name)
  if not ok or not parser then
    vim.notify("CodePoints: failed to get treesitter parser for " .. parser_name, vim.log.levels.ERROR)
    return {}, lang
  end

  local tree = parser:parse()[1]
  if not tree then
    vim.notify("CodePoints: failed to parse buffer", vim.log.levels.ERROR)
    return {}, lang
  end

  local root = tree:root()
  local entries = {}

  for child in root:iter_children() do
    if lang.is_declaration(child) then
      local sr, _, er, ec = child:range()

      -- If end_col is 0, the node ends at the start of end_row (i.e., just the
      -- newline of the previous line). Don't include that extra line.
      -- This is common with preprocessor directives in C/C++.
      if ec == 0 and er > sr then
        er = er - 1
      end

      local name = lang.get_name(child, bufnr)

      -- Fallback: if the language module couldn't extract a name, use the line number
      if not name or name == "[unknown]" then
        name = "<L" .. (sr + 1) .. ">"
      end

      table.insert(entries, {
        name = name,
        display_type = lang.get_display_type(child, bufnr),
        arity = lang.get_arity(child, bufnr),
        start_row = sr,
        end_row = er,
        lines = vim.api.nvim_buf_get_lines(bufnr, sr, er + 1, false),
      })
    end
  end

  return entries, lang
end

return M
