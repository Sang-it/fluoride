local M = {}

local DEFAULT_CONFIG = {
  window = {
    title = "Fluoride",
    width = 0.3,
    height = 0.85,
    row = 2,
    col = 2,
    border = "single",
    winblend = 15,
    footer = true,
    center_breakpoint = 80,
  },
  keymaps = {
    close = "q",
    close_alt = "<C-c>",
    jump = "<CR>",
    peek = "gd",
    hover = "K",
  },
}

M.config = vim.deepcopy(DEFAULT_CONFIG)

--- Setup the plugin with user configuration.
--- @param user_config? table
function M.setup(user_config)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULT_CONFIG), user_config or {})
end

--- Open the Fluoride floating window for the current buffer.
function M.run()
  local source_bufnr = vim.api.nvim_get_current_buf()
  local treesitter = require("fluoride.treesitter")

  local entries, lang = treesitter.get_code_points(source_bufnr)

  if not lang then
    return
  end

  if #entries == 0 then
    vim.notify("Fluoride: no top-level declarations found", vim.log.levels.INFO)
    return
  end

  local window = require("fluoride.window")
  window.open(source_bufnr, entries, lang, M.config)
end

return M
