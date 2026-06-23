local base = "https://raw.githubusercontent.com/Kyariko/Mysterious-Importer-X/dev/Modules/"
local baserbxm = "https://raw.githubusercontent.com/Kyariko/Mysterious-Importer-X/dev/Modules/rbxm/"

local cache = {}

local localFolder = "MIX_CACHE"

if not isfolder(localFolder) then
    makefolder(localFolder)
end

local function loadRBXM(name)
    local path = "MIX_CACHE/" .. name .. ".rbxm"

    if not isfile(path) then
        local ok, data = pcall(function()
            return game:HttpGet(base .. name .. ".rbxm")
        end)

        if not ok then
            warn("Download failed:", name)
            return nil
        end

        writefile(path, data)
    end

    task.wait() -- 👈 important pour éviter race condition

    local ok, result = pcall(function()
        return game:GetObjects(getcustomasset(path))[1]
    end)

    if not ok then
        warn("RBXM load failed:", name, result)
        return nil
    end

    return result
end

local function loadModule(name)
    if cache[name] then
        return cache[name]
    end

    local success, code = pcall(function()
        return game:HttpGet(base .. name .. ".lua")
    end)

    if not success then
        warn("Failed to fetch module:", name)
        return nil
    end

    local fn, err = loadstring(code)
    if not fn then
        error("Compile error in " .. name .. ": " .. err)
    end

    local module = fn()
    cache[name] = module

    return module
end

local GUI = loadModule("GUI")
local Import = loadModule("Import")
local Custom = loadModule("Customization")

local App = {
    Import = Import,
    Customization = Custom
}

GUI.Bind(App)
GUI.Init_GUI(loadRBXM("UI"))