# ARNZ UI Library

An iOS-style "liquid glass" UI library for Roblox executors (Luau). The look and layout are rebuilt from the `StarterGui.ARNZ` design. It has no game logic: you build windows, tabs, sections and elements, and it handles animation, config saving and notifications.

- Version: 1.0.0
- Font: Builder Extended ExtraBold (`rbxassetid://16658237174`)
- Written for Madium. Needs `gethui` or CoreGui access. Config saving needs `writefile`, `readfile`, `isfile`, `isfolder`, `makefolder`, `listfiles` and `delfile`.
- Status: syntax-checked only. Not yet run in a live client.

## Install

Put `ARNZ_Library.lua` in your executor workspace folder, then:

```lua
local ARNZ = loadstring(readfile("ARNZ_Library.lua"))()
```

`ARNZ_Example.lua` shows every element in use.

## Quick start

```lua
local ARNZ = loadstring(readfile("ARNZ_Library.lua"))()

local Window = ARNZ:CreateWindow({
    Name = "My Script",
    ConfigFolder = "MyScript",
    MenuKey = "RightShift",
})

local Tab = Window:CreateTab("Main", "aim")
local Section = Tab:CreateSection("Combat", "Example section.")

Section:CreateToggle({
    Name = "Enabled", Flag = "enabled", Default = false,
    Callback = function(v) print("Enabled:", v) end,
})

Window:CreateSettingsTab("Settings", "sliders")
Window:CreateConfigTab("Config", "disk")
Window:LoadAutoConfig() -- call once, after every element exists
```

Every method also works in lowerCamelCase: `ARNZ:createWindow`, `Window:createTab`, `Tab:createSection`, `Section:createToggle`, and so on.

## Window

`ARNZ:CreateWindow(config)`

| Option | Default | Meaning |
|---|---|---|
| `Name` | `"ARNZ"` | Window id. Creating a window with the same name destroys the old one, so re-running a script is safe. |
| `ConfigFolder` | `Name` | Workspace folder for configs. |
| `MenuKey` | `RightShift` | Key that shows or hides the menu. KeyCode name or `Enum.KeyCode`. |
| `Scale` | `1` | Menu size multiplier (0.5 to 2). |
| `Glass` | `0.5` | Card transparency (0 to 1). Higher is clearer. |
| `Blur` | `true` | Blur the game while the menu is open. |
| `Visible` | `true` | Initial visibility. |
| `DefaultConfig` | `"default"` | Config name used before any has been saved. |
| `Size`, `Position` | design values | `UDim2` overrides. |

Window methods:

| Method | Purpose |
|---|---|
| `CreateTab(name, icon)` | Adds a tab and returns it. |
| `CreateSettingsTab(name, icon)` | Built-in tab: menu key, scale, glass, blur, unload. |
| `CreateConfigTab(name, icon)` | Built-in tab: profiles, auto save, auto load, copy and import JSON. |
| `SelectTab(name)` | Switches tab with the animation. |
| `Notify(text, seconds)` or `Notify({Text=, Duration=})` | Stacking toast at the bottom. |
| `SetVisible(bool)`, `Toggle()` | Show or hide. |
| `SetMenuKey(key)`, `SetScale(n)`, `SetGlass(n)`, `SetBlur(bool)` | Change the look at runtime. |
| `GetFlag(flag)`, `SetFlag(flag, value, silent)` | Read or write an element by flag. |
| `LoadAutoConfig()` | Loads the last config if Auto Load is on. |
| `OnDestroy(fn)` | Cleanup callback, run on destroy. |
| `Destroy()` | Removes the menu, connections and blur. |

Fields: `Window.Flags[flag]` (current values), `Window.Elements[flag]` (element objects), `Window.Config` (config manager).

## Tabs and sections

```lua
local Tab = Window:CreateTab("Visuals", "eye")
local Section = Tab:CreateSection("Title", "Short description")
```

Built-in icons: `eye`, `aim`, `sliders`, `disk`, `grid`, `circle`. You can also pass `"rbxassetid://123"` or a number. Add your own with:

```lua
ARNZ:RegisterIcon("plus", function(shape)
    -- shape(x, y, width, height, corner, filled), all values are 0..1 scales
    shape(0.5, 0.5, 0.8, 0.12, 1, true)
    shape(0.5, 0.5, 0.12, 0.8, 1, true)
end)
```

Tab buttons resize automatically to fit the number of tabs.

## Elements

Every creator takes one table. Common options:

| Option | Meaning |
|---|---|
| `Name`, `Description` | Title and small text. |
| `Flag` | Makes the value readable from `Window.Flags` and saveable in configs. |
| `Default` | Initial value. |
| `Callback` | Called with the new value when it changes. |
| `Persist` | `false` keeps a flagged element out of saved configs. |
| `RunOnCreate` | `true` fires the callback once with the default. |

| Creator | Extra options | Value |
|---|---|---|
| `CreateToggle` | | `boolean` |
| `CreateSlider` | `Min`, `Max`, `Step`, `Suffix` | `number`, snapped to `Step` |
| `CreateDropdown` | `Options`, `AllowCustom`, `Refresh` (function returning a list) | `string` |
| `CreateTextbox` | `Placeholder`, `MaxLength` | `string` |
| `CreateColorPicker` | | `Color3` (saved as `#RRGGBB`) |
| `CreateKeybind` | `Pressed` (called on key press; `Callback` fires when the binding changes) | key name, or `"None"` |
| `CreateButton` | `ButtonText` | none |
| `CreateLabel` | | none |

Element methods:

| Method | Purpose |
|---|---|
| `:Get()` | Current value. |
| `:Set(value, silent)` | Returns `true` if accepted. `silent = true` skips callbacks. |
| `:Reset()` | Back to the default. |
| `:OnChanged(fn)` | Add another listener. |
| `:Fire()` | Run callbacks with the current value. |
| `:SetVisible(bool)` | Show or hide the row. |
| `:Destroy()` | Remove the element. |
| `:Refresh(list)` | Dropdown: replace the options. |
| `:SetRange(min, max)` | Slider: change the range. |
| `:IsDown()` | Keybind: whether the key is held. |
| `:SetText(text)` | Button and label: change the text. |

Keybinds: click the button, then press a key or mouse button 2 or 3. Escape or Backspace clears it. Clicking with the left mouse button cancels.

Invalid values passed to `Set` are rejected, not clamped silently into something else, except sliders, which clamp and snap.

## Configs

- Files live in `<ConfigFolder>/configs/<name>.json` (schema 1).
- Auto Save, Auto Load and the last used name live in `<ConfigFolder>/meta.json`.
- Only elements with a `Flag` are saved. Flags must be unique per window; a duplicate flag is warned about and that element is not saved.
- Auto Save writes the current profile 0.8 seconds after the last change.

```lua
Window.Config:Save("legit")
Window.Config:Load("legit")
Window.Config:Delete("legit")
Window.Config:List()          --> { "legit", ... }
Window.Config:Export()        --> JSON string
Window.Config:Import(json)
Window.Config:SetAutoSave(true)
Window.Config:SetAutoLoad(true)
```

`Save`, `Load`, `Delete` and `Import` return `ok, result_or_error`. Call `Window:LoadAutoConfig()` after all elements are created, otherwise there is nothing to apply the values to.

## Notes

- If the client has no `UIShadow` support, shadows are skipped and the layout still builds.
- If file functions are missing, the library still works, but configs cannot be saved and the Config tab says so.
- The library also sets `getgenv().ARNZ_LIBRARY` and keeps open windows in `getgenv().__ARNZ_UI_WINDOWS`.
- The color picker reads the mouse in viewport space and corrects for the top-bar inset. If it picks the wrong spot in your client, that offset is the first thing to check.

## Known limits

- Not run in a live client yet: dropdown, color picker and keybind capture are untested in-game.
- Tab pages scroll horizontally, and each section is a fixed 340 px wide card.
