local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Utility.Remotes)

local NotificationService = {}

function NotificationService.Send(player: Player, kind: string, text: string, duration: number?)
	if player and player.Parent then
		Remotes.Event("Notification"):FireClient(player, kind, text, duration)
	end
end

function NotificationService.SendMany(players: { Player }, kind: string, text: string, duration: number?)
	for _, player in ipairs(players) do
		NotificationService.Send(player, kind, text, duration)
	end
end

return NotificationService
