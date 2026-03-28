----------------------------------------------------------------------
-- SmartGear -- Upgrade Alert System
-- Shows a notification when a better item is in your inventory
-- with a one-click EQUIP button.
----------------------------------------------------------------------
SmartGear = SmartGear or {}

local ALERT_DURATION = 12         -- seconds before auto-hide
local SCAN_DELAY = 1.5            -- seconds after inventory change
local MIN_SCORE_DIFF = 5          -- minimum score improvement to alert
local COMBAT_LOCKOUT = true       -- don't alert during combat

-- State
local alertQueue = {}             -- pending alerts
local isShowing = false
local currentAlert = nil          -- {bagId, slotIndex, wornSlot, itemLink, ...}
local scanPending = false
local hideTimerId = nil

----------------------------------------------------------------------
-- UI References (populated after XML loads)
----------------------------------------------------------------------
local frame, itemNameLabel, descLabel, scoreLabel, iconTexture
local equipBtn, dismissBtn

local function InitUI()
    frame         = SmartGearAlertFrame
    if not frame then return false end

    itemNameLabel = frame:GetNamedChild("ItemName")
    descLabel     = frame:GetNamedChild("Description")
    scoreLabel    = frame:GetNamedChild("Score")
    iconTexture   = frame:GetNamedChild("Icon")
    equipBtn      = frame:GetNamedChild("EquipBtn")
    dismissBtn    = frame:GetNamedChild("DismissBtn")

    if not equipBtn or not dismissBtn then return false end

    equipBtn:SetHandler("OnClicked", function()
        SmartGear.OnEquipClicked()
    end)

    dismissBtn:SetHandler("OnClicked", function()
        SmartGear.HideAlert()
    end)

    -- Tooltip on icon hover
    if iconTexture then
        iconTexture:SetHandler("OnMouseEnter", function()
            if currentAlert and currentAlert.itemLink then
                InitializeTooltip(ItemTooltip, iconTexture, RIGHT, -5)
                ItemTooltip:SetLink(currentAlert.itemLink)
            end
        end)
        iconTexture:SetHandler("OnMouseExit", function()
            ClearTooltip(ItemTooltip)
        end)
    end

    return true
end

----------------------------------------------------------------------
-- Show / Hide alert
----------------------------------------------------------------------
function SmartGear.ShowAlert(alertData)
    if not frame and not InitUI() then return end
    if not frame then return end

    currentAlert = alertData
    isShowing = true

    -- Set item info
    local lang = SmartGear.currentLang or "en"
    local itemName = GetItemLinkName(alertData.itemLink)
    itemName = zo_strformat("<<1>>", itemName)

    local quality = GetItemLinkQuality(alertData.itemLink)
    local qualityColor = GetItemQualityColor(quality)

    itemNameLabel:SetText(qualityColor:Colorize(itemName))

    -- Description: what it replaces
    local replaceText = ""
    if alertData.equippedName and alertData.equippedName ~= "" then
        replaceText = (lang == "ru" and "Замена: " or "Replaces: ") .. alertData.equippedName
    else
        replaceText = (lang == "ru" and "Пустой слот" or "Empty slot")
    end
    descLabel:SetText(replaceText)

    -- Score
    local diff = alertData.scoreDiff or 0
    local scoreText = ""
    if diff > 0 then
        scoreText = "|c00FF00^ +" .. diff .. " |r"
    end

    -- Add change details
    if alertData.changes then
        local details = {}
        for _, ch in ipairs(alertData.changes) do
            local txt = ""
            if ch.detail == "meta_vs_nonmeta" then
                txt = lang == "ru" and "Мета-сет!" or "Meta set!"
            elseif ch.detail == "higher_tier" then
                txt = lang == "ru" and "Выше тир" or "Higher tier"
            elseif ch.detail == "completes_set" then
                txt = lang == "ru" and "Замыкает сет!" or "Completes set!"
            elseif ch.detail == "better_trait" then
                txt = lang == "ru" and "Лучший трейт" or "Better trait"
            elseif ch.detail == "higher_level" then
                txt = lang == "ru" and "Выше уровень" or "Higher level"
            elseif ch.detail == "higher_quality" then
                txt = lang == "ru" and "Выше качество" or "Higher quality"
            end
            if txt ~= "" then
                table.insert(details, txt)
            end
        end
        if #details > 0 then
            scoreText = scoreText .. table.concat(details, ", ")
        end
    end
    scoreLabel:SetText(scoreText)

    -- Icon
    local icon = GetItemLinkIcon(alertData.itemLink)
    if icon and icon ~= "" then
        iconTexture:SetTexture(icon)
        iconTexture:SetHidden(false)
    else
        iconTexture:SetHidden(true)
    end

    -- Equip button text
    local btnLabel = equipBtn:GetNamedChild("Label")
    if btnLabel then
        btnLabel:SetText(lang == "ru" and "НАДЕТЬ" or "EQUIP")
    end

    -- Show
    frame:SetHidden(false)

    -- Auto-hide timer
    if hideTimerId then
        EVENT_MANAGER:UnregisterForUpdate(hideTimerId)
    end
    hideTimerId = SmartGear.name .. "AlertHide"
    EVENT_MANAGER:RegisterForUpdate(hideTimerId, ALERT_DURATION * 1000, function()
        SmartGear.HideAlert()
        EVENT_MANAGER:UnregisterForUpdate(hideTimerId)
    end)
end

function SmartGear.HideAlert()
    if frame then
        frame:SetHidden(true)
    end
    isShowing = false
    currentAlert = nil

    if hideTimerId then
        EVENT_MANAGER:UnregisterForUpdate(hideTimerId)
        hideTimerId = nil
    end

    -- Show next in queue
    if #alertQueue > 0 then
        local next = table.remove(alertQueue, 1)
        zo_callLater(function() SmartGear.ShowAlert(next) end, 500)
    end
end

----------------------------------------------------------------------
-- Equip button handler
----------------------------------------------------------------------
function SmartGear.OnEquipClicked()
    if not currentAlert then return end

    local bagId = currentAlert.bagId
    local slotIndex = currentAlert.slotIndex
    local wornSlot = currentAlert.wornSlot

    -- Verify item is still there
    local currentLink = GetItemLink(bagId, slotIndex)
    if currentLink ~= currentAlert.itemLink then
        local lang = SmartGear.currentLang or "en"
        d("|c00FF00[SmartGear]|r " .. (lang == "ru" and "Предмет перемещён или изменён." or "Item moved or changed, cannot equip."))
        SmartGear.HideAlert()
        return
    end

    -- Cannot equip in combat
    if IsUnitInCombat("player") then
        local lang = SmartGear.currentLang or "en"
        d("|c00FF00[SmartGear]|r " .. (lang == "ru" and "Нельзя надеть в бою!" or "Cannot equip during combat!"))
        return
    end

    -- Equip the item
    if wornSlot then
        EquipItem(bagId, slotIndex, wornSlot)
    else
        -- Let the game pick the slot
        EquipItem(bagId, slotIndex)
    end

    local lang = SmartGear.currentLang or "en"
    d("|c00FF00[SmartGear]|r " .. (lang == "ru" and "Надето: " or "Equipped: ") .. currentAlert.itemLink)
    SmartGear.HideAlert()
end

----------------------------------------------------------------------
-- Inventory scanner: find upgrades in bag
----------------------------------------------------------------------
local function ScanBagForUpgrades()
    if not SmartGear.savedVars or not SmartGear.savedVars.showAlerts then return end
    if COMBAT_LOCKOUT and IsUnitInCombat("player") then return end

    local bagId = BAG_BACKPACK
    local bagSlots = GetBagSize(bagId)
    local bestUpgrade = nil

    for slotIndex = 0, bagSlots - 1 do
        local itemLink = GetItemLink(bagId, slotIndex)
        if itemLink and itemLink ~= "" then
            local itemType = GetItemLinkItemType(itemLink)
            if itemType == ITEMTYPE_ARMOR or itemType == ITEMTYPE_WEAPON then
                local comp = SmartGear.CompareWithEquipped(bagId, slotIndex)
                if comp and comp.isUpgrade and comp.scoreDiff >= MIN_SCORE_DIFF then
                    -- Only keep upgrades, not for items on cooldown
                    if not bestUpgrade or comp.scoreDiff > bestUpgrade.scoreDiff then
                        bestUpgrade = {
                            bagId = bagId,
                            slotIndex = slotIndex,
                            wornSlot = comp.wornSlot,
                            itemLink = itemLink,
                            equippedName = comp.equippedName,
                            equippedLink = comp.equippedLink,
                            scoreDiff = comp.scoreDiff,
                            slotLabel = comp.slotLabel,
                            changes = comp.changes,
                            verdict = comp.verdict,
                        }
                    end
                end
            end
        end
    end

    if bestUpgrade then
        if isShowing then
            -- Queue it if already showing an alert
            table.insert(alertQueue, bestUpgrade)
        else
            SmartGear.ShowAlert(bestUpgrade)
        end
    end
end

----------------------------------------------------------------------
-- Trigger scan on inventory changes
----------------------------------------------------------------------
local function OnInventoryUpdate(_, bagId, slotIndex, isNewItem)
    if bagId ~= BAG_BACKPACK then return end
    if not SmartGear.savedVars or not SmartGear.savedVars.showAlerts then return end

    -- Debounce: don't scan every single slot update
    if not scanPending then
        scanPending = true
        zo_callLater(function()
            scanPending = false
            ScanBagForUpgrades()
        end, SCAN_DELAY * 1000)
    end
end

----------------------------------------------------------------------
-- Initialize
----------------------------------------------------------------------
function SmartGear.InitUpgradeAlerts()
    -- Register for new items in backpack
    EVENT_MANAGER:RegisterForEvent(
        SmartGear.name .. "UpgradeAlert",
        EVENT_INVENTORY_SINGLE_SLOT_UPDATE,
        OnInventoryUpdate
    )
    EVENT_MANAGER:AddFilterForEvent(
        SmartGear.name .. "UpgradeAlert",
        EVENT_INVENTORY_SINGLE_SLOT_UPDATE,
        REGISTER_FILTER_BAG_ID, BAG_BACKPACK
    )

    -- Also scan on loot received
    EVENT_MANAGER:RegisterForEvent(
        SmartGear.name .. "LootAlert",
        EVENT_LOOT_RECEIVED,
        function()
            if SmartGear.savedVars and SmartGear.savedVars.showAlerts then
                zo_callLater(ScanBagForUpgrades, 2000)
            end
        end
    )

    -- Scan once on load (after a short delay)
    zo_callLater(function()
        if SmartGear.savedVars and SmartGear.savedVars.showAlerts then
            ScanBagForUpgrades()
        end
    end, 5000)
end

----------------------------------------------------------------------
-- Manual scan command
----------------------------------------------------------------------
function SmartGear.ScanUpgrades()
    ScanBagForUpgrades()
    if not isShowing then
        local lang = SmartGear.currentLang or "en"
        d("|c00FF00[SmartGear]|r " .. (lang == "ru" and "Улучшений не найдено." or "No upgrades found."))
    end
end
