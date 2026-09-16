--[[
	Collection object definitions. Object N is found by completing Room N.
	Objects without a room yet show as locked slots. IconKey = the object's image in
	ReplicatedStorage.GameAssets.UIImages (a letter is shown until it exists).
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
	[2] = {
		Id = "GrandmasRing",
		Name = "Grandma's Diamond Ring",
		Number = 2,
		Color = Color3.fromRGB(170, 225, 255),
		Icon = "",
		IconKey = "Icon_Ring",
	},
	[3] = {
		Id = "GoldenRemote",
		Name = "Golden TV Remote",
		Number = 3,
		Color = Color3.fromRGB(255, 190, 30),
		Icon = "",
		IconKey = "Icon_Remote",
	},
	[4] = {
		Id = "GoldenWrench",
		Name = "Golden Wrench",
		Number = 4,
		Color = Color3.fromRGB(255, 205, 60),
		Icon = "",
		IconKey = "Icon_Wrench",
	},
	[5] = {
		Id = "TreasureMap",
		Name = "Treasure Map",
		Number = 5,
		Color = Color3.fromRGB(235, 205, 150),
		Icon = "",
		IconKey = "Icon_Map",
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
