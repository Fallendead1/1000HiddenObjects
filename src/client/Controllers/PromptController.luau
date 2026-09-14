--[[
	Interaction prompts in the game's style. Every ProximityPrompt in the game uses
	Style = Custom and is drawn here: a studded key cap (the keyboard key or gamepad button; on
	touch a big TAP button that works the prompt), the action and object on a dark tag, a fill
	that rises inside the key while a hold prompt is held, and a quick pop in / out. A prompt
	only animates when it appears, so standing next to one never spams anything.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent.Parent.UI.UI)

local player = Players.LocalPlayer

local PromptController = {}

type Shown = { Gui: BillboardGui, Scale: UIScale, Connections: { RBXScriptConnection } }
local shown: { [ProximityPrompt]: Shown } = {}

local GamepadNames = {
	[Enum.KeyCode.ButtonX] = "X",
	[Enum.KeyCode.ButtonY] = "Y",
	[Enum.KeyCode.ButtonA] = "A",
	[Enum.KeyCode.ButtonB] = "B",
	[Enum.KeyCode.ButtonL1] = "LB",
	[Enum.KeyCode.ButtonR1] = "RB",
}

local function keyText(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Gamepad then
		return GamepadNames[prompt.GamepadKeyCode] or prompt.GamepadKeyCode.Name
	end
	local s = UserInputService:GetStringForKeyCode(prompt.KeyboardKeyCode)
	return (s and s ~= "") and string.upper(s) or prompt.KeyboardKeyCode.Name
end

local function hide(prompt: ProximityPrompt)
	local s = shown[prompt]
	if not s then
		return
	end
	shown[prompt] = nil
	for _, c in ipairs(s.Connections) do
		c:Disconnect()
	end
	UI.Tween(s.Scale, { Scale = 0.01 }, 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In).Completed:Once(function()
		s.Gui:Destroy()
	end)
end

local function show(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	hide(prompt)
	local adornee = prompt.Parent
	if not (adornee and (adornee:IsA("BasePart") or adornee:IsA("Attachment"))) then
		return
	end
	local touch = inputType == Enum.ProximityPromptInputType.Touch
	local action = string.upper(prompt.ActionText)
	local object = prompt.ObjectText
	local keySize = touch and 78 or 58
	local actionWidth = TextService:GetTextSize(action, 22, UI.Font, Vector2.new(400, 60)).X
	local objectWidth = object ~= "" and TextService:GetTextSize(object, 14, UI.FontBody, Vector2.new(400, 40)).X or 0
	local tagWidth = math.max(actionWidth, objectWidth) + 26
	local tagHeight = object ~= "" and 52 or 40

	local gui = Instance.new("BillboardGui")
	gui.Name = "InteractPrompt"
	gui.Adornee = adornee
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Active = touch
	gui.Size = UDim2.fromOffset(keySize + tagWidth + 24, keySize + 12)
	-- Float just above the top of the object, not at its centre (big parts would hide it).
	local lift = adornee:IsA("BasePart") and (adornee :: BasePart).Size.Y / 2 + 1.4 or 1.5
	gui.StudsOffsetWorldSpace = Vector3.new(0, lift, 0)
	gui.Parent = player:WaitForChild("PlayerGui")
	local root = UI.Frame({ BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)
	local scale = UI.New("UIScale", { Scale = 0.5 }, root) :: UIScale

	local key: GuiObject
	if touch then
		-- A real button: pressing it works the prompt (hold prompts fill while held).
		local button = UI.Button({ Text = "TAP", Color = UI.Colors.Green, Size = UDim2.fromOffset(keySize, keySize), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0), TextSize = 22, Corner = 16 }, root)
		button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				prompt:InputHoldBegin()
			end
		end)
		button.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				prompt:InputHoldEnd()
			end
		end)
		key = button
	else
		key = UI.Surface3D({ Size = UDim2.fromOffset(keySize, keySize), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0) }, root, UI.Colors.Green, 12, 0.12)
		local text = keyText(prompt, inputType)
		local label = UI.Label({ Text = text, TextSize = 30, TextWrapped = false, TextScaled = #text > 2, Size = UDim2.new(1, -10, 0.86, 0), Position = UDim2.fromOffset(5, 0) }, key)
		if #text > 2 then
			UI.New("UITextSizeConstraint", { MaxTextSize = 22 }, label)
		end
	end

	local fill: Frame? = nil
	if prompt.HoldDuration > 0 then
		local face = key:FindFirstChild("Face") or key
		fill = UI.Frame({ Name = "HoldFill", BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.45, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0) }, face)
		UI.Corner(fill :: Frame, 12)
	end

	local tag = UI.Panel({ Size = UDim2.fromOffset(tagWidth, tagHeight), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, keySize + 14, 0.5, 0), BackgroundTransparency = 0.12 }, root)
	UI.Label({ Text = action, TextSize = 22, TextWrapped = false, Size = UDim2.new(1, -16, 0, 26), Position = UDim2.fromOffset(8, object ~= "" and 4 or 7), TextXAlignment = Enum.TextXAlignment.Left }, tag)
	if object ~= "" then
		UI.Label({ Text = object, TextSize = 14, Font = UI.FontBody, TextColor3 = UI.Colors.TextDim, Size = UDim2.new(1, -16, 0, 16), Position = UDim2.fromOffset(8, 31), TextXAlignment = Enum.TextXAlignment.Left }, tag)
	end

	UI.Tween(scale, { Scale = 1 }, 0.22, Enum.EasingStyle.Back)

	local connections = {}
	if fill then
		local f = fill :: Frame
		table.insert(connections, prompt.PromptButtonHoldBegan:Connect(function()
			UI.Tween(f, { Size = UDim2.fromScale(1, 1) }, prompt.HoldDuration, Enum.EasingStyle.Linear)
		end))
		table.insert(connections, prompt.PromptButtonHoldEnded:Connect(function()
			UI.Tween(f, { Size = UDim2.fromScale(1, 0) }, 0.15)
		end))
	end
	table.insert(connections, prompt.Triggered:Connect(function()
		scale.Scale = 1.15
		UI.Tween(scale, { Scale = 1 }, 0.25, Enum.EasingStyle.Back)
	end))
	shown[prompt] = { Gui = gui, Scale = scale, Connections = connections }
end

function PromptController.Init()
	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if prompt.Style == Enum.ProximityPromptStyle.Custom then
			show(prompt, inputType)
		end
	end)
	ProximityPromptService.PromptHidden:Connect(hide)

	-- Studio-only test hook: fire PlayerGui.DevShowPrompt(prompt, "Keyboard" | "Touch" | "Gamepad")
	-- to draw a prompt (or with nil to hide it) without real input.
	if game:GetService("RunService"):IsStudio() then
		local hook = Instance.new("BindableEvent")
		hook.Name = "DevShowPrompt"
		hook.Parent = player:WaitForChild("PlayerGui")
		hook.Event:Connect(function(prompt: ProximityPrompt, kind: string?)
			if kind then
				show(prompt, Enum.ProximityPromptInputType[kind])
			else
				hide(prompt)
			end
		end)
	end
end

return PromptController
