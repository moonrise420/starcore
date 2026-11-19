-- StarCore server: power (reads every energy source on the ship) and shields (drives CAP shield generators
-- with correct values). Level 3 parts (ZPMs, naquadah generators, CAP shields) are found by their fields/functions,
-- so other packs with the same API work too. A shield whose "Activate" input is wired stays under the player's control.
local function wired(ent, input)
	local inp = ent.Inputs and ent.Inputs[input]
	return inp ~= nil and IsValid(inp.Src)
end

local function isSource(e)
	return isnumber(e.Energy) and isnumber(e.MaxEnergy) and e.MaxEnergy > 0 and e:GetClass() ~= "starcore"
end

local function isShield(e)
	return isfunction(e.Status) and isfunction(e.Enabled) and isfunction(e.SetShieldColor) and isfunction(e.SetSize)
end

function StarCore.PowerAttach(core)
	core.PowerSources, core.Shields, core.RDPart = {}, {}, nil
	for _, e in ipairs(core.Parts or {}) do
		if IsValid(e) then
			if isSource(e) then core.PowerSources[#core.PowerSources + 1] = e end
			if isShield(e) then core.Shields[#core.Shields + 1] = e end
			if not core.RDPart and e.HasRD and isfunction(e.GetResource) then core.RDPart = e end
		end
	end
	core:SetNWInt("starcore_sources", #core.PowerSources)
	core:SetNWInt("starcore_shields", #core.Shields)
end

-- AGP 2026-11-08: the energy the ship really has, as its parts see it through the resource network: PowerGrid's own
-- network, or Spacebuild's Resource Distribution when that carries the energy. Before, only ZPM-like sources (their
-- own reserve) and one Ascension Gates RD part were read: a ship powered by PowerGrid cells / solar panels showed "no
-- power" (no low-power warnings, starcore_jump_energy never charged), and in manual mode an unlinked ZPM showed
-- "Power 100 %" while the shield and transporter had nothing. Now every network the ship's parts are in counts once,
-- when something is connected in it (a lone, unlinked part feeds nothing), and a source's reserve only when the source
-- is in such a network. No network at all (PowerGrid off: free energy, or another resource addon): as before.
local function pgNet()
	local P = AGP and AGP.Power
	if P and P.Network and P.Parts and PowerGrid and PowerGrid.Active then return P end
end
local function rdNet()
	local RD
	if PowerGrid and PowerGrid.RD3 then RD = PowerGrid.RD3()
	elseif CAF and CAF.GetAddon then RD = CAF.GetAddon("Resource Distribution") end
	if RD and RD.GetEntityTable and RD.GetNetResourceAmount and RD.GetNetNetworkCapacity then return RD end
end

-- PowerGrid: the network of part e (once per network; each part's storage counted once)
local function pgAdd(P, e, nets, inNet, done, counted)
	done[e] = true
	local list = P.Network(e)
	local live = #list >= 2
	for _, x in ipairs(list) do
		done[x] = true
		if not live and P.Connected and P.Connected(x) then live = true end
	end
	if not live then return end
	local n = { energy = 0, cap = 0 }
	for _, x in ipairs(list) do
		inNet[x] = true
		local r = x.AGPRes and x.AGPRes.energy
		if r and not counted[x] then
			counted[x] = true
			n.energy, n.cap = n.energy + math.max(r.amount or 0, 0), n.cap + (r.max or 0)
			n.part = n.part or x
		end
	end
	if n.part then nets[#nets + 1] = n end
end

-- Resource Distribution: the network part e is linked to (network 0 = not linked)
local function rdAdd(RD, e, nets, inNet, done)
	local id = e.IsNode and e.netid or nil
	if not id then
		local t = RD.GetEntityTable(e)
		id = istable(t) and t.network or nil
	end
	if not isnumber(id) or id == 0 then return end
	inNet[e] = true
	if done[id] then return end
	done[id] = true
	-- linked nodes are one network for RD (its totals cover them all)
	local group = RD.getConnectedNets and RD.getConnectedNets(id)
	for k, v in pairs(istable(group) and group or {}) do
		if isnumber(k) then done[k] = true end
		if isnumber(v) then done[v] = true end
	end
	nets[#nets + 1] = { energy = RD.GetNetResourceAmount(id, "energy") or 0, cap = RD.GetNetNetworkCapacity(id, "energy") or 0, part = e, rd = RD }
end

-- nil when no network runs; else the ship's networks { { energy, cap, part }, ... } and the set of parts in them
function StarCore.PowerNets(core)
	local P = pgNet()
	local RD = not P and rdNet()
	if not P and not RD then return nil end
	local nets, inNet, done, counted = {}, {}, {}, {}
	for _, e in ipairs(core.OwnParts or core.Parts or {}) do   -- (2026-11-17: not the docked ships' parts)
		if P and IsValid(e) and P.Parts[e] and not done[e] then pgAdd(P, e, nets, inNet, done, counted)
		elseif RD and IsValid(e) then rdAdd(RD, e, nets, inNet, done) end
	end
	return nets, inNet
end

-- total stored energy of the ship (sources + the resource network if there is one)
function StarCore.PowerTotals(core)
	local nets, inNet = StarCore.PowerNets(core)   -- AGP 2026-11-08
	local total, max = 0, 0
	for _, e in ipairs(core.PowerSources or {}) do
		if IsValid(e) and (not nets or inNet[e]) then total = total + math.max(e.Energy, 0); max = max + e.MaxEnergy end
	end
	local net, netCap = 0, 0
	if nets then
		for _, n in ipairs(nets) do net, netCap = net + n.energy, netCap + n.cap end
		return total, max, net, netCap
	end
	local rd = core.RDPart
	if IsValid(rd) then
		net = rd:GetResource("energy", 0) or 0
		netCap = isfunction(rd.GetNetworkCapacity) and (rd:GetNetworkCapacity("energy", 0) or 0) or 0
	end
	return total, max, net, netCap
end

function StarCore.PowerThink(core)
	local now = CurTime()
	if now < (core.NextPower or 0) then return end
	core.NextPower = now + 1
	local total, max, net, netCap = StarCore.PowerTotals(core)
	local stored = total + net
	local rate = 0
	if core.LastStored then rate = (stored - core.LastStored) / math.max(now - (core.LastStoredT or now - 1), 0.1) end
	core.LastStored, core.LastStoredT = stored, now
	core.PowerRate = (core.PowerRate or rate) * 0.6 + rate * 0.4 -- smoothed
	local pct = (max + netCap) > 0 and stored / (max + netCap) * 100 or -1
	core:SetNWFloat("starcore_power_pct", pct)
	core:SetNWFloat("starcore_power_total", stored)
	core:SetNWFloat("starcore_power_rate", core.PowerRate)
	core:SetNWFloat("starcore_power_left", core.PowerRate < -0.01 and stored / -core.PowerRate or -1)
	if pct >= 0 and pct < 15 and not core.LowPowerWarned then
		core.LowPowerWarned = true
		StarCore.NotifyShip(core, "power_low", NOTIFY_ERROR)
		hook.Run("StarCore.Event", core, "power_low")
	elseif pct >= 20 then
		core.LowPowerWarned = nil
	end

	-- shields: state for the menu/HUD, and keep the chosen settings applied
	local up, strength, depleted = false, -1, false
	for _, g in ipairs(core.Shields or {}) do
		if IsValid(g) then
			if g:Enabled() then up = true end
			if isnumber(g.Strength) then strength = math.max(strength, g.Strength) end
			if g.Depleted then depleted = true end
		end
	end
	core:SetNWBool("starcore_shield_up", up)
	core:SetNWFloat("starcore_shield_strength", strength)
	core:SetNWBool("starcore_shield_depleted", depleted)
	if core.ShieldWasUp and not up and not core.ShieldOffByUs then
		StarCore.NotifyShip(core, "shield_down_alert", NOTIFY_ERROR)
		hook.Run("StarCore.Event", core, "shield_down")
	end
	core.ShieldWasUp, core.ShieldOffByUs = up, nil
end

-- apply the ship's shield settings (size and colour any time; strength preset only while off, CAP rescales otherwise)
function StarCore.ShieldApply(core, g)
	local s = core.Settings
	if s.shieldSize and s.shieldSize > 0 then g:SetSize(s.shieldSize) end
	if istable(s.shieldColor) then g:SetShieldColor(s.shieldColor[1] or 1, s.shieldColor[2] or 1, s.shieldColor[3] or 1) end
	if isnumber(s.shieldFreq) and s.shieldFreq >= 0 and isfunction(g.SetFrequency) then g:SetFrequency(s.shieldFreq) end
	if isnumber(s.shieldStrength) and isfunction(g.SetMultiplier) and not g:Enabled() then g:SetMultiplier(math.Clamp(math.floor(s.shieldStrength), -5, 5)) end
end

-- on/off; returns how many shields are up afterwards
function StarCore.ShieldSet(core, on)
	local upCount = 0
	for _, g in ipairs(core.Shields or {}) do
		if IsValid(g) and not wired(g, "Activate") then
			if on then
				StarCore.ShieldApply(core, g)
				if not g:Enabled() then g:Status(true) end
			elseif g:Enabled() then
				core.ShieldOffByUs = true
				g:Status(false)
			end
		end
		if IsValid(g) and g:Enabled() then upCount = upCount + 1 end
	end
	if on and upCount == 0 and #(core.Shields or {}) > 0 then StarCore.NotifyShip(core, "shield_failed", NOTIFY_ERROR) end
	return upCount
end

-- auto-raise: when the ship gets hit and the shield is down
hook.Add("EntityTakeDamage", "StarCore.ShieldAuto", function(ent, dmg)
	local core = StarCore.PartCore and StarCore.PartCore[ent]
	if not IsValid(core) or not core.Settings.shieldAuto then return end
	if (core.NextAutoShield or 0) > CurTime() then return end
	core.NextAutoShield = CurTime() + 3
	if not core:GetNWBool("starcore_shield_up") and #(core.Shields or {}) > 0 then
		timer.Simple(0, function() if IsValid(core) then StarCore.ShieldSet(core, true) end end)
	end
end)

-- optional: hyperspace jumps cost energy (server setting starcore_jump_energy, per 1000 units; needs a resource network)
-- AGP 2026-11-08: the ship's networks pay (StarCore.PowerNets); only with no network running, the one RD part as before
function StarCore.JumpCost(core, dist)
	local per = StarCore.CV.jumpEnergy:GetFloat()
	if per <= 0 then return 0 end
	local nets = StarCore.PowerNets(core)
	if nets then
		if #nets == 0 then return 0 end
	elseif not IsValid(core.RDPart) then return 0 end
	return math.ceil(per * dist / 1000)
end

-- what the ship has to pay a jump with (stored in its networks, not the sources' reserves)
function StarCore.JumpEnergy(core)
	local nets = StarCore.PowerNets(core)
	if nets then
		local have = 0
		for _, n in ipairs(nets) do have = have + n.energy end
		return have
	end
	local rd = core.RDPart
	return IsValid(rd) and (rd:GetResource("energy", 0) or 0) or 0
end

function StarCore.PayJump(core, cost)
	if cost <= 0 then return true end
	local nets = StarCore.PowerNets(core)
	if nets then
		if StarCore.JumpEnergy(core) < cost then return false end
		table.sort(nets, function(a, b) return a.energy > b.energy end)
		local left = cost
		for _, n in ipairs(nets) do
			if left <= 0 then break end
			local want = math.min(left, n.energy)
			if want > 0 then
				local took
				if n.rd then
					n.rd.ConsumeResource(n.part, "energy", want)
					took = want
				else
					took = AGP.Power.ConsumeResource(n.part, "energy", want) or 0
				end
				left = left - took
			end
		end
		return true
	end
	local rd = core.RDPart
	if not IsValid(rd) or (rd:GetResource("energy", 0) or 0) < cost then return false end
	rd:ConsumeResource("energy", cost)
	return true
end

-- menu data: the sources one by one
function StarCore.PowerState(core)
	local list = {}
	local nets, inNet = StarCore.PowerNets(core)   -- AGP 2026-11-08: only sources that feed the ship (see PowerTotals)
	for _, e in ipairs(core.PowerSources or {}) do
		if IsValid(e) and (not nets or inNet[e]) then list[#list + 1] = { class = e:GetClass(), pct = math.floor(math.max(e.Energy, 0) / e.MaxEnergy * 100) } end
	end
	local _, _, net, netCap = StarCore.PowerTotals(core)
	return { sources = list, net = math.floor(net), netCap = math.floor(netCap), shields = #(core.Shields or {}),
		shieldMax = (core.Shields and IsValid(core.Shields[1]) and core.Shields[1].MaxSize) or 2048,
		shieldWired = core.Shields and IsValid(core.Shields[1]) and wired(core.Shields[1], "Activate") or false }
end
