local Utilities = {}

function Utilities.new()
    local self = {
        lockPath = "urc/.manifest.lock"
    }
    function self:readAll(p) local f=fs.open(p,"r"); if not f then return nil end local s=f.readAll(); f.close(); return s end
    function self:writeAll(p,s) local d=fs.getDir(p); if d~="" and not fs.exists(d) then fs.makeDir(d) end local f=fs.open(p,"w"); assert(f,"Cannot write "..p); f.write(s); f.close() end
    function self:trim(s) return (s or ""):gsub("^%s+",""):gsub("%s+$","") end
    function self:combine(a,b) return fs.combine(a or "", b or "") end
    function self:jsonD(s) local f=textutils.unserialiseJSON or textutils.unserializeJSON; local ok,v=pcall(f,s); return ok and v or nil end
    function self:jsonE(t) local f=textutils.serialiseJSON or textutils.serializeJSON; return f(t,true) end
    function self:fetch(url)
        if not http then error("HTTP API disabled") end
        local ok, res = pcall(http.get, url)
        if not ok or not res then return nil end
        local b = res.readAll()
        res.close()
        return b
    end
    function self:vcmp(a,b)
        local function parts(v)
            local t = {}
            for n in tostring(v or "0"):gmatch("%d+") do t[#t+1] = tonumber(n) end
            return t
        end
        local A, B = parts(a), parts(b)
        local n = math.max(#A, #B)
        for i = 1, n do
            local x, y = A[i] or 0, B[i] or 0
            if x < y then return -1 elseif x > y then return 1 end
        end
        return 0
    end
    function self:loadLock()
        local s = self:readAll(self.lockPath); if not s then return nil end
        local obj = self:jsonD(s); if type(obj)~="table" then return nil end
        return obj
    end
    function self:saveLock(obj) self:writeAll(self.lockPath, self:jsonE(obj)) end
    return self
end

return Utilities