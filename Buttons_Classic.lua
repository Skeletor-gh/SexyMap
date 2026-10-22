
local _, sm = ...
sm.buttons = {}

local mod = sm.buttons
local L = sm.L
local ldbi = LibStub("LibDBIcon-1.0")

local moving, ButtonFadeOut

local animFrames = {}
local managedFrames = {} -- Button name -> frame that gets positioned
local addonButtons = {} -- Non-LibDBIcon addon buttons we have taken ownership of
local blizzButtons = {
	GameTimeFrame = sm.API.isVanilla and L.dayNightButton or sm.API.isTBC and L.dayNightButton or L["Calendar"],
	MiniMapTracking = L["Tracking Button"],
	SexyMapZoneTextButton = L["Zone Text"],
	MinimapZoomIn = L["Zoom In Button"],
	MinimapZoomOut = L["Zoom Out Button"],
	MiniMapWorldMapButton = MiniMapWorldMapButton and L["Map Button"] or nil,
	TimeManagerClockButton = L["Clock"],
}
local dynamicButtons = {
	MiniMapChallengeMode = MiniMapChallengeMode and L["Challenge Mode Button (When Available)"] or nil,
	GuildInstanceDifficulty = GuildInstanceDifficulty and L["Guild Dungeon Difficulty Indicator (When Available)"] or nil,
	MiniMapInstanceDifficulty = MiniMapInstanceDifficulty and L["Dungeon Difficulty Indicator (When Available)"] or nil,
	MiniMapMailFrame = L["New Mail Indicator (When Available)"],
	MiniMapBattlefieldFrame = L.classicPVPButton,
	--GarrisonLandingPageMinimapButton = L["Garrison Button (When Available)"],
	LFGMinimapFrame = L.classicLFGButton,
}

local options = {
	type = "group",
	name = L["Buttons"],
	childGroups = "tab",
	args = {
		custom = {
			type = "group",
			name = L["Addon Buttons"],
			args = {},
			order = 3,
		},
		dynamic = {
			type = "group",
			name = L["Dynamic Buttons"],
			args = {},
			order = 2,
		},
		stock = {
			type = "group",
			name = L["Standard Buttons"],
			args = {},
			order = 1,
		},
		enableDragging = {
			type = "toggle",
			name = L["Let SexyMap handle button dragging"],
			desc = L["Allow SexyMap to assume drag ownership for buttons attached to the minimap. Turn this off if you have another mod that you want to use to position your minimap buttons."],
			width = 2,
			order = 101,
			get = function()
				return mod.db.allowDragging
			end,
			set = function(info, v)
				mod.db.allowDragging = v
				if v then mod:UpdateDraggables() end
			end
		},
		lockDragging = {
			type = "toggle",
			name = L["Lock Button Dragging"],
			order = 102,
			disabled = function()
				return not mod.db.allowDragging
			end,
			get = function()
				return mod.db.lockDragging
			end,
			set = function(info, v)
				mod.db.lockDragging = v
			end
		},
		enforcePositions = {
			type = "toggle",
			name = L.enforcePositions,
			desc = L.enforcePositionsDesc,
			width = "full",
			order = 102.1,
			disabled = function()
				return not mod.db.allowDragging
			end,
			get = function()
				return mod.db.enforcePositions
			end,
			set = function(info, v)
				mod.db.enforcePositions = v
				if v then mod:UpdateDraggables() end
			end
		},
		dragRadius = {
			type = "range",
			name = L["Drag Radius"],
			desc = function()
				return L.radiusDesc:format(Minimap:GetWidth() / 2 + mod.db.radius)
			end,
			min = -150,
			max = 250,
			softMin = -50,
			softMax = 100,
			step = 1,
			bigStep = 1,
			order = 103,
			disabled = function()
				return not mod.db.allowDragging
			end,
			get = function()
				return mod.db.radius
			end,
			set = function(info, v)
				mod.db.radius = v
				mod:UpdateDraggables()
			end
		},
		grabAddonButtons = {
			type = "toggle",
			name = L.grabAddonButtons,
			desc = L.grabAddonButtonsDesc,
			width = "full",
			order = 103.1,
			get = function()
				return mod.db.grabAddonButtons
			end,
			set = function(info, v)
				mod.db.grabAddonButtons = v
				if v then mod:ScanForAddonButtons() end
			end
		},
		visSpacer = {
			order = 104,
			type = "header",
			name = L["Visibility"],
		},
		controlVisibility = {
			type = "toggle",
			name = L["Let SexyMap control button visibility"],
			desc = L["Turn this off if you want another mod to handle which buttons are visible on the minimap."],
			width = "full",
			order = 105,
			get = function()
				return mod.db.controlVisibility
			end,
			set = function(info, v)
				mod.db.controlVisibility = v
				for i = 1, #animFrames do
					local f = animFrames[i]
					if not v then
						mod:ChangeFrameVisibility(f, "always")
					else
						mod:ChangeFrameVisibility(f, mod.db.visibilitySettings[f:GetName()] or "hover")
					end
				end
			end
		},
	}
}

do
	local hideValues = {
		["always"] = L["Always"],
		["never"] = L["Never"],
		["hover"] = L["On Hover"],
	}

	local function visDisabled()
		return not mod.db.controlVisibility
	end

	local function dragDisabled()
		return not mod.db.allowDragging
	end

	-- Options are nested in a group per button, so the button name is the parent key
	local function hideGet(info, v)
		return (mod.db.visibilitySettings[info[#info-1]] or "hover") == v
	end

	local function hideSet(info, value)
		local name = info[#info-1]
		mod.db.visibilitySettings[name] = value
		mod:ChangeFrameVisibility(managedFrames[name] or _G[name], value)
	end

	local function angleGet(info)
		return mod:GetButtonAngle(info[#info-1])
	end

	local function angleSet(info, v)
		local name = info[#info-1]
		mod.db.dragPositions[name] = v
		mod:UpdateDraggables(managedFrames[name])
	end

	local function useGlobalGet(info)
		return not mod.db.radiusOverrides[info[#info-1]]
	end

	local function useGlobalSet(info, v)
		local name = info[#info-1]
		mod.db.radiusOverrides[name] = not v and mod.db.radius or nil
		mod:UpdateDraggables(managedFrames[name])
	end

	local function radiusGet(info)
		return mod.db.radiusOverrides[info[#info-1]] or mod.db.radius
	end

	local function radiusSet(info, v)
		local name = info[#info-1]
		mod.db.radiusOverrides[name] = v
		mod:UpdateDraggables(managedFrames[name])
	end

	local function radiusDesc(info)
		return L.radiusDesc:format(Minimap:GetWidth() / 2 + radiusGet(info))
	end

	local function radiusDisabled(info)
		return not mod.db.allowDragging or not mod.db.radiusOverrides[info[#info-1]]
	end

	function mod:AddButtonOptions(name)
		local p
		if blizzButtons[name] then
			p = options.args.stock.args -- Blizz icon = stock section
		elseif dynamicButtons[name] then
			p = options.args.dynamic.args -- Blizz dynamic (off by default) icon = dynamic section
		else
			p = options.args.custom.args -- Addon icon = custom section
		end
		p[name] = {
			type = "group",
			inline = true,
			name = blizzButtons[name] or dynamicButtons[name] or name:gsub("LibDBIcon10_", "") or "???",
			args = {
				visibility = {
					type = "multiselect",
					name = L["Visibility"],
					values = hideValues,
					get = hideGet,
					set = hideSet,
					disabled = visDisabled,
					order = 1,
				},
				angle = {
					type = "range",
					name = L.buttonAngle,
					desc = L.buttonAngleDesc,
					min = 0,
					max = 359,
					step = 1,
					get = angleGet,
					set = angleSet,
					disabled = dragDisabled,
					order = 2,
				},
				useGlobalRadius = {
					type = "toggle",
					name = L.useGlobalRadius,
					get = useGlobalGet,
					set = useGlobalSet,
					disabled = dragDisabled,
					order = 3,
				},
				radius = {
					type = "range",
					name = L.buttonRadius,
					desc = radiusDesc,
					min = -150,
					max = 250,
					softMin = -50,
					softMax = 100,
					step = 1,
					get = radiusGet,
					set = radiusSet,
					disabled = radiusDisabled,
					order = 4,
				},
			},
		}
	end
end

function mod:OnInitialize(profile)
	if type(profile.buttons) ~= "table" then
		profile.buttons = {
			radius = 10,
			dragPositions = {},
			visibilitySettings = {
				GameTimeFrame = sm.API.isVanilla and "never" or sm.API.isTBC and "never" or "hover",
				MinimapZoomIn = "never",
				MinimapZoomOut = "never",
				MiniMapWorldMapButton = "never",
				SexyMapZoneTextButton = "always",
				TimeManagerClockButton = "always",
				MiniMapMailFrame = "always",
				MiniMapBattlefieldFrame = "always",
				LFGMinimapFrame = "always",
				GarrisonLandingPageMinimapButton = "always",
			},
			allowDragging = true,
			lockDragging = false,
			controlVisibility = true
		}
	end

	self.db = profile.buttons

	-- Settings added after the initial profile layout
	if type(self.db.radiusOverrides) ~= "table" then
		self.db.radiusOverrides = {}
	end
	if self.db.enforcePositions == nil then
		self.db.enforcePositions = true
	end
	if self.db.grabAddonButtons == nil then
		self.db.grabAddonButtons = true
	end

	if self.db.tempWrathUpgrade then
		self.db.tempWrathUpgrade = nil
		if sm.API.isVanilla or sm.API.isTBC then
			self.db.visibilitySettings.GameTimeFrame = "never"
		else
			self.db.visibilitySettings.GameTimeFrame = "hover"
		end
	end
end

function mod:OnEnable()
	--GarrisonLandingPageMinimapButton:SetSize(36, 36) -- Shrink the missions button
	---- Stop Blizz changing the icon size || GarrisonLandingPageMinimapButton_UpdateIcon() >> SetLandingPageIconFromAtlases() >> self:SetSize()
	--hooksecurefunc(GarrisonLandingPageMinimapButton, "SetSize", function()
	--	sm.core.button.SetSize(GarrisonLandingPageMinimapButton, 36, 36)
	--end)
	---- Stop Blizz moving the icon || GarrisonLandingPageMinimapButton_UpdateIcon() >> ApplyGarrisonTypeAnchor() >> anchor:SetPoint()
	--hooksecurefunc("GarrisonLandingPageMinimapButton_UpdateIcon", function()
	--	mod:UpdateDraggables(GarrisonLandingPageMinimapButton)
	--end)

	sm.core:RegisterModuleOptions("Buttons", options, L["Buttons"])

	if MiniMapTrackingButton then
		-- MiniMapTrackingButton is a child of MiniMapTracking and sits on top of it eating all mouse events
		-- We need to let mouse events pass through into MiniMapTracking, so dragging actually works
		sm.core.button.SetPropagateMouseClicks(MiniMapTrackingButton, true)
		sm.core.button.SetPropagateMouseMotion(MiniMapTrackingButton, true)
	end

	if MiniMapWorldMapButton and self.db.controlVisibility then
		sm.core.button.Show(MiniMapWorldMapButton) -- Default hidden by Blizz on specific WoW flavors. Force show it initially then let the user control if they want it visible.
	end

	-- On classic (vanilla) only, when reloading UI, there's a bug where the tracking icon doesn't re-show.
	if sm.API.isVanilla then
		local icon = GetTrackingTexture()
		if icon then
			MiniMapTrackingIcon:SetTexture(icon)
			MiniMapTracking:Show()
		end
	end

	-- Frame grab is only meant to happen after LOADING_SCREEN_DISABLED
	-- This part is just a fallback in case PLAYER_LOGIN (OnEnable) somehow happens after LOADING_SCREEN_DISABLED
	if not sm.core.LOADING_SCREEN_DISABLED then -- If nil, LOADING_SCREEN_DISABLED already triggered
		self:StartFrameGrab()
	end
end

function mod:OnLoadingScreenOver()
	self:StartFrameGrab() -- This will only run if PLAYER_LOGIN (OnEnable) happens before LOADING_SCREEN_DISABLED
end

--------------------------------------------------------------------------------
-- Fading
--

local OnFinished, KillAnimation
local fadeStop = false -- Use a variable to prevent fadeout/in when moving the mouse around minimap/icons
do
	local restoreGarrisonButtonAnimation = false
	local restoreLFGButtonAnimation = false

	OnFinished = function(anim)
		-- Work around issues with buttons that have a pulse/fade ring animation.
		--if restoreGarrisonButtonAnimation and anim:GetParent():GetName() == "GarrisonLandingPageMinimapButton" then
		--	anim:GetParent().MinimapLoopPulseAnim:Play()
		--	restoreGarrisonButtonAnimation = false
		--end
		--if restoreLFGButtonAnimation and anim:GetParent():GetName() == "QueueStatusMinimapButton" then
		--	anim:GetParent().EyeHighlightAnim:Play()
		--	restoreLFGButtonAnimation = false
		--end
	end

	KillAnimation = function(n, f)
		-- Work around issues with buttons that have a pulse/fade ring animation.
		--if n == "GarrisonLandingPageMinimapButton" and (f.MinimapLoopPulseAnim:IsPlaying() or restoreGarrisonButtonAnimation) then
		--	restoreGarrisonButtonAnimation = true
		--	f.MinimapLoopPulseAnim:Stop()
		--	return f.MinimapLoopPulseAnim
		--end
		--if n == "QueueStatusMinimapButton" and (f.EyeHighlightAnim:IsPlaying() or restoreLFGButtonAnimation) then
		--	restoreLFGButtonAnimation = true
		--	f.EyeHighlightAnim:Stop()
		--	return f.EyeHighlightAnim
		--end
	end

	local OnEnter = function()
		if not mod.db.controlVisibility or fadeStop or moving then return end

		for i = 1, #animFrames do
			local f = animFrames[i]
			local n = f:GetName()
			if not mod.db.visibilitySettings[n] or mod.db.visibilitySettings[n] == "hover" then
				f.sexyMapFadeOut:Stop()

				local anim = KillAnimation(n, f)

				f:SetAlpha(1)
				if anim then
					OnFinished(anim)
				end
			end
		end
	end
	local OnLeave = function()
		if not mod.db.controlVisibility or moving then return end
		local focus = GetMouseFocus and GetMouseFocus() or GetMouseFoci and GetMouseFoci()[1] -- Minimap or Minimap icons including nil checks to compensate for other addons
		if focus and not focus:IsForbidden() and ((focus:GetName() == "Minimap") or (focus:GetParent() and focus:GetParent():GetName() and focus:GetParent():GetName():find("Mini[Mm]ap"))) then
			fadeStop = true
			return
		end
		fadeStop = false

		for i = 1, #animFrames do
			local f = animFrames[i]
			local n = f:GetName()

			if not mod.db.visibilitySettings[n] or mod.db.visibilitySettings[n] == "hover" then
				if n ~= "GameTimeFrame" or (n == "GameTimeFrame" and C_Calendar.GetNumPendingInvites() < 1) then
					f.sexyMapFadeOut:Play()

					KillAnimation(n, f)
				end
			end
		end
	end

	local hideFrame = CreateFrame("Frame") -- Dummy frame we use for hiding buttons to prevent other addons re-showing them
	hideFrame:Hide()
	function mod:NewFrame(f)
		local n = f:GetName()
		-- Only add Blizz buttons, LibDBIcon buttons & addon buttons found by :ScanForAddonButtons
		if blizzButtons[n] or dynamicButtons[n] or n:find("LibDBIcon") or addonButtons[f] then
			-- Create the animation
			f.sexyMapFadeOut = f:CreateAnimationGroup()
			local smAlphaAnimOut = f.sexyMapFadeOut:CreateAnimation("Alpha")
			smAlphaAnimOut:SetOrder(1)
			smAlphaAnimOut:SetDuration(0.2)
			smAlphaAnimOut:SetFromAlpha(1)
			smAlphaAnimOut:SetToAlpha(0)
			smAlphaAnimOut:SetStartDelay(1)
			f.sexyMapFadeOut:SetToFinalAlpha(true)
			animFrames[#animFrames+1] = f
			managedFrames[n] = f

			-- Make sure everything is parented to the Minimap and set to the correct strata and frame level
			if blizzButtons[n] or dynamicButtons[n] then
				sm.core.button.SetParent(f, Minimap)
				sm.core.button.SetFrameStrata(f, "MEDIUM")
				sm.core.button.SetFixedFrameStrata(f, true)
				sm.core.button.SetFrameLevel(f, 8)
				sm.core.button.SetFixedFrameLevel(f, true)
			elseif addonButtons[f] and f:GetParent() ~= Minimap then
				-- Positioning is done in Minimap coords, so move buttons off MinimapBackdrop, keeping their strata
				local strata = f:GetFrameStrata()
				sm.core.button.SetParent(f, Minimap)
				sm.core.button.SetFrameStrata(f, strata)
			end

			-- Correctly position frames that aren't parents to the Minimap by default
			if n == "MiniMapInstanceDifficulty" or n == "GuildInstanceDifficulty" or n == "MiniMapChallengeMode" then
				f:ClearAllPoints()
				f:SetPoint("CENTER", Minimap, "CENTER", -60, 55)
			end
			if n == "GameTimeFrame" then
				f:ClearAllPoints()
				f:SetPoint("CENTER", Minimap, "TOPRIGHT", 4, -37)
			end
			if n == "LFGMinimapFrame" then
				f:ClearAllPoints()
				f:SetPoint("CENTER", Minimap, "CENTER", -60, -55)
			end

			-- Configure fading
			if n == "TimeManagerClockButton" then -- This is disgusting but have to work around other addons messing with it
				hooksecurefunc(f, "SetParent", function(self)
					local vis = mod.db.visibilitySettings[n] or "hover"
					if vis == "always" then
						sm.core.button.SetParent(self, Minimap)
						self:SetAlpha(1)
					elseif vis == "never" then
						sm.core.button.SetParent(self, hideFrame)
					else
						sm.core.button.SetParent(self, Minimap)
						self:SetAlpha(0)
					end
				end)
				f:SetParent(Minimap) -- Run the hook
			elseif mod.db.controlVisibility then
				self:ChangeFrameVisibility(f, mod.db.visibilitySettings[n] or "hover")
			end

			-- Don't add config or moving capability to the Zone Text and Clock buttons, handled in their own modules
			if n ~= "SexyMapZoneTextButton" and n ~= "TimeManagerClockButton" then
				self:AddButtonOptions(n)

				-- Configure dragging
				--if not sm.API.isVanilla and n == "MiniMapTracking" then
				--	self:MakeMovable(MiniMapTrackingButton, f)
				--else
					self:MakeMovable(f)
				--end
			end
		end
		f:HookScript("OnEnter", OnEnter)
		f:HookScript("OnLeave", OnLeave)
	end

	local frameParents = {} -- Store the original button parents for restoration
	function mod:ChangeFrameVisibility(frame, vis)
		if vis == "always" then
			if frameParents[frame] then
				frame:SetParent(frameParents[frame])
				frameParents[frame] = nil
			end
			if frame.MinimapLoopPulseAnim or frame.EyeHighlightAnim then
				KillAnimation(frame:GetName(), frame)
				frame:SetAlpha(1)
				OnFinished(frame.MinimapLoopPulseAnim or frame.EyeHighlightAnim)
			else
				frame:SetAlpha(1)
			end
		elseif vis == "never" then
			if not frameParents[frame] then
				frameParents[frame] = frame:GetParent()
			end
			frame:SetParent(hideFrame)
		else
			if frameParents[frame] then
				frame:SetParent(frameParents[frame])
				frameParents[frame] = nil
			end
			if frame.MinimapLoopPulseAnim or frame.EyeHighlightAnim then
				KillAnimation(frame:GetName(), frame)
				frame:SetAlpha(0)
				OnFinished(frame.MinimapLoopPulseAnim or frame.EyeHighlightAnim)
			else
				frame:SetAlpha(0)
			end
		end
	end

	ButtonFadeOut = OnLeave
end

--------------------------------------------------------------------------------
-- Dragging
--

local dragFrame = CreateFrame("Frame")

do
	local getCurrentAngle = function(parent, bx, by)
		local mx, my = parent:GetCenter()
		if not mx or not my or not bx or not by then return 0 end
		local h, w = (by - my), (bx - mx)
		if w == 0 then w = 0.001 end -- Prevent /0
		local angle = atan(h / w)
		if w < 0 then
			angle = angle + 180
		end
		return angle
	end

	-- The angle of a frame relative to the Minimap center, converting the frame's coords into Minimap coords
	local getFrameAngle = function(frame)
		local x, y = frame:GetCenter()
		if not x or not y then return 0 end
		local s = frame:GetEffectiveScale() / Minimap:GetEffectiveScale()
		return getCurrentAngle(Minimap, x * s, y * s)
	end

	local setPosition = function(frame, angle)
		local name = frame:GetName()
		local radius = (Minimap:GetWidth() / 2) + (mod.db.radiusOverrides[name] or mod.db.radius)
		local bx, by = sm.shapes:GetPosition(angle, radius)

		-- Use the raw widget functions so we don't trigger our own SetPoint hook
		sm.core.button.ClearAllPoints(frame)
		sm.core.button.SetPoint(frame, "CENTER", Minimap, "CENTER", bx, by)
	end

	local placeFrame = function(frame)
		local name = frame:GetName()
		setPosition(frame, mod.db.dragPositions[name] or getFrameAngle(frame))
	end

	function mod:GetButtonAngle(name)
		local angle = mod.db.dragPositions[name]
		if not angle then
			local frame = managedFrames[name]
			angle = frame and getFrameAngle(frame) or 0
		end
		return floor(angle % 360 + 0.5) % 360
	end

	local updatePosition = function()
		local x, y = GetCursorPosition()
		x, y = x / Minimap:GetEffectiveScale(), y / Minimap:GetEffectiveScale()
		local angle = getCurrentAngle(Minimap, x, y)
		local name = moving:GetName()
		mod.db.dragPositions[name] = angle
		setPosition(moving, angle)
	end

	local OnDragStart = function(frame)
		if mod.db.lockDragging or not mod.db.allowDragging then return end

		moving = frame
		fadeStop = true
		for i = 1, #animFrames do
			local f = animFrames[i]
			local n = f:GetName()
			if not mod.db.visibilitySettings[n] or mod.db.visibilitySettings[n] == "hover" then
				f.sexyMapFadeOut:Stop()

				local anim = KillAnimation(n, f)

				f:SetAlpha(1)
				if anim then
					OnFinished(anim)
				end
			end
		end
		dragFrame:SetScript("OnUpdate", updatePosition)
	end
	local OnDragStop = function()
		dragFrame:SetScript("OnUpdate", nil)
		moving = nil
		fadeStop = false
		ButtonFadeOut() -- Call the fade out function
	end

	-- Ownership: when another addon (LibDBIcon:Refresh, button bags, etc) or the default UI moves a button
	-- that we manage, put it straight back where the user wants it.
	local enforcePosition = function(frame)
		if not mod.db.allowDragging or not mod.db.enforcePositions then return end
		placeFrame(frame)
	end

	-- Same for the drag scripts, e.g. LibDBIcon:Lock/Unlock/Refresh replace them with its own drag handling
	local dragScripts = {}
	local enforceDragScripts = function(frame, script)
		if (script == "OnDragStart" or script == "OnDragStop") and mod.db.allowDragging and mod.db.enforcePositions then
			sm.core.button.SetScript(frame, "OnDragStart", dragScripts[frame][1])
			sm.core.button.SetScript(frame, "OnDragStop", dragScripts[frame][2])
		end
	end

	local hookedScripts, hookedPoints = {}, {}
	function mod:MakeMovable(frame, altFrame)
		frame:EnableMouse(true)
		frame:RegisterForDrag("LeftButton")
		local onDragStart = OnDragStart
		if altFrame then
			onDragStart = function()
				if mod.db.lockDragging or not mod.db.allowDragging then return end

				moving = altFrame
				dragFrame:SetScript("OnUpdate", updatePosition)
			end
		end
		dragScripts[frame] = {onDragStart, OnDragStop}
		sm.core.button.SetScript(frame, "OnDragStart", onDragStart)
		sm.core.button.SetScript(frame, "OnDragStop", OnDragStop)

		local target = altFrame or frame
		if not hookedScripts[frame] then
			hookedScripts[frame] = true
			hooksecurefunc(frame, "SetScript", enforceDragScripts)
		end
		if not hookedPoints[target] then
			hookedPoints[target] = true
			hooksecurefunc(target, "SetPoint", enforcePosition)
		end
		self:UpdateDraggables(target)
	end

	function mod:UpdateDraggables(frame)
		if not mod.db.allowDragging then return end

		if frame then
			placeFrame(frame)
		else
			for i = 1, #animFrames do
				local f = animFrames[i]
				local n = f:GetName()
				-- Don't move the Clock or Zone Text when changing shape/preset
				if n ~= "SexyMapZoneTextButton" and n ~= "TimeManagerClockButton" then
					placeFrame(f)
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Button grab
--

do
	local tbl = {
		Minimap, MiniMapTracking, TimeManagerClockButton, GameTimeFrame,
		MinimapZoomIn, MinimapZoomOut,
		MiniMapMailFrame, MiniMapBattlefieldFrame,
	}

	function mod:AddButton(_, button)
		self:NewFrame(button)
	end

	-- Named buttons on the minimap that we never want to take over
	local ignoreButtons = {
		QueueStatusMinimapButton = true,
		GarrisonLandingPageMinimapButton = true,
		MiniMapTrackingButton = true,
		MinimapZoneTextButton = true,
	}
	local function IsAddonButton(f)
		if f:IsForbidden() or f.sexyMapFadeOut or addonButtons[f] then return end
		if not f:IsObjectType("Button") or f:IsProtected() then return end
		local n = f:GetName()
		if not n or ignoreButtons[n] or blizzButtons[n] or dynamicButtons[n] or n:find("^LibDBIcon") or n:find("^SexyMap") then return end
		-- Only take frames that call themselves a minimap button, so we don't grab map pins (HandyNotes, GatherMate, etc)
		local lowerName = n:lower()
		if not lowerName:find("minimap", nil, true) or not lowerName:find("button", nil, true) then return end
		local w, h = f:GetSize()
		return w > 10 and w <= 50 and h > 10 and h <= 50
	end

	-- Take ownership of addon buttons that don't use LibDBIcon
	function mod:ScanForAddonButtons()
		if not mod.db.grabAddonButtons or InCombatLockdown() then return end
		local parents = {Minimap, MinimapBackdrop}
		for i = 1, #parents do
			local children = {parents[i]:GetChildren()}
			for j = 1, #children do
				local f = children[j]
				if IsAddonButton(f) then
					addonButtons[f] = true
					mod:NewFrame(f)
				end
			end
		end
	end

	local function CheckCalendar()
		if not mod.db.controlVisibility then return end
		local vis = mod.db.visibilitySettings.GameTimeFrame
		if not vis or vis == "hover" then
			if C_Calendar.GetNumPendingInvites() < 1 then
				mod:ChangeFrameVisibility(GameTimeFrame, "hover")
			else
				mod:ChangeFrameVisibility(GameTimeFrame, "always")
			end
		end
	end

	function mod:StartFrameGrab()
		if LFGMinimapFrame then -- Loads after PLAYER_ENTERING_WORLD
			tbl[#tbl+1] = LFGMinimapFrame
		end
		if MiniMapWorldMapButton then
			tbl[#tbl+1] = MiniMapWorldMapButton
		end
		if MiniMapInstanceDifficulty then
			tbl[#tbl+1] = MiniMapInstanceDifficulty
		end
		if GuildInstanceDifficulty then
			tbl[#tbl+1] = GuildInstanceDifficulty
		end
		if MiniMapChallengeMode then
			tbl[#tbl+1] = MiniMapChallengeMode
		end

		for i = 1, #tbl do
			mod:NewFrame(tbl[i])
		end

		local ldbiTbl = ldbi:GetButtonList()
		for i = 1, #ldbiTbl do
			mod:NewFrame(ldbi:GetMinimapButton(ldbiTbl[i]))
		end
		ldbi.RegisterCallback(mod, "LibDBIcon_IconCreated", "AddButton")

		-- Catch addon buttons created at login, and later by load on demand addons
		mod:ScanForAddonButtons()
		local scanFunc = function() mod:ScanForAddonButtons() end
		C_Timer.After(5, scanFunc)
		local scanFrame = CreateFrame("Frame")
		scanFrame:SetScript("OnEvent", function() C_Timer.After(1, scanFunc) end)
		scanFrame:RegisterEvent("ADDON_LOADED")

		-- If calendar is set to "hover" and we have pending invites, force show it
		if not sm.API.isVanilla and not sm.API.isTBC then -- Wrath+
			local frame = CreateFrame("Frame")
			frame:SetScript("OnEvent", CheckCalendar)
			frame:RegisterEvent("CALENDAR_UPDATE_PENDING_INVITES")
			frame:RegisterEvent("CALENDAR_ACTION_PENDING")
			CheckCalendar()
		end

		mod.StartFrameGrab = nil
	end
end

