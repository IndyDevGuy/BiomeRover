-- /utils.lua
-- Common turtle helpers

local U = {}

U.SLOT_FUEL = 1
U.FUEL_MIN  = 200

local function sel(s) turtle.select(s); return s end
local function cnt(s) local d=turtle.getItemDetail(s); return d and d.count or 0 end

function U.requireFuel(min, why)
    min = min or U.FUEL_MIN
    if turtle.getFuelLevel() == "unlimited" or turtle.getFuelLevel() >= min then return true end
    sel(U.SLOT_FUEL)
    if cnt(U.SLOT_FUEL) > 0 then
        turtle.refuel(64)
        if turtle.getFuelLevel() >= min then return true end
    end
    error(("Low fuel (<%d) %s"):format(min, why or ""))
end

-- heading tracking (0=N,1=E,2=S,3=W)
_G.__DIR = _G.__DIR or 0
local function wrapTurn(fn, d) return function() if fn() then _G.__DIR = (_G.__DIR + d) % 4; return true end end end
U.left, U.right = wrapTurn(turtle.turnLeft,-1), wrapTurn(turtle.turnRight,1)
function U.face(dir) dir = dir % 4; while _G.__DIR ~= dir do U.right() end end

local function step(move, dig, atk, detect)
    local tries=0
    while not move() do
        if detect() then atk(); dig(); sleep(0.05) else sleep(0.05) end
        tries=tries+1; if tries>20 then return false end
    end
    return true
end
function U.fwd()  U.requireFuel(); return step(turtle.forward, turtle.dig, turtle.attack, turtle.detect) end
function U.up()   U.requireFuel(); return step(turtle.up,      turtle.digUp, turtle.attackUp, turtle.detectUp) end
function U.down() U.requireFuel(); return step(turtle.down,    turtle.digDown, turtle.attackDown, turtle.detectDown) end

local function place(place, dig, detect) if detect() then dig() end; return place() end
function U.placeFront() return place(turtle.place,    turtle.dig,    turtle.detect) end
function U.placeDown()  return place(turtle.placeDown,turtle.digDown,turtle.detectDown) end
function U.placeUp()    return place(turtle.placeUp,  turtle.digUp,  turtle.detectUp) end

function U.dropAllExceptFuel(dir)
    for s=2,16 do
        if cnt(s)>0 then sel(s)
            if dir=="down" then turtle.dropDown() elseif dir=="up" then turtle.dropUp() else turtle.drop() end
        end
    end
end

function U.fillFrom(dir)
    for s=2,16 do
        if cnt(s)==0 then sel(s)
            if dir=="down" then turtle.suckDown() elseif dir=="up" then turtle.suckUp() else turtle.suck() end
        end
    end
end

-- withTempChest{ slot=4, dir="front", fn=function() ... end }
function U.withTempChest(opts)
    local slot = assert(opts.slot, "slot required")
    local dir  = opts.dir or "front"
    local fn   = assert(opts.fn, "fn required")
    sel(slot)
    local placed = (dir=="down" and U.placeDown()) or (dir=="up" and U.placeUp()) or U.placeFront()
    if not placed then return false, "place failed" end
    local ok, err = pcall(fn)
    if dir=="down" then turtle.digDown() elseif dir=="up" then turtle.digUp() else turtle.dig() end
    if not ok then return false, err end
    return true
end

return U
