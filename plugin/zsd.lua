-- plugin/zsd.lua
-- Entrypoint: loaded automatically by Neovim's runtime.
-- Registers :ZfsSnapshots command and loads the telescope extension.

if vim.g.loaded_zsd_telescope then
  return
end
vim.g.loaded_zsd_telescope = true

-- Lazy-load the extension only when telescope is available at call time.
local function load_ext()
  local ok, telescope = pcall(require, "telescope")
  if not ok then
    vim.notify("[zsd] telescope.nvim is required", vim.log.levels.ERROR)
    return false
  end
  telescope.load_extension("zsd")
  return true
end

-- :ZfsSnapshots [file]  — open the picker for an optional explicit file path
vim.api.nvim_create_user_command("ZfsSnapshots", function(cmd_opts)
  if not load_ext() then return end
  local opts = {}
  if cmd_opts.args and cmd_opts.args ~= "" then
    opts.file = cmd_opts.args
  end
  require("telescope").extensions.zsd.snapshots(opts)
end, {
  nargs = "?",
  complete = "file",
  desc = "Browse ZFS snapshots for the current (or given) file via zsd + Telescope",
})
