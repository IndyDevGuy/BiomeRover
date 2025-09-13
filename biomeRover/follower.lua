-- /follower.lua
local Messages = require("shared/messages")
local Utils    = require("shared/utils")

_G.TURTLE_ROLE = "follower"
local OP = Messages.OP

local CFG = {
    followDistance = 3,
    catchupDistance = 10,
    heartbeatInterval = 1.0,
}

-- Heading math (0=N,1=E,2=S,3=W)
local DIRS = {
    [0] = {x=0, z=-1, name="N"},
    [1] = {x=1, z=0,  name="E"},
    [2] = {x=0, z=1,  name="S"},
    [3] = {x=-1, z=0, name="W"},  -- FIXED: was "{-1,z=0}"
}

local pos = {x=0,y=0,z=0}
local head = 0
local minerLast = nil

local function face(h)
    local delta = (h - head) % 4
    if delta == 0 then return true end
    if delta == 1 then turtle.turnRight()
    elseif delta == 2 then turtle.turnRight(); turtle.turnRight()
    elseif delta == 3 then turtle.turnLeft() end
    head = h; return true
end

local function fwd()
    Utils.requireFuel(50,"follower move")
    while not turtle.forward() do
        local ok, data = turtle.inspect()
        if ok and data and data.name and data.name:find("turtle") then sleep(0.2) else turtle.dig(); sleep(0.1) end
    end
    pos.x = pos.x + DIRS[head].x; pos.z = pos.z + DIRS[head].z; return true
end

local function up()
    Utils.requireFuel(50,"follower up"); while not turtle.up() do local ok,d=turtle.inspectUp(); if ok and d and (d.name or ""):find("turtle") then sleep(0.2) else turtle.digUp() end end
    pos.y = pos.y + 1; return true
end

local function down()
    Utils.requireFuel(50,"follower down"); while not turtle.down() do local ok,d=turtle.inspectDown(); if ok and d and (d.name or ""):find("turtle") then sleep(0.2) else turtle.digDown() end end
    pos.y = pos.y - 1; return true
end

local function stepToward(dx, dy, dz)
    if dy > 0 then return up()
    elseif dy < 0 then return down() end
    if dx ~= 0 then face(dx > 0 and 1 or 3); return fwd() end
    if dz ~= 0 then face(dz > 0 and 2 or 0); return fwd() end
    return true
end

local function desiredFromMiner(m)
    local f = DIRS[m.heading]
    return { x = m.x - f.x * CFG.followDistance, y = m.y, z = m.z - f.z * CFG.followDistance }
end

local function mdist(a,b) local dx,dy,dz=a.x-b.x,a.y-b.y,a.z-b.z; return math.abs(dx)+math.abs(dy)+math.abs(dz),dx,dy,dz end

local function netPumpOnce()
    local id, m, proto = rednet.receive(Messages.PROTOCOL, 0.0)
    if id and type(m)=="table" then
        if m.op == OP.HELLO and m.role == "miner" then
            -- wait for heartbeats to get coordinates; do nothing
        elseif m.op == OP.HB and m.role=="miner" then
            minerLast = { x=m.body and m.body.x or m.x, y=m.body and m.body.y or m.y, z=m.body and m.body.z or m.z, heading=m.body and m.body.heading or m.heading }
        elseif m.op == OP.PAUSE then
            Messages.send(id, OP.ACK, { status="paused" })
        elseif m.op == OP.RESUME then
            Messages.send(id, OP.ACK, { status="running" })
        elseif m.op == OP.ABORT then
            error("Abort received")
        elseif m.op == OP.INIT then
            Messages.send(id, OP.ACK, { status="inited" })
        elseif m.op == OP.GO then
            Messages.send(id, OP.ACK, { status="go" })
        end
    end
end

local function main()
    Messages.ensureModem()
    Messages.hello({ status="READY" })
    while true do
        netPumpOnce()
        if minerLast then
            local tgt = desiredFromMiner(minerLast)
            local d,dx,dy,dz = mdist(pos, tgt)
            if d > 0 then stepToward(dx,dy,dz) else face(minerLast.heading) end
        end
        Messages.hb({ fuel=turtle.getFuelLevel(), status="trailing", pos=("("..pos.x..","..pos.y..","..pos.z..")") })
        sleep(CFG.heartbeatInterval)
    end
end

local ok, err = pcall(main)
if not ok then printError(err) end
