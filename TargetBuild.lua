----------------------------------------------------------------------
-- SmartGear — Target Build Browser UI
-- Full-featured: scroll, search, filter by role/context, grouping.
----------------------------------------------------------------------
SmartGear = SmartGear or {}

local isInitialized = false
local selectedBuildId = nil

-- Row pools
local buildRows = {}
local detailRows = {}
local bgCounter = 0

-- Scroll state
local scrollOffset = 0
local filteredBuilds = {}

-- Filter state
local searchText = ""
local filterRole = "all"    -- "all", "MagDD", "StamDD", "Tank", "Healer"
local filterCtx = "all"     -- "all", "solo", "group", "trial", "pvp"
local filterMyClass = true   -- true = show only current class builds

-- Layout constants
local ROW_HEIGHT = 30
local DETAIL_ROW_HEIGHT = 26
local MAX_VISIBLE_ROWS = 14
local MAX_DETAIL_ROWS = 14

-- UI refs
local browser, leftPanel, rightPanel, noBuildLabel
local listParent, searchBox, filtersParent
local buildNameLabel, roleCtxLabel, progressLabel
local activateBtn, deactivateBtn

-- Filter button controls
local filterBtns = {}

-- Localization helper
local function L(en, ru)
    return (SmartGear.currentLang == "ru") and ru or en
end

-- Role colors for list
local ROLE_COLORS = {
    MagDD  = {0.3, 0.6, 1.0},   -- blue
    StamDD = {0.3, 1.0, 0.3},   -- green
    Tank   = {1.0, 0.7, 0.3},   -- orange
    Healer = {1.0, 1.0, 0.5},   -- yellow
}

----------------------------------------------------------------------
-- Create a build row control
----------------------------------------------------------------------
local function CreateBuildRow(parent, index)
    local row = WINDOW_MANAGER:CreateControl("SGBRow" .. index, parent, CT_CONTROL)
    row:SetDimensions(250, ROW_HEIGHT)
    row:SetAnchor(TOPLEFT, parent, TOPLEFT, 0, (index - 1) * ROW_HEIGHT)
    row:SetMouseEnabled(true)

    bgCounter = bgCounter + 1
    local bg = WINDOW_MANAGER:CreateControl("SmartGearBG" .. bgCounter, row, CT_BACKDROP)
    bg:SetAnchorFill()
    bg:SetCenterColor(0.08, 0.08, 0.08, 0.6)
    bg:SetEdgeColor(0, 0, 0, 0)
    bg:SetEdgeTexture("", 1, 1, 0, 0)
    row._bg = bg

    -- Role dot
    local dot = WINDOW_MANAGER:CreateControl(nil, row, CT_BACKDROP)
    dot:SetDimensions(6, 6)
    dot:SetAnchor(LEFT, row, LEFT, 4, 0)
    dot:SetCenterColor(1, 1, 1, 1)
    dot:SetEdgeColor(0, 0, 0, 0)
    dot:SetEdgeTexture("", 1, 1, 0)
    row._dot = dot

    -- Name label
    local name = WINDOW_MANAGER:CreateControl(nil, row, CT_LABEL)
    name:SetFont("ZoFontGameSmall")
    name:SetColor(0.8, 0.8, 0.8, 1)
    name:SetAnchor(LEFT, row, LEFT, 14, 0)
    name:SetDimensions(200, ROW_HEIGHT)
    name:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    name:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    row._nameLabel = name

    -- Context tag
    local ctx = WINDOW_MANAGER:CreateControl(nil, row, CT_LABEL)
    ctx:SetFont("ZoFontGameSmall")
    ctx:SetColor(0.4, 0.4, 0.4, 1)
    ctx:SetAnchor(RIGHT, row, RIGHT, -4, 0)
    ctx:SetDimensions(40, ROW_HEIGHT)
    ctx:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
    ctx:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    row._ctxLabel = ctx

    -- Hover
    row:SetHandler("OnMouseEnter", function()
        bg:SetCenterColor(0.12, 0.18, 0.12, 0.8)
    end)
    row:SetHandler("OnMouseExit", function()
        local sel = selectedBuildId == row._buildId
        if sel then
            bg:SetCenterColor(0.1, 0.2, 0.1, 0.8)
        else
            bg:SetCenterColor(0.08, 0.08, 0.08, 0.6)
        end
    end)

    row:SetHidden(true)
    return row
end

----------------------------------------------------------------------
-- Create detail row
----------------------------------------------------------------------
local function CreateDetailRow(parent, index)
    local row = WINDOW_MANAGER:CreateControl("SGDRow" .. index, parent, CT_CONTROL)
    row:SetDimensions(400, DETAIL_ROW_HEIGHT)
    row:SetAnchor(TOPLEFT, parent, TOPLEFT, 0, (index - 1) * DETAIL_ROW_HEIGHT)

    local name = WINDOW_MANAGER:CreateControl(nil, row, CT_LABEL)
    name:SetFont("ZoFontGame")
    name:SetColor(0.8, 0.8, 0.8, 1)
    name:SetAnchor(LEFT, row, LEFT, 0, 0)
    name:SetDimensions(280, DETAIL_ROW_HEIGHT)
    name:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    name:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    row._nameLabel = name

    local cnt = WINDOW_MANAGER:CreateControl(nil, row, CT_LABEL)
    cnt:SetFont("ZoFontGameBold")
    cnt:SetColor(0, 1, 0, 1)
    cnt:SetAnchor(LEFT, row, LEFT, 285, 0)
    cnt:SetDimensions(40, DETAIL_ROW_HEIGHT)
    cnt:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    cnt:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    row._countLabel = cnt

    local barBg = WINDOW_MANAGER:CreateControl(nil, row, CT_BACKDROP)
    barBg:SetDimensions(70, 10)
    barBg:SetAnchor(LEFT, row, LEFT, 330, 0)
    barBg:SetCenterColor(0.12, 0.12, 0.12, 0.8)
    barBg:SetEdgeColor(0.2, 0.2, 0.2, 0.5)
    barBg:SetEdgeTexture("", 1, 1, 1)
    row._barBg = barBg

    local barFill = WINDOW_MANAGER:CreateControl(nil, row, CT_BACKDROP)
    barFill:SetDimensions(1, 10)
    barFill:SetAnchor(LEFT, barBg, LEFT, 0, 0)
    barFill:SetCenterColor(0, 0.6, 0, 0.9)
    barFill:SetEdgeColor(0, 0, 0, 0)
    barFill:SetEdgeTexture("", 1, 1, 0)
    row._barFill = barFill

    row:SetHidden(true)
    return row
end

----------------------------------------------------------------------
-- Create filter button
----------------------------------------------------------------------
local function CreateFilterBtn(parent, label, value, xOffset)
    local btn = WINDOW_MANAGER:CreateControl(nil, parent, CT_LABEL)
    btn:SetFont("ZoFontGameSmall")
    btn:SetText(label)
    btn:SetColor(0.5, 0.5, 0.5, 1)
    btn:SetDimensions(38, 20)
    btn:SetAnchor(LEFT, parent, LEFT, xOffset, 0)
    btn:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    btn:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    btn:SetMouseEnabled(true)

    btn._value = value
    btn._label = label

    btn:SetHandler("OnMouseUp", function()
        filterRole = value
        scrollOffset = 0
        SmartGear.RefreshBuildList()
    end)
    btn:SetHandler("OnMouseEnter", function()
        btn:SetColor(1, 1, 1, 1)
    end)
    btn:SetHandler("OnMouseExit", function()
        if filterRole == value then
            btn:SetColor(0, 1, 0, 1)
        else
            btn:SetColor(0.5, 0.5, 0.5, 1)
        end
    end)

    return btn
end

----------------------------------------------------------------------
-- Init UI
----------------------------------------------------------------------
local function MakeBG(parent, r, g, b, a)
    bgCounter = bgCounter + 1
    local bg = WINDOW_MANAGER:CreateControl("SmartGearBG" .. bgCounter, parent, CT_BACKDROP)
    bg:SetAnchorFill()
    bg:SetCenterColor(r, g, b, a)
    bg:SetEdgeColor(0, 0, 0, 0)
    bg:SetEdgeTexture("", 1, 1, 0, 0)
    return bg
end

local function InitUI()
    browser = SmartGearBuildBrowser
    if not browser then return false end

    -- Create all backgrounds in Lua (XML Texture color doesn't work reliably)
    MakeBG(browser, 0.04, 0.04, 0.04, 0.95)  -- main dark bg

    local closeBtn = browser:GetNamedChild("CloseBtn")
    if closeBtn then
        closeBtn:SetHandler("OnClicked", function() SmartGear.ToggleBuildBrowser() end)
    end

    leftPanel = browser:GetNamedChild("LeftPanel")
    rightPanel = browser:GetNamedChild("RightPanel")
    noBuildLabel = browser:GetNamedChild("NoBuildLabel")
    listParent = leftPanel:GetNamedChild("List")
    searchBox = leftPanel:GetNamedChild("SearchBox")
    filtersParent = leftPanel:GetNamedChild("Filters")

    buildNameLabel = rightPanel:GetNamedChild("BuildName")
    roleCtxLabel = rightPanel:GetNamedChild("RoleCtx")
    progressLabel = rightPanel:GetNamedChild("Progress")
    activateBtn = rightPanel:GetNamedChild("ActivateBtn")
    deactivateBtn = rightPanel:GetNamedChild("DeactivateBtn")

    -- Create backgrounds (after all refs are resolved)
    local header = browser:GetNamedChild("Header")
    if header then
        MakeBG(header, 0, 0.12, 0, 0.95)
        local headerTitle = header:GetNamedChild("Title")
        if headerTitle then
            headerTitle:SetText(L("SmartGear -- Target Build", "SmartGear -- Целевая сборка"))
        end
    end
    MakeBG(rightPanel, 0.06, 0.06, 0.06, 0.7)
    MakeBG(activateBtn, 0, 0.35, 0, 0.9)
    MakeBG(deactivateBtn, 0.35, 0.12, 0, 0.9)

    -- Activate/Deactivate handlers
    activateBtn:SetHandler("OnClicked", function()
        if selectedBuildId then
            SmartGear.ActivateBuild(selectedBuildId)
            SmartGear.RefreshBuildBrowser()
        end
    end)
    deactivateBtn:SetHandler("OnClicked", function()
        SmartGear.ActivateBuild(nil)
        SmartGear.RefreshBuildBrowser()
    end)

    -- Search box
    searchBox:SetHandler("OnTextChanged", function()
        searchText = searchBox:GetText() or ""
        scrollOffset = 0
        SmartGear.RefreshBuildList()
    end)
    -- Placeholder text
    searchBox:SetText("")

    -- Filter buttons: All | DD | Tank | Heal
    local filters = {
        {"All",  "all",    0},
        {"MagDD", "MagDD", 42},
        {"StamDD","StamDD",84},
        {"Tank", "Tank",   130},
        {"Heal", "Healer", 172},
    }
    for _, f in ipairs(filters) do
        local btn = CreateFilterBtn(filtersParent, f[1], f[2], f[3])
        table.insert(filterBtns, btn)
    end

    -- Class toggle button (below filters)
    local classToggle = WINDOW_MANAGER:CreateControl("SGClassToggle", filtersParent, CT_LABEL)
    classToggle:SetFont("ZoFontGameSmall")
    classToggle:SetDimensions(50, 20)
    classToggle:SetAnchor(LEFT, filtersParent, LEFT, 215, 0)
    classToggle:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    classToggle:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    classToggle:SetMouseEnabled(true)
    classToggle:SetText("[Cls]")
    classToggle:SetColor(0, 1, 0, 1)

    classToggle:SetHandler("OnMouseUp", function()
        filterMyClass = not filterMyClass
        scrollOffset = 0
        if filterMyClass then
            classToggle:SetColor(0, 1, 0, 1)
            classToggle:SetText("[Cls]")
        else
            classToggle:SetColor(0.5, 0.5, 0.5, 1)
            classToggle:SetText("[All]")
        end
        SmartGear.RefreshBuildList()
    end)
    classToggle:SetHandler("OnMouseEnter", function() classToggle:SetColor(1, 1, 1, 1) end)
    classToggle:SetHandler("OnMouseExit", function()
        if filterMyClass then classToggle:SetColor(0, 1, 0, 1)
        else classToggle:SetColor(0.5, 0.5, 0.5, 1) end
    end)

    -- Create row pools
    for i = 1, MAX_VISIBLE_ROWS do
        buildRows[i] = CreateBuildRow(listParent, i)
    end
    local detailParent = rightPanel:GetNamedChild("SetList")
    for i = 1, MAX_DETAIL_ROWS do
        detailRows[i] = CreateDetailRow(detailParent, i)
    end

    -- Mouse wheel scroll on build list
    listParent:SetMouseEnabled(true)
    listParent:SetHandler("OnMouseWheel", function(_, delta)
        scrollOffset = scrollOffset - delta * 2
        local maxScroll = math.max(0, #filteredBuilds - MAX_VISIBLE_ROWS)
        scrollOffset = math.max(0, math.min(scrollOffset, maxScroll))
        SmartGear.RenderBuildRows()
    end)

    -- ESC to close
    browser:SetHandler("OnKeyUp", function(_, key)
        if key == KEY_ESCAPE then SmartGear.ToggleBuildBrowser() end
    end)

    isInitialized = true
    return true
end

----------------------------------------------------------------------
-- Collect and filter builds
----------------------------------------------------------------------
function SmartGear.CollectFilteredBuilds()
    local lang = SmartGear.currentLang or "en"
    local all = {}

    if SmartGear.PreBuilds then
        for id, build in pairs(SmartGear.PreBuilds) do
            table.insert(all, { id = id, build = build, isPre = true })
        end
    end
    if SmartGear.savedVars and SmartGear.savedVars.customBuilds then
        for id, build in pairs(SmartGear.savedVars.customBuilds) do
            table.insert(all, { id = id, build = build, isPre = false })
        end
    end

    -- Get player class for filtering
    local playerClassId = GetUnitClassId("player")

    -- Apply filters
    local filtered = {}
    local searchLower = string.lower(searchText)

    for _, entry in ipairs(all) do
        local b = entry.build
        local name = lang == "ru" and (b.nameRu or b.name) or b.name
        local nameLower = string.lower(name or "")

        -- Class filter (default ON — only show builds for your class)
        if filterMyClass and b.classId and b.classId ~= playerClassId then
            -- skip: wrong class
        -- Role filter
        elseif filterRole ~= "all" and b.role ~= filterRole then
            -- skip
        -- Search filter
        elseif searchLower ~= "" and not string.find(nameLower, searchLower, 1, true) then
            -- skip
        else
            table.insert(filtered, entry)
        end
    end

    -- Sort: by role, then by name
    table.sort(filtered, function(a, b)
        if a.build.role ~= b.build.role then
            return (a.build.role or "") < (b.build.role or "")
        end
        local na = lang == "ru" and (a.build.nameRu or a.build.name) or a.build.name
        local nb = lang == "ru" and (b.build.nameRu or b.build.name) or b.build.name
        return (na or "") < (nb or "")
    end)

    filteredBuilds = filtered
end

----------------------------------------------------------------------
-- Render visible build rows (from scrollOffset)
----------------------------------------------------------------------
function SmartGear.RenderBuildRows()
    local lang = SmartGear.currentLang or "en"

    for i = 1, MAX_VISIBLE_ROWS do
        local row = buildRows[i]
        if not row then break end

        local dataIdx = scrollOffset + i
        if dataIdx <= #filteredBuilds then
            local data = filteredBuilds[dataIdx]
            local b = data.build
            local name = lang == "ru" and (b.nameRu or b.name) or b.name
            row._nameLabel:SetText(name or data.id)

            -- Context label
            local ctxShort = {solo="solo", group="grp", trial="tri", pvp="pvp"}
            row._ctxLabel:SetText(ctxShort[b.context] or "")

            -- Role dot color
            local rc = ROLE_COLORS[b.role] or {0.5, 0.5, 0.5}
            row._dot:SetCenterColor(rc[1], rc[2], rc[3], 1)

            -- Active highlight
            local isActive = SmartGear.ActiveBuild and SmartGear.ActiveBuild.id == data.id
            local isSelected = selectedBuildId == data.id

            if isActive then
                row._nameLabel:SetColor(0, 1, 0, 1)
            elseif isSelected then
                row._nameLabel:SetColor(1, 1, 1, 1)
            else
                row._nameLabel:SetColor(0.75, 0.75, 0.75, 1)
            end

            if isSelected then
                row._bg:SetCenterColor(0.1, 0.2, 0.1, 0.8)
            else
                row._bg:SetCenterColor(0.08, 0.08, 0.08, 0.6)
            end

            row._buildId = data.id
            row:SetHandler("OnMouseUp", function()
                selectedBuildId = data.id
                SmartGear.ShowBuildDetails(data.id)
                SmartGear.RenderBuildRows()
            end)

            row:SetHidden(false)
        else
            row:SetHidden(true)
        end
    end

    -- Update filter button colors
    for _, btn in ipairs(filterBtns) do
        if btn._value == filterRole then
            btn:SetColor(0, 1, 0, 1)
        else
            btn:SetColor(0.5, 0.5, 0.5, 1)
        end
    end
end

----------------------------------------------------------------------
-- Refresh build list (filter + render)
----------------------------------------------------------------------
function SmartGear.RefreshBuildList()
    SmartGear.CollectFilteredBuilds()
    SmartGear.RenderBuildRows()
end

----------------------------------------------------------------------
-- Show build details (right panel)
----------------------------------------------------------------------
function SmartGear.ShowBuildDetails(buildId)
    local build = nil
    if SmartGear.PreBuilds and SmartGear.PreBuilds[buildId] then
        build = SmartGear.PreBuilds[buildId]
    elseif SmartGear.savedVars and SmartGear.savedVars.customBuilds
           and SmartGear.savedVars.customBuilds[buildId] then
        build = SmartGear.savedVars.customBuilds[buildId]
    end

    if not build then
        rightPanel:SetHidden(true)
        noBuildLabel:SetHidden(false)
        return
    end

    rightPanel:SetHidden(false)
    noBuildLabel:SetHidden(true)

    local lang = SmartGear.currentLang or "en"
    local name = lang == "ru" and (build.nameRu or build.name) or build.name
    buildNameLabel:SetText(name or buildId)

    local roleName = SmartGear.GetRoleDisplayName and SmartGear.GetRoleDisplayName(build.role) or (build.role or "?")
    local ctxInfo = SmartGear.ContentContexts and SmartGear.ContentContexts[build.context]
    local ctxName = ctxInfo and (lang == "ru" and ctxInfo.nameRu or ctxInfo.name) or (build.context or "?")
    roleCtxLabel:SetText(roleName .. " | " .. ctxName)

    -- Per-slot progress evaluation
    local overall, slotResults = SmartGear.EvaluateBuildProgress(build)

    -- Progress label with overall %
    progressLabel:SetText(
        (lang == "ru" and "Прогресс: " or "Progress: ")
        .. overall .. "%"
    )
    if overall >= 80 then progressLabel:SetColor(0, 1, 0, 1)
    elseif overall >= 50 then progressLabel:SetColor(1, 1, 0, 1)
    else progressLabel:SetColor(1, 0.5, 0, 1) end

    -- Slot name lookup (localized)
    local SLOT_NAMES_SHORT = {
        [EQUIP_SLOT_HEAD]        = L("Head",  "Голова"),
        [EQUIP_SLOT_SHOULDERS]   = L("Shldr", "Плечи"),
        [EQUIP_SLOT_CHEST]       = L("Chest", "Грудь"),
        [EQUIP_SLOT_WAIST]       = L("Waist", "Пояс"),
        [EQUIP_SLOT_LEGS]        = L("Legs",  "Ноги"),
        [EQUIP_SLOT_FEET]        = L("Feet",  "Ступни"),
        [EQUIP_SLOT_HAND]        = L("Hands", "Руки"),
        [EQUIP_SLOT_NECK]        = L("Neck",  "Шея"),
        [EQUIP_SLOT_RING1]       = L("Ring1", "Кольцо1"),
        [EQUIP_SLOT_RING2]       = L("Ring2", "Кольцо2"),
        [EQUIP_SLOT_MAIN_HAND]   = L("MH",    "Осн"),
        [EQUIP_SLOT_OFF_HAND]    = L("OH",    "Лев"),
        [EQUIP_SLOT_BACKUP_MAIN] = L("BkMH",  "Зап"),
        [EQUIP_SLOT_BACKUP_OFF]  = L("BkOH",  "ЗапЛ"),
    }

    -- Fill detail rows with per-slot data
    for i = 1, MAX_DETAIL_ROWS do
        local row = detailRows[i]
        if not row then break end

        if i <= #slotResults then
            local sr = slotResults[i]
            local d_info = sr.details
            local slotName = SLOT_NAMES_SHORT[sr.slot] or "?"
            local targetSet = d_info and d_info.targetSet or "?"

            -- Build spec details for this slot
            local spec = build and build.slots and build.slots[sr.slot]
            local specParts = {}
            -- Weapon type short name
            if spec and spec.weaponType then
                local WT_NAMES = {
                    [WEAPONTYPE_DAGGER] = L("Dag","Кинж"),
                    [WEAPONTYPE_SWORD] = L("Swd","Меч"),
                    [WEAPONTYPE_AXE] = L("Axe","Топор"),
                    [WEAPONTYPE_HAMMER] = L("Mace","Бул"),
                    [WEAPONTYPE_TWO_HANDED_SWORD] = L("2HSwd","2Р Меч"),
                    [WEAPONTYPE_TWO_HANDED_AXE] = L("2HAxe","2Р Топор"),
                    [WEAPONTYPE_TWO_HANDED_HAMMER] = L("2HMaul","2Р Бул"),
                    [WEAPONTYPE_BOW] = L("Bow","Лук"),
                    [WEAPONTYPE_FIRE_STAFF] = L("Fire","Огонь"),
                    [WEAPONTYPE_LIGHTNING_STAFF] = L("Light","Молния"),
                    [WEAPONTYPE_ICE_STAFF] = L("Ice","Лёд"),
                    [WEAPONTYPE_RESTORATION_STAFF] = L("Resto","Восст"),
                    [WEAPONTYPE_SHIELD] = L("Shld","Щит"),
                }
                table.insert(specParts, WT_NAMES[spec.weaponType] or "?")
            end
            -- Trait short name
            if spec and spec.trait and SmartGear.TraitNames then
                local tName = SmartGear.TraitNames[spec.trait]
                if tName then table.insert(specParts, tName) end
            end
            -- Weight short name
            if spec and spec.weight then
                local W_SHORT = {
                    [ARMORTYPE_LIGHT] = L("Lt","Лг"),
                    [ARMORTYPE_MEDIUM] = L("Md","Ср"),
                    [ARMORTYPE_HEAVY] = L("Hv","Тж"),
                }
                table.insert(specParts, W_SHORT[spec.weight] or "")
            end

            local specStr = #specParts > 0 and (" [" .. table.concat(specParts, ",") .. "]") or ""

            -- Name: "Slot: SetName [WeaponType, Trait, Weight]"
            row._nameLabel:SetText(slotName .. ": " .. targetSet .. specStr)

            -- Score as text
            if d_info and d_info.empty then
                row._countLabel:SetText(L("EMPTY", "ПУСТО"))
                row._countLabel:SetColor(1, 0, 0, 1)
            else
                row._countLabel:SetText(sr.score .. "%")
                if sr.score >= 80 then
                    row._countLabel:SetColor(0, 1, 0, 1)
                elseif sr.score >= 50 then
                    row._countLabel:SetColor(1, 1, 0, 1)
                else
                    row._countLabel:SetColor(1, 0.5, 0, 1)
                end
            end

            -- Name color: set match
            if d_info and d_info.setMatch then
                row._nameLabel:SetColor(0, 1, 0, 1)
            elseif d_info and d_info.empty then
                row._nameLabel:SetColor(1, 0, 0, 1)
            else
                row._nameLabel:SetColor(0.8, 0.5, 0.2, 1)  -- orange = wrong set
            end

            -- Progress bar
            local barWidth = row._barBg:GetWidth()
            local ratio = sr.score / 100
            row._barFill:SetWidth(math.max(1, barWidth * ratio))
            if ratio >= 0.8 then row._barFill:SetCenterColor(0, 0.65, 0, 0.9)
            elseif ratio >= 0.5 then row._barFill:SetCenterColor(0.65, 0.65, 0, 0.9)
            else row._barFill:SetCenterColor(0.65, 0.3, 0, 0.8) end

            row:SetHidden(false)
        else
            row:SetHidden(true)
        end
    end

    -- Buttons
    local isActive = SmartGear.ActiveBuild and SmartGear.ActiveBuild.id == buildId
    activateBtn:SetHidden(isActive)
    deactivateBtn:SetHidden(not isActive)

    local actLabel = activateBtn:GetNamedChild("Label")
    local deactLabel = deactivateBtn:GetNamedChild("Label")
    if actLabel then actLabel:SetText(lang == "ru" and "АКТИВИРОВАТЬ" or "ACTIVATE") end
    if deactLabel then deactLabel:SetText(lang == "ru" and "ДЕАКТИВИРОВАТЬ" or "DEACTIVATE") end
end

----------------------------------------------------------------------
-- Toggle browser
----------------------------------------------------------------------
function SmartGear.ToggleBuildBrowser()
    if not isInitialized then
        if not InitUI() then
            d("|c00FF00[SmartGear]|r Build browser UI not available.")
            return
        end
    end

    if browser:IsHidden() then
        scrollOffset = 0
        SmartGear.RefreshBuildList()
        browser:SetHidden(false)

        if SmartGear.ActiveBuild and SmartGear.ActiveBuild.id then
            selectedBuildId = SmartGear.ActiveBuild.id
            SmartGear.ShowBuildDetails(selectedBuildId)
        else
            rightPanel:SetHidden(true)
            noBuildLabel:SetHidden(false)
            noBuildLabel:SetText(
                SmartGear.currentLang == "ru"
                    and "Выберите сборку из списка"
                    or  "Select a build from the list"
            )
        end
    else
        browser:SetHidden(true)
    end
end

----------------------------------------------------------------------
-- Refresh (after activate/deactivate)
----------------------------------------------------------------------
function SmartGear.RefreshBuildBrowser()
    if not isInitialized or not browser or browser:IsHidden() then return end
    SmartGear.RefreshBuildList()
    if selectedBuildId then
        SmartGear.ShowBuildDetails(selectedBuildId)
    end
end

----------------------------------------------------------------------
-- Init (deferred)
----------------------------------------------------------------------
function SmartGear.InitBuildBrowser() end
