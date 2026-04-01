----------------------------------------------------------------------
-- SmartGear — Target Build Browser UI
-- Custom in-game window for browsing, selecting, and managing
-- target builds with progress tracking.
----------------------------------------------------------------------
SmartGear = SmartGear or {}

local BUILD_LIST_TYPE = 1
local SET_DETAIL_TYPE = 1

-- State
local browserWindow = nil
local leftList = nil
local rightList = nil
local selectedBuildId = nil
local isInitialized = false

----------------------------------------------------------------------
-- UI References
----------------------------------------------------------------------
local ui = {}

local function InitUI()
    browserWindow = SmartGearBuildBrowser
    if not browserWindow then return false end

    ui.closeBtn       = browserWindow:GetNamedChild("CloseBtn")
    ui.leftPanel      = browserWindow:GetNamedChild("LeftPanel")
    ui.rightPanel     = browserWindow:GetNamedChild("RightPanel")
    ui.buildName      = ui.rightPanel:GetNamedChild("BuildName")
    ui.roleCtx        = ui.rightPanel:GetNamedChild("RoleCtx")
    ui.progress       = ui.rightPanel:GetNamedChild("Progress")
    ui.activateBtn    = ui.rightPanel:GetNamedChild("ActivateBtn")
    ui.deactivateBtn  = ui.rightPanel:GetNamedChild("DeactivateBtn")
    ui.noBuildLabel   = browserWindow:GetNamedChild("NoBuildLabel")

    leftList  = ui.leftPanel:GetNamedChild("List")
    rightList = ui.rightPanel:GetNamedChild("SetList")

    -- Close button
    ui.closeBtn:SetHandler("OnClicked", function()
        SmartGear.ToggleBuildBrowser()
    end)

    -- Activate button
    ui.activateBtn:SetHandler("OnClicked", function()
        if selectedBuildId then
            SmartGear.ActivateBuild(selectedBuildId)
            SmartGear.RefreshBuildBrowser()
        end
    end)

    -- Deactivate button
    ui.deactivateBtn:SetHandler("OnClicked", function()
        SmartGear.ActivateBuild(nil)
        SmartGear.RefreshBuildBrowser()
    end)

    -- ESC to close
    browserWindow:SetHandler("OnKeyUp", function(_, key)
        if key == KEY_ESCAPE then
            SmartGear.ToggleBuildBrowser()
        end
    end)

    -- Setup scroll lists
    SetupBuildList()
    SetupSetDetailList()

    isInitialized = true
    return true
end

----------------------------------------------------------------------
-- Build List (Left Panel)
----------------------------------------------------------------------
function SetupBuildList()
    if not leftList then return end

    ZO_ScrollList_AddDataType(leftList, BUILD_LIST_TYPE, "SmartGearBuildListRow", 36,
        function(control, data)
            SetupBuildListRow(control, data)
        end
    )

    ZO_ScrollList_EnableHighlight(leftList, "ZO_ThinListHighlight")
end

function SetupBuildListRow(control, data)
    local lang = SmartGear.currentLang or "en"
    local build = data.build
    local nameLabel = control:GetNamedChild("Name")
    local sourceLabel = control:GetNamedChild("Source")
    local bg = control:GetNamedChild("BG")

    local name = lang == "ru" and (build.nameRu or build.name) or build.name
    nameLabel:SetText(name or data.id)

    -- Source indicator
    local srcText = build.source == "alcast" and "[P]" or "[U]"
    sourceLabel:SetText(srcText)

    -- Highlight active build
    local isActive = SmartGear.ActiveBuild and SmartGear.ActiveBuild.id == data.id
    local isSelected = selectedBuildId == data.id

    if isActive then
        nameLabel:SetColor(0, 1, 0, 1)  -- green
    elseif isSelected then
        nameLabel:SetColor(1, 1, 1, 1)  -- white
    else
        nameLabel:SetColor(0.8, 0.8, 0.8, 1)  -- light gray
    end

    -- Click handler
    control:SetMouseEnabled(true)
    control:SetHandler("OnMouseUp", function()
        selectedBuildId = data.id
        SmartGear.ShowBuildDetails(data.id)
        RefreshBuildListHighlights()
    end)

    -- Hover
    control:SetHandler("OnMouseEnter", function()
        if bg then
            bg:SetCenterColor(0.15, 0.15, 0.15, 0.6)
        end
    end)
    control:SetHandler("OnMouseExit", function()
        if bg then
            bg:SetCenterColor(0.1, 0.1, 0.1, 0.4)
        end
    end)
end

function RefreshBuildListHighlights()
    ZO_ScrollList_RefreshVisible(leftList)
end

----------------------------------------------------------------------
-- Set Detail List (Right Panel)
----------------------------------------------------------------------
function SetupSetDetailList()
    if not rightList then return end

    ZO_ScrollList_AddDataType(rightList, SET_DETAIL_TYPE, "SmartGearSetDetailRow", 28,
        function(control, data)
            SetupSetDetailRow(control, data)
        end
    )
end

function SetupSetDetailRow(control, data)
    local nameLabel = control:GetNamedChild("SetName")
    local countLabel = control:GetNamedChild("Count")
    local barBG = control:GetNamedChild("BarBG")
    local barFill = control:GetNamedChild("BarFill")

    nameLabel:SetText(data.setName or "?")
    countLabel:SetText(data.equipped .. "/" .. data.needed)

    -- Color based on completion
    if data.equipped >= data.needed then
        nameLabel:SetColor(0, 1, 0, 1)  -- green = complete
        countLabel:SetColor(0, 1, 0, 1)
    elseif data.equipped > 0 then
        nameLabel:SetColor(1, 1, 0, 1)  -- yellow = partial
        countLabel:SetColor(1, 1, 0, 1)
    else
        nameLabel:SetColor(0.7, 0.7, 0.7, 1)  -- gray = none
        countLabel:SetColor(0.7, 0.7, 0.7, 1)
    end

    -- Progress bar
    if barBG and barFill then
        local barWidth = barBG:GetWidth()
        local ratio = data.needed > 0 and (data.equipped / data.needed) or 0
        ratio = math.min(1, ratio)
        barFill:SetWidth(math.max(1, barWidth * ratio))

        if ratio >= 1 then
            barFill:SetCenterColor(0, 0.7, 0, 0.9)
        elseif ratio > 0 then
            barFill:SetCenterColor(0.7, 0.7, 0, 0.9)
        else
            barFill:SetCenterColor(0.3, 0, 0, 0.9)
        end
    end
end

----------------------------------------------------------------------
-- Populate build list
----------------------------------------------------------------------
function SmartGear.PopulateBuildList()
    if not leftList then return end

    local scrollData = ZO_ScrollList_GetDataList(leftList)
    ZO_ScrollList_Clear(leftList)

    -- Pre-built builds
    if SmartGear.PreBuilds then
        for id, build in pairs(SmartGear.PreBuilds) do
            local entry = ZO_ScrollList_CreateDataEntry(BUILD_LIST_TYPE, {
                id = id,
                build = build,
            })
            table.insert(scrollData, entry)
        end
    end

    -- Custom builds
    if SmartGear.savedVars and SmartGear.savedVars.customBuilds then
        for id, build in pairs(SmartGear.savedVars.customBuilds) do
            local entry = ZO_ScrollList_CreateDataEntry(BUILD_LIST_TYPE, {
                id = id,
                build = build,
            })
            table.insert(scrollData, entry)
        end
    end

    -- Sort by name
    local lang = SmartGear.currentLang or "en"
    table.sort(scrollData, function(a, b)
        local nameA = lang == "ru" and (a.data.build.nameRu or a.data.build.name) or a.data.build.name
        local nameB = lang == "ru" and (b.data.build.nameRu or b.data.build.name) or b.data.build.name
        return (nameA or "") < (nameB or "")
    end)

    ZO_ScrollList_Commit(leftList)
end

----------------------------------------------------------------------
-- Show build details in right panel
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
        ui.rightPanel:SetHidden(true)
        ui.noBuildLabel:SetHidden(false)
        return
    end

    ui.rightPanel:SetHidden(false)
    ui.noBuildLabel:SetHidden(true)

    local lang = SmartGear.currentLang or "en"
    local name = lang == "ru" and (build.nameRu or build.name) or build.name
    ui.buildName:SetText(name or buildId)

    -- Role + Context
    local roleName = SmartGear.GetRoleDisplayName and SmartGear.GetRoleDisplayName(build.role) or (build.role or "?")
    local ctxInfo = SmartGear.ContentContexts and SmartGear.ContentContexts[build.context]
    local ctxName = ctxInfo and (lang == "ru" and ctxInfo.nameRu or ctxInfo.name) or (build.context or "?")
    ui.roleCtx:SetText(roleName .. " | " .. ctxName)

    -- Compute progress
    local sets = {}
    if build.slots then
        for slot, spec in pairs(build.slots) do
            if spec and spec.set then
                if not sets[spec.set] then
                    sets[spec.set] = { needed = 0, equipped = 0 }
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
    ui.progress:SetText(
        (lang == "ru" and "Прогресс: " or "Progress: ")
        .. totalEquipped .. "/" .. totalNeeded
        .. " (" .. pct .. "%)"
    )

    if pct >= 100 then
        ui.progress:SetColor(0, 1, 0, 1)
    elseif pct >= 50 then
        ui.progress:SetColor(1, 1, 0, 1)
    else
        ui.progress:SetColor(1, 0.5, 0, 1)
    end

    -- Populate set detail list
    local scrollData = ZO_ScrollList_GetDataList(rightList)
    ZO_ScrollList_Clear(rightList)

    for setName, info in pairs(sets) do
        local entry = ZO_ScrollList_CreateDataEntry(SET_DETAIL_TYPE, {
            setName = setName,
            needed = info.needed,
            equipped = info.equipped,
        })
        table.insert(scrollData, entry)
    end

    -- Sort: incomplete first, then by name
    table.sort(scrollData, function(a, b)
        local aComplete = a.data.equipped >= a.data.needed
        local bComplete = b.data.equipped >= b.data.needed
        if aComplete ~= bComplete then return not aComplete end
        return a.data.setName < b.data.setName
    end)

    ZO_ScrollList_Commit(rightList)

    -- Show/hide activate/deactivate buttons
    local isActive = SmartGear.ActiveBuild and SmartGear.ActiveBuild.id == buildId
    ui.activateBtn:SetHidden(isActive)
    ui.deactivateBtn:SetHidden(not isActive)

    -- Localize buttons
    local actLabel = ui.activateBtn:GetNamedChild("Label")
    local deactLabel = ui.deactivateBtn:GetNamedChild("Label")
    if actLabel then
        actLabel:SetText(lang == "ru" and "АКТИВИРОВАТЬ" or "ACTIVATE")
    end
    if deactLabel then
        deactLabel:SetText(lang == "ru" and "ДЕАКТИВИРОВАТЬ" or "DEACTIVATE")
    end
end

----------------------------------------------------------------------
-- Toggle browser visibility
----------------------------------------------------------------------
function SmartGear.ToggleBuildBrowser()
    if not isInitialized then
        if not InitUI() then
            d("|c00FF00[SmartGear]|r Build browser UI not available.")
            return
        end
    end

    if browserWindow:IsHidden() then
        SmartGear.PopulateBuildList()
        browserWindow:SetHidden(false)

        -- Show details if a build is active
        if SmartGear.ActiveBuild and SmartGear.ActiveBuild.id then
            selectedBuildId = SmartGear.ActiveBuild.id
            SmartGear.ShowBuildDetails(selectedBuildId)
        else
            ui.rightPanel:SetHidden(true)
            ui.noBuildLabel:SetHidden(false)
            ui.noBuildLabel:SetText(
                SmartGear.currentLang == "ru"
                    and "Выберите сборку из списка"
                    or  "Select a build from the list"
            )
        end
    else
        browserWindow:SetHidden(true)
    end
end

----------------------------------------------------------------------
-- Refresh browser (after activate/deactivate)
----------------------------------------------------------------------
function SmartGear.RefreshBuildBrowser()
    if not isInitialized or not browserWindow or browserWindow:IsHidden() then return end
    SmartGear.PopulateBuildList()
    if selectedBuildId then
        SmartGear.ShowBuildDetails(selectedBuildId)
    end
end

----------------------------------------------------------------------
-- Initialize (called from SmartGear.lua)
----------------------------------------------------------------------
function SmartGear.InitBuildBrowser()
    -- Defer init until window is first opened
    -- Register scene fragment for auto-hide
    if SmartGearBuildBrowser then
        -- Hide when entering combat or opening other UI
        local fragment = ZO_HUDFadeSceneFragment:New(SmartGearBuildBrowser, 200, 200)
        HUD_SCENE:AddFragment(fragment)
        HUD_UI_SCENE:AddFragment(fragment)
    end
end
