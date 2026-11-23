-- StarCore server: sensors (radar contacts with friend/foe) and weapons (aim with lead, line of sight, auto-defence).
-- Owner, crew and prop-protection friends can never be targeted. Weapons whose Fire input is wired stay under the
-- player's control. Works with any weapon that has Wire inputs "Fire" or "Launch" (+ "Vector"/"Entity"/"Target" to aim): turrets,
-- cannons, rail guns, Wire turrets (those only fire when the target is in front of them).
util.AddNetworkString("starcore_contacts")

local KIND = { player = 1, npc = 2, ship = 3, gate = 4 }
local IFF = { own = 1, crew = 2, friend = 3, neutral = 4, hostile = 5 }
StarCore.KIND, StarCore.IFF = KIND, IFF

-- projectile speed per weapon class (for aiming ahead); unknown classes use the default
local SPEED = { sg_turret_ = 14000, staff_stationary = 3000, hatak_staff_cannon = 1800, wraith_plasma_cannon = 4000,
	vanir_plasma_cannon = 4000, stationary_railgun = 30000, gmod_wire_turret = 50000,
	asgard_beam = 1e9, ori_beam_cannon = 1e9 }   -- (beams: no flight time, aimed straight at the target)
local function projectileSpeed(w)
	local c = w:GetClass()
	for prefix, v in pairs(SPEED) do if c:sub(1, #prefix) == prefix then return v end end
	return 6000
end

local function ownerOf(ent)
	if not IsValid(ent) then return nil end
	if ent:IsPlayer() then return ent end
	local o = ent.CPPIGetOwner and ent:CPPIGetOwner()
	if not IsValid(o) and ent.GetCreator then o = ent:GetCreator() end
	if not IsValid(o) and ent:GetClass() == "starcore" then o = ent:GetNWEntity("starcore_owner") end
	return IsValid(o) and o or nil
end

local function isFriend(a, b)
	if not IsValid(a) or not IsValid(b) then return false end
	if a == b then return true end
	for _, pair in ipairs({ { a, b }, { b, a } }) do
		if pair[1].CPPIGetFriends then
			local f = pair[1]:CPPIGetFriends()
			if istable(f) and table.HasValue(f, pair[2]) then return true end
		end
	end
	return false
end

-- the input that fires a weapon: "Fire" - or "Launch" on the drone launchers (AGP's drone_launcher and
-- launcher_drones,: the author wants every AGP weapon usable by the pilot and the gunners) AGP pieces
-- that are no ship's guns although they have a Fire input: a ship does not fire them, welded on or not (Asgard
-- beam, Ha'tak staff cannon, drone launcher, Ori beam cannon, the Destiny main weapon and turrets, ship rail gun, ion
-- cannon, Vanir and Wraith plasma cannons)
local NOT_SHIP_WEAPON = { ag_3 = true, asuran_gate_weapon = true, gate_overloader = true, minidrone_platform = true,
	ori_satellite = true, staff_stationary = true, stationary_railgun = true }
StarCore.NotShipWeapon = NOT_SHIP_WEAPON
local function fireInput(w)
	local i = w.Inputs
	if not i or NOT_SHIP_WEAPON[w:GetClass()] then return nil end
	return i.Fire and "Fire" or i.Launch and "Launch" or nil
end
StarCore.FireInput = fireInput

local function wired(ent, input)
	local inp = ent.Inputs and ent.Inputs[input]
	return inp ~= nil and IsValid(inp.Src)
end

-- which part of which ship (for "who shot at us")
StarCore.PartCore = StarCore.PartCore or setmetatable({}, { __mode = "k" })

function StarCore.CombatAttach(core)
	core.Weapons = {}
	-- AGP: a part taken off the ship stayed marked as part of it (hits on it still damaged the ship's hull, counted as
	-- "our own" for hostiles, the repair tool and tractor beam). Parts this core marked last time and no longer has
	-- lose the mark (unless another ship has taken them since)
	local marked = {}
	for _, e in ipairs(core.Parts or {}) do
		if IsValid(e) then
			StarCore.PartCore[e] = core
			marked[e] = true
			if fireInput(e) and e ~= core and #core.Weapons < StarCore.CV.maxWeapons:GetInt() then
				core.Weapons[#core.Weapons + 1] = e
			end
		end
	end
	for e in pairs(core.CombatMarked or {}) do
		if not marked[e] and StarCore.PartCore[e] == core then StarCore.PartCore[e] = nil end
	end
	core.CombatMarked = marked
	core:SetNWInt("starcore_weapons", #core.Weapons)
end

local function iffOf(core, ent)
	local owner = core:GetNWEntity("starcore_owner")
	local h = core.Hostiles and core.Hostiles[ent]
	if ent:IsPlayer() then
		if ent == owner then return IFF.own end
		if (ent:InVehicle() and core.Seats and table.HasValue(core.Seats, ent:GetVehicle())) or StarCore.IsInside(core, ent) then return IFF.crew end
		if isFriend(owner, ent) then return IFF.friend end
		if h and h > CurTime() then return IFF.hostile end
		return IFF.neutral
	elseif ent:IsNPC() then
		if h and h > CurTime() then return IFF.hostile end
		if IsValid(owner) and ent.Disposition and ent:Disposition(owner) == D_HT then return IFF.hostile end
		return IFF.neutral
	elseif ent:GetClass() == "starcore" then
		local o = ownerOf(ent)
		-- (alone he could not fight his own second ship) starcore_shoot_own_ships: another ship of the same owner is a
		-- ship like any other - neutral, hostile once it shot at this one
		if o == owner then
			if not StarCore.CV.shootOwnShips:GetBool() then return IFF.own end
			if h and h > CurTime() then return IFF.hostile end
			return IFF.neutral
		end
		if isFriend(owner, o) then return IFF.friend end
		if h and h > CurTime() then return IFF.hostile end
		if o and core.Hostiles and core.Hostiles[o] and core.Hostiles[o] > CurTime() then return IFF.hostile end
		return IFF.neutral
	end
	return IFF.neutral
end

local function targetable(core, c)
	if c.kind == KIND.gate then return false end
	if c.iff == IFF.own or c.iff == IFF.crew or c.iff == IFF.friend then return false end
	if c.kind == KIND.player and not StarCore.CV.targetPlayers:GetBool() then return false end
	return true
end
StarCore.Targetable = targetable

-- builds core.Contacts (sorted: hostiles first, then by distance)
function StarCore.SensorScan(core)
	local center = StarCore.ShipCenter and StarCore.ShipCenter(core) or core:GetPos()
	local range = math.min(core.Settings.radarRange or 15000, StarCore.CV.radarRange:GetFloat())
	local r2 = range * range
	local list = {}
	local function add(ent, kind)
		local d2 = ent:GetPos():DistToSqr(center)
		if d2 > r2 then return end
		local c = { ent = ent, kind = kind, dist = math.sqrt(d2) }
		c.iff = iffOf(core, ent)
		list[#list + 1] = c
	end
	for _, p in ipairs(player.GetAll()) do if p:Alive() then add(p, KIND.player) end end
	for _, n in ipairs(ents.FindByClass("npc_*")) do if IsValid(n) and n:IsNPC() and n:Health() > 0 then add(n, KIND.npc) end end
	for _, n in ipairs(ents.FindByClass("nextbot_*")) do if IsValid(n) then add(n, KIND.npc) end end
	for other in pairs(StarCore.Cores) do
		if IsValid(other) and other ~= core and not other.Sleeping then
			if not other.Cloaked or isFriend(core:GetNWEntity("starcore_owner"), other:GetNWEntity("starcore_owner")) then add(other, KIND.ship) end
		end
	end
	if StarGate then
		for _, g in ipairs(ents.FindByClass("stargate_*")) do
			if IsValid(g) and g.IsStargate and g ~= core.Gate then add(g, KIND.gate) end
		end
	end
	table.sort(list, function(a, b)
		local ha, hb = a.iff == IFF.hostile, b.iff == IFF.hostile
		if ha ~= hb then return ha end
		return a.dist < b.dist
	end)
	core.Contacts = list
	-- the selected target leaves the list -> drop it (unless locked)
	if IsValid(core.Target) and not core.TargetLock then
		local still = false
		for _, c in ipairs(list) do if c.ent == core.Target then still = true break end end
		if not still then core.Target = nil end
	end
	if core.Target ~= nil and not IsValid(core.Target) then core.Target = nil end
	core:SetNWEntity("starcore_target", core.Target or NULL)
end

function StarCore.ContactOf(core, ent)
	for _, c in ipairs(core.Contacts or {}) do if c.ent == ent then return c end end
end

-- next / previous target (only targetable contacts and gates for warping)
function StarCore.CycleTarget(core, dir)
	local list = core.Contacts or {}
	if #list == 0 then core.Target = nil return end
	local idx = 0
	for i, c in ipairs(list) do if c.ent == core.Target then idx = i end end
	for _ = 1, #list do
		idx = idx + dir
		if idx > #list then idx = 1 elseif idx < 1 then idx = #list end
		local c = list[idx]
		if c.iff ~= IFF.own then core.Target = c.ent break end
	end
	core:SetNWEntity("starcore_target", core.Target or NULL)
end

-- "who shot at us": the attacker (or the owner of the prop/vehicle that did it) becomes hostile for 2 minutes
hook.Add("EntityTakeDamage", "StarCore.Hostiles", function(ent, dmg)
	local core = StarCore.PartCore[ent]
	if not IsValid(core) then return end
	-- (the ship's own shots, drones and blasts: no attack - AGP knows what belongs to which ship)
	if StarGate and StarGate.OwnShipDamage and StarGate.OwnShipDamage(ent, dmg) then return end
	local att = dmg:GetAttacker()
	if not IsValid(att) or att:IsWorld() then return end
	if att:IsVehicle() and IsValid(att:GetDriver()) then att = att:GetDriver() end
	if StarCore.PartCore[att] == core then return end -- our own guns
	local otherCore = StarCore.PartCore[att]
	-- another ship of the same owner shooting at this one: with starcore_shoot_own_ships that ship is hostile now
	-- (auto-defence answers it), its owner - our own owner - is not
	local own = IsValid(otherCore) and StarCore.CV.shootOwnShips:GetBool() and ownerOf(otherCore) == core:GetNWEntity("starcore_owner")
	local src = (att:IsPlayer() or att:IsNPC()) and att or ownerOf(att) or att
	if not IsValid(src) then return end
	if src:IsPlayer() and iffOf(core, src) <= IFF.friend and not own then return end
	core.Hostiles = core.Hostiles or {}
	local now = CurTime()
	if not own then core.Hostiles[src] = now + 120 end
	if IsValid(otherCore) then core.Hostiles[otherCore] = now + 120 end
	-- "The ship is under attack": at most once in starcore_attack_notice seconds per ship (far too often - it was once per
	-- attacker, and a shot without an owner counted as a new attacker each time)
	local every = StarCore.CV.attackNotice:GetFloat()
	if every > 0 and now >= (core.NextAttackNote or 0) then
		core.NextAttackNote = now + every
		StarCore.NotifyShip(core, "under_attack", NOTIFY_ERROR)
		hook.Run("StarCore.Event", core, "under_attack")
	end
end)

-- aim point with lead (two passes: distance -> flight time -> moved target)
local function aimPoint(w, target)
	local pos = target:LocalToWorld(target:OBBCenter())
	local vel = target:GetVelocity()
	local speed = projectileSpeed(w)
	local aim = pos
	for _ = 1, 2 do
		local t = w:GetPos():Distance(aim) / speed
		aim = pos + vel * t
	end
	return aim
end
StarCore.AimPoint = aimPoint

-- the weapon itself and its own moving parts (CAP turrets: stand, turn, cannon) never block its shot
local function weaponParts(w)
	local list = { w }
	for _, k in ipairs({ "Cann", "Turn", "Stand", "Cann1", "Cann2", "Cann3", "Cann4" }) do if IsValid(w[k]) then list[#list + 1] = w[k] end end   -- (Cann1-4: the Destiny turrets' barrels)
	for _, c in ipairs(w:GetChildren()) do list[#list + 1] = c end
	return list
end

-- clear shot? Our OWN ship in the way counts as blocked (in-game test: a turret shot into the ship's
-- other turret), so the trace starts just outside the weapon and ignores only the weapon's own parts A
-- turret's barrel (a ship's weapons never fire into their own ship): AGP turrets fire every tick while Fire is 1,
-- also while they still turn; their shot goes from the muzzle to the aim point only when the barrel points within
-- about 25 degrees of it (sg_turret_base AimDirFrom), else straight along the barrel - which can be into the own ship.
-- So a turret gets Fire only when its barrel points at the aim, and the clear line is checked from its muzzle.
-- Returns barrel, muzzle position, barrel direction - or nil for a weapon without a barrel.
local BACKWARD = { sg_turret_destmed = true, sg_turret_destmain = true }   -- (their barrels look along -forward)
local MUZZLE = { "Fire", "FIRE", "Fire1", "FireTop" }
local function barrelOf(w)
	local b = IsValid(w.Cann) and w.Cann or IsValid(w.Cann1) and w.Cann1 or nil
	if not b then return nil end
	local dir = b:GetForward()
	if BACKWARD[w:GetClass()] then dir = -dir end
	local pos
	for _, name in ipairs(MUZZLE) do
		local id = b:LookupAttachment(name)
		local a = id and id > 0 and b:GetAttachment(id)
		if a then pos = a.Pos break end
	end
	return b, pos or b:WorldSpaceCenter(), dir
end
StarCore.BarrelOf = barrelOf
local AIMED = 0.92   -- (cos 23 degrees: inside AGP's 25.8)

-- a shield bubble of this ship (the shield generator is one of its parts): the line goes on through it
local function ownShield(core, e)
	local c = e:GetClass()
	if c ~= "shield" and c ~= "shield_core_buble" then return false end
	local gen = e.Parent or e:GetParent() or e:GetOwner()
	return IsValid(gen) and StarCore.PartCore[gen] == core
end

local function lineOfSight(core, w, target, aim)
	local _, muzzle, bdir = barrelOf(w)
	local start
	if muzzle then
		if bdir:Dot((aim - muzzle):GetNormalized()) < AIMED then return false end   -- (still turning)
		start = muzzle
	else
		local from = w:WorldSpaceCenter()
		start = from + (aim - from):GetNormalized() * (w:BoundingRadius() + 4)
	end
	local filter = weaponParts(w)
	local tr
	for _ = 1, 4 do
		tr = util.TraceLine({ start = start, endpos = aim, filter = filter, mask = MASK_SHOT })
		if not (tr.Hit and IsValid(tr.Entity) and ownShield(core, tr.Entity)) then break end
		filter[#filter + 1] = tr.Entity
	end
	if not tr.Hit then return true end
	local e = tr.Entity
	if not IsValid(e) then return false end
	if e == target or (target:IsPlayer() and e == target:GetVehicle()) or e:GetParent() == target then return true end
	-- another ship: hitting any of its parts is fine when that ship is the target
	return target:GetClass() == "starcore" and StarCore.PartCore[e] == target
end

local function setInput(w, name, value)
	if w.Inputs and w.Inputs[name] and w.TriggerInput then
		w.Inputs[name].Value = value
		w:TriggerInput(name, value)
	end
end

local function stopWeapons(core)
	for w in pairs(core.Firing or {}) do
		local fi = IsValid(w) and fireInput(w)
		if fi and not wired(w, fi) then
			setInput(w, fi, 0)
			if fi == "Launch" then setInput(w, "Lock", 0); setInput(w, "Open", 0) end   -- (the drone launcher's hatch shuts)
			setInput(w, "Active", 0)
		end
	end
	core.Firing = {}
	core:SetNWBool("starcore_engaging", false)
end
StarCore.StopWeapons = stopWeapons

-- Aiming by hand. A pilot or gunner whose own game is on crosshair aim (cl_hud.lua, key starcore_key_aim; gunners
-- start on it) sends the point under the crosshair 10 times a second. Holding fire, every weapon of the ship
-- goes for that point - no radar target needed. Turrets turn to it and fire at once, also while still turning - their
-- shots leave along the barrel until it is on the point. But never while the shot's real way goes into the own ship
-- (it just does not shoot when the barrel looks at the hull): checked along the barrel, or to the point once the
-- barrel is near enough for AGP's turrets to send the shot there (within about 25 degrees). (AGP's shots that touch
-- their own ship anyway fly through it without harm - the safety net, not the rule.)
--
--
local NEAR = 0.9   -- (sg_turret_base AimDirFrom: dot > 0.9 = the shot goes from the muzzle to the aim point)
local function ownShipInWay(core, w, p)
	local _, muzzle, bdir = barrelOf(w)
	local start, dir, len
	if muzzle then
		local to = (p - muzzle):GetNormalized()
		dir = bdir:Dot(to) > NEAR and to or bdir
		start, len = muzzle, math.min(muzzle:Distance(p), 6000)
	else
		local from = w:WorldSpaceCenter()
		dir = (p - from):GetNormalized()
		start, len = from + dir * (w:BoundingRadius() + 4), math.min(from:Distance(p), 6000)
	end
	local filter = weaponParts(w)
	local tr
	for _ = 1, 4 do
		tr = util.TraceLine({ start = start, endpos = start + dir * len, filter = filter, mask = MASK_SHOT })
		if not (tr.Hit and IsValid(tr.Entity) and ownShield(core, tr.Entity)) then break end
		filter[#filter + 1] = tr.Entity
	end
	return tr.Hit and IsValid(tr.Entity) and StarCore.PartCore[tr.Entity] == core
end
StarCore.OwnShipInWay = ownShipInWay
-- The crosshair's point. The player's game sends where its view is and where it looks (cl_hud.lua); the line is traced
-- here, where every part of the ship is known (StarCore.PartCore): it goes through the own ship - hull, turrets and
-- their parts, welded things, the shield bubble, the own shots - to the first thing that is not the ship. (The
-- game's trace only left out the seat and the seat's ship entity: the point landed on the own turrets or hull, the guns
-- held fire, drones flew into the own ship.)
--
local AIM_REACH = 60000
util.AddNetworkString("starcore_aim")
net.Receive("starcore_aim", function(_, ply)
	local from, dir = net.ReadVector(), net.ReadNormal()
	if not ply:InVehicle() then return end
	local veh = ply:GetVehicle()
	local core = StarCore.PartCore[veh] or (IsValid(veh:GetParent()) and StarCore.PartCore[veh:GetParent()])
	-- (the view is behind the ship at most a few ship lengths: farther, it is taken from the player's own eyes)
	local limit = IsValid(core) and core.LocalMins and ((core.LocalMaxs - core.LocalMins):Length() * 3 + 2000) or 20000
	if from:DistToSqr(ply:EyePos()) > limit * limit then from = ply:EyePos() end
	local tr = util.TraceLine({ start = from, endpos = from + dir * AIM_REACH, mask = MASK_SHOT, filter = function(e)
		if e == ply or e == veh then return false end
		if IsValid(core) then
			if StarCore.PartCore[e] == core then return false end
			local par = e:GetParent()
			if IsValid(par) and StarCore.PartCore[par] == core then return false end
			if ownShield(core, e) then return false end
			if e.AGPFrom and StarGate and StarGate.SameShip and StarGate.SameShip(e.AGPFrom, core) then return false end
		end
		return true
	end })
	ply.StarCoreAim, ply.StarCoreAimAt = tr.HitPos, CurTime()
end)
local AIM_FRESH = 0.4   -- (seconds: a player whose game stopped sending is back on auto)
local function aimsByHand(ply) return IsValid(ply) and ply.StarCoreAim ~= nil and CurTime() - (ply.StarCoreAimAt or 0) < AIM_FRESH end
StarCore.AimsByHand = aimsByHand

-- a gunner (or the pilot) on crosshair aim who does not fire: the turrets follow the crosshair all the same, without
-- firing. Drone launchers stay shut.
local function aimAtPoint(core, p)
	core.Firing = core.Firing or {}
	core:SetNWBool("starcore_engaging", false)
	for _, w in ipairs(core.Weapons) do
		local fi = IsValid(w) and fireInput(w)
		if fi and fi ~= "Launch" and not wired(w, fi) and w.Inputs and w.Inputs.Vector then
			setInput(w, "Active", 1)
			setInput(w, "Entity", NULL)
			setInput(w, "Vector", p)
			setInput(w, fi, 0)
			core.Firing[w] = true
		elseif fi and core.Firing[w] and not wired(w, fi) then
			-- fire let go: the drone launchers and fixed guns stop too - only the turrets were told before, the rest
			-- kept firing
			setInput(w, fi, 0)
			if fi == "Launch" then
				-- (no new drones; those in the air keep following the crosshair - with the lock off they flew straight on)
				setInput(w, "Lock", 1); setInput(w, "Target", p)
			end
		end
	end
end

local function fireAtPoint(core, p)
	core.Firing = core.Firing or {}
	if not core:GetNWBool("starcore_engaging") then hook.Run("StarCore.Event", core, "fired") end
	core:SetNWBool("starcore_engaging", true)
	core:SetNWEntity("starcore_firing_at", NULL)
	for _, w in ipairs(core.Weapons) do
		local fi = IsValid(w) and fireInput(w)
		if fi and not wired(w, fi) then
			setInput(w, "Active", 1)
			setInput(w, "Entity", NULL)
			setInput(w, "Vector", p)
			if fi == "Launch" then setInput(w, "Open", 1); setInput(w, "Lock", 1); setInput(w, "Target", p) end
			-- (drones fly round their own ship to the point - AGP lets them pass it: they launch wherever the crosshair
			-- is, also beside or behind the ship.. Guns still hold fire while their shot would go into the own ship.)
			--
			setInput(w, fi, (fi ~= "Launch" and ownShipInWay(core, w, p)) and 0 or 1)
			core.Firing[w] = true
		end
	end
end

-- 10 times a second: who do we shoot at, and do it
function StarCore.WeaponsThink(core)
	if not core.Weapons or #core.Weapons == 0 then
		if core.Firing and next(core.Firing) then stopWeapons(core) end
		return
	end
	local target
	local pilot = IsValid(core.PilotSeat) and core.PilotSeat:GetDriver()
	if core.Disabled then
		if core.Firing and next(core.Firing) then stopWeapons(core) end
		return
	end
	-- aimed by hand: the pilot or a gunner on crosshair aim holding fire (the latest crosshair wins)
	local hand, aimer
	local function consider(d)
		if not (aimsByHand(d) and StarCore.CanControl(core, d)) then return end
		if d:KeyDown(IN_ATTACK) then
			if not hand or d.StarCoreAimAt > hand.StarCoreAimAt then hand = d end
		elseif not aimer or d.StarCoreAimAt > aimer.StarCoreAimAt then
			aimer = d
		end
	end
	if IsValid(pilot) then consider(pilot) end
	for _, g in ipairs(StarCore.CrewIn and StarCore.CrewIn(core, "gunner") or {}) do consider(g) end
	if hand then fireAtPoint(core, hand.StarCoreAim) return end
	local trigger = core.Engage or (IsValid(pilot) and not aimsByHand(pilot) and StarCore.CanControl(core, pilot) and pilot:KeyDown(IN_ATTACK))
	if not trigger and StarCore.CrewIn then
		for _, g in ipairs(StarCore.CrewIn(core, "gunner")) do if not aimsByHand(g) and g:KeyDown(IN_ATTACK) then trigger = true break end end
	end
	local c = IsValid(core.Target) and StarCore.ContactOf(core, core.Target)
	if trigger and c and targetable(core, c) then target = c.ent end
	-- auto-defence: the nearest hostile, if nobody chose a target
	if not target and core.Settings.autoDefence and StarCore.CV.allowAutoDefence:GetBool() then
		for _, k in ipairs(core.Contacts or {}) do
			if k.iff == IFF.hostile and targetable(core, k) then target = k.ent break end
		end
	end
	if not IsValid(target) then
		if aimer then aimAtPoint(core, aimer.StarCoreAim) return end   -- (the turrets follow the crosshair)
		if core.Firing and next(core.Firing) then stopWeapons(core) end
		return
	end
	core.Firing = core.Firing or {}
	if not core:GetNWBool("starcore_engaging") then hook.Run("StarCore.Event", core, "fired") end
	core:SetNWBool("starcore_engaging", true)
	core:SetNWEntity("starcore_firing_at", target)
	for _, w in ipairs(core.Weapons) do
		local fi = IsValid(w) and fireInput(w)
		if fi and not wired(w, fi) then
			local aim = aimPoint(w, target)
			local canAim = w.Inputs.Vector or w.Inputs.Entity or w.Inputs.Target
			local fire = lineOfSight(core, w, target, aim)
			if not canAim then
				-- fixed weapon: only when the target is in front of it (15 degrees)
				local dir = (aim - w:GetPos()):GetNormalized()
				fire = fire and dir:Dot(w:GetForward()) > math.cos(math.rad(15))
			end
			setInput(w, "Active", 1)
			setInput(w, "Vector", aim)
			-- the drone launchers: the hatch open (they launch only then), the drones locked on the target
			if fi == "Launch" then setInput(w, "Open", 1); setInput(w, "Entity", target); setInput(w, "Lock", 1); setInput(w, "Target", aim) end
			setInput(w, fi, fire and 1 or 0)
			core.Firing[w] = true
		end
	end
end

-- contacts for the pilot and everyone with the menu open (2 times a second)
function StarCore.SendContacts(core)
	local to = {}
	local pilot = IsValid(core.PilotSeat) and core.PilotSeat:GetDriver()
	if IsValid(pilot) then to[#to + 1] = pilot end
	for ply, untilT in pairs(core.Viewers or {}) do
		if IsValid(ply) and untilT > CurTime() and ply ~= pilot then to[#to + 1] = ply else core.Viewers[ply] = nil end
	end
	if #to == 0 then return end
	local list = core.Contacts or {}
	local n = math.min(#list, 60)
	net.Start("starcore_contacts")
	net.WriteEntity(core)
	local shipAng = core.Helm and core.Helm.refAng and core:LocalToWorldAngles(core.Helm.refAng) or core:GetAngles()
	net.WriteFloat(shipAng.y)
	net.WriteUInt(n, 7)
	for i = 1, n do
		local c = list[i]
		net.WriteEntity(c.ent)
		net.WriteUInt(c.kind, 3)
		net.WriteUInt(c.iff, 3)
		net.WriteFloat(c.dist)
		net.WriteBool(targetable(core, c))
	end
	net.Send(to)
end

function StarCore.CombatThink(core)
	local now = CurTime()
	if now >= (core.NextSensor or 0) then
		core.NextSensor = now + 0.5
		StarCore.SensorScan(core)
		if core.Screens and #core.Screens > 0 then
			core.Viewers = core.Viewers or {}
			for _, ply in ipairs(player.GetAll()) do
				for _, sc in ipairs(core.Screens) do
					if IsValid(sc) and ply:GetPos():DistToSqr(sc:GetPos()) < 1000 * 1000 then core.Viewers[ply] = CurTime() + 1 break end
				end
			end
		end
		StarCore.SendContacts(core)
	end
	if now >= (core.NextWeapons or 0) then
		core.NextWeapons = now + 0.1
		StarCore.WeaponsThink(core)
	end
end

-- pilot: right mouse = next target
hook.Add("KeyPress", "StarCore.Targets", function(ply, key)
	if key ~= IN_ATTACK2 or not ply:InVehicle() then return end
	local veh = ply:GetVehicle()
	for core in pairs(StarCore.Cores) do
		if IsValid(core) and core.Seats and table.HasValue(core.Seats, veh) and StarCore.CanControl(core, ply) then
			local role = StarCore.SeatRole and StarCore.SeatRole(core, veh) or "pilot"
			if veh == core.PilotSeat or role == "gunner" then StarCore.CycleTarget(core, 1) end
			return
		end
	end
end)
