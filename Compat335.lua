--[[
Compat335.lua

Compatibility shims that let the modern AutoGear.lua run on the World of Warcraft
3.3.5a (Wrath of the Lich King, interface 30300) client used by private servers.

The modern addon targets the retail/Classic API family (Enum.*, the Item mixin,
C_Item / C_PlayerInfo / C_GossipInfo namespaces, GetItemInfoInstant, ColorMixin
helpers). None of those exist on 3.3.5a, but everything the addon needs can be
recovered from the 3.3.5a globals (GetItemInfo, GetContainerItemLink,
GetAuctionItemClasses, UnitSex, the gossip globals, ...).

Everything here is defined only when the modern API is absent, so the file is a
no-op on any client that already provides these APIs. AutoGear.lua captures a
number of these as file-locals at load time, so this file MUST load first (see
AutoGear.toc).
]]

local _ = ...

--------------------------------------------------------------------------------
-- Enum: numeric item constants. On 3.3.5a these carry the canonical modern
-- values so that item class/subclass/inventory-type IDs derived below compare
-- correctly against Enum.* throughout AutoGear.lua.
--------------------------------------------------------------------------------
Enum = Enum or {}

if not Enum.InventoryType then
	Enum.InventoryType = {
		IndexNonEquipType = 0, IndexHeadType = 1, IndexNeckType = 2,
		IndexShoulderType = 3, IndexBodyType = 4, IndexChestType = 5,
		IndexWaistType = 6, IndexLegsType = 7, IndexFeetType = 8,
		IndexWristType = 9, IndexHandType = 10, IndexFingerType = 11,
		IndexTrinketType = 12, IndexWeaponType = 13, IndexShieldType = 14,
		IndexRangedType = 15, IndexCloakType = 16, Index2HweaponType = 17,
		IndexBagType = 18, IndexTabardType = 19, IndexRobeType = 20,
		IndexWeaponmainhandType = 21, IndexWeaponoffhandType = 22,
		IndexHoldableType = 23, IndexAmmoType = 24, IndexThrownType = 25,
		IndexRangedrightType = 26, IndexQuiverType = 27, IndexRelicType = 28,
	}
end

if not Enum.ItemClass then
	Enum.ItemClass = {
		Consumable = 0, Container = 1, Weapon = 2, Gem = 3, Armor = 4,
		Reagent = 5, Projectile = 6, Tradegoods = 7, ItemEnhancement = 8,
		Recipe = 9, Money = 10, Quiver = 11, Quest = 12, Key = 13,
		Permanent = 14, Miscellaneous = 15, Glyph = 16, Battlepet = 17,
		WoWToken = 18,
	}
end

if not Enum.ItemWeaponSubclass then
	Enum.ItemWeaponSubclass = {
		Axe1H = 0, Axe2H = 1, Bows = 2, Guns = 3, Mace1H = 4, Mace2H = 5,
		Polearm = 6, Sword1H = 7, Sword2H = 8, Warglaive = 9, Staff = 10,
		Bearclaw = 11, Catclaw = 12, Unarmed = 13, Generic = 14, Dagger = 15,
		Thrown = 16, Obsolete3 = 17, Crossbow = 18, Wand = 19, Fishingpole = 20,
	}
end

if not Enum.ItemArmorSubclass then
	Enum.ItemArmorSubclass = {
		Generic = 0, Cloth = 1, Leather = 2, Mail = 3, Plate = 4, Cosmetic = 5,
		Shield = 6, Libram = 7, Idol = 8, Totem = 9, Sigil = 10, Relic = 11,
	}
end

if not Enum.ItemMiscellaneousSubclass then
	Enum.ItemMiscellaneousSubclass = {
		Junk = 0, Reagent = 1, CompanionPet = 2, Holiday = 3, Other = 4,
		Mount = 5,
	}
end

if not Enum.TooltipDataType then
	Enum.TooltipDataType = { Item = 0 }
end

-- Nothing below is needed on a client that already has the Item mixin (which is
-- the definitive modern-API marker); bail out to keep this a strict no-op there.
if Item then return end

--------------------------------------------------------------------------------
-- itemEquipLoc ("INVTYPE_*") -> Enum.InventoryType index. The INVTYPE_* keys
-- returned by GetItemInfo are locale-independent, so this map is exact.
--------------------------------------------------------------------------------
local INVTYPE_TO_INDEX = {
	[""] = 0,
	INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_BODY = 4,
	INVTYPE_CHEST = 5, INVTYPE_ROBE = 20, INVTYPE_WAIST = 6, INVTYPE_LEGS = 7,
	INVTYPE_FEET = 8, INVTYPE_WRIST = 9, INVTYPE_HAND = 10, INVTYPE_FINGER = 11,
	INVTYPE_TRINKET = 12, INVTYPE_CLOAK = 16, INVTYPE_WEAPON = 13,
	INVTYPE_SHIELD = 14, INVTYPE_2HWEAPON = 17, INVTYPE_WEAPONMAINHAND = 21,
	INVTYPE_WEAPONOFFHAND = 22, INVTYPE_HOLDABLE = 23, INVTYPE_RANGED = 15,
	INVTYPE_THROWN = 25, INVTYPE_RANGEDRIGHT = 26, INVTYPE_RELIC = 28,
	INVTYPE_TABARD = 19, INVTYPE_BAG = 18, INVTYPE_QUIVER = 27,
	INVTYPE_AMMO = 24,
}

--------------------------------------------------------------------------------
-- Numeric item class/subclass IDs. 3.3.5a's GetItemInfo only returns localized
-- class/subclass strings, so build a locale-independent name->ID map from the
-- client's own auction categories (GetAuctionItemClasses /
-- GetAuctionItemSubClasses), whose ordering is fixed by ItemSubClass.dbc.
--------------------------------------------------------------------------------
local IC = Enum.ItemClass
local WSC = Enum.ItemWeaponSubclass
local ASC = Enum.ItemArmorSubclass
local MSC = Enum.ItemMiscellaneousSubclass

-- Auction category position -> canonical Enum.ItemClass value (3.3.5a order).
local AUCTION_CLASS_IDS = {
	IC.Weapon, IC.Armor, IC.Container, IC.Consumable, IC.Glyph, IC.Tradegoods,
	IC.Projectile, IC.Quiver, IC.Recipe, IC.Gem, IC.Miscellaneous, IC.Quest,
}

-- Auction subcategory position -> canonical subclass value, for the classes
-- AutoGear inspects. Obsolete subclasses are omitted from the auction list, so
-- these skip the corresponding IDs (e.g. weapon 9/11/12/17).
local AUCTION_SUBCLASS_IDS = {
	[IC.Weapon] = {
		WSC.Axe1H, WSC.Axe2H, WSC.Bows, WSC.Guns, WSC.Mace1H, WSC.Mace2H,
		WSC.Polearm, WSC.Sword1H, WSC.Sword2H, WSC.Staff, WSC.Unarmed,
		WSC.Generic, WSC.Dagger, WSC.Thrown, WSC.Crossbow, WSC.Wand,
		WSC.Fishingpole,
	},
	[IC.Armor] = {
		ASC.Generic, ASC.Cloth, ASC.Leather, ASC.Mail, ASC.Plate, ASC.Shield,
		ASC.Libram, ASC.Idol, ASC.Totem, ASC.Sigil,
	},
	[IC.Miscellaneous] = {
		MSC.Junk, MSC.Reagent, MSC.CompanionPet, MSC.Holiday, MSC.Other,
		MSC.Mount,
	},
}

-- Normalize a localized type/subtype name so GetItemInfo's form matches the
-- auction category form regardless of singular/plural spelling.
local IRREGULAR_PLURALS = { stave = "staff", staves = "staff" }
local function normName(name)
	name = tostring(name):lower():gsub("[^%a]", "")
	name = name:gsub("s$", "")
	return IRREGULAR_PLURALS[name] or name
end

local classNameToID, subNameToID
local function buildItemClassMaps()
	if classNameToID then return end
	classNameToID, subNameToID = {}, {}
	if type(GetAuctionItemClasses) ~= "function" then return end
	local classes = { GetAuctionItemClasses() }
	for i = 1, #classes do
		local name = classes[i]
		local classID = AUCTION_CLASS_IDS[i]
		if name and classID then
			classNameToID[name] = classID
			classNameToID[normName(name)] = classID
			local subIDs = AUCTION_SUBCLASS_IDS[classID]
			if subIDs and type(GetAuctionItemSubClasses) == "function" then
				local map = {}
				local subs = { GetAuctionItemSubClasses(i) }
				for j = 1, #subs do
					local sname, sid = subs[j], subIDs[j]
					if sname and sid ~= nil then
						map[sname] = sid
						map[normName(sname)] = sid
					end
				end
				subNameToID[classID] = map
			end
		end
	end
end

local function classSubclassFromNames(itemType, itemSubType)
	if not itemType then return nil, nil end
	buildItemClassMaps()
	local classID = classNameToID[itemType] or classNameToID[normName(itemType)]
	local subclassID
	if classID and subNameToID[classID] and itemSubType then
		local map = subNameToID[classID]
		subclassID = map[itemSubType] or map[normName(itemSubType)]
	end
	return classID, subclassID
end

local function itemIDFromLink(item)
	if type(item) == "number" then return item end
	if type(item) == "string" then
		return tonumber(item:match("item:(%d+)"))
	end
end

--------------------------------------------------------------------------------
-- GetItemInfoInstant: (itemID, itemType, itemSubType, itemEquipLoc, icon,
-- classID, subclassID). AutoGear uses the first value and select(6, ...).
--------------------------------------------------------------------------------
if not GetItemInfoInstant then
	function GetItemInfoInstant(item)
		if not item then return end
		local name, link, _, _, _, itemType, itemSubType, _, equipLoc, icon = GetItemInfo(item)
		local id = itemIDFromLink(item) or (link and itemIDFromLink(link))
		local classID, subclassID = classSubclassFromNames(itemType, itemSubType)
		return id, itemType, itemSubType, equipLoc, icon, classID, subclassID
	end
end

--------------------------------------------------------------------------------
-- C_Item: the namespaced item helpers AutoGear calls directly, plus the members
-- probed by its "X or (C_Item and C_Item.X)" fallbacks.
--------------------------------------------------------------------------------
C_Item = C_Item or {}
C_Item.GetItemInfo = C_Item.GetItemInfo or GetItemInfo
C_Item.GetItemInfoInstant = C_Item.GetItemInfoInstant or GetItemInfoInstant
C_Item.GetItemCount = C_Item.GetItemCount or GetItemCount

if not C_Item.GetItemInventoryTypeByID then
	function C_Item.GetItemInventoryTypeByID(item)
		local equipLoc = select(9, GetItemInfo(item))
		if not equipLoc then return nil end
		return INVTYPE_TO_INDEX[equipLoc] or 0
	end
end

if not C_Item.GetItemNameByID then
	function C_Item.GetItemNameByID(item)
		return (GetItemInfo(item))
	end
end

if not C_Item.GetItemLinkByGUID then
	-- 3.3.5a has no per-item GUIDs; nothing to resolve.
	function C_Item.GetItemLinkByGUID()
		return nil
	end
end

--------------------------------------------------------------------------------
-- ContinueOnItemLoad scheduler: poll GetItemInfo until item data resolves, then
-- fire the callback. Never fire on unresolved data (that would score/equip on
-- partial info); drop with a visible log after a bounded wait instead.
--------------------------------------------------------------------------------
local LOAD_TIMEOUT = 8 -- seconds
local pendingLoads = {}
local loadFrame

local function notifyLoadFailure(link)
	local msg = "AutoGear: item data never loaded for " .. tostring(link) .. "; skipping."
	if AutoGearPrint then AutoGearPrint(msg, 0) else print(msg) end
end

local function processLoads(_, elapsed)
	local n = #pendingLoads
	for i = n, 1, -1 do
		local entry = pendingLoads[i]
		entry.elapsed = entry.elapsed + elapsed
		if entry.link and GetItemInfo(entry.link) then
			table.remove(pendingLoads, i)
			entry.callback()
		elseif entry.elapsed >= LOAD_TIMEOUT then
			table.remove(pendingLoads, i)
			notifyLoadFailure(entry.link)
		end
	end
	if #pendingLoads == 0 then loadFrame:Hide() end
end

local function scheduleLoad(link, callback)
	if link and GetItemInfo(link) then
		callback()
		return
	end
	if not loadFrame then
		loadFrame = CreateFrame("Frame")
		loadFrame:Hide()
		loadFrame:SetScript("OnUpdate", processLoads)
	end
	pendingLoads[#pendingLoads + 1] = { link = link, callback = callback, elapsed = 0 }
	loadFrame:Show()
end

--------------------------------------------------------------------------------
-- Item mixin: modern item objects are async handles over an item location or
-- link. On 3.3.5a the underlying data is synchronous, so these are thin readers
-- over GetItemInfo / GetContainerItemLink / GetInventoryItemLink.
--------------------------------------------------------------------------------
Item = {}
local itemMethods = {}
local itemMeta = { __index = itemMethods }

local function newItem(fields)
	return setmetatable(fields, itemMeta)
end

function Item:CreateFromBagAndSlot(bag, slot) return newItem({ _bag = bag, _slot = slot }) end
function Item:CreateFromEquipmentSlot(inv) return newItem({ _inv = inv }) end
function Item:CreateFromItemLink(link) return newItem({ _link = link }) end
function Item:CreateFromItemID(id) return newItem({ _link = "item:" .. tostring(id) }) end
function Item:CreateFromItemLocation(location) return newItem({ _loc = location }) end

function itemMethods:_resolveLink()
	if self._link ~= nil then return self._link or nil end
	if self._bag ~= nil then
		self._link = GetContainerItemLink(self._bag, self._slot) or false
	elseif self._inv ~= nil then
		self._link = GetInventoryItemLink("player", self._inv) or false
	elseif self._loc and self._loc.GetLink then
		self._link = self._loc:GetLink() or false
	else
		self._link = false
	end
	return self._link or nil
end

function itemMethods:IsItemEmpty() return self:_resolveLink() == nil end
function itemMethods:GetItemLink() return self:_resolveLink() end
function itemMethods:GetItemID() return itemIDFromLink(self:_resolveLink()) end

function itemMethods:GetItemName()
	local link = self:_resolveLink()
	return link and (GetItemInfo(link)) or nil
end

function itemMethods:GetItemQuality()
	local link = self:_resolveLink()
	return link and select(3, GetItemInfo(link)) or nil
end

function itemMethods:GetItemQualityColor()
	local quality = self:GetItemQuality()
	if not quality then return end
	return GetItemQualityColor(quality)
end

function itemMethods:GetItemGUID() return nil end

function itemMethods:IsItemDataCached()
	local link = self:_resolveLink()
	return link ~= nil and GetItemInfo(link) ~= nil
end

function itemMethods:HasItemLocation()
	return (self._bag ~= nil) or (self._inv ~= nil)
end

function itemMethods:GetItemLocation()
	if self._bag ~= nil then
		local bag, slot = self._bag, self._slot
		return {
			GetBagAndSlot = function() return bag, slot end,
			IsBagAndSlot = function() return true end,
			IsEquipmentSlot = function() return false end,
			IsValid = function() return GetContainerItemLink(bag, slot) ~= nil end,
			HasAnyLocation = function() return true end,
		}
	elseif self._inv ~= nil then
		local inv = self._inv
		return {
			GetEquipmentSlot = function() return inv end,
			GetBagAndSlot = function() return nil, nil end,
			IsBagAndSlot = function() return false end,
			IsEquipmentSlot = function() return true end,
			IsValid = function() return GetInventoryItemLink("player", inv) ~= nil end,
			HasAnyLocation = function() return true end,
		}
	end
	return nil
end

function itemMethods:ContinueOnItemLoad(callback)
	scheduleLoad(self:_resolveLink(), callback)
end

--------------------------------------------------------------------------------
-- ExtractHyperlinkString: (found, linkType, linkString). AutoGear uses
-- select(3, ...) to feed Item:CreateFromItemLink.
--------------------------------------------------------------------------------
if not ExtractHyperlinkString then
	function ExtractHyperlinkString(text)
		if type(text) ~= "string" then return false end
		local payload = text:match("|H(.-)|h")
		if not payload then
			if text:match("^%a+:") then payload = text else return false end
		end
		return true, payload:match("^(%a+):"), payload
	end
end

--------------------------------------------------------------------------------
-- C_PlayerInfo / PlayerLocation: only GetSex is used. Modern GetSex uses
-- Enum.UnitSex (Male=0, Female=1, None=2); UnitSex() uses 2=male, 3=female.
--------------------------------------------------------------------------------
if not PlayerLocation then
	PlayerLocation = {}
	function PlayerLocation:CreateFromUnit(unit) return { unit = unit } end
end

C_PlayerInfo = C_PlayerInfo or {}
if not C_PlayerInfo.GetSex then
	function C_PlayerInfo.GetSex(location)
		local sex = UnitSex(location and location.unit or "player")
		if sex == 3 then return 1 elseif sex == 2 then return 0 end
		return 2
	end
end

--------------------------------------------------------------------------------
-- LocalizedClassList: modern AutoGear uses FillLocalizedClassList (Legion+) or
-- LocalizedClassList; 3.3.5a exposes neither, only the
-- LOCALIZED_CLASS_NAMES_MALE / _FEMALE tables.
--------------------------------------------------------------------------------
if not FillLocalizedClassList and not LocalizedClassList then
	function LocalizedClassList(isFemale)
		local source = isFemale and LOCALIZED_CLASS_NAMES_FEMALE or LOCALIZED_CLASS_NAMES_MALE
		local list = {}
		if source then
			for classFile, localizedName in pairs(source) do
				list[classFile] = localizedName
			end
		end
		return list
	end
end

--------------------------------------------------------------------------------
-- C_GossipInfo: maps the modern questID-based API onto 3.3.5a's index-based
-- gossip globals. Field strides come from 3.3.5a FrameXML/GossipFrame.lua:
-- available quests = 5 (isTrivial at +2), active quests = 4 (isComplete at +3).
-- SelectGossip*Quest takes a 1-based index, so we surface the index as questID.
--------------------------------------------------------------------------------
C_GossipInfo = C_GossipInfo or {}
if not C_GossipInfo.GetAvailableQuests then
	function C_GossipInfo.GetNumActiveQuests()
		return GetNumGossipActiveQuests and GetNumGossipActiveQuests() or 0
	end

	function C_GossipInfo.GetActiveQuests()
		local quests, data = {}, { GetGossipActiveQuests() }
		local count = C_GossipInfo.GetNumActiveQuests()
		for i = 1, count do
			local base = (i - 1) * 4
			quests[i] = {
				questID = i,
				title = data[base + 1],
				isTrivial = data[base + 3] and true or false,
				isComplete = data[base + 4] and true or false,
			}
		end
		return quests
	end

	function C_GossipInfo.SelectActiveQuest(questID)
		return SelectGossipActiveQuest(questID)
	end

	function C_GossipInfo.GetNumAvailableQuests()
		return GetNumGossipAvailableQuests and GetNumGossipAvailableQuests() or 0
	end

	function C_GossipInfo.GetAvailableQuests()
		local quests, data = {}, { GetGossipAvailableQuests() }
		local count = C_GossipInfo.GetNumAvailableQuests()
		for i = 1, count do
			local base = (i - 1) * 5
			quests[i] = {
				questID = i,
				title = data[base + 1],
				isTrivial = data[base + 3] and true or false,
			}
		end
		return quests
	end

	function C_GossipInfo.SelectAvailableQuest(questID)
		return SelectGossipAvailableQuest(questID)
	end
end

--------------------------------------------------------------------------------
-- C_Cursor: GetCursorItem returns an item-location-like handle over the cursor
-- item, used to read rarity for the equip-bind confirmation.
--------------------------------------------------------------------------------
C_Cursor = C_Cursor or {}
if not C_Cursor.GetCursorItem then
	function C_Cursor.GetCursorItem()
		local kind, arg1, arg2 = GetCursorInfo()
		if kind ~= "item" then return nil end
		local link = arg2 or (arg1 and select(2, GetItemInfo(arg1)))
		if not link then return nil end
		return { GetLink = function() return link end }
	end
end

--------------------------------------------------------------------------------
-- Miscellaneous runtime globals that modern AutoGear assumes exist.
--------------------------------------------------------------------------------
if not UnitClassBase then
	-- WotLK class IDs; UnitClass on 3.3.5a returns only (localizedName, token).
	local CLASS_TOKEN_TO_ID = {
		WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5,
		DEATHKNIGHT = 6, SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11,
	}
	function UnitClassBase(unit)
		local token = select(2, UnitClass(unit))
		return token, token and CLASS_TOKEN_TO_ID[token]
	end
end

if not IsPlayerSpell then
	function IsPlayerSpell(spellID)
		if IsSpellKnown then return IsSpellKnown(spellID) end
		local name = GetSpellInfo(spellID)
		return name ~= nil and GetSpellInfo(name) ~= nil
	end
end

if not CanDualWield then
	function CanDualWield()
		return IsPlayerSpell(674) -- Dual Wield
	end
end

if not GetDetailedItemLevelInfo then
	function GetDetailedItemLevelInfo(item)
		return (select(4, GetItemInfo(item)))
	end
end

-- Max-level helpers: 3.3.5a has neither GetMaxPlayerLevel nor
-- GetMaxLevelForExpansionLevel (both added in later expansions); it exposes the
-- MAX_PLAYER_LEVEL constant and GetExpansionLevel instead.
if not GetMaxLevelForExpansionLevel then
	local EXPANSION_MAX_LEVEL = { [0] = 60, [1] = 70, [2] = 80 }
	function GetMaxLevelForExpansionLevel(expansionLevel)
		return EXPANSION_MAX_LEVEL[expansionLevel] or MAX_PLAYER_LEVEL or 80
	end
end

if not GetMaxPlayerLevel then
	function GetMaxPlayerLevel()
		return MAX_PLAYER_LEVEL
			or GetMaxLevelForExpansionLevel(GetExpansionLevel and GetExpansionLevel() or 2)
	end
end

--------------------------------------------------------------------------------
-- Global strings modern AutoGear references that 3.3.5a lacks. The addon uses
-- these only in string.find(tooltipText, STRING); an absent (nil) value would
-- error. Battle.net-account binding does not exist in 3.3.5a, so this text
-- never appears in a tooltip and the value simply never matches.
--------------------------------------------------------------------------------
if not ITEM_BIND_TO_BNETACCOUNT then
	ITEM_BIND_TO_BNETACCOUNT = "Binds to Battle.net Account"
end

--------------------------------------------------------------------------------
-- PaperDollItemsFrame: introduced in Cataclysm. On 3.3.5a the equipment slot
-- buttons (CharacterHeadSlot, ...) are children of PaperDollFrame instead.
-- AutoGear only iterates its children to build cosmetic slot-name labels.
--------------------------------------------------------------------------------
if not PaperDollItemsFrame then
	PaperDollItemsFrame = PaperDollFrame or CreateFrame("Frame")
end

--------------------------------------------------------------------------------
-- ColorMixin helper: AutoGear calls RAID_CLASS_COLORS[class]:WrapTextInColorCode.
-- 3.3.5a class colors are plain {r,g,b} tables, so attach the method.
--------------------------------------------------------------------------------
local function WrapTextInColorCode(color, text)
	return string.format(
		"|cff%02x%02x%02x%s|r",
		math.floor((color.r or 1) * 255 + 0.5),
		math.floor((color.g or 1) * 255 + 0.5),
		math.floor((color.b or 1) * 255 + 0.5),
		text
	)
end

if RAID_CLASS_COLORS then
	for _, color in pairs(RAID_CLASS_COLORS) do
		if type(color) == "table" and not color.WrapTextInColorCode then
			color.WrapTextInColorCode = WrapTextInColorCode
		end
	end
end
