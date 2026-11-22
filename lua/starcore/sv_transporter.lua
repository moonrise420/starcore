-- StarCore server, level 3: Asgard beaming with the ship's transporter (CAP "transporter" or anything with the
-- same Teleport/FindObjects functions). Beam a radar contact aboard, or beam everyone on the transporter pad down.
-- Rules: range and cooldown from the server; players only with their consent (own, crew, friends) unless the admin
-- allows hostile beaming; owner/crew/friends are never beamed away against their will.
local function isTransporter(e)
	return isfunction(e.Teleport) and isfunction(e.FindObjects) and e:GetClass() ~= "starcore"
end

function StarCore.TransporterAttach(core)
	core.Transporter = nil
	for _, e in ipairs(core.Parts or {}) do
		if IsValid(e) and isTransporter(e) then core.Transporter = e break end
	end
	core:SetNWEntity("starcore_transporter", core.Transporter or NULL)
end

local function padPos(core)
	local t = core.Transporter
	return t:GetPos() + Vector(0, 0, t:OBBMaxs().z + 40)
end

-- CAP's transporter needs energy (distance / 5 per object) when a resource network exists; check it first so the
-- player gets a clear message, and only report success when the transporter really beamed (it sets t.Next)
local function enoughEnergy(t, from, to, count)
	if not t.HasRD or not isfunction(t.GetResource) then return true end
	return (t:GetResource("energy", 0) or 0) >= from:Distance(to) / 5 * (count or 1)
end

local function beam(t, from, to, ply)
	local before = t.Next or 0
	t:Teleport(from, to, ply)
	return (t.Next or 0) ~= before
end

local function ready(core)
	local t = core.Transporter
	if not IsValid(t) then return false, "beam_none" end
	if (core.NextBeam or 0) > CurTime() then return false, "beam_busy" end
	-- AGP: the transporter's own recharge (CAP: 5 s, t.Next; ours was 3 s): a beam in between said
	-- "beam_failed" instead of "still recharging"
	if isnumber(t.Next) and t.Next > CurTime() then return false, "beam_busy" end
	return true
end

-- AGP: is anyone / anything on the pad that the transporter would take? ("beam down" with an empty pad said
-- "beam_failed"). The same search the transporter makes, without the ship's own parts (it never beams those)
local function padHasObjects(core)
	local t = core.Transporter
	local old = t.Exceptions
	local exc = {}
	for _, e in ipairs(core.Parts or {}) do if IsValid(e) then exc[e] = true end end
	t.Exceptions = exc
	local ok, found = pcall(t.FindObjects, t, padPos(core), true)
	t.Exceptions = old
	if not ok or not istable(found) then return true end   -- (cannot tell: let the transporter try)
	return next(found) ~= nil
end

-- the next beam after this one: our pause, or the transporter's own when it is longer
local function beamed(core)
	local t = core.Transporter
	core.NextBeam = math.max(CurTime() + 3, isnumber(t.Next) and t.Next or 0)
end

-- a contact aboard (to the transporter pad)
function StarCore.BeamAboard(core, ply, ent)
	local ok, why = ready(core)
	if not ok then return false, why end
	local c = IsValid(ent) and StarCore.ContactOf(core, ent)
	if not c or (c.kind ~= StarCore.KIND.player and c.kind ~= StarCore.KIND.npc) then return false, "beam_bad_target" end
	if ent:GetPos():Distance(core.Transporter:GetPos()) > StarCore.CV.beamRange:GetFloat() then return false, "beam_too_far" end
	local IFF = StarCore.IFF
	if c.kind == StarCore.KIND.player and c.iff ~= IFF.own and c.iff ~= IFF.crew and c.iff ~= IFF.friend and not StarCore.CV.beamHostile:GetBool() then
		return false, "beam_not_allowed"
	end
	if c.iff == IFF.hostile and not StarCore.CV.beamHostile:GetBool() then return false, "beam_not_allowed" end
	local t = core.Transporter
	local from, to = ent:GetPos() + Vector(0, 0, 5), padPos(core)
	if not enoughEnergy(t, from, to, 1) then return false, "beam_no_energy" end
	local radius = t.Radius
	t.Radius = math.max(ent:BoundingRadius(), 40) -- only this one, not people standing next to it
	local ok = beam(t, from, to, ply)
	t.Radius = radius
	if not ok then return false, "beam_failed" end
	beamed(core)   -- AGP
	hook.Run("StarCore.Event", core, "beam")
	return true
end

-- everyone on the pad down to the ground below the ship (or to a contact's position)
function StarCore.BeamDown(core, ply, ent)
	local ok, why = ready(core)
	if not ok then return false, why end
	local dest
	if IsValid(ent) and StarCore.ContactOf(core, ent) then
		dest = ent:GetPos() + Vector(0, 0, 10)
	else
		local c = StarCore.ShipCenter(core)
		local tr = util.TraceLine({ start = c, endpos = c - Vector(0, 0, 60000), filter = core.Parts, mask = MASK_SOLID_BRUSHONLY })
		dest = tr.HitPos + Vector(0, 0, 10)
	end
	if dest:Distance(core.Transporter:GetPos()) > StarCore.CV.beamRange:GetFloat() then return false, "beam_too_far" end
	if not util.IsInWorld(dest) then return false, "outside_map" end
	if not padHasObjects(core) then return false, "beam_nobody" end   -- AGP
	if not enoughEnergy(core.Transporter, padPos(core), dest, 1) then return false, "beam_no_energy" end
	if not beam(core.Transporter, padPos(core), dest, ply) then return false, "beam_failed" end
	beamed(core)   -- AGP
	hook.Run("StarCore.Event", core, "beam")
	return true
end
