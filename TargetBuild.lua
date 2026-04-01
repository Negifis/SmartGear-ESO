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

-- Scroll state
local scrollOffset = 0
local filteredBuilds = {}

-- Filter state
local searchText = ""
local filterRole = "all"    -- "all", "MagDD", "StamDD", "Tank", "Healer"
local filterCtx = "all"     -- "all", "solo", "group", "trial", "pvp"

-- Layout constants
local ROW_HEIGHT = 30
local DETAIL_ROW_HEIGHT = 26
local MAX_VISIBLE_ROWS = 14
local MAX_DETAIL_ROWS = 12

-- UI refs
local browser, leftPanel, rightPanel, noBuildLabel
local listParent, searchBox, filtersParent
local buildNameLabel, roleCtxLabel, progressLabel
local activateBtn, deactivateBtn

-- Filter button controls
local filterBtns = {}

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

    local bg = WINDOW_MANAGER:CreateControl(nil, row, CT_TEXTURE)
    bg:SetAnchorFill(row)
    bg:SetTexture("EsoUI/Art/Miscellaneous/single_pixel.dds")
    bg:SetColor(0.08, 0.08, 0.08, 0.6)
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
        bg:SetColor(0.12, 0.18, 0.12, 0.8)
    end)
    row:SetHandler("OnMouseExit", function()
        local sel = selectedBuildId == row._buildId
        if sel then
            bg:SetColor(0.1, 0.2, 0.1, 0.8)
        else
            bg:SetColor(0.08, 0.08, 0.08, 0.6)
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
    name:SetDimensions(190, DETAIL_ROW_HEIGHT)
    name:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    name:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    row._nameLabel = name

    local cnt = WINDOW_MANAGER:CreateControl(nil, row, CT_LABEL)
    cnt:SetFont("ZoFontGameBold")
    cnt:SetColor(0, 1, 0, 1)
    cnt:SetAnchor(LEFT, row, LEFT, 195, 0)
    cnt:SetDimensions(45, DETAIL_ROW_HEIGHT)
    cnt:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    cnt:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    row._countLabel = cnt

    local barBg = WINDOW_MANAGER:CreateControl(nil, row, CT_BACKDROP)
    barBg:SetDimensions(140, 10)
    barBg:SetAnchor(LEFT, row, LEFT, 248, 0)
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
local PIXEL = "EsoUI/Art/Miscellaneous/single_pixel.dds"

local function MakeBG(parent, r, g, b, a)
    local tex = WINDOW_MANAGER:CreateControl(nil, parent, CT_TEXTURE)
    tex:SetTexture(PIXEL)
    tex:SetAnchorFill(parent)
    tex:SetColor(r, g, b, a)
    return tex
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

    -- Header bg
    local header = browser:GetNamedChild("Header")
    if header then MakeBG(header, 0, 0.12, 0, 0.95) end

    -- Right panel bg
    MakeBG(rightPanel, 0.06, 0.06, 0.06, 0.7)

    -- Search box bg
    MakeBG(searchBox, 0.1, 0.1, 0.1, 0.85)

    -- Button backgrounds
    MakeBG(activateBtn, 0, 0.35, 0, 0.9)
    MakeBG(deactivateBtn, 0.35, 0.12, 0, 0.9)

    buildNameLabel = rightPanel:GetNamedChild("BuildName")
    roleCtxLabel = rightPanel:GetNamedChild("RoleCtx")
    progressLabel = rightPanel:GetNamedChild("Progress")
    activateBtn = rightPanel:GetNamedChild("ActivateBtn")
    deactivateBtn = rightPanel:GetNamedChild("DeactivateBtn")

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

    -- Apply filters
    local filtered = {}
    local searchLower = string.lower(searchText)

    for _, entry in ipairs(all) do
        local b = entry.build
        local name = lang == "ru" and (b.nameRu or b.name) or b.name
        local nameLower = string.lower(name or "")

        -- Role filter
        if filterRole ~= "all" and b.role ~= filterRole then
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
                row._bg:SetColor(0.1, 0.2, 0.1, 0.8)
            else
                row._bg:SetColor(0.08, 0.08, 0.08, 0.6)
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

    -- Compute set progress
    local sets = {}
    local setOrder = {}
    if build.slots then
        for slot, spec in pairs(build.slots) do
            if spec and spec.set then
                if not sets[spec.set] then
                    sets[spec.set] = { needed = 0, equipped = 0 }
                    table.insert(setOrder, spec.set)
                end
                sets[spec.set].needed = sets[spec.set].needed + 1
            end
        end
    end

    local totalNeeded = 0
    local totalEquipped = 0
    for setName, info in pairs(sets) do
        info.equipped = SmartGear.CountEquippedFromSet(setName)
        totalNeeded = totalNeeded + info.needed
        totalEquipped = totalEquipped + math.min(info.equipped, info.needed)
    end

    local pct = totalNeeded > 0 and math.floor(totalEquipped / totalNeeded * 100) or 0
    progressLabel:SetText(
        (lang == "ru" and "Прогресс: " or "Progress: ")
        .. totalEquipped .. "/" .. totalNeeded .. " (" .. pct .. "%)"
    )
    if pct >= 100 then progressLabel:SetColor(0, 1, 0, 1)
    elseif pct >= 50 then progressLabel:SetColor(1, 1, 0, 1)
    else progressLabel:SetColor(1, 0.5, 0, 1) end

    -- Sort: incomplete first
    table.sort(setOrder, function(a, b)
        local aC = sets[a].equipped >= sets[a].needed
        local bC = sets[b].equipped >= sets[b].needed
        if aC ~= bC then return not aC end
        return a < b
    end)

    -- Fill detail rows
    for i = 1, MAX_DETAIL_ROWS do
        local row = detailRows[i]
        if not row then break end
        if i <= #setOrder then
            local setName = setOrder[i]
            local info = sets[setName]
            row._nameLabel:SetText(setName)
            row._countLabel:SetText(info.equipped .. "/" .. info.needed)

            if info.equipped >= info.needed then
                row._nameLabel:SetColor(0, 1, 0, 1)
                row._countLabel:SetColor(0, 1, 0, 1)
            elseif info.equipped > 0 then
                row._nameLabel:SetColor(1, 1, 0, 1)
                row._countLabel:SetColor(1, 1, 0, 1)
            else
                row._nameLabel:SetColor(0.6, 0.6, 0.6, 1)
                row._countLabel:SetColor(0.6, 0.6, 0.6, 1)
            end

            local barWidth = row._barBg:GetWidth()
            local ratio = info.needed > 0 and (math.min(info.equipped, info.needed) / info.needed) or 0
            row._barFill:SetWidth(math.max(1, barWidth * ratio))
            if ratio >= 1 then row._barFill:SetCenterColor(0, 0.65, 0, 0.9)
            elseif ratio > 0 then row._barFill:SetCenterColor(0.65, 0.65, 0, 0.9)
            else row._barFill:SetCenterColor(0.25, 0, 0, 0.5) end

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
                    or "Select a build from the list"
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
