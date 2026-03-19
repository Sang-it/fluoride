local M = {}

M.filetypes = { "cpp" }

M.parsers = {
  cpp = "cpp",
}

M.comment_types = { comment = true }
M.comment_prefix = "//"

local SKIP_TYPES = {
  comment = true,
  preproc_include = true,
  preproc_ifdef = true,
  preproc_ifndef = true,
  preproc_if = true,
  preproc_else = true,
  preproc_endif = true,
  preproc_call = true,
  preproc_pragma = true,
  linkage_specification = true,
  using_declaration = true,
  import_declaration = true,
  module_declaration = true,
  global_module_fragment_declaration = true,
  private_module_fragment_declaration = true,
  empty_declaration = true,
  empty_statement = true,
  [";"] = true,
}

M.highlights = {
  ["function"]      = { prefix = "Keyword",  name = "Function" },
  ["struct"]        = { prefix = "Type",     name = "Type" },
  ["enum"]          = { prefix = "Type",     name = "Type" },
  ["enum class"]    = { prefix = "Type",     name = "Type" },
  ["union"]         = { prefix = "Type",     name = "Type" },
  ["typedef"]       = { prefix = "Type",     name = "Type" },
  ["variable"]      = { prefix = "Keyword",  name = "Identifier" },
  ["#define"]       = { prefix = "PreProc",  name = "Identifier" },
  ["class"]         = { prefix = "Type",     name = "Type" },
  ["namespace"]     = { prefix = "Keyword",  name = "Identifier" },
  ["template"]      = { prefix = "Keyword",  name = "Function" },
  ["using"]         = { prefix = "Type",     name = "Type" },
  ["concept"]       = { prefix = "Type",     name = "Type" },
  ["friend"]        = { prefix = "Keyword",  name = "Identifier" },
  ["static_assert"] = { prefix = "Keyword",  name = "Identifier" },
  ["export"]        = { prefix = "Keyword",  name = "Identifier" },
  ["expression"]    = { prefix = "Keyword",  name = "Identifier" },
  -- Children
  ["field"]         = { prefix = "Keyword",  name = "Identifier" },
  ["enumerator"]    = { prefix = "Type",     name = "Identifier" },
  ["method"]        = { prefix = "Keyword",  name = "Function" },
  ["constructor"]   = { prefix = "Keyword",  name = "Function" },
  ["destructor"]    = { prefix = "Keyword",  name = "Function" },
}

function M.is_declaration(node)
  return not SKIP_TYPES[node:type()]
end

--- Extract a name from a declarator (handles C++ qualified names, destructors, operators)
--- @param declarator any treesitter node
--- @param bufnr number buffer handle
--- @return string|nil name
local function extract_declarator_name(declarator, bufnr)
  if not declarator then return nil end
  local dt = declarator:type()

  if dt == "function_declarator" then
    local inner = declarator:field("declarator")[1]
    if inner then
      return extract_declarator_name(inner, bufnr)
    end
  end

  if dt == "pointer_declarator" or dt == "reference_declarator" then
    for child in declarator:iter_children() do
      local ct = child:type()
      if ct == "function_declarator" or ct == "identifier" or ct == "qualified_identifier"
        or ct == "field_identifier" or ct == "destructor_name" or ct == "operator_name" then
        return extract_declarator_name(child, bufnr)
      end
    end
  end

  if dt == "qualified_identifier" then
    return vim.treesitter.get_node_text(declarator, bufnr)
  end

  if dt == "destructor_name" then
    return "~" .. vim.treesitter.get_node_text(declarator, bufnr):gsub("^~", "")
  end

  if dt == "operator_name" or dt == "operator_cast" then
    return vim.treesitter.get_node_text(declarator, bufnr)
  end

  if dt == "identifier" or dt == "field_identifier" or dt == "type_identifier" then
    return vim.treesitter.get_node_text(declarator, bufnr)
  end

  if dt == "init_declarator" then
    local inner = declarator:field("declarator")[1]
    if inner then
      return extract_declarator_name(inner, bufnr)
    end
  end

  if dt == "structured_binding_declarator" then
    return vim.treesitter.get_node_text(declarator, bufnr)
  end

  -- Fallback
  local text = vim.treesitter.get_node_text(declarator, bufnr)
  return text:match("^[%*&]*([%w_:~]+)") or text
end

function M.get_name(node, bufnr)
  local node_type = node:type()

  -- function_definition
  if node_type == "function_definition" then
    local declarator = node:field("declarator")[1]
    return extract_declarator_name(declarator, bufnr) or "[unknown]"
  end

  -- declaration (variable, forward declaration, etc.)
  if node_type == "declaration" then
    local declarator = node:field("declarator")[1]
    if declarator then
      return extract_declarator_name(declarator, bufnr) or "[unknown]"
    end
    -- No declarator — bare type declaration (enum Foo { ... };)
    for child in node:iter_children() do
      local ct = child:type()
      if ct == "struct_specifier" or ct == "enum_specifier" or ct == "union_specifier" or ct == "class_specifier" then
        local name_node = child:field("name")[1]
        if name_node then
          return vim.treesitter.get_node_text(name_node, bufnr)
        end
      end
    end
  end

  -- type_definition (typedef)
  if node_type == "type_definition" then
    local declarator = node:field("declarator")[1]
    if declarator then
      return extract_declarator_name(declarator, bufnr) or vim.treesitter.get_node_text(declarator, bufnr)
    end
  end

  -- preproc_def / preproc_function_def
  if node_type == "preproc_def" or node_type == "preproc_function_def" then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  -- class_specifier, struct_specifier, union_specifier, enum_specifier
  if node_type == "class_specifier" or node_type == "struct_specifier"
    or node_type == "union_specifier" or node_type == "enum_specifier" then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  -- namespace_definition
  if node_type == "namespace_definition" then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
    return "<anonymous>"
  end

  -- alias_declaration: using MyInt = int;
  if node_type == "alias_declaration" then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  -- concept_definition
  if node_type == "concept_definition" then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  -- namespace_alias_definition: namespace fs = std::filesystem;
  if node_type == "namespace_alias_definition" then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  -- template_declaration: recurse into child
  if node_type == "template_declaration" then
    for child in node:iter_children() do
      local ct = child:type()
      if ct ~= "template_parameter_list" then
        local name = M.get_name(child, bufnr)
        if name and name ~= "[unknown]" then
          return name
        end
      end
    end
  end

  -- export_declaration: recurse into child
  if node_type == "export_declaration" then
    for child in node:iter_children() do
      local name = M.get_name(child, bufnr)
      if name and name ~= "[unknown]" then
        return name
      end
    end
  end

  -- friend_declaration: recurse into child
  if node_type == "friend_declaration" then
    for child in node:iter_children() do
      local ct = child:type()
      if ct == "declaration" or ct == "function_definition" then
        return M.get_name(child, bufnr)
      end
      if ct == "type_identifier" or ct == "qualified_identifier" then
        return vim.treesitter.get_node_text(child, bufnr)
      end
    end
  end

  -- static_assert_declaration
  if node_type == "static_assert_declaration" then
    local condition = node:field("condition")[1]
    if condition then
      local text = vim.treesitter.get_node_text(condition, bufnr)
      if #text > 40 then text = text:sub(1, 37) .. "..." end
      return text
    end
    return "<static_assert>"
  end

  -- Struct/union field declarations
  if node_type == "field_declaration" then
    local declarator = node:field("declarator")[1]
    if declarator then
      return extract_declarator_name(declarator, bufnr)
    end
  end

  -- Enum enumerators
  if node_type == "enumerator" then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  -- Expression statement
  if node_type == "expression_statement" then
    local text = vim.treesitter.get_node_text(node, bufnr)
    local first_line = text:match("^([^\n]*)")
    if #first_line > 40 then
      first_line = first_line:sub(1, 37) .. "..."
    end
    return first_line
  end

  -- template_instantiation
  if node_type == "template_instantiation" then
    local declarator = node:field("declarator")[1]
    if declarator then
      return vim.treesitter.get_node_text(declarator, bufnr)
    end
  end

  return "[unknown]"
end

--- Check if an enum_specifier is a scoped enum (enum class / enum struct)
local function is_scoped_enum(node, bufnr)
  local text = vim.treesitter.get_node_text(node, bufnr)
  return text:match("^enum%s+class%s") ~= nil or text:match("^enum%s+struct%s") ~= nil
end

function M.get_display_type(node, bufnr)
  local node_type = node:type()

  if node_type == "function_definition" then
    -- Check if it's a constructor/destructor by looking at the declarator
    local declarator = node:field("declarator")[1]
    if declarator then
      local name = extract_declarator_name(declarator, bufnr) or ""
      if name:match("~") then return "destructor" end
      -- Constructor: qualified name where scope == name (e.g., Foo::Foo)
      local scope, method = name:match("^(.+)::([^:]+)$")
      if scope and method and scope:match("[%w_]+$") == method then
        return "constructor"
      end
    end
    return "function"
  end

  if node_type == "declaration" then
    local declarator = node:field("declarator")[1]
    if declarator then
      local dt = declarator:type()
      if dt == "function_declarator" then
        -- Check for constructor/destructor forward declaration
        local inner = declarator:field("declarator")[1]
        if inner then
          local name = extract_declarator_name(inner, bufnr) or ""
          if name:match("~") then return "destructor" end
        end
        return "function"
      end
      return "variable"
    end
    -- No declarator — bare type
    for child in node:iter_children() do
      local ct = child:type()
      if ct == "struct_specifier" then return "struct" end
      if ct == "enum_specifier" then
        if is_scoped_enum(child, bufnr) then return "enum class" end
        return "enum"
      end
      if ct == "union_specifier" then return "union" end
      if ct == "class_specifier" then return "class" end
    end
    return "variable"
  end

  if node_type == "type_definition" then return "typedef" end
  if node_type == "preproc_def" or node_type == "preproc_function_def" then return "#define" end
  if node_type == "struct_specifier" then return "struct" end
  if node_type == "union_specifier" then return "union" end
  if node_type == "class_specifier" then return "class" end
  if node_type == "namespace_definition" then return "namespace" end
  if node_type == "namespace_alias_definition" then return "namespace" end
  if node_type == "alias_declaration" then return "using" end
  if node_type == "concept_definition" then return "concept" end
  if node_type == "static_assert_declaration" then return "static_assert" end
  if node_type == "friend_declaration" then return "friend" end
  if node_type == "expression_statement" then return "expression" end
  if node_type == "template_instantiation" then return "template" end

  if node_type == "enum_specifier" then
    if is_scoped_enum(node, bufnr) then return "enum class" end
    return "enum"
  end

  if node_type == "field_declaration" then return "field" end
  if node_type == "enumerator" then return "enumerator" end

  -- template_declaration: determine type from inner child
  if node_type == "template_declaration" then
    for child in node:iter_children() do
      local ct = child:type()
      if ct == "concept_definition" then return "concept" end
      if ct ~= "template_parameter_list" then
        return "template"
      end
    end
    return "template"
  end

  -- export_declaration: recurse
  if node_type == "export_declaration" then
    for child in node:iter_children() do
      local ct = child:type()
      if ct ~= "export" then
        local dt = M.get_display_type(child, bufnr)
        if dt ~= child:type() then
          return "export"
        end
      end
    end
    return "export"
  end

  return node_type
end

function M.get_arity(node, bufnr)
  local node_type = node:type()

  if node_type == "function_definition" then
    local declarator = node:field("declarator")[1]
    if declarator then
      -- Navigate to the function_declarator
      local func_decl = declarator
      if func_decl:type() ~= "function_declarator" then
        -- Search children for function_declarator
        for child in declarator:iter_children() do
          if child:type() == "function_declarator" then
            func_decl = child
            break
          end
        end
      end
      if func_decl:type() == "function_declarator" then
        local params = func_decl:field("parameters")[1]
        if params then
          local count = 0
          for child in params:iter_children() do
            if child:type() == "parameter_declaration" or child:type() == "optional_parameter_declaration" then
              local text = vim.treesitter.get_node_text(child, bufnr)
              if not text:match("^%s*void%s*$") then
                count = count + 1
              end
            end
          end
          return count
        end
      end
    end
    return 0
  end

  -- Forward declaration arity
  if node_type == "declaration" then
    local declarator = node:field("declarator")[1]
    if declarator and declarator:type() == "function_declarator" then
      local params = declarator:field("parameters")[1]
      if params then
        local count = 0
        for child in params:iter_children() do
          if child:type() == "parameter_declaration" or child:type() == "optional_parameter_declaration" then
            local text = vim.treesitter.get_node_text(child, bufnr)
            if not text:match("^%s*void%s*$") then
              count = count + 1
            end
          end
        end
        return count
      end
    end
  end

  -- preproc_function_def
  if node_type == "preproc_function_def" then
    local params = node:field("parameters")[1]
    if params then
      local count = 0
      for child in params:iter_children() do
        if child:type() == "identifier" then
          count = count + 1
        end
      end
      return count
    end
    return 0
  end

  -- template_declaration: recurse
  if node_type == "template_declaration" then
    for child in node:iter_children() do
      if child:type() ~= "template_parameter_list" then
        return M.get_arity(child, bufnr)
      end
    end
  end

  return nil
end

-- Nesting support
function M.is_nestable(node)
  local t = node:type()
  if t == "class_specifier" or t == "struct_specifier" or t == "union_specifier" then
    return true
  end
  if t == "enum_specifier" then
    return true
  end
  if t == "namespace_definition" then
    return true
  end
  -- Handle bare declarations wrapping struct/enum/union/class
  if t == "declaration" then
    for child in node:iter_children() do
      local ct = child:type()
      if ct == "struct_specifier" or ct == "enum_specifier" or ct == "union_specifier" or ct == "class_specifier" then
        for sub in child:iter_children() do
          if sub:type() == "field_declaration_list" or sub:type() == "enumerator_list" then
            return true
          end
        end
      end
    end
  end
  -- Handle template_declaration wrapping a nestable type (e.g., template<T> class Box { ... })
  if t == "template_declaration" then
    for child in node:iter_children() do
      if M.is_nestable(child) then
        return true
      end
    end
  end
  return false
end

function M.get_body_node(node)
  local t = node:type()
  if t == "class_specifier" or t == "struct_specifier" or t == "union_specifier" then
    for child in node:iter_children() do
      if child:type() == "field_declaration_list" then
        return child
      end
    end
  end
  if t == "enum_specifier" then
    for child in node:iter_children() do
      if child:type() == "enumerator_list" then
        return child
      end
    end
  end
  if t == "namespace_definition" then
    for child in node:iter_children() do
      if child:type() == "declaration_list" then
        return child
      end
    end
  end
  -- Handle bare declarations wrapping struct/enum/union/class
  if t == "declaration" then
    for child in node:iter_children() do
      local ct = child:type()
      if ct == "struct_specifier" or ct == "union_specifier" or ct == "class_specifier" then
        for sub in child:iter_children() do
          if sub:type() == "field_declaration_list" then
            return sub
          end
        end
      end
      if ct == "enum_specifier" then
        for sub in child:iter_children() do
          if sub:type() == "enumerator_list" then
            return sub
          end
        end
      end
    end
  end
  -- Handle template_declaration wrapping a nestable type
  if t == "template_declaration" then
    for child in node:iter_children() do
      local body = M.get_body_node(child)
      if body then
        return body
      end
    end
  end
  return nil
end

local CHILD_TYPES = {
  -- Class/struct members
  function_definition = true,
  declaration = true,
  field_declaration = true,
  alias_declaration = true,
  friend_declaration = true,
  static_assert_declaration = true,
  template_declaration = true,
  type_definition = true,
  using_declaration = true,
  -- Enum members
  enumerator = true,
  -- Namespace children (full declarations)
  preproc_def = true,
  preproc_function_def = true,
  class_specifier = true,
  struct_specifier = true,
  enum_specifier = true,
  union_specifier = true,
  namespace_definition = true,
  concept_definition = true,
  expression_statement = true,
}

function M.is_child_declaration(node)
  local t = node:type()
  if t == "access_specifier" then return false end
  return CHILD_TYPES[t] or false
end

--- Extract access specifier label from an access_specifier node.
--- @param node any treesitter node
--- @param bufnr number buffer handle
--- @return string|nil "public", "protected", or "private"
function M.get_access_specifier(node, bufnr)
  if node:type() == "access_specifier" then
    local text = vim.treesitter.get_node_text(node, bufnr)
    -- The colon is a separate sibling node, so text is just "public"/"protected"/"private"
    local spec = text:match("^(%w+)")
    return spec
  end
  return nil
end

return M
