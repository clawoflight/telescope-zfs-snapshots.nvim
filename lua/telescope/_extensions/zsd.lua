-- SPDX-FileCopyrightText: 2026 Bennett Piater
-- SPDX-License-Identifier: MIT
--
-- telescope/_extensions/zsd.lua
-- Telescope extension for browsing ZFS snapshots via zsd

local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  error("zsd-telescope requires nvim-telescope/telescope.nvim")
end

local actions       = require("telescope.actions")
local action_state  = require("telescope.actions.state")
local finders       = require("telescope.finders")
local pickers       = require("telescope.pickers")
local previewers    = require("telescope.previewers")
local conf          = require("telescope.config").values
local utils         = require("telescope.utils")

local M = {}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Run a shell command synchronously, return stdout lines or nil+err.
local function run(cmd)
  local handle = io.popen(cmd .. " 2>&1")
  if not handle then
    return nil, "failed to open pipe for: " .. cmd
  end
  local output = handle:read("*a")
  local ok = handle:close()
  if not ok then
    return nil, output
  end
  return output, nil
end

--- Split a string by a separator character, return a list of lines.
local function lines(s)
  local result = {}
  for line in (s .. "\n"):gmatch("([^\n]*)\n") do
    if line ~= "" then
      table.insert(result, line)
    end
  end
  return result
end

--- Return the absolute path of the file in the current buffer, or nil.
local function current_file()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    return nil, "current buffer has no file"
  end
  -- Resolve to absolute path
  path = vim.fn.fnamemodify(path, ":p")
  if vim.fn.filereadable(path) == 0 then
    return nil, "file not readable: " .. path
  end
  return path, nil
end

--- Ask zsd for the list of snapshots that contain a different version of `file`.
--- Returns a list of entry tables: { index, snapshot, age, changed, file }
--- zsd list output is a pipe-delimited table:
---   # | File changed | Snapshot                            | Snapshot age
---   0 |   25 minutes | autosnap_2026-03-19_17:00:02_hourly |   25 minutes
local function get_snapshots(file)
  -- -d 30: scan the last 30 days of snapshots
  local raw, err = run(string.format("zsd -d 30 '%s' list", file))
  if not raw then
    return nil, err
  end

  local entries = {}
  for _, line in ipairs(lines(raw)) do
    -- Match lines like: "  0 |   25 minutes | autosnap_... |   25 minutes"
    local idx, changed, snap, age = line:match(
      "^%s*(%d+)%s*|%s*(.-)%s*|%s*(%S+)%s*|%s*(.-)%s*$"
    )
    if idx and snap then
      table.insert(entries, {
        index    = tonumber(idx),
        snapshot = snap,
        age      = age or "",
        changed  = changed or "",
        display  = string.format("%-4s %-16s  %s", idx, changed, snap),
        file     = file,
      })
    end
  end

  if #entries == 0 then
    return nil, "zsd found no snapshots for: " .. file
  end

  return entries, nil
end

-- ---------------------------------------------------------------------------
-- Custom previewer: runs `zsd diff <N>` and shows it with diff highlighting
-- ---------------------------------------------------------------------------

local diff_previewer = previewers.new_buffer_previewer({
  title = "ZSD Diff",

  define_preview = function(self, entry)
    local bufnr = self.state.bufnr
    local file  = entry.file
    local snap  = entry.snapshot

    local idx = entry.value and entry.value.index or entry.index or 0
    local cmd = string.format("zsd -d 30 '%s' diff %d 2>&1", file, idx)
    local raw, err = run(cmd)

    if not raw or raw == "" then
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "Error running zsd diff:",
        err or "(no output)",
      })
      return
    end

    -- Write diff output into the preview buffer
    local diff_lines = lines(raw)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, diff_lines)

    -- Apply diff syntax highlighting
    vim.api.nvim_buf_call(bufnr, function()
      vim.cmd("set filetype=diff")
    end)
  end,
})

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

--- Open the snapshot version of the file in a new vertical split.
local function open_snapshot_version(prompt_bufnr)
  local entry = action_state.get_selected_entry()
  actions.close(prompt_bufnr)

  if not entry then return end

  -- zsd cat prints the file content from the snapshot to stdout.
  -- We create a scratch buffer and fill it with that content.
  local cmd = string.format("zsd -d 30 '%s' cat %d 2>&1", entry.file, entry.index)
  local raw, err = run(cmd)

  if not raw then
    vim.notify("[zsd] cat failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
    return
  end

  local content = lines(raw)
  local ext = vim.fn.fnamemodify(entry.file, ":e")
  local snap_short = entry.snapshot:match("@(.+)$") or entry.snapshot

  -- Open vertical split with a descriptive buffer name
  vim.cmd("vsplit")
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true) -- unlisted scratch buffer
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
  vim.api.nvim_buf_set_name(buf, string.format("zsd://%s/%s", snap_short, vim.fn.fnamemodify(entry.file, ":t")))

  -- Set filetype for syntax highlighting
  if ext ~= "" then
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("set filetype=" .. ext)
    end)
  end

  -- Mark buffer as read-only / unmodifiable
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly   = true
  vim.bo[buf].buftype    = "nofile"
  vim.bo[buf].swapfile   = false

  vim.notify(string.format("[zsd] opened %s @ %s", vim.fn.fnamemodify(entry.file, ":t"), snap_short))
end

--- Open a vimdiff between the current file and the snapshot version.
local function open_diff(prompt_bufnr)
  local entry = action_state.get_selected_entry()
  actions.close(prompt_bufnr)

  if not entry then return end

  local cmd = string.format("zsd -d 30 '%s' cat %d 2>&1", entry.file, entry.index)
  local raw, err = run(cmd)

  if not raw then
    vim.notify("[zsd] cat failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
    return
  end

  local content     = lines(raw)
  local ext         = vim.fn.fnamemodify(entry.file, ":e")
  local snap_short  = entry.snapshot:match("@(.+)$") or entry.snapshot
  local buf_name    = string.format("zsd://%s/%s", snap_short, vim.fn.fnamemodify(entry.file, ":t"))

  -- Make sure the current file is shown in a normal window first
  vim.cmd("edit " .. vim.fn.fnameescape(entry.file))
  vim.cmd("diffthis")

  -- Open the snapshot in a vertical split
  vim.cmd("vsplit")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)

  pcall(vim.api.nvim_buf_set_name, buf, buf_name)

  if ext ~= "" then
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("set filetype=" .. ext)
    end)
  end

  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly   = true
  vim.bo[buf].buftype    = "nofile"
  vim.bo[buf].swapfile   = false

  vim.cmd("diffthis")

  vim.notify(string.format("[zsd] diffing %s against %s", vim.fn.fnamemodify(entry.file, ":t"), snap_short))
end

--- Restore the file from a snapshot, with confirmation.
local function restore_snapshot(prompt_bufnr)
  local entry = action_state.get_selected_entry()
  if not entry then return end

  local snap_short = entry.snapshot:match("@(.+)$") or entry.snapshot
  local fname      = vim.fn.fnamemodify(entry.file, ":~:.")

  vim.ui.select(
    { "Yes, restore it", "Cancel" },
    {
      prompt = string.format(
        "Restore %s from '%s'? This OVERWRITES the current file.",
        fname, snap_short
      ),
      kind = "confirmation",
    },
    function(choice)
      if choice ~= "Yes, restore it" then
        vim.notify("[zsd] restore cancelled", vim.log.levels.INFO)
        return
      end

      actions.close(prompt_bufnr)

      local cmd = string.format("zsd -d 30 '%s' restore %d 2>&1", entry.file, entry.index)
      local out, err = run(cmd)

      if not out then
        vim.notify("[zsd] restore failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
        return
      end

      -- Reload the buffer so Neovim reflects the restored file
      vim.schedule(function()
        local bufnr = vim.fn.bufnr(entry.file)
        if bufnr ~= -1 then
          vim.api.nvim_buf_call(bufnr, function()
            vim.cmd("edit!")
          end)
        end
        vim.notify(
          string.format("[zsd] restored %s from %s", fname, snap_short),
          vim.log.levels.INFO
        )
      end)
    end
  )
end

-- ---------------------------------------------------------------------------
-- Main picker
-- ---------------------------------------------------------------------------

function M.snapshots(opts)
  opts = opts or {}

  -- Allow passing an explicit file path, otherwise use the current buffer.
  local file = opts.file
  if not file then
    local err
    file, err = current_file()
    if not file then
      vim.notify("[zsd] " .. err, vim.log.levels.ERROR)
      return
    end
  end

  local entries, err = get_snapshots(file)
  if not entries then
    vim.notify("[zsd] " .. err, vim.log.levels.WARN)
    return
  end

  pickers.new(opts, {
    prompt_title  = "ZFS Snapshots  " .. vim.fn.fnamemodify(file, ":~:."),
    results_title = string.format("%d snapshots found", #entries),
    preview_title = "Diff vs current",

    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        return {
          value    = entry,
          display  = entry.display,
          ordinal  = entry.snapshot,
          file     = entry.file,
          snapshot = entry.snapshot,
          index    = entry.index,
          age      = entry.age,
          changed  = entry.changed,
        }
      end,
    }),

    sorter = conf.generic_sorter(opts),

    previewer = diff_previewer,

    attach_mappings = function(_, map)
      -- <CR>  → open snapshot in a read-only vertical split
      actions.select_default:replace(open_snapshot_version)

      -- <C-d> → vimdiff snapshot against current file
      map("i", "<M-d>", open_diff)
      map("n", "<M-d>", open_diff)

      -- <C-r> → restore file from snapshot (with confirmation)
      map("i", "<C-r>", restore_snapshot)
      map("n", "<C-r>", restore_snapshot)

      return true
    end,
  }):find()
end

-- ---------------------------------------------------------------------------
-- Extension registration
-- ---------------------------------------------------------------------------

return telescope.register_extension({
  exports = {
    snapshots = M.snapshots,
    -- Allow :Telescope zsd  (defaults to snapshots picker)
    zsd = M.snapshots,
  },
})
