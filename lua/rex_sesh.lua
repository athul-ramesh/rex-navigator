-- Rex session picker: one floating fzf over zoxide paths; Enter creates a session
-- and switches this Rex app client to it. Heavy work lives in rex-sesh-picker.

local M = {}

local home = os.getenv("HOME") or ""
M.HELPER = os.getenv("REX_SESH_PICKER")
  or (home .. "/.config/rex/rex-sesh-picker")
M.PICKER_LABEL = "rex-sesh"
M.BOUNDS = { x = 0.25, y = 0.15, w = 0.5, h = 0.7 }

local PATH_FALLBACK_PREFIXES = {
  "/opt/homebrew/bin",
  "/usr/local/bin",
  "/usr/bin",
  "/bin",
  home .. "/Library/Application Support/com.superlogical.rex"
    .. "/RexServer/Versions/Current/Rex Server.app/Contents/MacOS",
}

local function path_executable(p)
  local f = io.open(p, "rb")
  if f then
    f:close()
    return p
  end
  return nil
end

local function find_in_path(name)
  local seen = {}
  local function try(prefix)
    if seen[prefix] then return nil end
    seen[prefix] = true
    return path_executable(prefix .. "/" .. name)
  end
  for prefix in string.gmatch(os.getenv("PATH") or "", "[^:]+") do
    local hit = try(prefix)
    if hit then return hit end
  end
  for _, prefix in ipairs(PATH_FALLBACK_PREFIXES) do
    local hit = try(prefix)
    if hit then return hit end
  end
  return nil
end

M.find_python3 = find_in_path

function M.find_picker(view)
  for _, win in ipairs(view.windows or {}) do
    for _, layer in ipairs(win.layers or {}) do
      for _, block in ipairs(layer.blocks or {}) do
        if block.label == M.PICKER_LABEL then
          return win.window_id, layer.layer_id, block.block_id
        end
      end
    end
  end
  return nil
end

function M.open(ctx)
  local view, err = rex.session.view{}
  if view == nil then error(err, 0) end

  local _, layer_id, block_id = M.find_picker(view)
  if block_id ~= nil then
    rex.session.raise_layer{ layer_id = layer_id }
    rex.session.focus_block{ block_id = block_id }
    return { focused_existing = true, block_id = block_id }
  end

  local python3 = find_in_path("python3")
  if python3 == nil then
    error("python3 not found (checked PATH and Homebrew fallbacks)", 0)
  end

  local argv = {
    python3,
    M.HELPER,
    "--session", ctx.session_id,
    "--block", ctx.block_id or "",
    "--client", ctx.client_id or "",
  }
  local res, lerr = rex.session.new_layer{
    bounds = M.BOUNDS,
    focus = true,
    layout = rex.layout.block{
      flavor = "com.superlogical.terminal.shell",
      label = M.PICKER_LABEL,
      options = {
        cwd = home,
        command = argv,
        shell = "none",
      },
    },
  }
  if res == nil then error(lerr, 0) end
  local new_block = nil
  if res.block_ids ~= nil and res.block_ids[1] ~= nil then
    new_block = res.block_ids[1]
  end
  return { focused_existing = false, layer_id = res.layer_id, block_id = new_block }
end

rex.action{
  name = "rex_sesh",
  title = "New Session from Zoxide…",
  description = "Fuzzy-search zoxide directories, create a session there, and show it in this client.",
  keywords = "session zoxide fzf new workspace rex-sesh",
  run = function(ctx, _args)
    if ctx.session_id == nil then
      error("run from a terminal pane (key or palette), not bare rex CLI", 0)
    end
    -- Config actions are killed at ~30s; detached children die with them. Return once the float is up.
    return M.open(ctx)
  end,
}

return M
