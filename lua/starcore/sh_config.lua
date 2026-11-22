-- StarCore: shared settings, server limits (admin ConVars) and helpers
-- the NOTIFY_* numbers exist only on the client: the server needs them too for StarCore.Notify (a real server crashed here)
NOTIFY_GENERIC = NOTIFY_GENERIC or 0
NOTIFY_ERROR = NOTIFY_ERROR or 1
NOTIFY_UNDO = NOTIFY_UNDO or 2
NOTIFY_HINT = NOTIFY_HINT or 3
NOTIFY_CLEANUP = NOTIFY_CLEANUP or 4

local FLAGS = { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY }

StarCore.CV = {
	maxParts     = CreateConVar("starcore_max_parts", "600", FLAGS, "Most props one StarCore ship may have", 10, 5000),
	maxSpeed     = CreateConVar("starcore_max_speed", "2500", FLAGS, "Highest flight speed (units per second)", 100, 20000),
	allowJump    = CreateConVar("starcore_allow_jump", "1", FLAGS, "Ships may make hyperspace jumps (2026-11-16, a Workshop player's wish)", 0, 1),
	jumpRange    = CreateConVar("starcore_jump_range", "0", FLAGS, "Longest hyperspace jump in units (0 = whole map)", 0, 1000000),
	chargeMin    = CreateConVar("starcore_jump_charge_min", "2", FLAGS, "Shortest jump charge time in seconds", 0, 60),
	cooldownMin  = CreateConVar("starcore_jump_cooldown_min", "4", FLAGS, "Shortest time between two jumps in seconds", 0, 600),
	radarRange   = CreateConVar("starcore_radar_range", "30000", FLAGS, "Longest radar range in units", 1000, 200000),
	maxWeapons   = CreateConVar("starcore_max_weapons", "24", FLAGS, "Most weapons one ship may control", 0, 200),
	allowAutoDefence = CreateConVar("starcore_allow_auto_defence", "1", FLAGS, "Ships may shoot back at attackers by themselves", 0, 1),
	targetPlayers = CreateConVar("starcore_target_players", "1", FLAGS, "Ship weapons may target players (never owner, crew or friends)", 0, 1),
	jumpEnergy   = CreateConVar("starcore_jump_energy", "0", FLAGS, "Energy a jump costs per 1000 units (0 = free; needs a resource network)", 0, 10000000),
	beamRange    = CreateConVar("starcore_beam_range", "8000", FLAGS, "Longest Asgard beam distance in units", 100, 100000),
	beamHostile  = CreateConVar("starcore_beam_hostile", "0", FLAGS, "Ships may beam players who are not friends (and hostiles) aboard", 0, 1),
	destroyMode  = CreateConVar("starcore_destroy_mode", "1", FLAGS, "Ship at 0 hull: 0 = only disabled, 1 = falls apart as a burning wreck, 2 = removed", 0, 2),
	hull         = CreateConVar("starcore_hull", "1", FLAGS, "Ships have hull points and can be disabled by damage", 0, 1),
	allowTractor = CreateConVar("starcore_allow_tractor", "1", FLAGS, "Ships may use tractor beams", 0, 1),
	tractorRange = CreateConVar("starcore_tractor_range", "3000", FLAGS, "Longest tractor beam reach in units", 100, 50000),
	tractorPlayers = CreateConVar("starcore_tractor_players", "0", FLAGS, "Tractor beams may grab players who are not friends", 0, 1),
	allowCloak   = CreateConVar("starcore_allow_cloak", "1", FLAGS, "Ships may cloak", 0, 1),
	allowFleet   = CreateConVar("starcore_allow_fleet", "1", FLAGS, "Ships may fly in fleets", 0, 1),
	allowSelfDestruct = CreateConVar("starcore_allow_selfdestruct", "1", FLAGS, "Owners may self-destruct their ships", 0, 1),
	selfDestructDamage = CreateConVar("starcore_selfdestruct_damage", "1000", FLAGS, "Highest blast damage of a self-destruct: cap for the size the owner picks (0 = no damage)", 0, 10000),
	-- (the author's play test) "The ship is under attack" at most once in this many seconds per ship (0 = never)
	attackNotice = CreateConVar("starcore_attack_notice", "120", FLAGS, "Seconds between two 'ship under attack' messages of one ship (0 = none)", 0, 1800),
	-- (alone he could not fight his own second ship) own ships count as other ships for weapons
	shootOwnShips = CreateConVar("starcore_shoot_own_ships", "1", FLAGS, "Ships may target and shoot back at other ships of the same owner", 0, 1),
	carryPlayers = CreateConVar("starcore_jump_carry_players", "1", FLAGS, "Players standing inside a ship jump with it", 0, 1),
}
if SERVER then
	CreateConVar("sbox_maxstarcores", "2", { FCVAR_ARCHIVE, FCVAR_NOTIFY }, "Most StarCores per player")
end
-- AGP: the cleanup type on both sides (was server only: no "StarCores" line in the client's Cleanup menu); its names
-- Cleanup_starcores / Cleaned_starcores / SBoxLimit_starcores are in resource/localization/*/starcore.properties
cleanup.Register("starcores")
if CLIENT then
	-- every player picks how jumps look for them: 1 = light streak (default), 2 = instant flash, 3 = portal window
	CreateClientConVar("starcore_jump_style", "1", true, false, "StarCore jump look: 1 light streak, 2 flash, 3 portal", 1, 3)
	CreateClientConVar("starcore_hud", "1", true, false, "Show the StarCore pilot HUD", 0, 1)
	-- (the HUD next to the health box, two rows, "4 different variations"; then "i want style 4 as default"), drawn
	-- in cl_hud.lua
	CreateClientConVar("starcore_hud_look", "1", true, false, "StarCore pilot HUD look: 1 slim (default), 2 ship theme, 3 panels with bars", 1, 3)
	CreateClientConVar("starcore_unit_distance", "0", true, false, "StarCore distance/speed unit: 0 auto, 1 metres, 2 feet, 3 game units", 0, 3)
	-- sent to the server (userinfo): the helm reads them for the pilot
	CreateClientConVar("starcore_mouse_steer", "0", true, true, "StarCore: steer the ship with the mouse in the pilot seat (X turns, Y pitches)", 0, 1)
	CreateClientConVar("starcore_mouse_sens", "1", true, true, "StarCore: mouse steering sensitivity", 0.2, 3)
	-- free flight: the mouse turns the nose any way (loops), A/D roll, nothing levels the ship; off = the helm as
	-- always (level, the nose at most 30 degrees up or down)
	--
	CreateClientConVar("starcore_free_flight", "0", true, true, "StarCore: free flight - the mouse turns the ship any way, A/D roll, no levelling", 0, 1)
	-- keys of the pilot seat (a Workshop player: look around as a switch, keys for mouse steering and hover), picked in
	-- the menu's Settings tab (cl_hud.lua). 0 = no key. Look around: Alt by default, held or tapped on/off. Defaults M
	-- / H / J: free in Garry's Mod's default keys and in none of our addons.
	CreateClientConVar("starcore_key_look", tostring(KEY_LALT), true, false, "StarCore: key to look around in the pilot seat (0 = none)")
	CreateClientConVar("starcore_look_toggle", "0", true, false, "StarCore: 0 = hold the look-around key, 1 = tap it on/off", 0, 1)
	CreateClientConVar("starcore_key_mouse", tostring(KEY_M), true, false, "StarCore: key to switch mouse steering on/off (0 = none)")
	CreateClientConVar("starcore_key_hover", tostring(KEY_H), true, false, "StarCore: key to switch hover on/off (0 = none)")
	CreateClientConVar("starcore_key_freeze", tostring(KEY_J), true, false, "StarCore: key to freeze / unfreeze the ship (0 = none)")
	-- H J K L in one row
	CreateClientConVar("starcore_key_tractor", tostring(KEY_K), true, false, "StarCore: key for the tractor beam: grab what you look at / let go (0 = none)")
	CreateClientConVar("starcore_key_cloak", tostring(KEY_L), true, false, "StarCore: key to cloak / decloak the ship (0 = none)")
	-- I = pull in, O = push out (free in Garry's Mod's default keys and in none of our addons)
	--
	CreateClientConVar("starcore_key_tractor_pull", tostring(KEY_I), true, false, "StarCore: key for the tractor beam: pull in (again = just hold) (0 = none)")
	CreateClientConVar("starcore_key_tractor_push", tostring(KEY_O), true, false, "StarCore: key for the tractor beam: push away (again = just hold) (0 = none)")
	-- (carriers - "do 1 it sounds great"): dock into the bigger ship you are in / undock
	CreateClientConVar("starcore_key_dock", tostring(KEY_N), true, false, "StarCore: key to dock into a bigger ship / undock (0 = none)")
	-- the pilot's and gunners' aim: auto (the radar target) or the own crosshair
	CreateClientConVar("starcore_key_aim", tostring(MOUSE_MIDDLE), true, false, "StarCore: key to switch the weapons between auto aim and your crosshair (0 = none)")
	CreateClientConVar("starcore_looking", "0", false, true, "StarCore: set by the look-around key (the helm then ignores the mouse)", 0, 1)
end

-- our own links: fill in once they exist (empty = no button)
StarCore.Links = {
	GitHub = "https://github.com/moonrise420/starcore",
	Workshop = "https://steamcommunity.com/sharedfiles/filedetails/?id=3840678974",
	Tip = "https://www.paypal.me/soulridejourney", -- a tip / donation page (Ko-fi, PayPal.me, ...): the menu shows a "Support / Tip" button
}

-- per-ship defaults (the owner can change them in the menu, within the server limits)
StarCore.Defaults = {
	speed = 800,       -- forward speed (u/s)
	boost = 2,         -- Shift multiplies the speed
	climb = 300,       -- up/down speed (u/s)
	turn = 35,         -- turn rate (degrees per second)
	accel = 600,       -- how fast the ship reaches its speed (u/s per second)
	charge = 3,        -- jump charge time (s)
	cooldown = 6,      -- time between jumps (s)
	idleFreeze = 60,   -- freeze the hovering ship after this many idle seconds (0 = never)
	public = false,    -- everyone may fly / use the menu (otherwise owner + prop protection friends)
	radarRange = 15000, -- radar range (units), capped by starcore_radar_range
	autoDefence = false, -- shoot back at whoever attacks the ship
	shieldAuto = false, -- raise the shield when the ship is hit
	shieldSize = 0,     -- shield size (0 = leave the generator's own size)
	shieldStrength = 0, -- CAP strength preset -5..5 (0 = normal)
	shieldFreq = -1,    -- CAP shield frequency 0..1500 (-1 = leave it)
	theme = 1,          -- look of screens, menu accents and HUD (see StarCore.Themes)
	destructSize = 2,   -- self-destruct blast: 1 small, 2 medium, 3 large, 4 XL, 5 XXL (see StarCore.DestructSizes)
	name = "",          -- ship name (a new core gets a random one, sv_dock.lua), shown on radar, HUD and screens
	regno = "",         -- hull number, e.g. "SC-1042" (tells two ships with the same name apart)
	class = "auto",     -- "auto" (from length and weapons) or one of StarCore.ShipClasses
}

-- ship names and classes. The class comes from the ship's length and whether it has weapons, unless a player picks
-- one: a big ship without weapons is a freighter, with weapons a cruiser or capital ship. Carrier and station only
-- when picked by hand.
StarCore.ShipClasses = { "shuttle", "transport", "freighter", "fighter", "frigate", "cruiser", "capital", "carrier", "station" }
-- (24 letters, and the HUD, screens and radar show at most StarCore.NameShow of them)
--
StarCore.NameMax, StarCore.RegNoMax, StarCore.NameShow = 20, 12, 20   --
function StarCore.AutoClass(length, armed)
	if armed then
		if length < 500 then return "fighter" elseif length < 1200 then return "frigate" elseif length < 3000 then return "cruiser" end
		return "capital"
	end
	if length < 500 then return "shuttle" elseif length < 1500 then return "transport" end
	return "freighter"
end
function StarCore.ValidClass(id)
	if id == "auto" then return true end
	for _, c in ipairs(StarCore.ShipClasses) do if c == id then return true end end
	return false
end
-- names a new core may get (our own list; no ship names from films or series)
StarCore.ShipNames = {
	"Kestrel", "Halcyon", "Wayfarer", "Nightingale", "Polaris", "Meridian", "Vigilant", "Morning Star", "Silver Wake",
	"Lantern", "Far Horizon", "Ember", "Stormcrow", "Starling", "Northwind", "Quiet Thunder", "Solace", "Brightwater",
	"Ironbark", "Pathfinder", "Wanderer", "Blue Heron", "Long Shadow", "Driftwood", "Sentinel", "Cinder", "Seraph",
	"Mistral", "Copper Sun", "Arrowhead", "Tidewalker", "Lodestar", "Vesper", "Greyhound", "Skylark", "Tempest",
	"Highland", "Radiant", "Dawnlight", "Stillwater", "Ravenwing", "Amber Comet", "Pale Moon", "Old Faithful",
	"Graceful Fury", "Second Chance", "Free Spirit", "Hearthstone", "Swift Answer", "Glimmer", "Bulwark", "Corona",
	"Nomad", "Zephyr", "Kingfisher", "Harbinger", "Daybreak", "Wild Rose", "Steadfast", "Deepwater",
}

-- self-destruct sizes: radius factor and blast damage (the damage is capped by starcore_selfdestruct_damage)
StarCore.DestructSizes = {
	{ id = "small",  radius = 0.8,  damage = 100 },
	{ id = "medium", radius = 1.3,  damage = 200 },
	{ id = "large",  radius = 2,    damage = 350 },
	{ id = "xl",     radius = 3,    damage = 550 },
	{ id = "xxl",    radius = 4.5,  damage = 800 },
}
-- blast radius + damage for a ship of this size (length of its box) and size level; shared so the menu can show them
function StarCore.DestructBlast(shipSize, level)
	local d = StarCore.DestructSizes[level or 2] or StarCore.DestructSizes[2]
	local radius = math.min(math.max(shipSize * 0.6, 250) * d.radius, 12000)
	return radius, math.min(d.damage, StarCore.CV.selfDestructDamage:GetFloat())
end
StarCore.MaxMarks = 8

-- core designs: our own core models (Sketchfab, CC BY 4.0 - authors in CREDITS.md and lua/starcore/sh_license.lua),
-- converted by a build script One spawn menu entry per design; the Ship tab changes a placed core live. This is the only
-- place that maps a design to its model: the entity, spawn menu, tool and menu all read it from here.
StarCore.Designs = {
	{ id = "reactor_core",     family = "reactor",  model = "models/starcore/cores/reactor_core.mdl" },
	{ id = "reactor_bak",      family = "reactor",  model = "models/starcore/cores/reactor_bak.mdl" },
	{ id = "reactor_cell",     family = "reactor",  model = "models/starcore/cores/reactor_cell.mdl" },
	{ id = "crystal_cluster",  family = "crystal",  model = "models/starcore/cores/crystal_cluster.mdl" },
	{ id = "crystal_heart",    family = "crystal",  model = "models/starcore/cores/crystal_heart.mdl" },
	{ id = "crystal_energy",   family = "crystal",  model = "models/starcore/cores/crystal_energy.mdl" },
	{ id = "alien_prism",      family = "alien",    model = "models/starcore/cores/alien_prism.mdl" },
	{ id = "alien_artifact",   family = "alien",    model = "models/starcore/cores/alien_artifact.mdl" },
	{ id = "alien_tesseract",  family = "alien",    model = "models/starcore/cores/alien_tesseract.mdl" },
	{ id = "military_battery", family = "military", model = "models/starcore/cores/military_battery.mdl" },
	{ id = "military_cell",    family = "military", model = "models/starcore/cores/military_cell.mdl" },
	{ id = "military_case",    family = "military", model = "models/starcore/cores/military_case.mdl" },
}
-- the first four design ids (base-game placeholder models): old dupes, saved spawn lists and tool settings
-- keep working and get the best new model of their family
StarCore.DesignAliases = { reactor = "reactor_core", crystal = "crystal_cluster", alien = "alien_prism", military = "military_battery" }
-- any id (old ones too) -> a valid design id
function StarCore.DesignId(id)
	id = StarCore.DesignAliases[id] or id
	for _, d in ipairs(StarCore.Designs) do if d.id == id then return id end end
	return StarCore.Designs[1].id
end
function StarCore.DesignModel(id)
	id = StarCore.DesignId(id)
	for _, d in ipairs(StarCore.Designs) do if d.id == id then return d.model end end
end

-- looks for screens and HUD: neutral (standalone) + Stargate-flavoured ones
StarCore.Themes = {
	-- the first one is the look of all our addons (Ascension Gates, PowerGrid): dark blue, blue accent, light text
	{ id = "neutral",  bg = Color(14, 20, 30, 245), accent = Color(56, 150, 240), fg = Color(225, 235, 245), title = Color(255, 255, 255), warn = Color(255, 90, 70), button = Color(36, 52, 76), hover = Color(52, 80, 118) },
	{ id = "goauld",   bg = Color(25, 15, 5, 235),  accent = Color(200, 140, 30), fg = Color(255, 210, 120), title = Color(40, 20, 0),     warn = Color(255, 70, 40), button = Color(70, 45, 15), hover = Color(110, 70, 20) },
	{ id = "lcars",    bg = Color(0, 0, 0, 240),    accent = Color(255, 153, 0),  fg = Color(204, 153, 204), title = Color(0, 0, 0),       warn = Color(255, 60, 60), button = Color(153, 153, 204), hover = Color(204, 153, 102) },
	{ id = "ancient",  bg = Color(5, 25, 30, 235),  accent = Color(60, 200, 190), fg = Color(170, 255, 245), title = Color(0, 30, 30),     warn = Color(255, 100, 80), button = Color(20, 70, 75), hover = Color(30, 110, 110) },
	{ id = "military", bg = Color(15, 20, 12, 235), accent = Color(110, 140, 60), fg = Color(200, 230, 170), title = Color(10, 15, 5),     warn = Color(255, 110, 40), button = Color(45, 60, 30), hover = Color(70, 90, 45) },
}

-- our own icon for the StarCore category in the spawn menu
list.Set("ContentCategoryIcons", "StarCore", "gui/starcore_logo.png")

-- StarCore seats: normal GMod seats that already know their ship role
for _, s in ipairs({
	{ id = "captain", model = "models/nova/chair_office02.mdl", role = "pilot" },
	{ id = "pilot", model = "models/nova/jeep_seat.mdl", role = "pilot" },
	{ id = "gunner", model = "models/nova/airboat_seat.mdl", role = "gunner" },
	{ id = "engineer", model = "models/nova/chair_office01.mdl", role = "engineer" },
}) do
	list.Set("Vehicles", "starcore_seat_" .. s.id, {
		Name = "StarCore: " .. s.id:sub(1, 1):upper() .. s.id:sub(2), Model = s.model, Class = "prop_vehicle_prisoner_pod", Category = "StarCore",
		Information = "StarCore " .. s.role .. " seat",
		KeyValues = { vehiclescript = "scripts/vehicles/prisoner_pod.txt", limitview = "0" },
		StarCoreRole = s.role,
	})
end

-- FTL states (shared so the HUD can show them)
StarCore.FTL = { IDLE = 0, CHARGING = 1, JUMPING = 2, COOLDOWN = 3 }

-- who may control a core: owner, prop protection friends, admins in public-off mode, everyone in public mode
-- strict: public mode does not count (owner, friends and admins only; e.g. changing the core design)
function StarCore.CanControl(core, ply, strict)
	if not IsValid(core) or not IsValid(ply) then return false end
	if not strict and core:GetNWBool("starcore_public", false) then return true end
	local owner = core.CPPIGetOwner and core:CPPIGetOwner() or core:GetNWEntity("starcore_owner")
	if not IsValid(owner) then owner = core:GetNWEntity("starcore_owner") end
	if owner == ply or ply:IsAdmin() then return true end
	if IsValid(owner) and owner.CPPIGetFriends then
		local friends = owner:CPPIGetFriends()
		if istable(friends) and table.HasValue(friends, ply) then return true end
	end
	return false
end

-- which optional addons are there (level 2: Wiremod, level 3: a Stargate pack)
function StarCore.HasWire() return WireLib ~= nil end
function StarCore.HasStargate() return StarGate ~= nil end

if CLIENT then
	-- texts live in resource/localization/<lang>/starcore.properties ("#starcore.x"). With Ascension Gates installed
	-- they follow the language the player chose for it (sg_language, which starts as GMod's language), so all our
	-- addons speak one language; without it GMod's own language (GMod reads the file itself then).
	local props, propsLang, propsAt = {}, nil, 0
	local function readProps(code)
		local t = {}
		local raw = file.Read("resource/localization/" .. code .. "/starcore.properties", "GAME")
		if (not raw) then return nil end
		for line in raw:gmatch("[^\r\n]+") do
			local k, v = line:match("^%s*([^#=][^=]-)%s*=%s*(.-)%s*$")
			if (k) then t[k] = v end
		end
		return t
	end
	local function sgTable()
		if (CurTime() < propsAt) then return props end
		propsAt = CurTime() + 2
		local sg = GetConVar("sg_language")
		local code = sg and string.lower(sg:GetString()) or ""
		if (code == "" or code == string.lower(GetConVarString("gmod_language") or "")) then props, propsLang = nil, nil return nil end
		if (code ~= propsLang) then
			propsLang = code
			props = readProps(code) or readProps(code:match("^(%a+)") or "") or nil
		end
		return props
	end
	function StarCore.T(key, ...)
		local t = sgTable()
		local s = (t and t["starcore." .. key]) or language.GetPhrase("starcore." .. key)
		if select("#", ...) > 0 then
			local ok, f = pcall(string.format, s, ...)
			if ok then s = f end
		end
		return s
	end

	-- units: every player picks their own (starcore_unit_distance); 1 game unit = 1 inch, 39.37 units = 1 m
	StarCore.Units = StarCore.Units or {}
	local FEET = { US = true, LR = true, MM = true, BS = true, KY = true, PW = true, FM = true, MH = true }
	local cvUnit = GetConVar("starcore_unit_distance")
	function StarCore.Units.Mode() -- 1 m, 2 ft, 3 u (0 auto: feet for the US and a few others, else metres)
		local m = cvUnit:GetInt()
		if m < 1 or m > 3 then m = FEET[system.GetCountry() or ""] and 2 or 1 end
		return m
	end
	local PER = { 39.37, 12, 1 } -- game units per metre / foot / unit
	local NAME = { "m", "ft", "u" }
	function StarCore.Units.Per() return PER[StarCore.Units.Mode()] end -- game units in one shown unit
	function StarCore.Units.Name() return NAME[StarCore.Units.Mode()] end
	-- game units -> "120 m", "3.4 km", "850 ft", "1.2 mi", "4000 u"
	function StarCore.Units.Dist(u)
		local m = StarCore.Units.Mode()
		u = tonumber(u) or 0
		if m == 1 then
			local v = u / 39.37
			if math.abs(v) >= 1000 then return string.format("%.1f km", v / 1000) end
			return math.Round(v) .. " m"
		elseif m == 2 then
			local v = u / 12
			if math.abs(v) >= 5280 then return string.format("%.1f mi", v / 5280) end
			return math.Round(v) .. " ft"
		end
		return math.Round(u) .. " u"
	end
	-- height over the ground (StarCore.HeightOverGround): below 0 = no ground below (space) -> a dash
	function StarCore.Units.Alt(u)
		u = tonumber(u) or 0
		if u < 0 then return "-" end
		return StarCore.Units.Dist(u)
	end
	-- game units per second -> "20 m/s", "66 ft/s", "800 u/s"
	function StarCore.Units.Speed(u)
		return math.Round((tonumber(u) or 0) / StarCore.Units.Per()) .. " " .. StarCore.Units.Name() .. "/s"
	end
end
