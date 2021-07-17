local ADDON, T = ...
local L = {}

function L.InitMacroFrameBlizzard()
	CreateFrame("Button", "MacroFlyoutButton", MacroFrame, "UIPanelButtonTemplate")
	MacroFlyoutButton:SetSize(80, 22)
	MacroFlyoutButton:SetPoint("BOTTOMLEFT", MacroFrame, "BOTTOMLEFT", 81, 4)
	--MacroCancelButton:SetPoint("BOTTOMRIGHT", MacroFrameScrollFrame, "TOPRIGHT", 25, 8)
	--MacroSaveButton:SetPoint("BOTTOM", MacroCancelButton, "TOP", 0, 20)
	--MacroFlyoutButton:SetPoint("BOTTOM", MacroCancelButton, "TOP", 0, -1)
	MacroFlyoutButton:SetText("Flyout")
	MacroFlyoutButton:SetFrameStrata("HIGH")
	hooksecurefunc(MacroDeleteButton, "Disable", function() MacroFlyoutButton:Disable() end)
	hooksecurefunc(MacroDeleteButton, "Enable", function() MacroFlyoutButton:Enable() end)
	hooksecurefunc(MacroFrame, "Hide", function() if MacroFlyoutFrame.Mode=="MacroFrame" then MacroFlyoutFrame:Hide() end end)
	hooksecurefunc("MacroFrame_Update", function() if MacroFlyoutFrame.Mode=="MacroFrame" then MacroFlyoutFrame:Hide() end end)
	MacroFlyoutButton:SetScript("OnClick", function(self) MacroFlyoutFrame:Hide() MacroFlyoutFrame.Mode = "MacroFrame" MacroFlyoutFrame:Show() end )
end

function L.InitMacroFrame()	
	CreateFrame("Frame", "MacroFlyoutFrame", UIParent)
	
	MacroFlyoutFrame:SetToplevel(true)
	MacroFlyoutFrame:SetFrameStrata("HIGH")
	MacroFlyoutFrame:SetSize(465, 300)
	MacroFlyoutFrame:SetMovable(true)
	MacroFlyoutFrame:EnableMouse(true)
	
	MacroFlyoutFrame.BorderBox = CreateFrame("Frame", nil, MacroFlyoutFrame, "SelectionFrameTemplate")
	MacroFlyoutFrame.BorderBox:SetPoint("TOPLEFT")
	MacroFlyoutFrame.BorderBox:SetPoint("BOTTOMRIGHT")
	MacroFlyoutFrame.BG = MacroFlyoutFrame:CreateTexture(nil, "BACKGROUND")
	MacroFlyoutFrame.BG:SetPoint("TOPLEFT", 7, -7)
	MacroFlyoutFrame.BG:SetPoint("BOTTOMRIGHT", -7, 7)
	MacroFlyoutFrame.BG:SetColorTexture(0,0,0, 0.8)
	MacroFlyoutFrame.BorderBox.OnOkay = function() print("TODO: update macro") MacroFlyoutFrame:Hide() end
	MacroFlyoutFrame.BorderBox.OnCancel = function() MacroFlyoutFrame:Hide() end
	MacroFlyoutFrame:Hide()
	MacroFlyoutFrame:SetScript("OnShow", function(self) 
		if self.Mode=="MacroFrame" 
		then 
			MacroFlyoutFrame:ClearAllPoints()
			MacroFlyoutFrame:SetPoint("TOPLEFT", MacroFrame, "TOPRIGHT", 0, 0)
			MacroFlyoutFrame:RegisterForDrag(nil)
			print("TODO: parse current macro")
		else
			MacroFlyoutFrame:ClearAllPoints()
			MacroFlyoutFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
			MacroFlyoutFrame:RegisterForDrag("LeftButton")
		end 
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN) 
	end )
	MacroFlyoutFrame:SetScript("OnHide", function(self) self.Mode = nil end )
	MacroFlyoutFrame:SetScript("OnDragStart", MacroFlyoutFrame.StartMoving)
	MacroFlyoutFrame:SetScript("OnDragStop", MacroFlyoutFrame.StopMovingOrSizing)
	
	local buttons = {}
	for i = 1,10 do
		local button = CreateFrame("CheckButton", "MacroFlyoutFrameButton"..i, MacroFlyoutFrame, "SimplePopupButtonTemplate")
		buttons[i] = button
		button:SetID(i)
		button:SetPoint("TOPLEFT", MacroFlyoutFrame, "TOPLEFT", 16+(i-1)*(8+button:GetWidth()), -16)
		button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		button:Show()
		button:RegisterForDrag("LeftButton")
		button.Set = L.MacroFlyoutFrameButton_Set
		button.Clear = L.MacroFlyoutFrameButton_Clear
		button:SetScript("OnEnter", L.MacroFlyoutFrameButton_OnEnter)
		button:SetScript("OnLeave", L.MacroFlyoutFrameButton_OnLeave)
		button:SetScript("OnDragStart", function() button:Clear(true) end )
		button:SetScript("OnReceiveDrag", L.MacroFlyoutFrameButton_Drop)
		button:SetScript("OnClick", L.MacroFlyoutFrameButton_Drop)
		
	end
	
	-- TODO parse current open macro, also look for cancelmacro on left button
	-- TODO save macrotext when saving, with charactercheck
	-- TODO generate macrotext on updates
	-- TODO errors into chat window?
	
	
end

function L.MacroFlyoutFrameButton_Drop(self)
	local infoType, arg1, arg2, arg3 = GetCursorInfo()
	if infoType == "item" or infoType == "spell" or "macro"
	then 
		ClearCursor() 
		self:Set(infoType, arg1, arg2, arg3)
	end
end

function L.MacroFlyoutFrameButton_Set(self, infoType, arg1, arg2, arg3, addToCursor)
	self:Clear(true) 
	self.info = {infoType, arg1, arg2, arg3}
	self:SetNormalTexture(nil)
	if infoType == "item"
	then
		local icon = GetItemIcon(arg1)
		self:SetNormalTexture(icon)
	elseif infoType == "spell"
	then
		local name, rank, icon = GetSpellInfo(arg3)
		self:SetNormalTexture(icon)
	elseif infoType == "macro"
	then
		local name, icon = GetMacroInfo(arg1)
		self:SetNormalTexture(icon)
	end
end

function L.MacroFlyoutFrameButton_Clear(self, addToCursor)
	local infoType, arg1, arg2, arg3
	if self.info
	then
		infoType, arg1, arg2, arg3 = unpack(self.info)
	end
	self.info = nil
	self:SetNormalTexture(nil)
	if addToCursor
	then
		if infoType == "item"
		then
			PickupItem(arg1)
		elseif infoType == "spell"
		then
			PickupSpell(arg3) 
		elseif infoType == "macro"
		then
			PickupMacro(arg1)
		end
	end
end

function L.MacroFlyoutFrameButton_OnEnter(self)	
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 4, 4) 
	local infoType, arg1, arg2, arg3
	if self.info
	then
		infoType, arg1, arg2, arg3 = unpack(self.info)
	end
	if infoType == "item"
	then
		GameTooltip:SetItemByID(arg1)
	elseif infoType == "spell"
	then
		GameTooltip:SetSpellByID(arg3)
	elseif infoType == "macro"
	then
		local name = GetMacroInfo(arg1)
		GameTooltip:SetText(name)
	end
end

function L.MacroFlyoutFrameButton_OnLeave(self)	
	GameTooltip:Hide()
end

local function OnEvent(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON
	then
		L.InitMacroFrame()
	elseif event == "ADDON_LOADED" and arg1 == "Blizzard_MacroUI"
	then
		L.InitMacroFrameBlizzard()
	end
	if MacroFlyoutFrame and MacroFlyoutButton
	then
		self:UnregisterEvent("ADDON_LOADED")
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", OnEvent)
