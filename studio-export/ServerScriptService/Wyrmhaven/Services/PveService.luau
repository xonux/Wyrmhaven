-- The exploration map: which stages a player has opened, who they send in,
-- and what clearing one pays (Config/PveMap).
--
-- The fight itself is CombatEngine's job and the other side is played by
-- CombatAI at the stage's difficulty. For now the PLAYER's side is played by
-- the AI too and the whole battle resolves in one call - the battle screen is
-- what will hand those turns back to the player, through the same
-- `options.choose` door. Everything else here (unlocking, rewards, refusals)
-- is already final, so the screen only has to replace the chooser.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage.Wyrmhaven.Config
local PveMap = require(Config.PveMap)
local DragonDefs = require(Config.DragonDefs)
local DragonRules = require(Config.DragonRules)
local DragonLevels = require(Config.DragonLevels)
local SkillRules = require(Config.SkillRules)

local CombatEngine = require(script.Parent.CombatEngine)
local CombatAI = require(script.Parent.CombatAI)

local PveService = {}

local DragonService
local EconomyService
local FarmService
local LevelService
local HudService
local pveStatusUpdated
local pveBattleStarted
local pveBattleUpdate
local pveBattleResult

-- [userId] = { cleared = highest stage cleared, team = { dragonId }, lastFightAt }
local progress = {}
-- [userId] = the fight that player is in right now (see "a live fight")
local sessions = {}

-- Fights resolve instantly, so a held button could otherwise farm a stage as
-- fast as the network allows. Once the player picks every turn by hand this
-- stops mattering, but the remote stays open either way.
local FIGHT_COOLDOWN_SECONDS = 3

function PveService.Init(dragonServiceRef, economyServiceRef, farmServiceRef, levelServiceRef, hudServiceRef, remotesFolder)
	DragonService = dragonServiceRef
	EconomyService = economyServiceRef
	FarmService = farmServiceRef
	LevelService = levelServiceRef
	HudService = hudServiceRef
	pveStatusUpdated = remotesFolder:WaitForChild("PveStatusUpdated")
	pveBattleStarted = remotesFolder:WaitForChild("PveBattleStarted")
	pveBattleUpdate = remotesFolder:WaitForChild("PveBattleUpdate")
	pveBattleResult = remotesFolder:WaitForChild("PveBattleResult")
end

function PveService.LoadPlayer(player, saved)
	progress[player.UserId] = {
		cleared = math.clamp((saved and saved.cleared) or 0, 0, PveMap.Count),
		team = {}, -- dragon ids only live as long as the session, so the team is picked again on each join
	}
end

function PveService.GetSaveState(player)
	local record = progress[player.UserId]
	return record and { cleared = record.cleared } or nil
end

function PveService.RemovePlayer(player)
	progress[player.UserId] = nil
	local session = sessions[player.UserId]
	if session then
		-- Lets the fight's thread stop waiting on someone who has gone.
		session.abandoned = true
	end
end

------------------------------------------------------------------ roster

-- Dragons that can be sent in: Adults (DragonAdultLevel), not away breeding.
-- Babies are left out on purpose - growing one into a fighter is what the
-- map's Food pays for.
local function roster(player)
	local list = {}
	for _, dragon in ipairs(DragonService.GetPlayerDragons(player)) do
		if dragon.level >= DragonLevels.AdultLevel and not dragon.isBreeding then
			local def = DragonDefs[dragon.element]
			local stats = DragonRules.Stats(dragon.element, dragon.level)
			table.insert(list, {
				id = dragon.id,
				species = dragon.element,
				name = dragon.nickname or def.DisplayName,
				speciesName = def.DisplayName,
				level = dragon.level,
				rarity = DragonRules.Rarity(dragon.element),
				class = DragonRules.Class(dragon.element),
				className = DragonRules.ClassName(dragon.element),
				stats = stats,
				color = def.StageColors.Adult,
				habitatId = dragon.habitatId,
			})
		end
	end
	table.sort(list, function(a, b)
		if a.level ~= b.level then
			return a.level > b.level
		end
		return a.stats.Attack * a.stats.Health > b.stats.Attack * b.stats.Health
	end)
	return list
end

-- The team the player picked, minus anything that has since gone breeding or
-- been sold. Empty until they pick: the map screen proposes its own default.
local function currentTeam(player, available)
	local record = progress[player.UserId]
	if not record then
		return {}
	end
	local byId = {}
	for _, dragon in ipairs(available) do
		byId[dragon.id] = true
	end
	local team = {}
	for _, dragonId in ipairs(record.team) do
		if byId[dragonId] then
			table.insert(team, dragonId)
		end
	end
	record.team = team
	return team
end

-- Three strongest Adults, used when the player hasn't picked a team yet.
local function defaultTeam(available)
	local team = {}
	for i = 1, math.min(CombatEngine.TeamSize, #available) do
		table.insert(team, available[i].id)
	end
	return team
end

-- dragonIds: up to CombatEngine.TeamSize ids, in the order they should fight.
function PveService.SetTeam(player, dragonIds)
	local record = progress[player.UserId]
	if not record then
		return false
	end
	local available = {}
	for _, dragon in ipairs(roster(player)) do
		available[dragon.id] = true
	end
	local team, seen = {}, {}
	for _, dragonId in ipairs(dragonIds) do
		if typeof(dragonId) == "number" and available[dragonId] and not seen[dragonId] and #team < CombatEngine.TeamSize then
			seen[dragonId] = true
			table.insert(team, dragonId)
		end
	end
	record.team = team
	return true
end

------------------------------------------------------------------ status

-- One enemy as the map screen shows it before the fight.
local function enemyCard(entry)
	local def = DragonDefs[entry.Species]
	local stats = DragonRules.Stats(entry.Species, entry.Level)
	if entry.Boss then
		stats = {
			Attack = math.round(stats.Attack * PveMap.BossAttackMultiplier),
			Health = math.round(stats.Health * PveMap.BossHealthMultiplier),
			Speed = stats.Speed,
		}
	end
	return {
		species = entry.Species,
		name = entry.Name or def.DisplayName,
		level = entry.Level,
		boss = entry.Boss == true,
		rarity = DragonRules.Rarity(entry.Species),
		class = DragonRules.Class(entry.Species),
		className = DragonRules.ClassName(entry.Species),
		stats = stats,
		color = def.StageColors.Adult,
		skills = SkillRules.SkillsOf(entry.Species),
	}
end

local function buildStatus(player)
	local record = progress[player.UserId]
	local cleared = record and record.cleared or 0
	local available = roster(player)
	local team = currentTeam(player, available)
	if #team == 0 then
		team = defaultTeam(available)
		if record then
			record.team = team
		end
	end

	local levels = {}
	for _, level in ipairs(PveMap.Levels) do
		local enemies = {}
		for _, entry in ipairs(level.Enemies) do
			table.insert(enemies, enemyCard(entry))
		end
		local isCleared = level.Id <= cleared
		table.insert(levels, {
			id = level.Id,
			name = level.DisplayName,
			region = level.Region,
			position = level.Position,
			boss = level.Boss == true,
			difficulty = level.Difficulty,
			recommendedLevel = level.RecommendedLevel,
			unlocked = level.Id <= cleared + 1,
			cleared = isCleared,
			enemies = enemies,
			rewards = PveMap.Rewards(level.Id, not isCleared),
			fullRewards = level.Rewards, -- what it paid, or pays, the first time
		})
	end

	return {
		cleared = cleared,
		count = PveMap.Count,
		teamSize = CombatEngine.TeamSize,
		regions = PveMap.Regions,
		pathStones = PveMap.PathStones,
		levels = levels,
		roster = available,
		team = team,
	}
end

local function pushStatus(player, openRequest, extra)
	if not progress[player.UserId] then
		return
	end
	local status = buildStatus(player)
	status.openRequest = openRequest
	for key, value in pairs(extra or {}) do
		status[key] = value
	end
	pveStatusUpdated:FireClient(player, status)
end

-- Tap on the map button: forces the screen open on the client.
function PveService.RequestInfo(player)
	pushStatus(player, true)
end

function PveService.RefreshStatus(player, extra)
	pushStatus(player, false, extra)
end

------------------------------------------------------------------ the fight

local function buildEnemyTeam(level)
	local team = {}
	for _, entry in ipairs(level.Enemies) do
		local fighter = CombatEngine.Fighter(entry.Species, entry.Level, entry.Name, {
			boss = entry.Boss == true,
			scale = entry.Boss and PveMap.BossScale or nil, -- the battle screen draws it bigger
		})
		if entry.Boss then
			-- Scaling the entry's stats is enough: the battle reads them once,
			-- when it spawns the fighter.
			fighter.stats = {
				Attack = fighter.stats.Attack * PveMap.BossAttackMultiplier,
				Health = fighter.stats.Health * PveMap.BossHealthMultiplier,
				Speed = fighter.stats.Speed,
			}
		end
		table.insert(team, fighter)
	end
	return team
end

local function buildPlayerTeam(player, team)
	local byId = {}
	for _, dragon in ipairs(roster(player)) do
		byId[dragon.id] = dragon
	end
	local fighters = {}
	for _, dragonId in ipairs(team) do
		local dragon = byId[dragonId]
		if dragon then
			table.insert(fighters, CombatEngine.Fighter(dragon.species, dragon.level, dragon.name, { dragonId = dragon.id }))
		end
	end
	return fighters
end

local function payRewards(player, rewards)
	if rewards.Coins > 0 then
		EconomyService.AddCoins(player, rewards.Coins)
	end
	if rewards.Food > 0 then
		FarmService.AddFood(player, rewards.Food)
	end
	if rewards.Xp > 0 then
		LevelService.AddXp(player, rewards.Xp)
	end
end

------------------------------------------------------------------ a live fight

-- The fight runs in its own thread. CombatEngine is synchronous, so a
-- player's turn is simply a wait inside the chooser: the client is told what
-- just happened and what this dragon can do, it answers with a skill and a
-- target, and the thread picks up where it left off. There is one push per
-- turn, the enemy's included, so the screen can play the fight as it goes
-- rather than all at the end.
local TURN_SECONDS = 45 -- after that the AI takes the turn, so a fight never hangs
local POLL_SECONDS = 0.1

-- Who is in the fight, as the battle screen draws them (identity only - what
-- changes during the fight travels in the snapshot below).
local function fighterCards(battle)
	local cards = {}
	for _, fighter in ipairs(battle.fighters) do
		local def = DragonDefs[fighter.species]
		local source = fighter.source or {}
		table.insert(cards, {
			key = fighter.key,
			team = fighter.team,
			name = fighter.name,
			species = fighter.species,
			elements = fighter.elements,
			class = fighter.class,
			className = DragonRules.ClassName(fighter.species),
			level = fighter.level,
			color = def and def.StageColors.Adult,
			boss = source.boss == true,
			scale = source.scale,
			dragonId = source.dragonId,
			attack = math.round(fighter.baseAttack),
			speed = math.round(fighter.baseSpeed),
		})
	end
	return cards
end

-- Everything that moves: Health, shield, what is stuck on them.
local function snapshot(battle)
	local list = {}
	for _, fighter in ipairs(battle.fighters) do
		local statuses = {}
		for _, status in ipairs(fighter.statuses) do
			-- `id` names the status (Config/StatusDefs): the screen reads its
			-- name and, later, its icon from there.
			table.insert(statuses, { id = status.id, kind = status.kind, turns = status.turns })
		end
		table.insert(list, {
			key = fighter.key,
			health = math.round(fighter.health),
			maxHealth = math.round(fighter.maxHealth),
			shield = math.round(fighter.shield),
			alive = fighter.alive,
			stunned = fighter.stunTurns > 0,
			statuses = statuses,
		})
	end
	return list
end

-- The three buttons the player gets, with what each skill says it does and
-- how its element lands on each possible target.
local function actionCards(battle, fighter)
	local actions = battle:availableActions(fighter)
	for _, action in ipairs(actions) do
		local skill = SkillRules.Get(action.skill)
		action.description = SkillRules.Describe(action.skill)
		action.class = skill and skill.Class
	end
	return actions
end

-- Log entries written since the last push.
local function drainEvents(session, battle)
	local events = {}
	for index = session.sent + 1, #battle.log do
		table.insert(events, battle.log[index])
	end
	session.sent = #battle.log
	return events
end

local UPCOMING_SHOWN = 4 -- how many turns ahead the strip at the top shows

local function pushTurn(player, session, battle, fighter, actions)
	pveBattleUpdate:FireClient(player, {
		token = session.token,
		round = battle.round,
		actorKey = fighter and fighter.key or nil,
		yourTurn = actions ~= nil,
		actions = actions,
		upcoming = battle:upcoming(UPCOMING_SHOWN), -- who plays after this one
		events = drainEvents(session, battle),
		fighters = snapshot(battle),
		secondsLeft = actions and TURN_SECONDS or nil,
	})
end

-- The player's answer for the turn they are being asked about. Anything late,
-- for another turn, or simply not allowed is dropped - the wait below then
-- runs out and the AI takes that turn.
function PveService.SubmitAction(player, token, skillId, targetKey)
	local session = sessions[player.UserId]
	if not session or not session.waiting or session.token ~= token then
		return false
	end
	local fighter = session.actor
	if not fighter or not table.find(fighter.skills, skillId) or fighter.cooldowns[skillId] then
		return false
	end
	session.answer = { skillId = skillId, targetKey = targetKey }
	return true
end

function PveService.IsFighting(player)
	return sessions[player.UserId] ~= nil
end

-- Starts a stage. Returns true once the fight is under way (the result comes
-- later, through PveBattleResult), or false plus a reason the map explains.
function PveService.Fight(player, levelId)
	local record = progress[player.UserId]
	if not record then
		return false, "NotReady"
	end
	if sessions[player.UserId] then
		return false, "Busy"
	end
	local level = PveMap.Get(levelId)
	if not level then
		return false, "NoSuchStage"
	end
	if levelId > record.cleared + 1 then
		return false, "Locked"
	end
	local now = os.clock()
	if record.lastFightAt and now - record.lastFightAt < FIGHT_COOLDOWN_SECONDS then
		return false, "TooFast"
	end

	local available = roster(player)
	local team = currentTeam(player, available)
	if #team == 0 then
		team = defaultTeam(available)
		record.team = team
	end
	local playerTeam = buildPlayerTeam(player, team)
	if #playerTeam == 0 then
		return false, "NoTeam" -- no Adult free to fight
	end
	record.lastFightAt = now

	local seed = os.time() * 1000 + math.random(0, 999)
	local session = { levelId = levelId, sent = 0, token = 0, waiting = false, opened = false }
	sessions[player.UserId] = session

	task.spawn(function()
		local enemyPolicy = CombatAI.Policy(level.Difficulty, seed)
		-- Stands in for the player when they run out of time, and never for
		-- anything else.
		local standIn = CombatAI.Policy("Normal", seed + 1)
		local ok, result = pcall(CombatEngine.Resolve, playerTeam, buildEnemyTeam(level), {
			seed = seed,
			choose = function(fighter, battle)
				if not session.opened then
					session.opened = true
					pveBattleStarted:FireClient(player, {
						levelId = levelId,
						name = level.DisplayName,
						boss = level.Boss == true,
						difficulty = level.Difficulty,
						fighters = fighterCards(battle),
						fighterState = snapshot(battle),
						events = drainEvents(session, battle),
					})
				end
				if fighter.team ~= "A" then
					pushTurn(player, session, battle, fighter, nil)
					-- A beat of air, so the screen can play the enemy's turn
					-- instead of everything landing at once.
					task.wait(0.35)
					return enemyPolicy(fighter, battle)
				end

				session.token += 1
				session.actor = fighter
				session.answer = nil
				session.waiting = true
				pushTurn(player, session, battle, fighter, actionCards(battle, fighter))
				local deadline = os.clock() + TURN_SECONDS
				while session.answer == nil and os.clock() < deadline and not session.abandoned do
					task.wait(POLL_SECONDS)
				end
				session.waiting = false
				local answer = session.answer
				session.answer, session.actor = nil, nil
				if not answer then
					return standIn(fighter, battle)
				end
				return answer.skillId, answer.targetKey
			end,
		})

		sessions[player.UserId] = nil
		if not ok then
			warn("[Wyrmhaven] A fight went wrong: " .. tostring(result))
			if player.Parent then
				PveService.RefreshStatus(player, { fightError = "Failed" })
			end
			return
		end
		if not player.Parent then
			return -- they left mid-fight: no reward, no push
		end

		local won = result.winner == "A"
		local current = progress[player.UserId]
		local firstClear = won and current ~= nil and levelId == current.cleared + 1
		local rewards = won and PveMap.Rewards(levelId, firstClear) or { Coins = 0, Food = 0, Xp = 0 }
		if won and current then
			if firstClear then
				current.cleared = levelId
			end
			payRewards(player, rewards)
		end

		-- Whatever happened after the last turn push, so the screen can finish
		-- playing the fight before it shows the outcome.
		local tail = {}
		for index = session.sent + 1, #result.log do
			table.insert(tail, result.log[index])
		end
		-- And the state everyone ends in. Without it the screen would keep the
		-- last snapshot it was sent - the one from before the closing blows -
		-- and a dragon that went down at the end (a burn on its own turn, say)
		-- would still be standing at full Health on screen.
		local closing = {}
		for _, fighter in ipairs(result.fighters) do
			table.insert(closing, {
				key = fighter.key,
				health = fighter.health,
				maxHealth = fighter.maxHealth,
				shield = 0,
				alive = fighter.alive,
				stunned = false,
				statuses = {},
			})
		end
		pveBattleResult:FireClient(player, {
			levelId = levelId,
			name = level.DisplayName,
			won = won,
			firstClear = firstClear,
			rewards = rewards,
			rounds = result.rounds,
			timedOut = result.timedOut,
			fighters = result.fighters,
			fighterState = closing,
			events = tail,
		})
		HudService.PushUpdate(player) -- the Coins, Food and XP won
		PveService.RefreshStatus(player) -- the next stage is open now
	end)

	return true
end

return PveService
