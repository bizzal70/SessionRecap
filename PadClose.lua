local _, ns = ...

-- The controller's B button (PAD2) closes this addon's windows, as Escape
-- and their X do: while a window is shown, B is bound to closing it, and it
-- gets its usual job back once the window hides. Bindings cannot change in
-- combat, so a change that falls in combat waits until it ends.

local padWindows = {}
local padFrame = CreateFrame("Frame")

local function PadApply(window)
    if not (SetOverrideBinding and ClearOverrideBindings) then return end
    if InCombatLockdown and InCombatLockdown() then
        padFrame.waiting = true
        return
    end
    ClearOverrideBindings(window)
    if window:IsShown() then
        SetOverrideBinding(window, true, "PAD2", "CLICK " .. window.padCloseName .. ":LeftButton")
    end
end

padFrame:SetScript("OnEvent", function(self)
    if not self.waiting then return end
    self.waiting = false
    for _, window in ipairs(padWindows) do pcall(PadApply, window) end
end)
pcall(padFrame.RegisterEvent, padFrame, "PLAYER_REGEN_ENABLED")

-- window: the frame; name: its global name.
function ns.CloseWithPadB(window, name)
    if not window or type(name) ~= "string" or window.padCloseName then return end
    -- An invisible button for the binding to press: never placed on screen,
    -- and not clickable with the mouse.
    window.padCloseName = name .. "PadClose"
    local close = CreateFrame("Button", window.padCloseName, UIParent)
    close:EnableMouse(false)
    close:SetScript("OnClick", function() window:Hide() end)
    window.padClose = close
    padWindows[#padWindows + 1] = window
    window:HookScript("OnShow", function(self) pcall(PadApply, self) end)
    window:HookScript("OnHide", function(self) pcall(PadApply, self) end)
end
