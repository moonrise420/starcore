-- StarCore server: moves a whole ship (all parts + the people standing inside) to a new place in one tick
function StarCore.Passengers(core)
	local list = {}
	if not StarCore.CV.carryPlayers:GetBool() then return list end
	for _, ply in ipairs(player.GetAll()) do
		if ply:Alive() and not ply:InVehicle() and StarCore.IsInside(core, ply) then list[#list + 1] = ply end
	end
	for _, npc in ipairs(ents.FindByClass("npc_*")) do
		if IsValid(npc) and npc:IsNPC() and StarCore.IsInside(core, npc) then list[#list + 1] = npc end
	end
	return list
end

-- Loose things lying in the ship: a crate on the deck, a prop someone spawned in the hangar - not welded, so not a
-- part. They jump with the ship. Not: other ships and their parts, what is fixed to something outside the ship,
-- what is parented, people (above).
local function freeThing(core, e)
	if not IsValid(e) or e:IsPlayer() or e:IsNPC() or e:IsWeapon() or IsValid(e:GetParent()) or e:IsWorld() then return false end
	if StarCore.PartCore and StarCore.PartCore[e] then return false end
	if e:GetClass() == "starcore" or e.SpaceGridHull or e.SpaceGridKeel or e.SpaceGridSeat or e.SpaceGridDoor then return false end
	if e:IsVehicle() and IsValid(e:GetDriver()) then return false end
	local p = e:GetPhysicsObject()
	if not IsValid(p) then return false end
	if constraint.HasConstraints(e) then
		for _, c in ipairs(constraint.GetTable(e) or {}) do
			local o = c.Ent1 == e and c.Ent2 or c.Ent1
			if IsValid(o) and not o:IsWorld() and not (StarCore.PartCore and StarCore.PartCore[o] == core) then return false end
		end
	end
	return StarCore.IsInside(core, e)
end
function StarCore.Cargo(core)
	local list = {}
	if not core.LocalMins then return list end
	local lo, hi = Vector(math.huge, math.huge, math.huge), Vector(-math.huge, -math.huge, -math.huge)
	for i = 0, 7 do
		local a, b = core.LocalMins, core.LocalMaxs
		local c = core:LocalToWorld(Vector(bit.band(i, 1) > 0 and b.x or a.x, bit.band(i, 2) > 0 and b.y or a.y, bit.band(i, 4) > 0 and b.z or a.z))
		lo = Vector(math.min(lo.x, c.x), math.min(lo.y, c.y), math.min(lo.z, c.z))
		hi = Vector(math.max(hi.x, c.x), math.max(hi.y, c.y), math.max(hi.z, c.z))
	end
	local seen = {}
	for _, e in ipairs(core.Parts or {}) do seen[e] = true end
	for _, e in ipairs(ents.FindInBox(lo, hi)) do
		if not seen[e] and freeThing(core, e) then list[#list + 1] = e end
	end
	return list
end

-- move the ship so the core ends up at newPos / newAng
function StarCore.MoveShip(core, newPos, newAng)
	StarCore.Scan(core)
	local passengers = StarCore.Passengers(core)
	local cargo = StarCore.Cargo(core)
	local oldAng = core:GetAngles()
	local items = {}
	for _, e in ipairs(core.Parts) do
		if IsValid(e) and not IsValid(e:GetParent()) then
			local p = e:GetPhysicsObject()
			items[#items + 1] = {
				e = e, p = IsValid(p) and p or nil, moving = IsValid(p) and p:IsMotionEnabled(),
				lpos = core:WorldToLocal(e:GetPos()), lang = core:WorldToLocalAngles(e:GetAngles()),
			}
		end
	end
	for _, e in ipairs(cargo) do
		local p = e:GetPhysicsObject()
		-- (a sleeping thing's entity can be a step behind its body: the body's place)
		local at, an = IsValid(p) and p:GetPos() or e:GetPos(), IsValid(p) and p:GetAngles() or e:GetAngles()
		items[#items + 1] = {
			e = e, p = IsValid(p) and p or nil, moving = IsValid(p) and p:IsMotionEnabled(),
			lpos = core:WorldToLocal(at), lang = core:WorldToLocalAngles(an), cargo = true,
		}
	end
	local people = {}
	for _, ent in ipairs(passengers) do
		people[#people + 1] = { e = ent, lpos = core:WorldToLocal(ent:GetPos()) }
	end

	-- freeze, place, restore (the core itself is in the list, so compute targets from fixed values first)
	local ref = { pos = newPos, ang = newAng }
	local function toWorld(lpos) return (LocalToWorld(lpos, Angle(), ref.pos, ref.ang)) end
	for _, it in ipairs(items) do if it.p then it.p:EnableMotion(false) end end
	for _, it in ipairs(items) do
		local pos, ang = LocalToWorld(it.lpos, it.lang, ref.pos, ref.ang)
		it.e:SetPos(pos)
		it.e:SetAngles(ang)
		if it.cargo and it.p then it.p:SetPos(pos); it.p:SetAngles(ang) end
	end
	for _, it in ipairs(items) do
		if it.p then
			it.p:EnableMotion(it.moving)
			if it.moving then it.p:SetVelocityInstantaneous(Vector(0, 0, 0)); it.p:Wake() end
		end
	end
	-- people one tick later and a little higher: placed in the same tick (or with the feet a hair inside the deck)
	-- the engine sees them as stuck and puts them back where they were (in-game test)
	local yawDiff = newAng.y - oldAng.y
	local function placePeople()
		for _, pp in ipairs(people) do
			if IsValid(pp.e) then
				pp.e:SetPos(toWorld(pp.lpos) + Vector(0, 0, 6))
				pp.e:SetVelocity(-pp.e:GetVelocity())
				if pp.e:IsPlayer() then
					local ea = pp.e:EyeAngles()
					pp.e:SetEyeAngles(Angle(ea.p, ea.y + yawDiff, 0))
				end
			end
		end
	end
	placePeople()
	timer.Simple(0, placePeople)
	if core.Helm then
		core.Helm.vel = Vector(0, 0, 0)
		core.Helm.angvel = Vector(0, 0, 0)
		core.Helm.targetZ = nil
	end
	return #items - #cargo, #people, #cargo
end
