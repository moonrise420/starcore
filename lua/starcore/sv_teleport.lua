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

-- move the ship so the core ends up at newPos / newAng
function StarCore.MoveShip(core, newPos, newAng)
	StarCore.Scan(core)
	local passengers = StarCore.Passengers(core)
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
	end
	for _, it in ipairs(items) do
		if it.p then
			it.p:EnableMotion(it.moving)
			if it.moving then it.p:SetVelocityInstantaneous(Vector(0, 0, 0)); it.p:Wake() end
		end
	end
	-- people one tick later and a little higher: placed in the same tick (or with the feet a hair inside the deck)
	-- the engine sees them as stuck and puts them back where they were (in-game test 2026-10-20)
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
	return #items, #people
end
