-- StarCore server: tractor beam, cloak, landing (docking help), fleet mode, self-destruct.
-- All of them can be switched off for the whole server by the admin (ConVars in sh_config.lua).

-- ===== tractor beam: pull an object to the ship or hold it in front of the ship =====
local function tractorAllowed(core, ent)
	if not IsValid(ent) or ent:IsWorld() or StarCore.PartCore[ent] == core then return false, "tractor_bad_target" end
	if ent:IsPlayer() then
		local c = StarCore.ContactOf(core, ent)
		if not StarCore.CV.tractorPlayers:GetBool() and not (c and (c.iff == StarCore.IFF.own or c.iff == StarCore.IFF.friend or c.iff == StarCore.IFF.crew)) then
			return false, "tractor_not_allowed"
		end
	end
	local p = ent:GetPhysicsObject()
	if not ent:IsPlayer() and not ent:IsNPC() and not IsValid(p) then return false, "tractor_bad_target" end
	if ent:GetPos():Distance(StarCore.ShipCenter(core)) > StarCore.CV.tractorRange:GetFloat() then return false, "tractor_too_far" end
	-- another player's prop: only with prop protection permission
	if ent.CPPICanPhysgun and IsValid(core:GetNWEntity("starcore_owner")) and not ent:CPPICanPhysgun(core:GetNWEntity("starcore_owner")) then return false, "tractor_not_allowed" end
	return true
end

function StarCore.TractorSet(core, ent, mode)
	if not ent then
		core.Tractor = nil
		core:SetNWEntity("starcore_tractor", NULL)
		return true
	end
	if not StarCore.CV.allowTractor:GetBool() then return false, "disabled_by_server" end
	local ok, why = tractorAllowed(core, ent)
	if not ok then return false, why end
	local dist = ent:GetPos():Distance(StarCore.ShipCenter(core))
	core.Tractor = { ent = ent, mode = mode or "hold", hold = math.max(dist, 150) }
	core:SetNWEntity("starcore_tractor", ent)
	return true
end

function StarCore.TractorThink(core)
	local tb = core.Tractor
	if not tb then return end
	local ent = tb.ent
	if not IsValid(ent) or ent:GetPos():Distance(StarCore.ShipCenter(core)) > StarCore.CV.tractorRange:GetFloat() * 1.2 then
		StarCore.TractorSet(core, nil)
		return
	end
	local c = StarCore.ShipCenter(core)
	local shipAng = core:LocalToWorldAngles(core.Helm and core.Helm.refAng or Angle())
	if tb.mode == "pull" then tb.hold = math.max(tb.hold - 400 * FrameTime(), (core:GetNWVector("starcore_size"):Length() * 0.5) + 100) end
	local want = c + Angle(0, shipAng.y, 0):Forward() * tb.hold
	local shipVel = core.Helm and core.Helm.vel or Vector(0, 0, 0)
	local vel = (want - ent:WorldSpaceCenter()) * 3 + shipVel
	if vel:Length() > 2500 then vel = vel:GetNormalized() * 2500 end
	if ent:IsPlayer() or ent:IsNPC() then
		ent:SetVelocity(vel - ent:GetVelocity())
	else
		local p = ent:GetPhysicsObject()
		if IsValid(p) then
			p:EnableMotion(true)
			p:SetVelocity(vel)
			p:AddAngleVelocity(-p:GetAngleVelocity() * 0.2)
			p:Wake()
		end
	end
end

-- ===== cloak: the ship fades out, other ships' radar no longer sees it =====
function StarCore.CloakSet(core, on)
	if on and not StarCore.CV.allowCloak:GetBool() then return false, "disabled_by_server" end
	if on == (core.Cloaked == true) then return true end
	core.Cloaked = on
	core:SetNWBool("starcore_cloaked", on)
	core.CloakSaved = core.CloakSaved or {}
	for _, e in ipairs(core.Parts or {}) do
		if IsValid(e) then
			if on then
				if not core.CloakSaved[e] then core.CloakSaved[e] = { mode = e:GetRenderMode(), col = e:GetColor() } end
				e:SetRenderMode(RENDERMODE_TRANSALPHA)
				local col = e:GetColor()
				e:SetColor(Color(col.r, col.g, col.b, 0))
				e:DrawShadow(false)
			else
				local s = core.CloakSaved[e]
				if s then e:SetRenderMode(s.mode); e:SetColor(s.col) end
				e:DrawShadow(true)
			end
		end
	end
	if not on then core.CloakSaved = nil end
	core:EmitSound(on and "ambient/levels/citadel/pod_open1.wav" or "ambient/levels/citadel/pod_close1.wav", 80, 140)
	hook.Run("StarCore.Event", core, on and "cloak_on" or "cloak_off")
	return true
end

-- firing reveals a cloaked ship
hook.Add("StarCore.Event", "StarCore.CloakFire", function(core, event)
	if event == "fired" and core.Cloaked then StarCore.CloakSet(core, false) end
end)

-- ===== landing (only when the pilot presses "Land here"): down to the ground below, gently, then hold =====
function StarCore.Land(core)
	local c = StarCore.ShipCenter(core)
	local tr = util.TraceHull({ start = c, endpos = c - Vector(0, 0, 60000), mins = Vector(-8, -8, 0), maxs = Vector(8, 8, 8), filter = core.Parts, mask = MASK_SOLID })
	if not tr.Hit then return false, "land_no_ground" end
	local half = core.LocalMaxs and (c.z - core:LocalToWorld(Vector(0, 0, core.LocalMins.z)).z) or 50
	local spot = tr.HitPos + Vector(0, 0, math.max(half, 10) + 4)
	core.Landing = true
	local ok, why = StarCore.AutopilotSet(core, spot)
	if ok and core.Autopilot then core.Autopilot.precise = true end
	return ok, why
end

hook.Add("StarCore.Event", "StarCore.LandPark", function(core, event)
	if event == "autopilot_arrived" and core.Landing then
		core.Landing = nil
		StarCore.SetFrozen(core, true)
		StarCore.NotifyShip(core, "landed", NOTIFY_GENERIC)
	end
end)

-- ===== fleet: a friend's ship follows ours in formation and jumps with us =====
function StarCore.FleetJoin(follower, leader)
	if not IsValid(leader) or leader == follower or leader:GetClass() ~= "starcore" then return false, "fleet_bad" end
	if not StarCore.CV.allowFleet:GetBool() then return false, "disabled_by_server" end
	local fo, lo = follower:GetNWEntity("starcore_owner"), leader:GetNWEntity("starcore_owner")
	if not StarCore.CanControl(leader, fo) and fo ~= lo then return false, "fleet_not_friend" end
	follower.FleetLeader = leader
	-- keep today's place next to the leader (in the leader's own direction)
	follower.FleetOffset = leader:WorldToLocal(StarCore.ShipCenter(follower))
	follower:SetNWEntity("starcore_fleet", leader)
	StarCore.HelmSetOn(follower, true)
	return true
end

function StarCore.FleetLeave(core)
	core.FleetLeader = nil
	core:SetNWEntity("starcore_fleet", NULL)
	if core.Autopilot and core.Autopilot.fleet then StarCore.AutopilotSet(core, nil) end
end

function StarCore.FleetThink(core)
	local l = core.FleetLeader
	if not l then return end
	if not IsValid(l) then StarCore.FleetLeave(core) return end
	if core.FTLData.state ~= StarCore.FTL.IDLE then return end
	local want = l:LocalToWorld(core.FleetOffset)
	if not core.Autopilot then StarCore.AutopilotSet(core, want, true) end
	if core.Autopilot then core.Autopilot.pos = want; core.Autopilot.fleet = true end
end

-- the leader jumped: everyone in its fleet jumps to the same place next to it
hook.Add("StarCore.Jumped", "StarCore.Fleet", function(leader, from, to)
	for core in pairs(StarCore.Cores) do
		if IsValid(core) and core.FleetLeader == leader then
			timer.Simple(0.5 + math.random() * 0.8, function()
				if not IsValid(core) or not IsValid(leader) then return end
				local wantCenter = leader:LocalToWorld(core.FleetOffset)
				local target = wantCenter - (StarCore.ShipCenter(core) - core:GetPos())
				core.Settings.charge = core.Settings.charge -- own charge time still applies
				StarCore.RequestJump(core, nil, { kind = "coord", pos = target })
			end)
		end
	end
end)

-- ===== self-destruct: owner only, countdown, can be cancelled =====
function StarCore.SelfDestruct(core, ply, start)
	local owner = core:GetNWEntity("starcore_owner")
	if ply ~= owner and not (IsValid(ply) and ply:IsAdmin()) then return false, "no_permission" end
	local name = "StarCore.SelfDestruct" .. core:EntIndex()
	if not start then
		if timer.Exists(name) then
			timer.Remove(name)
			core:SetNWFloat("starcore_destruct", 0)
			hook.Run("StarCore.Event", core, "self_destruct_stop")
		end
		return true
	end
	if not StarCore.CV.allowSelfDestruct:GetBool() then return false, "disabled_by_server" end
	if timer.Exists(name) then return true end
	local secs = 10
	core:SetNWFloat("starcore_destruct", CurTime() + secs)
	local left = secs
	hook.Run("StarCore.Event", core, "self_destruct", left)
	timer.Create(name, 1, secs, function()
		if not IsValid(core) then timer.Remove(name) return end
		left = left - 1
		if left == 5 or left == 3 or (left <= 2 and left > 0) then
			core.VoiceLast = nil -- every count is spoken
			hook.Run("StarCore.Event", core, "self_destruct", left)
		end
		core:EmitSound("buttons/blip1.wav", 90, left <= 3 and 140 or 110)
		if left <= 0 then StarCore.Explode(core) end
	end)
	return true
end

function StarCore.Explode(core)
	local parts = table.Copy(core.Parts or {})
	local c = StarCore.ShipCenter(core)
	-- size picked in the ship menu (small .. XXL); the server ConVar caps the damage
	local level = math.Clamp(math.floor(tonumber(core.Settings and core.Settings.destructSize) or 2), 1, #StarCore.DestructSizes)
	local radius, dmg = StarCore.DestructBlast(core:GetNWVector("starcore_size"):Length(), level)
	local owner = core:GetNWEntity("starcore_owner")
	for i, e in ipairs(parts) do
		if IsValid(e) and not e:IsPlayer() then
			timer.Simple(math.min(i * 0.03, 1.5), function()
				if not IsValid(e) then return end
				local fx = EffectData(); fx:SetOrigin(e:WorldSpaceCenter()); fx:SetMagnitude(2 + level); fx:SetScale(1 + level * 0.5)
				if i % 3 == 1 then util.Effect("Explosion", fx) end
				e:Remove()
			end)
		end
	end
	-- bigger blasts: a few extra explosions spread over the blast area
	for k = 1, (level - 1) * 2 do
		timer.Simple(0.2 + k * 0.15, function()
			local fx = EffectData(); fx:SetOrigin(c + VectorRand() * radius * 0.4); fx:SetMagnitude(4); fx:SetScale(3)
			util.Effect("Explosion", fx)
		end)
	end
	if dmg > 0 then util.BlastDamage(IsValid(core) and core or game.GetWorld(), IsValid(owner) and owner or game.GetWorld(), c, radius, dmg) end
	util.ScreenShake(c, 6 + level * 2, 5, 1.5 + level * 0.5, radius * 3)
end

function StarCore.SystemsThink(core)
	StarCore.TractorThink(core)
	if (core.NextFleet or 0) < CurTime() then
		core.NextFleet = CurTime() + 0.25
		StarCore.FleetThink(core)
	end
end
