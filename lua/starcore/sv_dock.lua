-- StarCore server: ship names, hull numbers, classes, and carriers.
--
--
-- Docking: a ship whose middle is inside the box of a bigger StarCore ship (its hangar, or on its deck) locks into it with
-- the dock key (N), the Helm tab button or the Wire input Dock, when it is slow. While docked it flies, freezes and jumps
-- with the big ship and its own helm is off; the same key lets go and it hovers again with the big ship's speed.
-- There is no weld or other constraint between the two ships: the docked ship's parts follow the big ship's core every
-- tick, in the place they had when it docked (StarCore.DockThink), and the big ship moves them as its own parts
-- (StarCore.Scan adds them to its part lists: flying, freezing, jumping). The two ships stay two ships (each its own
-- core, parts, seats, menu, weapons and hull) and the duplicator saves nothing of the docking.
-- (the first version held the ships with a physics weld outside GMod's constraint systems; in 2 of 6 game runs the
-- big ship's own welds slipped with it - its deck plate turned ~15 degrees against its core.)

-- texts from players: no control characters, trimmed, at most max letters (UTF-8 safe)
local function clean(s, max)
	if not isstring(s) then return nil end
	s = s:gsub("%c", ""):gsub("^%s+", ""):gsub("%s+$", "")
	local n = utf8 and utf8.len(s)
	if n and n > max then
		-- (letter by letter: GMod's utf8.offset cut one letter too late in the game test)
		local out, k = {}, 0
		for _, c in utf8.codes(s) do
			k = k + 1
			if k > max then break end
			out[k] = utf8.char(c)
		end
		s = table.concat(out)
	elseif not n then
		s = s:gsub("[\128-\255]", ""):sub(1, max)   -- (broken UTF-8: plain letters only)
	end
	return s
end
StarCore.CleanText = clean

function StarCore.RandomName()
	local list = StarCore.ShipNames
	return list[math.random(#list)]
end

-- a hull number no other ship on the server has right now
function StarCore.RandomRegNo(except)
	local taken = {}
	for _, c in ipairs(ents.FindByClass("starcore")) do
		if c ~= except and c.Settings and isstring(c.Settings.regno) then taken[c.Settings.regno] = true end
	end
	for _ = 1, 30 do
		local no = "SC-" .. math.random(100, 9999)
		if not taken[no] then return no end
	end
	return "SC-" .. math.random(10000, 99999)
end

-- a new core (Initialize): a name and a number; a pasted core keeps the ones of its dupe (merged in after Initialize),
-- but gets a new number when another ship already has that one (two pastes of one dupe)
function StarCore.IdentityNew(core)
	local s = core.Settings
	if not isstring(s.name) or s.name == "" then s.name = StarCore.RandomName() end
	if not isstring(s.regno) or s.regno == "" then s.regno = StarCore.RandomRegNo(core) end
	if not StarCore.ValidClass(s.class) then s.class = "auto" end
end
function StarCore.IdentityPasted(core)
	local s = core.Settings
	if not istable(s) then return end
	if not isstring(s.name) then s.name = StarCore.RandomName() end
	if not StarCore.ValidClass(s.class) then s.class = "auto" end
	if isstring(s.regno) and s.regno ~= "" then
		for _, c in ipairs(ents.FindByClass("starcore")) do
			if c ~= core and c.Settings and c.Settings.regno == s.regno then s.regno = StarCore.RandomRegNo(core) break end
		end
	elseif not isstring(s.regno) then
		s.regno = StarCore.RandomRegNo(core)
	end
end

-- from the Ship tab: d.name, d.regno (free text, may be empty), d.class ("auto" or a class), d.random (a new random name)
function StarCore.SetIdentity(core, d)
	local s = core.Settings
	if d.random then
		local old, n = s.name, 0
		repeat s.name = StarCore.RandomName(); n = n + 1 until s.name ~= old or n > 5
	else
		local name = clean(d.name, StarCore.NameMax)
		if name then s.name = name end
	end
	local no = clean(d.regno, StarCore.RegNoMax)
	if no then s.regno = no end
	if isstring(d.class) and StarCore.ValidClass(d.class) then s.class = d.class end
	StarCore.SyncNW(core)
end

-- the class shown (the author's pick, or from the ship's own length and weapons: docked ships do not count)
function StarCore.ShipClassOf(core)
	local s = core.Settings or {}
	if s.class ~= "auto" and StarCore.ValidClass(s.class) then return s.class end
	local a, b = core.OwnMins or core.LocalMins, core.OwnMaxs or core.LocalMaxs
	local size = a and (b - a) or Vector(0, 0, 0)
	return StarCore.AutoClass(math.max(size.x, size.y, size.z), core.Weapons ~= nil and #core.Weapons > 0)
end

-- "Kestrel" (or "SC-1042" without a name, or "?")
function StarCore.ShipLabel(core)
	local s = IsValid(core) and core.Settings or {}
	if isstring(s.name) and s.name ~= "" then return s.name end
	if isstring(s.regno) and s.regno ~= "" then return s.regno end
	return "?"
end

-- ---------------------------------------------------------------------------------------------------------------------
-- docking

local DOCK_SPEED = 250   -- most speed difference to the big ship (units per second)

local function lengthOf(core)
	local a, b = core.OwnMins or core.LocalMins, core.OwnMaxs or core.LocalMaxs
	if not a then return 0 end
	local s = b - a
	return math.max(s.x, s.y, s.z)
end

-- the ships docked in this one (oldest core first)
function StarCore.DockedShips(carrier)
	local list = {}
	for c in pairs(StarCore.Cores) do
		if IsValid(c) and c.DockedTo == carrier then list[#list + 1] = c end
	end
	table.sort(list, function(a, b) return a:EntIndex() < b:EntIndex() end)
	return list
end

-- the bigger ship this one is in: its middle inside the other ship's own box (a little above its top counts: on deck);
-- the smallest such ship wins (a fighter in a cruiser's hangar that sits in a station)
function StarCore.FindCarrier(core)
	local mid = StarCore.ShipCenter(core)
	local mine = lengthOf(core)
	local best, bestLen
	for other in pairs(StarCore.Cores) do
		local a, b = other.OwnMins, other.OwnMaxs
		if IsValid(other) and other ~= core and a and not other.Sleeping and not other.TooBig and not other.DockedTo and not other.Destroyed then
			local l = other:WorldToLocal(mid)
			if l.x >= a.x - 16 and l.x <= b.x + 16 and l.y >= a.y - 16 and l.y <= b.y + 16 and l.z >= a.z - 16 and l.z <= b.z + 200 then
				local len = lengthOf(other)
				if len > mine and (not best or len < bestLen) then best, bestLen = other, len end
			end
		end
	end
	return best
end

-- the part of a ship everything is measured from: the core, or (a core parented to something) its first free physics part
local function physRoot(core)
	local p = core:GetPhysicsObject()
	if not IsValid(core:GetParent()) and IsValid(p) then return core, p end
	for _, e in ipairs(core.PhysParts or {}) do
		local q = IsValid(e) and e:GetPhysicsObject()
		if IsValid(q) then return e, q end
	end
end

local function jumping(core) return core.FTLData and core.FTLData.state == StarCore.FTL.JUMPING end

-- returns true, carrier or false, why
function StarCore.Dock(core, ply)
	if core.DockedTo then return false, "dock_already" end
	if core.Sleeping or core.TooBig then return false, core.TooBig and "too_big" or "second_core" end
	if core.Destroyed or core.Disabled then return false, "ship_disabled" end
	if jumping(core) then return false, "busy" end
	if #StarCore.DockedShips(core) > 0 then return false, "dock_has_ships" end
	StarCore.Scan(core)
	local carrier = StarCore.FindCarrier(core)
	if not carrier then return false, "dock_no_carrier" end
	if IsValid(ply) and not StarCore.CanControl(carrier, ply) then return false, "dock_not_allowed" end
	if jumping(carrier) then return false, "busy" end
	local _, p1 = physRoot(core)
	local root, p2 = physRoot(carrier)
	if not (p1 and p2) then return false, "dock_no_carrier" end
	local cp = carrier:GetPhysicsObject()
	local relVel = p1:GetVelocity() - (IsValid(cp) and cp:GetVelocity() or Vector(0, 0, 0))
	if relVel:Length() > DOCK_SPEED then return false, "dock_too_fast" end
	StarCore.AutopilotSet(core, nil)
	if core.Tractor and StarCore.TractorSet then StarCore.TractorSet(core, nil) end
	StarCore.HelmSetOn(core, false)
	-- where each of its free physics parts sits, seen from the big ship's root part
	local rel = {}
	for _, e in ipairs(core.PhysParts or {}) do
		if IsValid(e) then
			local lp, la = WorldToLocal(e:GetPos(), e:GetAngles(), root:GetPos(), root:GetAngles())
			rel[e] = { pos = lp, ang = la }
		end
	end
	core.DockedTo, core.DockRoot, core.DockRel = carrier, root, rel
	core:SetNWEntity("starcore_docked", carrier)
	core:SetNWString("starcore_docked_name", StarCore.ShipLabel(carrier))
	StarCore.Scan(carrier)
	hook.Run("StarCore.Event", core, "docked")
	return true, carrier
end

-- let go: hover where it is, with the big ship's speed (so the hangar does not run into it). removing = the docked core
-- is being removed (only the lock goes)
-- a docked ship does not touch the big ship it is on (no pushing between the two while they fly as one); everything else
-- still collides with both. Only on the server, where props are simulated.
hook.Add("ShouldCollide", "StarCore.Dock", function(a, b)
	local s = a.StarCoreDockOn
	if s and s[b] then return false end
	s = b.StarCoreDockOn
	if s and s[a] then return false end
end)

-- (changed: the big ship's own parts changed, the physics must look at the pairs again)
local function dockTouch(parts, carrierSet, changed)
	for _, e in ipairs(parts or {}) do
		if IsValid(e) and (e.StarCoreDockOn ~= carrierSet or changed) then
			if carrierSet and e.StarCoreDockCC == nil then e.StarCoreDockCC = e:GetCustomCollisionCheck() end
			e.StarCoreDockOn = carrierSet
			if carrierSet then e:SetCustomCollisionCheck(true)
			else
				e:SetCustomCollisionCheck(e.StarCoreDockCC == true)
				e.StarCoreDockCC = nil
			end
			e:CollisionRulesChanged()
		end
	end
end

function StarCore.Undock(core, removing)
	local carrier = core.DockedTo
	if IsValid(core) then dockTouch(core.OwnParts or core.Parts, nil) end
	core.DockedTo, core.DockRoot, core.DockRel = nil, nil, nil
	if IsValid(carrier) then carrier.NextScan = 0 end
	if removing or not IsValid(core) then return true end
	core:SetNWEntity("starcore_docked", NULL)
	if IsValid(carrier) then StarCore.Scan(carrier) end
	StarCore.Scan(core)
	StarCore.HelmSetOn(core, true)
	if core.Helm and core.Helm.on then
		local h = IsValid(carrier) and carrier.Helm
		if h and h.on and not h.frozen and h.vel then core.Helm.vel = Vector(h.vel.x, h.vel.y, h.vel.z) end
	else
		StarCore.HelmSetOn(core, false)   -- (cannot hover, e.g. disabled: gravity back on, it falls like any wreck)
	end
	hook.Run("StarCore.Event", core, "undocked")
	return true
end

-- every tick of a docked core: the big ship gone or one of them destroyed -> let go; else every part moves exactly like
-- the big ship's root part (its speed and turning), a small way off its place is made up softly (in a quarter second),
-- and only a part far off (8 units, 2 degrees: knocked hard) is put back at once. A frozen big ship has frozen the
-- docked parts too (StarCore.DockAddCarried): nothing to do then.
-- (put back at once from 1 unit off, the docked ship shook while the big ship flew - owner)
local CATCHUP = 4   -- per second: a quarter second to make up a small way off
local function offTooFar(e, pos, ang)
	if e:GetPos():DistToSqr(pos) > 64 then return true end
	-- (its angles against its saved angles, both from GetAngles: a seat's GetForward() is 90 degrees off its angles, so
	-- every docked seat counted as turned away and was put back every tick - the weld fought that and now and then
	-- kicked the docked ship off its place)
	local a = e:GetAngles()
	return a:Forward():Dot(ang:Forward()) < 0.99939 or a:Up():Dot(ang:Up()) < 0.99939
end
function StarCore.DockThink(core)
	if not core.DockedTo then return end
	local c, root = core.DockedTo, core.DockRoot
	if not IsValid(c) or not IsValid(root) or c.Destroyed or core.Destroyed or c.Sleeping then StarCore.Undock(core) return end
	local rp = root:GetPhysicsObject()
	if not IsValid(rp) or not rp:IsMotionEnabled() then return end
	local v, w = rp:GetVelocity(), rp:LocalToWorldVector(rp:GetAngleVelocity())   -- (w: degrees per second, world axes)
	local wr, mid = w * (math.pi / 180), rp:LocalToWorld(rp:GetMassCenter())
	local rpos, rang = root:GetPos(), root:GetAngles()
	for e, r in pairs(core.DockRel) do
		local p = IsValid(e) and e:GetPhysicsObject()
		if IsValid(p) and p:IsMotionEnabled() then
			local pos, ang = LocalToWorld(r.pos, r.ang, rpos, rang)
			local catch = vector_origin
			if offTooFar(e, pos, ang) then e:SetPos(pos); e:SetAngles(ang)
			else catch = (pos - e:GetPos()) * CATCHUP end
			p:SetVelocity(v + wr:Cross(p:LocalToWorld(p:GetMassCenter()) - mid) + catch)
			p:SetAngleVelocity(p:WorldToLocalVector(w))
			p:EnableGravity(false)
			p:Wake()   -- (the big ship's helm woke them before; it leaves them to this now)
		end
	end
end

-- called by StarCore.Scan of the big ship, after its own parts are known: the docked ships' parts join its part lists
-- (move, freeze, jump, cloak and the free-space checks take them along); seats, screens, weapons, power, hull and the
-- class stay with each ship. The box grows to hold them, so a jump never puts a docked ship into a wall.
function StarCore.DockAddCarried(core)
	local docked = StarCore.DockedShips(core)
	core:SetNWInt("starcore_docked_ships", #docked)
	if #docked == 0 then return end
	local parts, phys, seen = {}, {}, {}
	for _, e in ipairs(core.Parts) do parts[#parts + 1] = e; seen[e] = true end
	for _, e in ipairs(core.PhysParts) do phys[#phys + 1] = e end
	local mins, maxs = Vector(core.LocalMins), Vector(core.LocalMaxs)
	local flying = core.Helm and core.Helm.on
	local frozen = core.Helm and core.Helm.frozen
	for _, d in ipairs(docked) do
		for _, e in ipairs(d.Parts or {}) do
			if IsValid(e) and not seen[e] then parts[#parts + 1] = e; seen[e] = true end
		end
		for _, e in ipairs(d.PhysParts or {}) do
			local p = IsValid(e) and e:GetPhysicsObject()
			if IsValid(p) then
				phys[#phys + 1] = e
				if flying then p:EnableGravity(false) end
				if frozen then p:EnableMotion(false) end
			end
		end
		if d.LocalMins then
			for i = 0, 7 do
				local a, b = d.LocalMins, d.LocalMaxs
				local c = Vector(bit.band(i, 1) > 0 and b.x or a.x, bit.band(i, 2) > 0 and b.y or a.y, bit.band(i, 4) > 0 and b.z or a.z)
				local l = core:WorldToLocal(d:LocalToWorld(c))
				mins.x = math.min(mins.x, l.x); mins.y = math.min(mins.y, l.y); mins.z = math.min(mins.z, l.z)
				maxs.x = math.max(maxs.x, l.x); maxs.y = math.max(maxs.y, l.y); maxs.z = math.max(maxs.z, l.z)
			end
		end
	end
	core.Parts, core.PhysParts = parts, phys
	core.LocalMins, core.LocalMaxs = mins, maxs
	-- the docked ships and the big ship do not push each other. The set of the big ship's parts stays the same table and
	-- the docked parts are told again only when it changed (a new set in every scan, every 2 s, told the physics
	-- each time that the collision rules changed; it checked the docked ship's contacts again and kicked it 3-6 units
	-- off its place in one tick, about 2 s into a flight - test ptdock, 3 of 6 runs)
	local set, own, changed = core.DockNoCollide or {}, {}, false
	for _, e in ipairs(core.OwnParts or {}) do
		if IsValid(e) then
			own[e] = true
			if not set[e] then set[e] = true; changed = true end
		end
	end
	for e in pairs(set) do
		if not own[e] then set[e] = nil; changed = true end
	end
	core.DockNoCollide = set
	for _, d in ipairs(docked) do dockTouch(d.OwnParts or d.Parts, set, changed) end
end

-- through a Stargate: a docked ship goes along with the ship it is docked in (Ascension Gates asks with
-- "StarGate.TeleportAlong"; e and list = the contraption going through, along = what may come with it). Nothing holds
-- a docked ship to its carrier, so the gate saw only the carrier; the docked ship met the far gate alone and was lost.
hook.Add("StarGate.TeleportAlong", "StarCore.Docked", function(e, list, along)
	local carriers = {}
	local function look(v)
		if not IsValid(v) then return end
		local c = v:GetClass() == "starcore" and v or (StarCore.PartCore and StarCore.PartCore[v])
		if IsValid(c) then carriers[c] = true end
	end
	look(e)
	for _, v in ipairs(list or {}) do look(v) end
	for c in pairs(carriers) do
		for _, d in ipairs(StarCore.DockedShips(c)) do
			if not carriers[d] then
				along[#along + 1] = d
				for _, p in ipairs(d.OwnParts or d.Parts or {}) do
					if IsValid(p) and not p:IsPlayer() then along[#along + 1] = p end
				end
			end
		end
	end
end)
