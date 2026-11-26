-- StarCore server: tractor beam, cloak, landing (docking help), fleet mode, self-destruct.
-- All of them can be switched off for the whole server by the admin (ConVars in sh_config.lua).

-- ===== tractor beam: pull an object to the ship or hold it in front of the ship =====
-- it aimed with a thin line from the player's eyes, not from the camera the pilot sees (third person, look-around, menu
-- open), and it took anything with physics. Now it picks what the pilot SEES: the client sends its camera (origin +
-- direction); the best thing near the middle of the view (an exact hit first, else the closest to the middle within a
-- few degrees, bigger things count bigger), only things in plain view and in reach. Never: the ship itself,
-- Stargates / DHDs / ramps of others, anything the gate spawner or the map placed, parented parts. A frozen prop is
-- frozen again where the beam lets it go (like the physics gun).: what the ship's owner or its pilot spawned is always
-- allowed, Stargates, DHDs and ramps too. Never, not even one's own: what the map or the gate spawner placed, and
-- parts fixed onto something else (a gate's inner ring).
--
--
local NO_TRACTOR = { "^stargate_", "^dhd_", "ramp", "^func_", "^prop_door", "^prop_dynamic", "^env_", "^info_", "^trigger_" }
local function spawnedBy(ent, ply)
	if not IsValid(ply) then return false end
	if ent.CPPIGetOwner then
		local o = ent:CPPIGetOwner()
		if IsValid(o) then return o == ply end
	end
	if ent.GetCreator and ent:GetCreator() == ply then return true end   -- (sandbox spawning sets it)
	return ent.GetVar and ent:GetVar("Owner") == ply or false            -- (Stargate pack tools)
end
local function tractorClassOK(core, ent)
	if ent.GateSpawnerSpawned or ent:CreatedByMap() or IsValid(ent:GetParent()) then return false end
	local pilot = IsValid(core.PilotSeat) and core.PilotSeat:GetDriver() or nil
	if spawnedBy(ent, core:GetNWEntity("starcore_owner")) or spawnedBy(ent, pilot) then return true end
	local cls = ent:GetClass()
	for _, pat in ipairs(NO_TRACTOR) do if cls:find(pat) then return false end end
	if ent.IsStargate or ent.IsDHD or ent.IsRamp then return false end
	return true
end

local function tractorAllowed(core, ent)
	if not IsValid(ent) or ent:IsWorld() or StarCore.PartCore[ent] == core then return false, "tractor_bad_target" end
	if not ent:IsPlayer() and not ent:IsNPC() and not tractorClassOK(core, ent) then return false, "tractor_bad_target" end
	if ent:IsPlayer() then
		if ent:InVehicle() then return false, "tractor_bad_target" end
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

-- the best thing to grab near the middle of a view (origin, direction). Returns the entity, or nil and why not.
local PICK_DEG = 7
function StarCore.TractorPick(core, origin, dir, viewer)
	local range = StarCore.CV.tractorRange:GetFloat()
	local center = StarCore.ShipCenter(core)
	-- not in the way: the ship itself, the pilot and the pilot's seat (a line from the eyes down to something below the
	-- middle of the view went through the pilot's own body - test)
	local ownSet = {}
	for _, e in ipairs(core.Parts or {}) do ownSet[e] = true end
	if IsValid(viewer) then
		ownSet[viewer] = true
		if viewer:InVehicle() then ownSet[viewer:GetVehicle()] = true end
	end
	local own = function(e) return not ownSet[e] end
	dir = dir:GetNormalized()
	-- what the middle of the view hits first (people too)
	local tr = util.TraceLine({ start = origin, endpos = origin + dir * (range + center:Distance(origin)), filter = own, mask = MASK_SHOT })
	if IsValid(tr.Entity) and tractorAllowed(core, tr.Entity) then return tr.Entity end
	local best, bestScore, why = nil, math.huge, "tractor_nothing"
	for _, e in ipairs(ents.FindInSphere(center, range)) do
		if IsValid(e) and StarCore.PartCore[e] ~= core and (e:IsPlayer() or e:IsNPC() or IsValid(e:GetPhysicsObject())) then
			local to = e:WorldSpaceCenter() - origin
			local dist = to:Length()
			if dist > 1 then
				local deg = math.deg(math.acos(math.Clamp(to:Dot(dir) / dist, -1, 1)))
				local size = math.deg(math.atan((e:OBBMaxs() - e:OBBMins()):Length() * 0.5 / dist))
				local score = deg - size
				if score < PICK_DEG and score < bestScore then
					local ok, whyNot = tractorAllowed(core, e)
					if ok then
						-- in plain view: nothing solid between the camera and it (the ship itself does not count)
						local los = util.TraceLine({ start = origin, endpos = e:WorldSpaceCenter(), filter = own, mask = MASK_SOLID })
						if not los.Hit or los.Entity == e then best, bestScore = e, score end
					elseif whyNot ~= "tractor_bad_target" then
						why = whyNot
					end
				end
			end
		end
	end
	if best then return best end
	if IsValid(tr.Entity) and not tr.Entity:IsWorld() then
		local _, whyNot = tractorAllowed(core, tr.Entity)
		return nil, whyNot or why
	end
	return nil, why
end

local function release(tb)
	local ent = tb and tb.ent
	if not IsValid(ent) or ent:IsPlayer() or ent:IsNPC() or tb.mode == "push" then return end   -- (pushed away: it flies on)
	local p = ent:GetPhysicsObject()
	if IsValid(p) and tb.wasFrozen then p:SetVelocity(Vector(0, 0, 0)); p:EnableMotion(false) end
end

function StarCore.TractorSet(core, ent, mode)
	if not ent then
		release(core.Tractor)
		core.Tractor = nil
		core:SetNWEntity("starcore_tractor", NULL)
		return true
	end
	if not StarCore.CV.allowTractor:GetBool() then return false, "disabled_by_server" end
	local ok, why = tractorAllowed(core, ent)
	if not ok then return false, why end
	-- the same thing again (another button, the Wire value changed): only the mode changes
	local same = core.Tractor and core.Tractor.ent == ent
	if core.Tractor and not same then release(core.Tractor) end
	local dist = ent:GetPos():Distance(StarCore.ShipCenter(core))
	local p = ent:GetPhysicsObject()
	local wasFrozen = same and core.Tractor.wasFrozen or (not ent:IsPlayer() and not ent:IsNPC() and IsValid(p) and not p:IsMotionEnabled())
	core.Tractor = { ent = ent, mode = mode or "hold", hold = math.max(dist, 150), wasFrozen = wasFrozen }
	core:SetNWEntity("starcore_tractor", ent)
	core:EmitSound("ambient/machines/thumper_startup1.wav", 70, 160, 0.5)
	return true
end

function StarCore.TractorThink(core)
	local tb = core.Tractor
	if not tb then return end
	local ent = tb.ent
	if not IsValid(ent) or ent:GetPos():Distance(StarCore.ShipCenter(core)) > StarCore.CV.tractorRange:GetFloat() * 1.2
		or not StarCore.CV.allowTractor:GetBool() or (ent:IsPlayer() and (not ent:Alive() or ent:InVehicle())) then
		StarCore.TractorSet(core, nil)
		return
	end
	local c = StarCore.ShipCenter(core)
	local shipAng = core:LocalToWorldAngles(core.Helm and core.Helm.refAng or Angle())
	if tb.mode == "pull" then tb.hold = math.max(tb.hold - 400 * FrameTime(), (core:GetNWVector("starcore_size"):Length() * 0.5) + 100) end
	-- pushed away faster and faster; at the end of the beam's reach it lets go and the thing flies on
	--
	if tb.mode == "push" then
		tb.pushSpeed = math.min((tb.pushSpeed or 300) + 900 * FrameTime(), 1500)
		tb.hold = tb.hold + tb.pushSpeed * FrameTime()
		if tb.hold >= StarCore.CV.tractorRange:GetFloat() * 0.95 then StarCore.TractorSet(core, nil) return end
	end
	-- (test rcjumprings: a thing caught close under a big ship was held at that distance ahead of the ship's middle - inside the
	-- ship: the beam rammed it into the own hull at up to 1240 a second, a wooden crate broke. Held outside the ship, as "pull"
	-- already stops there.)
	tb.hold = math.max(tb.hold, (core:GetNWVector("starcore_size"):Length() * 0.5) + 100)
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
-- The sounds: his picks, from AGP's Stargate sounds. StarCore also runs without AGP: then the game's own sound nearest
-- to each pick.
local DESTRUCT_SND = {
	start = { "alarm/sga_midway_selfdestruct.wav", "ambient/alarms/klaxon1.wav" },   -- when the countdown starts (5.7 s)
	again = { "alarm/sgc_evac_alarm.wav", "ambient/alarms/klaxon1.wav" },            -- again while it counts
	tick = { "glebqip/self_destruct_beep.wav", "buttons/blip1.wav" },                -- every second
	last = { "glebqip/self_destruct_beep3.wav", "buttons/blip1.wav" },               -- the last 3 seconds
	stop = { "glebqip/computer_end.wav", "buttons/button9.wav" },                    -- stopped
	boom = { "ambient/explosions/exp2.wav" },                                        -- the ship blows up
}
local AGAIN_AT = { [4] = true, [1] = true }   -- (seconds left: every 3 s once the start alarm is over)
local sndCache = {}
function StarCore.DestructSound(kind)
	if sndCache[kind] == nil then
		sndCache[kind] = false
		for _, f in ipairs(DESTRUCT_SND[kind] or {}) do
			if file.Exists("sound/" .. f, "GAME") then sndCache[kind] = f break end
		end
	end
	return sndCache[kind] or nil
end
local function destructSound(core, kind, level)
	local f = StarCore.DestructSound(kind)
	if f then core:EmitSound(f, level or 95, 100) end
end

function StarCore.SelfDestruct(core, ply, start)
	local owner = core:GetNWEntity("starcore_owner")
	if ply ~= owner and not (IsValid(ply) and ply:IsAdmin()) then return false, "no_permission" end
	local name = "StarCore.SelfDestruct" .. core:EntIndex()
	if not start then
		if timer.Exists(name) then
			timer.Remove(name)
			core:SetNWFloat("starcore_destruct", 0)
			for _, k in ipairs({ "start", "again" }) do
				local f = StarCore.DestructSound(k)
				if f then core:StopSound(f) end
			end
			destructSound(core, "stop", 90)
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
	destructSound(core, "start", 100)
	timer.Create(name, 1, secs, function()
		if not IsValid(core) then timer.Remove(name) return end
		left = left - 1
		if left == 5 or left == 3 or (left <= 2 and left > 0) then
			core.VoiceLast = nil -- every count is spoken
			hook.Run("StarCore.Event", core, "self_destruct", left)
		end
		if left > 0 then
			destructSound(core, left <= 3 and "last" or "tick", 90)
			if AGAIN_AT[left] then destructSound(core, "again", 100) end
		end
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
	-- one blast sound for the whole ship (the author's pick); the explosions below are silent (TE_EXPLFLAG_NOSOUND)
	local boom = StarCore.DestructSound("boom")
	if boom then sound.Play(boom, c, 140, 100, 1) end
	for i, e in ipairs(parts) do
		if IsValid(e) and not e:IsPlayer() then
			timer.Simple(math.min(i * 0.03, 1.5), function()
				if not IsValid(e) then return end
				local fx = EffectData(); fx:SetOrigin(e:WorldSpaceCenter()); fx:SetMagnitude(2 + level); fx:SetScale(1 + level * 0.5); fx:SetFlags(4)
				if i % 3 == 1 then util.Effect("Explosion", fx) end
				e:Remove()
			end)
		end
	end
	-- bigger blasts: a few extra explosions spread over the blast area
	for k = 1, (level - 1) * 2 do
		timer.Simple(0.2 + k * 0.15, function()
			local fx = EffectData(); fx:SetOrigin(c + VectorRand() * radius * 0.4); fx:SetMagnitude(4); fx:SetScale(3); fx:SetFlags(4)
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
