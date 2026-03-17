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
  impl_item = "impl",
  trait_item = "trait",
  type_item = "type",
  const_item = "const",
  static_item = "static",
  mod_item = "mod",
  macro_definition = "macro",
}

local SKIP_TYPES = {
  use_declaration = true,
  line_comment = true,
  block_comment = true,
  attribute_item = true,
  inner_attribute_item = true,
  extern_crate_declaration = true,
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
    local type_node = node:field("type")[1]
    local trait_node = node:field("trait")[1]
    if trait_node and type_node then
      return vim.treesitter.get_node_text(trait_node, bufnr) .. " for " .. vim.treesitter.get_node_text(type_node, bufnr)
    elseif type_node then
      return vim.treesitter.get_node_text(type_node, bufnr)
    end
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
  return t == "impl_item" or t == "trait_item"
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
  return nil
end

-- Child node types inside impl/trait blocks
local CHILD_TYPES = {
  function_item = true,
  const_item = true,
  type_item = true,
}

--- Check if a child node inside a nestable parent is a declaration.
--- @param node any treesitter node
--- @return boolean
function M.is_child_declaration(node)
  return CHILD_TYPES[node:type()] or false
end

return M
