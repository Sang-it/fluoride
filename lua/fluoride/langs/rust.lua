local M = {}

M.filetypes = { "rust" }

M.parsers = {
  rust = "rust",
}

M.comment_types = { line_comment = true, block_comment = true }
M.comment_prefix = "//"

local DECLARATION_TYPES = {
  function_item = "fn",
  struct_item = "struct",
  enum_item = "enum",
  union_item = "union",
  impl_item = "impl",
  trait_item = "trait",
  type_item = "type",
  const_item = "const",
  static_item = "static",
  mod_item = "mod",
  macro_definition = "macro",
  macro_invocation = "macro",
  foreign_mod_item = "extern",
  expression_statement = "expression",
}

local SKIP_TYPES = {
  use_declaration = true,
  line_comment = true,
  block_comment = true,
  attribute_item = true,
  inner_attribute_item = true,
  extern_crate_declaration = true,
  empty_statement = true,
}

M.highlights = {
  ["fn"]      = { prefix = "Keyword",  name = "Function" },
  ["pub fn"]  = { prefix = "Keyword",  name = "Function" },
  ["struct"]  = { prefix = "Type",     name = "Type" },
  ["pub struct"] = { prefix = "Type",  name = "Type" },
  ["enum"]    = { prefix = "Type",     name = "Type" },
  ["pub enum"] = { prefix = "Type",    name = "Type" },
  ["impl"]    = { prefix = "Keyword",  name = "Type" },
  ["trait"]   = { prefix = "Type",     name = "Type" },
  ["pub trait"] = { prefix = "Type",   name = "Type" },
  ["type"]    = { prefix = "Type",     name = "Type" },
  ["pub type"] = { prefix = "Type",    name = "Type" },
  ["const"]   = { prefix = "Keyword",  name = "Identifier" },
  ["pub const"] = { prefix = "Keyword", name = "Identifier" },
  ["static"]  = { prefix = "Keyword",  name = "Identifier" },
  ["pub static"] = { prefix = "Keyword", name = "Identifier" },
  ["mod"]     = { prefix = "Keyword",  name = "Identifier" },
  ["pub mod"] = { prefix = "Keyword",  name = "Identifier" },
  ["macro"]   = { prefix = "Keyword",  name = "Function" },
  ["union"]   = { prefix = "Type",     name = "Type" },
  ["pub union"] = { prefix = "Type",   name = "Type" },
  ["extern"]  = { prefix = "Keyword",  name = "Identifier" },
  ["expression"] = { prefix = "Keyword", name = "Identifier" },
  ["field"]   = { prefix = "Keyword",  name = "Identifier" },
  ["pub field"] = { prefix = "Keyword", name = "Identifier" },
  ["variant"] = { prefix = "Type",     name = "Identifier" },
}

function M.is_declaration(node)
  return not SKIP_TYPES[node:type()]
end

--- Check if a node has a visibility modifier (pub).
--- @param node any treesitter node
--- @param bufnr number buffer handle
--- @return boolean
local function is_pub(node, bufnr)
  for child in node:iter_children() do
    if child:type() == "visibility_modifier" then
      return true
    end
  end
  -- Also check raw text as fallback
  local text = vim.treesitter.get_node_text(node, bufnr)
  return text:match("^pub%s") ~= nil or text:match("^pub%(") ~= nil
end

function M.get_name(node, bufnr)
  local node_type = node:type()

  if node_type == "function_item"
    or node_type == "struct_item"
    or node_type == "enum_item"
    or node_type == "union_item"
    or node_type == "trait_item"
    or node_type == "type_item"
    or node_type == "const_item"
    or node_type == "static_item"
    or node_type == "mod_item"
  then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  -- impl_item: impl Foo { ... } or impl Trait for Foo { ... }
  if node_type == "impl_item" then
    local text = vim.treesitter.get_node_text(node, bufnr)
    local first_line = text:match("^([^\n]*)")
    -- Strip "impl" keyword and trailing "{"
    first_line = first_line:gsub("^impl%s+", "")
    first_line = first_line:gsub("%s*{%s*$", "")
    first_line = vim.trim(first_line)
    if #first_line > 50 then
      first_line = first_line:sub(1, 47) .. "..."
    end
    if first_line ~= "" then
      return first_line
    end
    -- Fallback to type node
    local type_node = node:field("type")[1]
    if type_node then
      return vim.treesitter.get_node_text(type_node, bufnr)
    end
  end

  -- Struct fields and enum variants
  if node_type == "field_declaration" or node_type == "enum_variant" then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  -- macro_invocation: e.g., lazy_static! { ... }, vec![1, 2, 3]
  if node_type == "macro_invocation" then
    local macro_node = node:field("macro")[1]
    if macro_node then
      return vim.treesitter.get_node_text(macro_node, bufnr) .. "!"
    end
  end

  -- foreign_mod_item: extern "C" { ... }
  if node_type == "foreign_mod_item" then
    local text = vim.treesitter.get_node_text(node, bufnr)
    local first_line = text:match("^([^\n]*)")
    first_line = first_line:gsub("[{]%s*$", "")
    first_line = first_line:gsub("^extern%s*", "")
    first_line = vim.trim(first_line)
    if #first_line > 40 then
      first_line = first_line:sub(1, 37) .. "..."
    end
    if first_line == "" then first_line = "<extern>" end
    return first_line
  end

  -- expression_statement: top-level expression
  if node_type == "expression_statement" then
    local text = vim.treesitter.get_node_text(node, bufnr)
    local first_line = text:match("^([^\n]*)")
    if #first_line > 40 then
      first_line = first_line:sub(1, 37) .. "..."
    end
    return first_line
  end

  -- macro_definition: macro_rules! name { ... }
  if node_type == "macro_definition" then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr) .. "!"
    end
  end

  return "[unknown]"
end

function M.get_display_type(node, bufnr)
  local node_type = node:type()

  -- Struct fields and enum variants
  if node_type == "field_declaration" then
    if is_pub(node, bufnr) then return "pub field" end
    return "field"
  end
  if node_type == "enum_variant" then
    return "variant"
  end

  local base = DECLARATION_TYPES[node_type] or node_type

  if is_pub(node, bufnr) and base ~= "impl" and base ~= "macro" then
    return "pub " .. base
  end

  return base
end

function M.get_arity(node, _bufnr)
  local node_type = node:type()

  if node_type == "function_item" then
    local params = node:field("parameters")[1]
    if params then
      local count = 0
      for child in params:iter_children() do
        local ct = child:type()
        if ct == "parameter" or ct == "self_parameter" then
          -- Don't count self/&self/&mut self
          if ct == "self_parameter" then
            -- skip
          else
            count = count + 1
          end
        end
      end
      return count
    end
    return 0
  end

  return nil
end

--- Check if a node contains child declarations that can be nested.
--- @param node any treesitter node
--- @return boolean
function M.is_nestable(node)
  local t = node:type()
  return t == "impl_item" or t == "trait_item" or t == "struct_item" or t == "enum_item"
    or t == "union_item" or t == "mod_item"
end

--- Get the body node to iterate for child declarations.
--- @param node any treesitter node
--- @return any|nil body node
function M.get_body_node(node)
  local t = node:type()
  if t == "impl_item" or t == "trait_item" then
    for child in node:iter_children() do
      if child:type() == "declaration_list" then
        return child
      end
    end
  end
  if t == "struct_item" or t == "union_item" then
    for child in node:iter_children() do
      if child:type() == "field_declaration_list" then
        return child
      end
    end
  end
  if t == "enum_item" then
    for child in node:iter_children() do
      if child:type() == "enum_variant_list" then
        return child
      end
    end
  end
  if t == "mod_item" then
    for child in node:iter_children() do
      if child:type() == "declaration_list" then
        return child
      end
    end
  end
  return nil
end

-- Child node types inside impl/trait/struct/enum/mod blocks
local CHILD_TYPES = {
  function_item = true,
  const_item = true,
  type_item = true,
  field_declaration = true,
  enum_variant = true,
  -- mod children (full declarations)
  struct_item = true,
  enum_item = true,
  union_item = true,
  impl_item = true,
  trait_item = true,
  static_item = true,
  mod_item = true,
  macro_definition = true,
  macro_invocation = true,
}

--- Check if a child node inside a nestable parent is a declaration.
--- @param node any treesitter node
--- @return boolean
function M.is_child_declaration(node)
  return CHILD_TYPES[node:type()] or false
end

return M
