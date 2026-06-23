local Import = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer =  Players.LocalPlayer

local GetLocalVehiclePacket = require(ReplicatedStorage.Vehicle.VehicleUtils).GetLocalVehiclePacket

local wheelOffsetCache = setmetatable({}, {__mode = "k"})
local wheelScaleStates = setmetatable({}, {__mode = "k"})
local wheelScaleWatcherStarted = false
local RunService = game:GetService("RunService")

local function findFirstBasePart(model)
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            return descendant
        end
    end
    return nil
end

local function ensureLocalEngine(LocalModel)
    if not LocalModel then
        return nil
    end

    local engine = LocalModel:FindFirstChild("LocalCustomEngine")
    if engine and engine:IsA("BasePart") then
        LocalModel.PrimaryPart = engine
        return engine
    end

    local success, center, size = pcall(function()
        return LocalModel:GetBoundingBox()
    end)

    if not success or not center or not size then
        local fallbackPart = findFirstBasePart(LocalModel)
        if fallbackPart then
            center = fallbackPart.CFrame
            size = Vector3.new(1, 1, 1)
        else
            center = CFrame.new()
            size = Vector3.new(1, 1, 1)
        end
    end

    local paddedSize = Vector3.new(
        math.max(0.1, size.X),
        math.max(0.1, size.Y),
        math.max(0.1, size.Z)
    )

    engine = Instance.new("Part")
    engine.Name = "LocalCustomEngine"
    engine.Size = paddedSize
    engine.Transparency = 1
    engine.CanCollide = false
    engine.Massless = false
    engine.Anchored = false
    engine.CFrame = center
    engine.Parent = LocalModel

    LocalModel.PrimaryPart = engine
    return engine
end

local function findDescendantByName(root, name)
    if not root or type(name) ~= "string" then
        return nil
    end

    if root.Name == name then
        return root
    end

    for _, child in ipairs(root:GetDescendants()) do
        if child.Name == name then
            return child
        end
    end

    return nil
end

local function getActualVehicleModels()
    local packet = GetLocalVehiclePacket()
    if not packet or not packet.Model then
        return nil, nil
    end

    local wrapper = packet.Model
    local actual = wrapper
    if wrapper:FindFirstChild("Model") and wrapper.Model:IsA("Model") then
        actual = wrapper.Model
    end

    return wrapper, actual
end

function CleanRealModel(RealModel)
    local preset = findDescendantByName(RealModel, "Preset")
    for _, part in ipairs(RealModel:GetDescendants()) do
        if part:IsA("BasePart") then
            if not (preset and part:IsDescendantOf(preset)) then
                part.Transparency = 1
                if part.Name == "Windows" then
                    part.Size = Vector3.one * 0.001
                end
            end
        end
    end
end

function SetupLocalModel(LocalModel, wrapperModel, RealModel)
    local wheelsFolder = LocalModel:FindFirstChild("Wheels", true)
    for _, obj in ipairs(LocalModel:GetDescendants()) do
        if obj:IsA("BasePart") then
            obj.CanCollide = false
            obj.Massless = false
            obj.CanTouch = false
        end
    end

    local Engine = ensureLocalEngine(LocalModel)
    if not Engine then
        warn("SetupLocalModel: failed to create local engine")
        return
    end

    LocalModel.Name = "LocalCustomModel"

    if wheelsFolder then
        local wheelOffsets = {}
        for _, localWheel in ipairs(wheelsFolder:GetChildren()) do
            if localWheel:IsA("Model") or localWheel:IsA("BasePart") then
                local success, pivot = pcall(function()
                    return localWheel:GetPivot()
                end)
                if success and pivot then
                    wheelOffsets[localWheel.Name] = Engine.CFrame:ToObjectSpace(pivot)
                end
            end
        end
        if not next(wheelOffsets) then
            warn("SetupLocalModel: Wheels folder found but no valid wheel markers were cached")
        end
        wheelOffsetCache[LocalModel] = wheelOffsets
        -- Keep the Wheels markers in the LocalModel so sync can use exact marker pivots.
        -- Make marker parts invisible and non-colliding instead of destroying them.
        for _, desc in ipairs(wheelsFolder:GetDescendants()) do
            if desc:IsA("BasePart") then
                desc.Transparency = 1
                desc.CanCollide = false
                desc.CanTouch = false
            end
        end
    else
        warn("SetupLocalModel: no Wheels folder found in local model")
    end

    LocalModel.Parent = wrapperModel
end

function WeldAllToPrimary(Model)
    local PrimaryPart = Model.PrimaryPart or findFirstBasePart(Model)
    if not PrimaryPart then
        warn("No PrimaryPart set or found for model")
        return
    end

    for _, part in ipairs(Model:GetDescendants()) do
        if part:IsA("BasePart") and part ~= PrimaryPart then
            part.Anchored = false

            local weld = Instance.new("Weld")
            weld.Name = part.Name .. "_Weld"
            weld.Part0 = PrimaryPart
            weld.Part1 = part

            weld.C0 = PrimaryPart.CFrame:ToObjectSpace(part.CFrame)
            weld.C1 = CFrame.new()

            weld.Parent = PrimaryPart
        end
    end
end

function Import.import_Init(LocalModel)
    local wrapperModel, RealModel = getActualVehicleModels()
    if not LocalModel or not wrapperModel or not RealModel then
        return
    end

    CleanRealModel(wrapperModel)
    SetupLocalModel(LocalModel, wrapperModel, RealModel)

    local realPrimary = RealModel.PrimaryPart or findFirstBasePart(RealModel)
    if realPrimary and LocalModel.PrimaryPart then
        pcall(function()
            LocalModel:SetPrimaryPartCFrame(realPrimary.CFrame)
        end)
    end

    WeldAllToPrimary(LocalModel)
    SetModelToEngine(LocalModel, RealModel)
end

local function scaleCFrame(cframe, scale)
    if typeof(cframe) ~= "CFrame" or type(scale) ~= "number" then
        return cframe
    end

    local right = cframe.RightVector * scale
    local up = cframe.UpVector * scale
    local look = cframe.LookVector * scale
    local pos = cframe.Position * scale

    return CFrame.fromMatrix(pos, right, up, look)
end

local function ensureModelPrimaryPart(model)
    if not model or not model:IsA("Model") then
        return nil
    end

    if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
        return model.PrimaryPart
    end

    local part = findFirstBasePart(model)
    if part then
        model.PrimaryPart = part
    end
    return model.PrimaryPart
end

local function applyWheelScaleToModel(wheelModel, scale)
    if not wheelModel or scale == nil then
        return
    end

    scale = tonumber(scale) or 1
    if scale == 1 then
        return
    end

    ensureModelPrimaryPart(wheelModel)
    pcall(function()
        wheelModel:ScaleTo(scale)
    end)
end

local function getWheelScaleValues(values)
    if not values then
        return nil
    end

    return {
        FL = tonumber(values.FL_S) or 1,
        FR = tonumber(values.FR_S) or 1,
        RL = tonumber(values.RL_S) or 1,
        RR = tonumber(values.RR_S) or 1,
    }
end

local function getWheelScaleNames()
    return {
        FL = "WheelFrontLeft",
        FR = "WheelFrontRight",
        RL = "WheelBackLeft",
        RR = "WheelBackRight",
    }
end

local function findWheelModel(wrapperModel, RealModel, wheelName)
    if wrapperModel then
        local wheel = findDescendantByName(wrapperModel, wheelName)
        if wheel then
            return wheel
        end
    end

    if RealModel then
        local wheel = findDescendantByName(RealModel, wheelName)
        if wheel then
            return wheel
        end
    end

    if wrapperModel and wrapperModel.Parent then
        local wheel = findDescendantByName(wrapperModel.Parent, wheelName)
        if wheel then
            return wheel
        end
    end

    return nil
end

local function applyWheelScales(LocalModel, values)
    if not LocalModel or not values then
        return
    end

    local wrapperModel, RealModel = getActualVehicleModels()
    if not wrapperModel or not RealModel then
        return
    end

    local scaleValues = getWheelScaleValues(values)
    local names = getWheelScaleNames()

    local store = {}
    for localName, realName in pairs(names) do
        local wheelModel = findWheelModel(wrapperModel, RealModel, realName)
        if wheelModel then
            local scale = scaleValues[localName] or 1
            applyWheelScaleToModel(wheelModel, scale)
            store[localName] = scale
        end
    end

    if next(store) then
        wheelScaleStates[LocalModel] = store
        if not wheelScaleWatcherStarted then
            wheelScaleWatcherStarted = true
            local elapsed = 0
            RunService.Heartbeat:Connect(function(dt)
                elapsed = elapsed + dt
                if elapsed < 0.25 then
                    return
                end
                elapsed = 0
                for trackedModel, scales in pairs(wheelScaleStates) do
                    if not trackedModel or not trackedModel.Parent then
                        wheelScaleStates[trackedModel] = nil
                    else
                        local wrapper, real = getActualVehicleModels()
                        if wrapper or real then
                            for localName, scaleValue in pairs(scales) do
                                local wheelModel = findWheelModel(wrapper, real, names[localName])
                                if wheelModel then
                                    applyWheelScaleToModel(wheelModel, scaleValue)
                                end
                            end
                        end
                    end
                end
            end)
        end
    end
end

-- helper: hide all BasePart visuals (no longer used)

function SetModelToEngine(LocalModel, RealModel)
    local LocalEngine = LocalModel.PrimaryPart
    if not LocalEngine then
        warn("Local custom model has no PrimaryPart")
        return
    end

    local RealEngine = RealModel.PrimaryPart or findDescendantByName(RealModel, "Engine")
    if not RealEngine and RealModel.Parent then
        RealEngine = findDescendantByName(RealModel.Parent, "Engine")
    end
    if not RealEngine or not RealEngine:IsA("BasePart") then
        RealEngine = findFirstBasePart(RealModel)
        if RealEngine then
            warn("SetModelToEngine: Engine part not found, falling back to real primary/base part")
        end
    end
    if not RealEngine or not RealEngine:IsA("BasePart") then
        warn("Real vehicle engine part not found or unsuitable")
        return
    end
    -- copy physical properties from the real engine to preserve mass/density
    pcall(function()
        if LocalEngine and LocalEngine:IsA("BasePart") then
            local phys = RealEngine.CustomPhysicalProperties
            if phys then
                LocalEngine.CustomPhysicalProperties = phys
            end
            LocalEngine.Massless = false
            LocalEngine.Transparency = 1
            LocalEngine.CanCollide = false
            LocalEngine.CanTouch = false
        end
    end)

    local MainWeld = Instance.new("Weld")
    MainWeld.Name = "CustomModelEngineWeld"
    -- Parent to RealEngine to keep the real part authoritative
    MainWeld.Parent = RealEngine
    -- Make the real engine the Part0 so it remains fixed; local engine is Part1
    MainWeld.Part0 = RealEngine
    MainWeld.Part1 = LocalEngine
    -- Preserve current world-space relationship between the two parts
    MainWeld.C0 = CFrame.new()
    local ok, c1 = pcall(function()
        return LocalEngine.CFrame:ToObjectSpace(RealEngine.CFrame)
    end)
    if ok and c1 then
        MainWeld.C1 = c1
    else
        MainWeld.C1 = CFrame.new()
    end
end

local function findEngineWeld(LocalModel)
    if not LocalModel then
        return nil
    end

    for _, descendant in ipairs(LocalModel:GetDescendants()) do
        if descendant:IsA("Weld") and descendant.Name == "CustomModelEngineWeld" then
            return descendant
        end
    end

    local wrapperModel, RealModel = getActualVehicleModels()
    if RealModel then
        for _, descendant in ipairs(RealModel:GetDescendants()) do
            if descendant:IsA("Weld") and descendant.Name == "CustomModelEngineWeld" then
                return descendant
            end
        end
        if wrapperModel then
            for _, descendant in ipairs(wrapperModel:GetDescendants()) do
                if descendant:IsA("Weld") and descendant.Name == "CustomModelEngineWeld" then
                    return descendant
                end
            end
        end
    end

    return nil
end

function Import.applyScale(LocalModel, scale)
    if not LocalModel then return end
    scale = tonumber(scale) or 1
    if scale == 1 then return end

    -- Use the engine-provided scaling method only
    pcall(function()
        LocalModel:ScaleTo(scale)
    end)

    local engine = LocalModel:FindFirstChild("LocalCustomEngine")
    if engine and engine:IsA("BasePart") then
        LocalModel.PrimaryPart = engine
    end

    local offsets = wheelOffsetCache[LocalModel]
    if offsets and type(scale) == "number" then
        for key, offset in pairs(offsets) do
            offsets[key] = scaleCFrame(offset, scale)
        end
    end
end

function Import.applyOffsets(LocalModel, c0, c1)
    if not LocalModel then
        warn("Import.applyOffsets: LocalModel is nil")
        return
    end

    local weld = findEngineWeld(LocalModel)
    if not weld then
        warn("Import.applyOffsets: engine weld not found on local model")
        return
    end

    local localEngine = LocalModel:FindFirstChild("LocalCustomEngine", true) or LocalModel.PrimaryPart

    if c0 and typeof(c0) == "CFrame" then
        if weld.Part1 == localEngine then
            weld.C1 = weld.C1 * c0
        elseif weld.Part0 == localEngine then
            weld.C0 = weld.C0 * c0
        else
            warn("Import.applyOffsets: local engine not found on engine weld")
        end
    end

    if c1 and typeof(c1) == "CFrame" then
        if weld.Part1 == localEngine then
            weld.C1 = c1
        elseif weld.Part0 == localEngine then
            weld.C0 = c1
        else
            warn("Import.applyOffsets: local engine not found on engine weld")
        end
    end
end

function Import.syncWheelOffsets(LocalModel, values)
    if not LocalModel then
        warn("Import.syncWheelOffsets: LocalModel is nil")
        return
    end

    local offsets = wheelOffsetCache[LocalModel]
    if not offsets or not next(offsets) then
        warn("Import.syncWheelOffsets: no cached wheel offsets for local model")
        return
    end

    local wrapperModel, RealModel = getActualVehicleModels()
    if not wrapperModel or not RealModel then
        warn("Import.syncWheelOffsets: unable to get packet model")
        return
    end

    local localPrimary = LocalModel.PrimaryPart or findFirstBasePart(LocalModel)
    if not localPrimary then
        warn("Import.syncWheelOffsets: local model has no primary part")
        return
    end

    local realPrimary = RealModel.PrimaryPart or findFirstBasePart(RealModel)
    if not realPrimary then
        warn("Import.syncWheelOffsets: real model has no primary part")
        return
    end

    local preset = findDescendantByName(wrapperModel, "Preset") or findDescendantByName(RealModel, "Preset")
    if not preset then
        warn("Import.syncWheelOffsets: real preset not found")
        return
    end

    local mapping = {
        FL = "WheelFrontLeft",
        FR = "WheelFrontRight",
        RL = "WheelBackLeft",
        RR = "WheelBackRight",
    }

    if values then
        applyWheelScales(LocalModel, values)
    end

    for localName, localOffset in pairs(offsets) do
        local realName = mapping[localName] or localName
        local realWheel = findDescendantByName(preset, realName)
        if not realWheel then
            warn("Import.syncWheelOffsets: real wheel model not found for", realName)
            continue
        end

        local thrust = realWheel:FindFirstChild("Thrust", true)
        if not thrust or not thrust:IsA("BasePart") then
            warn("Import.syncWheelOffsets: Thrust part missing for", realName)
            continue
        end

        local weld = thrust:FindFirstChild("Weld", true)
        if not weld or not weld:IsA("Weld") then
            warn("Import.syncWheelOffsets: Weld missing in Thrust for", realName)
            continue
        end

        local uiOffset = Vector3.new()
        if values then
            local delta = tonumber(values[localName .. "_O"]) or 0
            uiOffset = Vector3.new(0, delta, 0)
        end

        -- Try to find an explicit marker under LocalModel.Wheels matching the local wheel name
        local markerWorld = nil
        local wheelsFolder = LocalModel:FindFirstChild("Wheels", true)
        if wheelsFolder then
            local marker = wheelsFolder:FindFirstChild(localName, true)
            if not marker then
                marker = LocalModel:FindFirstChild(localName, true)
            end
            if marker then
                if marker:IsA("Model") then
                    local ok, pivot = pcall(function() return marker:GetPivot() end)
                    if ok and pivot then
                        markerWorld = pivot
                    end
                elseif marker:IsA("BasePart") then
                    markerWorld = marker.CFrame
                end
            end
        end

        local desiredWorld
        if markerWorld then
            desiredWorld = markerWorld * CFrame.new(uiOffset)
        else
            local offset = localOffset * CFrame.new(uiOffset)
            desiredWorld = localPrimary.CFrame * offset
        end

        -- Compute weld transforms so that the thrust part ends up at desiredWorld.
        local applied = false

        local function safeSetC0(w, cf)
            pcall(function() w.C0 = cf end)
        end

        local function safeSetC1(w, cf)
            pcall(function() w.C1 = cf end)
        end

        -- If the weld's Part0 is the thrust, compute C0 such that Part0 becomes desiredWorld:
        -- desiredWorld * C0 = Part1.CFrame * C1  => C0 = desiredWorld:ToObjectSpace(Part1.CFrame * C1)
        if weld.Part0 == thrust then
            if weld.Part1 and weld.Part1:IsA("BasePart") then
                local ok, newC0 = pcall(function()
                    return desiredWorld:ToObjectSpace(weld.Part1.CFrame * weld.C1)
                end)
                if ok and newC0 then
                    safeSetC0(weld, newC0)
                    applied = true
                end
            end
        end

        -- If the weld's Part1 is the thrust, compute C1 such that Part1 becomes desiredWorld:
        -- Part0.CFrame * C0 = desiredWorld * C1  => C1 = desiredWorld:ToObjectSpace(Part0.CFrame * C0)
        if not applied and weld.Part1 == thrust then
            if weld.Part0 and weld.Part0:IsA("BasePart") then
                local ok, newC1 = pcall(function()
                    return desiredWorld:ToObjectSpace(weld.Part0.CFrame * weld.C0)
                end)
                if ok and newC1 then
                    safeSetC1(weld, newC1)
                    applied = true
                end
            end
        end

        -- Fallback: if neither end exactly matches the thrust, attempt to place Part1 at desiredWorld
        if not applied and weld.Part0 and weld.Part1 then
            if weld.Part0:IsA("BasePart") and weld.Part1:IsA("BasePart") then
                local ok, newC1 = pcall(function()
                    return desiredWorld:ToObjectSpace(weld.Part0.CFrame * weld.C0)
                end)
                if ok and newC1 then
                    safeSetC1(weld, newC1)
                    applied = true
                end
            end
        end

        if not applied then
            warn("Import.syncWheelOffsets: failed to apply weld transform for", realName)
        end
    end
end

return Import