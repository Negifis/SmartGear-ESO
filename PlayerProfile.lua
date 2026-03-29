----------------------------------------------------------------------
-- SmartGear -- Player Profile Module
-- Reads and caches player stats, race, mundus stone for adaptive scoring.
-- Uses a dirty-flag pattern: stats are re-read lazily on first access
-- after a relevant game event fires.
----------------------------------------------------------------------
SmartGear = SmartGear or {}

----------------------------------------------------------------------
-- Mundus Stone ability ID -> stat mapping
-- IDs are stable across ESO patches (Mundus stones are base-game buffs)
----------------------------------------------------------------------
local MUNDUS_STONES = {
    [13940] = { name = "The Thief",       nameRu = "Вор",           stat = "critPercent",   value = 1548 },
    [13943] = { name = "The Shadow",      nameRu = "Тень",          stat = "critDamage",    value = 12 },
    [13974] = { name = "The Lover",       nameRu = "Любовник",      stat = "penetration",   value = 2752 },
    [13975] = { name = "The Atronach",    nameRu = "Атронах",       stat = "magRecovery",   value = 310 },
    [13976] = { name = "The Ritual",      nameRu = "Ритуал",        stat = "healingDone",   value = 10 },
    [13977] = { name = "The Apprentice",  nameRu = "Ученик",        stat = "weaponDamage",  value = 238 },
    [13984] = { name = "The Warrior",     nameRu = "Воин",          stat = "weaponDamage",  value = 238 },
    [13979] = { name = "The Tower",       nameRu = "Башня",         stat = "maxResource",   value = 2028 },
    [13980] = { name = "The Steed",       nameRu = "Конь",          stat = "maxHealth",     value = 2028 },
    [13981] = { name = "The Lady",        nameRu = "Леди",          stat = "resistance",    value = 2752 },
    [13982] = { name = "The Lord",        nameRu = "Лорд",          stat = "maxHealth",     value = 2028 },
    [13978] = { name = "The Mage",        nameRu = "Маг",           stat = "maxResource",   value = 2028 },
    [13942] = { name = "The Serpent",     nameRu = "Змей",          stat = "stamRecovery",  value = 310 },
}

----------------------------------------------------------------------
-- Race ID -> bonuses mapping
-- ESO race IDs: 1=Breton, 2=Redguard, 3=Orc, 4=DarkElf, 5=Nord,
-- 6=Argonian, 7=HighElf, 8=WoodElf, 9=Khajiit, 10=Imperial
----------------------------------------------------------------------
local RACE_BONUSES = {
    [1]  = { name = "Breton",   nameRu = "Бретон",      stats = { maxResource = 2000, costReduction = 0.07 } },
    [2]  = { name = "Redguard", nameRu = "Редгард",     stats = { maxResource = 1000, stamRecovery = 300 } },
    [3]  = { name = "Orc",      nameRu = "Орк",         stats = { maxResource = 1000, maxHealth = 1000, weaponDamage = 258 } },
    [4]  = { name = "Dark Elf", nameRu = "Данмер",      stats = { maxResource = 1910, weaponDamage = 258 } },
    [5]  = { name = "Nord",     nameRu = "Норд",        stats = { maxHealth = 1000, resistance = 2600, ultimateGen = 5 } },
    [6]  = { name = "Argonian", nameRu = "Аргонианин",  stats = { maxHealth = 1000, healingDone = 6, magRecovery = 100 } },
    [7]  = { name = "High Elf", nameRu = "Альтмер",     stats = { maxResource = 2000, weaponDamage = 258 } },
    [8]  = { name = "Wood Elf", nameRu = "Босмер",      stats = { maxResource = 2000, penetration = 950 } },
    [9]  = { name = "Khajiit",  nameRu = "Каджит",      stats = { critPercent = 3.33, maxHealth = 915, maxResource = 915 } },
    [10] = { name = "Imperial", nameRu = "Имперец",     stats = { maxHealth = 2000, maxResource = 2000 } },
}

----------------------------------------------------------------------
-- Player Profile data structure
----------------------------------------------------------------------
SmartGear.PlayerProfile = {
    -- Combat stats (raw from GetPlayerStat)
    weaponDamage = 0,
    spellDamage = 0,
    weaponSpellDmg = 0,   -- STAT_WEAPON_AND_SPELL_DAMAGE
    maxMagicka = 0,
    maxStamina = 0,
    maxHealth = 0,
    critRating = 0,        -- raw crit rating
    spellCritRating = 0,   -- raw spell crit
    physPen = 0,
    spellPen = 0,
    armorRating = 0,
    physResist = 0,
    spellResist = 0,
    critResist = 0,
    healingDone = 0,

    -- Derived (computed)
    effectiveCrit = 0,     -- % crit chance (best of weapon/spell)
    effectivePen = 0,      -- best of phys/spell pen
    effectiveResist = 0,   -- for tanks

    -- Identity
    raceId = 0,
    raceName = "",
    raceNameRu = "",
    raceStats = nil,       -- ref to RACE_BONUSES entry

    -- Mundus
    mundusId = nil,
    mundusName = "",
    mundusNameRu = "",
    mundusStat = nil,      -- which stat mundus boosts
    mundusInfo = nil,      -- ref to MUNDUS_STONES entry

    -- State
    dirty = true,
    lastRefresh = 0,
}

----------------------------------------------------------------------
-- Read all combat stats from ESO API
----------------------------------------------------------------------
local function ReadCombatStats()
    local p = SmartGear.PlayerProfile

    -- Direct stat reads
    p.weaponSpellDmg = GetPlayerStat(STAT_WEAPON_AND_SPELL_DAMAGE) or 0
    p.spellDamage    = GetPlayerStat(STAT_SPELL_POWER) or 0
    p.weaponDamage   = GetPlayerStat(STAT_POWER) or 0

    p.maxMagicka = GetPlayerStat(STAT_MAGICKA_MAX) or 0
    p.maxStamina = GetPlayerStat(STAT_STAMINA_MAX) or 0
    p.maxHealth  = GetPlayerStat(STAT_HEALTH_MAX) or 0

    p.critRating      = GetPlayerStat(STAT_CRITICAL_STRIKE) or 0
    p.spellCritRating = GetPlayerStat(STAT_SPELL_CRITICAL) or 0

    p.physPen  = GetPlayerStat(STAT_PHYSICAL_PENETRATION) or 0
    p.spellPen = GetPlayerStat(STAT_SPELL_PENETRATION) or 0

    p.armorRating = GetPlayerStat(STAT_ARMOR_RATING) or 0
    p.physResist  = GetPlayerStat(STAT_PHYSICAL_RESIST) or 0
    p.spellResist = GetPlayerStat(STAT_SPELL_RESIST) or 0

    p.critResist  = GetPlayerStat(STAT_CRITICAL_RESISTANCE) or 0
    p.healingDone = GetPlayerStat(STAT_HEALING_DONE) or 0

    -- Derived: crit rating -> percentage (ESO formula: rating / 219.3 per %)
    local critA = p.critRating / 219.3
    local critB = p.spellCritRating / 219.3
    p.effectiveCrit = math.max(critA, critB)

    -- Derived: effective pen (best of phys/spell)
    p.effectivePen = math.max(p.physPen, p.spellPen)

    -- Derived: effective resist (for tanks)
    p.effectiveResist = math.max(p.armorRating, math.max(p.physResist, p.spellResist))
end

----------------------------------------------------------------------
-- Detect race
----------------------------------------------------------------------
local function ReadRace()
    local p = SmartGear.PlayerProfile
    p.raceId = GetUnitRaceId("player") or 0

    local raceInfo = RACE_BONUSES[p.raceId]
    if raceInfo then
        p.raceName   = raceInfo.name
        p.raceNameRu = raceInfo.nameRu
        p.raceStats  = raceInfo.stats
    else
        p.raceName   = "Unknown"
        p.raceNameRu = "Неизвестно"
        p.raceStats  = nil
    end
end

----------------------------------------------------------------------
-- Detect mundus stone from active buffs
----------------------------------------------------------------------
local function ReadMundus()
    local p = SmartGear.PlayerProfile
    p.mundusId     = nil
    p.mundusName   = ""
    p.mundusNameRu = ""
    p.mundusStat   = nil
    p.mundusInfo   = nil

    local numBuffs = GetNumBuffs("player") or 0
    for i = 1, numBuffs do
        local buffName, timeStarted, timeEnding, buffSlot, stackCount,
              iconFilename, buffType, effectType, abilityType,
              statusEffectType, abilityId, canClickOff = GetUnitBuffInfo("player", i)

        if abilityId and MUNDUS_STONES[abilityId] then
            local mundus = MUNDUS_STONES[abilityId]
            p.mundusId     = abilityId
            p.mundusName   = mundus.name
            p.mundusNameRu = mundus.nameRu
            p.mundusStat   = mundus.stat
            p.mundusInfo   = mundus
            return -- found mundus, done
        end
    end
end

----------------------------------------------------------------------
-- Full profile refresh
----------------------------------------------------------------------
function SmartGear.RefreshPlayerProfile()
    ReadCombatStats()
    ReadRace()
    ReadMundus()

    local p = SmartGear.PlayerProfile
    p.dirty = false
    p.lastRefresh = GetGameTimeMilliseconds()
end

----------------------------------------------------------------------
-- Lazy refresh: call at start of scoring if dirty
----------------------------------------------------------------------
function SmartGear.EnsureProfileFresh()
    if SmartGear.PlayerProfile.dirty then
        SmartGear.RefreshPlayerProfile()
    end
end

----------------------------------------------------------------------
-- Gap analysis: compare current stats to role targets
-- Returns table of gap scores 0.0 (capped) to 1.0 (empty)
----------------------------------------------------------------------
function SmartGear.ComputeStatGaps(role)
    SmartGear.EnsureProfileFresh()

    local targets = SmartGear.StatTargets and SmartGear.StatTargets[role]
    if not targets then return {} end

    local p = SmartGear.PlayerProfile
    local gaps = {}

    -- Helper: compute single gap
    local function gap(current, target)
        if not target or target <= 0 then return 0 end
        local g = (target - current) / target
        return math.max(0, math.min(1, g))
    end

    -- Weapon / spell damage
    local effectiveWSD = math.max(p.weaponSpellDmg, math.max(p.weaponDamage, p.spellDamage))
    gaps.weaponDamage = gap(effectiveWSD, targets.weaponDamage)

    -- Critical chance (%)
    gaps.critPercent = gap(p.effectiveCrit, targets.critPercent)

    -- Penetration
    gaps.penetration = gap(p.effectivePen, targets.penetration)

    -- Max resource (mag or stam depending on role)
    if role == "MagDD" or role == "Healer" then
        gaps.maxResource = gap(p.maxMagicka, targets.maxResource)
    elseif role == "StamDD" then
        gaps.maxResource = gap(p.maxStamina, targets.maxResource)
    else  -- Tank
        gaps.maxResource = gap(math.max(p.maxMagicka, p.maxStamina), targets.maxResource)
    end

    -- Max health
    gaps.maxHealth = gap(p.maxHealth, targets.maxHealth)

    -- Resistance (for tanks)
    gaps.resistance = gap(p.effectiveResist, targets.resistance or 0)

    -- Crit resist
    gaps.critResist = gap(p.critResist, targets.critResist or 0)

    -- Healing done (healer)
    gaps.healingDone = gap(p.healingDone, targets.healingDone or 0)

    -- Mundus special: resolves to the stat the mundus boosts
    if p.mundusInfo and p.mundusInfo.stat and gaps[p.mundusInfo.stat] then
        gaps.mundus = gaps[p.mundusInfo.stat]
    else
        gaps.mundus = 0.5  -- unknown mundus = neutral
    end

    -- Stats without explicit targets get neutral gap
    gaps.executeDmg    = 0.4  -- Bloodthirsty: always somewhat useful for DD
    gaps.statusEffect  = 0.3  -- Charged: moderate value
    gaps.enchant       = 0.4  -- Infused: generally useful
    gaps.blockCost     = (role == "Tank") and 0.6 or 0.1
    gaps.dodge         = 0.15 -- Well-Fitted: rarely optimal
    gaps.critDamage    = gaps.critPercent * 0.8  -- correlated with crit need

    return gaps
end

----------------------------------------------------------------------
-- Mark profile dirty (called from event handlers)
----------------------------------------------------------------------
local function MarkDirty()
    SmartGear.PlayerProfile.dirty = true
end

----------------------------------------------------------------------
-- Initialize: register events
----------------------------------------------------------------------
function SmartGear.InitPlayerProfile()
    -- Gear change
    EVENT_MANAGER:RegisterForEvent(
        SmartGear.name .. "ProfileGear",
        EVENT_INVENTORY_SINGLE_SLOT_UPDATE,
        function(_, bagId)
            if bagId == BAG_WORN then MarkDirty() end
        end
    )

    -- Bar swap
    EVENT_MANAGER:RegisterForEvent(
        SmartGear.name .. "ProfileBarSwap",
        EVENT_ACTIVE_WEAPON_PAIR_CHANGED,
        MarkDirty
    )

    -- Zone load / login
    EVENT_MANAGER:RegisterForEvent(
        SmartGear.name .. "ProfileActivated",
        EVENT_PLAYER_ACTIVATED,
        MarkDirty
    )

    -- Buff changes (mundus, food, etc.)
    EVENT_MANAGER:RegisterForEvent(
        SmartGear.name .. "ProfileEffect",
        EVENT_EFFECT_CHANGED,
        function(_, changeType, effectSlot, effectName, unitTag)
            if unitTag == "player" then MarkDirty() end
        end
    )

    -- Attribute respec
    EVENT_MANAGER:RegisterForEvent(
        SmartGear.name .. "ProfileRespec",
        EVENT_ATTRIBUTE_FORCE_RESPEC,
        MarkDirty
    )

    -- Initial read (after a delay for all addons to load)
    zo_callLater(function()
        SmartGear.RefreshPlayerProfile()
    end, 3000)
end
