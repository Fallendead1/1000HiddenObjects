--[[
	Collection object definitions. Object N is found by completing Room N.
	Only #001 needs real content now; the rest are generated as locked slots.
]]

export type TargetDef = {
	Id: string,
	Name: string,
	Number: number,
	Color: Color3,
	Icon: string, -- image asset id string, or "" for placeholder
	IconKey: string, -- UI image key (ReplicatedStorage.GameAssets.UIImages), text glyph fallback
}

local Targets: { [number]: TargetDef } = {
	[1] = {
		Id = "GoldenKey",
		Name = "Golden Key",
		Number = 1,
		Color = Color3.fromRGB(255, 200, 40),
		Icon = "",
		IconKey = "Icon_Key",
	},
}

local TargetData = {}

function TargetData.Get(number: number): TargetDef?
	return Targets[number]
end

function TargetData.GetById(id: string): TargetDef?
	for _, def in pairs(Targets) do
		if def.Id == id then
			return def
		end
	end
	return nil
end

function TargetData.FormatNumber(number: number): string
	return string.format("#%03d", number)
end

return TargetData
