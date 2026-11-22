-- StarCore client: the ship menu (R in the pilot seat, or E on the core). Tabs: Helm, Jump, Settings.
local T = StarCore.T
local U = StarCore.Units
local FTL = StarCore.FTL
local frame, current, state
local build -- the whole menu (defined at the end)

-- AGP: every command reply rebuilt the whole window: a slider or the colour mixer vanished under the mouse mid-drag
-- and every scroll position jumped back to the top. Now a reply for the open window sets the open controls in place
-- (live below), rebuilds only a tab whose own data changed (never while the mouse button is held or one of its text
-- fields is in use) and a rebuilt tab keeps its scroll position.
local live = {}        -- name -> { pnl = panel, fn = function(state) }: runs on every reply for the open core
local applying = false -- live setters are running: the controls' change callbacks must not send the value back
local function onReply(name, pnl, fn) live[name] = { pnl = pnl, fn = fn } end
-- a checkbox that follows the reply (get(state) -> true/false, nil = leave it)
local function liveCheck(cb, name, get)
	local change = cb.OnChange
	cb.OnChange = function(...) if not applying and change then change(...) end end
	onReply(name, cb, function(st)
		local want = get(st)
		if want ~= nil and cb:GetChecked() ~= want then cb:SetValue(want and 1 or 0) end
	end)
end

-- ===== look: every control is painted in the ship's theme (dark boxes, theme text), never white on white =====
local TH, C = StarCore.Themes[1], {}
local function lum(c) return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b end
-- the wanted text colour on a background, or near black/white when it would be hard to read there
local function textOn(bg, fg)
	if math.abs(lum(fg) - lum(bg)) >= 90 then return fg end
	return lum(bg) > 128 and Color(10, 10, 10) or Color(240, 240, 240)
end
local function setTheme(id)
	TH = StarCore.Themes[id] or StarCore.Themes[1]
	local bg = TH.bg
	C.frame = Color(bg.r, bg.g, bg.b, 250)
	C.panel = Color(math.min(bg.r + 14, 255), math.min(bg.g + 14, 255), math.min(bg.b + 14, 255))
	C.box = Color(bg.r * 0.45, bg.g * 0.45, bg.b * 0.45)
	C.alt = Color(math.min(bg.r * 0.45 + 10, 255), math.min(bg.g * 0.45 + 10, 255), math.min(bg.b * 0.45 + 10, 255))
	C.text = textOn(C.panel, TH.fg)
	C.boxText = textOn(C.box, TH.fg)
	C.dim = Color(C.boxText.r, C.boxText.g, C.boxText.b, 110)
	C.btn, C.btnHover, C.accent = TH.button, TH.hover, TH.accent
	C.btnText = textOn(TH.button, TH.fg)
	C.btnHoverText = textOn(TH.hover, TH.fg)
	C.accentText = textOn(TH.accent, TH.title)
end
setTheme(1)

local function paintBox(w, h, col, border)
	if border then
		draw.RoundedBox(4, 0, 0, w, h, border)
		draw.RoundedBox(4, 1, 1, w - 2, h - 2, col)
	else
		draw.RoundedBox(4, 0, 0, w, h, col)
	end
end

local function styleBar(bar)
	if not IsValid(bar) then return end
	if bar.SetHideButtons then bar:SetHideButtons(true) end
	bar.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, C.box) end
	if IsValid(bar.btnGrip) then bar.btnGrip.Paint = function(self, w, h) draw.RoundedBox(4, 2, 0, w - 4, h, self:IsHovered() and C.btnHover or C.btn) end end
	for _, b in ipairs({ bar.btnUp, bar.btnDown }) do
		if IsValid(b) then b.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, C.btn) end end
	end
end

local function styleEntry(p)
	p.Paint = function(self, w, h)
		paintBox(w, h, C.box, self:HasFocus() and C.accent or C.btn)
		if self:GetText() == "" and not self:HasFocus() then
			local ph = self.GetPlaceholderText and self:GetPlaceholderText() or ""
			if ph ~= "" then draw.SimpleText(language.GetPhrase(ph), self.m_FontName or "DermaDefault", 3, h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
		end
		self:DrawTextEntryText(C.boxText, C.accent, C.boxText)
	end
end

-- drop-down lists (combo boxes) are separate menus: they get the same look when they open
local function styleMenu(menu)
	if not IsValid(menu) then return end
	menu.Paint = function(_, w, h) paintBox(w, h, C.box, C.accent) end
	for _, o in ipairs(menu.GetCanvas and menu:GetCanvas():GetChildren() or menu:GetChildren()) do
		if o.SetTextColor then
			o.Paint = function(self, w, h)
				local hov = self:IsHovered()
				if hov then draw.RoundedBox(2, 1, 0, w - 2, h, C.accent) end
				self:SetTextColor(hov and C.accentText or C.boxText)
			end
		end
	end
end

local STYLE = {}
STYLE.DFrame = function(p)
	p.Paint = function(_, w, h)
		draw.RoundedBox(10, 0, 0, w, h, C.frame)
		draw.RoundedBoxEx(6, 0, 0, w, 24, C.accent, true, true, false, false)
	end
	if IsValid(p.lblTitle) then p.lblTitle:SetTextColor(C.accentText) end
end
STYLE.DPropertySheet = function(p)
	p.Paint = function(self, w, h)
		local tab = self:GetActiveTab()
		local off = IsValid(tab) and tab:GetTall() - 8 or 20
		draw.RoundedBox(4, 0, off, w, h - off, C.panel)
	end
	local add = p.AddSheet
	p.AddSheet = function(self, ...)
		local sh = add(self, ...)
		if sh and IsValid(sh.Tab) then
			sh.Tab.Paint = function(tab, w, h)
				local active = tab:IsActive()
				local col = active and C.accent or (tab:IsHovered() and C.btnHover or C.btn)
				draw.RoundedBoxEx(4, 0, 0, w, h, col, true, true, false, false)
				tab:SetTextColor(active and C.accentText or (tab:IsHovered() and C.btnHoverText or C.btnText))
			end
		end
		return sh
	end
end
STYLE.DScrollPanel = function(p) styleBar(p:GetVBar()) end
STYLE.DLabel = function(p) p:SetTextColor(C.text) end
STYLE.DButton = function(p)
	p.Paint = function(self, w, h)
		local col, tc = C.btn, C.btnText
		if not self:IsEnabled() then col, tc = C.box, C.dim
		elseif self:IsDown() then col, tc = C.accent, C.accentText
		elseif self:IsHovered() then col, tc = C.btnHover, C.btnHoverText end
		draw.RoundedBox(4, 0, 0, w, h, col)
		self:SetTextColor(tc)
	end
end
STYLE.DTextEntry = styleEntry
STYLE.DComboBox = function(p)
	p:SetTextColor(C.boxText)
	p.Paint = function(self, w, h) paintBox(w, h, self:IsHovered() and C.alt or C.box, C.accent) end
	local open = p.OpenMenu
	p.OpenMenu = function(self, ...)
		open(self, ...)
		styleMenu(self.Menu)
	end
end
STYLE.DCheckBoxLabel = function(p)
	if IsValid(p.Label) then p.Label:SetTextColor(C.text) end
	if IsValid(p.Button) then
		p.Button.Paint = function(self, w, h)
			paintBox(w, h, C.box, C.accent)
			if self:GetChecked() then draw.RoundedBox(2, 3, 3, w - 6, h - 6, C.accent) end
		end
	end
end
STYLE.DNumSlider = function(p)
	p.Label:SetTextColor(C.text)
	styleEntry(p.TextArea)
	p.Slider.Paint = function(self, w, h)
		draw.RoundedBox(2, 7, h / 2 - 2, w - 14, 4, C.box)
		draw.RoundedBox(2, 7, h / 2 - 2, (w - 14) * math.Clamp(self:GetSlideX(), 0, 1), 4, C.accent)
	end
	if IsValid(p.Slider.Knob) then
		p.Slider.Knob.Paint = function(self, w, h) paintBox(w, h, self:IsHovered() and C.btnHover or C.btn, C.accent) end
	end
end
STYLE.DProgress = function(p)
	p.Paint = function(self, w, h)
		paintBox(w, h, C.box)
		local f = math.Clamp(self:GetFraction(), 0, 1)
		if f > 0 then draw.RoundedBox(4, 0, 0, math.max(w * f, 8), h, C.accent) end
	end
end
STYLE.DListView = function(p)
	p.Paint = function(_, w, h) paintBox(w, h, C.box, C.btn) end
	styleBar(p.VBar)
	local addCol, addLine = p.AddColumn, p.AddLine
	p.AddColumn = function(self, ...)
		local col = addCol(self, ...)
		if IsValid(col) and IsValid(col.Header) then
			col.Header.Paint = function(b, w, h)
				draw.RoundedBox(0, 0, 0, w, h, b:IsHovered() and C.btnHover or C.btn)
				b:SetTextColor(b:IsHovered() and C.btnHoverText or C.btnText)
			end
		end
		return col
	end
	p.AddLine = function(self, ...)
		local line = addLine(self, ...)
		if IsValid(line) then
			line.Paint = function(l, w, h)
				local sel, hov = l.m_bSelected, l:IsHovered()
				if sel then draw.RoundedBox(0, 0, 0, w, h, C.accent)
				elseif hov then draw.RoundedBox(0, 0, 0, w, h, C.btnHover)
				elseif l.m_bAlt then draw.RoundedBox(0, 0, 0, w, h, C.alt) end
				local tc = sel and C.accentText or (hov and C.btnHoverText or C.boxText)
				for _, c in pairs(l.Columns or {}) do if IsValid(c) and c.SetTextColor then c:SetTextColor(tc) end end
			end
		end
		return line
	end
end

-- vgui.Create + the theme look
-- (button texts cut off, a bigger window did not help): a button given a width is never narrower than its text (in
-- every language), also when its text changes later
local function fitButton(b)
	local setW, setT = b.SetWide, b.SetText
	local function fit(self)
		local want = self.StarCoreWantWide
		if not want then return end
		surface.SetFont(self:GetFont() or "DermaDefault")
		local w = math.max(want, (surface.GetTextSize(self:GetText() or "")) + 14)
		if self:GetWide() ~= w then setW(self, w) end
	end
	b.SetWide = function(self, w) self.StarCoreWantWide = w fit(self) end
	b.SetText = function(self, t) setT(self, t) fit(self) end
end

local function create(class, parent)
	local p = vgui.Create(class, parent)
	if STYLE[class] then STYLE[class](p) end
	if class == "DButton" then fitButton(p) end
	return p
end
-- (the core design list of the StarCore tool showed white text on a white field - the menu skin of the player decides
-- the tool page's colours): the list paints itself in StarCore's colours, field and drop-down
function StarCore.StyleCombo(p)
	if not IsValid(p) or p.StarCoreStyled then return end
	p.StarCoreStyled = true
	STYLE.DComboBox(p)
end

net.Receive("starcore_notify", function()
	local key, kind = net.ReadString(), net.ReadUInt(3)
	local args = {}
	for i = 1, net.ReadUInt(4) do args[i] = net.ReadString() end
	notification.AddLegacy(T(key, unpack(args)), kind, kind == NOTIFY_ERROR and 4 or 6)
	surface.PlaySound(kind == NOTIFY_ERROR and "buttons/button10.wav" or "buttons/button15.wav")
end)

local function send(cmd, data)
	if not IsValid(current) then return end
	net.Start("starcore_cmd")
	net.WriteEntity(current)
	net.WriteString(cmd)
	net.WriteTable(data or {})
	net.SendToServer()
end

local function ftlText(core)
	local st = core:GetNWInt("starcore_ftl")
	local t1 = core:GetNWFloat("starcore_ftl_t1")
	if st == FTL.CHARGING then return T("ftl_charging"), 1 - math.max(t1 - CurTime(), 0) / math.max(t1 - core:GetNWFloat("starcore_ftl_t0"), 0.01)
	elseif st == FTL.JUMPING then return T("ftl_jumping"), 1
	elseif st == FTL.COOLDOWN then return T("ftl_cooldown", math.ceil(math.max(t1 - CurTime(), 0))), 0 end
	return T("ftl_ready"), 0
end
StarCore.FTLText = ftlText

local function label(parent, text, font)
	local l = create("DLabel", parent)
	l:Dock(TOP)
	l:DockMargin(4, 4, 4, 0)
	l:SetFont(font or "DermaDefault")
	l:SetText(text)
	-- (texts cut off): a text longer than the window is wide goes onto the next line; the labels that change their text
	-- (their own Think) keep their height right through SizeToContents
	l:SetWrap(true)
	l:SetAutoStretchVertical(true)
	l.SizeToContents = function(self) self:SizeToContentsY() end
	l:SizeToContents()
	return l
end

-- unit: nil (plain number), "dist", "speed" or "accel": shown in the player's own unit, sent in game units
local function slider(parent, key, min, max, dec, unit)
	local s = create("DNumSlider", parent)
	s:Dock(TOP)
	s:DockMargin(4, 2, 4, 0)
	local per = unit and U.Per() or 1
	local text = T("set_" .. key)
	if unit == "dist" then text = text .. " (" .. U.Name() .. ")"
	elseif unit == "speed" then text = text .. " (" .. U.Name() .. "/s)"
	elseif unit == "accel" then text = text .. " (" .. U.Name() .. "/s²)" end
	s:SetText(text)
	s:SetTooltip(text)
	-- (texts cut off): the text gets up to 62 % of the row, and a longer one goes onto two lines
	local layout = s.PerformLayout
	s.PerformLayout = function(self, w, h)
		if layout then layout(self, w, h) end
		if w < 200 then return end
		surface.SetFont(self.Label:GetFont() or "DermaDefault")
		local need = (surface.GetTextSize(self.Label:GetText() or "")) + 8
		local lw = math.max(self.Label:GetWide(), math.min(need, math.floor(w * 0.62)))
		self.Label:SetWide(lw)
		self.Label:SetWrap(need > lw)
		self.Label.StarCoreWrapped = need > lw
	end
	s:SetMinMax(min / per, max / per)
	s:SetDecimals(dec or ((max - min) / per < 60 and 1 or 0))
	s:SetValue((state.settings[key] or StarCore.Defaults[key]) / per)
	s.OnValueChanged = function(_, v)
		if applying then return end -- AGP: set from a reply, not by the player
		timer.Create("StarCore.Slider." .. key, 0.4, 1, function() send("settings", { values = { [key] = v * per } }) end)
	end
	-- AGP: follow the server's value (clamped, changed by others), not while dragged or still to be sent
	onReply("set." .. key, s, function(st)
		local v = st.settings and st.settings[key]
		if not isnumber(v) or s:IsEditing() or timer.Exists("StarCore.Slider." .. key) then return end
		s:SetValue(v / per)
	end)
	return s
end

-- AGP: a label whose text follows the ship (the window is no longer rebuilt on every reply)
local function liveLabel(parent, fn)
	local l = label(parent, fn())
	-- (Parts, Seats, Size: this Think replaced the label's own, which fits its height to the text once the window is
	-- wide - the height from the first, narrow measure stayed)
	local own = l.Think
	l.Think = function(self)
		if own then own(self) end
		local t = IsValid(current) and fn()
		if t and t ~= self:GetText() then
			self:SetText(t)
			self:SizeToContents()
		end
	end
	return l
end

local function button(parent, text, fn)
	local b = create("DButton", parent)
	b:Dock(TOP)
	b:DockMargin(4, 4, 4, 0)
	b:SetTall(26)
	b:SetText(text)
	b.DoClick = fn
	return b
end

local function buildHelm(sheet)
	local p = create("DScrollPanel", sheet)
	local status = label(p, "", "DermaDefaultBold")
	status.Think = function(self)
		if not IsValid(current) then return end
		local on = current:GetNWBool("starcore_hover")
		local txt = on and T("hover_on") or T("hover_off")
		if current:GetNWBool("starcore_frozen") then txt = txt .. " · " .. T("frozen") end
		if current:GetNWBool("starcore_toobig") then txt = T("too_big") end
		if current:GetNWBool("starcore_sleeping") then txt = T("second_core") end
		if IsValid(current:GetNWEntity("starcore_docked")) then txt = T("hud_docked", current:GetNWString("starcore_docked_name", "?")) end
		self:SetText(txt)
		self:SizeToContents()
	end
	button(p, T("btn_hover"), function() send("hover", { on = not current:GetNWBool("starcore_hover") }) end)
	-- (carriers): dock into the bigger ship this one sits in / let go; a carrier lets all go
	local dk = button(p, T("btn_dock"), function() send("dock", {}) end)
	local carried = liveLabel(p, function() return T("dock_carrying", current:GetNWInt("starcore_docked_ships")) end)
	local rel = button(p, T("btn_undock_all"), function() send("undock_all", {}) end)
	carried:SetVisible(false)
	rel:SetVisible(false)
	-- (hidden panels do not think: the always shown dock button shows / hides the carrier line)
	dk.Think = function(self)
		if not IsValid(current) then return end
		local t = IsValid(current:GetNWEntity("starcore_docked")) and T("btn_undock") or T("btn_dock")
		if self:GetText() ~= t then self:SetText(t) end
		local show = current:GetNWInt("starcore_docked_ships") > 0
		if rel:IsVisible() ~= show then rel:SetVisible(show); carried:SetVisible(show); rel:GetParent():InvalidateLayout() end
	end
	button(p, T("btn_freeze"), function() send("freeze", { on = not current:GetNWBool("starcore_frozen") }) end)
	-- stand facing the ship's nose
	button(p, T("btn_front"), function() send("front", {}) end)
	button(p, T("btn_front_clear"), function() send("front", { clear = true }) end)
	-- first / third person in this seat (in the pilot seat Ctrl flies down and no longer switches the view)
	button(p, T("btn_view"), function() send("view", {}) end)
	label(p, T("keys_help"))
	slider(p, "speed", 50, GetConVar("starcore_max_speed"):GetFloat(), nil, "speed")
	slider(p, "boost", 1, 4, 1)
	slider(p, "climb", 20, 2000, nil, "speed")
	slider(p, "turn", 5, 120)
	slider(p, "accel", 50, 5000, nil, "accel")
	slider(p, "idleFreeze", 0, 600)
	local pub = create("DCheckBoxLabel", p)
	pub:Dock(TOP)
	pub:DockMargin(4, 6, 4, 0)
	pub:SetText(T("set_public"))
	pub:SetValue(state.settings.public and 1 or 0)
	pub.OnChange = function(_, v) send("settings", { values = { public = v } }) end
	liveCheck(pub, "set.public", function(st) return st.settings and st.settings.public == true end) -- AGP
	return p
end

local function buildJump(sheet)
	local p = create("DPanel", sheet)
	p.Paint = nil
	local status = label(p, "", "DermaDefaultBold")
	local bar = create("DProgress", p)
	bar:Dock(TOP)
	bar:DockMargin(4, 2, 4, 4)
	bar:SetTall(10)
	status.Think = function(self)
		if not IsValid(current) then return end
		local txt, frac = ftlText(current)
		self:SetText(txt)
		self:SizeToContents()
		bar:SetFraction(frac)
	end

	local list = create("DListView", p)
	list:Dock(TOP)
	list:DockMargin(4, 0, 4, 0)
	list:SetTall(150)
	list:SetMultiSelect(false)
	list:AddColumn("#"):SetFixedWidth(24)
	list:AddColumn(T("mark_name"))
	list:AddColumn(T("mark_dist")):SetFixedWidth(80)
	for i, m in ipairs(state.marks or {}) do
		local d = IsValid(current) and current:GetPos():Distance(m.pos)
		local line = list:AddLine(i, m.name, d and U.Dist(d) or "?")
		if d then line:SetSortValue(3, d) end
		line.index = i
	end
	-- AGP: distances follow the ship on every reply (the list itself is rebuilt only when the marks change)
	onReply("jump.dist", list, function(st)
		if not IsValid(current) then return end
		for _, line in pairs(list:GetLines()) do
			local m = st.marks and st.marks[line.index]
			if m and isvector(m.pos) then
				local d = current:GetPos():Distance(m.pos)
				line:SetColumnText(3, U.Dist(d))
				line:SetSortValue(3, d)
			end
		end
	end)
	local function selected()
		local _, line = list:GetSelectedLine()
		return line and line.index
	end
	list.DoDoubleClick = function(_, _, line) send("jump", { kind = "mark", index = line.index }) end

	local row = create("DPanel", p)
	row:Dock(TOP)
	row:DockMargin(4, 4, 4, 0)
	row:SetTall(24)
	row.Paint = nil
	local name = create("DTextEntry", row)
	name:Dock(FILL)
	name:SetPlaceholderText(T("mark_name_hint"))
	local save = create("DButton", row)
	save:Dock(RIGHT)
	save:SetWide(150)
	save:SetText(T("btn_save_mark"))
	save.DoClick = function()
		local idx = selected() or (#(state.marks or {}) + 1)
		if idx > StarCore.MaxMarks then notification.AddLegacy(T("marks_full"), NOTIFY_ERROR, 4) return end
		send("mark_save", { index = idx, name = name:GetValue() })
	end

	local btns = create("DPanel", p)
	btns:Dock(TOP)
	btns:DockMargin(4, 4, 4, 0)
	btns:SetTall(26)
	btns.Paint = nil
	local function small(text, fn)
		local b = create("DButton", btns)
		b:Dock(LEFT)
		b:DockMargin(0, 0, 4, 0)
		b:SetWide(126)
		b:SetText(text)
		b.DoClick = fn
	end
	small(T("btn_jump_mark"), function() local i = selected() if i then send("jump", { kind = "mark", index = i }) end end)
	small(T("btn_rename"), function() local i = selected() if i then send("mark_rename", { index = i, name = name:GetValue() }) end end)
	small(T("btn_delete"), function() local i = selected() if i then send("mark_delete", { index = i }) end end)
	small(T("btn_fly_mark"), function() local i = selected() if i then send("autopilot", { kind = "mark", index = i }) end end)

	label(p, T("coords"), "DermaDefaultBold")
	local co = create("DPanel", p)
	co:Dock(TOP)
	co:DockMargin(4, 2, 4, 0)
	co:SetTall(24)
	co.Paint = nil
	local cur = IsValid(current) and current:GetPos() or Vector()
	local fields = {}
	for i, axis in ipairs({ "x", "y", "z" }) do
		local e = create("DTextEntry", co)
		e:Dock(LEFT)
		e:DockMargin(0, 0, 4, 0)
		e:SetWide(110)
		e:SetNumeric(true)
		e:SetValue(tostring(math.floor(cur[axis])))
		fields[i] = e
	end
	local go = create("DButton", co)
	go:Dock(FILL)
	go:SetText(T("btn_jump_coords"))
	go.DoClick = function()
		local v = Vector(tonumber(fields[1]:GetValue()) or 0, tonumber(fields[2]:GetValue()) or 0, tonumber(fields[3]:GetValue()) or 0)
		send("jump", { kind = "coord", pos = v })
	end

	local flyCoords = create("DButton", p)
	flyCoords:Dock(TOP)
	flyCoords:DockMargin(4, 4, 4, 0)
	flyCoords:SetTall(26)
	flyCoords:SetText(T("btn_fly_coords"))
	flyCoords.DoClick = function()
		local v = Vector(tonumber(fields[1]:GetValue()) or 0, tonumber(fields[2]:GetValue()) or 0, tonumber(fields[3]:GetValue()) or 0)
		send("autopilot", { kind = "coord", pos = v })
	end
	button(p, T("btn_jump_owner"), function() send("jump", { kind = "owner" }) end)
	button(p, T("btn_autopilot_stop"), function() send("autopilot", { stop = true }) end)
	button(p, T("btn_cancel"), function() send("cancel") end)
	return p
end

local function buildGates(sheet)
	local sg = state.sg
	local p = create("DPanel", sheet)
	p.Paint = nil
	if sg.hasGate then
		label(p, T("sg_ship_gate", sg.name ~= "" and sg.name or sg.class, sg.address, sg.group), "DermaDefaultBold")
	else
		label(p, T("sg_no_ship_gate"), "DermaDefaultBold")
	end
	local status = label(p, "")
	status.Think = function(self)
		if not IsValid(current) or not sg.hasGate then return end
		local g = T("sg_state_idle")
		if current:GetNWBool("starcore_gate_open") then
			g = current:GetNWBool("starcore_gate_inbound") and T("sg_state_open_in") or T("sg_state_open_out")
		elseif current:GetNWBool("starcore_gate_busy") then g = T("sg_state_busy") end
		local i = T("sg_iris_none")
		if IsValid(current:GetNWEntity("starcore_iris")) then
			i = current:GetNWBool("starcore_iris_closed") and T("sg_iris_closed") or T("sg_iris_open")
			if current:GetNWBool("starcore_iris_wired") then i = i .. " (" .. T("sg_iris_wired") .. ")" end
		end
		self:SetText(g .. "   ·   " .. i)
		self:SizeToContents()
	end

	local list = create("DListView", p)
	list:Dock(TOP)
	list:DockMargin(4, 4, 4, 0)
	list:SetTall(200)
	list:SetMultiSelect(false)
	list:AddColumn(T("col_gate"))
	list:AddColumn(T("col_address")):SetFixedWidth(110)
	list:AddColumn(T("mark_dist")):SetFixedWidth(70)
	local lines = {}
	for _, g in ipairs(sg.list or {}) do
		local addr = g.dial or g.address
		if sg.hasGate and not g.dial then addr = addr .. " ✕" end
		local line = list:AddLine(g.name, addr, U.Dist(g.dist))
		line:SetSortValue(3, tonumber(g.dist) or 0)
		line.gate = g
		lines[g.id] = line
	end
	-- AGP: distances follow the ship on every reply; the list is rebuilt only when the gates change
	onReply("gates.dist", list, function(st)
		for _, g in ipairs(st.sg and st.sg.list or {}) do
			local line = lines[g.id]
			if IsValid(line) then
				line:SetColumnText(3, U.Dist(g.dist))
				line:SetSortValue(3, tonumber(g.dist) or 0)
				line.gate = g
			end
		end
	end)
	local function sel()
		local _, line = list:GetSelectedLine()
		return line and line.gate
	end

	local row = create("DPanel", p)
	row:Dock(TOP)
	row:DockMargin(4, 4, 4, 0)
	row:SetTall(26)
	row.Paint = nil
	local mode = create("DComboBox", row)
	mode:Dock(LEFT)
	mode:SetWide(120)
	mode:AddChoice(T("mode_fast"), "fast", true)
	mode:AddChoice(T("mode_slow"), "slow")
	mode:AddChoice(T("mode_nox"), "nox")
	local function rowButton(text, fn, wide)
		local b = create("DButton", row)
		b:Dock(LEFT)
		b:DockMargin(4, 0, 0, 0)
		b:SetWide(wide or 120)
		b:SetText(text)
		b.DoClick = fn
		b:SetEnabled(sg.hasGate)
		return b
	end
	rowButton(T("btn_dial"), function()
		local g = sel()
		if not g then return end
		if not g.dial then notification.AddLegacy(T("sg_not_dialable"), NOTIFY_ERROR, 4) return end
		local _, m = mode:GetSelected()
		send("sg_dial", { address = g.dial, mode = m or "fast" })
	end)
	rowButton(T("btn_close_gate"), function() send("sg_close") end)
	rowButton(T("btn_iris"), function() send("sg_iris") end, 110)

	local auto = create("DCheckBoxLabel", p)
	auto:Dock(TOP)
	auto:DockMargin(4, 6, 4, 0)
	auto:SetText(T("set_iris_auto"))
	auto:SetValue(sg.irisAuto and 1 or 0)
	auto.OnChange = function(_, v) send("sg_irisauto", { on = v }) end
	liveCheck(auto, "sg.irisAuto", function(st) return st.sg and st.sg.irisAuto end) -- AGP

	button(p, T("btn_jump_gate"), function()
		local g = sel()
		if g then send("jump", { kind = "gate", id = g.id }) end
	end)
	button(p, T("btn_fly_gate"), function()
		local g = sel()
		if g then send("autopilot", { kind = "gate", id = g.id }) end
	end)
	return p
end

-- radar: contacts arrive twice a second while the menu is open or you fly the ship
StarCore.Radar = StarCore.Radar or {}
local IFFCOL = { Color(80, 160, 255), Color(80, 220, 255), Color(90, 220, 120), Color(200, 200, 200), Color(255, 70, 60) }
local IFFKEY = { "iff_own", "iff_crew", "iff_friend", "iff_neutral", "iff_hostile" }
local KINDKEY = { "kind_player", "kind_npc", "kind_ship", "kind_gate" }
StarCore.IFFCOL, StarCore.IFFKEY = IFFCOL, IFFKEY

net.Receive("starcore_contacts", function()
	local core = net.ReadEntity()
	local yaw = net.ReadFloat()
	local list = {}
	for i = 1, net.ReadUInt(7) do
		list[i] = { ent = net.ReadEntity(), kind = net.ReadUInt(3), iff = net.ReadUInt(3), dist = net.ReadFloat(), canFire = net.ReadBool() }
	end
	if IsValid(core) then StarCore.Radar[core] = { yaw = yaw, list = list, time = CurTime() } end
	hook.Run("StarCore.ContactsUpdated", core)
end)

-- (ship names and classes): "Kestrel SC-1042 · Fighter" (empty when the ship has neither name nor number);
-- withClass = false leaves the class out
function StarCore.ShipTitle(core, withClass)
	if not IsValid(core) then return "" end
	local name, no = core:GetNWString("starcore_name", ""), core:GetNWString("starcore_regno", "")
	local n = utf8.len(name)
	if n and n > StarCore.NameShow then   -- (long names end in "…" here; the Ship tab shows the whole name)
		local out, k = {}, 0
		for _, c in utf8.codes(name) do
			k = k + 1
			if k > StarCore.NameShow - 1 then break end
			out[k] = utf8.char(c)
		end
		name = table.concat(out) .. "…"
	end
	local s = name
	if no ~= "" then s = s ~= "" and (s .. " " .. no) or no end
	local cls = core:GetNWString("starcore_class", "")
	if s ~= "" and cls ~= "" and withClass ~= false then s = s .. " · " .. T("class_" .. cls) end
	return s
end

function StarCore.ContactName(c)
	local e = c.ent
	if not IsValid(e) then return "?" end
	if e:IsPlayer() then return e:Nick() end
	if c.kind == 3 then
		local o = e:GetNWEntity("starcore_owner")
		local who = IsValid(o) and o:Nick() or "?"
		local title = StarCore.ShipTitle(e)
		if title == "" then return T("ship_of", who) end
		return title .. " (" .. who .. ")"
	end
	if c.kind == 4 then
		local n = e.GetGateName and e:GetGateName() or ""
		return n ~= "" and n or e:GetClass()
	end
	return language.GetPhrase(e:GetClass())
end

local function buildRadar(sheet)
	local p = create("DPanel", sheet)
	p.Paint = nil
	local top = create("DPanel", p)
	top:Dock(TOP)
	top:SetTall(230)
	top.Paint = nil
	local scope = create("DPanel", top)
	scope:Dock(LEFT)
	scope:SetWide(230)
	scope.Paint = function(self, w, h)
		local cx, cy, r = w / 2, h / 2, math.min(w, h) / 2 - 4
		draw.RoundedBox(8, 0, 0, w, h, Color(5, 15, 25, 240))
		for k = 1, 3 do surface.DrawCircle(cx, cy, r * k / 3, 40, 90, 120, 255) end
		surface.SetDrawColor(40, 90, 120, 255)
		surface.DrawLine(cx - r, cy, cx + r, cy)
		surface.DrawLine(cx, cy - r, cx, cy + r)
		-- the ship in the middle, nose up
		surface.SetDrawColor(140, 220, 255, 255)
		surface.DrawLine(cx, cy - 6, cx - 4, cy + 4)
		surface.DrawLine(cx, cy - 6, cx + 4, cy + 4)
		local data = IsValid(current) and StarCore.Radar[current]
		if not data then return end
		-- AGP: capped by the server limit like the sensors themselves (sv_combat SensorScan)
		local range = math.max(math.min(state.settings.radarRange or 15000, GetConVar("starcore_radar_range"):GetFloat()), 1)
		local center = current:GetPos()
		local target = current:GetNWEntity("starcore_target")
		local a = math.rad(-data.yaw)
		for _, c in ipairs(data.list) do
			if IsValid(c.ent) then
				local d = c.ent:GetPos() - center
				-- rotate into ship space: forward (x) = up on the screen, left (y) = left
				local fx = d.x * math.cos(a) - d.y * math.sin(a)
				local fy = d.x * math.sin(a) + d.y * math.cos(a)
				local px, py = cx - fy / range * r, cy - fx / range * r
				local col = IFFCOL[c.iff] or color_white
				local s = c.ent == target and 8 or 5
				draw.RoundedBox(s / 2, px - s / 2, py - s / 2, s, s, col)
				if c.ent == target then surface.SetDrawColor(255, 255, 0); surface.DrawOutlinedRect(px - 7, py - 7, 14, 14) end
			end
		end
	end
	local list = create("DListView", top)
	list:Dock(FILL)
	list:DockMargin(6, 0, 0, 0)
	list:SetMultiSelect(false)
	list:AddColumn(T("col_contact"))
	-- each column at least as wide as its longest word in the player's language
	local function colWide(min, ...)
		surface.SetFont("DermaDefault")
		local w = min
		for _, t in ipairs({ ... }) do w = math.max(w, (surface.GetTextSize(t)) + 12) end
		return w
	end
	list:AddColumn(T("col_kind")):SetFixedWidth(colWide(60, T("col_kind"), T("kind_player"), T("kind_npc"), T("kind_ship"), T("kind_gate")))
	list:AddColumn(T("col_iff")):SetFixedWidth(colWide(64, T("col_iff"), T("iff_friend"), T("iff_hostile"), T("iff_neutral"), T("iff_own"), T("iff_crew")))
	list:AddColumn(T("mark_dist")):SetFixedWidth(colWide(56, T("mark_dist"), "99999 m"))
	local filling = false
	local function fill()
		if not IsValid(list) then return end
		local data = IsValid(current) and StarCore.Radar[current]
		local target = IsValid(current) and current:GetNWEntity("starcore_target")
		filling = true
		list:Clear()
		for _, c in ipairs(data and data.list or {}) do
			local line = list:AddLine(StarCore.ContactName(c), T(KINDKEY[c.kind] or "kind_npc"), T(IFFKEY[c.iff] or "iff_neutral"), U.Dist(c.dist))
			line:SetSortValue(4, c.dist)
			line.contact = c
			if c.ent == target then line:SetSelected(true) end
		end
		filling = false
	end
	fill()
	hook.Add("StarCore.ContactsUpdated", list, function(_, core) if core == current then fill() end end)
	list.OnRowSelected = function(_, _, line)
		if not filling and line.contact and IsValid(line.contact.ent) then send("target", { id = line.contact.ent:EntIndex() }) end
	end

	local row = create("DPanel", p)
	row:Dock(TOP)
	row:DockMargin(4, 6, 4, 0)
	row:SetTall(26)
	row.Paint = nil
	local function rb(text, fn, wide)
		local b = create("DButton", row)
		b:Dock(LEFT)
		b:DockMargin(0, 0, 4, 0)
		b:SetWide(wide or 84)
		b:SetText(text)
		b.DoClick = fn
		return b
	end
	local function selId() local t = IsValid(current) and current:GetNWEntity("starcore_target") return IsValid(t) and t:EntIndex() or nil end
	rb(T("btn_prev"), function() send("target", { step = -1 }) end, 60)
	rb(T("btn_next"), function() send("target", { step = 1 }) end, 60)
	local eng = rb(T("btn_engage"), function() send("engage", { on = not (IsValid(current) and current:GetNWBool("starcore_engaging")) }) end, 110)
	eng.Think = function(self) self:SetText(IsValid(current) and current:GetNWBool("starcore_engaging") and T("btn_ceasefire") or T("btn_engage")) end
	rb(T("btn_hostile"), function() local id = selId() if id then send("hostile", { id = id, on = true }) end end, 90)
	rb(T("btn_clear"), function() local id = selId() if id then send("hostile", { id = id, on = false }) end end, 70)

	local row2 = create("DPanel", p)
	row2:Dock(TOP)
	row2:DockMargin(4, 4, 4, 0)
	row2:SetTall(26)
	row2.Paint = nil
	local lock = create("DCheckBoxLabel", row2)
	lock:Dock(LEFT)
	lock:SetWide(130)
	lock:SetText(T("set_lock"))
	lock:SetValue(IsValid(current) and current:GetNWBool("starcore_lock") and 1 or 0)
	lock.OnChange = function(_, v) send("lock", { on = v }) end
	liveCheck(lock, "lock", function() return IsValid(current) and current:GetNWBool("starcore_lock") end) -- AGP
	local function beamButton(text, cmd)
		local b = create("DButton", row2)
		b:Dock(RIGHT)
		b:DockMargin(4, 0, 0, 0)
		b:SetWide(110)
		b:SetText(text)
		b.DoClick = function() send(cmd, { id = selId() or 0 }) end
		b:SetEnabled(IsValid(current) and IsValid(current:GetNWEntity("starcore_transporter")))
		-- AGP: follows a transporter added or removed while the window is open (no rebuild any more)
		b.Think = function(self) self:SetEnabled(IsValid(current) and IsValid(current:GetNWEntity("starcore_transporter"))) end
	end
	beamButton(T("btn_beam_down"), "beam_down")
	beamButton(T("btn_beam_aboard"), "beam_aboard")
	button(p, T("btn_jump_target"), function() local id = selId() if id then send("jump", { kind = "contact", id = id }) end end)

	button(p, T("btn_follow_target"), function() local id = selId() if id then send("autopilot", { kind = "contact", id = id, follow = true }) end end)
	local auto = create("DCheckBoxLabel", p)
	auto:Dock(TOP)
	auto:DockMargin(4, 8, 4, 0)
	auto:SetText(T("set_autoDefence"))
	auto:SetValue(state.settings.autoDefence and 1 or 0)
	auto.OnChange = function(_, v) send("settings", { values = { autoDefence = v } }) end
	liveCheck(auto, "set.autoDefence", function(st) return st.settings and st.settings.autoDefence == true end) -- AGP
	slider(p, "radarRange", 1000, GetConVar("starcore_radar_range"):GetFloat(), nil, "dist")
	liveLabel(p, function() return T("weapons_info", IsValid(current) and current:GetNWInt("starcore_weapons") or 0) end) -- AGP
	return p
end

local function fmtNum(n)
	n = tonumber(n) or 0
	if math.abs(n) >= 1e9 then return string.format("%.1fG", n / 1e9) end
	if math.abs(n) >= 1e6 then return string.format("%.1fM", n / 1e6) end
	if math.abs(n) >= 1e3 then return string.format("%.1fk", n / 1e3) end
	return tostring(math.floor(n))
end
StarCore.FmtNum = fmtNum

local function buildPower(sheet)
	local pw = state.power or { sources = {}, shields = 0 }
	local p = create("DScrollPanel", sheet)
	label(p, T("power_title"), "DermaDefaultBold")
	local bar = create("DProgress", p)
	bar:Dock(TOP)
	bar:DockMargin(4, 2, 4, 0)
	bar:SetTall(14)
	local info = label(p, "")
	info.Think = function(self)
		if not IsValid(current) then return end
		local pct = current:GetNWFloat("starcore_power_pct", -1)
		if pct < 0 then
			self:SetText(T("power_none"))
			bar:SetFraction(0)
		else
			bar:SetFraction(pct / 100)
			local left = current:GetNWFloat("starcore_power_left", -1)
			local leftTxt = left < 0 and T("power_stable") or T("power_left", string.NiceTime(left))
			self:SetText(T("power_info", math.floor(pct), fmtNum(current:GetNWFloat("starcore_power_total")), fmtNum(current:GetNWFloat("starcore_power_rate")), leftTxt))
		end
		self:SizeToContents()
	end
	local srcLabels, netLabel = {}, nil
	for i, src in ipairs(pw.sources or {}) do
		srcLabels[i] = label(p, "  • " .. language.GetPhrase(src.class) .. ": " .. src.pct .. " %")
	end
	if (pw.netCap or 0) > 0 then netLabel = label(p, T("power_network", fmtNum(pw.net), fmtNum(pw.netCap))) end
	-- AGP: the numbers follow every reply; the tab is rebuilt only when the sources or shields change
	onReply("power.nums", p, function(st)
		local np = st.power or {}
		for i, src in ipairs(np.sources or {}) do
			if IsValid(srcLabels[i]) then
				srcLabels[i]:SetText("  • " .. language.GetPhrase(src.class) .. ": " .. src.pct .. " %")
				srcLabels[i]:SizeToContents()
			end
		end
		if IsValid(netLabel) and (np.netCap or 0) > 0 then
			netLabel:SetText(T("power_network", fmtNum(np.net), fmtNum(np.netCap)))
			netLabel:SizeToContents()
		end
	end)

	label(p, " ")
	label(p, T("shield_title"), "DermaDefaultBold")
	if (pw.shields or 0) == 0 then
		label(p, T("shield_none"))
		return p
	end
	local st = label(p, "")
	st.Think = function(self)
		if not IsValid(current) then return end
		local txt
		if current:GetNWBool("starcore_shield_depleted") then txt = T("shield_depleted")
		elseif current:GetNWBool("starcore_shield_up") then txt = T("shield_up", math.floor(current:GetNWFloat("starcore_shield_strength")))
		else txt = T("shield_down") end
		if pw.shieldWired then txt = txt .. " (" .. T("sg_iris_wired") .. ")" end
		self:SetText(txt)
		self:SizeToContents()
	end
	button(p, T("btn_shield"), function() send("shield", { on = not current:GetNWBool("starcore_shield_up") }) end)
	local auto = create("DCheckBoxLabel", p)
	auto:Dock(TOP)
	auto:DockMargin(4, 6, 4, 0)
	auto:SetText(T("set_shieldAuto"))
	auto:SetValue(state.settings.shieldAuto and 1 or 0)
	auto.OnChange = function(_, v) send("settings", { values = { shieldAuto = v } }) end
	liveCheck(auto, "set.shieldAuto", function(rs) return rs.settings and rs.settings.shieldAuto == true end) -- AGP
	slider(p, "shieldSize", 0, pw.shieldMax or 2048, nil, "dist")
	slider(p, "shieldStrength", -5, 5)
	slider(p, "shieldFreq", -1, 1500)
	label(p, T("shield_color"))
	local mixer = create("DColorMixer", p)
	mixer:Dock(TOP)
	mixer:DockMargin(4, 2, 4, 0)
	mixer:SetTall(110)
	mixer:SetPalette(true)
	mixer:SetAlphaBar(false)
	mixer:SetWangs(false)
	local c = state.settings.shieldColor
	if istable(c) then mixer:SetColor(Color((c[1] or 1) * 255, (c[2] or 1) * 255, (c[3] or 1) * 255)) end
	mixer.ValueChanged = function(_, col)
		if applying then return end -- AGP: set from a reply, not by the player
		timer.Create("StarCore.ShieldColor", 0.5, 1, function() send("settings", { values = { shieldColor = { col.r / 255, col.g / 255, col.b / 255 } } }) end)
	end
	-- AGP: follow the server's colour, never while the player drags it or a change is still to be sent
	onReply("set.shieldColor", mixer, function(rs)
		local sc = rs.settings and rs.settings.shieldColor
		if not istable(sc) or input.IsMouseDown(MOUSE_LEFT) or timer.Exists("StarCore.ShieldColor") then return end
		local want, have = Color((sc[1] or 1) * 255, (sc[2] or 1) * 255, (sc[3] or 1) * 255), mixer:GetColor()
		if math.abs(have.r - want.r) + math.abs(have.g - want.g) + math.abs(have.b - want.b) > 3 then mixer:SetColor(want) end
	end)
	return p
end

local function buildShip(sheet)
	local p = create("DScrollPanel", sheet)
	-- name (with a dice for a random one), hull number, class
	label(p, T("identity_title"), "DermaDefaultBold")
	local function textField(key, max, labelKey, extra)
		label(p, T(labelKey))
		local row = create("DPanel", p)
		row:Dock(TOP)
		row:DockMargin(4, 2, 4, 0)
		row:SetTall(24)
		row.Paint = nil
		local e = create("DTextEntry", row)
		e:Dock(FILL)
		e:SetValue(state.settings[key] or "")
		local function commit()
			local v = e:GetValue()
			if v ~= (state.settings[key] or "") then send("identity", { [key] = v }) end
		end
		e.OnEnter = commit
		local baseLose = e.OnLoseFocus
		e.OnLoseFocus = function(self) commit() if baseLose then baseLose(self) end end
		-- true = this letter is NOT taken (the field is full)
		e.AllowInput = function(self) local n = utf8.len(self:GetValue() or "") return n ~= nil and n >= max end
		onReply("identity." .. key, e, function(st)
			if e:HasFocus() then return end
			local v = st.settings and st.settings[key]
			if isstring(v) and v ~= e:GetValue() then e:SetValue(v) end
		end)
		if extra then extra(row) end
		return e
	end
	textField("name", StarCore.NameMax, "ship_name", function(row)
		local dice = create("DButton", row)
		dice:Dock(RIGHT)
		dice:DockMargin(4, 0, 0, 0)
		dice:SetWide(120)
		dice:SetText(T("btn_name_random"))
		dice.DoClick = function() send("identity", { random = true }) end
	end)
	textField("regno", StarCore.RegNoMax, "ship_regno")
	label(p, T("ship_class"))
	local cls = create("DComboBox", p)
	cls:Dock(TOP)
	cls:DockMargin(4, 2, 4, 0)
	local curCls = state.settings.class or "auto"
	local autoNow = IsValid(current) and current:GetNWString("starcore_class", "") or ""
	cls:AddChoice(T("class_auto", autoNow ~= "" and curCls == "auto" and T("class_" .. autoNow) or "..."), "auto", curCls == "auto")
	for _, c in ipairs(StarCore.ShipClasses) do cls:AddChoice(T("class_" .. c), c, curCls == c) end
	cls.OnSelect = function(_, _, _, v) if not applying and v ~= curCls then curCls = v send("identity", { class = v }) end end
	onReply("identity.class", cls, function(st)
		local v = st.settings and st.settings.class
		if not isstring(v) or v == curCls then return end
		curCls = v
		if v == "auto" then cls:ChooseOptionID(1) return end
		for i, c in ipairs(StarCore.ShipClasses) do if c == v then cls:ChooseOptionID(i + 1) end end
	end)
	local ch = label(p, T("class_hint"))
	ch:SetWrap(true)
	ch:SetAutoStretchVertical(true)
	label(p, " ")
	-- core design: changes the model of this core live (server checks owner/friends, ship landed)
	label(p, T("design_title"), "DermaDefaultBold")
	local design = create("DComboBox", p)
	design:Dock(TOP)
	design:DockMargin(4, 2, 4, 0)
	local curDesign = StarCore.DesignId(state.design or (IsValid(current) and current:GetNWString("starcore_design")) or "")
	for _, d in ipairs(StarCore.Designs) do design:AddChoice(T("design." .. d.id), d.id, d.id == curDesign) end
	design.OnSelect = function(_, _, _, v) if not applying and v ~= curDesign then send("design", { id = v }) end end
	-- AGP: a refused change (ship not landed, no permission) goes back to the real design (no rebuild now)
	onReply("design", design, function(st)
		local want = StarCore.DesignId(st.design or (IsValid(current) and current:GetNWString("starcore_design")) or "")
		local _, have = design:GetSelected()
		if have == want then return end
		for i, d in ipairs(StarCore.Designs) do
			if d.id == want then design:ChooseOptionID(i) end
		end
	end)
	local dh = label(p, T("design_hint"))
	dh:SetWrap(true)
	dh:SetAutoStretchVertical(true)
	label(p, " ")
	label(p, T("hull_title"), "DermaDefaultBold")
	local bar = create("DProgress", p)
	bar:Dock(TOP)
	bar:DockMargin(4, 2, 4, 0)
	bar:SetTall(14)
	local hl = label(p, "")
	hl.Think = function(self)
		if not IsValid(current) then return end
		local max = current:GetNWInt("starcore_hull_max")
		if max <= 0 then self:SetText(T("hull_off")) bar:SetFraction(1) self:SizeToContents() return end
		local pct = current:GetNWInt("starcore_hull") / max
		bar:SetFraction(pct)
		self:SetText((current:GetNWBool("starcore_disabled") and T("ship_disabled") .. "  " or "") .. T("hud_hull", math.floor(pct * 100)) .. "   " .. T("hull_repair_hint"))
		self:SizeToContents()
	end
	label(p, " ")
	label(p, T("systems_title"), "DermaDefaultBold")
	local cl = button(p, T("btn_cloak"), function() send("cloak", { on = not current:GetNWBool("starcore_cloaked") }) end)
	cl.Think = function(self) self:SetText(IsValid(current) and current:GetNWBool("starcore_cloaked") and T("btn_decloak") or T("btn_cloak")) end
	-- aimed with the camera the player sees (the middle of the screen), cl_hud.lua StarCore.ViewNow
	local function view(t) local o, d = StarCore.ViewNow() t.vo, t.vd = o, d return t end
	button(p, T("btn_tractor_hold"), function() send("tractor", view({ mode = "hold" })) end)
	button(p, T("btn_tractor_pull"), function() send("tractor", view({ mode = "pull" })) end)
	button(p, T("btn_tractor_push"), function() send("tractor", view({ mode = "push" })) end)   --
	button(p, T("btn_tractor_target"), function() send("tractor", { mode = "hold", target = true }) end)
	button(p, T("btn_tractor_off"), function() send("tractor", { off = true }) end)
	label(p, T("tractor_hint"))
	button(p, T("btn_land"), function() send("land") end)
	label(p, " ")
	label(p, T("fleet_title"), "DermaDefaultBold")
	local fl = label(p, "")
	fl.Think = function(self)
		local l = IsValid(current) and current:GetNWEntity("starcore_fleet")
		self:SetText(IsValid(l) and T("fleet_following", IsValid(l:GetNWEntity("starcore_owner")) and l:GetNWEntity("starcore_owner"):Nick() or "?") or T("fleet_none"))
		self:SizeToContents()
	end
	button(p, T("btn_fleet_join"), function() send("fleet", {}) end)
	button(p, T("btn_fleet_leave"), function() send("fleet", { leave = true }) end)
	label(p, " ")
	label(p, T("destruct_title"), "DermaDefaultBold")
	-- blast size: small .. XXL (radius and damage; the server caps the damage)
	label(p, T("destruct_size"))
	local size = create("DComboBox", p)
	size:Dock(TOP)
	size:DockMargin(4, 2, 4, 0)
	local cur = state.settings.destructSize or StarCore.Defaults.destructSize
	for i, d in ipairs(StarCore.DestructSizes) do size:AddChoice(T("destruct_" .. d.id), i, cur == i) end
	-- AGP: the blast line follows the choice at once, and the server's value on every reply
	size.OnSelect = function(_, _, _, v)
		cur = v
		if not applying then send("settings", { values = { destructSize = v } }) end
	end
	onReply("set.destructSize", size, function(st)
		local v = st.settings and st.settings.destructSize
		if isnumber(v) and v ~= cur and StarCore.DestructSizes[v] then size:ChooseOptionID(v) end
	end)
	local blast = label(p, "")
	blast.Think = function(self)
		if not IsValid(current) then return end
		local r, dmg = StarCore.DestructBlast(current:GetNWVector("starcore_size"):Length(), cur)
		self:SetText(T("destruct_info", U.Dist(r), math.floor(dmg)))
		self:SizeToContents()
	end
	local armed = false
	local db = button(p, T("btn_destruct"), nil)
	db.DoClick = function(self)
		if not armed then armed = true; self:SetText(T("btn_destruct_confirm")); timer.Simple(4, function() armed = false; if IsValid(self) then self:SetText(T("btn_destruct")) end end) return end
		armed = false
		send("selfdestruct", { on = true })
	end
	button(p, T("btn_destruct_cancel"), function() send("selfdestruct", { on = false }) end)
	return p
end

local function buildSettings(sheet)
	local p = create("DScrollPanel", sheet)
	label(p, T("jump_style"), "DermaDefaultBold")
	local box = create("DComboBox", p)
	box:Dock(TOP)
	box:DockMargin(4, 2, 4, 0)
	local cv = GetConVar("starcore_jump_style")
	for i, k in ipairs({ "style_streak", "style_flash", "style_portal" }) do box:AddChoice(T(k), i, cv:GetInt() == i) end
	box.OnSelect = function(_, _, _, v) RunConsoleCommand("starcore_jump_style", tostring(v)) end
	label(p, T("theme"), "DermaDefaultBold")
	local tb = create("DComboBox", p)
	tb:Dock(TOP)
	tb:DockMargin(4, 2, 4, 0)
	for i, th in ipairs(StarCore.Themes) do tb:AddChoice(T("theme_" .. th.id), i, (state.settings.theme or 1) == i) end
	tb.OnSelect = function(_, _, _, v) send("settings", { values = { theme = v } }) end
	local hud = create("DCheckBoxLabel", p)
	hud:Dock(TOP)
	hud:DockMargin(4, 8, 4, 0)
	hud:SetText(T("show_hud"))
	hud:SetConVar("starcore_hud")
	-- the HUD's look, each player's own
	label(p, T("hud_style"))
	local hs = create("DComboBox", p)
	hs:Dock(TOP)
	hs:DockMargin(4, 2, 4, 0)
	local hcv = GetConVar("starcore_hud_look")
	for _, i in ipairs({ 1, 2, 3 }) do hs:AddChoice(T("hud_style" .. i), i, hcv:GetInt() == i) end
	hs.OnSelect = function(_, _, _, v) RunConsoleCommand("starcore_hud_look", tostring(v)) end
	local voice = create("DCheckBoxLabel", p)
	voice:Dock(TOP)
	voice:DockMargin(4, 8, 4, 0)
	voice:SetText(T("set_voice"))
	voice:SetConVar("starcore_voice")

	-- units for every distance and speed (menu, screens, HUD): this player's own choice
	label(p, " ")
	label(p, T("unit_title"), "DermaDefaultBold")
	local ub = create("DComboBox", p)
	ub:Dock(TOP)
	ub:DockMargin(4, 2, 4, 0)
	local ucv = GetConVar("starcore_unit_distance")
	for i, k in ipairs({ "unit_auto", "unit_m", "unit_ft", "unit_u" }) do ub:AddChoice(T(k), i - 1, ucv:GetInt() == i - 1) end
	ub.OnSelect = function(_, _, _, v)
		RunConsoleCommand("starcore_unit_distance", tostring(v))
		timer.Simple(0.2, function() if IsValid(frame) and IsValid(current) then build() end end) -- sliders show the new unit
	end

	-- mouse steering (per player): the mouse flies the ship from the pilot seat
	label(p, " ")
	label(p, T("mouse_title"), "DermaDefaultBold")
	local ms = create("DCheckBoxLabel", p)
	ms:Dock(TOP)
	ms:DockMargin(4, 4, 4, 0)
	ms:SetText(T("set_mouse_steer"))
	ms:SetConVar("starcore_mouse_steer")
	local sens = create("DNumSlider", p)
	sens:Dock(TOP)
	sens:DockMargin(4, 2, 4, 0)
	sens:SetText(T("set_mouse_sens"))
	sens:SetMinMax(0.2, 3)
	sens:SetDecimals(1)
	sens:SetConVar("starcore_mouse_sens")
	local mh = label(p, T("mouse_help"))
	mh:SetWrap(true)
	mh:SetAutoStretchVertical(true)
	-- free flight: loops and rolls, nothing levels the ship
	local ff = create("DCheckBoxLabel", p)
	ff:Dock(TOP)
	ff:DockMargin(4, 6, 4, 0)
	ff:SetText(T("set_free_flight"))
	ff:SetConVar("starcore_free_flight")
	local fh = label(p, T("free_flight_help"))
	fh:SetWrap(true)
	fh:SetAutoStretchVertical(true)

	-- keys of the pilot seat (per player, cl_hud.lua): click a button, press a key; right-click = no key
	label(p, " ")
	label(p, T("keys_title"), "DermaDefaultBold")
	local function binder(textKey, cvName)
		label(p, T(textKey))
		local b = vgui.Create("DBinder", p)
		STYLE.DButton(b)
		b:Dock(TOP)
		b:DockMargin(4, 2, 4, 0)
		b:SetTall(24)
		b:SetConVar(cvName)
		b:SetValue(GetConVar(cvName):GetInt())
		b:SetTooltip(cvName)
		return b
	end
	binder("key_look", "starcore_key_look")
	local lm = create("DComboBox", p)
	lm:Dock(TOP)
	lm:DockMargin(4, 2, 4, 0)
	local lcv = GetConVar("starcore_look_toggle")
	lm:AddChoice(T("look_hold"), 0, lcv:GetInt() == 0)
	lm:AddChoice(T("look_tap"), 1, lcv:GetInt() == 1)
	lm.OnSelect = function(_, _, _, v) RunConsoleCommand("starcore_look_toggle", tostring(v)) end
	binder("key_mouse", "starcore_key_mouse")
	binder("key_hover", "starcore_key_hover")
	binder("key_freeze", "starcore_key_freeze")
	binder("key_tractor", "starcore_key_tractor")   --
	binder("key_tractor_pull", "starcore_key_tractor_pull")   --
	binder("key_tractor_push", "starcore_key_tractor_push")
	binder("key_cloak", "starcore_key_cloak")
	binder("key_dock", "starcore_key_dock")   -- (carriers)
	binder("key_aim", "starcore_key_aim")   -- (gunners aim with the crosshair)
	local kh = label(p, T("seatkeys_help"))
	kh:SetWrap(true)
	kh:SetAutoStretchVertical(true)
	label(p, " ")
	label(p, T("ship_info"), "DermaDefaultBold")
	if IsValid(current) then
		-- AGP: follow the ship (the window is no longer rebuilt on every reply)
		liveLabel(p, function() return T("info_parts", current:GetNWInt("starcore_parts")) end)
		liveLabel(p, function() return T("info_seats", current:GetNWInt("starcore_seats")) end)
		liveLabel(p, function()
			local size = current:GetNWVector("starcore_size")
			return T("info_size", U.Dist(size.x), U.Dist(size.y), U.Dist(size.z))
		end)
	end
	label(p, T("info_addons", StarCore.HasWire() and T("yes") or T("no"), StarCore.HasStargate() and T("yes") or T("no")))
	for _, k in ipairs({ "Workshop", "GitHub" }) do
		local url = StarCore.Links and StarCore.Links[k] or ""
		if url ~= "" then button(p, "StarCore (" .. (k == "Workshop" and "Steam Workshop" or "GitHub") .. ")", function() gui.OpenURL(url) end) end
	end
	local tip = StarCore.Links and StarCore.Links.Tip or ""
	if tip ~= "" then button(p, T("btn_tip"), function() gui.OpenURL(tip) end) end

	-- credits: our code licence + the authors of the core models (lua/starcore/sh_license.lua, CREDITS.md)
	label(p, " ")
	label(p, T("credits_title"), "DermaDefaultBold")
	local cc = label(p, T("credits_code"))
	cc:SetWrap(true)
	cc:SetAutoStretchVertical(true)
	local cm = label(p, T("credits_models"))
	cm:SetWrap(true)
	cm:SetAutoStretchVertical(true)
	for _, c in ipairs(StarCore.Credits or {}) do
		local b = button(p, string.format("%s: \"%s\" - %s (%s)", T("design." .. c.design), c.title, c.author, c.license), function() gui.OpenURL(c.url) end)
		b:SetTall(22)
	end
	return p
end

-- AGP: what each tab shows that only a rebuild of the tab can change (numbers and settings follow the reply in
-- place, see live at the top). A tab is rebuilt when its signature differs from the last reply.
local function marksSig(marks)
	local out = {}
	for i, m in ipairs(marks or {}) do out[i] = tostring(m.name) .. "@" .. tostring(m.pos) end
	return table.concat(out, ";")
end
local function gatesSig(sg)
	if not sg then return "" end
	local ids = {}
	for _, g in ipairs(sg.list or {}) do ids[#ids + 1] = table.concat({ tostring(g.id), tostring(g.name), tostring(g.address), tostring(g.dial) }, "|") end
	table.sort(ids) -- the server sorts by distance: flying past gates is no change
	return table.concat({ tostring(sg.hasGate), tostring(sg.name), tostring(sg.address), tostring(sg.group), tostring(sg.class) }, "|") .. "#" .. table.concat(ids, ";")
end
local function powerSig(pw)
	pw = pw or {}
	local cls = {}
	for i, src in ipairs(pw.sources or {}) do cls[i] = tostring(src.class) end
	return table.concat(cls, ",") .. "|" .. tostring(pw.shields or 0) .. "|" .. tostring(pw.shieldMax) .. "|" .. tostring(pw.shieldWired) .. "|" .. tostring((pw.netCap or 0) > 0)
end
local function themeOf(st) return st and st.settings and st.settings.theme or 1 end

local TABS = {
	{ id = "helm", text = "tab_helm", icon = "icon16/arrow_up.png", fn = buildHelm },
	{ id = "jump", text = "tab_jump", icon = "icon16/lightning.png", fn = buildJump, sig = function(st) return marksSig(st.marks) end },
	{ id = "gates", text = "tab_gates", icon = "icon16/world.png", fn = buildGates, sig = function(st) return gatesSig(st.sg) end, only = function(st) return st.sg ~= nil end },
	{ id = "radar", text = "tab_radar", icon = "icon16/transmit.png", fn = buildRadar },
	{ id = "power", text = "tab_power", icon = "icon16/lightning_add.png", fn = buildPower, sig = function(st) return powerSig(st.power) end },
	{ id = "ship", text = "tab_ship", icon = "icon16/wrench.png", fn = buildShip, sig = function(st) return tostring(st.design) end },
	{ id = "settings", text = "tab_settings", icon = "icon16/cog.png", fn = buildSettings },
}

local function scrollOf(p)
	return IsValid(p) and p.GetVBar and p:GetVBar():GetScroll() or 0
end
-- the scroll bar works only once the tab is laid out (and shown): try for a few frames
local function keepScroll(p, y)
	if not (y and y > 0 and IsValid(p) and p.GetVBar) then return end
	local think, tries = p.Think, 0
	p.Think = function(self, ...)
		tries = tries + 1
		local bar = self:GetVBar()
		bar:SetScroll(y)
		if bar:GetScroll() >= y - 1 or tries > 60 then self.Think = think end
		if think then return think(self, ...) end
	end
end
-- the player is dragging something (slider, colour mixer, scroll bar) or typing in this tab
local function busy(p)
	if input.IsMouseDown(MOUSE_LEFT) then return true end
	local f = vgui.GetKeyboardFocus()
	return IsValid(f) and IsValid(p) and (f == p or f:HasParent(p))
end

local function applyLive()
	applying = true
	for name, l in pairs(live) do
		if not IsValid(l.pnl) then
			live[name] = nil
		else
			local ok, err = pcall(l.fn, state)
			if not ok then ErrorNoHalt("StarCore menu (" .. name .. "): " .. tostring(err) .. "\n") end
		end
	end
	applying = false
end

local function rebuildTab(t)
	local item = frame.items[t.id]
	if not (item and IsValid(item.Panel)) then return end
	local old, sheet = item.Panel, frame.sheet
	local y = scrollOf(old)
	local np = t.fn(sheet)
	np:SetParent(sheet)
	np:SetPos(old:GetPos())
	np:SetSize(old:GetSize())
	np:SetVisible(old:IsVisible())
	item.Panel = np
	item.Tab:SetPanel(np)
	old:Remove()
	keepScroll(np, y)
	sheet:InvalidateLayout()
end

-- tabs marked dirty are rebuilt as soon as the player is not using them (also from frame.Think)
local function refreshTabs()
	for _, t in ipairs(TABS) do
		if frame.dirty[t.id] then
			local item = frame.items[t.id]
			if not item then
				frame.dirty[t.id] = nil
			elseif not busy(item.Panel) then
				frame.dirty[t.id] = nil
				rebuildTab(t)
			end
		end
	end
end

function build()
	-- (after leaving the seat or closing the window): a new window opens on the tab the player had open last (cookie,
	-- per player)
	local tabId, scroll = cookie.GetString("starcore_menu_tab", "helm"), {}
	if IsValid(frame) then
		local active = frame.sheet:GetActiveTab()
		for id, item in pairs(frame.items or {}) do
			if item.Tab == active then tabId = id end
			scroll[id] = scrollOf(item.Panel)
		end
		frame:OnClose()   -- (a rebuilt window keeps its place, size and mouse mode)
		local mouseOn = frame:IsMouseInputEnabled()
		frame:Remove()
		timer.Simple(0, function() if IsValid(frame) then frame:SetMouseInputEnabled(mouseOn) end end)
	end
	live = {}
	setTheme(themeOf(state))
	-- (the menu should stay open while he flies, be dragged around and resized at its edges like a window, and he keeps
	-- flying and using keys meanwhile): the keyboard stays with the game (except while typing in a text box,
	-- OnTextEntryGetFocus below); R swaps the mouse between the window and steering (PlayerBindPress below); the window
	-- keeps its place and size (cookies) and closes only with its X (or when the ship is gone).
	frame = create("DFrame")
	local fw = math.Clamp(cookie.GetNumber("starcore_menu_w", 560), 380, ScrW() - 20)
	local fh = math.Clamp(cookie.GetNumber("starcore_menu_h", 560), 300, ScrH() - 20)
	frame:SetSize(fw, fh)
	local fx, fy = cookie.GetNumber("starcore_menu_x", -1), cookie.GetNumber("starcore_menu_y", -1)
	if fx < 0 or fy < 0 then frame:Center() else frame:SetPos(math.Clamp(fx, 0, ScrW() - fw), math.Clamp(fy, 0, ScrH() - fh)) end
	frame:SetTitle("StarCore")
	frame:SetSizable(true)
	frame:SetDraggable(true)
	frame:SetScreenLock(true)
	frame:SetMinWidth(380)
	frame:SetMinHeight(300)
	frame:SetDeleteOnClose(true)
	frame:MakePopup()
	frame:SetKeyboardInputEnabled(false)
	frame.OnClose = function(self)
		local x, y = self:GetPos()
		cookie.Set("starcore_menu_x", x); cookie.Set("starcore_menu_y", y)
		cookie.Set("starcore_menu_w", self:GetWide()); cookie.Set("starcore_menu_h", self:GetTall())
	end
	frame.PaintOver = function(self, w, h)
		if not self:IsMouseInputEnabled() then   -- mouse is steering: say how to get it back
			draw.SimpleText(T("menu_mouse_back"), "DermaDefault", w - 34, 12, C.accentText, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
	end
	local sheet = create("DPropertySheet", frame)
	sheet:Dock(FILL)
	frame.sheet = sheet
	frame.items, frame.dirty = {}, {}
	for _, t in ipairs(TABS) do
		if not t.only or t.only(state) then
			local item = sheet:AddSheet(T(t.text), t.fn(sheet), t.icon)
			frame.items[t.id] = item
			keepScroll(item.Panel, scroll[t.id])
		end
	end
	if frame.items[tabId] then sheet:SetActiveTab(frame.items[tabId].Tab) end
	sheet.OnActiveTabChanged = function(_, _, new)
		for id, item in pairs(frame.items or {}) do
			if item.Tab == new then cookie.Set("starcore_menu_tab", id) end
		end
	end
	-- this Think replaced DFrame's own, which does the dragging - so the window never moved. Now it calls DFrame's first
	-- (title bar drag, bottom-right corner) and adds the edges: the left, right and bottom border resize the window
	-- (the tabs cover the rest, the border gets the clicks).
	local EDGE = 7
	frame:DockPadding(EDGE, 24 + 4, EDGE, EDGE)
	local base = vgui.GetControlTable("DFrame")
	local function edgesAt(self)
		local mx, my = self:ScreenToLocal(gui.MouseX(), gui.MouseY())
		local w, h = self:GetSize()
		if my <= 24 or mx < 0 or my < 0 or mx > w or my > h then return nil end
		local l, r, b = mx < EDGE, mx > w - EDGE, my > h - EDGE
		if l or r or b then return { l = l, r = r, b = b } end
	end
	frame.OnMousePressed = function(self, code)
		local e = code == MOUSE_LEFT and edgesAt(self)
		if e then
			e.mx, e.my, e.x, e.w, e.h = gui.MouseX(), gui.MouseY(), self.x, self:GetWide(), self:GetTall()
			self.AGPEdge = e
			self:MouseCapture(true)
			return
		end
		return base.OnMousePressed(self, code)
	end
	frame.OnMouseReleased = function(self, code)
		self.AGPEdge = nil
		return base.OnMouseReleased(self, code)
	end
	frame.Think = function(self)
		base.Think(self)   -- (dragging at the title bar, the corner, the mouse pointer)
		local e = self.AGPEdge
		if e then
			if not input.IsMouseDown(MOUSE_LEFT) then self.AGPEdge = nil; self:MouseCapture(false)
			else
				local dx, dy = gui.MouseX() - e.mx, gui.MouseY() - e.my
				local w, h, x = e.w, e.h, e.x
				if e.r then w = math.Clamp(e.w + dx, 380, ScrW() - e.x) end
				if e.l then w = math.Clamp(e.w - dx, 380, e.x + e.w); x = e.x + e.w - w end
				if e.b then h = math.Clamp(e.h + dy, 300, ScrH() - self.y) end
				self:SetPos(x, self.y)
				self:SetSize(w, h)
			end
		end
		local hov = self.AGPEdge or (self:IsHovered() and edgesAt(self))
		if hov then self:SetCursor(hov.b and (hov.l and "sizenesw" or hov.r and "sizenwse" or "sizens") or "sizewe") end
		if not IsValid(current) then self:Close() return end
		-- keep the radar data coming while the menu is open
		if (self.nextWatch or 0) < CurTime() then self.nextWatch = CurTime() + 2; send("watch") end
		if next(self.dirty) then refreshTabs() end -- AGP: a change that came while the player was busy
	end
end

net.Receive("starcore_menu", function()
	local core = net.ReadEntity()
	local data = net.ReadTable()
	if not IsValid(core) then return end
	local old = state
	local same = IsValid(frame) and current == core and old ~= nil
	current, state = core, data
	-- AGP: a new window, another core, another theme or the Gates tab coming or going builds the whole window;
	-- any other reply updates the open one in place (see live at the top)
	if not same or themeOf(old) ~= themeOf(state) or (old.sg == nil) ~= (state.sg == nil) then build() return end
	for _, t in ipairs(TABS) do
		if t.sig and t.sig(old) ~= t.sig(state) then frame.dirty[t.id] = true end
	end
	applyLive()
	refreshTabs()
end)

concommand.Add("starcore_menu_close", function() if IsValid(frame) then frame:Close() end end)

-- R while the window is open: the mouse goes from the window to steering and back (the window stays). The key does not
-- reach the server then (it would only open the menu again). Typing in a text box: the keyboard goes to the window.
hook.Add("PlayerBindPress", "StarCore.MenuMouse", function(ply, bind, pressed)
	if not pressed or not IsValid(frame) or not string.find(bind, "+reload", 1, true) then return end
	local tf = vgui.GetKeyboardFocus()
	if IsValid(tf) and tf:HasParent(frame) then return end
	local on = not frame:IsMouseInputEnabled()
	frame:SetMouseInputEnabled(on)
	if not on then frame:SetKeyboardInputEnabled(false) end
	return true
end)
hook.Add("OnTextEntryGetFocus", "StarCore.MenuKeys", function(p)
	if IsValid(frame) and IsValid(p) and p:HasParent(frame) then frame:SetKeyboardInputEnabled(true) end
end)
hook.Add("OnTextEntryLoseFocus", "StarCore.MenuKeys", function(p)
	if IsValid(frame) and IsValid(p) and p:HasParent(frame) then frame:SetKeyboardInputEnabled(false) end
end)
