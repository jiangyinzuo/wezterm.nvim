# wezterm.nvim

Utilities for interacting with the wezterm cli through Lua/neovim. Spawn tasks and switch tabs/panes, all from within Neovim.

## Demo

[Wezterm.nvim.webm](https://user-images.githubusercontent.com/38540736/232179762-0ac68014-f0dc-421c-a19f-b202da4ff663.webm)

## Installation

> Note: Requires Neovim >= 0.10

With `folke/lazy.nvim`

```lua
{
    'willothy/wezterm.nvim',
    config = true
}
```

If you don't want the user commands, use

```lua
{
    'willothy/wezterm.nvim',
    opts = {
        create_commands = false
    }
}
```

## Usage

For API documentation, see `:h wezterm.nvim` or [`doc/wezterm.nvim.txt`](./doc/wezterm.nvim.txt).

### Functions

For keybindings, functions that take a numeric value (index, id, relno, etc.) will check vim.v.count if they aren't passed an index.

For example:

```lua
-- Switch tab by index using vim.v.count
vim.keymap.set("n", "<leader>wt", require('wezterm').switch_tab.index)
```

### User command

Use `:WeztermSpawn <command> <args>...` to spawn a task in a new WezTerm tab.
Use `:WeztermSpawn` without arguments to open a new tab with WezTerm's default
program (usually a shell).

Use `:WeztermGetText` to select a pane and open its text in a new Neovim tab.
If Telescope is available, it provides the pane picker; otherwise the command
uses `vim.ui.select`. Cancelling the picker leaves your buffers unchanged.

You can specify the pane directly and include scrollback with a negative
`start_line`:

```vim
:WeztermGetText pane_id=3
:WeztermGetText pane_id=3 start_line=-200
:WeztermGetText start_line=-200
```

Both options are optional. Without `pane_id`, the command always opens the pane
picker. Without `start_line`, it captures the terminal screen without scrollback.

### Colored scrollback snapshots

Use `:WeztermSnapshot` to select a pane and browse a colored snapshot of its
screen and all retained scrollback in a new Neovim tab:

```vim
:WeztermSnapshot
:WeztermSnapshot pane_id=3
:WeztermSnapshot pane_id=3 start_line=-200
:WeztermSnapshot pane_id=3 start_line=0
```

The command uses `wezterm cli get-text --escapes` and decodes ANSI colors and
styles into highlights in a read-only text buffer. Line numbers are enabled and
browsing starts in Normal mode at the latest output:

| Keys | Action |
| --- | --- |
| `123G` or `:123` | Jump to snapshot line 123 |
| `/pattern` | Search |
| `ma`, `'a`, `:marks` | Add, jump to, and list Vim marks |
| `gg`, `G`, `Ctrl-U`, `Ctrl-D` | Navigate the snapshot |
| `zh`, `zl`, `zH`, `zL` | Scroll horizontally along long lines |
| `q` | Close and discard the snapshot |

Snapshots are static: new output is not followed, and marks belong to the
snapshot buffer. Long lines stay intact with `nowrap`, including after window
resizes; scroll horizontally to browse them. Existing line breaks in WezTerm's
export are preserved. There is no terminal scrollback limit on the snapshot.
RGB and 256-color sequences are supported, along with bold, italic, underline,
reverse and strikethrough styles. Indexed ANSI colors 0–15 use Neovim's
`terminal_color_0` through `terminal_color_15` palette, which can be configured
to match WezTerm. Requires a WezTerm version supporting `get-text --escapes`.

## Tests

Run from the repository root (Neovim >= 0.10):

```sh
nvim --headless -u NONE -l tests/commands.lua
nvim --headless -u NONE -l tests/ansi.lua
nvim --headless -u NONE -l tests/snapshot.lua
```

The tests mock the WezTerm process and Telescope modules, so they do not require
a running WezTerm instance or an installed Telescope. Snapshot tests use the
ANSI decoder and an attached RGB UI to check the resulting colors.
