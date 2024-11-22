--[[
API

Init(onsuccess)
	This function is initializing the library and creating the necessery frames. Must be called first, after all the buttons are up. PLAYER_ENTERING_WORLD is a good cancidate.
	Parameters:
		onsuccess: callback after the operation, as it can happen the execution is delayed due to combat lockdown
		
Update(now, onsuccess)
	Updates the look (arrows) for all the buttons.
	Parameters:
		now: if true, the update happens instantly, not queued with other operations that might be delayed due to combat
		onsuccess: callback after the operation, as it can happen the execution is delayed due to combat lockdown

ForceClose(action, onsuccess)
	Closing the flyout frame.
	Parameters:
		action: optional, if present, only close if that action was pressed
		onsuccess: callback after the operation, as it can happen the execution is delayed due to combat lockdown

SetAction(slot, actions, onsuccess)
SetMacro(slot, actions, onsuccess)
	Set the button actions for the given action slot or macro id. See Actions for details.
	Parameters:
		slot: the actionslot or macro id
		actions: specified actions for the flyout buttons, nil to delete
		onsuccess: callback after the operation, as it can happen the execution is delayed due to combat lockdown

ClearAll(onsuccess)
ClearActions(onsuccess)
ClearMacros(onsuccess)
	Clears all the previous actions for every type or just actions or just macros.
	Parameters:
		onsuccess: callback after the operation, as it can happen the execution is delayed due to combat lockdown

SetOverrideDistance(parent|string, value, onsuccess)
		parent: the parent button, eg ActionButton9 to override value on
		string: the actionslot or macroid to override value on, MacroN or ActionN, where N is the slot/id
		value: direction for the flyout, valid values are "LEFT","RIGHT","UP","DOWN", default is based on the actionbars, but mostly "UP"
		onsuccess: callback after the operation, as it can happen the execution is delayed due to combat lockdown
		
SetOverrideDirection(parent|string, value, onsuccess)
		parent: the parent button, eg ActionButton9 to override value on
		string: the actionslot or macroid to override value on, MacroN or ActionN, where N is the slot/id
		value: distance for the flyout background to start, default is 3, the size of border/shadow 
		onsuccess: callback after the operation, as it can happen the execution is delayed due to combat lockdown
		
SetOverrideCooldown(parent|string, value, onsuccess)
		parent: the parent button, eg ActionButton9 to override value on
		string: the actionslot or macroid to override value on, MacroN or ActionN, where N is the slot/id
		value: the cooldown color: NONE|BLACK|WHITE, nil equals NONE
		onsuccess: callback after the operation, as it can happen the execution is delayed due to combat lockdown

Actions
	Structure to setup the flyout.
	It is evaluated the following way. On button click (no keypress!), first it is checked if the corresponding action is macro or other. In case of macro, if there is any action for it with SetMacro, it is used. Otherwise the action value with SetAction is attempted.
	Maximum 10 actions can be specified.
	It should be and array of tables, where tables contain key value pairs for relevant SecureActionButtonTemplate attributes, extended with $icon key. See SecureActionButtonTemplate for more details.
	$icon is used for look and tooltips, valid value formats are "spell:id", "spell:name", "item:id", "item:name", "texture:id", "texture:id:tooltip]", with spell and item tooltip and count is updated automatically, tooltip is optional for texture
	Example: 
		local actions = {
			{["$icon"]="item:6948", ["*type1"]="macro", ["*type2"]="macro", macrotext1="/run print('btn1')",macrotext2="/cast Hearthstone"},
			{["$icon"]="spell:49361", ["type"]="macro", macrotext="/run print('btn2')"},
			{["$icon"]="item:3776", ["type"]="macro", macrotext="/run print('btn3')"},
			{["$icon"]="texture:136172:tooltip", ["type"]="macro", macrotext="/run print('btn4')"},
			{["$icon"]="item:19013", ["type"]="macro", macrotext="/run print('btn5')"},
			{["$icon"]="item:16022", ["type"]="macro", macrotext="/run print('btn6')"},
			{["type"]="macro", macrotext="/run print('btn7')"},
		}

]]--

assert(LibStub, "LibFlyoutFrame requires LibStub")
local MAJOR, MINOR = "LibFlyoutFrame-1.0", 3;
local Lib, oldminor = LibStub:NewLibrary(MAJOR, MINOR);
if not Lib then return end

local BE = LibStub:GetLibrary("LibBEncode-1.0")
assert(BE, "LibFlyoutFrame LibBEncode")

local L = {}

local MAX_BUTTONS = 10
local MAX_COUNT = 99
local ICON_UNKNOWN = 134400 -- gear: 136243

local flyout = nil
local buttons = {}
local proxies = {}
local deferredQueue = {}
local deferredFrame = CreateFrame("Frame")
local actionkeys = {}

local PlayerHasToy = _G.PlayerHasToy or function() return false end
local GetToyInfo = _G.C_ToyBox and _G.C_ToyBox.GetToyInfo or function() end
local IsToyUsable = _G.C_ToyBox and _G.C_ToyBox.IsToyUsable or function() end
local GetItemCooldown = _G.C_Container and _G.C_Container.GetItemCooldown or _G.GetItemCooldown

do -- lib entry points, deferred in combat

function Lib.Init(onsuccess)
	if L.AddDeferredIfCombat(LibInit, onsuccess)
	then 
		return
	end
	
	if (not flyout)
	then
		L.FlyoutCreate()
		L.ProxyButtonsCreate()
		L.ProxyButtonsUpdateAll()
	end
	
	if onsuccess
	then
		onsuccess()
	end
end

local function SetHelper(prefix, slot, actions, onsuccess)
	if L.AddDeferredIfCombat(SetHelper, prefix, slot, actions, onsuccess)
	then 
		return
	end
	
	local key = prefix..slot
	
	if (actions)
	then
		local bencode = actions and BE.Encode(actions)
		actionkeys[key] = true
		flyout:SetAttribute(key, bencode)
	else
		actionkeys[key] = nil
		flyout:SetAttribute(key, nil)
	end

	if onsuccess
	then
		onsuccess()
	end
end

function Lib.SetMacro(slot, actions, onsuccess)
	SetHelper("$macro", slot, actions, onsuccess)
end

function Lib.SetAction(slot, actions, onsuccess)
	SetHelper("$action", slot, actions, onsuccess)
end

local function ClearHelper(prefix, onsuccess)
	if L.AddDeferredIfCombat(ClearHelper, prefix, onsuccess)
	then 
		return
	end
	
	local findstr = "^"..(prefix or "")
	for key,_ in pairs(actionkeys)
	do 
		if not prefix or (key:find(findstr) ~= nil)
		then
			flyout:SetAttribute(key, nil)
			actionkeys[key]=nil
		end
	end
	
	if onsuccess
	then
		onsuccess()
	end
end

function Lib.ClearMacros(onsuccess)
	ClearHelper("$macro", onsuccess)
end

function Lib.ClearActions(onsuccess)
	ClearHelper("$action", onsuccess)
end

function Lib.ClearAll(onsuccess)
	ClearHelper(nil, onsuccess)
end

local function OverrideHelper(mixed, attribute, value, onsuccess)
	if L.AddDeferredIfCombat(OverrideHelper, mixed, attribute, value, onsuccess)
	then 
		return
	end
	
	if type(mixed) == "string"
	then
        flyout:SetAttribute(attribute..mixed, value)
    else
		for _, proxy in ipairs(proxies)
		do
			local pparent = proxy:GetParent()
			if parent == pparent
			then
				proxy:SetAttribute(attribute, value)
				L.ProxyButtonUpdate(proxy)
			end
		end
    end
	
	
	if onsuccess
	then
		onsuccess()
	end
end

function Lib.SetOverrideDirection(parent, value, onsuccess)
	OverrideHelper(parent, "$direction", value, onsuccess)
end

function Lib.SetOverrideDistance(parent, value, onsuccess)
	OverrideHelper(parent, "$distance", value, onsuccess)
end

function Lib.SetOverrideCooldown(parent, value, onsuccess)
	OverrideHelper(parent, "$cooldown", value, onsuccess)
end

function Lib.Update(now, onsuccess)
	if not now and L.AddDeferredIfCombat(Lib.Update, now, onsuccess)
	then 
		return
	end
	
	L.ProxyButtonsUpdateAll()
	
	if onsuccess
	then
		onsuccess()
	end
end

function Lib.ForceClose(action,onsuccess)
	if not now and L.AddDeferredIfCombat(Lib.ForceClose, onsuccess)
	then 
		return
	end
	
	if not action or flyout:GetAttribute("$action")==action
	then
		flyout:Hide()
	end
	
	if onsuccess
	then
		onsuccess()
	end
end

end

do -- deferred call handling

function L.AddDeferredIfCombat(func, ...)
	return L.AddDeferredIfCombatBase(false, func, ...)
end

function L.AddDeferredIfCombatHideMessage(func, ...)
	return L.AddDeferredIfCombatBase(true, func, ...)
end

function L.AddDeferredIfCombatBase(hidemsg, func, ...)
	if not InCombatLockdown()
	then
		return false
	else
		if not deferredFrame:IsEventRegistered("PLAYER_REGEN_ENABLED")
		then
			if not hidemsg
			then
				print("Requested actions will be finished once you leave combat.")
			end
			deferredFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
			deferredFrame:SetScript("OnEvent", L.RunDeferred)
		end
		deferredQueue[#deferredQueue+1]={func=func,args={...}}
	end
	return true
end

function L.RunDeferred()
	if not InCombatLockdown()
	then
		deferredFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
		for i=1,#deferredQueue
		do
			local event = deferredQueue[i]
			if event.args
			then
				event.func(unpack(event.args))
			else
				event.func()
			end
		end
		deferredQueue = {}
	end
end
end

do -- ui elements

--[[
Look based on 
Retail Interface/FrameXML/SpellFlyout.lua
Retail Interface/FrameXML/SpellFlyout.xml
Classic Interface/FrameXML/ActionButton.lua
Classic Interface/FrameXML/ActionButtonTemplate.xml
]]--

function L.FlyoutCreate()
	if flyout
	then
		return
	end
	
	local self = CreateFrame("Frame", "CustomFlyoutFrame", nil, "SecureFrameTemplate, SecureHandlerStateTemplate")
	flyout = self
	
	self.BgEnd = self:CreateTexture(nil, "BACKGROUND")
	self.BgEnd:SetTexture("Interface\\Buttons\\ActionBarFlyoutButton")
	self.BgEnd:SetSize(37,22)
	self.BgEnd:SetTexCoord(0.01562500,0.59375000,0.74218750,0.91406250)
	self.HorizBg = self:CreateTexture(nil, "BACKGROUND")
	self.HorizBg:SetTexture("Interface\\Buttons\\ActionBarFlyoutButton-FlyoutMidLeft")
	self.HorizBg:SetHorizTile(true)
	self.HorizBg:SetSize(32,37)
	self.HorizBg:SetTexCoord(0,1,0,0.578125)
	self.VertBg = self:CreateTexture(nil, "BACKGROUND")
	self.VertBg:SetTexture("Interface\\Buttons\\ActionBarFlyoutButton-FlyoutMid")
	self.VertBg:SetVertTile(true)
	self.VertBg:SetSize(37,32)
	self.VertBg:SetTexCoord(0,0.578125,0,1)
	
	self:HookScript("OnShow", L.FlyoutUpdate)
	self:HookScript("OnHide", L.FlyoutUpdate)
	
	for i=1,MAX_BUTTONS
	do
		L.FlyoutButtonCreate(self)
	end
	
	local conditionBase, driver = '[%s] %d; ', {}
    local conditions = {
		'overridebar,bar:1', 'shapeshift,bar:1', 'bonusbar:1,bar:1', 'bonusbar:2,bar:1', 'bonusbar:3,bar:1', 'bonusbar:4,bar:1', 
        'bar:1', 'bar:2', 'bar:3', 'bar:4', 'bar:5', 'bar:6',
    }
	for i, macroCondition in ipairs(conditions) do
        table.insert(driver, conditionBase:format(macroCondition, i))
    end
	table.insert(driver, #conditions + 1)
	driver = table.concat(driver)
	RegisterStateDriver(self, '$actionpage', driver)
	self:SetAttribute('_onstate-$actionpage', [=[ -- self, stateid, newstate
		local parent = self:GetParent()
		if parent
		then
			local actionNew = parent:RunAttribute("$funcCalculateAction") 
			local actionOld = self:GetAttribute("$action")
			
			if actionOld ~= actionNew
			then
				self:Hide()
			end
		end
		self:CallMethod("OnBarChange", self)
	]=])
	self.OnBarChange = L.FlyoutOnBarChange
	self.OnSlotChange = L.FlyoutOnSlotChange
	
	self.closeproxy = CreateFrame("Frame", "CustomFlyoutFrameCloseProxy")
	self.closeproxy:HookScript("OnHide", function() if not L.AddDeferredIfCombatHideMessage(function() if self:IsVisible() then self.closeproxy:Show() end end) then self:Hide() end end)
	self.closeproxy:Hide()
	tinsert(UISpecialFrames, self.closeproxy:GetName())
	
	self:SetScript("OnEvent", L.FlyoutOnEvent)
	self:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
	
	self:SetFrameStrata("DIALOG");
	self:Hide()
end

function L.FlyoutOnEvent(self, event, arg1)
	if event == "ACTIONBAR_SLOT_CHANGED"
	then
		self:OnSlotChange(arg1)
	end
end

function L.FlyoutOnSlotChange(self, slot)
	for _,proxy in ipairs(proxies)
	do
		local parent = proxy:GetParent()
		if parent.action == slot
		then
			L.ProxyButtonUpdate(proxy)
		end
	end
end

function L.FlyoutOnBarChange(self)
	L.ProxyButtonsUpdateAll()
end
	
function L.FlyoutUpdate(self)
	if self:IsVisible()
	then
		L.FlyoutUpdateBG(self)
		L.FlyoutUpdateButtons(self)
		self.closeproxy:Show()
	end
	L.ProxyButtonsUpdateAll()
end

function L.FlyoutUpdateBG(self)
	local direction = self:GetAttribute("$direction")
	local distance = self:GetAttribute("$distance")
	if (not direction) then
		direction = "UP"
	end
	if (not distance) then
		distance = 0
	end
	self.BgEnd:ClearAllPoints()
	if (direction == "UP") 
	then
		self.BgEnd:SetPoint("TOP")
		SetClampedTextureRotation(self.BgEnd, 0)
		self.HorizBg:Hide()
		self.VertBg:Show()
		self.VertBg:ClearAllPoints()
		self.VertBg:SetPoint("TOP", self.BgEnd, "BOTTOM")
		self.VertBg:SetPoint("BOTTOM", 0, distance)
	elseif (direction == "DOWN") 
	then
		self.BgEnd:SetPoint("BOTTOM")
		SetClampedTextureRotation(self.BgEnd, 180)
		self.HorizBg:Hide()
		self.VertBg:Show()
		self.VertBg:ClearAllPoints()
		self.VertBg:SetPoint("BOTTOM", self.BgEnd, "TOP")
		self.VertBg:SetPoint("TOP", 0, -distance)
	elseif (direction == "LEFT") 
	then
		self.BgEnd:SetPoint("LEFT")
		SetClampedTextureRotation(self.BgEnd, 270)
		self.VertBg:Hide()
		self.HorizBg:Show()
		self.HorizBg:ClearAllPoints()
		self.HorizBg:SetPoint("LEFT", self.BgEnd, "RIGHT")
		self.HorizBg:SetPoint("RIGHT", -distance, 0)
	elseif (direction == "RIGHT")
	then
		self.BgEnd:SetPoint("RIGHT")
		SetClampedTextureRotation(self.BgEnd, 90)
		self.VertBg:Hide()
		self.HorizBg:Show()
		self.HorizBg:ClearAllPoints()
		self.HorizBg:SetPoint("RIGHT", self.BgEnd, "LEFT")
		self.HorizBg:SetPoint("LEFT", distance, 0)
	end
	local r, g, b = 0.7, 0.7, 0.7
	self.HorizBg:SetVertexColor(r, g, b)
	self.VertBg:SetVertexColor(r, g, b)
	self.BgEnd:SetVertexColor(r, g, b)
end

function L.FlyoutUpdateButtons()
	for _,button in ipairs(buttons)
	do
		L.FlyoutButtonUpdate(button)
	end
end

function L.FlyoutButtonCreate(parent)
	local num = #buttons
	if numButtons==MAX_BUTTONS
	then
		return
	end
	
	num = num+1
	local self = CreateFrame("CheckButton", "CustomFlyoutButton"..num, parent, "ActionButtonTemplate,SecureActionButtonTemplate,SecureFrameTemplate,SecureHandlerBaseTemplate")
	buttons[num] = self
	
	self:RegisterForClicks("AnyUp")
	self:SetSize(28,28)
	self:SetNormalTexture(0)
	self:SetPushedTexture(0)
	self:SetCheckedTexture(0)
	self.Count:SetPoint("BOTTOMRIGHT", 0, 0)
	self.updateCount = nil
	self.icon:SetTexCoord(4/64, 60/64, 4/64, 60/64)
	self.icon:SetTexture(ICON_UNKNOWN)
	self.oldicon = nil
	
	self:WrapScript(self, "OnClick", [=[ -- self, button, down
	
		local flyout = self:GetFrameRef("CustomFlyout")
		flyout:Hide()
		
	]=])
	
	self:SetFrameRef("CustomFlyout", parent)
	
	self:SetScript("OnEvent", L.FlyoutButtonOnEvent);
	
	self:Hide()
	
	if onsuccess
	then
		onsuccess(self)
	end
end

function L.FlyoutButtonUpdate(self)
	if self:IsVisible()
	then
		local icon = self:GetAttribute("$icon")
		local oldicon = self.oldicon
		local cooldown = self:GetAttribute("$cooldown")
		self.updateCooldown = nil
		if icon ~= oldicon
		then
			local iconid = ICON_UNKNOWN
			local itype, id, tooltip
			if icon
			then
				itype, id = strsplit(":", icon, 2)
			end
			if itype == "item"
			then
				local idstr = id
				id = tonumber(idstr)
				if not id
				then
					id = GetItemInfoInstant(idstr)
				end
				if id
				then
					iconid = GetItemIcon(id)
					L.FlyoutButtonUpdateCountItem(self, id)
					self.updateCount = function() L.FlyoutButtonUpdateCountItem(self, id) end
					self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
					self:RegisterEvent("BAG_UPDATE")
					if GetToyInfo(id)
					then
						self:SetScript("OnEnter", function() GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 4, 4) GameTooltip:SetToyByItemID(id) end)
					else
						self:SetScript("OnEnter", function() GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 4, 4) GameTooltip:SetItemByID(id) end)
					end
					self:SetScript("OnLeave", function() GameTooltip:Hide() end)
				end
			elseif itype == "spell"
			then
				local newid
				_,_,newid,_,_,_,id = GetSpellInfo(id)
				if id
				then
					iconid = newid
					L.FlyoutButtonUpdateCountSpell(self, id)
					self.updateCount = function() L.FlyoutButtonUpdateCountSpell(self, id) end
					self:RegisterEvent("BAG_UPDATE")
					self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
					self:SetScript("OnEnter", function() GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 4, 4) GameTooltip:SetSpellByID(id) end)
					self:SetScript("OnLeave", function() GameTooltip:Hide() end)
				end
			elseif itype == "texture"
			then
				id, tooltip = strsplit(":", id, 2)
				iconid = tonumber(id)
				L.FlyoutButtonReset(self)
				if tooltip
				then
					self:SetScript("OnEnter", function() GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 4, 4) GameTooltip:SetText(tooltip) end)
					self:SetScript("OnLeave", function() GameTooltip:Hide() end)
				end
			else
				L.FlyoutButtonReset(self)
			end
			self.icon:SetTexture(iconid)
			self.oldicon = icon
			if cooldown
			then
				local color = cooldown
				self.updateCooldown = function() L.FlyoutButtonUpdateCooldown(self, itype, id, color) end
				self.updateCooldown()
			else
				self.cooldown:SetAlpha(0)
			end
		end
	else
		L.FlyoutButtonReset(self)
	end
end

function L.FlyoutButtonReset(self)
	self.updateCount = nil
	self.updateCooldown = nil
	self.cooldown:SetAlpha(0)
	self.Count:SetText("")
	self.icon:SetDesaturated(false)
	self:SetScript("OnEnter", nil)
	self:SetScript("OnLeave", nil)
	self:UnregisterEvent("BAG_UPDATE")
	self:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
end

function L.FlyoutButtonUpdateCooldown(self, itype, id, color)
	local startTime, duration
	if itype == "item"
	then
		startTime, duration = GetItemCooldown(id)
	elseif itype == "spell"
	then
		startTime, duration = GetSpellCooldown(id)
	end
	if startTime and 0<startTime
	then
		if color == "WHITE"
		then
			self.cooldown:SetSwipeColor(1, 1, 1)
		else
			self.cooldown:SetSwipeColor(0, 0, 0)
		end
		self.cooldown:SetAlpha(1)
		self.cooldown:SetCooldown(startTime, duration)
	end
end

function L.FlyoutButtonUpdateCountItem(self, id, noretry)
	local desaturated = false
	local count = GetItemCount(id)
	local isToy = GetToyInfo(id) and PlayerHasToy(id) and IsToyUsable(id)
	if (count==0 and not isToy)
	then
		desaturated = true
	end
	local item=Item:CreateFromItemID(id)
	if not item:IsItemDataCached() and not noretry
	then
		item:ContinueOnItemLoad(function() L.FlyoutButtonUpdateCountItem(self, id, false) end)
		count = ""
	else
		local t,s=select(12, GetItemInfo(id))
		local lookup = {}
		lookup[LE_ITEM_CLASS_CONSUMABLE]=true
		lookup[LE_ITEM_CLASS_REAGENT]=true
		lookup[LE_ITEM_CLASS_PROJECTILE]=true
		lookup[LE_ITEM_CLASS_TRADEGOODS]=true
		lookup[LE_ITEM_CLASS_ITEM_ENHANCEMENT]=true
		lookup[LE_ITEM_CLASS_QUESTITEM]=true
		if lookup[t] and not GetToyInfo(id)
		then
			if ( count > MAX_COUNT)
			then
				count = "*"
			end
		else
			count = ""
		end
	end
	
	self.Count:SetText(count)
	self.icon:SetDesaturated(desaturated)
end

function L.FlyoutButtonUpdateCountSpell(self, id)
	local desaturated = false
	local count = ""
	if ( IsConsumableSpell(id)) 
	then
		count = GetSpellCount(id);
		if (count == 0)
		then
			desaturated = true
		end
		if ( count > MAX_COUNT)
		then
			count = "*"
		end
	end
	self.Count:SetText(count)
	self.icon:SetDesaturated(desaturated)
end

function L.FlyoutButtonOnEvent(self, event, ...)
	if event == "BAG_UPDATE" or event == "SPELL_UPDATE_COOLDOWN"
	then
		if self.updateCooldown
		then
			self.updateCooldown()
		end
		if self.updateCount
		then
			self.updateCount()
		end
	end
end

function L.ProxyButtonsCreate()
	local frame = EnumerateFrames()
	while frame 
	do
		 -- protected frames must have a name
		if frame.IsProtected and frame:IsProtected() and frame.GetObjectType and frame:GetObjectType() == "CheckButton" and frame.action
		then
			local name = frame:GetName()
			
			--[[ Whitelist based on names?
			^ActionButton%d+$
			^MultiBarBottomLeftButton%d+$
			^MultiBarBottomRightButton%d+$
			^MultiBarLeftButton%d+$
			^MultiBarRightButton%d+$
			^BT4Button%d+$
			^ButtonForge%d+$
			^DominosActionButton%d+$
			^ElvUI_Bar%d+Button%d+$
			^TinyExtraBarsContainerFrame%d+ButtonFrame%d+Button%d+_%d+$
			]]--
			
			if name and not -- Blacklisted frames (incompatible addon/frame)
				(
					string.find(name, "^ButtonForge%d+$") or
					string.find(name, "^OverrideActionBarButton%d+$") or
					string.find(name, "^MultiCastActionButton%d+$") 
				)
			then
				L.ProxyButtonCreate(frame)
			end
			
		end
		frame = EnumerateFrames(frame)
	end
end

function L.ProxyButtonsUpdateAll()
	for _,proxy in ipairs(proxies)
	do
		if proxy:IsVisible()
		then
			L.ProxyButtonUpdate(proxy)
		end
	end
end

function L.ProxyButtonCreate(parent)
	local parentName = parent:GetName()
	local self = CreateFrame("CheckButton", parentName.."FlyoutProxy", parent, "SecureActionButtonTemplate,SecureHandlerBaseTemplate,SecureHandlerDragTemplate")
	proxies[#proxies+1] = self
	
	self:RegisterForClicks("AnyUp")
	self:SetSize(36,36)
	self.icon = self:CreateTexture(nil, "BACKGROUND")
	self.FlyoutBorder = self:CreateTexture(nil, "ARTWORK", nil, 1)
	self.FlyoutBorder:SetTexture("Interface\\Buttons\\ActionBarFlyoutButton")
	self.FlyoutBorder:SetSize(42,42)
	self.FlyoutBorder:SetTexCoord(0.01562500,0.67187500,0.39843750,0.72656250)
	self.FlyoutBorder:SetPoint("CENTER")
	self.FlyoutBorderShadow = self:CreateTexture(nil, "ARTWORK", nil, 1)
	self.FlyoutBorderShadow:SetSize(48,48)
	self.FlyoutBorderShadow:SetTexture("Interface\\Buttons\\ActionBarFlyoutButton")
	self.FlyoutBorderShadow:SetTexCoord(0.01562500,0.76562500,0.00781250,0.38281250)
	self.FlyoutBorderShadow:SetPoint("CENTER")
	self.FlyoutArrow = self:CreateTexture(nil, "ARTWORK", nil, 2)
	self.FlyoutArrow:SetTexture("Interface\\Buttons\\ActionBarFlyoutButton")
	self.FlyoutArrow:SetSize(23,11)
	self.FlyoutArrow:SetTexCoord(0.62500000,0.98437500,0.74218750,0.82812500)
	self.FlyoutArrow:SetPoint("CENTER")
	
	self:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
	self:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	
	self:RegisterForDrag("LeftButton", "RightButton")
	
	self:WrapScript(self, "OnClick", [=[ -- self, button, down
		if button=="RightButton" then return end
		
		local flyout = self:GetFrameRef("CustomFlyout")
		local action = self:RunAttribute("$funcCalculateAction", button) 
		local buttonActions, macroid = self:RunAttribute("$funcGetFlyoutActions", action) 
		local flyoutVisible = flyout:IsVisible()
		
		if flyout:GetParent() == self
		then
			flyout:Hide()
		end
		
		if not buttonActions then return end
		
		]=] .. BE.GetDecodeScript("buttonActions", "buttonActions") .. [=[
		
				
		local CUSTOMFLYOUT_DEFAULT_SPACING = 4
		local CUSTOMFLYOUT_INITIAL_SPACING = 7
		local CUSTOMFLYOUT_FINAL_SPACING = 4
	
		flyout:Hide()
		
		if flyout:GetParent() ~= self or not flyoutVisible
		then
			local direction = self:GetAttribute("$direction") or flyout:GetAttribute("$directionAction"..action) or flyout:GetAttribute("$directionMacro"..macroid) or self:GetAttribute("$defaultdirection") or "UP"
			local distance = self:GetAttribute("$distance") or flyout:GetAttribute("distanceAction"..action) or flyout:GetAttribute("distanceMacro"..macroid) or 3
			local cooldown = self:GetAttribute("$cooldown") or flyout:GetAttribute("$cooldownAction"..action) or flyout:GetAttribute("$cooldownMacro"..macroid)
			
			-- Update all buttons for this flyout
			local prevButton = nil
			local numButtons = 0
			local buttons = table.new()
			for _,child in ipairs(table.new(flyout:GetChildren()))
			do
				local name = child:GetName()
				local num, found = gsub(name,"^CustomFlyoutButton","")
				if found and child:IsObjectType("CheckButton")
				then
					buttons[tonumber(num)]=child
				end
			end
			for num=1,#buttons
			do
				local button = buttons[num]
				local attributes = buttonActions[num]
				local visible = attributes ~= nil and next(attributes) ~= nil
				if (visible) 
				then
					button:ClearAllPoints()
					if (direction == "UP") then
						if (prevButton) then
							button:SetPoint("BOTTOM", prevButton, "TOP", 0, CUSTOMFLYOUT_DEFAULT_SPACING)
						else
							button:SetPoint("BOTTOM", flyout, BOTTOM, 0, CUSTOMFLYOUT_INITIAL_SPACING)
						end
					elseif (direction == "DOWN") then
						if (prevButton) then
							button:SetPoint("TOP", prevButton, "BOTTOM", 0, -CUSTOMFLYOUT_DEFAULT_SPACING)
						else
							button:SetPoint("TOP", flyout, "TOP", 0, -CUSTOMFLYOUT_INITIAL_SPACING)
						end
					elseif (direction == "LEFT") then
						if (prevButton) then
							button:SetPoint("RIGHT", prevButton, "LEFT", -CUSTOMFLYOUT_DEFAULT_SPACING, 0)
						else
							button:SetPoint("RIGHT", flyout, "RIGHT", -CUSTOMFLYOUT_INITIAL_SPACING, 0)
						end
					elseif (direction == "RIGHT") then
						if (prevButton) then
							button:SetPoint("LEFT", prevButton, "RIGHT", CUSTOMFLYOUT_DEFAULT_SPACING, 0)
						else
							button:SetPoint("LEFT", flyout, "LEFT", CUSTOMFLYOUT_INITIAL_SPACING, 0)
						end
					end
					
					local oldaction = button:GetAttribute("$oldaction")
					if oldaction
					then
						for _,attribute in ipairs(newtable(strsplit("\t", oldaction)))
						do 
							button:SetAttribute(attribute, nil)
						end
					end
						
					oldaction = table.new()
					for key,value in pairs(attributes)
					do
						if #oldaction>0
						then
							table.insert(oldaction, "\t") --no delimeter in restriceted tables
						end
						table.insert(oldaction, key)
						button:SetAttribute(key, value)
					end
					oldaction = table.concat(oldaction)
					button:SetAttribute("$oldaction", oldaction)
					button:SetAttribute("$cooldown", cooldown)
					
					button:Show()
					prevButton = button
					numButtons = numButtons+1
				else
					button:Hide()
				end
			end
			
			if numButtons==0 then return end
			
			-- Show the flyout
			if (direction == "UP" or direction == "DOWN") then
				flyout:SetWidth(prevButton:GetWidth())
				flyout:SetHeight((prevButton:GetHeight()+CUSTOMFLYOUT_DEFAULT_SPACING) * numButtons - CUSTOMFLYOUT_DEFAULT_SPACING + CUSTOMFLYOUT_INITIAL_SPACING + CUSTOMFLYOUT_FINAL_SPACING)
			else
				flyout:SetHeight(prevButton:GetHeight())
				flyout:SetWidth((prevButton:GetWidth()+CUSTOMFLYOUT_DEFAULT_SPACING) * numButtons - CUSTOMFLYOUT_DEFAULT_SPACING + CUSTOMFLYOUT_INITIAL_SPACING + CUSTOMFLYOUT_FINAL_SPACING)
			end
			flyout:SetParent(self)
			flyout:ClearAllPoints()
			if (direction == "UP") then
				flyout:SetPoint("BOTTOM", self, "TOP", 0, 0)
			elseif (direction == "DOWN") then
				flyout:SetPoint("TOP", self, "BOTTOM", 0, 0)
			elseif (direction == "LEFT") then
				flyout:SetPoint("RIGHT", self, "LEFT", 0, 0)
			elseif (direction == "RIGHT") then
				flyout:SetPoint("LEFT", self, "RIGHT", 0, 0)
			end
			flyout:SetAttribute("$direction", direction)
			flyout:SetAttribute("$distance", distance)
			flyout:SetAttribute("$action", action)
			--flyout:SetFrameStrata(self:GetFrameStrata())
			--flyout:SetFrameLevel(self:GetFrameLevel())
			flyout:Show()
		end
	]=])
	
	self:SetAttribute("_ondragstart", [=[ -- self, button, kind, value
		local flyout = self:GetFrameRef("CustomFlyout")
		local lockbars = flyout:GetAttribute("$lockbars")
		lockbars = lockbars and tonumber(lockbars) or 0
		if (lockbars==0) or IsModifiedClick("PICKUPACTION")
		then
			local action = self:RunAttribute("$funcCalculateAction", button) 
			return "action", action
		end
	]=])
	
	self:SetAttribute("_onreceivedrag", [=[ -- self, button, kind, value
		if kind
		then
			local flyout = self:GetFrameRef("CustomFlyout")
			local action = self:RunAttribute("$funcCalculateAction", button) 
			return "action", action
		end
	]=])
		
	self:SetAttribute("$funcCalculateAction", [=[ -- self
		-- L.ProxyButtonCalculateAction equivalent in restriceted env
		-- parent:GetEffectiveAttribute calls SecureButton_GetModifiedAttribute internally
		local NUM_ACTIONBAR_BUTTONS=12
		local button = ...
		local parent = self:GetParent()
		if ( not button ) 
		then
			button = "LeftButton"
		end
		if ( parent:GetID() > 0 )
		then
			local page = parent:GetEffectiveAttribute("actionpage", button); 
			if ( not page ) 
			then
				page = GetActionBarPage();
			end
			return (parent:GetID() + ((page - 1) * NUM_ACTIONBAR_BUTTONS));
		else
			return parent:GetEffectiveAttribute("action", button) or self:GetAttribute("$action");
		end
	]=])
	
	self:SetAttribute("$funcGetFlyoutActions", [=[ -- self
		-- similar to L.FlyoutIsFlyout in restriceted env
		local slot = ...
		local flyout = self:GetFrameRef("CustomFlyout")
		if slot
		then
			local val
			local actionType, id = GetActionInfo(slot)
			if actionType == "macro"
			then
				val = flyout:GetAttribute("$macro"..id)
				if val
				then
					return val, id
				end
			end
			if actionType
			then
				val = flyout:GetAttribute("$action"..slot)
				if val
				then
					return val
				end
			end
		end
		return nil
	]=])	
	
	self:SetFrameRef("CustomFlyout", flyout)
	
    self:HookScript('OnEnter', L.ProxyButtonOnEnter)
    self:HookScript('OnLeave', L.ProxyButtonOnLeave)
	self:HookScript("OnShow", L.ProxyButtonUpdate)
	
	self:SetPoint("CENTER", parent, "CENTER")
	if parent
	then
		self:SetFrameStrata(parent:GetFrameStrata())
		self:SetFrameLevel(parent:GetFrameLevel()+10)
		self:SetScale(parent:GetWidth()/self:GetWidth())
		local name = parent:GetName() or ""
		if name:find("^ActionButton%d+$") or name:find("^MultiBarBottomLeftButton%d+$") or name:find("^MultiBarBottomRightButton%d+$")
		then
			self:SetAttribute("$blizzard", true)
		elseif name:find("^MultiBarLeftButton%d+$") or name:find("^MultiBarRightButton%d+$")
		then
			self:SetAttribute("$defaultdirection", "LEFT")
			self:SetAttribute("$blizzard", true)
		end
	else
		self:SetScale(1)
	end
	
	if parent.action
	then
		self:SetAttribute("*type1", "macro")
		self:SetAttribute("*type2", "macro")
		self:SetAttribute("*macrotext1", "/click "..parentName)
		self:SetAttribute("*macrotext2", "/click "..parentName.." RightButton ")
		self:SetAttribute("$action", parent.action)
	end
	
	self:Show()
	
	if onsuccess
	then
		onsuccess(self)
	end
end

function L.ProxyButtonOnEnter(self, ...)
	L.ProxyButtonUpdate(self)
	local parent = self:GetParent()
	local handler = parent:GetScript("OnEnter")
	if handler and not self:GetAttribute("$blizzard")
	then
		handler(parent, ...)
	else
		if ( GetCVar("UberTooltips") == "1" )
		then
			GameTooltip_SetDefaultAnchor(GameTooltip, self)
		else
			local pparent = parent:GetParent()
			if ( pparent == MultiBarBottomRight or pparent == MultiBarRight or pparent == MultiBarLeft )
			then
				GameTooltip:SetOwner(self, "ANCHOR_LEFT");
			else
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			end
		end
		GameTooltip:SetAction(parent.action)
	end

end

function L.ProxyButtonOnLeave(self, ...)
	L.ProxyButtonUpdate(self)
	local parent = self:GetParent()
	local handler = parent:GetScript("OnLeave")
	if handler and not self:GetAttribute("$blizzard")
	then
		handler(parent, ...)
	else
		GameTooltip:Hide()
	end
end

function L.ProxyButtonUpdate(self)
	L.ProxyButtonUpdateArrowBorder(self)
	L.ProxyButtonUpdateClickTrough(self)
	if not InCombatLockdown()
	then
		flyout:SetAttribute("$lockbars", LOCK_ACTIONBAR)
		if self.action
		then
			self.SetAttribute("$action", self.action)
		end
	end
end

function L.ProxyButtonUpdateClickTrough(self)
	if not InCombatLockdown()
	then
		local action = L.ProxyButtonCalculateAction(self)
		local isFlyout, macroid = L.FlyoutIsFlyout(action)
		self:EnableMouse(isFlyout)
		if macroid ~= nil
		then
			local macrobody = GetMacroBody(macroid)
			self:SetAttribute("macro", macroid)
			self:SetAttribute("*macrotext1", nil)
			self:SetAttribute("*macrotext2", nil)
		else
			local parent = self:GetParent()
			local parentName = parent:GetName()
			self:SetAttribute("*macrotext1", "/click "..parentName)
			self:SetAttribute("*macrotext2", "/click "..parentName.." RightButton ")
		end
	end
end

function L.ProxyButtonCalculateAction(self, button)
	local parent = self:GetParent()
	if ( not button ) 
	then
		button = "LeftButton"
	end
	if ( parent:GetID() > 0 )
	then
		local page = SecureButton_GetModifiedAttribute(parent, "actionpage", button);
		if ( not page ) 
		then
			page = GetActionBarPage();
		end
		return (parent:GetID() + ((page - 1) * NUM_ACTIONBAR_BUTTONS));
	else
		return SecureButton_GetModifiedAttribute(parent, "action", button) or self:GetAttribute("$action");
	end
end

function L.FlyoutIsFlyout(slot)
	if slot
	then
		local actionType, id = GetActionInfo(slot)
		if actionType == "macro"
		then
			if flyout:GetAttribute("$macro"..id)
			then
				return true, id
			end
		end
		if actionType
		then
			if flyout:GetAttribute("$action"..slot)
			then
				return true
			end
		end
	end
	return false
end

L.GetMouseFocus = GetMouseFocus or function()
	local foci = GetMouseFoci() 
	if foci[1] ~= nil and foci[1][0] ~= nil
	then
		return foci[1][0]
	end
	return nil	
end

function L.ProxyButtonUpdateArrowBorder(self)
	local action = L.ProxyButtonCalculateAction(self)
	local isFlyout, macroid = L.FlyoutIsFlyout(action)
	
	if isFlyout 
	then
		local direction = self:GetAttribute("$direction") or flyout:GetAttribute("$directionAction"..action) or flyout:GetAttribute("$directionMacro"..macroid) or self:GetAttribute("$defaultdirection") or "UP"
		local clicked = (flyout:GetParent()==self and flyout:IsVisible()) or (L.GetMouseFocus() == self)
		
		local arrowDistance
		if clicked then
			self.FlyoutBorder:Show()
			self.FlyoutBorderShadow:Show()
			arrowDistance = 5
		else
			self.FlyoutBorder:Hide()
			self.FlyoutBorderShadow:Hide()
			arrowDistance = 2
		end
		self.FlyoutArrow:Show()
			
		-- Update arrow
		self.FlyoutArrow:Show()
		self.FlyoutArrow:ClearAllPoints()
		if (direction == "LEFT") then
			self.FlyoutArrow:SetPoint("LEFT", self, "LEFT", -arrowDistance, 0)
			SetClampedTextureRotation(self.FlyoutArrow, 270)
		elseif (direction == "RIGHT") then
			self.FlyoutArrow:SetPoint("RIGHT", self, "RIGHT", arrowDistance, 0)
			SetClampedTextureRotation(self.FlyoutArrow, 90)
		elseif (direction == "DOWN") then
			self.FlyoutArrow:SetPoint("BOTTOM", self, "BOTTOM", 0, -arrowDistance)
			SetClampedTextureRotation(self.FlyoutArrow, 180)
		else
			self.FlyoutArrow:SetPoint("TOP", self, "TOP", 0, arrowDistance)
			SetClampedTextureRotation(self.FlyoutArrow, 0)
		end
	else
		self.FlyoutBorder:Hide()
		self.FlyoutBorderShadow:Hide()
		self.FlyoutArrow:Hide()
	end
end

end