local Import = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer =  Players.LocalPlayer

local GetLocalVehiclePacket = require(ReplicatedStorage.Vehicle.VehicleUtils).GetLocalVehiclePacket

local function findFirstBasePart(model)
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            return descendant
        end
    end
    return nil
end

function WeldAllToPrimary(Model: Model)
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

function CleanRealModel(RealModel)
    for _, part in ipairs(RealModel:GetDescendants()) do
        if part:IsA("BasePart") then
            if part:IsA("MeshPart") then
                part.Transparency = 1
            end

            if part.Name == "Windows" then
                part.Size = Vector3.one * 0.001
            end

            part.Massless = true
            part.CanCollide = false
            part.CanTouch = false
        end
    end
end

function SetupLocalModel(LocalModel, RealModel)
    for _, obj in ipairs(LocalModel:GetDescendants()) do
        if obj.Name == "Wheels" then
            obj:Destroy()
        elseif obj:IsA("BasePart") then
            obj.CanCollide = false
            obj.Massless = false
            obj.CanTouch = false
        end
    end

    -- compute bounding box of the local model to create a primary part that
    -- envelopes the whole model and sits at its center
    local success, center, size = pcall(function()
        return LocalModel:GetBoundingBox()
    end)

    -- fallback if GetBoundingBox failed
    if not success or not center or not size then
        local fallbackPart = findFirstBasePart(LocalModel)
        if fallbackPart then
            center = fallbackPart.CFrame
            size = Vector3.new(1,1,1)
        else
            center = CFrame.new()
            size = Vector3.new(1,1,1)
        end
    end

    -- ensure minimum dimensions to avoid size zero
    local paddedSize = Vector3.new(
        math.max(0.1, size.X),
        math.max(0.1, size.Y),
        math.max(0.1, size.Z)
    )

    local Engine = Instance.new("Part")
    Engine.Name = "LocalCustomEngine"
    Engine.Size = paddedSize
    Engine.Transparency = 1
    Engine.CanCollide = false
    Engine.Massless = false
    Engine.Anchored = false
    Engine.CFrame = center
    Engine.Parent = LocalModel

    LocalModel.PrimaryPart = Engine
    LocalModel.Name = "LocalCustomModel"
    LocalModel.Parent = RealModel.Parent
end

function SetModelToEngine(LocalModel, RealModel)
    local LocalEngine = LocalModel.PrimaryPart
    if not LocalEngine then
        warn("Local custom model has no PrimaryPart")
        return
    end

    local RealEngine = RealModel.Parent:FindFirstChild("Engine")
    if not RealEngine then
        warn("Real vehicle engine part not found")
        return
    end
    -- copy physical properties from the real engine to preserve mass/density
    pcall(function()
        if RealEngine and RealEngine:IsA("BasePart") and LocalEngine and LocalEngine:IsA("BasePart") then
            local phys = RealEngine.CustomPhysicalProperties
            if phys then
                LocalEngine.CustomPhysicalProperties = phys
            end
            -- ensure local engine keeps mass
            LocalEngine.Massless = false
            LocalEngine.Transparency = 1
            LocalEngine.CanCollide = false
        end
    end)

    local MainWeld = Instance.new("Weld")
    MainWeld.Name = "CustomModelEngineWeld"
    MainWeld.Parent = LocalEngine
    MainWeld.Part0 = LocalEngine
    MainWeld.Part1 = RealEngine
    MainWeld.C0 = CFrame.new()
    MainWeld.C1 = CFrame.new()
end

function Import.applyOffsets(LocalModel, c0, c1)
    if not LocalModel then
        warn("Import.applyOffsets: LocalModel is nil")
        return
    end

    local primary = LocalModel.PrimaryPart
    if not primary then
        warn("Import.applyOffsets: LocalModel has no PrimaryPart")
        return
    end

    -- find the engine weld on the primary part
    local weld = primary:FindFirstChild("CustomModelEngineWeld")
    if not weld then
        -- try searching descendants
        for _, v in ipairs(primary:GetDescendants()) do
            if v:IsA("Weld") and v.Name == "CustomModelEngineWeld" then
                weld = v
                break
            end
        end
    end

    if not weld then
        warn("Import.applyOffsets: engine weld not found on local model")
        return
    end

    if c0 and typeof(c0) == "CFrame" then
        weld.C0 = c0
    end

    if c1 and typeof(c1) == "CFrame" then
        weld.C1 = c1
    end
end

function Import.applyScale(LocalModel, scale)
    if not LocalModel then return end
    scale = tonumber(scale) or 1
    if scale == 1 then return end

    -- Use the engine-provided scaling method only
    pcall(function()
        LocalModel:ScaleTo(scale)
    end)
end

function Import.import_Init(CustomModel)
    local RealModel : Model = GetLocalVehiclePacket().Model.Model
    if not CustomModel or not RealModel then return end
    CleanRealModel(RealModel)
    SetupLocalModel(CustomModel, RealModel)
    WeldAllToPrimary(CustomModel)
    SetModelToEngine(CustomModel, RealModel)
    
end

return Import