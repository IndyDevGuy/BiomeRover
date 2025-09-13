-- control_ui.lua
-- Pocket Computer Mission Controller (Turtle Rover Program)
-- Roles: leader, miner, follower
-- Protocol: "turtle_rover"
-- Controls the bridge-building mission (4 blocks wide, L->R).
-- CC:Tweaked required. Place a wireless modem on the pocket.

-- =============== CONFIG ===============

local PROTOCOL      = "turtle_rover"
local SAVE_PATH     = "/biomeRover/config.json"
local HEARTBEAT_SEC = 1.0          -- UI refresh cadence
local HELLO_TIMEOUT = 3.0          -- wait after scan
local REPLY_TIMEOUT = 2.5          -- network reply timeout
local HB_STALE_SEC  = 5.0          -- mark unit stale after no HB
local DEFAULTS = {
  bridge = { width = 4, direction = "L2R" }, -- fixed per spec
  slots = {
    all = { fuel = 1 },
    miner = { fuel = 1, biome_absorber = 2, fuel_chest = 3, material_chest = 4 }
  }
}

-- =============== STATE ===============

local roster = {
  -- id -> {id=number, role="leader|miner|follower", label=string, fuel=number, status=string, pos=string, biome=string, inv=table, ver=string, last=number}
}
local roles = { leader=nil, miner=nil, follower=nil } -- IDs for quick access
local mission = { state="IDLE", started_at=nil, paused=false, note="" }

-- =============== UTIL ===============

local function now() return os.epoch("utc")/1000 end

local function ensureDir(path)
  local parts = {}
  for part in path:gmatch("[^/]+") do table.insert(parts, part) end
  local cur = ""
  for i=1,#parts-1 do
    cur = cur.."/"..parts[i]
    if not fs.exists(cur) then fs.makeDir(cur) end
  end
end

local function save()
  ensureDir(SAVE_PATH)
  local f = fs.open(SAVE_PATH,"w")
  if not f then return end
  f.write(textutils.serializeJSON({
    roster = roster,
    roles  = roles,
    mission= mission,
    defaults = DEFAULTS
  }))
  f.close()
end

local function load()
  if not fs.exists(SAVE_PATH) then return end
  local f = fs.open(SAVE_PATH,"r")
  if not f then return end
  local ok, data = pcall(textutils.unserializeJSON, f.readAll() or "{}")
  f.close()
  if ok and type(data)=="table" then
    roster = data.roster or roster
    roles  = data.roles or roles
    mission= data.mission or mission
  end
end

local function sideWithModem()
  for _,s in ipairs(rs.getSides()) do
    if peripheral.getType(s) == "modem" and peripheral.call(s, "isWireless") then
      return s
    end
  end
end

local function openRednet()
  if not rednet.isOpen() then
    local s = sideWithModem()
    if not s then
      error("No wireless modem found on pocket. Attach one and retry.")
    end
    rednet.open(s)
  end
end

local function send(to, msg, expect_reply)
  msg.protocol = PROTOCOL
  rednet.send(to, msg, PROTOCOL)
  if expect_reply then
    local t = os.startTimer(REPLY_TIMEOUT)
    while true do
      local e, p1, p2, p3, p4 = os.pullEvent()
      if e=="rednet_message" then
        local id, payload, proto = p1, p2, p3
        if proto==PROTOCOL and id==to and type(payload)=="table" and payload.corr==msg.corr then
          return payload
        end
      elseif e=="timer" and p1==t then
        return nil, "timeout"
      end
    end
  end
  return true
end

local function broadcast(msg)
  msg.protocol = PROTOCOL
  rednet.broadcast(msg, PROTOCOL)
end

local function shortId(id) return ("#" .. tostring(id)) end
local function clamp(n, a, b) if n<a then return a elseif n>b then return b else return n end end
local function secsAgo(ts) if not ts then return "—" end return string.format("%.0fs", math.max(0, now()-ts)) end

-- =============== ROSTER MGMT ===============

local function setRole(id, role)
  -- ensure uniqueness
  for k,v in pairs(roles) do
    if v == id then roles[k]=nil end
  end
  roles[role] = id
  if roster[id] then roster[id].role = role end
  save()
end

local function clearRole(role)
  roles[role] = nil
  save()
end

local function forget(id)
  roster[id] = nil
  for r, rid in pairs(roles) do if rid==id then roles[r]=nil end end
  save()
end

local function upsertUnit(info)
  local id = info.id
  local r  = roster[id] or { id=id }
  for k,v in pairs(info) do r[k]=v end
  r.last = now()
  roster[id] = r
end

-- =============== NETWORK HANDLERS ===============

local function handleNet()
  -- Keep listening for heartbeats / status pushes
  local e, sid, payload, proto = os.pullEvent("rednet_message")
  if proto ~= PROTOCOL or type(payload) ~= "table" then return end
  if payload.op == "hello" then
    upsertUnit({
      id=sid, role=payload.role, label=payload.label, ver=payload.ver,
      status=payload.status or "READY", fuel=payload.fuel, pos=payload.pos,
      biome=payload.biome, inv=payload.inv
    })
    -- Remember role mapping if not set
    if payload.role and not roles[payload.role] then setRole(sid, payload.role) end

  elseif payload.op == "hb" then
    local r = roster[sid] or { id=sid }
    r.fuel  = payload.fuel
    r.pos   = payload.pos
    r.status= payload.status
    r.biome = payload.biome or r.biome
    r.inv   = payload.inv or r.inv
    r.last  = now()
    roster[sid] = r

  elseif payload.op == "ack" then
    -- could surface a toast; for simplicity we just refresh state
    local r = roster[sid] or { id=sid }
    r.status = payload.status or r.status
    r.last   = now()
    roster[sid] = r

  elseif payload.op == "note" then
    mission.note = payload.note or mission.note

  end
end

-- =============== COMMANDS ===============

local corrSeq = 0
local function nextCorr()
  corrSeq = corrSeq + 1
  return ("%x"):format(corrSeq)
end

local function cmd(to, op, body, expect_reply)
  local msg = { op=op, body=body or {}, corr=nextCorr() }
  if to == "ALL" then
    broadcast(msg); return true
  elseif type(to)=="number" then
    return send(to, msg, expect_reply)
  else
    return false, "bad target"
  end
end

local function allPresent()
  return roles.leader and roles.miner and roles.follower
end

local function scanForUnits()
  -- Clear last-seen timestamps but keep remembered roles
  broadcast({ op="ping", corr=nextCorr() })
  local deadline = now() + HELLO_TIMEOUT
  while now() < deadline do
    local e, sid, payload, proto, dist
    local timeLeft = clamp(deadline - now(), 0.05, HELLO_TIMEOUT)
    local tid = os.startTimer(timeLeft)
    while true do
      local ev, p1, p2, p3 = os.pullEvent()
      if ev=="rednet_message" then
        sid, payload, proto = p1, p2, p3
        if proto==PROTOCOL and type(payload)=="table" and payload.op=="hello" then
          upsertUnit({
            id=sid, role=payload.role, label=payload.label, ver=payload.ver,
            status=payload.status or "READY", fuel=payload.fuel, pos=payload.pos,
            biome=payload.biome, inv=payload.inv
          })
          if payload.role and not roles[payload.role] then setRole(sid, payload.role) end
        end
      elseif ev=="timer" and p1==tid then
        break
      end
    end
  end
  save()
end

local function initMission()
  mission.state="INIT"; mission.started_at=nil; mission.paused=false; mission.note=""
  -- Push fixed mission parameters to all units
  local body = {
    bridge = { width = DEFAULTS.bridge.width, direction = DEFAULTS.bridge.direction },
    slots  = DEFAULTS.slots
  }
  cmd("ALL","init", body)
  -- Ask each role to sync its prerequisites
  if roles.leader then cmd(roles.leader,"sync",{ want="materials" }) end
  if roles.miner  then cmd(roles.miner,"sync",{ want="chests+absorber" }) end
  if roles.follower then cmd(roles.follower,"sync",{ want="trail" }) end
  save()
end

local function startMission()
  if not allPresent() then mission.note="Missing units (need leader+miner+follower)"; return end
  mission.state="RUN"; mission.started_at=now(); mission.paused=false; mission.note=""
  cmd("ALL","go",{ })
  save()
end

local function pauseMission()
  if mission.state ~= "RUN" then return end
  mission.paused = true; mission.state="PAUSED"
  cmd("ALL","pause",{})
  save()
end

local function resumeMission()
  if mission.state ~= "PAUSED" then return end
  mission.paused = false; mission.state="RUN"
  cmd("ALL","resume",{})
  save()
end

local function abortMission()
  mission.state="ABORT"; mission.note="Operator abort"
  cmd("ALL","abort",{})
  save()
end

local function shutdownUnits()
  cmd("ALL","shutdown",{})
end

local function nudge(step)
  step = step or 1
  -- Ask leader to step forward build by 'step' (useful if stuck)
  if roles.leader then cmd(roles.leader, "nudge", { step = step }) end
end

-- =============== UI ===============

local W,H = term.getSize()
local theme = {
  bg  = colors.black, fg = colors.white,
  ok  = colors.green, warn=colors.yellow, err=colors.red, mid=colors.gray, hi=colors.cyan
}

local function clr(cbg, cfg)
  term.setBackgroundColor(cbg or theme.bg)
  term.setTextColor(cfg or theme.fg)
end

local function line(y, text, cfg, cbg)
  clr(cbg, cfg)
  term.setCursorPos(1,y)
  term.clearLine()
  term.write(text)
end

local function padRight(s, n) s=tostring(s or "") if #s<n then return s..string.rep(" ", n-#s) else return s:sub(1,n) end end

local function drawHeader()
  clr(theme.hi, colors.black)
  term.setCursorPos(1,1); term.clearLine()
  local title = "Turtle Rover Control • Bridge 4-Wide (L→R)"
  term.write(padRight(title, W))
  clr()
  local st = mission.state
  local c = (st=="RUN" and theme.ok) or (st=="PAUSED" and theme.warn) or (st=="ABORT" and theme.err) or theme.mid
  line(2, ("State: "):upper()..st, colors.white, c)
  local elapsed = mission.started_at and string.format(" • Elapsed %ds", math.floor(now() - mission.started_at)) or ""
  line(3, ("Note: "..(mission.note or "—")..elapsed), theme.fg, theme.bg)
end

local function roleBadge(role)
  local id = roles[role]
  if not id then return role..": [—]" end
  local r = roster[id]
  local stale = (r and r.last and (now()-r.last > HB_STALE_SEC))
  local mark = stale and " (stale)" or ""
  local fuel = r and r.fuel and (" • fuel "..tostring(r.fuel)) or ""
  local status = r and r.status or "?"
  return string.format("%s: %s %s • %s%s", role, shortId(id), fuel, status, mark)
end

local function drawRoster()
  line(5,  roleBadge("leader"))
  line(6,  roleBadge("miner"))
  line(7,  roleBadge("follower"))
  line(8,  "Bridge: width=4 • dir=L→R")
  line(9,  "Slots: ALL slot1=fuel | Miner: 1 fuel, 2 absorber, 3 fuel chest, 4 material chest", theme.mid)
end

local function fmtUnitDetail(id)
  local r = roster[id]; if not r then return {"[missing]"} end
  local rows = {}
  table.insert(rows, (r.label and (r.label.." ") or "")..shortId(id).." • "..(r.role or "?").." • v"..(r.ver or "?"))
  table.insert(rows, "Status: "..(r.status or "—").." • Seen "..secsAgo(r.last).." ago")
  table.insert(rows, "Fuel: "..tostring(r.fuel or "—"))
  if r.pos then table.insert(rows, "Pos: "..r.pos) end
  if r.biome then table.insert(rows, "Biome: "..r.biome) end
  return rows
end

local focusedRole = "leader" -- which detail pane shows

local function drawDetails()
  local y = 11
  line(10, ("Details: "..focusedRole):upper(), colors.black, theme.hi)
  local id = roles[focusedRole]
  if not id then
    line(y, "No "..focusedRole.." assigned. Run [S]can or [R]emap.", theme.warn); y=y+1
    return
  end
  for _,row in ipairs(fmtUnitDetail(id)) do
    line(y, row); y=y+1
  end
end

local function drawHelp()
  local rows = {
    "[Enter] Start  [P]ause  [R]esume  [B] Abort  [N]udge  [S]can  [M]ap Roles  [D]etails  [X] Shutdown  [Q] Quit"
  }
  line(H, padRight(rows[1], W), colors.black, theme.hi)
end

local function render()
  term.setBackgroundColor(theme.bg); term.setTextColor(theme.fg); term.clear()
  drawHeader()
  drawRoster()
  drawDetails()
  drawHelp()
end

-- =============== ROLE MAPPER (tiny modal) ===============

local function prompt(msg, choices)
  -- simple single-line prompt waiting for key of choices
  local winW = math.min(W, math.max(30, #msg+2))
  local x = math.floor((W - winW)/2)+1
  local y = 4
  term.setCursorPos(x,y); clr(colors.gray, colors.black); term.write(padRight(msg, winW))
  term.setCursorPos(x,y+1); clr(colors.gray, colors.black); term.write(padRight("["..table.concat(choices,"/").."]", winW))
  while true do
    local e, k = os.pullEvent("key")
    local name = keys.getName(k)
    for _,c in ipairs(choices) do
      if name == string.lower(c) then return name end
    end
  end
end

local function mapRoles()
  render()
  term.setCursorPos(1, H-2); term.clearLine(); print("Role mapper: press L/M/F then click a discovered unit in chat list (use IDs).")
  print("Or press ESC to cancel.")
  local mapOrder = {"leader","miner","follower"}
  local idx=1
  while idx <= #mapOrder do
    local role = mapOrder[idx]
    line(H-3, "Assign role: "..role.." — type numeric ID + Enter (or ESC to skip)", theme.hi)
    term.setCursorPos(1,H-1); term.clearLine(); term.write("> ")
    local input = read()
    if input == "" then break end
    local id = tonumber(input)
    if id and roster[id] then
      setRole(id, role)
      idx = idx + 1
      render()
    else
      line(H-3, "Invalid ID. Try again.", theme.err)
    end
  end
end

-- =============== MAIN LOOPS ===============

local function uiLoop()
  while true do
    render()
    local t = os.startTimer(HEARTBEAT_SEC)
    while true do
      local ev, p1 = os.pullEvent()
      if ev=="timer" and p1==t then break end
      if ev=="key" then
        local k = keys.getName(p1)
        if k=="enter" then
          if mission.state=="IDLE" or mission.state=="INIT" or mission.state=="PAUSED" then
            if mission.state~="INIT" then initMission() end
            startMission()
          end
        elseif k=="p" then
          pauseMission()
        elseif k=="r" then
          resumeMission()
        elseif k=="b" then
          abortMission()
        elseif k=="s" then
          scanForUnits()
        elseif k=="d" then
          if focusedRole=="leader" then focusedRole="miner"
          elseif focusedRole=="miner" then focusedRole="follower"
          else focusedRole="leader" end
        elseif k=="m" then
          mapRoles()
        elseif k=="n" then
          nudge(1)
        elseif k=="x" then
          shutdownUnits()
        elseif k=="q" then
          term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear(); term.setCursorPos(1,1)
          return
        end
        break
      end
    end
  end
end

local function netLoop()
  while true do
    handleNet()
  end
end

-- =============== BOOTSTRAP ===============

local function banner()
  term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear()
  term.setCursorPos(1,1)
  print("Turtle Rover Mission Controller")
  print("Protocol: "..PROTOCOL)
  print("Bridge: 4-wide • Direction: Left→Right")
  print("All turtles: slot 1 reserved for fuel")
  print("Miner slots: 1 fuel, 2 absorber, 3 fuel chest, 4 material chest")
  print("Opening wireless modem...")
end

local function main()
  banner()
  openRednet()
  load()

  -- Initial discovery pass (units respond with 'hello')
  print("Scanning for units...")
  scanForUnits()
  print("Discovered "..tostring((function() local n=0 for _ in pairs(roster) do n=n+1 end return n end)()).." unit(s).")
  print("Press any key to open control UI.")
  os.pullEvent("key")

  parallel.waitForAny(uiLoop, netLoop)
end

-- =============== RUN ===============

local ok, err = pcall(main)
if not ok then
  term.setBackgroundColor(colors.black); term.setTextColor(colors.red); term.clear()
  term.setCursorPos(1,1); print("Controller crashed:\n"..tostring(err))
end
