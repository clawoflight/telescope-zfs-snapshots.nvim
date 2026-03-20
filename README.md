<!--
SPDX-FileCopyrightText: 2026 Bennett Piater
SPDX-License-Identifier: MIT
-->

# telescope-zfs-snapshots.nvim

Browse the ZFS snapshot history of any file using [zsd](https://github.com/j-keck/zsd) and [Telescope](https://github.com/nvim-telescope/telescope.nvim).

Each snapshot is listed in the picker; the preview pane shows a live diff against the current version.

## Requirements

- Neovim ≥ 0.9
- [nvim-telescope/telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [`zsd`](https://github.com/j-keck/zsd) on your `$PATH` (If you're on Arch Linux, I package it in the AUR)
- Files must live on a ZFS dataset with snapshots

## Installation

**lazy.nvim**
```lua
{
  "clawoflight/telescope-zfs-snapshots.nvim",
  dependencies = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("telescope").load_extension("zsd")
  end,
}
```

**packer.nvim**
```lua
use {
  "clawoflight/telescope-zfs-snapshots.nvim",
  requires = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("telescope").load_extension("zsd")
  end,
}
```

## Usage

Open the picker for the current buffer:
```vim
:ZfsSnapshots
```

Or from Lua / as a Telescope command:
```lua
require("telescope").extensions.zsd.snapshots()
```
```vim
:Telescope zsd snapshots
```

Pass an explicit path:
```vim
:ZfsSnapshots /path/to/file
```

## Keymaps

| Key     | Action                                              |
|---------|-----------------------------------------------------|
| `<CR>`  | Open snapshot in a read-only vertical split         |
| `<M-d>` | Open `vimdiff` between the snapshot and current file |
| `<C-c>` | Close picker                                        |
| `<Esc>` | Close picker (normal mode)                          |

Standard Telescope scroll keymaps (`<C-u>`, `<C-d>`, `<C-f>`, `<C-b>`) work in the preview.

## How it works

1. `zsd <file> list` — enumerates snapshots where the file differs
2. Preview: `zsd <file> diff <snapshot>` — unified diff rendered with `filetype=diff`
3. `<CR>`: `zsd <file> cat <snapshot>` — loads snapshot content into a scratch buffer
4. `MM-d>`: same as above, but opens both buffers in `diffthis` mode
