local doc = [=[ [options] subType, list1, list2, ...
[options] maximum one from each line, coma separated, optional
   left,right,up,down, defaults up for unknown buttons or default blizz frame direction
   item_ench_temp,conjure,spell,item,mixed defaults mixed
item_ench_temp elements (poisons, wrightstones, oils, etc, left click for MH, right click for OH)
   subType: dynamic or fixed
   list (for fixed): coma separated list of item ids or names
conjure elements (left click use, right click conjure spell)
   subType: dynamic or fixed
   list (for fixed): coma separated list of spell ids or names
spell elements
   subType: profession/portal/teleport/totem_earth/totem_fire/totem_air/totem_water/trap/track/aspect/warlockpet/fixed
   list (for fixed): coma separated list of spell ids or names
item element
   subType: fixed
   list (for fixed): coma separated list of item ids or names
mixed elements
   subType: fixed
   list: coma separated list of spell:id/item:id/macro:id, icon and tooltip are not dynamic for macros
]=]

--[[
TODO:
use internal GetSpellInfo with the ability to remap string to last known (eg classic water/food)
implement gui to create new macros with drag and drop
]]--

local ADDON, T = ...
local L = {}

_G["SLASH_"..ADDON.."1"] = "/flyout"

local LFF = LibStub:GetLibrary("LibFlyoutFrame-1.0")
assert(LFF, ADDON .. " requires LibFlyoutFrame")

	
local macros = {
	--[[ macroid={GetMacroInfo plus flyout at end} ]]-- 
}
local dynamiclist = {
	--[[ macroid={type="bag|spell", cache="dynamiccache", generator=generator, params={list, mainType, subType, dynamic} } ]]-- 
}

function L.UpdateMacros()
	local change = {}
	local oldmacros = macros
	macros = {}
	-- Slots 1-120 are used for general macros, and 121-138 for character-specific macros. 
	for id=1,138 --GetNumMacros()?
	do
		local oName, oIcon, oBody, oIsLocal, oFlyout = L.GetMacroInfoFlyout(id, oldmacros)
		local nName, nIcon, nBody, nIsLocal, nFlyout = L.GetMacroInfoFlyout(id)
		if oFlyout ~= nFlyout
		then
			table.insert(change, id)
			if nFlyout
			then
				local actions = {}
				local options, list = L.ParseSlashOptions(nFlyout)
				local generator, mainType, subType, dynamic
				generator, list, mainType, subType, dynamic = L.GetActionGeneratorParams(options, list)
				if generator
				then
					actions, dynamiccache = generator(list, mainType, subType, dynamic)
				end
				local dir = nil
				for _, option in ipairs(options)
				do
					if option=="left"
					then
						dir = "LEFT"
					elseif option=="right"
					then
						dir = "RIGHT"
					elseif option=="up"
					then
						dir = "UP"
					elseif option=="down"
					then
						dir = "DOWN"
					end
				end
				LFF.SetOverrideDirection("Macro"..id, dir)
				if dynamic
				then
					dynamiclist[id] = {
						["type"] = dynamic,
						["cache"] = dynamiccache,
						["generator"] = generator,
						["params"] = {list, mainType, subType, dynamic}
					}
				else
					dynamiclist[id] = nil
				end
				LFF.SetMacro(id, actions)
			else
				LFF.SetMacro(id, nil)
			end
		end
	end
	if #change>0
	then
		LFF.Update()
		L.CloseFlyoutOnMacro(change)
	end
end

function L.UpdateDynamic(dynamic)
	for id,item in pairs(dynamiclist)
	do
		if item["type"]==dynamic
		then
			local generator = item["generator"]
			local oldcache = item["cache"]
			if generator
			then
				local actions, dynamiccache = generator(unpack(item["params"]))
				if dynamiccache ~= oldcache
				then
					dynamiclist[id]["cache"]=dynamiccache
					LFF.SetMacro(id, actions)
				end
			end
		end
	end
end

function L.CloseFlyoutOnMacro(macroids) -- list of macroids
	local map = {}
	for slot=1,120
	do
		local t,id = GetActionInfo(slot) 
		if t=="macro"
		then
			map[id]=slot
		end
	end
	for _,id in ipairs(macroids)
	do
		LFF.ForceClose(map[id])
	end
end

local matchStartSlashCmd = "^".._G["SLASH_"..ADDON.."1"].." "

function L.GetMacroInfoFlyout(macroid, incache)
	local cache = incache or macros
	if cache[macroid]
	then
		return unpack(cache[macroid])
	end
	if incache then return end
	local name, icon, body, isLocal = GetMacroInfo(macroid)
	if name
	then
		isLocal = isLocal or false
		icon = icon or false
		body = body or ""
		local flyout
		for _,line in ipairs({strsplit("\n",body)})
		do 
			if line:match(matchStartSlashCmd)
			then
				flyout = strsub(line, #matchStartSlashCmd)
			end
		end
		cache[macroid] = {name, icon, body, isLocal, flyout}
		return name, icon, body, isLocal, flyout
	end
	return
end

local function trim(s)
	return s:gsub("^%s*(.-)%s*$", "%1")
end

function L.ParseSlashOptions(slash)
	local options = {}
	local list = {}
	
	local optstart, optend, optstr = string.find(slash, "^%s*%[([^%]]*)%]%s*")
	if optend
	then
		slash = strsub(slash, optend+1)
		options = {strsplit(",", optstr)}
	end
	if #slash>0
	then
		list = {strsplit(",", slash)}
	end
	for i=1,#options
	do
		options[i]=strlower(trim(options[i]))
	end
	for i=1,#list
	do
		list[i]=trim(list[i])
	end
	return options, list
end

function L.GenerateItemEnchant(item)
	local icon = item and "item:"..tostring(item)
	local macrotext
	if type(item)=="number" or tostring(tonumber(item))==item
	then
		macrotext = "/use item:"..item
	elseif item
	then
		macrotext ="/use "..item
	end
	macrotext = macrotext .. "\n/use [btn:1] 16; [btn:2] 17\n/click StaticPopup1Button1"
	return {["$icon"]=icon, ["type"]="macro", ["macrotext"]=macrotext}
end

function L.GenerateConjure(item)
	local spellName, _, _, _, _, _, spellId = GetSpellInfo(item)
	local rank = GetSpellSubtext(spellId)
	if rank
	then
		spellName = spellName .. "(" .. rank .. ")"
	end
	local itemId = T.DB.conjureSpellItemMap[spellId]
	if type(itemId)=="table"
	then
		local i = select(5, GetTalentInfo(itemId[1], itemId[2]))
		itemId = i and itemId[i+3] or nil
	end
	local icon = itemId and "item:"..tostring(itemId)
	local macrotext = "/use item:"..tostring(itemId)
	return {["$icon"]=icon, ["*type1"]="macro", ["*macrotext1"]=macrotext, ["*type2"]="spell", ["spell2"]=spellName}
end

function L.GenerateSpell(item)
	local name, _, _, _, _, _, spellId = GetSpellInfo(item)
	local rank = GetSpellSubtext(spellId)
	if rank
	then
		name = name .. "(" .. rank .. ")"
	end
	local icon = "spell:"..tostring(spellId)
	return {["$icon"]=icon, ["type"]="spell", ["spell"]=name}
end

function L.GenerateItem(item)
	local icon = item and "item:"..tostring(item)
	local macrotext
	if type(item)=="number" or tostring(tonumber(item))==item
	then
		macrotext = "/use item:"..item
	elseif item
	then
		macrotext ="/use "..item
	end
	return {["$icon"]=icon, ["type"]="macro", ["macrotext"]=macrotext}
end

function L.GenerateMacro(macro)
	local name, icon = GetMacroInfo(macro)
	icon = "texture:"..tostring(icon)..":"..tostring(name)
	return {["$icon"]=icon, ["type"]="macro", ["macro"]=macro}
end

function L.ActionGeneratorItemEnchant(list, mainType, subType, dynamic)
	local dynamiccache = nil
	if dynamic
	then
		list = {}
		local set = {}
		for bag=0,NUM_BAG_SLOTS
		do
			for slot=1,GetContainerNumSlots(bag)
			do
				local id = GetContainerItemID(bag,slot)
				if id and T.DB.item_ench_temp[id] and not set[id]
				then
					table.insert(list, id)
					set[id]=true
				end
			end
		end
		table.sort(list)
		dynamiccache = table.concat(list,",")
	end
	local actions = {}
	for i=1,math.min(10, #list)
	do
		local item = list[i]
		table.insert(actions, L.GenerateItemEnchant(item))
	end
	return actions, dynamiccache
end

function L.ActionGeneratorConjure(list, mainType, subType, dynamic)
	local dynamiccache = nil
	if dynamic
	then
		list = {}
		for _, spellName in ipairs(T.DB.conjure)
		do
			local spellId = select(7, GetSpellInfo(spellName))
			if spellId
			then
				table.insert(list, spellId)
			end
		end
		dynamiccache = table.concat(list,",")
	end
	local actions = {}
	for i=1,math.min(10, #list)
	do
		local item = list[i]
		table.insert(actions, L.GenerateConjure(item))
	end
	return actions, dynamiccache
end

function L.ActionGeneratorSpell(list, mainType, subType, dynamic)
	local dynamiccache = nil
	local lookup = T.DB.spells[subType]
	if dynamic and subType and lookup
	then
		list = {}
		for _, spellName in ipairs(lookup)
		do
			local spellId = select(7, GetSpellInfo(spellName))
			if spellId
			then
				table.insert(list, spellId)
			end
		end
		dynamiccache = table.concat(list,",")
	end
	local actions = {}
	for i=1,math.min(10, #list)
	do
		local item = list[i]
		table.insert(actions, L.GenerateSpell(item))
	end
	return actions, dynamiccache
end

function L.ActionGeneratorItem(list, mainType, subType, dynamic)
	local actions = {}
	for i=1,math.min(10, #list)
	do
		local item = list[i]
		table.insert(actions, L.GenerateItem(item))
	end
	return actions
end

function L.ActionGeneratorMixed(list, mainType, subType, dynamic)
	local actions = {}
	for i=1,math.min(10, #list)
	do
		local item = list[i]
		local itype, id = strsplit(":", item, 2)
		if itype == "item" and id
		then
			table.insert(actions, L.GenerateItem(id))
		elseif itype == "spell" and id
		then
			table.insert(actions, L.GenerateSpell(id))
		elseif itype == "macro" and id
		then
			table.insert(actions, L.GenerateMacro(id))
		end
	end
	return actions
end
	

function L.GetActionGeneratorParams(options, list)
	local listorig = list
	list = {}
	for _, element in ipairs(listorig)
	do
		table.insert(list, element)
	end
	local mainType = "mixed"
	local subType = nil
	
	for _, option in ipairs(options)
	do
		if option=="item_ench_temp" or option=="conjure" or option=="spell" or option=="item"
		then
			mainType = option
		end
	end
	local actions = nil
	local dynamic = nil
	local generator = nil
	if mainType=="item_ench_temp"
	then
		if list[1]=="dynamic"
		then
			subType = table.remove(list, 1)
			dynamic = "bag"
		elseif list[1]=="fixed"
		then
			subType = table.remove(list, 1)
		end
		generator = L.ActionGeneratorItemEnchant
	elseif mainType=="conjure"
	then
		if list[1]=="dynamic"
		then
			subType = table.remove(list, 1)
			dynamic = "spell"
		elseif list[1]=="fixed"
		then
			subType = table.remove(list, 1)
		end
		generator = L.ActionGeneratorConjure
	elseif mainType=="spell"
	then
		if list[1] and T.DB.spells[list[1]]
		then
			subType = table.remove(list, 1)
			dynamic = "spell"
		elseif list[1]=="fixed"
		then
			subType = table.remove(list, 1)
		end
		generator = L.ActionGeneratorSpell
	elseif mainType=="item"
	then
		if list[1]=="fixed"
		then
			subType = table.remove(list, 1)
		end
		generator = L.ActionGeneratorItem
	else
		if list[1]=="fixed"
		then
			subType = table.remove(list, 1)
		end
		generator = L.ActionGeneratorMixed
	end
	
	return generator, list, mainType, subType, dynamic
end

local function ProcessCommand(msg)
	local _, _, cmd, args = string.find(msg or "", "%s?(%w+)%s?(.*)")
	local cmdlower = strlower(cmd or "")
	if not cmd or cmdlower == "help" or cmdlower == ""
	then
		for _,line in ipairs({strsplit("\n",("Syntax: " .. _G["SLASH_"..ADDON.."1"] .. doc))})
		do 
			print(line)
		end
	elseif cmdlower == "gui"
	then
		print("TODO GUI")
		LFF.Update()
	end
end

local function Init()
	--print(ADDON .. " loaded, for more information type /flyout")
end

local worldEnterd = false
local function OnEvent(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON
	then
		self:UnregisterEvent("ADDON_LOADED")
		SlashCmdList[ADDON] = ProcessCommand
		Init()
	elseif event == "PLAYER_ENTERING_WORLD"
	then
		LFF.Init()
		L.UpdateMacros()
		worldEnterd = true
	elseif event == "UPDATE_MACROS" and worldEnterd
	then
		L.UpdateMacros()
	elseif event == "BAG_UPDATE" and worldEnterd
	then
		L.UpdateDynamic("bag")
	elseif event == "LEARNED_SPELL_IN_TAB" and worldEnterd
	then
		L.UpdateDynamic("spell")
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UPDATE_MACROS")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("LEARNED_SPELL_IN_TAB")
frame:SetScript("OnEvent", OnEvent)


