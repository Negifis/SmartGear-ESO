----------------------------------------------------------------------
-- SmartGear — Core Scoring Engine
----------------------------------------------------------------------
SmartGear = SmartGear or {}

-- Rating constants
SmartGear.RATING_RECOMMENDED = 4   -- ★★★ + meta
SmartGear.RATING_GOOD        = 3   -- ★★★
SmartGear.RATING_DECENT      = 2   -- ★★☆
SmartGear.RATING_MAYBE       = 1   -- ★☆☆
SmartGear.RATING_BAD         = 0   -- ☆☆☆
SmartGear.RATING_STICKERBOOK = -1  -- collect for another role

----------------------------------------------------------------------
-- Get currently equipped set IDs for synergy detection
----------------------------------------------------------------------
local function GetEquippedSets()
    local sets = {}
    for slot = 0, 16 do
        local itemLink = GetItemLink(BAG_WORN, slot)
        if itemLink and itemLink ~= "" then
            local hasSet, setName, numBonuses, numEquipped, maxEquipped, setId = GetItemLinkSetInfo(itemLink, true)
            if hasSet and setId then
                if not sets[setId] then
                    sets[setId] = {
                        name = setName,
                        equipped = numEquipped,
                        max = maxEquipped,
                        id = setId,
                    }
                end
            end
        end
    end
    return sets
end

----------------------------------------------------------------------
-- Check if item's set matches any equipped set
----------------------------------------------------------------------
local function CheckSetSynergy(itemLink, equippedSets)
    local hasSet, setName, numBonuses, numEquipped, maxEquipped, setId = GetItemLinkSetInfo(itemLink, false)
    if not hasSet then
        return nil, nil, nil, nil
    end

    local isEquippedSet = false
    local currentCount = 0
    local maxCount = maxEquipped or 5

    if equippedSets[setId] then
        isEquippedSet = true
        currentCount = equippedSets[setId].equipped
    end

    return setName, isEquippedSet, currentCount, maxCount
end

----------------------------------------------------------------------
-- Look up set in meta database
----------------------------------------------------------------------
local function GetMetaInfo(setName)
    if not setName then return nil end
    -- Try exact match first
    local meta = SmartGear.MetaSets[setName]
    if meta then return meta end

    -- Try case-insensitive / partial match
    local lowerName = string.lower(setName)
    for name, data in pairs(SmartGear.MetaSets) do
        if string.lower(name) == lowerName then
            return data
        end
    end
    return nil
end

----------------------------------------------------------------------
-- Check if set is relevant for a role
----------------------------------------------------------------------
local function IsSetForRole(metaInfo, role, pvpMode)
    if not metaInfo or not metaInfo.roles then return false end
    if metaInfo.pvpOnly and not pvpMode then return false end
    for _, r in ipairs(metaInfo.roles) do
        if r == role then return true end
    end
    return false
end

----------------------------------------------------------------------
-- Check if set is relevant for ANY role (for stickerbook recommendation)
----------------------------------------------------------------------
local function IsSetForAnyRole(metaInfo)
    if not metaInfo then return false end
    return metaInfo.tier == "S" or metaInfo.tier == "A"
end

----------------------------------------------------------------------
-- Evaluate armor trait quality for role
----------------------------------------------------------------------
local function EvaluateArmorTrait(traitType, role, pvpMode)
    local config = SmartGear.RoleConfig[role]
    if not config then return "unknown", false end

    if pvpMode then
        if config.pvpTraits and config.pvpTraits[traitType] then
            return "optimal", true
        end
    else
        if config.optimalTraits and config.optimalTraits[traitType] then
            return "optimal", true
        end
    end

    -- Infused is always acceptable on large pieces
    if traitType == ITEM_TRAIT_TYPE_ARMOR_INFUSED then
        return "good", false
    end

    -- Training is never good for endgame
    if traitType == ITEM_TRAIT_TYPE_ARMOR_TRAINING then
        return "bad", false
    end

    return "suboptimal", false
end

----------------------------------------------------------------------
-- Evaluate jewelry trait quality
----------------------------------------------------------------------
local function EvaluateJewelryTrait(traitType, role)
    local config = SmartGear.RoleConfig[role]
    if not config then return "unknown", false end

    if config.optimalJewelryTrait and config.optimalJewelryTrait[traitType] then
        return "optimal", true
    end

    -- Infused is generally acceptable
    if traitType == ITEM_TRAIT_TYPE_JEWELRY_INFUSED then
        return "good", false
    end

    return "suboptimal", false
end

----------------------------------------------------------------------
-- Evaluate weapon trait quality
----------------------------------------------------------------------
local function EvaluateWeaponTrait(traitType, role)
    local config = SmartGear.RoleConfig[role]
    if not config then return "unknown", false end

    if config.optimalWeaponTraits and config.optimalWeaponTraits[traitType] then
        return "optimal", true
    end

    return "suboptimal", false
end

----------------------------------------------------------------------
-- Check armor weight fitness
----------------------------------------------------------------------
local function EvaluateArmorWeight(armorType, role)
    local config = SmartGear.RoleConfig[role]
    if not config then return false end
    return config.optimalWeights and config.optimalWeights[armorType] or false
end

----------------------------------------------------------------------
-- MAIN SCORING FUNCTION
-- Returns a table with all evaluation details
----------------------------------------------------------------------
function SmartGear.EvaluateItem(bagId, slotIndex)
    local itemLink = GetItemLink(bagId, slotIndex)
    if not itemLink or itemLink == "" then return nil end

    local itemType = GetItemType(bagId, slotIndex)
    -- Only evaluate equipment
    if itemType ~= ITEMTYPE_ARMOR and itemType ~= ITEMTYPE_WEAPON and itemType ~= ITEMTYPE_JEWELRYCRAFTING
       and GetItemLinkItemType(itemLink) ~= ITEMTYPE_ARMOR
       and GetItemLinkItemType(itemLink) ~= ITEMTYPE_WEAPON then
        -- Check via link as fallback
        local linkItemType = GetItemLinkItemType(itemLink)
        if linkItemType ~= ITEMTYPE_ARMOR and linkItemType ~= ITEMTYPE_WEAPON then
            return nil
        end
    end

    local role = SmartGear.currentRole or "MagDD"
    local pvpMode = SmartGear.savedVars and SmartGear.savedVars.pvpMode or false
    local equippedSets = GetEquippedSets()

    local result = {
        itemLink = itemLink,
        role = role,
        rating = SmartGear.RATING_BAD,
        stars = 0,
        -- Set info
        setName = nil,
        isMetaSet = false,
        metaTier = nil,
        metaNotes = nil,
        isForCurrentRole = false,
        isForAnyRole = false,
        isEquippedSet = false,
        setEquipped = 0,
        setMax = 0,
        completesSet = false,
        -- Trait info
        traitName = nil,
        traitQuality = "unknown",  -- optimal/good/suboptimal/bad
        isOptimalTrait = false,
        -- Weight info
        armorWeight = nil,
        isOptimalWeight = true,  -- default true for non-armor
        -- Quality
        quality = GetItemLinkQuality(itemLink),
        -- Level & stats
        itemLevel = 0,
        requiredLevel = 0,
        requiredCP = 0,
        -- Flags
        isMythic = false,
        isMonsterSet = false,
        isPvpSet = false,
        recommendTransmute = false,
    }

    -- === LEVEL ANALYSIS ===
    local hasReqLevel, reqLevel, hasReqCP, reqCP = GetItemLinkGlyphMinLevels(itemLink)
    result.requiredLevel = GetItemRequiredLevel(bagId, slotIndex) or 0
    result.requiredCP = GetItemRequiredChampionPoints(bagId, slotIndex) or 0
    -- Effective item level: CP160 = max, lower = weaker
    if result.requiredCP > 0 then
        result.itemLevel = 50 + result.requiredCP
    else
        result.itemLevel = result.requiredLevel
    end

    -- === SET ANALYSIS ===
    local setName, isEquippedSet, currentCount, maxCount = CheckSetSynergy(itemLink, equippedSets)
    result.setName = setName

    if setName then
        result.isEquippedSet = isEquippedSet or false
        result.setEquipped = currentCount or 0
        result.setMax = maxCount or 5

        -- Would this item complete or advance the set?
        if isEquippedSet and currentCount and maxCount then
            result.completesSet = (currentCount + 1) >= maxCount
        end

        local metaInfo = GetMetaInfo(setName)
        if metaInfo then
            result.isMetaSet = true
            result.metaTier = metaInfo.tier
            result.metaRating = metaInfo.rating or 50
            result.metaNotes = metaInfo.notes
            result.isMythic = metaInfo.isMythic or false
            result.isMonsterSet = metaInfo.isMonsterSet or false
            result.isPvpSet = metaInfo.pvpOnly or false
            result.isForCurrentRole = IsSetForRole(metaInfo, role, pvpMode)
            result.isForAnyRole = IsSetForAnyRole(metaInfo)
        end
    end

    -- === TRAIT ANALYSIS ===
    local traitType = GetItemTrait(bagId, slotIndex)
    if traitType and traitType ~= ITEM_TRAIT_TYPE_NONE then
        result.traitName = SmartGear.TraitNames[traitType] or GetString("SI_ITEMTRAITTYPE", traitType)

        local equipType = GetItemLinkEquipType(itemLink)
        -- Determine if jewelry, weapon, or armor
        if equipType == EQUIP_TYPE_NECK or equipType == EQUIP_TYPE_RING then
            result.traitQuality, result.isOptimalTrait = EvaluateJewelryTrait(traitType, role)
        elseif equipType == EQUIP_TYPE_MAIN_HAND or equipType == EQUIP_TYPE_OFF_HAND
            or equipType == EQUIP_TYPE_ONE_HAND or equipType == EQUIP_TYPE_TWO_HAND then
            result.traitQuality, result.isOptimalTrait = EvaluateWeaponTrait(traitType, role)
        else
            result.traitQuality, result.isOptimalTrait = EvaluateArmorTrait(traitType, role, pvpMode)
        end

        -- Should we recommend transmute?
        if result.isMetaSet and result.isForCurrentRole and not result.isOptimalTrait then
            result.recommendTransmute = true
        end
    end

    -- === ARMOR WEIGHT ANALYSIS ===
    local armorType = GetItemArmorType(bagId, slotIndex)
    if armorType and armorType ~= ARMORTYPE_NONE then
        result.armorWeight = armorType
        result.isOptimalWeight = EvaluateArmorWeight(armorType, role)
    end

    -- === COMPUTE FINAL RATING ===
    local score = 0

    if result.isMetaSet and result.isForCurrentRole then
        -- Meta set for current role: tier base + internal rating bonus
        local tierBase = 10
        if result.metaTier == "S" then tierBase = 40
        elseif result.metaTier == "A" then tierBase = 30
        elseif result.metaTier == "B" then tierBase = 20 end

        -- Internal rating (0-100) adds up to +10 bonus within tier
        -- So S-tier rating 100 = 50, S-tier rating 30 = 43
        local ratingBonus = 0
        if result.metaRating and result.metaRating > 0 then
            ratingBonus = math.floor(result.metaRating / 10)
        end
        score = score + tierBase + ratingBonus
    elseif result.setName and not result.isMetaSet then
        -- Has set but not in meta DB — neutral
        score = score + 5
    elseif not result.setName then
        -- No set at all
        score = score + 0
    end

    -- Trait scoring
    if result.isOptimalTrait then
        score = score + 20
    elseif result.traitQuality == "good" then
        score = score + 10
    elseif result.traitQuality == "suboptimal" then
        score = score + 3
    elseif result.traitQuality == "bad" then
        score = score - 5
    end

    -- Weight scoring
    if result.isOptimalWeight then
        score = score + 10
    else
        score = score - 5
    end

    -- Set synergy bonus
    if result.completesSet then
        score = score + 15
    elseif result.isEquippedSet then
        score = score + 8
    end

    -- Quality bonus
    if result.quality then
        if result.quality == ITEM_DISPLAY_QUALITY_LEGENDARY then
            score = score + 5
        elseif result.quality == ITEM_DISPLAY_QUALITY_ARTIFACT then
            score = score + 3
        end
    end

    -- Item level scoring (CP160 = max = 210 effective)
    -- Higher level items have better base stats
    if result.itemLevel > 0 then
        local maxLevel = 210  -- 50 + CP160
        local levelRatio = result.itemLevel / maxLevel
        score = score + math.floor(levelRatio * 15)  -- up to +15 for max level
    end

    -- Mythic always relevant
    if result.isMythic and result.isForCurrentRole then
        score = score + 20
    end

    -- Convert score to rating
    if score >= 55 then
        result.rating = SmartGear.RATING_RECOMMENDED
        result.stars = 3
    elseif score >= 35 then
        result.rating = SmartGear.RATING_GOOD
        result.stars = 3
    elseif score >= 20 then
        result.rating = SmartGear.RATING_DECENT
        result.stars = 2
    elseif score >= 5 then
        result.rating = SmartGear.RATING_MAYBE
        result.stars = 1
    else
        -- Check stickerbook recommendation
        if result.isMetaSet and result.isForAnyRole and not result.isForCurrentRole then
            result.rating = SmartGear.RATING_STICKERBOOK
            result.stars = 0
        else
            result.rating = SmartGear.RATING_BAD
            result.stars = 0
        end
    end

    result.score = score
    return result
end

----------------------------------------------------------------------
-- Evaluate an equipped item by its worn slot index
----------------------------------------------------------------------
local function EvaluateEquippedSlot(wornSlot)
    local itemLink = GetItemLink(BAG_WORN, wornSlot)
    if not itemLink or itemLink == "" then return nil end
    return SmartGear.EvaluateItemLink(itemLink)
end

----------------------------------------------------------------------
-- SMART SLOT RESOLUTION
-- Returns a list of {slot, label} for comparison, aware of paired slots
-- Strategy: for paired slots (rings, dual wield), compare against
-- the WEAKEST equipped item so we suggest replacing it
----------------------------------------------------------------------
local function GetComparisonSlots(equipType)
    -- Single-slot equipment: straightforward
    local singleSlots = {
        [EQUIP_TYPE_HEAD]      = { { slot = EQUIP_SLOT_HEAD, label = "Head" } },
        [EQUIP_TYPE_CHEST]     = { { slot = EQUIP_SLOT_CHEST, label = "Chest" } },
        [EQUIP_TYPE_SHOULDERS] = { { slot = EQUIP_SLOT_SHOULDERS, label = "Shoulders" } },
        [EQUIP_TYPE_WAIST]     = { { slot = EQUIP_SLOT_WAIST, label = "Waist" } },
        [EQUIP_TYPE_LEGS]      = { { slot = EQUIP_SLOT_LEGS, label = "Legs" } },
        [EQUIP_TYPE_FEET]      = { { slot = EQUIP_SLOT_FEET, label = "Feet" } },
        [EQUIP_TYPE_HAND]      = { { slot = EQUIP_SLOT_HAND, label = "Hands" } },
        [EQUIP_TYPE_NECK]      = { { slot = EQUIP_SLOT_NECK, label = "Neck" } },
    }

    if singleSlots[equipType] then
        return singleSlots[equipType], "single"
    end

    -- RINGS: compare against both, suggest replacing the worse one
    if equipType == EQUIP_TYPE_RING then
        return {
            { slot = EQUIP_SLOT_RING1, label = "Ring 1" },
            { slot = EQUIP_SLOT_RING2, label = "Ring 2" },
        }, "paired_replace_worst"
    end

    -- TWO-HAND: compare against main bar and backup bar main slots
    if equipType == EQUIP_TYPE_TWO_HAND then
        return {
            { slot = EQUIP_SLOT_MAIN_HAND, label = "Main Bar" },
            { slot = EQUIP_SLOT_BACKUP_MAIN, label = "Backup Bar" },
        }, "bar_choice"
    end

    -- MAIN_HAND type: can go in main hand of either bar
    if equipType == EQUIP_TYPE_MAIN_HAND then
        return {
            { slot = EQUIP_SLOT_MAIN_HAND, label = "Main Bar" },
            { slot = EQUIP_SLOT_BACKUP_MAIN, label = "Backup Bar" },
        }, "bar_choice"
    end

    -- OFF_HAND (shield, torch, etc.): compare off-hand slots
    -- But SKIP bars where a 2H weapon is equipped (2H blocks the off-hand)
    if equipType == EQUIP_TYPE_OFF_HAND then
        local slots = {}

        -- Main bar: only if NOT using 2H
        local mainLink = GetItemLink(BAG_WORN, EQUIP_SLOT_MAIN_HAND)
        local mainIs2H = false
        if mainLink and mainLink ~= "" then
            mainIs2H = (GetItemLinkEquipType(mainLink) == EQUIP_TYPE_TWO_HAND)
        end
        if not mainIs2H then
            table.insert(slots, { slot = EQUIP_SLOT_OFF_HAND, label = "Main Bar Off-hand" })
        end

        -- Backup bar: only if NOT using 2H
        local backupLink = GetItemLink(BAG_WORN, EQUIP_SLOT_BACKUP_MAIN)
        local backupIs2H = false
        if backupLink and backupLink ~= "" then
            backupIs2H = (GetItemLinkEquipType(backupLink) == EQUIP_TYPE_TWO_HAND)
        end
        if not backupIs2H then
            table.insert(slots, { slot = EQUIP_SLOT_BACKUP_OFF, label = "Backup Bar Off-hand" })
        end

        -- If both bars are 2H, no valid off-hand slot exists
        if #slots == 0 then
            return nil, nil
        end

        return slots, "bar_choice"
    end

    -- ONE_HAND: can go main hand OR off-hand on either bar
    -- But skip off-hand slots where a 2H weapon occupies the main hand
    -- (2H weapon = off-hand is blocked/empty by design)
    if equipType == EQUIP_TYPE_ONE_HAND then
        local slots = {}

        -- Main bar: check if main hand has a 2H weapon
        local mainLink = GetItemLink(BAG_WORN, EQUIP_SLOT_MAIN_HAND)
        local mainIs2H = false
        if mainLink and mainLink ~= "" then
            local mainEquipType = GetItemLinkEquipType(mainLink)
            mainIs2H = (mainEquipType == EQUIP_TYPE_TWO_HAND)
        end

        if mainIs2H then
            -- 2H on main bar: only compare against main hand (replacing the 2H)
            table.insert(slots, { slot = EQUIP_SLOT_MAIN_HAND, label = "Main Hand (2H)" })
        else
            table.insert(slots, { slot = EQUIP_SLOT_MAIN_HAND, label = "Main Hand" })
            table.insert(slots, { slot = EQUIP_SLOT_OFF_HAND, label = "Off Hand" })
        end

        -- Backup bar: check if backup main has a 2H weapon
        local backupLink = GetItemLink(BAG_WORN, EQUIP_SLOT_BACKUP_MAIN)
        local backupIs2H = false
        if backupLink and backupLink ~= "" then
            local backupEquipType = GetItemLinkEquipType(backupLink)
            backupIs2H = (backupEquipType == EQUIP_TYPE_TWO_HAND)
        end

        if backupIs2H then
            -- 2H on backup bar: only compare against backup main
            table.insert(slots, { slot = EQUIP_SLOT_BACKUP_MAIN, label = "Backup Main (2H)" })
        else
            -- Check if backup has anything at all
            if backupLink and backupLink ~= "" then
                table.insert(slots, { slot = EQUIP_SLOT_BACKUP_MAIN, label = "Backup Main" })
                table.insert(slots, { slot = EQUIP_SLOT_BACKUP_OFF, label = "Backup Off" })
            else
                -- Backup bar empty — offer both slots
                table.insert(slots, { slot = EQUIP_SLOT_BACKUP_MAIN, label = "Backup Main" })
                table.insert(slots, { slot = EQUIP_SLOT_BACKUP_OFF, label = "Backup Off" })
            end
        end

        return slots, "paired_replace_worst"
    end

    return nil, nil
end

----------------------------------------------------------------------
-- Build all comparisons for an item and pick the smartest one
-- "paired_replace_worst": compare against worst equipped in group
-- "bar_choice": compare against each bar, pick most beneficial
-- "single": only one slot, straightforward
----------------------------------------------------------------------
local function SmartCompare(newEval, equipType)
    local slotDefs, strategy = GetComparisonSlots(equipType)
    if not slotDefs then return nil end

    local comparisons = {}
    for _, slotDef in ipairs(slotDefs) do
        local comp = SmartGear._BuildComparison(newEval, slotDef.slot)
        comp.slotLabel = slotDef.label
        table.insert(comparisons, comp)
    end

    if #comparisons == 0 then return nil end

    if strategy == "paired_replace_worst" then
        -- Find the equipped slot with the LOWEST score (weakest item)
        -- and compare against that — suggest replacing the worst piece.
        -- Empty slots are only preferred if ALL slots are empty.
        local worstOccupied = nil
        local firstEmpty = nil
        for _, comp in ipairs(comparisons) do
            if comp.slotEmpty then
                if not firstEmpty then firstEmpty = comp end
            else
                if not worstOccupied or comp.equippedScore < worstOccupied.equippedScore then
                    worstOccupied = comp
                end
            end
        end
        -- Prefer comparing against an occupied slot (replacing worst item)
        -- Only suggest empty slot if no occupied slots exist
        return worstOccupied or firstEmpty

    elseif strategy == "bar_choice" then
        -- For weapons on different bars, show comparison for the bar
        -- where this item would be the biggest upgrade.
        -- Prefer occupied slots over empty ones.
        local bestOccupied = nil
        local firstEmpty = nil
        for _, comp in ipairs(comparisons) do
            if comp.slotEmpty then
                if not firstEmpty then firstEmpty = comp end
            else
                if not bestOccupied or comp.scoreDiff > bestOccupied.scoreDiff then
                    bestOccupied = comp
                end
            end
        end
        return bestOccupied or firstEmpty

    else -- "single"
        return comparisons[1]
    end
end

----------------------------------------------------------------------
-- COMPARATOR: Compare inventory item against equipped item(s)
----------------------------------------------------------------------
function SmartGear.CompareWithEquipped(bagId, slotIndex)
    local itemLink = GetItemLink(bagId, slotIndex)
    if not itemLink or itemLink == "" then return nil end

    local equipType = GetItemLinkEquipType(itemLink)
    if not equipType or equipType == EQUIP_TYPE_INVALID then return nil end

    local newEval = SmartGear.EvaluateItem(bagId, slotIndex)
    if not newEval then return nil end

    local comp = SmartCompare(newEval, equipType)
    if comp then comp.newEval = newEval end
    return comp
end

----------------------------------------------------------------------
-- COMPARATOR from item link (for tooltip hooks)
----------------------------------------------------------------------
function SmartGear.CompareWithEquippedByLink(itemLink)
    if not itemLink or itemLink == "" then return nil end

    local equipType = GetItemLinkEquipType(itemLink)
    if not equipType or equipType == EQUIP_TYPE_INVALID then return nil end

    local newEval = SmartGear.EvaluateItemLink(itemLink)
    if not newEval then return nil end

    local comp = SmartCompare(newEval, equipType)
    if comp then comp.newEval = newEval end
    return comp
end

----------------------------------------------------------------------
-- Internal: build a comparison struct between newEval and a worn slot
----------------------------------------------------------------------
function SmartGear._BuildComparison(newEval, wornSlot)
    local equippedLink = GetItemLink(BAG_WORN, wornSlot)
    local slotEmpty = (not equippedLink or equippedLink == "")
    local equippedEval = nil
    local equippedName = nil

    if not slotEmpty then
        equippedEval = EvaluateEquippedSlot(wornSlot)
        equippedName = GetItemName(BAG_WORN, wornSlot)
        if equippedName then equippedName = zo_strformat("<<1>>", equippedName) end
    end

    local eqScore = equippedEval and equippedEval.score or 0

    local comp = {
        wornSlot        = wornSlot,
        slotEmpty       = slotEmpty,
        equippedLink    = equippedLink,
        equippedName    = equippedName or "",
        equippedScore   = eqScore,
        equippedSetName = equippedEval and equippedEval.setName or nil,
        equippedTraitName = equippedEval and equippedEval.traitName or nil,
        equippedRating  = equippedEval and equippedEval.rating or SmartGear.RATING_BAD,
        newScore        = newEval.score,
        scoreDiff       = newEval.score - eqScore,
        isUpgrade       = false,
        isDowngrade     = false,
        isSidegrade     = false,
        verdict         = "unknown",
        changes         = {},
    }

    if slotEmpty then
        comp.isUpgrade = true
        comp.verdict = "upgrade"
        table.insert(comp.changes, { aspect = "slot", direction = "up", detail = "empty_slot" })
        return comp
    end

    -- Detailed change tracking
    if newEval.setName and equippedEval then
        -- Meta tier comparison
        if newEval.isMetaSet and not equippedEval.isMetaSet then
            table.insert(comp.changes, { aspect = "set", direction = "up", detail = "meta_vs_nonmeta" })
        elseif not newEval.isMetaSet and equippedEval.isMetaSet then
            table.insert(comp.changes, { aspect = "set", direction = "down", detail = "nonmeta_vs_meta" })
        elseif newEval.isMetaSet and equippedEval.isMetaSet then
            local tierVal = { S = 4, A = 3, B = 2, C = 1 }
            local nv = tierVal[newEval.metaTier] or 0
            local ev = tierVal[equippedEval.metaTier] or 0
            if nv > ev then
                table.insert(comp.changes, { aspect = "set", direction = "up", detail = "higher_tier" })
            elseif nv < ev then
                table.insert(comp.changes, { aspect = "set", direction = "down", detail = "lower_tier" })
            end
        end
        -- Set completion
        if newEval.completesSet and not (equippedEval.completesSet) then
            table.insert(comp.changes, { aspect = "set_bonus", direction = "up", detail = "completes_set" })
        end
    end

    -- Trait
    if newEval.traitName and equippedEval and equippedEval.traitName then
        if newEval.isOptimalTrait and not equippedEval.isOptimalTrait then
            table.insert(comp.changes, { aspect = "trait", direction = "up", detail = "better_trait" })
        elseif not newEval.isOptimalTrait and equippedEval.isOptimalTrait then
            table.insert(comp.changes, { aspect = "trait", direction = "down", detail = "worse_trait" })
        end
    end

    -- Weight
    if newEval.armorWeight and equippedEval and equippedEval.armorWeight then
        if newEval.isOptimalWeight and not equippedEval.isOptimalWeight then
            table.insert(comp.changes, { aspect = "weight", direction = "up", detail = "better_weight" })
        elseif not newEval.isOptimalWeight and equippedEval.isOptimalWeight then
            table.insert(comp.changes, { aspect = "weight", direction = "down", detail = "worse_weight" })
        end
    end

    -- Quality
    if newEval.quality and equippedEval and equippedEval.quality then
        if newEval.quality > equippedEval.quality then
            table.insert(comp.changes, { aspect = "quality", direction = "up", detail = "higher_quality" })
        elseif newEval.quality < equippedEval.quality then
            table.insert(comp.changes, { aspect = "quality", direction = "down", detail = "lower_quality" })
        end
    end

    -- Item level comparison
    if newEval.itemLevel and equippedEval and equippedEval.itemLevel then
        comp.newItemLevel = newEval.itemLevel
        comp.equippedItemLevel = equippedEval.itemLevel
        comp.levelDiff = newEval.itemLevel - equippedEval.itemLevel
        if newEval.itemLevel > equippedEval.itemLevel then
            table.insert(comp.changes, {
                aspect = "level", direction = "up",
                detail = "higher_level",
                value = "+" .. (newEval.itemLevel - equippedEval.itemLevel),
            })
        elseif newEval.itemLevel < equippedEval.itemLevel then
            table.insert(comp.changes, {
                aspect = "level", direction = "down",
                detail = "lower_level",
                value = tostring(newEval.itemLevel - equippedEval.itemLevel),
            })
        end
    end

    -- Verdict
    local diff = comp.scoreDiff
    if diff >= 10 then
        comp.isUpgrade = true;   comp.verdict = "upgrade"
    elseif diff >= 3 then
        comp.isUpgrade = true;   comp.verdict = "slight_upgrade"
    elseif diff > -3 then
        comp.isSidegrade = true; comp.verdict = "sidegrade"
    elseif diff > -10 then
        comp.isDowngrade = true; comp.verdict = "slight_downgrade"
    else
        comp.isDowngrade = true; comp.verdict = "downgrade"
    end

    return comp
end

----------------------------------------------------------------------
-- Evaluate from item link directly (for tooltip hooks)
----------------------------------------------------------------------
function SmartGear.EvaluateItemLink(itemLink)
    if not itemLink or itemLink == "" then return nil end

    local linkItemType = GetItemLinkItemType(itemLink)
    if linkItemType ~= ITEMTYPE_ARMOR and linkItemType ~= ITEMTYPE_WEAPON then
        return nil
    end

    local role = SmartGear.currentRole or "MagDD"
    local pvpMode = SmartGear.savedVars and SmartGear.savedVars.pvpMode or false
    local equippedSets = GetEquippedSets()

    local result = {
        itemLink = itemLink,
        role = role,
        rating = SmartGear.RATING_BAD,
        stars = 0,
        setName = nil,
        isMetaSet = false,
        metaTier = nil,
        metaNotes = nil,
        isForCurrentRole = false,
        isForAnyRole = false,
        isEquippedSet = false,
        setEquipped = 0,
        setMax = 0,
        completesSet = false,
        traitName = nil,
        traitQuality = "unknown",
        isOptimalTrait = false,
        armorWeight = nil,
        isOptimalWeight = true,
        quality = GetItemLinkQuality(itemLink),
        -- Level & stats
        itemLevel = 0,
        requiredLevel = 0,
        requiredCP = 0,
        isMythic = false,
        isMonsterSet = false,
        isPvpSet = false,
        recommendTransmute = false,
    }

    -- === LEVEL ANALYSIS (from link) ===
    result.requiredLevel = GetItemLinkRequiredLevel(itemLink) or 0
    result.requiredCP = GetItemLinkRequiredChampionPoints(itemLink) or 0
    if result.requiredCP > 0 then
        result.itemLevel = 50 + result.requiredCP
    else
        result.itemLevel = result.requiredLevel
    end

    -- === SET ANALYSIS ===
    local hasSet, setName, numBonuses, numEquipped, maxEquipped, setId = GetItemLinkSetInfo(itemLink, false)
    if hasSet then
        result.setName = setName
        -- Check equipped sets
        if equippedSets[setId] then
            result.isEquippedSet = true
            result.setEquipped = equippedSets[setId].equipped
        end
        result.setMax = maxEquipped or 5
        if result.isEquippedSet then
            result.completesSet = (result.setEquipped + 1) >= result.setMax
        end

        local metaInfo = GetMetaInfo(setName)
        if metaInfo then
            result.isMetaSet = true
            result.metaTier = metaInfo.tier
            result.metaRating = metaInfo.rating or 50
            result.metaNotes = metaInfo.notes
            result.isMythic = metaInfo.isMythic or false
            result.isMonsterSet = metaInfo.isMonsterSet or false
            result.isPvpSet = metaInfo.pvpOnly or false
            result.isForCurrentRole = IsSetForRole(metaInfo, role, pvpMode)
            result.isForAnyRole = IsSetForAnyRole(metaInfo)
        end
    end

    -- === TRAIT ANALYSIS (from link) ===
    local traitType = GetItemLinkTraitType(itemLink)
    if traitType and traitType ~= ITEM_TRAIT_TYPE_NONE then
        result.traitName = SmartGear.TraitNames[traitType] or GetString("SI_ITEMTRAITTYPE", traitType)

        local equipType = GetItemLinkEquipType(itemLink)
        if equipType == EQUIP_TYPE_NECK or equipType == EQUIP_TYPE_RING then
            result.traitQuality, result.isOptimalTrait = EvaluateJewelryTrait(traitType, role)
        elseif equipType == EQUIP_TYPE_MAIN_HAND or equipType == EQUIP_TYPE_OFF_HAND
            or equipType == EQUIP_TYPE_ONE_HAND or equipType == EQUIP_TYPE_TWO_HAND then
            result.traitQuality, result.isOptimalTrait = EvaluateWeaponTrait(traitType, role)
        else
            result.traitQuality, result.isOptimalTrait = EvaluateArmorTrait(traitType, role, pvpMode)
        end

        if result.isMetaSet and result.isForCurrentRole and not result.isOptimalTrait then
            result.recommendTransmute = true
        end
    end

    -- === ARMOR WEIGHT (from link) ===
    local armorType = GetItemLinkArmorType(itemLink)
    if armorType and armorType ~= ARMORTYPE_NONE then
        result.armorWeight = armorType
        result.isOptimalWeight = EvaluateArmorWeight(armorType, role)
    end

    -- === SCORING (same logic as bag version) ===
    local score = 0

    if result.isMetaSet and result.isForCurrentRole then
        if result.metaTier == "S" then score = score + 40
        elseif result.metaTier == "A" then score = score + 30
        elseif result.metaTier == "B" then score = score + 20
        else score = score + 10 end
    elseif result.setName and not result.isMetaSet then
        score = score + 5
    end

    if result.isOptimalTrait then score = score + 20
    elseif result.traitQuality == "good" then score = score + 10
    elseif result.traitQuality == "suboptimal" then score = score + 3
    elseif result.traitQuality == "bad" then score = score - 5 end

    if result.isOptimalWeight then score = score + 10
    else score = score - 5 end

    if result.completesSet then score = score + 15
    elseif result.isEquippedSet then score = score + 8 end

    if result.quality == ITEM_DISPLAY_QUALITY_LEGENDARY then score = score + 5
    elseif result.quality == ITEM_DISPLAY_QUALITY_ARTIFACT then score = score + 3 end

    -- Item level scoring (same as bag version)
    if result.itemLevel > 0 then
        local maxLevel = 210
        local levelRatio = result.itemLevel / maxLevel
        score = score + math.floor(levelRatio * 15)
    end

    if result.isMythic and result.isForCurrentRole then score = score + 20 end

    if score >= 55 then
        result.rating = SmartGear.RATING_RECOMMENDED; result.stars = 3
    elseif score >= 35 then
        result.rating = SmartGear.RATING_GOOD; result.stars = 3
    elseif score >= 20 then
        result.rating = SmartGear.RATING_DECENT; result.stars = 2
    elseif score >= 5 then
        result.rating = SmartGear.RATING_MAYBE; result.stars = 1
    else
        if result.isMetaSet and result.isForAnyRole and not result.isForCurrentRole then
            result.rating = SmartGear.RATING_STICKERBOOK; result.stars = 0
        else
            result.rating = SmartGear.RATING_BAD; result.stars = 0
        end
    end

    result.score = score
    return result
end
