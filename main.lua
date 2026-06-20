local cache = {}

local function import(file)
    if cache[file] then
        return cache[file]
    end

    local code = readfile(file)
    local fn = loadstring(code)

    local result = fn()
    cache[file] = result

    return result
end

local GUI = import("Mysterious Importer X/GUI.lua")
local Import_Module = import("Mysterious Importer X/Import.lua")
local Customization_Module = import("Mysterious Importer X/Customization.lua")

local App = {
    Import = Import_Module,
    Customization = Customization_Module
}

GUI.Bind(App)
GUI.Init_GUI()