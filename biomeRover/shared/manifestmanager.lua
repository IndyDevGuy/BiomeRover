-- urc/manifestmanager.lua
local ManifestManager = {}

function ManifestManager.new(registryManager)
    local self = {
        registryManager    = registryManager,
        manifestUrl        = "https://IndyDevGuy.github.io/BiomeRover/manifest.json",
        latestVersion      = nil,
        latestManifestUrl  = nil,
        builtAt            = nil,
        commit             = nil,
        items              = nil,
    }

    function self:baseFromManifest()
        return (self.manifestUrl:gsub("/manifest%.json$", ""))
    end

    function self:appJsonFromManifest()
        return self:baseFromManifest() .. "/app.json"
    end

    function self:setManifestItems()
        self.items = registryManager.registry.utilities:jsonD(registryManager.registry.utilities:fetch(self.manifestUrl))
    end

    function self:setData()
        local data = registryManager.registry.utilities:fetch(self:appJsonFromManifest())
        if not data then return end
        local app = registryManager.registry.utilities:jsonD(data)
        if type(app) == "table" then
            self.latestVersion     = app.version
            self.latestManifestUrl = app.manifest_url
            self.builtAt           = app.built_at
            self.commit            = app.commit
        end
    end

    self:setData()
    self:setManifestItems()
    return self
end

return ManifestManager