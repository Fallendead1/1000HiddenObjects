--[[
	Gamepass ownership (cached per session), Developer Product receipts (idempotent, server
	granted), purchase prompting, Studio/dev mock purchases, live price lookup and badges.
	Products with ID 0 are hidden in production and mocked in development.
]]

local BadgeService = game:GetService("BadgeService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Remotes = require(Shared.Utility.Remotes)
local RateLimiter = require(Shared.Utility.RateLimiter)

local Services = require(script.Parent)

local MonetizationService = {}

local passCache: { [Player]: { [string]: boolean } } = {}
local priceCache: { [string]: { Price: number?, Name: string?, FetchedAt: number } } = {}
local purchaseLimiter = RateLimiter.new(2, 3)
local devGrants: { [Player]: { [string]: boolean } } = {}

local function isMockMode(): boolean
	return RunService:IsStudio() and GameConfig.DevelopmentMode
end

local function setPassAttribute(player: Player, key: string, owns: boolean)
	player:SetAttribute("Pass_" .. key, owns)
end

local function refreshPasses(player: Player)
	local cache = passCache[player] or {}
	passCache[player] = cache
	for _, def in ipairs(MonetizationConfig.GamepassDefs) do
		local owns = false
		if def.Id ~= 0 then
			local ok, result = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, def.Id)
			end)
			owns = ok and result == true
		end
		if devGrants[player] and devGrants[player][def.Key] then
			owns = true
		end
		cache[def.Key] = owns
		setPassAttribute(player, def.Key, owns)
	end
	Services.PlayerSessionService.RecomputeDerived(player)
end

function MonetizationService.OwnsPass(player: Player, key: string): boolean
	local cache = passCache[player]
	if cache and cache[key] ~= nil then
		return cache[key]
	end
	return false
end

-- Grant effects for a repeatable product. Returns true when granted.
function MonetizationService.GrantProduct(player: Player, key: string): boolean
	local effects = MonetizationConfig.Effects
	local match = Services.MatchService.GetMatchForPlayer(player)

	if key == "QuickHint" then
		if not Services.HintService.GrantQuickHint(player) then
			Services.NotificationService.Send(player, "Info", "Quick Hint saved for your next room.")
		end
	elseif key == "SuperHint" then
		if not Services.HintService.GrantSuperHint(player) then
			Services.NotificationService.Send(player, "Info", "Super Hint saved for your next room.")
		end
	elseif key == "SearchPower10Min" then
		Services.PlayerSessionService.ExtendBoost(player, "SearchBoostExpires", effects.BoostDurationSeconds)
		Services.NotificationService.Send(player, "Premium", "2X SEARCH POWER activated!")
	elseif key == "Cash10Min" then
		Services.PlayerSessionService.ExtendBoost(player, "CashBoostExpires", effects.BoostDurationSeconds)
		Services.NotificationService.Send(player, "Premium", "2X CASH activated!")
	elseif key == "TeamSearchSurge" then
		if match then
			local base = math.max(match.TeamSurgeExpires or 0, workspace:GetServerTimeNow())
			match.TeamSurgeExpires = base + effects.BoostDurationSeconds
			Services.MatchService.GetStateConfig():SetAttribute("TeamSurgeExpires", match.TeamSurgeExpires)
			Services.NotificationService.SendMany(match.Players, "Premium", string.format("%s activated TEAM SEARCH SURGE!", player.Name))
		else
			Services.PlayerSessionService.ExtendBoost(player, "SearchBoostExpires", effects.BoostDurationSeconds)
		end
	elseif key == "TrashBomb" then
		player:SetAttribute("PendingTrashBombs", (player:GetAttribute("PendingTrashBombs") or 0) + 1)
		Remotes.Event("PurchaseUpdate"):FireClient(player, "TrashBombReady", {})
	else
		return false
	end
	Services.AnalyticsService.Log("premium_purchase", player, { Product = key })
	return true
end

local function processReceipt(receiptInfo): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = Services.DataService.WaitFor(player, 10)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local receiptId = tostring(receiptInfo.PurchaseId)
	if data.PurchaseHistory[receiptId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local key = nil
	for _, def in ipairs(MonetizationConfig.ProductDefs) do
		if def.Id == receiptInfo.ProductId then
			key = def.Key
			break
		end
	end
	if not key then
		warn("[Monetization] Receipt for unknown product", receiptInfo.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local granted = MonetizationService.GrantProduct(player, key)
	if not granted then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	Services.DataService.Update(player, function(d)
		d.PurchaseHistory[receiptId] = os.time()
		-- Trim old receipts.
		local count = 0
		for _ in pairs(d.PurchaseHistory) do
			count += 1
		end
		if count > 60 then
			local oldestKey, oldest = nil, math.huge
			for k, t in pairs(d.PurchaseHistory) do
				if t < oldest then
					oldest, oldestKey = t, k
				end
			end
			if oldestKey then
				d.PurchaseHistory[oldestKey] = nil
			end
		end
	end)
	local saved = Services.DataService.Save(player)
	if not saved and not RunService:IsStudio() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService.PromptPurchase(player: Player, key: string)
	local def, kind = MonetizationConfig.FindDef(key)
	if not def then
		return
	end
	if def.MatchOnly and not Services.MatchService.IsPlayerInMatch(player) then
		Services.NotificationService.Send(player, "Warning", "This can only be used inside a room.")
		return
	end
	if kind == "Gamepass" and MonetizationService.OwnsPass(player, key) then
		Services.NotificationService.Send(player, "Info", "You already own this.")
		return
	end
	if def.Id == 0 then
		if isMockMode() then
			MonetizationService.MockGrant(player, key)
		else
			Services.NotificationService.Send(player, "Warning", "This item is not available yet.")
		end
		return
	end
	Services.AnalyticsService.Log("premium_prompt", player, { Product = key })
	if kind == "Gamepass" then
		pcall(function()
			MarketplaceService:PromptGamePassPurchase(player, def.Id)
		end)
	else
		pcall(function()
			MarketplaceService:PromptProductPurchase(player, def.Id)
		end)
	end
end

-- Studio/dev only: grant without Robux so every flow can be tested.
function MonetizationService.MockGrant(player: Player, key: string)
	if not isMockMode() and not Services.DevService.IsAuthorized(player) then
		return
	end
	local def, kind = MonetizationConfig.FindDef(key)
	if not def then
		return
	end
	if kind == "Gamepass" then
		devGrants[player] = devGrants[player] or {}
		devGrants[player][key] = true
		refreshPasses(player)
		Remotes.Event("PurchaseUpdate"):FireClient(player, "PassGranted", { Key = key })
		Services.NotificationService.Send(player, "Premium", string.format("[DEV] %s granted!", def.Name))
	else
		MonetizationService.GrantProduct(player, key)
	end
end

function MonetizationService.GetShopInfo()
	local list = {}
	for _, def in ipairs(MonetizationConfig.GamepassDefs) do
		local price = MonetizationService.GetLivePrice(def.Id, Enum.InfoType.GamePass)
		table.insert(list, {
			Key = def.Key, Kind = "Gamepass", Name = def.Name, Description = def.Description, Icon = def.Icon,
			Tab = def.Tab, Price = price, SuggestedPrice = def.SuggestedPrice, Configured = def.Id ~= 0, MatchOnly = def.MatchOnly == true,
		})
	end
	for _, def in ipairs(MonetizationConfig.ProductDefs) do
		local price = MonetizationService.GetLivePrice(def.Id, Enum.InfoType.Product)
		table.insert(list, {
			Key = def.Key, Kind = "Product", Name = def.Name, Description = def.Description, Icon = def.Icon,
			Tab = def.Tab, Price = price, SuggestedPrice = def.SuggestedPrice, Configured = def.Id ~= 0, MatchOnly = def.MatchOnly == true,
		})
	end
	return list
end

function MonetizationService.GetLivePrice(id: number, infoType: Enum.InfoType): number?
	if id == 0 then
		return nil
	end
	local cacheKey = infoType.Name .. id
	local cached = priceCache[cacheKey]
	if cached and os.clock() - cached.FetchedAt < 300 then
		return cached.Price
	end
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(id, infoType)
	end)
	local price = ok and info and info.PriceInRobux or nil
	priceCache[cacheKey] = { Price = price, Name = ok and info and info.Name or nil, FetchedAt = os.clock() }
	return price
end

function MonetizationService.CheckBadges(player: Player, firstClear: boolean, isFinder: boolean)
	local data = Services.DataService.Get(player)
	if not data then
		return
	end
	local badges = MonetizationConfig.Badges
	local toAward = {}
	if firstClear then
		if data.ObjectsFound >= 1 then table.insert(toAward, badges.FirstObject) end
		if data.ObjectsFound >= 10 then table.insert(toAward, badges.TenObjects) end
		if data.ObjectsFound >= 100 then table.insert(toAward, badges.HundredObjects) end
		if data.ObjectsFound >= 500 then table.insert(toAward, badges.FiveHundredObjects) end
		if data.ObjectsFound >= 1000 then table.insert(toAward, badges.ThousandObjects) end
	end
	if isFinder and data.FinderWins >= 1 then
		table.insert(toAward, badges.FirstFinderWin)
	end
	for _, badgeId in ipairs(toAward) do
		if badgeId ~= 0 then
			task.spawn(function()
				pcall(function()
					if not BadgeService:UserHasBadgeAsync(player.UserId, badgeId) then
						BadgeService:AwardBadge(player.UserId, badgeId)
					end
				end)
			end)
		end
	end
end

function MonetizationService.Init()
	MarketplaceService.ProcessReceipt = processReceipt

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased then
			task.spawn(function()
				refreshPasses(player)
				for _, def in ipairs(MonetizationConfig.GamepassDefs) do
					if def.Id == passId then
						Remotes.Event("PurchaseUpdate"):FireClient(player, "PassGranted", { Key = def.Key })
						Services.NotificationService.Send(player, "Premium", def.Name .. " unlocked!")
						Services.AnalyticsService.Log("premium_purchase", player, { Product = def.Key })
					end
				end
			end)
		end
	end)

	Remotes.Event("RequestPurchase").OnServerEvent:Connect(function(player, key)
		if not purchaseLimiter:Allow(player) then
			return
		end
		if type(key) ~= "string" then
			return
		end
		MonetizationService.PromptPurchase(player, key)
	end)

	Remotes.Function("GetShopInfo").OnServerInvoke = function(player)
		Services.AnalyticsService.Log("shop_open", player)
		return MonetizationService.GetShopInfo()
	end

	local function onPlayer(player: Player)
		passCache[player] = {}
		task.spawn(refreshPasses, player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		passCache[player] = nil
		devGrants[player] = nil
	end)
end

return MonetizationService
