----------------------------------------------------------------------
-- SmartGear — Target Build Scoring Engine
-- Evaluates items based on how much they bring the player
-- closer to a target build. Uses a 5-layer gradient system.
----------------------------------------------------------------------
SmartGear = SmartGear or {}

----------------------------------------------------------------------
-- Count how many pieces of a set are currently equipped
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
-- Activate a target build: resolve from PreBuilds or customBuilds,
-- compute derived caches (_sets, _statProfile)
----------------------------------------------------------------------
function SmartGear.ActivateBuild(buildId)
    if not buildId then
        SmartGear.ActiveBuild = nil
        if SmartGear.savedVars then
            SmartGear.savedVars.activeBuildId = nil
        end
        d("|c00FF00[SmartGear]|r Target build deactivated.")
        return
    end

    -- Find the build
    local build = nil
    if SmartGear.PreBuilds and SmartGear.PreBuilds[buildId] then
        build = SmartGear.PreBuilds[buildId]
    elseif SmartGear.savedVars and SmartGear.savedVars.customBuilds
           and SmartGear.savedVars.customBuilds[buildId] then
        build = SmartGear.savedVars.customBuilds[buildId]
    end

    if not build then
        d("|c00FF00[SmartGear]|r Build not found: " .. tostring(buildId))
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

    -- Compute stat profile from set contributions
    build._statProfile = {}
    if SmartGear.MetaSets then
        for setName, setInfo in pairs(build._sets) do
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
    d("|c00FF00[SmartGear]|r Target build activated: |cFFFF00" .. (name or buildId) .. "|r")

    -- Show progress
    SmartGear.ShowBuildProgress()
end

----------------------------------------------------------------------
-- Compute target build score for an item
-- Returns: score (number), match (table with details)
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
    }

    -- Get item's set name
    local itemSetName = result.setName
    if not itemSetName then
        -- No set = always penalty
        match.statSynergy = -3
        return -3, match
    end

    -- Check if item belongs to any target set
    local targetSetInfo = build._sets[itemSetName]

    if targetSetInfo then
        -- ============================================
        -- LAYER 1: Set membership (+25 to +35)
        -- ============================================
        match.isTargetSet = true
        match.setName = itemSetName
        score = score + 25

        -- Check if we still need pieces
        local equipped = SmartGear.CountEquippedFromSet(itemSetName)
        local needed = targetSetInfo.count
        if equipped < needed then
            score = score + 10  -- urgently need this piece
            match.needMore = true
            match.piecesNeeded = needed - equipped
        else
            score = score + 3   -- already have enough, just trait/weight upgrade
        end

        -- ============================================
        -- LAYER 2: Correct trait (+8)
        -- ============================================
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

        -- ============================================
        -- LAYER 3: Correct weight (+5)
        -- ============================================
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

    else
        -- ============================================
        -- LAYER 4: Stat similarity for non-target sets (-5 to +10)
        -- ============================================
        local synergy = 0
        if build._statProfile and SmartGear.MetaSets then
            local meta = SmartGear.MetaSets[itemSetName]
            if meta and meta.statContributions then
                -- Compare item's stat contributions with build's stat profile
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
                    synergy = math.floor(ratio * 15) - 5  -- 0 overlap = -5, full overlap = +10
                    synergy = math.max(-5, math.min(10, synergy))
                end
            else
                synergy = -3  -- unknown set, mild penalty
            end
        end
        match.statSynergy = synergy
        score = score + synergy

        -- ============================================
        -- LAYER 5: Non-target set penalty (-5)
        -- ============================================
        score = score - 5
    end

    return score, match
end

----------------------------------------------------------------------
-- Show build progress in chat
----------------------------------------------------------------------
function SmartGear.ShowBuildProgress()
    local build = SmartGear.ActiveBuild
    if not build then
        d("|c00FF00[SmartGear]|r No target build active.")
        return
    end

    local lang = SmartGear.currentLang or "en"
    local name = lang == "ru" and (build.nameRu or build.name) or build.name

    d("|c00FF00[SmartGear]|r " .. (lang == "ru" and "Прогресс сборки: " or "Build progress: ")
        .. "|cFFFF00" .. (name or "?") .. "|r")

    local totalSlots = 0
    local matchedSlots = 0
    local missing = {}

    if build._sets then
        for setName, setInfo in pairs(build._sets) do
            local equipped = SmartGear.CountEquippedFromSet(setName)
            local needed = setInfo.count
            totalSlots = totalSlots + needed

            if equipped >= needed then
                matchedSlots = matchedSlots + needed
                d("  |c00FF00(+)|r " .. setName .. ": " .. equipped .. "/" .. needed)
            else
                matchedSlots = matchedSlots + equipped
                d("  |cFFFF00(.)|r " .. setName .. ": " .. equipped .. "/" .. needed
                    .. " (" .. (lang == "ru" and "нужно " or "need ") .. (needed - equipped) .. ")")
                table.insert(missing, { name = setName, need = needed - equipped })
            end
        end
    end

    d("  " .. (lang == "ru" and "Итого: " or "Total: ")
        .. "|cFFFFFF" .. matchedSlots .. "/" .. totalSlots .. "|r"
        .. " (" .. math.floor(matchedSlots / math.max(1, totalSlots) * 100) .. "%)")
end

----------------------------------------------------------------------
-- List available builds
----------------------------------------------------------------------
function SmartGear.ListBuilds()
    local lang = SmartGear.currentLang or "en"
    d("|c00FF00[SmartGear]|r " .. (lang == "ru" and "Доступные сборки:" or "Available builds:"))

    local count = 0

    -- Pre-built
    if SmartGear.PreBuilds then
        for id, build in pairs(SmartGear.PreBuilds) do
            local name = lang == "ru" and (build.nameRu or build.name) or build.name
            local active = (SmartGear.ActiveBuild and SmartGear.ActiveBuild.id == id) and " |c00FF00<<ACTIVE|r" or ""
            d("  |c00DDFF[pre]|r " .. id .. " — " .. (name or "?")
                .. " (" .. (build.role or "?") .. "/" .. (build.context or "?") .. ")" .. active)
            count = count + 1
        end
    end

    -- Custom
    if SmartGear.savedVars and SmartGear.savedVars.customBuilds then
        for id, build in pairs(SmartGear.savedVars.customBuilds) do
            local name = lang == "ru" and (build.nameRu or build.name) or build.name
            local active = (SmartGear.ActiveBuild and SmartGear.ActiveBuild.id == id) and " |c00FF00<<ACTIVE|r" or ""
            d("  |cFFFF00[usr]|r " .. id .. " — " .. (name or "?")
                .. " (" .. (build.role or "?") .. "/" .. (build.context or "?") .. ")" .. active)
            count = count + 1
        end
    end

    if count == 0 then
        d("  " .. (lang == "ru" and "(нет доступных сборок)" or "(no builds available)"))
    end
end
