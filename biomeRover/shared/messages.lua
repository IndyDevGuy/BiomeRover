-- /messages.lua
-- Unified messaging for Turtle Rover Program

local M = {}

M.PROTOCOL = "turtle_rover"

M.OP = {
    HELLO   = "hello",
    HB      = "hb",
    INIT    = "init",
    GO      = "go",
    PAUSE   = "pause",
    RESUME  = "resume",
    ABORT   = "abort",
    NUDGE   = "nudge",
    -- Leader <-> Miner (materials/fuel)
    REQ_MAT = "req_mat",
    MAT_RDY = "mat_rdy",
    MAT_DONE= "mat_done",
    REQ_FUEL= "req_fuel",
    FUEL_RDY= "fuel_rdy",
    FUEL_DONE="fuel_done",
    -- Telemetry
    BIOME   = "biome",
    PING    = "ping",
    ACK     = "ack",
    NOTE    = "note",
}

local corr = 0
local function nextCorr() corr = corr + 1; return ("%x"):format(corr) end

function M.ensureModem()
    if M._open then return true end
    for _, side in ipairs({"left","right","top","bottom","front","back"}) do
        if peripheral.getType(side) == "modem" and peripheral.call(side,"isWireless") then
            if not rednet.isOpen(side) then rednet.open(side) end
            M._open, M._side = true, side
            return true
        end
    end
    return false
end

local function env(op, body)
    return {
        op   = op,
        body = body or {},
        role = _G.TURTLE_ROLE or "unknown",
        id   = os.getComputerID(),
        ts   = os.epoch("utc"),
        corr = nextCorr(),
    }
end

function M.hello(extra)               assert(M.ensureModem()); rednet.broadcast(env(M.OP.HELLO, extra), M.PROTOCOL) end
function M.hb(extra)                  assert(M.ensureModem()); rednet.broadcast(env(M.OP.HB, extra),    M.PROTOCOL) end
function M.broadcast(op, body)        assert(M.ensureModem()); rednet.broadcast(env(op, body),           M.PROTOCOL) end
function M.send(to, op, body)         assert(M.ensureModem()); rednet.send(to, env(op, body),            M.PROTOCOL) end

function M.rpc(to, op, body, expectOp, timeout)
    local msg = env(op, body); assert(M.ensureModem()); rednet.send(to, msg, M.PROTOCOL)
    local deadline = os.clock() + (timeout or 10)
    while os.clock() < deadline do
        local id, payload, proto = rednet.receive(M.PROTOCOL, math.max(0, deadline - os.clock()))
        if id == to and type(payload) == "table" and payload.corr == msg.corr then
            if (not expectOp) or payload.op == expectOp then return payload end
        end
    end
    return nil, "timeout"
end

return M
