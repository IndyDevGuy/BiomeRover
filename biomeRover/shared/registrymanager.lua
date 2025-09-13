local RegistryManager = {}

function RegistryManager.new()
    local self = {
        moduleRegistry = {},
        registry = {},
        registry_mt = {}
    }

    function self:setupRegistry()

        self.registry_mt = {
            __index = function(table, key)
                -- This function is called when an undefined key is accessed (like __get)
                if self.moduleRegistry[key] then
                    return self.moduleRegistry[key] -- Return the registered module
                else
                    -- Handle cases where the module is not found (e.g., return nil or an error)
                    return nil
                end
            end,
            __newindex = function(table, key, value)
                -- This function is called when an undefined key is assigned a value (like __set)
                self.moduleRegistry[key] = value -- Store the module in the registry
            end
        }

        self.registry = setmetatable({}, self.registry_mt)
    end

    self:setupRegistry()

    return self
end

return RegistryManager