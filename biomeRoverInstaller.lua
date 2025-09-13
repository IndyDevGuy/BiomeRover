-- install.lua (self-updating)  — CC:Tweaked / ComputerCraft
-- Usage:
--   install
-- Flags:
--   --noupdate   Skip the self-update check (used internally after updating)
--
local VERSION = "0.0.01"

local args = {...}

-- -------------- small arg/flag parser
local flags = {}
for i=#args,1,-1 do
    if args[i]:sub(1,2) == "--" then flags[args[i]] = true; table.remove(args,i) end
end

local function usage()
    print("Usage:")
    print(" install")
end

-- -------------- helpers
local function fetch(url)
    if not http then error("HTTP API is disabled in the CC config") end
    local ok, res = pcall(http.get, url)
    if not ok or not res then error("HTTP GET failed: "..tostring(url)) end
    local body = res.readAll(); res.close(); return body
end

local function ensureDir(path)
    local dir = fs.getDir(path)
    if dir and dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
end

local function writeAll(path, data)
    ensureDir(path)
    local f = fs.open(path, "w"); if not f then error("Cannot write "..path) end
    f.write(data); f.close()
end

local function readAll(path)
    local f = fs.open(path, "r"); if not f then return nil end
    local s = f.readAll(); f.close(); return s
end

local function jsonDecode(s)
    local dec = textutils.unserialiseJSON or textutils.unserializeJSON
    local ok, v = pcall(dec, s); if not ok then return nil end; return v
end

local function jsonEncode(t)
    local enc = textutils.serialiseJSON or textutils.serializeJSON
    return enc(t, true)
end

local function pagesBaseFromManifest(url)
    -- turn https://user.github.io/repo/manifest.json -> https://user.github.io/repo
    return (url:gsub("/manifest%.json$",""))
end

local function manifestUrlFrom(owner, repo)
    return ("https://%s.github.io/%s/manifest.json"):format(owner, repo)
end

local function installerJsonFrom(manifestUrl)
    return manifestUrl:gsub("/manifest%.json$","/installer.json")
end

local function pathFromUrl(url)
    -- Prefer raw.githubusercontent.com …/<sha>/<path>
    local p = url:match("^https?://raw%.githubusercontent%.com/[^/]+/[^/]+/[^/]+/(.+)$")
            or url:match("^https?://github%.com/[^/]+/[^/]+/raw/[^/]+/(.+)$")
            or url:match("/(biomeRover/.+)$")
            or url:match("/([^/]+)$")
    return p or "downloaded.file"
end

local function vcmp(a,b)
    local function split(v)
        local t={} ; for part in tostring(v):gmatch("[0-9]+") do t[#t+1]=tonumber(part) end
        return t
    end
    local A,B=split(a),split(b)
    local n=math.max(#A,#B)
    for i=1,n do
        local x=A[i] or 0; local y=B[i] or 0
        if x<y then return -1 elseif x>y then return 1 end
    end
    return 0
end

-- -------------- derive manifest URL
local manifestUrl = manifestUrlFrom("indydevguy", "BiomeRover")

-- -------------- self-update (once)
if not flags["--noupdate"] then
    local ij = installerJsonFrom(manifestUrl)
    local ok, data = pcall(fetch, ij)
    if ok and data then
        local obj = jsonDecode(data)
        if type(obj)=="table" and obj.version and obj.url then
            if vcmp(VERSION, obj.version) < 0 then
                print("Installer update found "..VERSION.." -> "..obj.version..", updating...")
                local newCode = fetch(obj.url)
                local me = shell.getRunningProgram()
                writeAll(me, newCode)
                print("Installer updated. Restarting...")
                -- re-run with same args but skip re-check to avoid loop
                local cmd = me.." --noupdate "..table.concat(args," ")
                shell.run(cmd)
                return
            end
        end
    end
end

-- -------------- install via manifest
print("Fetching manifest: "..manifestUrl)
local raw = fetch(manifestUrl)
local items = jsonDecode(raw)
if type(items) ~= "table" then error("Manifest is not valid JSON array") end

-- download all files
local installed = {}
for i,url in ipairs(items) do
    if type(url) == "string" then
        local path = pathFromUrl(url)
        write((" [%2d/%2d] %s\n   -> %s"):format(i, #items, url, path))
        local content = fetch(url)
        writeAll(path, content)
        installed[#installed+1] = path
    end
end

-- fetch app.json to record version in lock
local function appJsonFrom(manifestUrl) return manifestUrl:gsub("/manifest%.json$","/app.json") end
local ver = "0.0.0"
local ok, aj = pcall(fetch, appJsonFrom(manifestUrl))
if ok and aj then
    local o = jsonDecode(aj); if type(o)=="table" and o.version then ver = o.version end
end

-- write a lock for updater.lua to use later
writeAll("biomeRover/.manifest.lock", jsonEncode({
    manifest_url = manifestUrl,
    version      = ver,
    files        = installed
}))

print("Done. Run:")
print("/biomeRover/control.lua for the control computer.")
print("/biomeRover/leader.lua for the leader turtle.")
print("/biomeRover/miner.lua  for the miner turtle.")
print("/biomeRover/follower.lua for the follower turtle.")
print("Version: "..ver)
