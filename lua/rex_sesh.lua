local M = {}

local home = (os and os.getenv and os.getenv("HOME")) or ""

local MAX_LAUNCHES = 48
local CURRENT_DETAIL = "current"
local OPEN_DETAIL = "open"

-- Rex server PATH is often /usr/bin:/bin:/usr/sbin:/sbin only.
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

local function split_lines(text)
  if text == "" then
    return {}
  end
  local out = {}
  local pos = 1
  while true do
    local nl = text:find("\n", pos, true)
    if nl then
      out[#out + 1] = text:sub(pos, nl - 1)
      pos = nl + 1
    else
      if pos <= #text then
        out[#out + 1] = text:sub(pos)
      end
      break
    end
  end
  return out
end

local function parse_zoxide_score_line(line)
  local score_s, rest = line:match("^%s*([%d%.]+)%s+(.*)$")
  if score_s == nil then
    return nil
  end
  local score = tonumber(score_s)
  local path = trim(rest or "")
  if score == nil or path == "" then
    return nil
  end
  return score, path
end

local function merge_resolved_scores(scores, canon_lines)
  local by_path = {}
  local order = {}
  for i, canon in ipairs(canon_lines) do
    if canon ~= "" then
      local sc = scores[i]
      if sc ~= nil then
        local prev = by_path[canon]
        if prev == nil then
          by_path[canon] = sc
          order[#order + 1] = canon
        elseif sc > prev then
          by_path[canon] = sc
        end
      end
    end
  end
  local out = {}
  for _, path in ipairs(order) do
    out[#out + 1] = { path = path, score = by_path[path] }
  end
  return out
end

local function select_launches(scored, open_sessions, max_n)
  local label_set = {}
  local hex_labels = {}
  local hex_bases = {}
  for _, s in ipairs(open_sessions) do
    if type(s.label) == "string" and s.label ~= "" then
      label_set[s.label] = true
      local base = s.label:match("^(.*)%-%x%x%x%x%x%x$")
      if base ~= nil then
        hex_labels[s.label] = true
        hex_bases[base] = true
      end
    end
  end

  local basename_counts = {}
  for _, row in ipairs(scored) do
    local b = basename(row.path)
    basename_counts[b] = (basename_counts[b] or 0) + 1
  end

  local function covered(path)
    local b = basename(path)
    if label_set[b] and basename_counts[b] == 1 then
      return true
    end
    if hex_bases[b] then
      return hex_labels[b .. "-" .. sha256_hex6(path)] == true
    end
    return false
  end

  local kept = {}
  for _, row in ipairs(scored) do
    if not covered(row.path) then
      kept[#kept + 1] = row
    end
  end

  for i, row in ipairs(kept) do
    row._ord = i
  end
  table.sort(kept, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end
    return a._ord < b._ord
  end)

  local out = {}
  for i = 1, math.min(max_n, #kept) do
    out[#out + 1] = { path = kept[i].path, score = kept[i].score }
  end
  return out
end

local RESOLVE_DIRS_PY = [[
import os, sys
for line in sys.stdin:
    raw = line.strip()
    if not raw or not os.path.isdir(raw):
        print()
        continue
    try:
        canon = os.path.realpath(raw)
    except OSError:
        print()
        continue
    if not os.path.isdir(canon):
        print()
        continue
    print(canon.replace("\\", "/"))
]]

local function resolve_zoxide_dirs(raw_lines)
  if #raw_lines == 0 then
    return {}
  end
  local python3 = find_bin("python3")
  if python3 == nil then
    error(
      "python3 not found (checked PATH and Homebrew fallbacks; install python3)",
      0
    )
  end
  local stdin = table.concat(raw_lines, "\n") .. "\n"
  local r = rex.exec({ python3, "-c", RESOLVE_DIRS_PY }, { stdin = stdin })
  if r == nil or not r.ok then
    local err = (r and trim(r.stderr)) or "python resolve failed"
    error("zoxide path resolve failed: " .. err, 0)
  end
  local canon_lines = split_lines(r.stdout or "")
  if #canon_lines ~= #raw_lines then
    error("python3 resolve line count mismatch", 0)
  end
  for i, canon in ipairs(canon_lines) do
    if canon ~= "" then
      canon_lines[i] = slashes(trim(canon))
    else
      canon_lines[i] = ""
    end
  end
  return canon_lines
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

local function load_zoxide_launches(open_sessions)
  local zoxide = find_bin("zoxide")
  if zoxide == nil then
    error(
      "zoxide not found (checked PATH and Homebrew fallbacks; brew install zoxide)",
      0
    )
  end
  local r = rex.exec({ zoxide, "query", "-l", "-s" })
  if r == nil then
    error("zoxide query failed: could not run " .. zoxide, 0)
  end
  if not r.ok then
    error("zoxide query failed: " .. trim(r.stderr), 0)
  end
  local raw_lines = {}
  local scores = {}
  for line in r.stdout:gmatch("[^\r\n]+") do
    local score, path = parse_zoxide_score_line(line)
    if score ~= nil and path ~= nil then
      raw_lines[#raw_lines + 1] = path
      scores[#scores + 1] = score
    end
  end
  local canon_lines = resolve_zoxide_dirs(raw_lines)
  local merged = merge_resolved_scores(scores, canon_lines)
  local selected = select_launches(merged, open_sessions, MAX_LAUNCHES)
  local live_labels = live_label_set(open_sessions)
  local launches = {}
  for _, row in ipairs(selected) do
    launches[#launches + 1] = {
      path = row.path,
      label = M.session_label_for(row.path, live_labels),
      score = row.score,
    }
  end
  return launches
end

function M.build_board(here_session_id)
  local open_sessions = load_open_sessions()
  open_sessions = order_open_sessions(open_sessions, here_session_id)
  for _, s in ipairs(open_sessions) do
    s.current = (here_session_id ~= nil and here_session_id ~= "" and s.session_id == here_session_id)
  end
  local launches = load_zoxide_launches(open_sessions)
  return { open_sessions = open_sessions, launches = launches }
end

local OPEN_PREFIX = "o:"
local DIR_PREFIX = "d:"

function M.board_to_pick_items(board)
  local items = {}
  for _, session in ipairs(board.open_sessions) do
    local detail = OPEN_DETAIL
    if session.current then
      detail = CURRENT_DETAIL
    end
    items[#items + 1] = {
      id = OPEN_PREFIX .. session.session_id,
      title = session.label,
      detail = detail,
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

local function pick_request(board)
  if board_empty(board) then
    return {
      title = "No sessions to show",
      placeholder = "Visit folders so zoxide has history, or start a Rex session",
      items = {},
    }
  end
  return {
    title = "Sessions",
    placeholder = "Filter sessions and directories",
    items = M.board_to_pick_items(board),
  }
end

local function ui_pick_available(ui)
  return type(ui) == "table" and type(ui.pick) == "function"
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

  local choice = args.choice
  if choice == nil then
    local has_ui, ui = pcall(function()
      return rex.ui
    end)
    if not has_ui or not ui_pick_available(ui) then
      error(
        "rex.ui.pick is missing (custom UI needs control API revision 17+)",
        0
      )
    end
    local req = pick_request(board)
    local id, why = ui.pick(req)
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

  assert(split_lines("a\n\nb\n")[1] == "a")
  assert(split_lines("a\n\nb\n")[2] == "")
  assert(split_lines("a\n\nb\n")[3] == "b")
  assert(#split_lines("") == 0)

  local sc, p = parse_zoxide_score_line("  88.5 /Users/a/b c")
  assert(sc == 88.5 and p == "/Users/a/b c")
  assert(parse_zoxide_score_line("nope") == nil)

  local merged_one = merge_resolved_scores({ 1, 5, 3 }, { "/p", "/p", "" })
  assert(#merged_one == 1 and merged_one[1].path == "/p" and merged_one[1].score == 5)

  local uniq = select_launches(
    { { path = "/tmp/ws", score = 10 }, { path = "/tmp/other", score = 5 } },
  { { label = "ws" } },
    MAX_LAUNCHES
  )
  assert(#uniq == 1 and uniq[1].path == "/tmp/other")

  local shared = select_launches(
    { { path = "/a/foo", score = 2 }, { path = "/b/foo", score = 1 } },
    { { label = "foo" } },
    MAX_LAUNCHES
  )
  assert(#shared == 2)

  local hex_label = M.session_label_for("/b/foo", { foo = true })
  local hex_hide = select_launches(
    { { path = "/a/foo", score = 2 }, { path = "/b/foo", score = 1 } },
    { { label = hex_label } },
    MAX_LAUNCHES
  )
  assert(#hex_hide == 1 and hex_hide[1].path == "/a/foo")

  local cap_hide = select_launches(
    {
      { path = "/covered", score = 30 },
      { path = "/keep", score = 20 },
      { path = "/drop", score = 10 },
    },
    { { label = "covered" } },
    1
  )
  assert(#cap_hide == 1 and cap_hide[1].path == "/keep")

  local tie = select_launches(
    { { path = "/first", score = 5 }, { path = "/second", score = 5 } },
    {},
    2
  )
  assert(tie[1].path == "/first" and tie[2].path == "/second")

  local sort10 = select_launches(
    { { path = "/nine", score = 9 }, { path = "/ten", score = 10 } },
    {},
    MAX_LAUNCHES
  )
  assert(sort10[1].path == "/ten")

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
  assert(
    items[1].id == "o:sid-open"
      and items[1].icon == "terminal"
      and items[1].detail == OPEN_DETAIL
  )
  assert(items[2].id == "d:/tmp/ws" and items[2].subtitle == "/tmp/ws")

  local current_board = {
    open_sessions = {
      { session_id = "A", label = "a", current = false },
      { session_id = "B", label = "b", current = true },
    },
    launches = {},
  }
  local cur_items = M.board_to_pick_items(current_board)
  assert(cur_items[1].detail == OPEN_DETAIL and cur_items[2].detail == CURRENT_DETAIL)

  local dec = M.decision_from_id("o:sid-open", board)
  assert(dec and dec.kind == "open" and dec.session_id == "sid-open")
  dec = M.decision_from_id("d:/tmp/ws", board)
  assert(dec and dec.kind == "dir" and dec.path == "/tmp/ws")
  assert(M.decision_from_id("d:/nope", board) == nil)

  local board2 = {
    open_sessions = board.open_sessions,
    launches = { { path = "/tmp/other", label = "other" } },
  }
  assert(M.decision_from_id("d:/tmp/ws", board2) == nil)
  assert(M.decision_from_id("d:/tmp/other", board2).path == "/tmp/other")

  local ordered = lift_back_target({
    { session_id = "C", label = "c" },
    { session_id = "B", label = "b" },
    { session_id = "A", label = "a" },
  }, "B")
  assert(ordered[1].session_id == "B" and ordered[2].session_id == "C")

  local with_current = {
    { session_id = "C", label = "c", current = false },
    { session_id = "B", label = "b", current = true },
    { session_id = "A", label = "a", current = false },
  }
  local lifted = lift_back_target(with_current, "B")
  assert(lifted[1].session_id == "B" and lifted[2].session_id == "C" and lifted[1].current == true)

  local empty_req = pick_request({ open_sessions = {}, launches = {} })
  assert(empty_req.title == "No sessions to show" and #empty_req.items == 0)
  local full_req = pick_request(board)
  assert(full_req.title == "Sessions" and #full_req.items == 2)

  assert(ui_pick_available(nil) == false)
  assert(ui_pick_available({}) == false)
  assert(ui_pick_available({ pick = function() end }) == true)

  local with_dup = M.session_label_for("/x/alpha", { alpha = true })
  assert(with_dup:match("^alpha%-%x%x%x%x%x%x$"))

  local zoxide = find_bin("zoxide")
  assert(zoxide ~= nil, "zoxide missing from PATH and Homebrew fallbacks")
  assert(zoxide:sub(1, 1) == "/", zoxide)

  local python3 = find_bin("python3")
  assert(python3 ~= nil, "python3 missing from PATH and Homebrew fallbacks")
  assert(python3:sub(1, 1) == "/", python3)

  return "self_check ok"
end

M._internal = {
  pretty = pretty,
  find_bin = find_bin,
  split_lines = split_lines,
  parse_zoxide_score_line = parse_zoxide_score_line,
  merge_resolved_scores = merge_resolved_scores,
  select_launches = select_launches,
  pick_request = pick_request,
  ui_pick_available = ui_pick_available,
  MAX_LAUNCHES = MAX_LAUNCHES,
  CURRENT_DETAIL = CURRENT_DETAIL,
  OPEN_DETAIL = OPEN_DETAIL,
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