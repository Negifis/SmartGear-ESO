----------------------------------------------------------------------
-- SmartGear — Target Build Browser UI
-- Simple implementation using direct control creation.
----------------------------------------------------------------------
SmartGear = SmartGear or {}

local isInitialized = false
local selectedBuildId = nil
local buildRows = {}    -- left panel row controls
local detailRows = {}   -- right panel detail controls

-- UI refs
local browser, leftPanel, rightPanel, noBuildLabel
local buildNameLabel, roleCtxLabel, progressLabel
local activateBtn, deactivateBtn

local ROW_HEIGHT = 32
local DETAIL_ROW_HEIGHT = 26
local MAX_BUILD_ROWS = 12
local MAX_DETAIL_ROWS = 10

----------------------------------------------------------------------
-- Create a clickable row for the build list
----------------------------------------------------------------------
local function CreateBuildRow(parent, index)
    local row = WINDOW_MANAGER:CreateControl("SmartGearBuildRow" .. index, parent, CT_CONTROL)
    row:SetDimensions(210, ROW_HEIGHT)
    row:SetAnchor(TOPLEFT, parent, TOPLEFT, 0, (index - 1) * ROW_HEIGHT)
    row:SetMouseEnabled(true)

    -- Background
    local bg = WINDOW_MANAGER:CreateControl(nil, row, CT_BACKDROP)
    bg:SetAnchorFill(row)
    bg:SetCenterColor(0.1, 0.1, 0.1, 0.5)
    bg:SetEdgeColor(0.2, 0.2, 0.2, 0.3)
    bg:SetEdgeTexture("", 1, 1, 1)
    row._bg = bg

    -- Name label
    local name = WINDOW_MANAGER:CreateControl(nil, row, CT_LABEL)
    name:SetFont("ZoFontGame")
    name:SetColor(0.85, 0.85, 0.85, 1)
    name:SetAnchor(LEFT, row, LEFT, 6, 0)
    name:SetDimensions(175, ROW_HEIGHT)
    name:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    name:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    row._nameLabel = name

    -- Source tag
    local src = WINDOW_MANAGER:CreateControl(nil, row, CT_LABEL)
    src:SetFont("ZoFontGameSmall")
    src:SetColor(0.5, 0.5, 0.5, 1)
    src:SetAnchor(RIGHT, row, RIGHT, -4, 0)
    src:SetDimensions(30, ROW_HEIGHT)
    src:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
    src:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    row._srcLabel = src

    -- Hover handlers
    row:SetHandler("OnMouseEnter", function()
        bg:SetCenterColor(0.2, 0.25, 0.2, 0.7)
    end)
    row:SetHandler("OnMouseExit", function()
        bg:SetCenterColor(0.1, 0.1, 0.1, 0.5)
    end)

    row:SetHidden(true)
    return row
end

----------------------------------------------------------------------
-- Create a detail row for set progress
----------------------------------------------------------------------
local function CreateDetailRow(parent, index)
    local row = WINDOW_MANAGER:CreateControl("SmartGearDetailRow" .. index, parent, CT_CONTROL)
    row:SetDimensions(400, DETAIL_ROW_HEIGHT)
    row:SetAnchor(TOPLEFT, parent, TOPLEFT, 0, (index - 1) * DETAIL_ROW_HEIGHT)

    -- Set name
    local name = WINDOW_MANAGER:CreateControl(nil, row, CT_LABEL)
    name:SetFont("ZoFontGame")
    name:SetColor(0.85, 0.85, 0.85, 1)
    name:SetAnchor(LEFT, row, LEFT, 4, 0)
    name:SetDimensions(190, DETAIL_ROW_HEIGHT)
    name:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    name:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    row._nameLabel = name

    -- Count label
    local cnt = WINDOW_MANAGER:CreateControl(nil, row, CT_LABEL)
    cnt:SetFont("ZoFontGameBold")
    cnt:SetColor(0, 1, 0, 1)
    cnt:SetAnchor(LEFT, row, LEFT, 200, 0)
    cnt:SetDimensions(50, DETAIL_ROW_HEIGHT)
    cnt:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    cnt:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    row._countLabel = cnt

    -- Bar background
    local barBg = WINDOW_MANAGER:CreateControl(nil, row, CT_BACKDROP)
    barBg:SetDimensions(130, 10)
    barBg:SetAnchor(LEFT, row, LEFT, 260, 0)
    barBg:SetCenterColor(0.15, 0.15, 0.15, 0.8)
    barBg:SetEdgeColor(0.3, 0.3, 0.3, 0.5)
    barBg:SetEdgeTexture("", 1, 1, 1)
    row._barBg = barBg

    -- Bar fill
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
-- Initialize UI
----------------------------------------------------------------------
local function InitUI()
    browser = SmartGearBuildBrowser
    if not browser then return false end

    -- Close button
    local closeBtn = browser:GetNamedChild("CloseBtn")
    if closeBtn then
        closeBtn:SetHandler("OnClicked", function()
            SmartGear.ToggleBuildBrowser()
        end)
    end

    -- Panels
    leftPanel = browser:GetNamedChild("LeftPanel")
    rightPanel = browser:GetNamedChild("RightPanel")
    noBuildLabel = browser:GetNamedChild("NoBuildLabel")

    -- Right panel labels
    buildNameLabel = rightPanel:GetNamedChild("BuildName")
    roleCtxLabel   = rightPanel:GetNamedChild("RoleCtx")
    progressLabel  = rightPanel:GetNamedChild("Progress")
    activateBtn    = rightPanel:GetNamedChild("ActivateBtn")
    deactivateBtn  = rightPanel:GetNamedChild("DeactivateBtn")

    -- Activate/Deactivate handlers
    if activateBtn then
        activateBtn:SetHandler("OnClicked", function()
            if selectedBuildId then
                SmartGear.ActivateBuild(selectedBuildId)
                SmartGear.RefreshBuildBrowser()
            end
        end)
    end
    if deactivateBtn then
        deactivateBtn:SetHandler("OnClicked", function()
            SmartGear.ActivateBuild(nil)
            SmartGear.RefreshBuildBrowser()
        end)
    end

    -- Create build list rows (left panel)
    local listParent = leftPanel:GetNamedChild("List") or leftPanel
    for i = 1, MAX_BUILD_ROWS do
        buildRows[i] = CreateBuildRow(listParent, i)
    end

    -- Create detail rows (right panel)
    local detailParent = rightPanel:GetNamedChild("SetList") or rightPanel
    for i = 1, MAX_DETAIL_ROWS do
        detailRows[i] = CreateDetailRow(detailParent, i)
    end

    -- ESC to close
    browser:SetHandler("OnKeyUp", function(_, key)
        if key == KEY_ESCAPE then
            SmartGear.ToggleBuildBrowser()
        end
    end)

    isInitialized = true
    return true
end

----------------------------------------------------------------------
-- Populate build list (left panel)
----------------------------------------------------------------------
function SmartGear.PopulateBuildList()
    local lang = SmartGear.currentLang or "en"
    local builds = {}

    -- Collect all builds
    if SmartGear.PreBuilds then
        for id, build in pairs(SmartGear.PreBuilds) do
            table.insert(builds, { id = id, build = build, isPre = true })
        end
    end
    if SmartGear.savedVars and SmartGear.savedVars.customBuilds then
        for id, build in pairs(SmartGear.savedVars.customBuilds) do
            table.insert(builds, { id = id, build = build, isPre = false })
        end
    end

    -- Sort by name
    table.sort(builds, function(a, b)
        local na = lang == "ru" and (a.build.nameRu or a.build.name) or a.build.name
        local nb = lang == "ru" and (b.build.nameRu or b.build.name) or b.build.name
        return (na or "") < (nb or "")
    end)

    -- Fill rows
    for i = 1, MAX_BUILD_ROWS do
        local row = buildRows[i]
        if not row then break end

        if i <= #builds then
            local data = builds[i]
            local name = lang == "ru" and (data.build.nameRu or data.build.name) or data.build.name
            row._nameLabel:SetText(name or data.id)
            row._srcLabel:SetText(data.isPre and "[P]" or "[U]")

            -- Color: green if active
            local isActive = SmartGear.ActiveBuild and SmartGear.ActiveBuild.id == data.id
            if isActive then
                row._nameLabel:SetColor(0, 1, 0, 1)
            else
                row._nameLabel:SetColor(0.85, 0.85, 0.85, 1)
            end

            -- Click handler
            row._buildId = data.id
            row:SetHandler("OnMouseUp", function()
                selectedBuildId = data.id
                SmartGear.ShowBuildDetails(data.id)
                -- Refresh highlights
                SmartGear.PopulateBuildList()
            end)

            -- Highlight selected
            if selectedBuildId == data.id then
                row._bg:SetCenterColor(0.15, 0.2, 0.15, 0.7)
            else
                row._bg:SetCenterColor(0.1, 0.1, 0.1, 0.5)
            end

            row:SetHidden(false)
        else
            row:SetHidden(true)
        end
    end
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

    -- Build name
    local name = lang == "ru" and (build.nameRu or build.name) or build.name
    buildNameLabel:SetText(name or buildId)

    -- Role + Context
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

    -- Progress label
    local pct = totalNeeded > 0 and math.floor(totalEquipped / totalNeeded * 100) or 0
    progressLabel:SetText(
        (lang == "ru" and "Прогресс: " or "Progress: ")
        .. totalEquipped .. "/" .. totalNeeded .. " (" .. pct .. "%)"
    )
    if pct >= 100 then progressLabel:SetColor(0, 1, 0, 1)
    elseif pct >= 50 then progressLabel:SetColor(1, 1, 0, 1)
    else progressLabel:SetColor(1, 0.5, 0, 1) end

    -- Sort sets: incomplete first
    table.sort(setOrder, function(a, b)
        local aComplete = sets[a].equipped >= sets[a].needed
        local bComplete = sets[b].equipped >= sets[b].needed
        if aComplete ~= bComplete then return not aComplete end
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

            -- Color
            if info.equipped >= info.needed then
                row._nameLabel:SetColor(0, 1, 0, 1)
                row._countLabel:SetColor(0, 1, 0, 1)
            elseif info.equipped > 0 then
                row._nameLabel:SetColor(1, 1, 0, 1)
                row._countLabel:SetColor(1, 1, 0, 1)
            else
                row._nameLabel:SetColor(0.7, 0.7, 0.7, 1)
                row._countLabel:SetColor(0.7, 0.7, 0.7, 1)
            end

            -- Progress bar
            local barWidth = row._barBg:GetWidth()
            local ratio = info.needed > 0 and (math.min(info.equipped, info.needed) / info.needed) or 0
            row._barFill:SetWidth(math.max(1, barWidth * ratio))
            if ratio >= 1 then
                row._barFill:SetCenterColor(0, 0.7, 0, 0.9)
            elseif ratio > 0 then
                row._barFill:SetCenterColor(0.7, 0.7, 0, 0.9)
            else
                row._barFill:SetCenterColor(0.3, 0, 0, 0.5)
            end

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
    if actLabel then
        actLabel:SetText(lang == "ru" and "АКТИВИРОВАТЬ" or "ACTIVATE")
    end
    if deactLabel then
        deactLabel:SetText(lang == "ru" and "ДЕАКТИВИРОВАТЬ" or "DEACTIVATE")
    end
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
        SmartGear.PopulateBuildList()
        browser:SetHidden(false)

        -- Auto-select active build
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
    SmartGear.PopulateBuildList()
    if selectedBuildId then
        SmartGear.ShowBuildDetails(selectedBuildId)
    end
end

----------------------------------------------------------------------
-- Init (called from SmartGear.lua)
----------------------------------------------------------------------
function SmartGear.InitBuildBrowser()
    -- Deferred — actual init happens on first open
end
