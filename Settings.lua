----------------------------------------------------------------------
-- SmartGear — Settings Panel (LibAddonMenu-2.0)
----------------------------------------------------------------------
SmartGear = SmartGear or {}

function SmartGear.InitSettings()
    local LAM = LibAddonMenu2
    if not LAM then
        -- LibAddonMenu not available — settings via slash command only
        return
    end

    local lang = SmartGear.currentLang or "en"
    local sv = SmartGear.savedVars

    local panelData = {
        type = "panel",
        name = "SmartGear",
        displayName = "|c00FF00Smart|rGear",
        author = "SmartGear Team",
        version = SmartGear.version,
        slashCommand = "/smartgearsettings",
        registerForRefresh = true,
        registerForDefaults = true,
    }

    local optionsTable = {
        -- Role selection
        {
            type = "dropdown",
            name = lang == "ru" and "Роль персонажа" or "Character Role",
            tooltip = lang == "ru"
                and "Авто-определение по атрибутам и навыкам, или выберите вручную"
                or "Auto-detect from attributes and skills, or choose manually",
            choices = { "auto", "MagDD", "StamDD", "Tank", "Healer" },
            choicesValues = { "auto", "MagDD", "StamDD", "Tank", "Healer" },
            getFunc = function() return sv.roleOverride end,
            setFunc = function(value)
                sv.roleOverride = value
                SmartGear.currentRole = SmartGear.DetectRole()
            end,
            default = SmartGear.defaults.roleOverride,
            width = "full",
        },
        -- Current detected role (read-only info)
        {
            type = "description",
            text = function()
                local role = SmartGear.currentRole or "?"
                local display = SmartGear.GetRoleDisplayName(role)
                return (lang == "ru" and "Текущая роль: " or "Current role: ") .. "|cFFFF00" .. display .. "|r"
            end,
            width = "full",
        },
        -- PvP mode
        {
            type = "checkbox",
            name = lang == "ru" and "PvP режим" or "PvP Mode",
            tooltip = lang == "ru"
                and "Включает рекомендации для PvP (Impenetrable вместо Divines)"
                or "Enable PvP recommendations (Impenetrable instead of Divines)",
            getFunc = function() return sv.pvpMode end,
            setFunc = function(value) sv.pvpMode = value end,
            default = SmartGear.defaults.pvpMode,
            width = "full",
        },
        -- Display header
        {
            type = "header",
            name = lang == "ru" and "Отображение" or "Display",
            width = "full",
        },
        -- Show tooltips
        {
            type = "checkbox",
            name = lang == "ru" and "Показывать в тултипах" or "Show in Tooltips",
            tooltip = lang == "ru"
                and "Отображать блок SmartGear в подсказках предметов"
                or "Display SmartGear block in item tooltips",
            getFunc = function() return sv.showTooltips end,
            setFunc = function(value) sv.showTooltips = value end,
            default = SmartGear.defaults.showTooltips,
            width = "full",
        },
        -- Show stars
        {
            type = "checkbox",
            name = lang == "ru" and "Показывать звёзды рейтинга" or "Show Rating Stars",
            tooltip = lang == "ru"
                and "Показывать строку с ★★★ оценкой"
                or "Show the ★★★ rating line",
            getFunc = function() return sv.showStars end,
            setFunc = function(value) sv.showStars = value end,
            default = SmartGear.defaults.showStars,
            width = "full",
        },
        -- Show details
        {
            type = "checkbox",
            name = lang == "ru" and "Показывать детали" or "Show Details",
            tooltip = lang == "ru"
                and "Показывать подробную информацию (сет, трейт, вес)"
                or "Show detailed info (set, trait, weight)",
            getFunc = function() return sv.showDetails end,
            setFunc = function(value) sv.showDetails = value end,
            default = SmartGear.defaults.showDetails,
            width = "full",
        },
        -- Show comparison with equipped
        {
            type = "checkbox",
            name = lang == "ru" and "Сравнение с экипировкой" or "Compare with Equipped",
            tooltip = lang == "ru"
                and "Показывать блок сравнения предмета с текущей экипировкой (улучшение/ухудшение)"
                or "Show comparison block against currently equipped item (upgrade/downgrade)",
            getFunc = function() return sv.showComparison end,
            setFunc = function(value) sv.showComparison = value end,
            default = SmartGear.defaults.showComparison,
            width = "full",
        },
        -- Upgrade alerts
        {
            type = "checkbox",
            name = lang == "ru" and "Уведомления об улучшениях" or "Upgrade Alerts",
            tooltip = lang == "ru"
                and "Показывать всплывающее окно, когда в сумке есть предмет лучше надетого (с кнопкой Надеть)"
                or "Show popup when a better item is found in your bag (with Equip button)",
            getFunc = function() return sv.showAlerts end,
            setFunc = function(value) sv.showAlerts = value end,
            default = SmartGear.defaults.showAlerts,
            width = "full",
        },
        -- Show stickerbook hints
        {
            type = "checkbox",
            name = lang == "ru" and "Подсказки для стикербука" or "Stickerbook Hints",
            tooltip = lang == "ru"
                and "Подсказывать, когда предмет стоит добавить в коллекцию наборов"
                or "Suggest when an item should be added to the set collection",
            getFunc = function() return sv.showStickerbook end,
            setFunc = function(value) sv.showStickerbook = value end,
            default = SmartGear.defaults.showStickerbook,
            width = "full",
        },
        -- Language
        {
            type = "dropdown",
            name = lang == "ru" and "Язык / Language" or "Language",
            tooltip = lang == "ru"
                and "Язык отображения SmartGear"
                or "SmartGear display language",
            choices = { "auto", "en", "ru" },
            choicesValues = { "auto", "en", "ru" },
            getFunc = function() return sv.language end,
            setFunc = function(value)
                sv.language = value
                if value == "auto" then
                    local clientLang = GetCVar("language.2")
                    SmartGear.currentLang = (clientLang == "ru") and "ru" or "en"
                else
                    SmartGear.currentLang = value
                end
            end,
            default = SmartGear.defaults.language,
            width = "full",
        },
    }

    LAM:RegisterAddonPanel("SmartGearOptions", panelData)
    LAM:RegisterOptionControls("SmartGearOptions", optionsTable)
end

-- Open settings panel (called from slash command)
function SmartGear.OpenSettings()
    local LAM = LibAddonMenu2
    if LAM then
        LAM:OpenToPanel("SmartGearOptions")
    else
        d("|c00FF00[SmartGear]|r LibAddonMenu-2.0 not installed. Use /smartgear role or /smartgear refresh")
    end
end
