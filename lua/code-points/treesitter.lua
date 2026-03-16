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

--- Adjust end_row for nodes whose range includes a trailing newline.
--- If end_col is 0 and end_row > start_row, the node ends at the start of
--- end_row (just the trailing newline from the previous line).
--- @param sr number start_row (0-indexed)
--- @param er number end_row (0-indexed)
--- @param ec number end_col
--- @return number adjusted end_row
local function adjust_end_row(sr, er, ec)
  if ec == 0 and er > sr then
    return er - 1
  end
  return er
end

--- Build a single entry from a treesitter node.
--- @param node any treesitter node
--- @param lang CodePointsLang language module
--- @param bufnr number buffer handle
--- @param sr_override number|nil optional start_row override (when comments are attached)
--- @return table entry
local function build_entry(node, lang, bufnr, sr_override)
  local sr, _, er, ec = node:range()
  er = adjust_end_row(sr, er, ec)

  -- Use overridden start_row if provided (to include leading comments)
  local effective_sr = sr_override or sr

  local name = lang.get_name(node, bufnr)
  if not name or name == "[unknown]" then
    -- Use the first line of the node's text as a meaningful fallback
    local text = vim.treesitter.get_node_text(node, bufnr)
    local first_line = text:match("^([^\n]*)")
    -- Strip the display_type keyword from the start to avoid duplication
    local display_type = lang.get_display_type(node, bufnr)
    if first_line:sub(1, #display_type) == display_type then
      first_line = vim.trim(first_line:sub(#display_type + 1))
    end
    if #first_line > 40 then
      first_line = first_line:sub(1, 37) .. "..."
    end
    name = first_line ~= "" and first_line or "<L" .. (sr + 1) .. ">"
  end

  return {
    name = name,
    display_type = lang.get_display_type(node, bufnr),
    arity = lang.get_arity(node, bufnr),
    start_row = effective_sr,
    decl_start_row = sr, -- the actual declaration start (without leading comments)
    end_row = er,
    lines = vim.api.nvim_buf_get_lines(bufnr, effective_sr, er + 1, false),
    children = nil,
  }
end

--- Walk backwards through a list of sibling nodes to find leading comments
--- that are strictly adjacent to a declaration node (no blank line gap).
--- Returns the adjusted start_row that includes all attached comments.
--- @param siblings table[] list of all sibling nodes
--- @param decl_index number index of the declaration node in siblings (1-indexed)
--- @param comment_types table<string, boolean> set of comment node type names
--- @return number adjusted_start_row
local function find_comment_start(siblings, decl_index, comment_types)
  local decl_node = siblings[decl_index]
  local sr = select(1, decl_node:range())
  local current_sr = sr

  local j = decl_index - 1
  while j >= 1 do
    local prev = siblings[j]
    local prev_type = prev:type()

    if not comment_types[prev_type] then
      break
    end

    local prev_sr, _, prev_er, prev_ec = prev:range()
    prev_er = adjust_end_row(prev_sr, prev_er, prev_ec)

    -- Strict adjacency: comment must end on the line directly before current_sr
    if prev_er + 1 == current_sr then
      current_sr = prev_sr
      j = j - 1
    else
      break
    end
  end

  return current_sr
end

--- Process a list of sibling nodes into entries, attaching leading comments.
--- @param siblings table[] list of sibling treesitter nodes
--- @param lang CodePointsLang language module
--- @param bufnr number buffer handle
--- @param is_decl_fn fun(node): boolean function to check if a node is a declaration
--- @return table[] entries
local function process_siblings(siblings, lang, bufnr, is_decl_fn)
  local comment_types = lang.comment_types or {}
  local entries = {}

  for i, child in ipairs(siblings) do
    if is_decl_fn(child) then
      -- Walk backwards to find leading comments
      local comment_sr = find_comment_start(siblings, i, comment_types)
      local decl_sr = select(1, child:range())
      local sr_override = (comment_sr < decl_sr) and comment_sr or nil

      local entry = build_entry(child, lang, bufnr, sr_override)
      table.insert(entries, entry)
    end
  end

  return entries
end

--- Extract all top-level code points from a buffer using the appropriate language module.
--- @param bufnr number buffer handle
--- @return table[] entries list of entries (with optional children)
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

  -- Collect all top-level children
  local all_children = {}
  for child in root:iter_children() do
    table.insert(all_children, child)
  end

  local comment_types = lang.comment_types or {}
  local entries = {}

  for i, child in ipairs(all_children) do
    if lang.is_declaration(child) then
      -- Walk backwards to find leading comments
      local comment_sr = find_comment_start(all_children, i, comment_types)
      local decl_sr = select(1, child:range())
      local sr_override = (comment_sr < decl_sr) and comment_sr or nil

      local entry = build_entry(child, lang, bufnr, sr_override)

      -- Check if this node has nestable children (e.g., methods in a class/impl)
      if lang.is_nestable and lang.get_body_node and lang.is_child_declaration then
        if lang.is_nestable(child) then
          local body = lang.get_body_node(child)
          if body then
            -- Collect all body children
            local body_children = {}
            for grandchild in body:iter_children() do
              table.insert(body_children, grandchild)
            end

            -- Process children with comment attachment
            local child_entries = process_siblings(body_children, lang, bufnr, function(n)
              return lang.is_child_declaration(n)
            end)

            if #child_entries > 0 then
              entry.children = child_entries
            end
          end
        end
      end

      table.insert(entries, entry)
    end
  end

  return entries, lang
end

return M
