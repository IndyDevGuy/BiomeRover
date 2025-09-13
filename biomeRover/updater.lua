-- updater.lua — update BiomeRover from GitHub Pages manifest with versioning
-- Usage:
--   updater
-- Flags:
--   --force                  -- overwrite even if versions match
--   --check                  -- just print versions and exit
local registryManager = require("shared/registrymanager")
local utilityManager = require("shared/utilities")
local versionManager = require("shared/versionmanager")
local manifestManager = require("shared/manifestmanager")

local args = {...}
local FORCE, CHECK = false, false
for i = #args, 1, -1 do
    if args[i] == "--force" then FORCE = true; table.remove(args, i)
    elseif args[i] == "--check" then CHECK = true; table.remove(args, i)
    end
end

local function pathFromUrl(url)
    local rel = url:match("^https?://raw%.githubusercontent%.com/[^/]+/[^/]+/[^/]+/(.+)$")
            or url:match("^https?://github%.com/[^/]+/[^/]+/raw/[^/]+/(.+)$")
            or url:match("/(biomeRover/.+)$")
            or ("biomeRover/"..(url:match("/([^/]+)$") or "downloaded.file"))
    return rel
end

-- make registry class (factory)
local registryMngr = registryManager.new()

registryMngr.registry.utilities = utilityManager.new()
registryMngr.registry.manifestManager = manifestManager.new(registryMngr)
registryMngr.registry.versionManager = versionManager.new(registryMngr)
-- ---------- choose manifest URL ----------

local installedVersion = registryMngr.registry.versionManager:readVersion()
if not installedVersion then
    local lock=registryMngr.registry.utilities:loadLock(); installedVersion = (lock and lock.version) or "0.0.0"
end

--- latest version from Pages app.json (if present) ---
local latestVersion = registryMngr.registry.manifestManager.latestVersion

local manifestUrl
local lock = registryMngr.registry.utilities:loadLock()
if lock then
    manifestUrl = lock.manifest_url
elseif not lock or not lock.manifest_url then
    manifestUrl = registryMngr.registry.manifestManager.latestManifestUrl
end
local latestManifestUrl = manifestUrl

-- Fallback if app.json missing
if not latestVersion then latestVersion = "0.0.0" end

print(("Installed version: %s"):format(installedVersion))
print(("Available  version: %s"):format(latestVersion))

if CHECK and not FORCE then return end
if not FORCE and registryMngr.registry.utilities:vcmp(installedVersion, latestVersion) >= 0 then
    print("Already up to date. Use --force to re-install.")
    return
end

-- ---------- update using manifest ----------
print("Fetching manifest: "..latestManifestUrl)
local items = registryMngr.registry.manifestManager.items
assert(type(items)=="table","Invalid manifest JSON")

-- Build sets for cleanup
local newList, newSet = {}, {}
for _,url in ipairs(items) do
    if type(url)=="string" then
        local path = pathFromUrl(url)
        newList[#newList+1] = {url=url, path=path}
        newSet[path] = true
    end
end

local prevSet = {}
if prev and prev.files then for _,p in ipairs(prev.files) do prevSet[p]=true end end

local created, updated, skipped = 0,0,0
for i,it in ipairs(newList) do
    local path, url = it.path, it.url
    local needs = FORCE or (not fs.exists(path))
    local remote
    if not needs then
        remote = registryMngr.registry.utilities:fetch(url)
        if registryMngr.registry.utilities:readAll(path) ~= remote then needs = true end
    end
    if needs then
        remote = remote or registryMngr.registry.utilities:fetch(url)
        registryMngr.registry.utilities:writeAll(path, remote)
        if prevSet[path] then updated=updated+1 else created=created+1 end
        print("updated: "..path)
    else
        skipped=skipped+1
    end
end

-- Remove files no longer in manifest (safety: only under biomeRover/)
local removed = 0
for p,_ in pairs(prevSet) do
    if not newSet[p] and p:sub(1,4)=="biomeRover/" and fs.exists(p) then
        fs.delete(p); removed=removed+1; print("removed: "..p)
    end
end

-- Save lock with latest version
registryMngr.registry.utilities:saveLock({
    manifest_url = latestManifestUrl,
    version      = latestVersion,
    files        = (function(t) local r={} for _,it in ipairs(newList) do r[#r+1]=it.path end return r end)()
})

print(("-- done --\ncreated: %d  updated: %d  skipped: %d  removed: %d"):format(created, updated, skipped, removed))
print("Run: /biomeRover/control.lua for control computer.")
print("Run: /biomeRover/leader.lua for leader turtle.")
print("Run: /biomeRover/miner.lua for miner turtle.")
print("Run: /biomeRover/follower.lua for follower turtle.")
