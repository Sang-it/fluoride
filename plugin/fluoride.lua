if vim.g.loaded_fluoride then
  return
end
vim.g.loaded_fluoride = true

vim.api.nvim_create_user_command("Fluoride", function()
  require("fluoride").run()
end, {
  nargs = 0,
  desc = "Open Fluoride window to view and reorder top-level declarations",
})
