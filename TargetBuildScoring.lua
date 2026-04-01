----------------------------------------------------------------------
-- SmartGear — Target Build Scoring Engine v2
-- Per-slot evaluation: each slot scored 0-100% on all parameters.
-- Overall progress = average across all slots.
----------------------------------------------------------------------
SmartGear = SmartGear or {}

----------------------------------------------------------------------
-- Count equipped pieces of a set
----------------------------------------------------------------------
function SmartGear.CountEquippedFromSet(setName)
    if not setName then return 0 end
    local count = 0
    local lowerTarget = string.lower(setName)
    for slot = 0, 16 do
        local itemLink = GetItemLink(BAG_WORN, slot)
        if itemLink and itemLink ~= "" then
            local hasSet, sName = GetItemLinkSetInfo(itemLink, true)
            if hasSet and sName and string.lower(sName) == lowerTarget then
                count = count + 1
            end
        end
    end
    return count
end

----------------------------------------------------------------------
-- Evaluate a SINGLE equipped slot vs what the build wants
-- Returns: slotScore (0-100), details table
--
-- Scoring weights:
--   Set match:    50 points (biggest factor)
--   Trait match:  20 points
--   Weight match: 10 points
--   Quality:      10 points (legendary=10, epic=7, superior=4)
--   Level:        10 points (CP160=10, scales down)
----------------------------------------------------------------------
local QUALITY_SCORES = {
    [ITEM_DISPLAY_QUALITY_LEGENDARY] = 10,
    [ITEM_DISPLAY_QUALITY_ARTIFACT]  = 7,
    [ITEM_DISPLAY_QUALITY_ARCANE]    = 4,
    [ITEM_DISPLAY_QUALITY_MAGIC]     = 2,
    [ITEM_DISPLAY_QUALITY_NORMAL]    = 0,
}

function SmartGear.EvaluateSlotVsBuild(wornSlot, build)
    if not build or not build.slots then return 0, nil end

    local spec = build.slots[wornSlot]
    if not spec then
        return -1, nil  -- slot not in build (e.g., nil backup off-hand for 2H)
    end

    local itemLink = GetItemLink(BAG_WORN, wornSlot)
    local details = {
        slot = wornSlot,
        targetSet = spec.set,
        targetTrait = spec.trait,
        targetWeight = spec.weight,
        setMatch = false,
        traitMatch = false,
        weightMatch = false,
        qualityScore = 0,
        levelScore = 0,
        empty = false,
    }

    -- Empty slot = 0%
    if not itemLink or itemLink == "" then
        details.empty = true
        return 0, details
    end

    local score = 0

    -- === SET (50 pts) ===
    local hasSet, setName = GetItemLinkSetInfo(itemLink, true)
    if hasSet and setName and spec.set then
        if string.lower(setName) == string.lower(spec.set) then
            score = score + 50
            details.setMatch = true
        end
    end

    -- === TRAIT (20 pts) ===
    if spec.trait then
        local itemTrait = GetItemLinkTraitType(itemLink)
        if itemTrait and itemTrait == spec.trait then
            score = score + 20
            details.traitMatch = true
        end
    else
        -- Build doesn't specify trait = auto-pass
        score = score + 20
        details.traitMatch = true
    end

    -- === WEIGHT / WEAPON TYPE (10 pts) ===
    if spec.weaponType then
        -- Weapon slot: check weapon type (Bow, Fire Staff, Dagger, etc.)
        local itemWeaponType = GetItemLinkWeaponType(itemLink)
        if itemWeaponType and itemWeaponType == spec.weaponType then
            score = score + 10
            details.weightMatch = true  -- reuse field for "type match"
        end
    elseif spec.weight then
        -- Armor slot: check weight
        local itemWeight = GetItemLinkArmorType(itemLink)
        if itemWeight and itemWeight == spec.weight then
            score = score + 10
            details.weightMatch = true
        end
    else
        score = score + 10
        details.weightMatch = true
    end

    -- === QUALITY (10 pts) ===
    local quality = GetItemLinkQuality(itemLink)
    local qScore = QUALITY_SCORES[quality] or 0
    score = score + qScore
    details.qualityScore = qScore

    -- === LEVEL (10 pts) ===
    local reqCP = GetItemLinkRequiredChampionPoints(itemLink) or 0
    local reqLevel = GetItemLinkRequiredLevel(itemLink) or 0
    local effectiveLevel = reqCP > 0 and (50 + reqCP) or reqLevel
    local maxLevel = 210  -- CP160
    local levelScore = math.min(10, math.floor((effectiveLevel / maxLevel) * 10))
    score = score + levelScore
    details.levelScore = levelScore

    return score, details
end

----------------------------------------------------------------------
-- Evaluate full build progress: all slots
-- Returns: overallPercent, slotResults[]
----------------------------------------------------------------------
function SmartGear.EvaluateBuildProgress(build)
    if not build or not build.slots then return 0, {} end

    local results = {}
    local totalScore = 0
    local slotCount = 0

    for slot, spec in pairs(build.slots) do
        if spec then
            local score, details = SmartGear.EvaluateSlotVsBuild(slot, build)
            if score >= 0 then  -- -1 = slot not in build
                table.insert(results, {
                    slot = slot,
                    score = score,
                    details = details,
                })
                totalScore = totalScore + score
                slotCount = slotCount + 1
            end
        end
    end

    local overallPercent = slotCount > 0 and math.floor(totalScore / slotCount) or 0

    -- Sort by score ascending (worst slots first = what to upgrade)
    table.sort(results, function(a, b) return a.score < b.score end)

    return overallPercent, results
end

----------------------------------------------------------------------
-- Compute target build score for an ITEM being evaluated
-- Used by ComputeScore() in Core.lua
-- Returns: score adjustment, match details
----------------------------------------------------------------------
function SmartGear.ComputeTargetBuildScore(result, build)
    if not build or not build.slots or not result then
        return 0, nil
    end

    local score = 0
    local match = {
        isTargetSet = false,
        needMore = false,
        correctTrait = false,
        correctWeight = false,
        statSynergy = 0,
        setName = nil,
        piecesNeeded = 0,
        slotMatch = false,    -- item matches a specific slot exactly
        slotScore = 0,        -- how well it matches best target slot
    }

    -- === WEAPON TYPE COMPATIBILITY CHECK ===
    -- Check equip type (1H vs 2H) and specific weapon type (Bow, Fire Staff, etc.)
    local itemEquipType = result.equipType
    local itemWeaponType = result.itemLink and GetItemLinkWeaponType(result.itemLink) or nil

    if itemEquipType == EQUIP_TYPE_TWO_HAND or itemEquipType == EQUIP_TYPE_ONE_HAND
       or itemEquipType == EQUIP_TYPE_OFF_HAND then

        local buildHasOffBar = build.slots[EQUIP_SLOT_OFF_HAND] ~= nil
        local buildHasBackupOff = build.slots[EQUIP_SLOT_BACKUP_OFF] ~= nil

        -- DW build but 2H item → hard penalty
        if buildHasOffBar and itemEquipType == EQUIP_TYPE_TWO_HAND then
            match.wrongWeaponType = true
            return -20, match
        end

        -- Check specific weapon type against what the build specifies
        if itemWeaponType then
            local weaponMatch = false
            for _, slot in pairs({EQUIP_SLOT_MAIN_HAND, EQUIP_SLOT_OFF_HAND,
                                   EQUIP_SLOT_BACKUP_MAIN, EQUIP_SLOT_BACKUP_OFF}) do
                local spec = build.slots[slot]
                if spec and spec.weaponType then
                    if spec.weaponType == itemWeaponType then
                        weaponMatch = true
                        break
                    end
                end
            end
            -- If build specifies weapon types and this item doesn't match any → penalty
            local buildHasWeaponTypes = false
            for _, slot in pairs({EQUIP_SLOT_MAIN_HAND, EQUIP_SLOT_OFF_HAND,
                                   EQUIP_SLOT_BACKUP_MAIN, EQUIP_SLOT_BACKUP_OFF}) do
                if build.slots[slot] and build.slots[slot].weaponType then
                    buildHasWeaponTypes = true
                    break
                end
            end
            if buildHasWeaponTypes and not weaponMatch then
                match.wrongWeaponType = true
                return -15, match
            end
        end
    end

    local itemSetName = result.setName
    if not itemSetName then
        match.statSynergy = -3
        return -3, match
    end

    -- Check if item belongs to any target set
    local targetSetInfo = build._sets and build._sets[itemSetName]

    if targetSetInfo then
        match.isTargetSet = true
        match.setName = itemSetName

        -- Check if we still need pieces
        local equipped = SmartGear.CountEquippedFromSet(itemSetName)
        local needed = targetSetInfo.count
        if equipped < needed then
            match.needMore = true
            match.piecesNeeded = needed - equipped
            score = score + 35  -- urgently need this piece
        else
            score = score + 15  -- have enough, upgrade quality/trait
        end

        -- Check trait match against any slot that uses this set
        local itemTrait = result.itemLink and GetItemLinkTraitType(result.itemLink) or nil
        if itemTrait then
            for _, slot in ipairs(targetSetInfo.slots) do
                local slotSpec = build.slots[slot]
                if slotSpec and slotSpec.trait and slotSpec.trait == itemTrait then
                    match.correctTrait = true
                    score = score + 8
                    break
                end
            end
        end

        -- Check weight match
        if result.armorWeight and result.armorWeight ~= ARMORTYPE_NONE then
            for _, slot in ipairs(targetSetInfo.slots) do
                local slotSpec = build.slots[slot]
                if slotSpec and slotSpec.weight and slotSpec.weight == result.armorWeight then
                    match.correctWeight = true
                    score = score + 5
                    break
                end
            end
        end

        -- Check exact slot match (set + trait + weight all correct for a specific slot)
        if match.correctTrait and match.correctWeight then
            match.slotMatch = true
        end

    else
        -- Not a target set: check stat similarity
        local synergy = 0
        if build._statProfile and SmartGear.MetaSets then
            local meta = SmartGear.MetaSets[itemSetName]
            if meta and meta.statContributions then
                local overlap = 0
                local total = 0
                for stat, val in pairs(meta.statContributions) do
                    total = total + 1
                    if build._statProfile[stat] then
                        overlap = overlap + 1
                    end
                end
                if total > 0 then
                    local ratio = overlap / total
                    synergy = math.floor(ratio * 15) - 5
                    synergy = math.max(-5, math.min(10, synergy))
                end
            else
                synergy = -3
            end
        end
        match.statSynergy = synergy
        score = score + synergy - 5  -- non-target penalty
    end

    return score, match
end

----------------------------------------------------------------------
-- Activate a target build
----------------------------------------------------------------------
function SmartGear.ActivateBuild(buildId)
    if not buildId then
        SmartGear.ActiveBuild = nil
        if SmartGear.savedVars then
            SmartGear.savedVars.activeBuildId = nil
        end
        local lang = SmartGear.currentLang or "en"
        d("|c00FF00[SmartGear]|r " .. (lang == "ru" and "Целевая сборка деактивирована." or "Target build deactivated."))
        return
    end

    local build = nil
    if SmartGear.PreBuilds and SmartGear.PreBuilds[buildId] then
        build = SmartGear.PreBuilds[buildId]
    elseif SmartGear.savedVars and SmartGear.savedVars.customBuilds
           and SmartGear.savedVars.customBuilds[buildId] then
        build = SmartGear.savedVars.customBuilds[buildId]
    end

    if not build then
        d("|c00FF00[SmartGear]|r " .. (lang == "ru" and "Сборка не найдена: " or "Build not found: ") .. tostring(buildId))
        return
    end

    -- Compute derived caches
    build._sets = {}
    if build.slots then
        for slot, spec in pairs(build.slots) do
            if spec and spec.set then
                local setName = spec.set
                if not build._sets[setName] then
                    build._sets[setName] = { count = 0, slots = {} }
                end
                build._sets[setName].count = build._sets[setName].count + 1
                table.insert(build._sets[setName].slots, slot)
            end
        end
    end

    -- Compute stat profile
    build._statProfile = {}
    if SmartGear.MetaSets then
        for setName, _ in pairs(build._sets) do
            local meta = SmartGear.MetaSets[setName]
            if meta and meta.statContributions then
                for stat, val in pairs(meta.statContributions) do
                    build._statProfile[stat] = (build._statProfile[stat] or 0) + val
                end
            end
        end
    end

    build.id = buildId
    SmartGear.ActiveBuild = build

    if SmartGear.savedVars then
        SmartGear.savedVars.activeBuildId = buildId
    end

    local lang = SmartGear.currentLang or "en"
    local name = lang == "ru" and (build.nameRu or build.name) or build.name
    d("|c00FF00[SmartGear]|r " .. (lang == "ru" and "Цель: " or "Target: ") .. "|cFFFF00" .. (name or buildId) .. "|r")
    SmartGear.ShowBuildProgress()
end

----------------------------------------------------------------------
-- Slot name lookup
----------------------------------------------------------------------
local SLOT_NAMES = {
    [EQUIP_SLOT_HEAD]        = { en = "Head",       ru = "Голова" },
    [EQUIP_SLOT_SHOULDERS]   = { en = "Shoulders",  ru = "Плечи" },
    [EQUIP_SLOT_CHEST]       = { en = "Chest",      ru = "Грудь" },
    [EQUIP_SLOT_WAIST]       = { en = "Waist",      ru = "Пояс" },
    [EQUIP_SLOT_LEGS]        = { en = "Legs",       ru = "Ноги" },
    [EQUIP_SLOT_FEET]        = { en = "Feet",       ru = "Ступни" },
    [EQUIP_SLOT_HAND]        = { en = "Hands",      ru = "Руки" },
    [EQUIP_SLOT_NECK]        = { en = "Neck",       ru = "Шея" },
    [EQUIP_SLOT_RING1]       = { en = "Ring 1",     ru = "Кольцо 1" },
    [EQUIP_SLOT_RING2]       = { en = "Ring 2",     ru = "Кольцо 2" },
    [EQUIP_SLOT_MAIN_HAND]   = { en = "Main Hand",  ru = "Основная" },
    [EQUIP_SLOT_OFF_HAND]    = { en = "Off Hand",   ru = "Левая" },
    [EQUIP_SLOT_BACKUP_MAIN] = { en = "Backup Main", ru = "Запасная" },
    [EQUIP_SLOT_BACKUP_OFF]  = { en = "Backup Off",  ru = "Запасная лев." },
}

----------------------------------------------------------------------
-- Show build progress in chat (per-slot)
----------------------------------------------------------------------
function SmartGear.ShowBuildProgress()
    local build = SmartGear.ActiveBuild
    if not build then
        local lang = SmartGear.currentLang or "en"
        d("|c00FF00[SmartGear]|r " .. (lang == "ru" and "Нет активной целевой сборки." or "No target build active."))
        return
    end

    local lang = SmartGear.currentLang or "en"
    local name = lang == "ru" and (build.nameRu or build.name) or build.name
    local overall, slotResults = SmartGear.EvaluateBuildProgress(build)

    d("|c00FF00[SmartGear]|r " .. (lang == "ru" and "Прогресс: " or "Progress: ")
        .. "|cFFFF00" .. (name or "?") .. "|r — |cFFFFFF" .. overall .. "%|r")

    for _, sr in ipairs(slotResults) do
        local d_info = sr.details
        if d_info then
            local slotInfo = SLOT_NAMES[sr.slot]
            local slotName = slotInfo and (lang == "ru" and slotInfo.ru or slotInfo.en) or "?"

            local parts = {}
            if d_info.empty then
                table.insert(parts, "|cFF0000EMPTY|r")
            else
                table.insert(parts, d_info.setMatch and "|c00FF00Set(+)|r" or "|cFF0000Set(x)|r")
                table.insert(parts, d_info.traitMatch and "|c00FF00Trait(+)|r" or "|cFFFF00Trait(x)|r")
                table.insert(parts, d_info.weightMatch and "|c00FF00Wt(+)|r" or "|cFFFF00Wt(x)|r")
                table.insert(parts, "Q:" .. d_info.qualityScore .. " L:" .. d_info.levelScore)
            end

            local color = sr.score >= 80 and "|c00FF00" or (sr.score >= 50 and "|cFFFF00" or "|cFF8800")
            d("  " .. color .. string.format("%3d%%", sr.score) .. "|r "
                .. slotName .. ": " .. table.concat(parts, " "))
        end
    end
end

----------------------------------------------------------------------
-- List available builds
----------------------------------------------------------------------
function SmartGear.ListBuilds()
    local lang = SmartGear.currentLang or "en"
    d("|c00FF00[SmartGear]|r " .. (lang == "ru" and "Доступные сборки:" or "Available builds:"))
    d("  " .. (lang == "ru" and "(используй /smartgear builds для окна)" or "(use /smartgear builds for browser)"))

    local count = 0
    if SmartGear.PreBuilds then
        for id, build in pairs(SmartGear.PreBuilds) do
            local name = lang == "ru" and (build.nameRu or build.name) or build.name
            local cls = build.className or ""
            local active = (SmartGear.ActiveBuild and SmartGear.ActiveBuild.id == id) and " |c00FF00<<|r" or ""
            d("  |c00DDFF[P]|r " .. (name or id) .. " (" .. (build.role or "?")
                .. "/" .. (build.context or "?") .. "/" .. cls .. ")" .. active)
            count = count + 1
        end
    end
    if SmartGear.savedVars and SmartGear.savedVars.customBuilds then
        for id, build in pairs(SmartGear.savedVars.customBuilds) do
            local name = lang == "ru" and (build.nameRu or build.name) or build.name
            local active = (SmartGear.ActiveBuild and SmartGear.ActiveBuild.id == id) and " |c00FF00<<|r" or ""
            d("  |cFFFF00[U]|r " .. (name or id) .. " (" .. (build.role or "?")
                .. "/" .. (build.context or "?") .. ")" .. active)
            count = count + 1
        end
    end
    if count == 0 then
        d("  " .. (lang == "ru" and "(нет доступных)" or "(none available)"))
    end
end
