-- StarCore ship voice: the ship announces what happens (jump, arrival, shield down, attack, low power ...).
-- Server: every StarCore.Event goes to the people on board. Client: plays a voice line if one exists
-- (sound/starcore/voice/<language>/<event>.wav, then sound/starcore/voice/<event>.wav), otherwise our own chime,
-- and shows the sentence as a subtitle. Each player switches it on/off (starcore_voice).
StarCore.VoiceEvents = {
	jump_charge = "info", arrived = "info", autopilot_arrived = "info", beam = "info", iris_closed = "info",
	power_low = "warn", incoming = "warn", hostile = "warn", hull_low = "warn",
	shield_down = "alert", under_attack = "alert", hull_critical = "alert", self_destruct = "alert", self_destruct_stop = "info", destroyed = "alert",
}

if SERVER then
	util.AddNetworkString("starcore_voice")

	function StarCore.Crew(core)
		local list, seen = {}, {}
		local function add(p) if IsValid(p) and not seen[p] then seen[p] = true; list[#list + 1] = p end end
		for _, seat in ipairs(core.Seats or {}) do if IsValid(seat) then add(seat:GetDriver()) end end
		for _, p in ipairs(player.GetAll()) do if StarCore.IsInside(core, p) then add(p) end end
		return list
	end

	hook.Add("StarCore.Event", "StarCore.Voice", function(core, event, arg)
		if not IsValid(core) or not StarCore.VoiceEvents[event] then return end
		-- the same line at most every 4 s
		core.VoiceLast = core.VoiceLast or {}
		if (core.VoiceLast[event] or 0) > CurTime() then return end
		core.VoiceLast[event] = CurTime() + 4
		local to = StarCore.Crew(core)
		if #to == 0 then return end
		net.Start("starcore_voice")
		net.WriteString(event)
		net.WriteString(tostring(arg or ""))
		net.Send(to)
	end)
	return
end

CreateClientConVar("starcore_voice", "1", true, false, "StarCore ship voice and subtitles on/off", 0, 1)
local subtitle, subtitleUntil, subtitleLevel = nil, 0, "info"
local COL = { info = Color(140, 220, 255), warn = Color(255, 200, 80), alert = Color(255, 90, 70) }
local CHIME = { info = "buttons/blip1.wav", warn = "buttons/button10.wav", alert = "ambient/alarms/klaxon1.wav" }

net.Receive("starcore_voice", function()
	local event, arg = net.ReadString(), net.ReadString()
	if not GetConVar("starcore_voice"):GetBool() then return end
	local level = StarCore.VoiceEvents[event] or "info"
	local lang = GetConVar("gmod_language") and GetConVar("gmod_language"):GetString() or "en"
	local snd
	for _, p in ipairs({ "starcore/voice/" .. lang .. "/" .. event .. ".wav", "starcore/voice/" .. event .. ".wav" }) do
		if file.Exists("sound/" .. p, "GAME") then snd = p break end
	end
	-- (only real audio - the generated chime tones are gone: sounds every Garry's Mod has)
	surface.PlaySound(snd or CHIME[level] or CHIME.info)
	subtitle = StarCore.T("voice_" .. event, arg)
	subtitleUntil = CurTime() + 4
	subtitleLevel = level
end)

surface.CreateFont("StarCoreVoice", { font = "Roboto", size = 26, weight = 700 })
hook.Add("HUDPaint", "StarCore.Voice", function()
	if not subtitle or CurTime() > subtitleUntil then return end
	local a = math.Clamp((subtitleUntil - CurTime()) * 255, 0, 255)
	local col = COL[subtitleLevel] or COL.info
	draw.SimpleTextOutlined("◆ " .. subtitle, "StarCoreVoice", ScrW() / 2, ScrH() * 0.18, Color(col.r, col.g, col.b, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, Color(0, 0, 0, a * 0.8))
end)
