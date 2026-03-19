local M = {}

M.filetypes = { "c" }

M.parsers = {
  c = "c",
}

M.comment_types = { comment = true }
M.comment_prefix = "//"

local SKIP_TYPES = {
  comment = true,
  preproc_include = true,
  preproc_call = true,
  preproc_pragma = true,
  preproc_else = true,
  preproc_endif = true,
  empty_declaration = true,
  empty_statement = true,
  [";"] = true,
}

M.highlights = {
  ["function"]  = { prefix = "Keyword",  name = "Function" },
  ["struct"]    = { prefix = "Type",     name = "Type" },
  ["enum"]      = { prefix = "Type",     name = "Type" },
  ["union"]     = { prefix = "Type",     name = "Type" },
  ["typedef"]        = { prefix = "Type",     name = "Type" },
  ["typedef struct"] = { prefix = "Type",     name = "Type" },
  ["typedef enum"]   = { prefix = "Type",     name = "Type" },
  ["typedef union"]  = { prefix = "Type",     name = "Type" },
  ["variable"]  = { prefix = "Keyword",  name = "Identifier" },
  ["#define"]   = { prefix = "PreProc",  name = "Identifier" },
  ["expression"] = { prefix = "Keyword",  name = "Identifier" },
  -- Preprocessor conditionals
  ["#ifndef"]    = { prefix = "PreProc",  name = "Identifier" },
  ["#ifdef"]     = { prefix = "PreProc",  name = "Identifier" },
  ["#if"]        = { prefix = "PreProc",  name = "Identifier" },
  -- Struct/union/enum children
  ["field"]      = { prefix = "Keyword",  name = "Identifier" },
  ["enumerator"] = { prefix = "Type",     name = "Identifier" },
}

function M.is_declaration(node)
  return not SKIP_TYPES[node:type()]
end

function M.get_name(node, bufnr)
  local node_type = node:type()

  -- function_definition: int foo(int x) { ... }
  if node_type == "function_definition" then
    local declarator = node:field("declarator")[1]
    if declarator then
      -- The declarator is a function_declarator containing the name
      if declarator:type() == "function_declarator" then
        local name_decl = declarator:field("declarator")[1]
        if name_decl then
          return vim.treesitter.get_node_text(name_decl, bufnr)
        end
      -- Pointer declarator: int *foo() { ... }
      elseif declarator:type() == "pointer_declarator" then
        for child in declarator:iter_children() do
          if child:type() == "function_declarator" then
            local name_decl = child:field("declarator")[1]
            if name_decl then
              return vim.treesitter.get_node_text(name_decl, bufnr)
            end
          end
        end
      end
      return vim.treesitter.get_node_text(declarator, bufnr):match("^([%w_]+)")
    end
  end

  -- declaration: int x = 5; or void foo(void); or enum Foo { ... };
  if node_type == "declaration" then
    local declarator = node:field("declarator")[1]
    if declarator then
      -- Could be init_declarator, function_declarator, etc.
      if declarator:type() == "init_declarator" then
        local inner = declarator:field("declarator")[1]
        if inner then
          return vim.treesitter.get_node_text(inner, bufnr):match("^[%*]*([%w_]+)")
        end
      elseif declarator:type() == "function_declarator" then
        local inner = declarator:field("declarator")[1]
        if inner then
          return vim.treesitter.get_node_text(inner, bufnr)
        end
      end
      local text = vim.treesitter.get_node_text(declarator, bufnr)
      return text:match("^[%*]*([%w_]+)") or text
    end

    -- No declarator — bare type declaration (e.g., enum SortOrder { ... };)
    -- Look at the type field for struct/enum/union specifiers
    for child in node:iter_children() do
      local ct = child:type()
      if ct == "struct_specifier" or ct == "enum_specifier" or ct == "union_specifier" then
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
      return vim.treesitter.get_node_text(declarator, bufnr)
    end
  end

  -- preproc_def: #define FOO ...
  if node_type == "preproc_def" then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  -- preproc_function_def: #define FOO(x) ...
  if node_type == "preproc_function_def" then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  -- struct/enum/union specifier at top level
  if node_type == "struct_specifier" or node_type == "enum_specifier" or node_type == "union_specifier" then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  -- Struct/union field declarations (inside struct body)
  if node_type == "field_declaration" then
    local declarator = node:field("declarator")[1]
    if declarator then
      return vim.treesitter.get_node_text(declarator, bufnr):match("^[%*]*([%w_]+)") or vim.treesitter.get_node_text(declarator, bufnr)
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

  -- Enum enumerators
  if node_type == "enumerator" then
    local name_node = node:field("name")[1]
    if name_node then
      return vim.treesitter.get_node_text(name_node, bufnr)
    end
  end

  -- Preprocessor conditionals: #ifdef/#ifndef use the identifier, #if uses the condition text
  if node_type == "preproc_ifdef" then
    for child in node:iter_children() do
      if child:type() == "identifier" then
        return vim.treesitter.get_node_text(child, bufnr)
      end
    end
    return "<guard>"
  end
  if node_type == "preproc_if" then
    -- The condition is the first non-keyword child
    for child in node:iter_children() do
      local ct = child:type()
      if ct ~= "#if" then
        local text = vim.treesitter.get_node_text(child, bufnr)
        if #text > 40 then text = text:sub(1, 37) .. "..." end
        return text
      end
    end
    return "<condition>"
  end

  return "[unknown]"
end

function M.get_display_type(node, bufnr)
  local node_type = node:type()

  if node_type == "function_definition" then
    return "function"
  end

  if node_type == "declaration" then
    -- Check if it's a function forward declaration or variable
    local declarator = node:field("declarator")[1]
    if declarator then
      if declarator:type() == "function_declarator" then
        return "function"
      end
      return "variable"
    end

    -- No declarator — bare type declaration (e.g., enum SortOrder { ... };)
    for child in node:iter_children() do
      local ct = child:type()
      if ct == "struct_specifier" then return "struct" end
      if ct == "enum_specifier" then return "enum" end
      if ct == "union_specifier" then return "union" end
    end
    return "variable"
  end

  if node_type == "type_definition" then
    -- Check if typedef wraps a struct/enum/union (e.g., "typedef struct { ... } Name;")
    for child in node:iter_children() do
      local ct = child:type()
      if ct == "struct_specifier" then return "typedef struct" end
      if ct == "enum_specifier" then return "typedef enum" end
      if ct == "union_specifier" then return "typedef union" end
    end
    return "typedef"
  end

  if node_type == "preproc_def" or node_type == "preproc_function_def" then
    return "#define"
  end

  if node_type == "struct_specifier" then return "struct" end
  if node_type == "enum_specifier" then return "enum" end
  if node_type == "union_specifier" then return "union" end
  if node_type == "field_declaration" then return "field" end
  if node_type == "enumerator" then return "enumerator" end
  if node_type == "expression_statement" then return "expression" end

  -- Preprocessor conditionals
  if node_type == "preproc_ifdef" then
    -- Distinguish #ifndef from #ifdef by the first child token
    for child in node:iter_children() do
      if child:type() == "#ifndef" then return "#ifndef" end
      if child:type() == "#ifdef" then return "#ifdef" end
    end
    return "#ifdef"
  end
  if node_type == "preproc_if" then return "#if" end

  return node_type
end

function M.get_arity(node, _bufnr)
  local node_type = node:type()

  if node_type == "function_definition" then
    local declarator = node:field("declarator")[1]
    if declarator and declarator:type() == "function_declarator" then
      local params = declarator:field("parameters")[1]
      if params then
        local count = 0
        for child in params:iter_children() do
          local ct = child:type()
          if ct == "parameter_declaration" then
            count = count + 1
          end
        end
        -- Check for void parameter: int foo(void) should be arity 0
        if count == 1 then
          for child in params:iter_children() do
            if child:type() == "parameter_declaration" then
              local text = vim.treesitter.get_node_text(child, _bufnr)
              if text:match("^%s*void%s*$") then
                return 0
              end
            end
          end
        end
        return count
      end
    end
    return 0
  end

  -- Forward declaration: void foo(int x, int y);
  if node_type == "declaration" then
    local declarator = node:field("declarator")[1]
    if declarator and declarator:type() == "function_declarator" then
      local params = declarator:field("parameters")[1]
      if params then
        local count = 0
        for child in params:iter_children() do
          if child:type() == "parameter_declaration" then
            count = count + 1
          end
        end
        if count == 1 then
          for child in params:iter_children() do
            if child:type() == "parameter_declaration" then
              local text = vim.treesitter.get_node_text(child, _bufnr)
              if text:match("^%s*void%s*$") then
                return 0
              end
            end
          end
        end
        return count
      end
    end
  end

  -- preproc_function_def: #define FOO(x, y) — has arity
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

  return nil
end

-- Nesting support for C structs, enums, and unions
function M.is_nestable(node)
  local t = node:type()
  if t == "struct_specifier" or t == "union_specifier" then
    return true
  end
  if t == "enum_specifier" then
    return true
  end
  -- Handle bare declarations or typedefs wrapping struct/enum/union (e.g., "enum Foo { ... };", "typedef struct { ... } Name;")
  if t == "declaration" or t == "type_definition" then
    for child in node:iter_children() do
      local ct = child:type()
      if ct == "struct_specifier" or ct == "enum_specifier" or ct == "union_specifier" then
        -- Check if it has a body (not just a forward declaration)
        for sub in child:iter_children() do
          if sub:type() == "field_declaration_list" or sub:type() == "enumerator_list" then
            return true
          end
        end
      end
    end
  end
  -- Preprocessor conditionals are always nestable (they contain declarations)
  if t == "preproc_ifdef" or t == "preproc_if" then
    return true
  end
  return false
end

function M.get_body_node(node)
  local t = node:type()
  -- Preprocessor conditionals: the node itself is the body (children are mixed with tokens)
  if t == "preproc_ifdef" or t == "preproc_if" then
    return node
  end
  if t == "struct_specifier" or t == "union_specifier" then
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
  -- Handle bare declarations or typedefs wrapping struct/enum/union
  if t == "declaration" or t == "type_definition" then
    for child in node:iter_children() do
      local ct = child:type()
      if ct == "struct_specifier" or ct == "union_specifier" then
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
  return nil
end

local C_CHILD_TYPES = {
  function_definition = true,
  declaration = true,
  field_declaration = true,
  enumerator = true,
  type_definition = true,
  preproc_def = true,
  preproc_function_def = true,
  preproc_ifdef = true,
  preproc_if = true,
  struct_specifier = true,
  enum_specifier = true,
  union_specifier = true,
  expression_statement = true,
}

function M.is_child_declaration(node)
  local t = node:type()
  -- Skip access specifiers (public:, private:, protected:)
  if t == "access_specifier" then return false end
  return C_CHILD_TYPES[t] or false
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

--- Get the guard identifier for a #ifndef include guard, so the matching
--- #define can be filtered from children.
--- @param node any treesitter node (preproc_ifdef)
--- @param bufnr number buffer handle
--- @return string|nil guard_name the identifier if this is a #ifndef, nil otherwise
function M.get_preproc_guard_name(node, bufnr)
  if node:type() ~= "preproc_ifdef" then return nil end
  local is_ifndef = false
  for child in node:iter_children() do
    if child:type() == "#ifndef" then
      is_ifndef = true
    elseif child:type() == "identifier" and is_ifndef then
      return vim.treesitter.get_node_text(child, bufnr)
    end
  end
  return nil
end

return M
