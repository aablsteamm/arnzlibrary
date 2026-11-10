--[[
	ARNZ UI Library  v1.0.0
	iOS-style "liquid glass" UI for Roblox executors (Madium, Luau). Look and layout rebuilt from StarterGui.ARNZ.
	Font: Builder Extended ExtraBold (rbxassetid://16658237174). No external assets except that font and two small knob images.

	LOAD
		local ARNZ = loadstring(readfile("ARNZ_Library.lua"))()

	WINDOW
		local Window = ARNZ:CreateWindow({
			Name = "My Script",              -- window id; a window with the same Name is replaced on reload
			ConfigFolder = "MyScript",       -- executor workspace folder for configs (default: Name)
			MenuKey = "RightShift",          -- KeyCode name or Enum.KeyCode
			Scale = 1, Glass = 0.5, Blur = true, Visible = true,
			DefaultConfig = "default",
		})
		Window:CreateTab(name, icon)        -> Tab      icon: "eye" "aim" "sliders" "disk" "grid" "circle", "rbxassetid://..." or a number
		Window:CreateSettingsTab(name, icon) -> Tab     built-in: menu key, scale, glass, blur, unload
		Window:CreateConfigTab(name, icon)   -> Tab     built-in: profiles, auto save, auto load, copy / import JSON
		Window:SelectTab(name)
		Window:Notify("text", seconds) or Window:Notify({ Text = "..", Duration = 3 })
		Window:SetVisible(bool)  Window:Toggle()  Window:SetMenuKey("Insert")
		Window:SetScale(n)  Window:SetGlass(n)  Window:SetBlur(bool)
		Window:GetFlag(flag)  Window:SetFlag(flag, value)  Window.Flags[flag]  Window.Elements[flag]
		Window:LoadAutoConfig()             call once after all elements exist: loads the last config if Auto Load is on
		Window:OnDestroy(fn)  Window:Destroy()
		Window.Config:Save(name) :Load(name) :Delete(name) :List() :Export() :Import(json) :SetAutoSave(b) :SetAutoLoad(b)

	TAB / SECTION
		local Section = Tab:CreateSection(name, description)

	ELEMENTS (all take one table; Flag makes the value saveable in configs and readable from Window.Flags)
		Section:CreateToggle     { Name, Description, Default = false, Flag, Callback }
		Section:CreateSlider     { Name, Description, Min = 0, Max = 100, Step = 1, Default, Suffix = "", Flag, Callback }
		Section:CreateDropdown   { Name, Description, Options = { "A", "B" }, Default, Flag, Callback, AllowCustom, Refresh = function() return list end }
		Section:CreateTextbox    { Name, Description, Placeholder, Default, MaxLength = 64, Flag, Callback }
		Section:CreateColorPicker{ Name, Description, Default = Color3, Flag, Callback }
		Section:CreateKeybind    { Name, Description, Default = "Q", Flag, Callback (on change), Pressed (on key press) }
		Section:CreateButton     { Name, Description, ButtonText = "Run", Callback }
		Section:CreateLabel      { Name, Description }
		Common options: Persist = false (do not save), RunOnCreate = true (fire Callback once with the default)
		Every element: :Get() :Set(value, silent) :Reset() :OnChanged(fn) :Fire() :SetVisible(bool) :Destroy()
		Dropdown: :Refresh(list)   Slider: :SetRange(min, max)   Keybind: :IsDown()   Label/Button: :SetText(text)

	Method names also work in lowerCamelCase: ARNZ:createWindow, Window:createTab, Tab:createSection, Section:createToggle ...
	Config files: <ConfigFolder>/configs/<name>.json, settings flags in <ConfigFolder>/meta.json (needs writefile & co.).
]]

-- ================================================================== services & helpers
local cloneref = cloneref or function(i) return i end
local function service(name) return cloneref(game:GetService(name)) end

local RunService = service("RunService")
local UserInputService = service("UserInputService")
local TweenService = service("TweenService")
local HttpService = service("HttpService")
local Lighting = service("Lighting")
local GuiService = service("GuiService")

local genv = (getgenv and getgenv()) or _G

local Library = { Version = "1.0.0" }
local Window, Tab, Section, Element, ConfigManager = {}, {}, {}, {}, {}
for _, class in ipairs({ Window, Tab, Section, Element, ConfigManager }) do class.__index = class end

local FS = {
	ok = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
		and type(isfolder) == "function" and type(makefolder) == "function" and type(listfiles) == "function"
		and type(delfile) == "function",
}
Library.FileSystem = FS.ok

local SUPPORTS_SHADOW = pcall(function() Instance.new("UIShadow"):Destroy() end)

-- every function of a class also gets a lowerCamelCase alias (createWindow, createTab, ...)
local function addAliases(class)
	local extra = {}
	for k, v in pairs(class) do
		if type(k) == "string" and type(v) == "function" and k:sub(1, 1) ~= "_" then
			local lower = k:sub(1, 1):lower() .. k:sub(2)
			if lower ~= k and class[lower] == nil then extra[lower] = v end
		end
	end
	for k, v in pairs(extra) do class[k] = v end
end

local function New(className, props, children)
	local ok, inst = pcall(Instance.new, className)
	if not ok then -- class not available in this client (e.g. UIShadow): keep the tree shape with a placeholder
		inst = Instance.new("Folder")
		props = nil
	end
	local parent
	if props then
		for k, v in pairs(props) do
			if k == "Parent" then parent = v else inst[k] = v end
		end
	end
	if children then
		for _, c in ipairs(children) do c.Parent = inst end
	end
	if parent then inst.Parent = parent end
	return inst
end

-- ================================================================== theme
local FONT = Font.new("rbxassetid://16658237174", Enum.FontWeight.ExtraBold, Enum.FontStyle.Normal)
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
local HEADER = Color3.new(0.749019623, 0.749019623, 0.749019623)
local BIO = Color3.new(0.435294151, 0.435294151, 0.435294151)
local STROKE = Color3.new(0.654901981, 0.654901981, 0.654901981)
local RED_GREEN = ColorSequence.new(Color3.new(0.541176498, 0, 0), Color3.new(0.301960796, 1, 0))
local RIM = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0, 0), NumberSequenceKeypoint.new(0.0997267738, 0.75, 0),
	NumberSequenceKeypoint.new(0.501366079, 0.0124999881, 0), NumberSequenceKeypoint.new(0.897540987, 0.756250024, 0),
	NumberSequenceKeypoint.new(1, 0, 0),
})
local ITEM_GRADIENT = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.new(0.70588237, 0.70588237, 0.70588237)),
	ColorSequenceKeypoint.new(0.0934256092, WHITE), ColorSequenceKeypoint.new(1, WHITE),
})
local OUTLINE_T = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0, 0), NumberSequenceKeypoint.new(0.00136612018, 0.893750012, 0),
	NumberSequenceKeypoint.new(0.501366079, 1, 0), NumberSequenceKeypoint.new(0.998633862, 0.881250024, 0),
	NumberSequenceKeypoint.new(1, 0, 0),
})
local ICON_ON, ICON_OFF = Color3.new(0.18, 0.18, 0.18), Color3.new(0.58, 0.58, 0.58)

local TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local POP = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TAB_OUT = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local TAB_IN = TweenInfo.new(0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0, false, 0.07)
local FAST = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- tween that never throws (a custom instance may not expose every property)
local function tween(inst, props, info)
	local ok, t = pcall(function() return TweenService:Create(inst, info or TWEEN, props) end)
	if ok and t then t:Play() return t end
	return nil
end

-- ================================================================== value helpers
local function hexToColor3(hex)
	local r, g, b = tostring(hex):match("^#?(%x%x)(%x%x)(%x%x)$")
	if not r then return nil end
	return Color3.fromRGB(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16))
end

local function color3ToHex(c)
	return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function toKeyName(x)
	if typeof(x) == "EnumItem" then return x.Name end
	if type(x) == "string" and x ~= "" then return x end
	return nil
end

local function validKeyName(name)
	if name == "None" then return true end
	if name:sub(1, 5) == "Mouse" then
		local ok, v = pcall(function() return Enum.UserInputType[name] end)
		return ok and v ~= nil
	end
	local ok, v = pcall(function() return Enum.KeyCode[name] end)
	return ok and v ~= nil
end

local function inputMatches(input, name)
	if name == "None" then return false end
	if name:sub(1, 5) == "Mouse" then
		local ok, t = pcall(function() return Enum.UserInputType[name] end)
		return ok and input.UserInputType == t
	end
	local ok, code = pcall(function() return Enum.KeyCode[name] end)
	return ok and input.KeyCode == code
end

local function inputHeld(name)
	if name == "None" then return false end
	if name:sub(1, 5) == "Mouse" then
		local ok, t = pcall(function() return Enum.UserInputType[name] end)
		return ok and UserInputService:IsMouseButtonPressed(t)
	end
	local ok, code = pcall(function() return Enum.KeyCode[name] end)
	return ok and UserInputService:IsKeyDown(code)
end

local function defaultFor(kind, meta)
	if kind == "toggle" then return false end
	if kind == "slider" then return meta.Min end
	if kind == "color" then return WHITE end
	if kind == "keybind" then return "None" end
	return ""
end

-- returns the normalized value, or nil when v is not acceptable for this kind
local function normalize(kind, meta, v)
	if kind == "toggle" then
		if type(v) ~= "boolean" then return nil end
		return v
	elseif kind == "slider" then
		if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
		v = math.clamp(v, meta.Min, meta.Max)
		if meta.Step and meta.Step > 0 then v = meta.Min + math.floor((v - meta.Min) / meta.Step + 0.5) * meta.Step end
		return tonumber(string.format("%.4f", math.clamp(v, meta.Min, meta.Max)))
	elseif kind == "dropdown" then
		if type(v) ~= "string" then return nil end
		if v == "" then return "" end
		if meta.AllowCustom then return v:sub(1, 64) end
		for _, item in ipairs(meta.Items) do
			if item == v then return v end
		end
		return nil
	elseif kind == "textbox" then
		if type(v) ~= "string" then return nil end
		return v:sub(1, meta.MaxLength or 64)
	elseif kind == "color" then
		if typeof(v) == "Color3" then return hexToColor3(color3ToHex(v)) end
		if type(v) == "string" then return hexToColor3(v) end
		return nil
	elseif kind == "keybind" then
		local name = toKeyName(v)
		if name and validKeyName(name) then return name end
		return nil
	end
	return nil
end

local function compareKey(kind, v)
	if kind == "color" then return color3ToHex(v) end
	return v
end

local function serialize(o)
	if o.Kind == "color" then return color3ToHex(o.Value) end
	return o.Value
end

-- ================================================================== icons (drawn from frames, no assets)
local ICONS = {}
ICONS.eye = function(s) s(0.5, 0.5, 0.92, 0.56, 1, false); s(0.5, 0.5, 0.26, 0.26, 1, true) end
ICONS.aim = function(s)
	s(0.5, 0.5, 0.62, 0.62, 1, false); s(0.5, 0.5, 0.1, 0.1, 1, true)
	s(0.5, 0.1, 0.07, 0.2, nil, true); s(0.5, 0.9, 0.07, 0.2, nil, true)
	s(0.1, 0.5, 0.2, 0.07, nil, true); s(0.9, 0.5, 0.2, 0.07, nil, true)
end
ICONS.sliders = function(s)
	s(0.5, 0.25, 0.84, 0.07, 1, true); s(0.5, 0.5, 0.84, 0.07, 1, true); s(0.5, 0.75, 0.84, 0.07, 1, true)
	s(0.3, 0.25, 0.2, 0.2, 1, true); s(0.68, 0.5, 0.2, 0.2, 1, true); s(0.42, 0.75, 0.2, 0.2, 1, true)
end
ICONS.disk = function(s)
	s(0.5, 0.5, 0.8, 0.8, 0.15, false); s(0.5, 0.3, 0.42, 0.14, 0.3, true)
	s(0.5, 0.66, 0.5, 0.07, 1, true); s(0.5, 0.8, 0.5, 0.07, 1, true)
end
ICONS.grid = function(s)
	s(0.28, 0.28, 0.36, 0.36, 0.2, true); s(0.72, 0.28, 0.36, 0.36, 0.2, true)
	s(0.28, 0.72, 0.36, 0.36, 0.2, true); s(0.72, 0.72, 0.36, 0.36, 0.2, true)
end
ICONS.circle = function(s) s(0.5, 0.5, 0.7, 0.7, 1, false); s(0.5, 0.5, 0.2, 0.2, 1, true) end

-- Library:RegisterIcon("name", function(shape) shape(x, y, w, h, corner, filled) end)  (all values are 0..1 scales)
function Library:RegisterIcon(name, builder)
	if type(name) == "string" and type(builder) == "function" then ICONS[name] = builder end
end

local function drawIcon(kind, parent)
	local root = New("Frame", {
		Name = "Icon", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), Parent = parent,
	}, { New("UIAspectRatioConstraint", { AspectRatio = 1 }) })
	local parts = {}
	local asset = (type(kind) == "number" and ("rbxassetid://" .. kind))
		or (type(kind) == "string" and (kind:match("^rbxassetid://") or kind:match("^rbxasset://")) and kind)
		or (type(kind) == "string" and kind:match("^%d+$") and ("rbxassetid://" .. kind))
	if asset then
		parts[1] = New("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Image = asset, ImageColor3 = WHITE, Parent = root })
		return { root = root, parts = parts }
	end
	local function shape(x, y, w, h, round, filled)
		local f = New("Frame", {
			BackgroundTransparency = filled and 0 or 1, BackgroundColor3 = WHITE, BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(w, h), Parent = root,
		})
		if round then New("UICorner", { CornerRadius = UDim.new(round, 0), Parent = f }) end
		if filled then
			parts[#parts + 1] = f
		else
			parts[#parts + 1] = New("UIStroke", { Thickness = 2, Color = WHITE, Parent = f })
		end
	end
	;(ICONS[kind] or ICONS.circle)(shape)
	return { root = root, parts = parts }
end

local function colorProp(part)
	if part:IsA("UIStroke") then return "Color" end
	if part:IsA("ImageLabel") then return "ImageColor3" end
	return "BackgroundColor3"
end

local function setIconColor(icon, color)
	for _, p in ipairs(icon.parts) do p[colorProp(p)] = color end
end

local function tweenIconColor(icon, color)
	for _, p in ipairs(icon.parts) do tween(p, { [colorProp(p)] = color }) end
end

-- ================================================================== row pieces
local function labelPair(row, title, desc, hPos, hSize, bPos, bSize)
	local function make(name, text, color, pos, size, maxSize, textSize)
		return New("TextLabel", {
			Name = name, BackgroundTransparency = 1, BorderSizePixel = 0, FontFace = FONT, Text = text, TextColor3 = color,
			TextSize = textSize, TextScaled = true, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
			Position = pos, Size = size, Parent = row,
		}, { New("UIStroke", { Color = STROKE }), New("UITextSizeConstraint", { MaxTextSize = maxSize }) })
	end
	make("headerText", title, HEADER, hPos, hSize, 15, 14)
	make("bioText", desc or "", BIO, bPos, bSize, 30, 18)
end

-- glass button (selectButton design)
local function glassButton(props, corner)
	props.BackgroundColor3 = WHITE
	props.BorderSizePixel = 0
	props.FontFace = FONT
	props.TextColor3 = BLACK
	props.TextScaled = true
	local children = {
		New("UICorner", corner and { CornerRadius = corner } or nil),
		New("Frame", { Name = "Outline", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 1, 0) }, {
			New("UICorner", corner and { CornerRadius = corner } or nil),
			New("UIStroke", nil, { New("UIGradient", { Transparency = OUTLINE_T }) }),
		}),
		New("UIGradient", { Color = ITEM_GRADIENT, Rotation = -90 }),
		New("UIShadow", { BlurRadius = UDim.new(0, 20), Color = WHITE, Transparency = 0.5 }),
		New("UITextSizeConstraint", { MaxTextSize = 14 }),
	}
	return New("TextButton", props, children)
end

-- ================================================================== config manager
local function cleanName(s)
	s = tostring(s or ""):gsub("[^%w%-%_ ]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	s = s:sub(1, 32)
	if s == "" then return nil end
	return s
end

function ConfigManager.new(window, folder, defaultName)
	local self = setmetatable({}, ConfigManager)
	self.Window = window
	self.Root = cleanName(folder) or "ARNZ"
	self.Dir = self.Root .. "/configs"
	self.MetaPath = self.Root .. "/meta.json"
	self.Available = FS.ok
	self.Meta = { autosave = false, autoload = false, last = cleanName(defaultName) or "default" }
	self.Current = self.Meta.last
	self._token = 0
	self:_loadMeta()
	self.Current = self.Meta.last
	return self
end

function ConfigManager:Ensure()
	if not self.Available then return false end
	pcall(function()
		if not isfolder(self.Root) then makefolder(self.Root) end
		if not isfolder(self.Dir) then makefolder(self.Dir) end
	end)
	return true
end

function ConfigManager:_loadMeta()
	if not self.Available then return end
	local ok, raw = pcall(function() if isfile(self.MetaPath) then return readfile(self.MetaPath) end end)
	if not ok or type(raw) ~= "string" then return end
	local okJson, data = pcall(function() return HttpService:JSONDecode(raw) end)
	if not okJson or type(data) ~= "table" then return end
	if type(data.autosave) == "boolean" then self.Meta.autosave = data.autosave end
	if type(data.autoload) == "boolean" then self.Meta.autoload = data.autoload end
	if cleanName(data.last) then self.Meta.last = cleanName(data.last) end
end

function ConfigManager:SaveMeta()
	if not self:Ensure() then return false end
	return (pcall(function() writefile(self.MetaPath, HttpService:JSONEncode(self.Meta)) end))
end

function ConfigManager:Collect()
	local values = {}
	for _, o in ipairs(self.Window._order) do
		if o.Persist and o.Flag then values[o.Flag] = serialize(o) end
	end
	return { schema = 1, library = Library.Version, savedAt = os.time(), values = values }
end

function ConfigManager:Export()
	return HttpService:JSONEncode(self:Collect())
end

function ConfigManager:_apply(data)
	if type(data) ~= "table" or type(data.values) ~= "table" then return false, "invalid json" end
	local window = self.Window
	local applied = 0
	window._loading = true
	for flag, v in pairs(data.values) do
		local o = window.Elements[flag]
		if o and o.Persist and o:Set(v) then applied += 1 end
	end
	window._loading = false
	return true, applied
end

function ConfigManager:Import(json)
	local ok, data = pcall(function() return HttpService:JSONDecode(json) end)
	if not ok then return false, "invalid json" end
	return self:_apply(data)
end

function ConfigManager:Save(name)
	if not self.Available then return false, "filesystem unavailable" end
	name = cleanName(name or self.Current)
	if not name then return false, "invalid name" end
	self:Ensure()
	local ok, err = pcall(function() writefile(self.Dir .. "/" .. name .. ".json", self:Export()) end)
	if not ok then return false, tostring(err) end
	self.Current, self.Meta.last = name, name
	self:SaveMeta()
	return true, name
end

function ConfigManager:Load(name)
	if not self.Available then return false, "filesystem unavailable" end
	name = cleanName(name or self.Current)
	if not name then return false, "invalid name" end
	local path = self.Dir .. "/" .. name .. ".json"
	local okExists, exists = pcall(isfile, path)
	if not okExists or not exists then return false, "not found" end
	local okRead, raw = pcall(readfile, path)
	if not okRead or type(raw) ~= "string" then return false, "read failed" end
	local ok, res = self:Import(raw)
	if ok then
		self.Current, self.Meta.last = name, name
		self:SaveMeta()
	end
	return ok, res
end

function ConfigManager:Delete(name)
	if not self.Available then return false, "filesystem unavailable" end
	name = cleanName(name)
	if not name then return false, "invalid name" end
	local path = self.Dir .. "/" .. name .. ".json"
	local ok, err = pcall(function()
		if not isfile(path) then error("not found") end
		delfile(path)
	end)
	if not ok then return false, tostring(err) end
	return true, name
end

function ConfigManager:List()
	local names = {}
	if not self.Available then return names end
	local ok, files = pcall(listfiles, self.Dir)
	if ok and type(files) == "table" then
		for _, p in ipairs(files) do
			local n = tostring(p):match("([^/\\]+)%.json$")
			if n then names[#names + 1] = n end
		end
	end
	table.sort(names, function(a, b) return a:lower() < b:lower() end)
	return names
end

function ConfigManager:SetAutoSave(v)
	self.Meta.autosave = v == true
	self:SaveMeta()
	if self.Meta.autosave then self:_queueAutosave() end
end

function ConfigManager:SetAutoLoad(v)
	self.Meta.autoload = v == true
	self:SaveMeta()
end

function ConfigManager:LoadAuto()
	if self.Meta.autoload then return self:Load(self.Meta.last) end
	return false, "auto load is off"
end

function ConfigManager:_queueAutosave()
	if not self.Meta.autosave or self.Window.Destroyed then return end
	self._token += 1
	local mine = self._token
	task.delay(0.8, function()
		if mine ~= self._token or self.Window.Destroyed or not self.Meta.autosave then return end
		self:Save(self.Current)
	end)
end

-- ================================================================== elements (shared behaviour)
function Element:Get()
	return self.Value
end

function Element:_emitUi()
	for _, fn in ipairs(self._ui) do
		local ok, err = pcall(fn, self.Value)
		if not ok then warn("[ARNZ UI] element error (" .. tostring(self.Flag or self.Kind) .. "): " .. tostring(err)) end
	end
end

function Element:Fire()
	for _, fn in ipairs(self._user) do
		local ok, err = pcall(fn, self.Value)
		if not ok then warn("[ARNZ UI] callback error (" .. tostring(self.Flag or self.Kind) .. "): " .. tostring(err)) end
	end
end

-- silent = true updates the UI and Flags but does not run callbacks
function Element:Set(value, silent)
	local v = normalize(self.Kind, self.Meta, value)
	if v == nil then return false end
	if compareKey(self.Kind, v) == compareKey(self.Kind, self.Value) then return true end
	self.Value = v
	if self.Flag then self.Window.Flags[self.Flag] = v end
	self:_emitUi()
	if not silent then self:Fire() end
	if self.Persist and not self.Window._loading then self.Window.Config:_queueAutosave() end
	return true
end

function Element:Reset()
	return self:Set(self.Default)
end

function Element:OnChanged(fn)
	if type(fn) == "function" then self._user[#self._user + 1] = fn end
	return self
end

function Element:SetVisible(v)
	if self.Row then self.Row.Visible = v ~= false end
end

function Element:Destroy()
	local window = self.Window
	if self.Flag and window.Elements[self.Flag] == self then
		window.Elements[self.Flag] = nil
		window.Flags[self.Flag] = nil
	end
	for i, o in ipairs(window._order) do
		if o == self then table.remove(window._order, i) break end
	end
	for i, o in ipairs(window._keybinds) do
		if o == self then table.remove(window._keybinds, i) break end
	end
	if self.Row then pcall(function() self.Row:Destroy() end) end
end

function Element:SetText(text)
	if self._setText then self._setText(tostring(text)) end
end

function Element:IsDown()
	return self.Kind == "keybind" and inputHeld(self.Value)
end

function Element:Refresh(list)
	if self.Kind == "dropdown" and self._refresh then self._refresh(list) end
end

function Element:SetRange(min, max)
	if self.Kind ~= "slider" or type(min) ~= "number" or type(max) ~= "number" or max <= min then return end
	self.Meta.Min, self.Meta.Max = min, max
	local v = normalize("slider", self.Meta, self.Value)
	self.Value = v
	if self.Flag then self.Window.Flags[self.Flag] = v end
	self:_emitUi()
end

-- ================================================================== window
local registry = genv.__ARNZ_UI_WINDOWS
if type(registry) ~= "table" then
	registry = {}
	genv.__ARNZ_UI_WINDOWS = registry
end

function Library:CreateWindow(cfg)
	cfg = type(cfg) == "table" and cfg or {}
	local self = setmetatable({}, Window)
	self.Name = tostring(cfg.Name or "ARNZ")

	local previous = registry[self.Name]
	if previous and previous.Destroy and not previous.Destroyed then pcall(function() previous:Destroy() end) end
	registry[self.Name] = self

	self.Flags, self.Elements = {}, {}
	self.Destroyed = false
	self.Visible = cfg.Visible ~= false
	self.MenuKey = toKeyName(cfg.MenuKey) or "RightShift"
	self._order, self._tabs, self._tabList, self._cards, self._keybinds = {}, {}, {}, {}, {}
	self._conns, self._cleanups, self._destroyHandlers = {}, {}, {}
	self._animating = {}
	self._glass = math.clamp(tonumber(cfg.Glass) or 0.5, 0, 1)
	self._blurOn = cfg.Blur ~= false
	self._loading = false
	self._tabToken = 0
	self._current = nil
	self._listening = nil
	self._toastCount = 0

	self.Config = ConfigManager.new(self, cfg.ConfigFolder or self.Name, cfg.DefaultConfig)

	-- ---- guis
	local parentGui = (gethui and gethui()) or service("CoreGui")
	local screen = New("ScreenGui", {
		Name = "ARNZ_" .. self.Name, ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 1000,
	})
	local overlay = New("ScreenGui", {
		Name = "ARNZ_" .. self.Name .. "_Overlay", ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 1001,
	})
	screen.Parent = parentGui
	overlay.Parent = parentGui
	self.Gui, self.Overlay = screen, overlay

	-- GetMouseLocation() is in viewport space (includes the topbar inset); this is the shift to GUI space of `screen`
	local insetProbe = New("Frame", { Name = "InsetProbe", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromOffset(1, 1), Parent = screen })
	function self._guiInsetOffset() return GuiService:GetGuiInset().Y - insetProbe.AbsolutePosition.Y end

	local main = New("Frame", {
		Name = "Main", Active = true, BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = cfg.Position or UDim2.new(0.167085424, 0, 0.143876344, 0), Size = cfg.Size or UDim2.new(0.665201008, 0, 0.712247312, 0),
		Visible = self.Visible, Parent = screen,
	}, {
		New("UICorner", { CornerRadius = UDim.new(0, 16) }),
		New("UIShadow", { BlurRadius = UDim.new(0, 20), Color = WHITE, Spread = UDim2.new(0.01, 0, 0.01, 0), Transparency = 0.75 }),
	})
	local uiScale = New("UIScale", { Scale = math.clamp(tonumber(cfg.Scale) or 1, 0.5, 2), Parent = main })
	self.Main, self._uiScale = main, uiScale

	local foot = New("Frame", {
		Name = "Foot", BackgroundColor3 = WHITE, BackgroundTransparency = 0.949999988, BorderSizePixel = 0,
		Position = UDim2.new(0.206275657, 0, 0.838172555, 0), Size = UDim2.new(0.586177945, 0, 0.144342825, 0), Parent = main,
	}, {
		New("UICorner", { CornerRadius = UDim.new(1, 0) }),
		New("UIGradient", { Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(0.254901975, 0.254901975, 0.254901975)),
			ColorSequenceKeypoint.new(0.522491395, WHITE),
			ColorSequenceKeypoint.new(1, Color3.new(0.329411775, 0.329411775, 0.329411775)),
		}) }),
		New("UIShadow", { BlurRadius = UDim.new(0, 20), Color = WHITE, Spread = UDim2.new(0.01, 0, 0.01, 0), Transparency = 0.75 }),
	})
	self._tabContainer = New("Frame", {
		Name = "tabContainer", BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.new(0.0628259629, 0, 0.0693958774, 0), Size = UDim2.new(0.871508896, 0, 0.844307899, 0), Parent = foot,
	}, {
		New("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0.05, 0), SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local body = New("Frame", {
		Name = "Body", BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0.0050084237, 0), Size = UDim2.new(1, 0, 0.833164155, 0), Parent = main,
	})
	local bodyHeader = New("Frame", {
		Name = "header", Active = true, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0.217833906, 0), Parent = body,
	})
	self._body = body
	self._headerIconHolder = New("Frame", {
		Name = "tabIcon", BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.new(0.0198300276, 0, 0.233566746, 0), Size = UDim2.new(0.0472143516, 0, 0.508917034, 0), Parent = bodyHeader,
	})
	local tabName = New("TextLabel", {
		Name = "tabName", BackgroundTransparency = 1, BorderSizePixel = 0, FontFace = FONT, Text = "",
		TextColor3 = WHITE, TextScaled = true, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0.0783758238, 0, 0.233566746, 0), Size = UDim2.new(0.3, 0, 0.508917034, 0), Parent = bodyHeader,
	}, {
		New("UIShadow", { BlurRadius = UDim.new(0, 20), Color = WHITE, Transparency = 0.5 }),
		New("UIStroke", { Color = Color3.new(0.309803933, 0.309803933, 0.309803933), Transparency = 0.639999986 }),
	})
	self._tabName, self._titleHome = tabName, tabName.Position

	-- ---- notifications (stacked, bottom centre)
	self._toasts = New("Frame", {
		Name = "Toasts", AnchorPoint = Vector2.new(0.5, 1), BackgroundTransparency = 1, Position = UDim2.new(0.5, 0, 1, -34),
		Size = UDim2.new(0, 460, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = overlay,
	}, {
		New("UIListLayout", {
			HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	-- ---- blur
	self._blur = New("BlurEffect", { Name = "ARNZ_Blur_" .. self.Name, Size = 0, Parent = Lighting })

	-- ---- per-frame animators (slider glide)
	self:_connect(RunService.RenderStepped, function(dt)
		for fn in pairs(self._animating) do
			if fn(dt) then self._animating[fn] = nil end
		end
	end)

	-- ---- window drag
	do
		local dragging, startMouse, startPos
		self:_connect(bodyHeader.InputBegan, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging, startMouse, startPos = true, input.Position, main.Position
			end
		end)
		self:_connect(UserInputService.InputChanged, function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				local d = input.Position - startMouse
				main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
			end
		end)
		self:_connect(UserInputService.InputEnded, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
		end)
	end

	-- ---- input: keybind capture, menu key, keybind elements
	self:_connect(UserInputService.InputBegan, function(input, processed)
		if self.Destroyed then return end
		if self._listening then
			self._listening(input)
			return
		end
		if UserInputService:GetFocusedTextBox() then return end
		if not processed and inputMatches(input, self.MenuKey) then
			self:Toggle()
			return
		end
		if processed then return end
		for _, kb in ipairs(self._keybinds) do
			if kb._pressed and inputMatches(input, kb.Value) then
				local ok, err = pcall(kb._pressed, kb.Value)
				if not ok then warn("[ARNZ UI] keybind error: " .. tostring(err)) end
			end
		end
	end)

	self:_applyBlur()
	return self
end

function Window:_connect(signal, fn)
	local c = signal:Connect(fn)
	self._conns[#self._conns + 1] = c
	return c
end

function Window:_applyBlur()
	if self._blur then tween(self._blur, { Size = (self.Visible and self._blurOn) and 14 or 0 }) end
end

function Window:_define(kind, cfg, default, meta)
	local flag = cfg.Flag
	if flag ~= nil then
		flag = tostring(flag)
		if self.Elements[flag] then
			warn(("[ARNZ UI] duplicate flag '%s': that element will not be saved"):format(flag))
			flag = nil
		end
	end
	local o = setmetatable({
		Kind = kind, Window = self, Meta = meta, Flag = flag, Persist = flag ~= nil and cfg.Persist ~= false,
		_ui = {}, _user = {},
	}, Element)
	local v = normalize(kind, meta, default)
	if v == nil then v = normalize(kind, meta, defaultFor(kind, meta)) end
	o.Value, o.Default = v, v
	if flag then
		self.Flags[flag] = v
		self.Elements[flag] = o
	end
	if type(cfg.Callback) == "function" then o._user[1] = cfg.Callback end
	self._order[#self._order + 1] = o
	return o
end

-- ---- public window api
function Window:GetFlag(flag)
	local o = self.Elements[flag]
	return o and o.Value
end

function Window:SetFlag(flag, value, silent)
	local o = self.Elements[flag]
	return o ~= nil and o:Set(value, silent)
end

function Window:SetVisible(v)
	v = v ~= false
	self.Visible = v
	self.Main.Visible = v
	self:_applyBlur()
end

function Window:Toggle()
	self:SetVisible(not self.Visible)
end

function Window:SetMenuKey(key)
	local name = toKeyName(key)
	if name and name ~= "None" and validKeyName(name) then
		self.MenuKey = name
		return true
	end
	return false
end

function Window:SetScale(n)
	if type(n) == "number" then self._uiScale.Scale = math.clamp(n, 0.5, 2) end
end

function Window:SetGlass(n)
	if type(n) ~= "number" then return end
	self._glass = math.clamp(n, 0, 1)
	for _, c in ipairs(self._cards) do c.BackgroundTransparency = self._glass end
end

function Window:SetBlur(v)
	self._blurOn = v == true
	self:_applyBlur()
end

function Window:OnDestroy(fn)
	if type(fn) == "function" then self._destroyHandlers[#self._destroyHandlers + 1] = fn end
end

function Window:LoadAutoConfig()
	return self.Config:LoadAuto()
end

function Window:Notify(options, duration)
	if self.Destroyed then return end
	local text = options
	if type(options) == "table" then
		text = options.Text or options.Content or options.Title or ""
		duration = options.Duration or duration
	end
	duration = tonumber(duration) or 2.6
	self._toastCount += 1
	local label
	local toast = New("Frame", {
		Name = "Toast", LayoutOrder = self._toastCount, Size = UDim2.new(0, 0, 0, 38), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, Parent = self._toasts,
	}, {
		New("UICorner", { CornerRadius = UDim.new(1, 0) }),
		New("UIPadding", { PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20) }),
		New("UIShadow", { BlurRadius = UDim.new(0, 20), Transparency = 0.5 }),
	})
	label = New("TextLabel", {
		BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), FontFace = FONT,
		Text = tostring(text), TextColor3 = Color3.new(0.2, 0.2, 0.2), TextSize = 16, TextTransparency = 1, Parent = toast,
	})
	tween(toast, { BackgroundTransparency = 0.25 }, FAST)
	tween(label, { TextTransparency = 0 }, FAST)
	task.delay(duration, function()
		if not toast.Parent then return end
		tween(toast, { BackgroundTransparency = 1 }, FAST)
		tween(label, { TextTransparency = 1 }, FAST)
		task.delay(0.2, function() if toast.Parent then toast:Destroy() end end)
	end)
end

function Window:Destroy()
	if self.Destroyed then return end
	self.Destroyed = true
	for _, fn in ipairs(self._destroyHandlers) do pcall(fn) end
	for _, c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
	for _, fn in ipairs(self._cleanups) do pcall(fn) end
	pcall(function() self._blur:Destroy() end)
	pcall(function() self.Gui:Destroy() end)
	pcall(function() self.Overlay:Destroy() end)
	if registry[self.Name] == self then registry[self.Name] = nil end
end

-- ================================================================== tabs
function Window:_layoutTabs()
	local n = #self._tabList
	if n == 0 then return end
	local w = math.min(0.125693157, (0.98 - 0.05 * (n - 1)) / n)
	for _, name in ipairs(self._tabList) do
		self._tabs[name].button.Size = UDim2.new(w, 0, 0.931506872, 0)
	end
end

-- Animated tab switch: the old page fades up and out, the new one fades in from below, the title slides, icons pop.
function Window:SelectTab(name, instant)
	local chosen = self._tabs[name]
	if not chosen then return false end
	if self._current == name and not instant then return true end
	self._current = name
	self._tabToken += 1
	local token = self._tabToken
	local tabName, titleHome = self._tabName, self._titleHome

	if instant then
		tabName.Text = name
		tabName.TextTransparency = 0
		tabName.Position = titleHome
	else
		tween(tabName, { TextTransparency = 1 }, TAB_OUT)
		task.delay(0.16, function()
			if token ~= self._tabToken or self.Destroyed then return end
			tabName.Text = name
			tabName.Position = UDim2.new(titleHome.X.Scale, titleHome.X.Offset + 16, titleHome.Y.Scale, titleHome.Y.Offset)
			tween(tabName, { TextTransparency = 0, Position = titleHome }, TAB_IN)
		end)
	end

	for n, t in pairs(self._tabs) do
		local on = n == name
		tween(t.button, { BackgroundTransparency = on and 0 or 0.55 })
		tween(t.buttonScale, { Scale = on and 1.1 or 1 }, on and POP or TWEEN)
		if instant then
			setIconColor(t.buttonIcon, on and ICON_ON or ICON_OFF)
		else
			tweenIconColor(t.buttonIcon, on and ICON_ON or ICON_OFF)
		end
		t.headerIcon.root.Visible = on
		if on then
			t.headerScale.Scale = instant and 1 or 0.35
			if not instant then tween(t.headerScale, { Scale = 1 }, POP) end
		end

		local g, home = t.group, t.home
		if on then
			g.Visible = true
			if instant then
				g.GroupTransparency, g.Position, t.groupScale.Scale = 0, home, 1
			else
				g.GroupTransparency = 1
				g.Position = UDim2.new(home.X.Scale, home.X.Offset, home.Y.Scale, home.Y.Offset + 24)
				t.groupScale.Scale = 0.975
				tween(g, { GroupTransparency = 0, Position = home }, TAB_IN)
				tween(t.groupScale, { Scale = 1 }, TAB_IN)
			end
		elseif g.Visible then
			if instant then
				g.Visible = false
			else
				tween(g, { GroupTransparency = 1, Position = UDim2.new(home.X.Scale, home.X.Offset, home.Y.Scale, home.Y.Offset - 10) }, TAB_OUT)
				task.delay(0.17, function()
					if self._current ~= n and not self.Destroyed then g.Visible = false end
				end)
			end
		end
	end
	return true
end

function Window:CreateTab(name, icon)
	name = tostring(name or "Tab")
	if self._tabs[name] then return self._tabs[name].object end

	local button = New("ImageButton", {
		Name = "tabButton_" .. name, AutoButtonColor = false, BackgroundColor3 = WHITE, BorderSizePixel = 0,
		LayoutOrder = #self._tabList + 1, Size = UDim2.new(0.125693157, 0, 0.931506872, 0), Parent = self._tabContainer,
	}, {
		New("UICorner", { CornerRadius = UDim.new(0.25, 0) }),
		New("UIStroke", { Color = Color3.new(0.568627477, 0.568627477, 0.568627477), Transparency = 0.689999998 }, {
			New("UIGradient", { Color = ColorSequence.new(WHITE, Color3.new(0.368627459, 0.368627459, 0.368627459)), Transparency = RIM }),
		}),
		New("UIShadow", { BlurRadius = UDim.new(0, 20), Transparency = 0.5 }),
	})
	local holder = New("Frame", {
		Name = "icon", BackgroundTransparency = 1, Position = UDim2.new(0.161764711, 0, 0.176470593, 0),
		Size = UDim2.new(0.661764681, 0, 0.661764681, 0), Parent = button,
	})
	local buttonIcon = drawIcon(icon or "circle", holder)
	local buttonScale = New("UIScale", { Scale = 1, Parent = button })
	local headerIcon = drawIcon(icon or "circle", self._headerIconHolder)
	headerIcon.root.Visible = false
	setIconColor(headerIcon, WHITE)
	local headerScale = New("UIScale", { Scale = 1, Parent = headerIcon.root })

	local home = UDim2.new(0.0198300276, 0, 0.217999965, 0)
	local group = New("CanvasGroup", {
		Name = "pageGroup_" .. name, BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
		Position = home, Size = UDim2.new(0.966005683, 0, 0.782023728, 0), Parent = self._body,
	}, { New("UIScale", { Scale = 1 }) })
	local page = New("ScrollingFrame", {
		Name = "functions_" .. name, Active = true, BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(1, 0, 1, 0),
		CanvasSize = UDim2.new(0, 0, 0.782023728, 0), AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X, ScrollBarThickness = 3, Parent = group,
	}, {
		New("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 16), SortOrder = Enum.SortOrder.LayoutOrder }),
		New("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14) }),
	})

	local object = setmetatable({ Name = name, Window = self, Page = page, _sections = 0 }, Tab)
	self._tabs[name] = {
		button = button, buttonIcon = buttonIcon, buttonScale = buttonScale, headerIcon = headerIcon, headerScale = headerScale,
		page = page, group = group, groupScale = group:FindFirstChildOfClass("UIScale"), home = home, object = object,
	}
	self._tabList[#self._tabList + 1] = name
	self:_layoutTabs()
	self:_connect(button.MouseButton1Click, function() self:SelectTab(name) end)

	if not self._current then self:SelectTab(name, true) else setIconColor(buttonIcon, ICON_OFF) end
	return object
end

-- ================================================================== sections (cards)
function Tab:CreateSection(name, description)
	local window = self.Window
	self._sections += 1
	local card = New("Frame", {
		Name = "mainFrame", Active = true, BackgroundColor3 = WHITE, BackgroundTransparency = window._glass, BorderSizePixel = 0,
		ClipsDescendants = true, LayoutOrder = self._sections, Size = UDim2.new(0, 340, 1, 0), Parent = self.Page,
	}, {
		New("UICorner", { CornerRadius = UDim.new(0.15, 0) }),
		New("UIShadow", { BlurRadius = UDim.new(0, 20), Color = WHITE, Transparency = 0.5 }),
		New("UIStroke", { Color = WHITE, Thickness = 1, Transparency = 0.55 }, { New("UIGradient", { Transparency = RIM }) }),
	})
	window._cards[#window._cards + 1] = card
	labelPair(card, tostring(name or "Section"), description, UDim2.new(0.0866982564, 0, 0.04, 0), UDim2.new(0.821428597, 0, 0.09, 0),
		UDim2.new(0.0843608901, 0, 0.135, 0), UDim2.new(0.821428597, 0, 0.1, 0))
	card.headerText.UITextSizeConstraint.MaxTextSize = 38
	card.bioText.UITextSizeConstraint.MaxTextSize = 18

	local list = New("ScrollingFrame", {
		Name = "templatesContainer", Active = true, BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.new(0.0227272734, 0, 0.27, 0), Size = UDim2.new(0.954545, 0, 0.71, 0),
		CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 3, ScrollBarImageColor3 = Color3.new(0.666666687, 0.666666687, 0.666666687), Parent = card,
	}, {
		New("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		New("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 12) }),
	})
	return setmetatable({ Window = window, Tab = self, Card = card, List = list, _rows = 0 }, Section)
end

function Section:_row(name, height)
	self._rows += 1
	return New("Frame", {
		Name = name, BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = self._rows,
		Size = UDim2.new(1, 0, 0, height), Parent = self.List,
	})
end

local function finish(o, cfg)
	if cfg.RunOnCreate then task.spawn(function() o:Fire() end) end
	return o
end

-- ---- toggle
function Section:CreateToggle(cfg)
	cfg = cfg or {}
	local window = self.Window
	local o = window:_define("toggle", cfg, cfg.Default == true, {})
	local r = self:_row("ToggleTemplate", 52)
	o.Row = r
	labelPair(r, tostring(cfg.Name or "Toggle"), cfg.Description, UDim2.new(0.04, 0, 0.03, 0), UDim2.new(0.55, 0, 0.42, 0),
		UDim2.new(0.043, 0, 0.45, 0), UDim2.new(0.55, 0, 0.5, 0))
	local pill = New("Frame", {
		Name = "toggleFrame", BackgroundColor3 = WHITE, BorderSizePixel = 0,
		Position = UDim2.new(0.67, 0, 0.23, 0), Size = UDim2.new(0.31, 0, 0.54, 0), Parent = r,
	}, {
		New("UICorner", { CornerRadius = UDim.new(1, 0) }),
		New("UIGradient", { Color = RED_GREEN }),
		New("UIShadow", { BlurRadius = UDim.new(0, 20), Transparency = 0.5 }, { New("UIGradient", { Color = RED_GREEN }) }),
	})
	local pillGrad = pill:FindFirstChildOfClass("UIGradient")
	local shadow = pill:FindFirstChildOfClass("UIShadow")
	local shadowGrad = shadow and shadow:FindFirstChildOfClass("UIGradient")
	local knob = New("ImageButton", {
		Name = "button", BackgroundTransparency = 1, BorderSizePixel = 0, Image = "rbxassetid://7771590397",
		Position = UDim2.new(-0.0038596706, 0, 0, 0), Size = UDim2.new(0.310314178, 0, 1, 0), Parent = pill,
	}, {
		New("UICorner", { CornerRadius = UDim.new(1, 0) }),
		New("UIAspectRatioConstraint", { AspectRatio = 0.982661605, AspectType = Enum.AspectType.ScaleWithParentSize, DominantAxis = Enum.DominantAxis.Height }),
	})
	local hit = New("TextButton", { Name = "hit", BackgroundTransparency = 1, Text = "", Size = UDim2.new(1, 0, 1, 0), ZIndex = 3, Parent = pill })

	local function render(on, instant)
		local x = on and UDim2.new(1, -knob.AbsoluteSize.X + 1, 0, 0) or UDim2.new(-0.0038596706, 0, 0, 0)
		if on and knob.AbsoluteSize.X == 0 then x = UDim2.new(0.69, 0, 0, 0) end
		local off = on and Vector2.new(-1, 0) or Vector2.new(1, 0)
		if instant then
			knob.Position, pillGrad.Offset = x, off
			if shadowGrad then shadowGrad.Offset = off end
		else
			tween(knob, { Position = x }); tween(pillGrad, { Offset = off })
			if shadowGrad then tween(shadowGrad, { Offset = off }) end
		end
	end
	render(o.Value, true)
	hit.MouseButton1Click:Connect(function() o:Set(not o.Value) end)
	o._ui[#o._ui + 1] = function(v) render(v, false) end
	pill:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() render(o.Value, true) end)
	return finish(o, cfg)
end

-- ---- slider
function Section:CreateSlider(cfg)
	cfg = cfg or {}
	local window = self.Window
	local min, max = tonumber(cfg.Min) or 0, tonumber(cfg.Max) or 100
	if max <= min then max = min + 1 end
	local meta = { Min = min, Max = max, Step = tonumber(cfg.Step) or 1, Suffix = tostring(cfg.Suffix or "") }
	local o = window:_define("slider", cfg, cfg.Default, meta)
	if cfg.Default == nil then o.Value, o.Default = normalize("slider", meta, min), normalize("slider", meta, min) end
	local r = self:_row("dragFrameTemplate", 84)
	o.Row = r
	labelPair(r, tostring(cfg.Name or "Slider"), cfg.Description, UDim2.new(0.037, 0, 0, 0), UDim2.new(0.55, 0, 0.2, 0),
		UDim2.new(0.043, 0, 0.19, 0), UDim2.new(0.85, 0, 0.22, 0))
	local bar = New("Frame", {
		Name = "scrollFrame", BackgroundColor3 = WHITE, BorderSizePixel = 0,
		Position = UDim2.new(0.0255474448, 0, 0.575684726, 0), Size = UDim2.new(0.952554762, 0, 0.270676702, 0), Parent = r,
	}, {
		New("UICorner", { CornerRadius = UDim.new(1, 0) }),
		New("UIGradient", { Color = ColorSequence.new(Color3.new(0.541176498, 0.541176498, 0.541176498), WHITE) }),
		New("UIShadow", { BlurRadius = UDim.new(0, 20), Transparency = 0.5 }, { New("UIGradient", { Color = RED_GREEN }) }),
	})
	local knob = New("ImageButton", {
		Name = "dragButton", BackgroundTransparency = 1, BorderSizePixel = 0, Image = "rbxassetid://136279142593661",
		Position = UDim2.new(0, 0, -0.277777791, 0), Size = UDim2.new(0.107771732, 0, 1.41527808, 0), Parent = bar,
	}, {
		New("UICorner", { CornerRadius = UDim.new(1, 0) }),
		New("UIStroke", { Color = Color3.new(0.478431404, 0.478431404, 0.478431404) }),
		New("UIShadow", { BlurRadius = UDim.new(0, 20), Transparency = 0.5 }),
	})
	local amount = New("TextLabel", {
		Name = "amount", BackgroundTransparency = 1, BorderSizePixel = 0, FontFace = FONT, Text = "", TextColor3 = WHITE,
		TextScaled = true, Position = UDim2.new(0.13, 0, 0.1, 0), Size = UDim2.new(0.751141369, 0, 0.803729236, 0), Parent = knob,
	}, { New("UIStroke"), New("UITextSizeConstraint", { MaxTextSize = 25 }) })

	local knobScale = New("UIScale", { Scale = 1, Parent = knob })
	local knobStroke = knob:FindFirstChildOfClass("UIStroke")
	local barShadow = bar:FindFirstChildOfClass("UIShadow")
	local kw = knob.Size.X.Scale
	local function fraction(v) return (v - meta.Min) / (meta.Max - meta.Min) end
	local shown = fraction(o.Value) -- smoothed handle position, 0..1
	local goal = shown
	local function place(a) knob.Position = UDim2.new(a * (1 - kw), 0, -0.277777791, 0) end
	local function glide(dt)
		shown += (goal - shown) * (1 - math.exp(-dt * 24))
		if math.abs(goal - shown) < 0.0004 then shown = goal end
		place(shown)
		return shown == goal
	end
	place(shown)
	amount.Text = string.format("%g", o.Value) .. meta.Suffix
	o._ui[#o._ui + 1] = function(v)
		goal = fraction(v)
		amount.Text = string.format("%g", v) .. meta.Suffix
		window._animating[glide] = true
	end

	-- hold feedback: the handle swells, its rim thickens and the bar glows while it is held
	local function setHeld(held)
		tween(knobScale, { Scale = held and 1.28 or 1 }, held and POP or TWEEN)
		if knobStroke then tween(knobStroke, { Thickness = held and 2.5 or 1 }, FAST) end
		if barShadow then tween(barShadow, { Transparency = held and 0.15 or 0.5 }, FAST) end
	end

	local dragging = false
	local function fromX(x)
		local kwPx = bar.AbsoluteSize.X * kw -- unscaled handle width, independent of the hold animation
		local w = math.max(bar.AbsoluteSize.X - kwPx, 1)
		local a = math.clamp((x - bar.AbsolutePosition.X - kwPx / 2) / w, 0, 1)
		o:Set(meta.Min + a * (meta.Max - meta.Min))
	end
	local function began(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if not dragging then setHeld(true) end
			dragging = true
			fromX(input.Position.X)
		end
	end
	knob.InputBegan:Connect(began)
	bar.InputBegan:Connect(began)
	window:_connect(UserInputService.InputChanged, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			fromX(input.Position.X)
		end
	end)
	window:_connect(UserInputService.InputEnded, function(input)
		if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and dragging then
			dragging = false
			setHeld(false)
		end
	end)
	return finish(o, cfg)
end

-- ---- dropdown
function Section:CreateDropdown(cfg)
	cfg = cfg or {}
	local window = self.Window
	local items = {}
	for _, v in ipairs(cfg.Options or cfg.Items or {}) do items[#items + 1] = tostring(v) end
	local meta = { Items = items, AllowCustom = cfg.AllowCustom == true }
	local o = window:_define("dropdown", cfg, cfg.Default or "", meta)

	local ROW_H, ITEM_H, PAD, MAX_VISIBLE = 84, 28, 4, 5
	local r = self:_row("dropBoxTemplate", ROW_H)
	o.Row = r
	r.ClipsDescendants = true
	local head = New("Frame", { Name = "head", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, ROW_H), Parent = r })
	labelPair(head, tostring(cfg.Name or "Dropdown"), cfg.Description, UDim2.new(0.037, 0, 0.06, 0), UDim2.new(0.5, 0, 0.25, 0),
		UDim2.new(0.043, 0, 0.31, 0), UDim2.new(0.5, 0, 0.45, 0))
	local pill = New("Frame", {
		Name = "selectBox", BackgroundColor3 = WHITE, BorderSizePixel = 0,
		Position = UDim2.new(0.55, 0, 0, 8), Size = UDim2.new(0.42, 0, 0, 30), Parent = head,
	}, {
		New("UICorner", { CornerRadius = UDim.new(1, 0) }),
		New("UIShadow", { BlurRadius = UDim.new(0, 20), Color = WHITE, Transparency = 0.5 }),
	})
	local selected = New("TextLabel", {
		Name = "selectedType", BackgroundTransparency = 1, BorderSizePixel = 0, FontFace = FONT, Text = "", TextColor3 = BLACK,
		TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.new(0.129037112, 0, 0.227917805, 0), Size = UDim2.new(0.58, 0, 0.63, 0), Parent = pill,
	}, { New("UITextSizeConstraint", { MaxTextSize = 20 }) })
	local arrow = New("TextLabel", {
		Name = "icon", BackgroundTransparency = 1, BorderSizePixel = 0, FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json"),
		Text = "\194\187", TextColor3 = BLACK, TextScaled = true, Rotation = 90,
		Position = UDim2.new(0.65, 0, 0, 0), Size = UDim2.new(0.35, 0, 1, 0), Parent = pill,
	}, { New("UITextSizeConstraint", { MaxTextSize = 32 }) })
	local click = New("TextButton", { Name = "hit", BackgroundTransparency = 1, Text = "", Size = UDim2.new(1, 0, 1, 0), ZIndex = 3, Parent = pill })
	local list = New("ScrollingFrame", {
		Name = "selectBoxDrop", Active = true, BackgroundColor3 = WHITE, BorderSizePixel = 0, ClipsDescendants = true, Visible = false,
		Position = UDim2.new(0.55, 0, 0, 44), Size = UDim2.new(0.42, 0, 0, 0), ScrollBarThickness = 3, ScrollBarImageColor3 = BLACK,
		CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = r,
	}, {
		New("UICorner", { CornerRadius = UDim.new(0, 4) }),
		New("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, PAD), SortOrder = Enum.SortOrder.LayoutOrder }),
		New("UIPadding", { PaddingTop = UDim.new(0, PAD), PaddingBottom = UDim.new(0, PAD) }),
	})

	local buttons = {}
	local isOpen = false
	local function listHeight() return math.min(#meta.Items, MAX_VISIBLE) * (ITEM_H + PAD) + PAD end
	local function refreshSelected()
		selected.Text = (o.Value ~= "" and o.Value) or "Select"
		for name, b in pairs(buttons) do
			b.TextColor3 = (name == o.Value) and Color3.fromRGB(30, 140, 60) or BLACK
		end
	end
	local function resize()
		if isOpen then
			local h = listHeight()
			tween(list, { Size = UDim2.new(0.42, 0, 0, h) })
			tween(r, { Size = UDim2.new(1, 0, 0, ROW_H + h + 4) })
		end
	end
	local function setOpen(v)
		isOpen = v
		if v then
			list.Visible = true
			resize()
			tween(arrow, { Rotation = -90 })
		else
			tween(list, { Size = UDim2.new(0.42, 0, 0, 0) })
			tween(r, { Size = UDim2.new(1, 0, 0, ROW_H) })
			tween(arrow, { Rotation = 90 })
			task.delay(0.25, function() if not isOpen and list.Parent then list.Visible = false end end)
		end
	end
	local function rebuild()
		for _, b in pairs(buttons) do b:Destroy() end
		buttons = {}
		for i, text in ipairs(meta.Items) do
			local b = glassButton({ Name = "selectButton", Text = text, LayoutOrder = i, Size = UDim2.new(0.9, 0, 0, ITEM_H), Parent = list })
			buttons[text] = b
			b.MouseButton1Click:Connect(function()
				o:Set(text)
				setOpen(false)
			end)
		end
		refreshSelected()
		resize()
	end
	click.MouseButton1Click:Connect(function()
		if type(cfg.Refresh) == "function" then
			local ok, newItems = pcall(cfg.Refresh)
			if ok and type(newItems) == "table" then
				meta.Items = {}
				for _, v in ipairs(newItems) do meta.Items[#meta.Items + 1] = tostring(v) end
				rebuild()
			end
		end
		setOpen(not isOpen)
	end)
	o._ui[#o._ui + 1] = refreshSelected
	o._refresh = function(newItems)
		meta.Items = {}
		for _, v in ipairs(newItems or {}) do meta.Items[#meta.Items + 1] = tostring(v) end
		rebuild()
	end
	rebuild()
	return finish(o, cfg)
end

-- ---- textbox
function Section:CreateTextbox(cfg)
	cfg = cfg or {}
	local window = self.Window
	local o = window:_define("textbox", cfg, cfg.Default or "", { MaxLength = tonumber(cfg.MaxLength) or 64 })
	local r = self:_row("txtBoxTemplate", 70)
	o.Row = r
	labelPair(r, tostring(cfg.Name or "Textbox"), cfg.Description, UDim2.new(0.037, 0, 0.02, 0), UDim2.new(0.55, 0, 0.26, 0),
		UDim2.new(0.043, 0, 0.27, 0), UDim2.new(0.9, 0, 0.25, 0))
	local box = New("TextBox", {
		Name = "txtBox", BackgroundColor3 = Color3.new(0.36470589, 0.36470589, 0.36470589), BackgroundTransparency = 0.55, BorderSizePixel = 0,
		FontFace = FONT, PlaceholderColor3 = Color3.new(0.498039216, 0.498039216, 0.498039216), PlaceholderText = tostring(cfg.Placeholder or ""),
		Position = UDim2.new(0.045353435, 0, 0.56, 0), Size = UDim2.new(0.897163093, 0, 0.38, 0), Text = o.Value,
		TextColor3 = BLACK, TextScaled = true, ClearTextOnFocus = false, Parent = r,
	}, {
		New("UICorner", { CornerRadius = UDim.new(1, 0) }),
		New("UIStroke", { Color = Color3.new(0.784313798, 0.784313798, 0.784313798), Thickness = 0.5 }),
		New("UIShadow", { BlurRadius = UDim.new(0, 20), Color = WHITE, Transparency = 0.5 }),
		New("UITextSizeConstraint", { MaxTextSize = 15 }),
	})
	box.FocusLost:Connect(function()
		o:Set(box.Text)
		box.Text = o.Value
	end)
	o._ui[#o._ui + 1] = function(v) box.Text = v end
	return finish(o, cfg)
end

-- ---- button
function Section:CreateButton(cfg)
	cfg = cfg or {}
	local r = self:_row("ButtonTemplate", 52)
	local obj = setmetatable({ Kind = "button", Window = self.Window, Row = r, _ui = {}, _user = {} }, Element)
	labelPair(r, tostring(cfg.Name or "Button"), cfg.Description, UDim2.new(0.04, 0, 0.03, 0), UDim2.new(0.55, 0, 0.42, 0),
		UDim2.new(0.043, 0, 0.45, 0), UDim2.new(0.55, 0, 0.5, 0))
	local b = glassButton({
		Name = "selectButton", Text = tostring(cfg.ButtonText or "Run"), Position = UDim2.new(0.64, 0, 0.2, 0), Size = UDim2.new(0.33, 0, 0.6, 0), Parent = r,
	}, UDim.new(1, 0))
	b.MouseButton1Click:Connect(function()
		if type(cfg.Callback) == "function" then
			local ok, err = pcall(cfg.Callback)
			if not ok then warn("[ARNZ UI] button error: " .. tostring(err)) end
		end
	end)
	obj._setText = function(t) b.Text = t end
	return obj
end

-- ---- label
function Section:CreateLabel(cfg)
	cfg = type(cfg) == "table" and cfg or { Name = tostring(cfg) }
	local r = self:_row("LabelTemplate", 52)
	local obj = setmetatable({ Kind = "label", Window = self.Window, Row = r, _ui = {}, _user = {} }, Element)
	labelPair(r, tostring(cfg.Name or ""), cfg.Description, UDim2.new(0.04, 0, 0.03, 0), UDim2.new(0.9, 0, 0.42, 0),
		UDim2.new(0.043, 0, 0.45, 0), UDim2.new(0.9, 0, 0.5, 0))
	obj._setText = function(t) r.headerText.Text = t end
	return obj
end

-- ---- color picker
function Section:CreateColorPicker(cfg)
	cfg = cfg or {}
	local window = self.Window
	local o = window:_define("color", cfg, cfg.Default or WHITE, {})
	local ROW_H, PANEL_H = 84, 150
	local r = self:_row("colorTemplate", ROW_H)
	o.Row = r
	r.ClipsDescendants = true
	local head = New("Frame", { Name = "head", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, ROW_H), Parent = r })
	labelPair(head, tostring(cfg.Name or "Color"), cfg.Description, UDim2.new(0.037, 0, 0.06, 0), UDim2.new(0.5, 0, 0.25, 0),
		UDim2.new(0.043, 0, 0.31, 0), UDim2.new(0.5, 0, 0.45, 0))
	local swatch = New("Frame", {
		Name = "swatch", BackgroundColor3 = o.Value, BorderSizePixel = 0,
		Position = UDim2.new(0.55, 0, 0, 8), Size = UDim2.new(0.42, 0, 0, 30), Parent = head,
	}, {
		New("UICorner", { CornerRadius = UDim.new(1, 0) }),
		New("UIStroke", { Color = WHITE, Thickness = 1.5, Transparency = 0.35 }),
		New("UIShadow", { BlurRadius = UDim.new(0, 20), Color = WHITE, Transparency = 0.5 }),
	})
	local hexLabel = New("TextLabel", {
		Name = "hex", BackgroundTransparency = 1, BorderSizePixel = 0, FontFace = FONT, Text = "", TextColor3 = BLACK,
		TextScaled = true, Position = UDim2.new(0.1, 0, 0.2, 0), Size = UDim2.new(0.8, 0, 0.6, 0), Parent = swatch,
	}, { New("UITextSizeConstraint", { MaxTextSize = 16 }) })
	local click = New("TextButton", { Name = "hit", BackgroundTransparency = 1, Text = "", Size = UDim2.new(1, 0, 1, 0), ZIndex = 3, Parent = swatch })

	local panel = New("Frame", {
		Name = "panel", BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, ROW_H - 6), Size = UDim2.new(1, 0, 0, PANEL_H), Parent = r,
	})
	local sv = New("Frame", {
		Name = "sv", BackgroundColor3 = WHITE, BorderSizePixel = 0,
		Position = UDim2.new(0.043, 0, 0, 0), Size = UDim2.new(0.66, 0, 0, PANEL_H - 14), Parent = panel,
	}, { New("UICorner", { CornerRadius = UDim.new(0, 8) }) })
	New("Frame", {
		Name = "sat", BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = sv,
	}, { New("UICorner", { CornerRadius = UDim.new(0, 8) }), New("UIGradient", { Transparency = NumberSequence.new(0, 1) }) })
	New("Frame", {
		Name = "val", BackgroundColor3 = BLACK, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Parent = sv,
	}, { New("UICorner", { CornerRadius = UDim.new(0, 8) }), New("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0) }) })
	local svCursor = New("Frame", {
		Name = "cursor", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.fromOffset(12, 12), ZIndex = 5, Parent = sv,
	}, { New("UICorner", { CornerRadius = UDim.new(1, 0) }), New("UIStroke", { Color = WHITE, Thickness = 2 }) })

	local hueKeys = {}
	for i = 0, 6 do hueKeys[#hueKeys + 1] = ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i == 6 and 0 or i / 6, 1, 1)) end
	local hue = New("Frame", {
		Name = "hue", BackgroundColor3 = WHITE, BorderSizePixel = 0,
		Position = UDim2.new(0.75, 0, 0, 0), Size = UDim2.new(0.11, 0, 0, PANEL_H - 14), Parent = panel,
	}, { New("UICorner", { CornerRadius = UDim.new(0, 8) }), New("UIGradient", { Rotation = 90, Color = ColorSequence.new(hueKeys) }) })
	local hueCursor = New("Frame", {
		Name = "cursor", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = UDim2.new(1, 6, 0, 8), ZIndex = 5, Parent = hue,
	}, { New("UICorner", { CornerRadius = UDim.new(1, 0) }), New("UIStroke", { Color = WHITE, Thickness = 2 }) })

	local h, s, v = o.Value:ToHSV()
	local internal, drag = false, nil
	local function apply()
		local c = Color3.fromHSV(h, s, v)
		sv.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
		svCursor.Position = UDim2.fromScale(s, 1 - v)
		hueCursor.Position = UDim2.fromScale(0.5, h)
		swatch.BackgroundColor3 = c
		hexLabel.Text = color3ToHex(c)
		hexLabel.TextColor3 = (0.299 * c.R + 0.587 * c.G + 0.114 * c.B) > 0.6 and BLACK or WHITE
	end
	local function commit()
		apply()
		internal = true
		o:Set(Color3.fromHSV(h, s, v))
		internal = false
	end
	local function update()
		local m = UserInputService:GetMouseLocation()
		local x, y = m.X, m.Y - window._guiInsetOffset()
		if drag == "sv" then
			s = math.clamp((x - sv.AbsolutePosition.X) / math.max(sv.AbsoluteSize.X, 1), 0, 1)
			v = 1 - math.clamp((y - sv.AbsolutePosition.Y) / math.max(sv.AbsoluteSize.Y, 1), 0, 1)
		elseif drag == "hue" then
			h = math.clamp((y - hue.AbsolutePosition.Y) / math.max(hue.AbsoluteSize.Y, 1), 0, 0.999)
		else
			return
		end
		commit()
	end
	local function began(which)
		return function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				drag = which
				update()
			end
		end
	end
	sv.InputBegan:Connect(began("sv"))
	hue.InputBegan:Connect(began("hue"))
	window:_connect(UserInputService.InputChanged, function(input)
		if drag and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then update() end
	end)
	window:_connect(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then drag = nil end
	end)

	o._ui[#o._ui + 1] = function(color)
		if internal then return end
		h, s, v = color:ToHSV()
		apply()
	end
	local isOpen = false
	click.MouseButton1Click:Connect(function()
		isOpen = not isOpen
		tween(r, { Size = UDim2.new(1, 0, 0, ROW_H + (isOpen and PANEL_H or 0)) })
	end)
	apply()
	return finish(o, cfg)
end

-- ---- keybind (click, then press a key or a mouse button; Esc / Backspace clears)
function Section:CreateKeybind(cfg)
	cfg = cfg or {}
	local window = self.Window
	local o = window:_define("keybind", cfg, cfg.Default or "None", {})
	if type(cfg.Pressed) == "function" then o._pressed = cfg.Pressed end
	local r = self:_row("KeybindTemplate", 52)
	o.Row = r
	labelPair(r, tostring(cfg.Name or "Keybind"), cfg.Description, UDim2.new(0.04, 0, 0.03, 0), UDim2.new(0.55, 0, 0.42, 0),
		UDim2.new(0.043, 0, 0.45, 0), UDim2.new(0.55, 0, 0.5, 0))
	local b = glassButton({
		Name = "selectButton", Text = o.Value, Position = UDim2.new(0.64, 0, 0.2, 0), Size = UDim2.new(0.33, 0, 0.6, 0), Parent = r,
	}, UDim.new(1, 0))
	local function render() b.Text = o.Value end
	o._ui[#o._ui + 1] = render
	b.MouseButton1Click:Connect(function()
		if window._listening then return end
		b.Text = "..."
		window._listening = function(input)
			local name
			if input.UserInputType == Enum.UserInputType.Keyboard then
				if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Backspace then name = "None" else name = input.KeyCode.Name end
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.MouseButton3 then
				name = input.UserInputType.Name
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
				name = o.Value -- clicking elsewhere cancels
			else
				return
			end
			window._listening = nil
			if not o:Set(name) then render() end
			render()
		end
	end)
	window._keybinds[#window._keybinds + 1] = o
	return finish(o, cfg)
end

-- ================================================================== built-in tabs
function Window:CreateSettingsTab(name, icon)
	local tab = self:CreateTab(name or "Settings", icon or "sliders")
	local ui = tab:CreateSection("Interface", "Look and feel of this menu.")
	ui:CreateKeybind({
		Name = "Menu Key", Description = "Shows or hides the menu.", Flag = "ui.menuKey", Default = self.MenuKey,
		Callback = function(k)
			if not self:SetMenuKey(k) then self.Elements["ui.menuKey"]:Set(self.MenuKey, true) end
		end,
	})
	ui:CreateSlider({
		Name = "Scale", Description = "Menu size multiplier.", Flag = "ui.scale", Min = 0.7, Max = 1.3, Step = 0.05,
		Default = self._uiScale.Scale, Callback = function(v) self:SetScale(v) end,
	})
	ui:CreateSlider({
		Name = "Glass", Description = "Card transparency. Higher is clearer.", Flag = "ui.glass", Min = 0.2, Max = 0.9, Step = 0.05,
		Default = self._glass, Callback = function(v) self:SetGlass(v) end,
	})
	ui:CreateToggle({
		Name = "Menu Blur", Description = "Blurs the game while the menu is open.", Flag = "ui.blur", Default = self._blurOn,
		Callback = function(v) self:SetBlur(v) end,
	})
	local script = tab:CreateSection("Script", "ARNZ UI Library " .. Library.Version)
	script:CreateButton({
		Name = "Unload", Description = "Removes the menu and everything it created.", ButtonText = "Unload",
		Callback = function() self:Destroy() end,
	})
	return tab
end

function Window:CreateConfigTab(name, icon)
	local tab = self:CreateTab(name or "Config", icon or "disk")
	local config = self.Config
	local profiles = tab:CreateSection("Profiles", "JSON files in " .. config.Dir .. ".")
	local nameBox = profiles:CreateTextbox({
		Name = "Name", Description = "Used by Save, Load and Delete.", Placeholder = "config name", Default = config.Current, MaxLength = 32,
		Callback = function(v)
			local n = cleanName(v)
			if n then config.Current = n end
		end,
	})
	local saved
	saved = profiles:CreateDropdown({
		Name = "Saved", Description = "Pick a file to fill the name.", Options = config:List(), Refresh = function() return config:List() end,
		Callback = function(v) if v ~= "" then nameBox:Set(v) end end,
	})
	local function refresh() saved:Refresh(config:List()) end
	profiles:CreateButton({
		Name = "Save", Description = "Writes every setting to the named file.", ButtonText = "Save",
		Callback = function()
			local ok, res = config:Save(nameBox.Value)
			if ok then refresh() end
			self:Notify(ok and ("Saved " .. res) or ("Save failed: " .. tostring(res)))
		end,
	})
	profiles:CreateButton({
		Name = "Load", Description = "Applies the named file.", ButtonText = "Load",
		Callback = function()
			local ok, res = config:Load(nameBox.Value)
			self:Notify(ok and ("Loaded " .. tostring(res) .. " values") or ("Load failed: " .. tostring(res)))
		end,
	})
	profiles:CreateButton({
		Name = "Delete", Description = "Removes the named file.", ButtonText = "Delete",
		Callback = function()
			local ok, res = config:Delete(nameBox.Value)
			if ok then refresh() end
			self:Notify(ok and ("Deleted " .. res) or ("Delete failed: " .. tostring(res)))
		end,
	})
	local auto = tab:CreateSection("Automation", "Remembered between sessions in " .. config.MetaPath .. ".")
	auto:CreateToggle({
		Name = "Auto Save", Description = "Saves the named file whenever a setting changes.", Default = config.Meta.autosave,
		Callback = function(v) config:SetAutoSave(v) end,
	})
	auto:CreateToggle({
		Name = "Auto Load", Description = "Loads the last used file on LoadAutoConfig().", Default = config.Meta.autoload,
		Callback = function(v) config:SetAutoLoad(v) end,
	})
	auto:CreateButton({
		Name = "Copy JSON", Description = "Copies the current settings as JSON.", ButtonText = "Copy",
		Callback = function()
			if setclipboard then
				setclipboard(config:Export())
				self:Notify("Copied to clipboard")
			else
				self:Notify("setclipboard is not available")
			end
		end,
	})
	auto:CreateButton({
		Name = "Import JSON", Description = "Applies settings JSON from the clipboard.", ButtonText = "Import",
		Callback = function()
			if not getclipboard then self:Notify("getclipboard is not available") return end
			local ok, res = config:Import(getclipboard())
			self:Notify(ok and ("Imported " .. tostring(res) .. " values") or ("Import failed: " .. tostring(res)))
		end,
	})
	if not config.Available then self:Notify("File functions unavailable: configs cannot be saved here") end
	return tab
end

-- ================================================================== finish
for _, class in ipairs({ Window, Tab, Section, Element, ConfigManager }) do addAliases(class) end
addAliases(Library)

genv.ARNZ_LIBRARY = Library
return Library
