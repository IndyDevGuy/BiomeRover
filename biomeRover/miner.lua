-- /miner.lua
local Messages = require("messages")
local Utils    = require("utils")

_G.TURTLE_ROLE = "miner"
local OP = Messages.OP

-- Slots: 1 fuel, 2 absorber, 3 fuel chest, 4 material chest
local REFUEL_GOAL = 1200

-- State: odometry broadcast for follower
local pos = {x=0,y=0,z=0}
local head = 0 -- 0=N,1=E,2=S,3=W
local DIRS = { [0]={x=0,z=-1}, [1]={x=1,z=0}, [2]={x=0,z=1}, [3]={x=-1,z=0} }

local function log(...) print("[MINER]", ...) end

-- Turning & steps update heading/pos
local function left()  turtle.turnLeft();  head = (head + 3) % 4 end
local function right() turtle.turnRight(); head = (head + 1) % 4 end
local function fwd()   if Utils.fwd() then pos.x = pos.x + DIRS[head].x; pos.z = pos.z + DIRS[head].z; return true end end
local function back()  if turtle.back() then pos.x = pos.x - DIRS[head].x; pos.z = pos.z - DIRS[head].z; return true end end
local function up()    if Utils.up() then pos.y = pos.y + 1; return true end end
local function down()  if Utils.down() then pos.y = pos.y - 1; return true end end

local function hb(status)
    Messages.hb({ role="miner", x=pos.x, y=pos.y, z=pos.z, heading=head, fuel=turtle.getFuelLevel(), status=status or "OK" })
end

-- Strict slot-1 fuel check/refuel via chest if needed
local function ensureFuel(min)
    min = min or Utils.FUEL_MIN
    if turtle.getFuelLevel() == "unlimited" or turtle.getFuelLevel() >= min then return true end
    -- slot 1 only
    Utils.requireFuel(min, "miner")
    if turtle.getFuelLevel() >= min then return true end
    -- place fuel chest, pull coal, refuel, pickup
    local ok, err = Utils.withTempChest{
        slot=3, dir="front",
        fn=function()
            for i=1,8 do
                turtle.select(Utils.SLOT_FUEL); turtle.suck(64); turtle.refuel(64)
                if turtle.getFuelLevel() >= REFUEL_GOAL then break end
            end
        end
    }
    return ok
end

-- Ops from leader/UI
local function handle(op, body, fromId)
    if op == OP.REQ_MAT then
        -- Place material chest in FRONT; wait for MAT_DONE; pick up
        local ok, perr = Utils.withTempChest{ slot=4, dir="front", fn=function() end }
        Messages.broadcast(OP.MAT_RDY, { ok=ok, err=perr })
        -- (Leader will send MAT_DONE; we don't need to block here.)
    elseif op == OP.REQ_FUEL then
        local ok, perr = Utils.withTempChest{ slot=3, dir="front", fn=function() end }
        Messages.broadcast(OP.FUEL_RDY, { ok=ok, err=perr })
    elseif op == OP.NUDGE then
        local step = (body and body.step) or 1
        for i=1,step do ensureFuel(); fwd() end
        Messages.send(fromId, OP.ACK, { status="nudged" })
    elseif op == OP.PAUSE then
        Messages.send(fromId, OP.ACK, { status="paused" })
    elseif op == OP.RESUME then
        Messages.send(fromId, OP.ACK, { status="running" })
    elseif op == OP.ABORT then
        error("Abort received")
    elseif op == OP.INIT then
        Messages.send(fromId, OP.ACK, { status="inited" })
    elseif op == OP.GO then
        Messages.send(fromId, OP.ACK, { status="go" })
    end
end

local function main()
    Messages.ensureModem()
    Messages.hello({ status="READY" })
    hb("READY")
    while true do
        -- light idle tick fuels + heartbeats
        ensureFuel()
        hb("OK")

        local id, msg, proto = rednet.receive(Messages.PROTOCOL, 1.0)
        if id and type(msg)=="table" and msg.op then
            local ok, err = pcall(handle, msg.op, msg.body, id)
            if not ok then log("ERR", err) end
        end
    end
end

local ok, err = pcall(main)
if not ok then printError(err) end
