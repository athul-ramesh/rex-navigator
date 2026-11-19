-- rex_sesh: switch open Rex sessions or create one from a zoxide directory.
--
-- Install: symlink this file into ~/.config/rex and require("rex_sesh") from
-- init.lua, then bind a key or use the command palette.

local M = {}

local has_ui, ui = pcall(function()
  return rex.ui
end)
if not has_ui or ui == nil then
  return M
end

local home = (os and os.getenv and os.getenv("HOME")) or ""

-- The Rex server process PATH is often just /usr/bin:/bin:/usr/sbin:/sbin.
-- Homebrew tools such as zoxide live outside that list, so resolve them
-- against common prefixes the same way the old helper did.
local PATH_FALLBACK_PREFIXES = {
  "/opt/homebrew/bin",
  "/usr/local/bin",
  "/usr/bin",
  "/bin",
}

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function slashes(path)
  return (path:gsub("\\", "/"))
end

local function pretty(path)
  local h = slashes(home)
  path = slashes(path)
  if h ~= "" and (path == h or path:sub(1, #h + 1) == h .. "/") then
    return "~" .. path:sub(#h + 1)
  end
  return path
end

local function basename(path)
  return (path:gsub("/+$", ""):match("([^/]+)$")) or path
end

local function path_executable(p)
  local f = io and io.open and io.open(p, "rb")
  if f then
    f:close()
    return p
  end
  return nil
end

local function find_bin(name)
  local seen = {}
  local function try(prefix)
    if seen[prefix] then
      return nil
    end
    seen[prefix] = true
    return path_executable(prefix .. "/" .. name)
  end
  for prefix in string.gmatch(os.getenv("PATH") or "", "[^:]+") do
    local hit = try(prefix)
    if hit then
      return hit
    end
  end
  for _, prefix in ipairs(PATH_FALLBACK_PREFIXES) do
    local hit = try(prefix)
    if hit then
      return hit
    end
  end
  return nil
end

local function shell_quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function sha256_hex6(text)
  local r = rex.exec({
    "bash",
    "-c",
    "printf %s " .. shell_quote(text) .. " | shasum -a 256",
  })
  if r == nil or not r.ok then
    return "000000"
  end
  local hex = trim(r.stdout):match("^(%x+)")
  if hex == nil or #hex < 6 then
    return "000000"
  end
  return hex:sub(1, 6)
end

local function is_dir(path)
  local r = rex.exec({ "test", "-d", path })
  return r ~= nil and r.ok
end

local function realpath_dir(raw)
  if not is_dir(raw) then
    return nil
  end
  local r = rex.exec({ "realpath", raw })
  if r == nil or not r.ok then
    return nil
  end
  local canon = trim(r.stdout)
  if canon == "" or not is_dir(canon) then
    return nil
  end
  return slashes(canon)
end

local VISIT_PATH = slashes(home) .. "/.config/rex/rex-sesh-visit-edge.json"

local function visit_path()
  return VISIT_PATH
end

local function load_visit_edge()
  if io == nil or io.open == nil then
    return nil
  end
  local file = io.open(visit_path(), "r")
  if file == nil then
    return nil
  end
  local text = file:read("*a")
  file:close()
  local ok, data = pcall(rex.json.decode, text)
  if not ok or type(data) ~= "table" or data.v ~= 1 then
    return nil
  end
  local departed, arrived = data.departed, data.arrived
  if type(departed) ~= "string" or departed == "" then
    return nil
  end
  if type(arrived) ~= "string" or arrived == "" then
    return nil
  end
  if departed == arrived then
    return nil
  end
  return { departed = departed, arrived = arrived }
end

local function store_visit_edge(edge)
  if io == nil or io.open == nil then
    return
  end
  local path = visit_path()
  local dir = path:match("^(.*)/[^/]+$")
  if dir then
    rex.exec({ "mkdir", "-p", dir })
  end
  local payload = rex.json.encode({
    v = 1,
    departed = edge.departed,
    arrived = edge.arrived,
  }) .. "\n"
  local tmp = path .. "." .. tostring(os.getpid and os.getpid() or "tmp") .. ".tmp"
  local file, err = io.open(tmp, "w")
  if file == nil then
    rex.log("warn", "rex_sesh: could not save visit edge: " .. tostring(err))
    return
  end
  file:write(payload)
  file:close()
  os.rename(tmp, path)
end

local function remember_visit(departed_id, arrived_id)
  if type(departed_id) ~= "string" or departed_id == "" then
    return
  end
  if type(arrived_id) ~= "string" or arrived_id == "" then
    return
  end
  if departed_id == arrived_id then
    return
  end
  local edge = { departed = departed_id, arrived = arrived_id }
  local existing = load_visit_edge()
  if existing ~= nil
    and existing.departed == edge.departed
    and existing.arrived == edge.arrived
  then
    return
  end
  store_visit_edge(edge)
end

local function lift_back_target(sessions, back_session_id)
  if back_session_id == nil or back_session_id == "" then
    return sessions
  end
  for i, session in ipairs(sessions) do
    if session.session_id == back_session_id then
      if i == 1 then
        return sessions
      end
      local out = { session }
      for j = 1, i - 1 do
        out[#out + 1] = sessions[j]
      end
      for j = i + 1, #sessions do
        out[#out + 1] = sessions[j]
      end
      return out
    end
  end
  return sessions
end

local function order_open_sessions(sessions, here_session_id)
  if here_session_id == nil or here_session_id == "" then
    return sessions
  end
  local edge = load_visit_edge()
  if edge == nil or edge.arrived ~= here_session_id then
    return sessions
  end
  return lift_back_target(sessions, edge.departed)
end

local function live_label_set(sessions)
  local set = {}
  for _, s in ipairs(sessions) do
    if type(s.label) == "string" and s.label ~= "" then
      set[s.label] = true
    end
  end
  return set
end

function M.session_label_for(path, live_labels)
  local base = basename(path)
  if base == "" then
    base = path
  end
  if live_labels[base] then
    base = base .. "-" .. sha256_hex6(path)
  end
  return base
end

local function load_open_sessions()
  local data, err = rex.call("session.list", {})
  if data == nil then
    error("session.list failed: " .. tostring(err), 0)
  end
  local raw = data.sessions
  if type(raw) ~= "table" then
    error("session.list returned unexpected sessions", 0)
  end
  local out = {}
  for _, item in ipairs(raw) do
    if type(item) == "table" then
      local sid, label = item.session_id, item.label
      if type(sid) == "string" and sid ~= "" and type(label) == "string" and label ~= "" then
        out[#out + 1] = { session_id = sid, label = label }
      end
    end
  end
  return out
end

local function load_zoxide_launches(live_labels)
  local zoxide = find_bin("zoxide")
  if zoxide == nil then
    error(
      "zoxide not found (checked PATH and Homebrew fallbacks; brew install zoxide)",
      0
    )
  end
  local r = rex.exec({ zoxide, "query", "--list" })
  if r == nil then
    error("zoxide query failed: could not run " .. zoxide, 0)
  end
  if not r.ok then
    error("zoxide query failed: " .. trim(r.stderr), 0)
  end
  local seen = {}
  local launches = {}
  for line in r.stdout:gmatch("[^\r\n]+") do
    local raw = trim(line)
    if raw ~= "" then
      local canon = realpath_dir(raw)
      if canon ~= nil and not seen[canon] then
        seen[canon] = true
        launches[#launches + 1] = {
          path = canon,
          label = M.session_label_for(canon, live_labels),
        }
      end
    end
  end
  return launches
end

function M.build_board(here_session_id)
  local open_sessions = load_open_sessions()
  local live_labels = live_label_set(open_sessions)
  local launches = load_zoxide_launches(live_labels)
  open_sessions = order_open_sessions(open_sessions, here_session_id)
  return { open_sessions = open_sessions, launches = launches }
end

local OPEN_PREFIX = "o:"
local DIR_PREFIX = "d:"

function M.board_to_pick_items(board)
  local items = {}
  for _, session in ipairs(board.open_sessions) do
    items[#items + 1] = {
      id = OPEN_PREFIX .. session.session_id,
      title = session.label,
      icon = "terminal",
    }
  end
  for _, launch in ipairs(board.launches) do
    items[#items + 1] = {
      id = DIR_PREFIX .. launch.path,
      title = launch.label,
      subtitle = pretty(launch.path),
      icon = "folder",
    }
  end
  return items
end

function M.decision_from_id(id, board)
  if type(id) ~= "string" or id == "" then
    return nil, "empty id"
  end
  if id:sub(1, #OPEN_PREFIX) == OPEN_PREFIX then
    local sid = id:sub(#OPEN_PREFIX + 1)
    for _, session in ipairs(board.open_sessions) do
      if session.session_id == sid then
        return { kind = "open", session_id = sid, label = session.label }, nil
      end
    end
    return nil, "unknown open session id"
  end
  if id:sub(1, #DIR_PREFIX) == DIR_PREFIX then
    local path = id:sub(#DIR_PREFIX + 1)
    for _, launch in ipairs(board.launches) do
      if launch.path == path then
        return { kind = "dir", path = path, label = launch.label }, nil
      end
    end
    return nil, "unknown directory id"
  end
  return nil, "unrecognized id prefix"
end

local function apply_decision(decision)
  if decision.kind == "open" then
    rex.client.queue("session.select", { session_id = decision.session_id })
    return decision.session_id
  end
  if decision.kind == "dir" then
    local session, err = rex.call("session.create", {
      label = decision.label,
      initial_windows = {
        {
          window_label = "shell",
          layout = rex.layout.block({
            flavor = "com.superlogical.terminal.shell",
            options = { cwd = decision.path },
          }),
        },
      },
    })
    if session == nil then
      error("creating session failed: " .. tostring(err), 0)
    end
    rex.client.queue("session.select", { session_id = session.session_id })
    return session.session_id
  end
  error("unknown decision kind", 0)
end

local function board_empty(board)
  return #board.open_sessions == 0 and #board.launches == 0
end

local function stop_pick(why)
  if why ~= "cancelled" then
    rex.log("warn", "rex_sesh: " .. tostring(why))
  end
end

local function run(ctx, args)
  if ctx.session_id == nil then
    error("run from a terminal pane (key or palette), not bare rex CLI", 0)
  end
  args = args or {}
  local board = M.build_board(ctx.session_id)
  if board_empty(board) then
    rex.log(
      "warn",
      "rex_sesh: no open sessions and no zoxide directories "
        .. "(visit folders so zoxide has history, or start a Rex session)"
    )
    return nil
  end

  local choice = args.choice
  if choice == nil then
    local id, why = rex.ui.pick({
      title = "Sessions",
      placeholder = "Filter sessions and directories",
      items = M.board_to_pick_items(board),
    })
    if id == nil then
      stop_pick(why)
      return nil
    end
    choice = id
  end

  local decision, derr = M.decision_from_id(choice, board)
  if decision == nil then
    stop_pick(derr or "invalid choice")
    return nil
  end

  local arrived = apply_decision(decision)
  remember_visit(ctx.session_id, arrived)
  return { choice = choice, arrived_session_id = arrived }
end

function M.self_check()
  assert(M.session_label_for("/tmp/foo", {}) == "foo")
  assert(pretty(home .. "/src") == "~/src")

  local board = {
    open_sessions = {
      { session_id = "sid-open", label = "navigator" },
    },
    launches = {
      { path = "/tmp/ws", label = "ws" },
    },
  }
  local items = M.board_to_pick_items(board)
  assert(#items == 2)
  assert(items[1].id == "o:sid-open" and items[1].icon == "terminal")
  assert(items[2].id == "d:/tmp/ws" and items[2].subtitle == "/tmp/ws")

  local dec = M.decision_from_id("o:sid-open", board)
  assert(dec and dec.kind == "open" and dec.session_id == "sid-open")
  dec = M.decision_from_id("d:/tmp/ws", board)
  assert(dec and dec.kind == "dir" and dec.path == "/tmp/ws")
  assert(M.decision_from_id("d:/nope", board) == nil)

  local ordered = lift_back_target({
    { session_id = "C", label = "c" },
    { session_id = "B", label = "b" },
    { session_id = "A", label = "a" },
  }, "B")
  assert(ordered[1].session_id == "B" and ordered[2].session_id == "C")

  local with_dup = M.session_label_for("/x/alpha", { alpha = true })
  assert(with_dup:match("^alpha%-%x%x%x%x%x%x$"))

  local zoxide = find_bin("zoxide")
  assert(zoxide ~= nil, "zoxide missing from PATH and Homebrew fallbacks")
  assert(zoxide:sub(1, 1) == "/", zoxide)

  return "self_check ok"
end

M._internal = {
  pretty = pretty,
  find_bin = find_bin,
  build_board = M.build_board,
  board_to_pick_items = M.board_to_pick_items,
  decision_from_id = M.decision_from_id,
  session_label_for = M.session_label_for,
  order_open_sessions = order_open_sessions,
  lift_back_target = lift_back_target,
  load_visit_edge = load_visit_edge,
  remember_visit = remember_visit,
  run = run,
  self_check = M.self_check,
}

rex.action({
  name = "rex_sesh",
  title = "New Session from Zoxide…",
  description = "Switch an open Rex session or create one from a zoxide directory.",
  keywords = "session zoxide workspace rex-sesh switch directory",
  args = { choice = "string?" },
  run = run,
})

return M