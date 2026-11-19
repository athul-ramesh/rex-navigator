# rex-navigator

Keyboard-driven Rex session picker from zoxide history. A shortcut or the command palette opens the Rex custom UI list (`rex.ui.pick`). Open sessions appear as terminal rows; choose one to switch. Directory rows create a session at that path and switch this Rex app client to it.

## Dependencies

- [Rex](https://rex.dev) server running (custom UI needs control API revision 17+)
- `zoxide` with some history (`brew install zoxide`)
- `realpath` and `shasum` (standard on macOS)

## Install

```bash
mkdir -p ~/.config/rex
ln -sf "$(pwd)/lua/rex_sesh.lua" ~/.config/rex/rex_sesh.lua
```

Add to `~/.config/rex/init.lua` if not already loaded:

```lua
require("rex_sesh")
rex.bind("cmd+shift+j", "rex_sesh")
```

Then reload:

```bash
rex config reload
```

## Usage

Focus a terminal pane and press ⌘⇧J, or run **New Session from Zoxide…** from the command palette. Pick an open session to switch, or a directory to start a new session there. Cancel dismisses the palette.

Visit history keeps one back-edge (`~/.config/rex/rex-sesh-visit-edge.json`). When you open the picker from a session you arrived at via a switch, the prior session is listed first.

You can skip the picker when testing:

```bash
rex do -s "$REX_SESSION" rex_sesh --args '{"choice":"o:SESSION_ID"}'
rex do -s "$REX_SESSION" rex_sesh --args '{"choice":"d:/absolute/path"}'
```

## Development

Pure helpers are on `require("rex_sesh")` (`build_board`, `board_to_pick_items`, `decision_from_id`, `session_label_for`, `self_check`).

```bash
rex config reload
rex do -e 'local M=loadfile(os.getenv("HOME").."/.config/rex/rex_sesh.lua")(); return M.self_check()'
rex do -e 'local M=loadfile(os.getenv("HOME").."/.config/rex/rex_sesh.lua")(); local b=M.build_board(nil); return {open=#b.open_sessions, launches=#b.launches}' --json
```

Do not load `lua/rex_sesh.lua` with `rex do … --action`. That path tries to encode the module table as JSON. Use `require("rex_sesh")` in `init.lua`, then `rex do rex_sesh` from a live session.

Custom UI reference: https://www.superlogical.com/rex/docs/customize/custom-ui