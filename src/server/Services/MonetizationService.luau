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
local PetConfig = require(Shared.Config.PetConfig)
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
		local had = cache[def.Key]
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
		-- VIP bought mid-room: this room's free Super Hint is available right away.
		if def.Key == "VIP" and owns and had == false and player:GetAttribute("InMatch") then
			player:SetAttribute("VIPFreeHints", MonetizationConfig.Effects.VIPFreeSuperHintsPerMatch)
		end
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
			MonetizationService.Bank(player, key)
		end
	elseif key == "SuperHint" then
		if not Services.HintService.GrantSuperHint(player) then
			MonetizationService.Bank(player, key)
		end
	elseif key == "Strength10Min" then
		Services.PlayerSessionService.ExtendBoost(player, "StrengthBoostExpires", effects.BoostDurationSeconds)
		Services.NotificationService.Send(player, "Premium", "2X STRENGTH activated!")
	elseif key == "Cash10Min" then
		Services.PlayerSessionService.ExtendBoost(player, "CashBoostExpires", effects.BoostDurationSeconds)
		Services.NotificationService.Send(player, "Premium", "2X CASH activated!")
	elseif key == "TeamMuscleBoost" then
		if match then
			local base = math.max(match.TeamMuscleExpires or 0, workspace:GetServerTimeNow())
			match.TeamMuscleExpires = base + effects.BoostDurationSeconds
			Services.MatchService.GetStateConfig():SetAttribute("TeamMuscleExpires", match.TeamMuscleExpires)
			for _, p in ipairs(match.Players) do
				Services.PlayerSessionService.RecomputeDerived(p)
			end
			Services.NotificationService.SendMany(match.Players, "Premium", string.format("%s activated TEAM MUSCLE BOOST!", player.Name))
		else
			Services.PlayerSessionService.ExtendBoost(player, "StrengthBoostExpires", effects.BoostDurationSeconds)
		end
	elseif key == "SpeedBoost10Min" then
		Services.PlayerSessionService.ExtendBoost(player, "SpeedBoostExpires", effects.BoostDurationSeconds)
		Services.NotificationService.Send(player, "Premium", "2X SPEED activated!")
	elseif key == "DoubleXP15Min" then
		Services.PlayerSessionService.ExtendBoost(player, "XPBoostExpires", effects.XPBoostSeconds)
		Services.NotificationService.Send(player, "Premium", "2X XP activated!")
	elseif key == "LiftItNow" then
		if match and match.State == "Searching" then
			Services.RetentionService.ActivateLift(player)
			Services.NotificationService.Send(player, "Premium", "LIFT IT NOW: grab it! (60 s)")
		else
			MonetizationService.Bank(player, key)
		end
	elseif key == "JunkBlaster" then
		local count = Services.RetentionService.Blast(player)
		if count then
			Services.NotificationService.Send(player, "Premium", count > 0 and string.format("JUNK BLASTER: %d packed junk burst open!", count) or "JUNK BLASTER: no packed junk close enough to burst.")
		else
			MonetizationService.Bank(player, key)
		end
	elseif key == "TreasureRadar" then
		if match and match.State ~= "Results" and match.State ~= "Returning" and match.State ~= "Ended" and Services.RetentionService.ActivateRadar(player) then
			Services.NotificationService.Send(player, "Premium", "TREASURE RADAR: every treasure in this room sparkles!")
		else
			MonetizationService.Bank(player, key)
		end
	elseif key == "PetSnack" then
		Services.PlayerSessionService.ExtendBoost(player, "PetSnackExpires", PetConfig.SnackSeconds)
		Services.NotificationService.Send(player, "Premium", "PET SNACK: your pets work twice as fast!")
	elseif key == "StarterPack" then
		Services.DataService.Update(player, function(data)
			data.StarterPack = true
			data.Banked.CashBoost = (data.Banked.CashBoost or 0) + effects.StarterPackCashBoostSeconds
			data.Banked.QuickHint = (data.Banked.QuickHint or 0) + effects.StarterPackQuickHints
		end)
		Services.PetService.GivePet(player, "MopPup", "StarterPack")
		if match and match.State == "Searching" then
			MonetizationService.ApplyBanked(player)
		end
		Services.NotificationService.Send(player, "Premium", "STARTER PACK unlocked! Your boosts and hints start in your next room.", 5)
	else
		return false
	end
	return true
end

-- A paid hint that can't be used right now (not in a room / every clue already out) is saved
-- in the profile and delivered when the player's next room starts.
function MonetizationService.Bank(player: Player, key: string)
	Services.DataService.Update(player, function(data)
		data.Banked[key] = (data.Banked[key] or 0) + 1
	end)
	Services.DataService.Save(player)
	local helpers = { LiftItNow = "LIFT IT NOW saved - it turns on the next time something is too heavy.", JunkBlaster = "JUNK BLASTER saved - use it near packed junk in your next room.", TreasureRadar = "TREASURE RADAR saved - it turns on in your next room." }
	if helpers[key] then
		Services.RetentionService.Publish(player)
		Services.NotificationService.Send(player, "Premium", helpers[key], 5)
		return
	end
	local name = key == "SuperHint" and "Super Hint" or "Quick Hint"
	Services.NotificationService.Send(player, "Premium", string.format("%s saved - it will be used when your next room starts.", name))
end

function MonetizationService.ApplyBanked(player: Player)
	local data = Services.DataService.Get(player)
	if not data then
		return
	end
	-- Reward boosts (daily login) start here, in the room, instead of ticking away in the lobby.
	local cash, strength = data.Banked.CashBoost or 0, data.Banked.StrengthBoost or 0
	if cash > 0 then
		Services.PlayerSessionService.ExtendBoost(player, "CashBoostExpires", cash)
	end
	if strength > 0 then
		Services.PlayerSessionService.ExtendBoost(player, "StrengthBoostExpires", strength)
	end
	if cash > 0 or strength > 0 then
		Services.DataService.Update(player, function(d)
			d.Banked.CashBoost = 0
			d.Banked.StrengthBoost = 0
		end)
		Services.NotificationService.Send(player, "Success", "Your saved boost is on!")
	end
	-- A Treasure Radar bought outside a room turns on in this one.
	if (data.Banked.TreasureRadar or 0) > 0 and player:GetAttribute("TreasureRadar") == "" and Services.RetentionService.ActivateRadar(player) then
		Services.DataService.Update(player, function(d)
			d.Banked.TreasureRadar -= 1
		end)
		Services.NotificationService.Send(player, "Premium", "Your saved TREASURE RADAR is on!")
	end
	if (data.Banked.JunkBlaster or 0) > 0 then
		Services.RetentionService.Publish(player)
	end
	MonetizationService.ApplyBankedHints(player)
end

-- Saved Quick / Super Hints are used when a room starts (SEARCH!): one of each per room, so a
-- stack of saved hints helps several rooms instead of giving every clue away at once.
function MonetizationService.ApplyBankedHints(player: Player)
	local data = Services.DataService.Get(player)
	if not data then
		return
	end
	local quick, super = data.Banked.QuickHint or 0, data.Banked.SuperHint or 0
	if quick == 0 and super == 0 then
		return
	end
	local usedQuick, usedSuper = 0, 0
	if quick > 0 and Services.HintService.GrantQuickHint(player) then
		usedQuick = 1
	end
	-- One region highlight per room is enough; keep the rest for later rooms.
	if super > 0 and Services.HintService.GrantSuperHint(player) then
		usedSuper = 1
	end
	Services.DataService.Update(player, function(d)
		d.Banked.QuickHint = math.max(0, (d.Banked.QuickHint or 0) - usedQuick)
		d.Banked.SuperHint = math.max(0, (d.Banked.SuperHint or 0) - usedSuper)
	end)
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
	Services.AnalyticsService.Purchased(player, key, "Product", receiptInfo.CurrencySpent)
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
	if def.OneTime then
		local data = Services.DataService.Get(player)
		if not data or data[key] then
			Services.NotificationService.Send(player, "Info", "You already have the " .. def.Name .. ".")
			return
		end
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
	Services.AnalyticsService.PurchasePrompted(player, key, kind)
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

local refreshingPrice: { [string]: boolean } = {}

local function fetchPrice(id: number, infoType: Enum.InfoType, cacheKey: string): number?
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(id, infoType)
	end)
	local price = ok and info and info.PriceInRobux or nil
	priceCache[cacheKey] = { Price = price, Name = ok and info and info.Name or nil, FetchedAt = os.clock() }
	return price
end

-- Answers from the cache whenever it can (a stale price is refreshed in the background), so
-- opening the shop never waits on Roblox. Only a price never seen before is fetched inline.
function MonetizationService.GetLivePrice(id: number, infoType: Enum.InfoType): number?
	if id == 0 then
		return nil
	end
	local cacheKey = infoType.Name .. id
	local cached = priceCache[cacheKey]
	if cached then
		if os.clock() - cached.FetchedAt >= 300 and not refreshingPrice[cacheKey] then
			refreshingPrice[cacheKey] = true
			task.spawn(function()
				fetchPrice(id, infoType, cacheKey)
				refreshingPrice[cacheKey] = nil
			end)
		end
		return cached.Price
	end
	return fetchPrice(id, infoType, cacheKey)
end

-- Looks every configured price up at once when the server starts, so even the first shop open
-- is instant.
function MonetizationService.WarmPrices()
	for _, pair in ipairs({ { MonetizationConfig.GamepassDefs, Enum.InfoType.GamePass }, { MonetizationConfig.ProductDefs, Enum.InfoType.Product } }) do
		for _, def in ipairs(pair[1]) do
			task.spawn(MonetizationService.GetLivePrice, def.Id, pair[2])
		end
	end
end

-- Badges already confirmed (or being awarded) this session, so Roblox isn't asked twice.
local badgeChecked: { [Player]: { [number]: boolean } } = {}

-- Awards every badge the player's saved progress qualifies for: collection milestones, the
-- first finder win and each room's speed badge (from the saved best time). Runs after every
-- room and on join, so badges created later still reach players who already earned them.
function MonetizationService.CheckBadges(player: Player)
	local data = Services.DataService.Get(player)
	if not data then
		return
	end
	local toAward = {}
	for _, milestone in ipairs({ { 1, "FirstObject" }, { 10, "TenObjects" }, { 100, "HundredObjects" }, { 500, "FiveHundredObjects" }, { 1000, "ThousandObjects" } }) do
		if data.ObjectsFound >= milestone[1] then
			table.insert(toAward, milestone[2])
		end
	end
	if data.FinderWins >= 1 then
		table.insert(toAward, "FirstFinderWin")
	end
	for roomId, badge in pairs(MonetizationConfig.ClearBadges) do
		if data.HighestRoomCompleted >= roomId then
			table.insert(toAward, badge)
		end
	end
	for roomKey, speed in pairs(MonetizationConfig.SpeedBadges) do
		local best = data.BestTimes[roomKey]
		if best and best <= speed.Seconds then
			table.insert(toAward, speed.Badge)
		end
	end
	local checked = badgeChecked[player] or {}
	badgeChecked[player] = checked
	for _, key in ipairs(toAward) do
		local badgeId = MonetizationConfig.Badges[key] or 0
		if badgeId ~= 0 and not checked[badgeId] then
			checked[badgeId] = true
			task.spawn(function()
				local ok, err = pcall(function()
					if not BadgeService:UserHasBadgeAsync(player.UserId, badgeId) then
						BadgeService:AwardBadge(player.UserId, badgeId)
						print("[Badges] Awarded", key, "to", player.Name)
					end
				end)
				if not ok then
					checked[badgeId] = nil -- try again after the next room
					warn("[Badges] Could not award", key, err)
				end
			end)
		end
	end
end

-- Developer products with Id 0 are looked up on Roblox by their exact StoreName, so products
-- created by hand in Creator Hub work without pasting IDs into the config.
local function resolveDeveloperProducts()
	local missing = false
	for _, def in ipairs(MonetizationConfig.ProductDefs) do
		if def.Id == 0 then
			missing = true
		end
	end
	if not missing then
		return
	end
	local ok, pages = pcall(function()
		return MarketplaceService:GetDeveloperProductsAsync()
	end)
	if not ok or not pages then
		return
	end
	local byName = {}
	while true do
		for _, item in ipairs(pages:GetCurrentPage()) do
			byName[item.Name] = item.ProductId or item.DeveloperProductId
		end
		if pages.IsFinished then
			break
		end
		local advanced = pcall(function()
			pages:AdvanceToNextPageAsync()
		end)
		if not advanced then
			break
		end
	end
	local found = {}
	for _, def in ipairs(MonetizationConfig.ProductDefs) do
		local id = def.Id == 0 and byName[def.StoreName]
		if id then
			def.Id = id
			MonetizationConfig.Products[def.Key] = id
			table.insert(found, def.Key)
		end
	end
	if #found > 0 then
		print("[Monetization] Developer products found by name: " .. table.concat(found, ", "))
	end
end

function MonetizationService.Init()
	MarketplaceService.ProcessReceipt = processReceipt
	task.spawn(resolveDeveloperProducts)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased then
			task.spawn(function()
				refreshPasses(player)
				for _, def in ipairs(MonetizationConfig.GamepassDefs) do
					if def.Id == passId then
						Remotes.Event("PurchaseUpdate"):FireClient(player, "PassGranted", { Key = def.Key })
						Services.NotificationService.Send(player, "Premium", def.Name .. " unlocked!")
						Services.AnalyticsService.Purchased(player, def.Key, "Gamepass", MonetizationService.GetLivePrice(def.Id, Enum.InfoType.GamePass))
					end
				end
			end)
		else
			for _, def in ipairs(MonetizationConfig.GamepassDefs) do
				if def.Id == passId then
					Services.AnalyticsService.PurchaseCancelled(player, def.Key, "Gamepass")
				end
			end
		end
	end)
	-- Product prompts closed without buying (bought ones are counted in processReceipt).
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
		local player = Players:GetPlayerByUserId(userId)
		if isPurchased or not player then
			return
		end
		for _, def in ipairs(MonetizationConfig.ProductDefs) do
			if def.Id == productId then
				Services.AnalyticsService.PurchaseCancelled(player, def.Key, "Product")
			end
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

	-- The client also fetches this in the background at start, so it is not a shop visit
	-- (AnalyticsService counts those when the Shop menu opens).
	Remotes.Function("GetShopInfo").OnServerInvoke = function()
		return MonetizationService.GetShopInfo()
	end
	task.spawn(MonetizationService.WarmPrices)

	local function onPlayer(player: Player)
		passCache[player] = {}
		task.spawn(refreshPasses, player)
		-- Catch-up: badges earned before they existed (or while awarding failed) arrive on join.
		task.spawn(function()
			if Services.DataService.WaitFor(player, 15) then
				MonetizationService.CheckBadges(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		passCache[player] = nil
		devGrants[player] = nil
		badgeChecked[player] = nil
	end)
end

return MonetizationService
