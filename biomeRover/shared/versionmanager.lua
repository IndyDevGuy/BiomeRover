-- /biomeRover/shared/versionmanager.lua
-- Exposes VERSION by reading the same text file used by your Pages workflow.
local VersionManager = {}

function VersionManager.new(registryManager)
    local self = {
        registryManager = registryManager,
        runBase = fs.getDir("")
    }

    function self:readVersion()
        -- Look for app_version.txt in sensible places
        local candidates = {
            self.registryManager.registry.utilities:combine(self.runBase, "app_version.txt"),
            "biomeRover/app_version.txt",
            "app_version.txt",
        }
        for _,p in ipairs(candidates) do
            if fs.exists(p) then
                local v = self.registryManager.registry.utilities:trim(self.registryManager.registry.utilities:readAll(p) or "")
                if v~="" then return v end
            end
        end
        return nil
    end
    return self
end
return VersionManager
