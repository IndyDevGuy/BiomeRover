-- /leader.lua
local Messages = require("shared/messages")
local Utils    = require("shared/utils")

_G.TURTLE_ROLE = "leader"
local OP = Messages.OP

-- ===== Config =====
local FUEL_MIN = 600
local MATERIAL_LOW_STACKS = 3
local FORWARD_LIMIT = math.huge

-- ===== Helpers =====
local function log(...) print("[LEADER]", ...) end

local function totalPlaceable()
    local stacks, items = 0, 0
    for s=2,16 do
        local d = turtle.getItemDetail(s)
        if d and not (d.name or ""):find("coal") then stacks = stacks + 1; items = items + d.count end
    end
    return stacks, items
end

local function selectPlaceable()
    for s=2,16 do
        local d = turtle.getItemDetail(s)
        if d and d.count > 0 and not (d.name or ""):find("coal") then turtle.select(s); return true end
    end
    return false
end

local function requestFuel()
    log("Requesting fuel…")
    Messages.broadcast(OP.REQ_FUEL, { leaderId = os.getComputerID() })
    while true do
        local id, msg, proto = rednet.receive(Messages.PROTOCOL, 30)
        if id and type(msg)=="table" and msg.op == OP.FUEL_RDY then
            turtle.select(1)
            -- move non-coal out of slot 1 if present
            local d1 = turtle.getItemDetail(1)
            if d1 and not (d1.name or ""):find("coal") then
                for s=2,16 do if turtle.getItemCount(s)==0 then turtle.transferTo(s) break end end
            end
            for i=1,8 do
                turtle.suck(64)
                local df = turtle.getItemDetail(1)
                if df and (df.name or ""):find("coal") then
                    turtle.refuel()
                    if turtle.getFuelLevel() >= FUEL_MIN then break end
                else break end
            end
            Messages.broadcast(OP.FUEL_DONE, { leaderId=os.getComputerID() })
            return turtle.getFuelLevel() >= FUEL_MIN
        end
    end
end

local function refuelIfNeeded()
    if turtle.getFuelLevel() == "unlimited" or turtle.getFuelLevel() >= FUEL_MIN then return true end
    turtle.select(1)
    local d = turtle.getItemDetail(1)
    if d and d.count > 0 then
        turtle.refuel()
        if turtle.getFuelLevel() >= FUEL_MIN then return true end
    end
    return requestFuel()
end

local function needMaterials()
    local stacks = select(1, totalPlaceable())
    return stacks <= MATERIAL_LOW_STACKS
end

local function requestMaterials()
    log("Requesting materials…")
    Messages.broadcast(OP.REQ_MAT, { leaderId=os.getComputerID(), need=10 })
    while true do
        local id, msg, proto = rednet.receive(Messages.PROTOCOL, 120)
        if id and type(msg)=="table" and msg.op == OP.MAT_RDY then
            -- Chest in FRONT: fill empty non-fuel slots
            for i=1,200 do
                local filled = 0
                for s=2,16 do
                    if turtle.getItemCount(s)==0 then turtle.select(s); turtle.suck(64) end
                    if turtle.getItemCount(s)>0 then filled = filled + 1 end
                end
                if filled >= 10 then break end
                sleep(0.1)
            end
            Messages.broadcast(OP.MAT_DONE, { leaderId=os.getComputerID() })
            return true
        end
    end
end

-- Movement / placement primitives
local function safeForward()
    local tries = 0
    while not turtle.forward() do
        tries = tries + 1
        local ok, data = turtle.inspect()
        if ok and data and data.name and data.name:find("turtle") then sleep(0.5)
        else turtle.dig(); sleep(0.2) end
        if tries > 20 then return false end
    end
    return true
end

local function ensureDownBlock()
    if turtle.detectDown() then return true end
    if not selectPlaceable() then return false end
    for i=1,5 do if turtle.placeDown() then return true end; sleep(0.1) end
    return false
end

local function sweepLeftToRight()
    if not ensureDownBlock() then return false end
    turtle.turnRight()
    for step=1,3 do
        if not safeForward() then turtle.turnLeft(); return false end
        if not ensureDownBlock() then turtle.turnLeft(); return false end
    end
    turtle.turnLeft(); turtle.turnLeft()
    for i=1,3 do turtle.forward() end
    turtle.turnRight()
    return true
end

-- Optional biome telemetry
local function tryBiome()
    local det = peripheral.find("environmentDetector") or peripheral.find("environment_detector")
    if not det then return nil end
    local ok, info = pcall(det.getBiome)
    if ok and type(info)=="table" then return info.name or info.biome or tostring(info.id) end
    return nil
end

-- Handle UI ops
local RUN = true
local function handleNetOnce()
    local id, msg, proto = rednet.receive(Messages.PROTOCOL, 0.1)
    if not id then return end
    if type(msg) ~= "table" then return end
    if msg.op == OP.PAUSE then RUN = false; Messages.send(id, OP.ACK, {status="paused"})
    elseif msg.op == OP.RESUME then RUN = true; Messages.send(id, OP.ACK, {status="running"})
    elseif msg.op == OP.ABORT then error("Abort received")
    elseif msg.op == OP.NUDGE then
        local step = (msg.body and msg.body.step) or 1
        for i=1,step do safeForward(); ensureDownBlock() end
        Messages.send(id, OP.ACK, {status="nudged"})
    elseif msg.op == OP.INIT then
        Messages.send(id, OP.ACK, {status="inited"})
    elseif msg.op == OP.GO then
        RUN = true; Messages.send(id, OP.ACK, {status="go"})
    end
end

-- Main build loop
local function buildBridge(limit)
    local steps = 0
    while steps < limit do
        handleNetOnce()
        if not RUN then sleep(0.2); goto continue end

        if not refuelIfNeeded() then log("Waiting for fuel…"); sleep(2) end
        if needMaterials() then if not requestMaterials() then log("Waiting for materials…"); sleep(2) end end

        if not sweepLeftToRight() then log("Sweep failed; retrying…"); sleep(0.5) end
        if not safeForward() then log("Forward blocked; retrying…"); sleep(0.5) end
        if not ensureDownBlock() then requestMaterials(); ensureDownBlock() end

        local biome = tryBiome()
        Messages.hb({ fuel=turtle.getFuelLevel(), status="building", biome=biome })
        steps = steps + 1
        ::continue::
    end
end

-- Entry
local function main()
    Messages.ensureModem()
    Messages.hello({ status="READY" })
    print("Leader: starting 4-wide bridge (L→R)")
    buildBridge(FORWARD_LIMIT)
end

local ok, err = pcall(main)
if not ok then printError(err) end
