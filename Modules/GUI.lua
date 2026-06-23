local GUI = {}

local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")
local LocalPlayer =  Players.LocalPlayer
local ContextActionService = game:GetService("ContextActionService")


local dragStart
local startPos
local dragFrame
local Hold = false

GUI.Values = {
    CarID = "",
    RimID = "",

    File = "",

    FR_O = 0,
    FL_O = 0,
    RL_O = 0,
    RR_O = 0,
    MAIN_O = 0,

    FR_S = 0,
    FL_S = 0,
    RL_S = 0,
    RR_S = 0,
    MAIN_S = 0,

    A_Spoiler = false,
    Turbine = false,
}

GUI.App = {}

local viewportCamera
local viewportTarget = Vector3.new()
local viewportDistance = 20
local viewportYaw = 0
local viewportPitch = math.rad(20)
local viewportDragging = false
local viewportDragStart = Vector2.new()
local viewportYawStart = 0
local viewportPitchStart = 0
local viewportMinDistance = 4
local viewportMaxDistance = 120

local function findViewport(UI)
    for _, item in ipairs(UI:GetDescendants()) do
        if item:IsA("ViewportFrame") then
            return item
        end
    end
    return nil
end

local function setupViewport(viewport)
    if not viewport then
        return nil
    end

    local camera = viewport:FindFirstChild("ViewportCamera")
    if not camera then
        camera = Instance.new("Camera")
        camera.Name = "ViewportCamera"
        camera.Parent = viewport
    end

    viewport.CurrentCamera = camera
    viewportCamera = camera
    return camera
end

local function clearViewportContents(viewport)
    if not viewport then
        return
    end

    for _, child in ipairs(viewport:GetChildren()) do
        if not child:IsA("Camera") then
            child:Destroy()
        end
    end
end

local function updateViewportModel(viewport, model)
    if not viewport or not model then
        return
    end

    setupViewport(viewport)
    clearViewportContents(viewport)

    local clone = model:Clone()
    clone.Parent = viewport

    local success, center, size = pcall(function()
        return clone:GetBoundingBox()
    end)

    if success and center and size then
        viewportTarget = center.Position
        viewportDistance = math.clamp(math.max(size.X, size.Y, size.Z) * 1.75, viewportMinDistance, viewportMaxDistance)
        viewportYaw = 0
        viewportPitch = math.rad(20)

        local offset = Vector3.new(0, math.max(size.Y, 4) * 0.75 + 1.5, viewportDistance)
        viewport.CurrentCamera.CFrame = CFrame.lookAt(viewportTarget + offset, viewportTarget)
        viewport.CurrentCamera.Focus = CFrame.new(viewportTarget)
    end
end

local function tryPreviewCarID(viewport, carId)
    if not viewport then
        warn("ViewportFrame not found in UI")
        return
    end

    if carId == "" or not GUI.App.LoadVehicle then
        return
    end

    local model = GUI.App.LoadVehicle(carId)
    if model then
        updateViewportModel(viewport, model)
    else
        warn("Vehicle preview failed for CarID:", carId)
    end
end

function GUI.Bind(depends)
    GUI.App = depends
end

function Drag(frame)
    Hold = true
    dragStart = UIS:GetMouseLocation()
    startPos = frame.Position
    dragFrame = frame
end

function GUI.Init_GUI(UI : ScreenGui)
    UI.Parent = LocalPlayer.PlayerGui

    UI.Main.Top.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            Drag(UI.Main)
        end
    end)

    UI.Main.Top.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            Hold = false
        end
    end)

    UIS.InputChanged:Connect(function(input)
        if Hold and dragFrame and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = UIS:GetMouseLocation() - dragStart

            dragFrame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)

    local viewport = findViewport(UI)

    for i,v in ipairs(UI:GetDescendants()) do
        if v:IsA("TextBox") then
            v.FocusLost:Connect(function(enterPressed)
                GUI.Values[v.Parent.Name] = v.Text
                if v.Parent.Name == "CarID" then
                    tryPreviewCarID(viewport, v.Text)
                end
            end)
        end
    end

    if viewport then
        viewport.MouseEnter:Connect(function()
            ContextActionService:BindAction("ViewportBlockMouse", function() return Enum.ContextActionResult.Sink end, false,
                Enum.UserInputType.MouseMovement,
                Enum.UserInputType.MouseButton1,
                Enum.UserInputType.MouseButton2,
                Enum.UserInputType.MouseWheel)
        end)

        viewport.MouseLeave:Connect(function()
            ContextActionService:UnbindAction("ViewportBlockMouse")
        end)
        local inputBegan = viewport.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                viewportDragging = true
                viewportDragStart = UIS:GetMouseLocation()
                viewportYawStart = viewportYaw
                viewportPitchStart = viewportPitch
            end
        end)

        local inputEnded = viewport.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                viewportDragging = false
            end
        end)

        UIS.InputChanged:Connect(function(input)
            if viewportDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local delta = UIS:GetMouseLocation() - viewportDragStart
                viewportYaw = viewportYawStart - delta.X * 0.003
                viewportPitch = math.clamp(viewportPitchStart + delta.Y * 0.003, math.rad(-80), math.rad(80))
                if viewportCamera then
                      local offsetVec = (CFrame.Angles(viewportPitch, viewportYaw, 0) * Vector3.new(0, 0, viewportDistance))
                      viewportCamera.CFrame = CFrame.lookAt(viewportTarget + offsetVec, viewportTarget)
                end
            end
        end)

        UIS.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseWheel then
                viewportDistance = math.clamp(viewportDistance - input.Position.Z * 2, viewportMinDistance, viewportMaxDistance)
                if viewportCamera then
                    local offsetVec = (CFrame.Angles(viewportPitch, viewportYaw, 0) * Vector3.new(0, 0, viewportDistance))
                    viewportCamera.CFrame = CFrame.lookAt(viewportTarget + offsetVec, viewportTarget)
                end
            end
        end)
    end

    local function refreshGuiValues()
        for _, item in ipairs(UI:GetDescendants()) do
            if item:IsA("TextBox") and item.Parent then
                GUI.Values[item.Parent.Name] = item.Text
            end
        end
    end

    UI.Main.Top.Import.InputBegan:Connect(function(Input)
        if Input.UserInputType == Enum.UserInputType.MouseButton1 then
            refreshGuiValues()

            local model = GUI.App.LoadVehicle and GUI.App.LoadVehicle(UI.Main.CarID.Input.Text)
            GUI.App.Import.import_Init(model)
            -- MAIN_S is the model scale; apply it first, then apply MAIN_O as a vertical offset
            if model and GUI.App.Import and GUI.Values then
                local scale = tonumber(GUI.Values.MAIN_S) or 1
                pcall(function()
                    GUI.App.Import.applyScale(model, scale)
                end)

                local yOffset = tonumber(GUI.Values.MAIN_O) or 0
                local offsetCFrame = CFrame.new(0, yOffset, 0)
                pcall(function()
                    GUI.App.Import.applyOffsets(model, offsetCFrame)
                end)

                pcall(function()
                    GUI.App.Import.syncWheelOffsets(model, GUI.Values)
                end)
            end
        end
    end)

    UI.Main.Exit.InputBegan:Connect(function(Input)
        if Input.UserInputType == Enum.UserInputType.MouseButton1 then
            UI.Main.Visible = false
        end
    end)
    
    UI.Open.InputBegan:Connect(function(Input)
        if Input.UserInputType == Enum.UserInputType.MouseButton1 then
            UI.Main.Visible = true
        end
    end)
    
    for i,v in ipairs(UI:GetDescendants()) do
        if v:IsA("TextButton") then
            if v:FindFirstChildOfClass("BoolValue") and v:FindFirstChild("Toggle") then
                v.MouseButton1Click:Connect(function()
                    GUI.Values[v.Name] = not GUI.Values[v.Name]
                    v.TextColor3 = GUI.Values[v.Name] and Color3.fromRGB(133, 255, 163) or Color3.fromRGB(255, 111, 111)
                end)
            end
        end
    end
end

return GUI
