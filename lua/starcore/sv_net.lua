-- StarCore server: menu data and commands from players (every command is checked: permission, distance, rate)
util.AddNetworkString("starcore_menu")
util.AddNetworkString("starcore_cmd")

local LIMITS = { -- min, max for the per-ship settings (speed also capped by starcore_max_speed while flying)
	speed = { 50, 20000 }, boost = { 1, 4 }, climb = { 20, 5000 }, turn = { 5, 120 }, accel = { 50, 5000 },
	charge = { 0, 60 }, cooldown = { 0, 600 }, idleFreeze = { 0, 3600 }, radarRange = { 1000, 200000 },
	shieldSize = { 0, 8192 }, theme = { 1, 5 }, shieldStrength = { -5, 5 }, shieldFreq = { -1, 1500 },
	destructSize = { 1, 5 },
}

function StarCore.OpenMenu(ply, core)
	core.Viewers = core.Viewers or {}
	core.Viewers[ply] = CurTime() + 3
	net.Start("starcore_menu")
	net.WriteEntity(core)
	net.WriteTable({ settings = core.Settings, marks = core.Marks, design = core.Design, sg = StarCore.SG and StarCore.SG.State(core) or nil,
		power = StarCore.PowerState and StarCore.PowerState(core) or nil })
	net.Send(ply)
end

local function nearEnough(core, ply)
	if ply:InVehicle() and core.Seats and table.HasValue(core.Seats, ply:GetVehicle()) then return true end
	return ply:GetPos():DistToSqr(core:GetPos()) < 1500 * 1500 or StarCore.IsInside(core, ply)
end

local handlers = {}

handlers.hover = function(core, ply, d)
	StarCore.HelmSetOn(core, d.on == true)
	return d.quiet == true   -- (the hover key of the pilot seat: no menu window comes up)
end

-- 2026-11-14 (owner: "how can the player set for the starcore were oriantation forward is"): the ship's front = the way the
-- player looks now (stand facing the nose, press the button); clear = back to the pilot seat's / the core's own direction
handlers.front = function(core, ply, d)
	if d.clear then
		core.FrontYaw = nil
	else
		core.FrontYaw = math.Round(core:WorldToLocalAngles(Angle(0, ply:EyeAngles().y, 0)).y, 1)
	end
	core:SetNWFloat("starcore_front", isnumber(core.FrontYaw) and core.FrontYaw or 1000)
	if core.Helm and StarCore.HelmRelock then StarCore.HelmRelock(core) end
	StarCore.Notify(ply, d.clear and "front_cleared" or "front_set", NOTIFY_GENERIC)
end

-- 2026-11-15: first / third person for whoever sits in one of the ship's seats (Ctrl no longer does it in the pilot seat:
-- there Ctrl flies down, see StarCore.PilotNoDuckView in sv_helm.lua)
handlers.view = function(core, ply, d)
	local veh = ply:GetVehicle()
	if not (IsValid(veh) and veh.SetThirdPersonMode and core.Seats and table.HasValue(core.Seats, veh)) then return end
	veh:SetThirdPersonMode(not veh:GetThirdPersonMode())
end

handlers.settings = function(core, ply, d)
	local shieldChanged = false
	for k, v in pairs(d.values or {}) do
		local lim = LIMITS[k]
		if lim and isnumber(v) then
			core.Settings[k] = math.Clamp(v, lim[1], lim[2])
			if k:sub(1, 6) == "shield" then shieldChanged = true end
		end
	end
	if shieldChanged then
		for _, g in ipairs(core.Shields or {}) do if IsValid(g) then StarCore.ShieldApply(core, g) end end
	end
	if d.values and d.values.autoDefence ~= nil then core.Settings.autoDefence = d.values.autoDefence == true end
	if d.values and d.values.shieldAuto ~= nil then core.Settings.shieldAuto = d.values.shieldAuto == true end
	if d.values and istable(d.values.shieldColor) then
		local c = d.values.shieldColor
		core.Settings.shieldColor = { math.Clamp(tonumber(c[1]) or 1, 0, 1), math.Clamp(tonumber(c[2]) or 1, 0, 1), math.Clamp(tonumber(c[3]) or 1, 0, 1) }
		for _, g in ipairs(core.Shields or {}) do if IsValid(g) then StarCore.ShieldApply(core, g) end end
	end
	if d.values and d.values.public ~= nil then
		core.Settings.public = d.values.public == true
		core:SetNWBool("starcore_public", core.Settings.public)
	end
end

-- core design (model): owner, prop protection friends and admins only, also in public mode
handlers.design = function(core, ply, d)
	if not isstring(d.id) then return end
	if not StarCore.CanControl(core, ply, true) then StarCore.Notify(ply, "no_permission", NOTIFY_ERROR) return end
	local ok, why = core:ChangeDesign(d.id)
	if not ok then StarCore.Notify(ply, why, NOTIFY_ERROR) end
end

handlers.jump = function(core, ply, d)
	local target
	if d.kind == "mark" and isnumber(d.index) then target = { kind = "mark", index = math.floor(d.index) }
	elseif d.kind == "coord" and isvector(d.pos) then target = { kind = "coord", pos = d.pos }
	elseif d.kind == "gate" and isnumber(d.id) then target = { kind = "gate", id = math.floor(d.id) }
	elseif d.kind == "contact" and isnumber(d.id) then target = { kind = "contact", id = math.floor(d.id) }
	elseif d.kind == "owner" then target = { kind = "owner" } end
	if not target then return end
	local ok, why = StarCore.RequestJump(core, ply, target)
	if not ok then StarCore.Notify(ply, why, NOTIFY_ERROR) end
end

handlers.cancel = function(core, ply, d)
	StarCore.CancelJump(core)
end

handlers.mark_save = function(core, ply, d)
	if isnumber(d.index) then StarCore.SaveMark(core, math.floor(d.index), isstring(d.name) and d.name or nil) end
end

handlers.mark_delete = function(core, ply, d)
	if isnumber(d.index) and core.Marks[d.index] then
		table.remove(core.Marks, math.floor(d.index))
	end
end

handlers.mark_rename = function(core, ply, d)
	local m = isnumber(d.index) and core.Marks[d.index]
	if m and isstring(d.name) and d.name ~= "" then m.name = d.name:sub(1, 32) end
end

handlers.freeze = function(core, ply, d)
	if core.Helm and core.Helm.on then StarCore.SetFrozen(core, d.on == true) end
	return d.quiet == true   -- (the freeze key of the pilot seat: no menu window comes up)
end

-- Stargate (level 3)
handlers.sg_dial = function(core, ply, d)
	if not (StarCore.SG and StarCore.SG.Available()) then return end
	local ok, why = StarCore.SG.Dial(core, ply, d.address, d.mode)
	if not ok then StarCore.Notify(ply, why, NOTIFY_ERROR) end
end

handlers.sg_close = function(core, ply, d)
	if StarCore.SG and StarCore.SG.Available() then StarCore.SG.Close(core) end
end

handlers.sg_iris = function(core, ply, d)
	if not (StarCore.SG and StarCore.SG.Available()) then return end
	if not IsValid(core.Iris) then StarCore.Notify(ply, "sg_no_iris", NOTIFY_ERROR) return end
	StarCore.SG.SetIris(core, not StarCore.SG.IrisClosed(core))
	core.SGIrisByUs = nil -- the player decided; auto mode does not reopen it
end

handlers.sg_irisauto = function(core, ply, d)
	core.SGIrisAuto = d.on == true
end

-- radar / weapons (handlers returning true do not resend the whole menu)
handlers.shield = function(core, ply, d)
	StarCore.ShieldSet(core, d.on == true)
end

handlers.beam_aboard = function(core, ply, d)
	local ok, why = StarCore.BeamAboard(core, ply, isnumber(d.id) and Entity(math.floor(d.id)) or NULL)
	if not ok then StarCore.Notify(ply, why, NOTIFY_ERROR) end
	return true
end

handlers.beam_down = function(core, ply, d)
	local ok, why = StarCore.BeamDown(core, ply, isnumber(d.id) and d.id > 0 and Entity(math.floor(d.id)) or nil)
	if not ok then StarCore.Notify(ply, why, NOTIFY_ERROR) end
	return true
end

handlers.autopilot = function(core, ply, d)
	if d.stop then StarCore.AutopilotSet(core, nil) return end
	local target
	if d.kind == "mark" and isnumber(d.index) and core.Marks[math.floor(d.index)] then
		target = core.Marks[math.floor(d.index)].pos + (StarCore.ShipCenter(core) - core:GetPos())
	elseif d.kind == "coord" and isvector(d.pos) then target = d.pos
	elseif d.kind == "gate" and isnumber(d.id) and StarCore.SG and StarCore.SG.Available() then
		local spot = StarCore.SG.JumpSpot(core, Entity(math.floor(d.id)))
		target = spot and spot + (StarCore.ShipCenter(core) - core:GetPos())
	elseif d.kind == "contact" and isnumber(d.id) then
		local e = Entity(math.floor(d.id))
		if IsValid(e) and StarCore.ContactOf(core, e) then target = e end
	end
	if not target then return end
	local ok, why = StarCore.AutopilotSet(core, target, d.follow == true)
	if not ok then StarCore.Notify(ply, why, NOTIFY_ERROR) end
end

local function aimed(ply, core)
	local tr = ply:GetEyeTrace()
	if ply:InVehicle() then
		tr = util.TraceLine({ start = ply:GetShootPos(), endpos = ply:GetShootPos() + ply:GetAimVector() * 60000, filter = core.Parts })
	end
	return tr.Entity
end

handlers.tractor = function(core, ply, d)
	if d.off then StarCore.TractorSet(core, nil) return true end
	local ent = (d.target and IsValid(core.Target)) and core.Target or aimed(ply, core)
	local ok, why = StarCore.TractorSet(core, ent, d.mode == "pull" and "pull" or "hold")
	if not ok then StarCore.Notify(ply, why, NOTIFY_ERROR) end
	return true
end

handlers.cloak = function(core, ply, d)
	local ok, why = StarCore.CloakSet(core, d.on == true)
	if not ok then StarCore.Notify(ply, why, NOTIFY_ERROR) end
end

handlers.land = function(core, ply, d)
	local ok, why = StarCore.Land(core)
	if not ok then StarCore.Notify(ply, why, NOTIFY_ERROR) end
end

handlers.fleet = function(core, ply, d)
	if d.leave then StarCore.FleetLeave(core) return end
	local ok, why = StarCore.FleetJoin(core, IsValid(core.Target) and core.Target or NULL)
	if not ok then StarCore.Notify(ply, why, NOTIFY_ERROR) else StarCore.Notify(ply, "fleet_joined", NOTIFY_GENERIC) end
end

handlers.selfdestruct = function(core, ply, d)
	local ok, why = StarCore.SelfDestruct(core, ply, d.on == true)
	if not ok then StarCore.Notify(ply, why, NOTIFY_ERROR) end
end

handlers.watch = function(core, ply, d)
	core.Viewers = core.Viewers or {}
	core.Viewers[ply] = CurTime() + 3
	return true
end

handlers.target = function(core, ply, d)
	if d.step then StarCore.CycleTarget(core, d.step > 0 and 1 or -1)
	elseif isnumber(d.id) then
		local e = Entity(math.floor(d.id))
		if IsValid(e) and StarCore.ContactOf(core, e) then core.Target = e end
	end
	core:SetNWEntity("starcore_target", core.Target or NULL)
	return true
end

handlers.engage = function(core, ply, d)
	core.Engage = d.on == true
	if not core.Engage then StarCore.StopWeapons(core) end
	return true
end

handlers.lock = function(core, ply, d)
	core.TargetLock = d.on == true
	core:SetNWBool("starcore_lock", core.TargetLock)
	return true
end

handlers.hostile = function(core, ply, d)
	local e = isnumber(d.id) and Entity(math.floor(d.id))
	if not IsValid(e) then return true end
	core.Hostiles = core.Hostiles or {}
	if d.on then
		local c = StarCore.ContactOf(core, e)
		if c and c.iff ~= StarCore.IFF.own and c.iff ~= StarCore.IFF.crew and c.iff ~= StarCore.IFF.friend then core.Hostiles[e] = CurTime() + 600 end
	else
		core.Hostiles[e] = nil
	end
	return true
end

net.Receive("starcore_cmd", function(_, ply)
	local core = net.ReadEntity()
	local cmd = net.ReadString()
	local data = net.ReadTable()
	if not IsValid(core) or core:GetClass() ~= "starcore" or not handlers[cmd] then return end
	if cmd ~= "watch" then
		if (ply.StarCoreNextCmd or 0) > CurTime() then return end
		ply.StarCoreNextCmd = CurTime() + 0.1
	end
	if not StarCore.CanControl(core, ply) then StarCore.Notify(ply, "no_permission", NOTIFY_ERROR) return end
	if not nearEnough(core, ply) then StarCore.Notify(ply, "too_far_from_core", NOTIFY_ERROR) return end
	local quiet = handlers[cmd](core, ply, data) == true
	StarCore.SyncNW(core)
	if quiet then return end
	StarCore.OpenMenu(ply, core) -- send the fresh state back
end)
