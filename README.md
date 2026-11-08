# rex-navigator

Keyboard-driven Rex session picker from zoxide history. A shortcut opens a floating fzf list. Open sessions appear near the prompt as labels only; Enter switches to that session. Directory rows still create a session at that path and switch this Rex app client to it.

## Dependencies

- [Rex](https://rex.dev) server running
- `fzf` (`brew install fzf`)
- `zoxide` with some history (`brew install zoxide`)
- Python 3 (stdlib only in the helper)

## Install

```bash
mkdir -p ~/.config/rex
ln -sf "$(pwd)/lua/rex_sesh.lua" ~/.config/rex/rex_sesh.lua
ln -sf "$(pwd)/bin/rex-sesh-picker" ~/.config/rex/rex-sesh-picker
chmod +x bin/rex-sesh-picker
```

Optional helper path override:

```bash
export REX_SESH_PICKER=/path/to/rex-sesh-picker
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

Focus a terminal pane and press ⌘⇧J, or run **New Session from Zoxide…** from the command palette. Enter on an open session switches to it. Enter on a directory creates a session there. Esc cancels.

You can also run the installed action from a session:

```bash
rex -C "Mac mini" do -s "$REX_SESSION" rex_sesh
```

## Remote Control

The helper switches the app with `client.perform` `session.select`. If Rex refuses because Remote Control is off, the session may already exist. Enable **Settings → Rex Server → Remote Control**, or open the new session from the sidebar. The picker prints the `session_id` when switch fails after create.

## Development

```bash
python3 -m py_compile bin/rex-sesh-picker
python3 bin/rex-sesh-picker --help
```

Do not load `lua/rex_sesh.lua` with `rex do … --action`. That path tries to encode the module table as JSON. Use `require("rex_sesh")` in `init.lua`, then `rex do rex_sesh` from a live session.
