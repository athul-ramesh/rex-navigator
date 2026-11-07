# rex-navigator

Keyboard-driven **new Rex session from zoxide history**. A shortcut opens a floating fzf picker over directories you have visited; Enter creates a session at that path and switches this Rex app client to it.

## Dependencies

- [Rex](https://rex.dev) server running
- `fzf` (`brew install fzf`)
- `zoxide` with some history (`brew install zoxide`)
- Python 3 (stdlib only in the helper)

## Install

```bash
mkdir -p ~/.config/rex
cp lua/rex_sesh.lua ~/.config/rex/
cp bin/rex-sesh-picker ~/.config/rex/
chmod +x ~/.config/rex/rex-sesh-picker
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

Reload Rex config after editing (`rex config reload` or restart the app).

## Usage

Focus a terminal pane, press **⌘⇧J** (or run **New Session from Zoxide…** from the command palette). Esc cancels without creating a session.

## Remote Control

Switching the Rex app UI uses `client.perform` `session.select`. If Rex refuses with a **Remote Control** message, the session may already exist. Enable **Settings → Rex Server → Remote Control**, or open the new session from the sidebar. The picker prints the `session_id` when switch fails after create.

## Development

```bash
python3 -m py_compile bin/rex-sesh-picker
rex do /path/to/rex-navigator/lua/rex_sesh.lua --action rex_sesh
```

The `rex_sesh` action must run from a live pane (not bare CLI without session context).
