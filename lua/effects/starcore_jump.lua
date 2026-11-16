-- StarCore jump effect. Flags: 1 = charging, 2 = jump out, 3 = arrive.
-- Each player sees their own style (starcore_jump_style): 1 light streak, 2 flash, 3 portal window.
local GLOW = Material("sprites/light_glow02_add")
local FLARE = Material("effects/blueflare1")
local BEAM = Material("sprites/physbeam")
local COLOR = Color(150, 210, 255)

function EFFECT:Init(data)
	self.Phase = data:GetFlags()
	self.Pos = data:GetOrigin()
	self.To = data:GetStart()
	self.Size = math.Clamp(data:GetMagnitude(), 64, 6000)
	self.Core = data:GetEntity()
	self.Style = GetConVar("starcore_jump_style") and GetConVar("starcore_jump_style"):GetInt() or 1
	self.Start = CurTime()
	self.Dir = (self.To - self.Pos):GetNormalized()
	if self.Dir:LengthSqr() < 0.5 then self.Dir = Vector(1, 0, 0) end
	if self.Phase == 1 then
		local t1 = IsValid(self.Core) and self.Core:GetNWFloat("starcore_ftl_t1") or 0
		self.Life = math.Clamp(t1 - CurTime(), 0.5, 60)
	elseif self.Phase == 2 then
		self.Life = 1.1
	else
		self.Life = 0.9
	end
	self:SetRenderBoundsWS(self.Pos - Vector(1, 1, 1) * self.Size * 10, self.Pos + Vector(1, 1, 1) * self.Size * 10)
	if self.Phase ~= 1 then
		local dl = DynamicLight(self:EntIndex() + math.random(1000))
		if dl then
			dl.pos = self.Pos; dl.r = COLOR.r; dl.g = COLOR.g; dl.b = COLOR.b
			dl.brightness = 4; dl.size = math.min(self.Size * 4, 2000); dl.decay = 2000; dl.dietime = CurTime() + 0.8
		end
	end
end

function EFFECT:Think()
	if self.Phase == 1 and IsValid(self.Core) then
		-- the charge glow follows the ship and ends early if the jump was cancelled
		if self.Core:GetNWInt("starcore_ftl") ~= StarCore.FTL.CHARGING then return false end
		self.LocalOff = self.LocalOff or self.Core:WorldToLocal(self.Pos)
		self.Pos = self.Core:LocalToWorld(self.LocalOff)
	end
	return CurTime() - self.Start < self.Life
end

local function ring(center, normal, radius, width, alpha)
	local right = normal:Angle():Right()
	local up = normal:Angle():Up()
	render.SetMaterial(BEAM)
	render.StartBeam(33)
	for i = 0, 32 do
		local a = i / 32 * math.pi * 2
		render.AddBeam(center + (right * math.cos(a) + up * math.sin(a)) * radius, width, i / 4, Color(COLOR.r, COLOR.g, COLOR.b, alpha))
	end
	render.EndBeam()
end

function EFFECT:Render()
	local f = math.Clamp((CurTime() - self.Start) / self.Life, 0, 1)
	local s = self.Size
	if self.Phase == 1 then
		-- charging: a pulsing glow that grows
		local pulse = 0.6 + 0.4 * math.sin(CurTime() * 8)
		render.SetMaterial(GLOW)
		render.DrawSprite(self.Pos, s * (0.5 + f) * pulse, s * (0.5 + f) * pulse, Color(COLOR.r, COLOR.g, COLOR.b, 120 * pulse))
		return
	end
	if self.Style == 3 then
		-- portal window: a ring opens in front of the ship (out) or at the arrival point (in)
		local center = self.Phase == 2 and (self.Pos + self.Dir * s * 0.8) or self.Pos
		local open = self.Phase == 2 and math.sin(f * math.pi) or (1 - f)
		ring(center, self.Dir, s * 1.3 * open + 1, 40, 255 * open)
		render.SetMaterial(FLARE)
		render.DrawSprite(center, s * 2 * open, s * 2 * open, Color(255, 255, 255, 120 * open))
		return
	end
	if self.Style == 2 or self.Phase == 3 then
		-- flash (also every style's arrival)
		local a = (1 - f)
		render.SetMaterial(GLOW)
		render.DrawSprite(self.Pos, s * 4 * (0.5 + f), s * 4 * (0.5 + f), Color(255, 255, 255, 255 * a))
		render.SetMaterial(FLARE)
		render.DrawSprite(self.Pos, s * 2, s * 2, Color(COLOR.r, COLOR.g, COLOR.b, 200 * a))
		if self.Style == 1 and self.Phase == 3 then
			-- light streak arrival: a short streak behind the ship (towards where it came from) that shrinks
			render.SetMaterial(BEAM)
			render.DrawBeam(self.Pos + self.Dir * s * 6 * a, self.Pos, s * 0.6 * a, 0, 1, Color(COLOR.r, COLOR.g, COLOR.b, 255 * a))
		end
		return
	end
	-- light streak (out): glow builds up, then the ship becomes a long streak flying off
	render.SetMaterial(GLOW)
	render.DrawSprite(self.Pos, s * 3 * f, s * 3 * f, Color(255, 255, 255, 200 * f))
	local len = s * 12 * f * f
	render.SetMaterial(BEAM)
	render.DrawBeam(self.Pos, self.Pos + self.Dir * len, s * 0.8 * (1 - f * 0.5), 0, 1, Color(COLOR.r, COLOR.g, COLOR.b, 255 * (1 - f * 0.3)))
end
