-- StarCore server, level 3 (needs a Stargate pack: Ascension Gates, CAP, CAP Enhanced or EAP):
-- the ship's own gate + iris, dialling, auto-iris, and "jump to a gate". Everything checks StarGate at call time,
-- so StarCore still works when no Stargate pack is installed.
StarCore.SG = StarCore.SG or {}
local SG = StarCore.SG

local function ownerOf(ent)
	if not IsValid(ent) then return nil end
	local o = ent.CPPIGetOwner and ent:CPPIGetOwner()
	if not IsValid(o) and ent.GetCreator then o = ent:GetCreator() end
	if not IsValid(o) and ent.GetVar then o = ent:GetVar("Owner") end
	return IsValid(o) and o or nil
end

local function isFriend(a, b)
	if not IsValid(a) or not IsValid(b) then return false end
	if a == b then return true end
	if a.CPPIGetFriends then
		local f = a:CPPIGetFriends()
		if istable(f) and table.HasValue(f, b) then return true end
	end
	return false
end

-- is this Wire input fed by a wire? Then the player controls it and StarCore's automatic leaves it alone.
local function wired(ent, input)
	local inp = ent.Inputs and ent.Inputs[input]
	return inp ~= nil and IsValid(inp.Src)
end

function SG.Available() return StarGate ~= nil end

-- called from StarCore.Scan: the ship's own gate (and its iris) are the first ones among the ship parts
function SG.Attach(core)
	core.Gate, core.Iris = nil, nil
	if not SG.Available() then return end
	for _, e in ipairs(core.Parts or {}) do
		if IsValid(e) and e.IsStargate and not core.Gate then core.Gate = e end
	end
	if IsValid(core.Gate) then
		local iris = core.Gate.GetIris and core.Gate:GetIris()
		if IsValid(iris) then core.Iris = iris end
	end
	core:SetNWEntity("starcore_gate", core.Gate or NULL)
	core:SetNWEntity("starcore_iris", core.Iris or NULL)
	core:SetNWBool("starcore_iris_wired", IsValid(core.Iris) and wired(core.Iris, "Activate") or false)
end

function SG.IrisClosed(core)
	return IsValid(core.Iris) and core.Iris.IsActivated == true
end

function SG.SetIris(core, closed)
	local iris = core.Iris
	if not IsValid(iris) or iris.IsActivated == closed then return false end
	if iris.Toggle then iris:Toggle() end
	return iris.IsActivated == closed
end

-- the list for the menu: every gate on the map (for "jump to gate"), plus the dial string if our gate can dial it
function SG.GateList(core)
	local list = {}
	if not SG.Available() then return list end
	local dial = {}
	local own = core.Gate
	if IsValid(own) and own.WireGetAddresses then
		local ok, addrs = pcall(own.WireGetAddresses, own)
		if ok and istable(addrs) then
			for _, a in ipairs(addrs) do dial[#dial + 1] = { str = a[1], name = a[2], blocked = a[3] } end
		end
	end
	for _, g in ipairs(ents.FindByClass("stargate_*")) do
		if IsValid(g) and g.IsStargate and g ~= own and not (g.GetPrivate and g:GetPrivate()) then
			local addr = g.GetGateAddress and g:GetGateAddress() or ""
			local entry = {
				id = g:EntIndex(), name = (g.GetGateName and g:GetGateName() ~= "" and g:GetGateName()) or g:GetClass(),
				address = addr, group = g.GetGateGroup and g:GetGateGroup() or "", class = g:GetClass(),
				dist = math.floor(g:GetPos():Distance(core:GetPos())),
			}
			-- match our gate's dial list by the 6-symbol address part
			for _, d in ipairs(dial) do
				if addr ~= "" and d.str:sub(1, 6) == addr:sub(1, 6) and (d.str:len() == 6 or not entry.dial) then
					entry.dial = d.str
					entry.blocked = d.blocked == 1 or d.blocked == true
				end
			end
			list[#list + 1] = entry
		end
	end
	table.sort(list, function(a, b) return a.dist < b.dist end)
	return list
end

-- state for the menu
function SG.State(core)
	if not SG.Available() then return nil end
	local g = core.Gate
	local st = { hasGate = IsValid(g), list = SG.GateList(core), irisAuto = core.SGIrisAuto ~= false }
	if IsValid(g) then
		st.name = g.GetGateName and g:GetGateName() or ""
		st.address = g.GetGateAddress and g:GetGateAddress() or ""
		st.group = g.GetGateGroup and g:GetGateGroup() or ""
		st.class = g:GetClass()
	end
	return st
end

function SG.Dial(core, ply, str, mode)
	local g = core.Gate
	if not IsValid(g) then return false, "sg_no_gate" end
	if g.IsOpen or g.Dialling or g.Active then return false, "sg_busy" end
	if hook.Run("StarGate.Player.CanDialGate", ply, g) == false then return false, "no_permission" end
	str = tostring(str or ""):upper()
	if #str < 6 or #str > 9 then return false, "sg_bad_address" end
	if mode == "nox" and g.NoxDialGate then g:NoxDialGate(str)
	else g:DialGate(str, mode ~= "slow") end
	core.SGOutbound = true
	return true
end

function SG.Close(core)
	local g = core.Gate
	if not IsValid(g) then return false end
	g:AbortDialling()
	return true
end

-- auto-iris: an unknown gate dials us -> close BEFORE the wormhole opens; friends and our own gates are let in
hook.Add("StarGate.Dial", "StarCore.AutoIris", function(caller, target, address, dialType)
	if not IsValid(target) then return end
	for core in pairs(StarCore.Cores) do
		if IsValid(core) and core.Gate == target and IsValid(core.Iris) and core.SGIrisAuto ~= false and not wired(core.Iris, "Activate") then
			local shipOwner = core:GetNWEntity("starcore_owner")
			local friend = isFriend(shipOwner, ownerOf(caller)) or isFriend(ownerOf(caller), shipOwner)
			if not friend then
				if SG.SetIris(core, true) then core.SGIrisByUs = true end
				StarCore.NotifyShip(core, "sg_incoming_closed", NOTIFY_HINT)
				hook.Run("StarCore.Event", core, "incoming")
			else
				StarCore.NotifyShip(core, "sg_incoming_friend", NOTIFY_HINT)
			end
		end
	end
end)

-- every half second (from the core's Think): reopen the iris we closed once the wormhole is gone
function SG.Think(core)
	local g = core.Gate
	if not IsValid(g) then return end
	core:SetNWBool("starcore_iris_closed", SG.IrisClosed(core))
	core:SetNWBool("starcore_gate_open", g.IsOpen == true)
	core:SetNWBool("starcore_gate_busy", (g.Active or g.Dialling) == true)
	core:SetNWBool("starcore_gate_inbound", (g.Active and not g.Outbound) == true)
	if not g.Active and not g.IsOpen and not g.Dialling then
		core.SGOutbound = nil
		if core.SGIrisByUs and core.SGIrisAuto ~= false and IsValid(core.Iris) and not wired(core.Iris, "Activate") then
			SG.SetIris(core, false)
			core.SGIrisByUs = nil
		end
	end
end

-- "jump to a gate": in front of the gate, with room for the whole ship
function SG.JumpSpot(core, gate)
	if not IsValid(gate) or not gate.IsStargate then return nil end
	local size = core.LocalMaxs and (core.LocalMaxs - core.LocalMins) or Vector(200, 200, 200)
	local radius = math.max(size.x, size.y) * 0.6
	local centerWorld = StarCore.ShipCenter(core)
	local coreToCenter = centerWorld - core:GetPos()
	local wantCenter = gate:GetPos() + gate:GetForward() * (radius + 450) + Vector(0, 0, size.z * 0.5 + 50)
	return wantCenter - coreToCenter
end
