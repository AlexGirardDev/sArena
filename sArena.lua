sArenaMixin = {};
sArenaFrameMixin = {};

sArenaMixin.layouts = {};
sArenaMixin.portraitClassIcon = true;
sArenaMixin.portraitSpecIcon = true;

sArenaMixin.defaultSettings = {
    profile = {
        currentLayout = "BlizzArena",
        classColors = true,
        showNames = true,
        statusText = {
            usePercentage = false,
            alwaysShow = true,
        },
        drCategories = {
            Stun = true,
            Incapacitate = true,
            Disorient = true,
            Silence = true,
            Root = true,
        },
        layoutSettings = {},
    },
};

local db;
local auraList;
local interruptList;
local drList;
local drTime = 18.5;
local severityColor = {
    [1] = { 0, 1, 0, 1},
    [2] = { 1, 1, 0, 1},
    [3] = { 1, 0, 0, 1},
};
local drCategories = {
    "Stun",
    "Incapacitate",
    "Disorient",
    "Silence",
    "Root",
};
local classIcons = {
    ["DRUID"] = 625999,
    ["HUNTER"] = 626000,
    ["MAGE"] = 626001,
    ["MONK"] = 626002,
    ["PALADIN"] = 626003,
    ["PRIEST"] = 626004,
    ["ROGUE"] = 626005,
    ["SHAMAN"] = 626006,
    ["WARLOCK"] = 626007,
    ["WARRIOR"] = 626008,
    ["DEATHKNIGHT"] = 135771,
    ["DEMONHUNTER"] = 1260827,
};
local emptyLayoutOptionsTable = {
    notice = {
        name = "The selected layout doesn't appear to have any settings.",
        type = "description",
    },
};
local blizzFrame;
local FEIGN_DEATH = GetSpellInfo(5384); -- Localized name for Feign Death

-- make local vars of globals that are used with high frequency
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo;
local UnitGUID = UnitGUID;
local UnitChannelInfo = UnitChannelInfo;
local GetTime = GetTime;
local After = C_Timer.After;
local UnitAura = UnitAura;
local SetPortraitToTexture = SetPortraitToTexture; -- not called often, but had problems in the past
local UnitHealthMax = UnitHealthMax;
local UnitHealth = UnitHealth;
local UnitPowerMax = UnitPowerMax;
local UnitPower = UnitPower;
local UnitPowerType = UnitPowerType;
local UnitIsDeadOrGhost = UnitIsDeadOrGhost;
local FindAuraByName = AuraUtil.FindAuraByName;
local ceil = ceil;
local AbbreviateLargeNumbers = AbbreviateLargeNumbers;
local UnitFrameHealPredictionBars_Update = UnitFrameHealPredictionBars_Update;

local function UpdateBlizzVisibility(instanceType)
    -- if blizz arena frames are disabled or hidden, ARENA_CROWD_CONTROL_SPELL_UPDATE will not fire
    -- just move the frames off screen

    if ( InCombatLockdown() ) then return end

    if ( not blizzFrame ) then
        blizzFrame = CreateFrame("Frame", nil, UIParent);
        blizzFrame:SetSize(1, 1);
        blizzFrame:SetPoint("RIGHT", UIParent, "RIGHT", 500, 0);
        blizzFrame:Show();
    end

    for i = 1, 5 do
        local arenaFrame = _G["ArenaEnemyFrame"..i];
        local prepFrame = _G["ArenaPrepFrame"..i];

        arenaFrame:ClearAllPoints();
        prepFrame:ClearAllPoints();

        -- frames should be visible in battlegrounds
        if ( instanceType == "arena" ) then
            arenaFrame:SetParent(blizzFrame);
            arenaFrame:SetPoint("CENTER", blizzFrame, "CENTER");
            prepFrame:SetParent(blizzFrame);
            prepFrame:SetPoint("CENTER", blizzFrame, "CENTER");
        else
            arenaFrame:SetParent("ArenaEnemyFrames");
            prepFrame:SetParent("ArenaPrepFrames");

            if ( i == 1 ) then
                arenaFrame:SetPoint("TOP", arenaFrame:GetParent(), "TOP");
                prepFrame:SetPoint("TOP", prepFrame:GetParent(), "TOP");
            else
                arenaFrame:SetPoint("TOP", "ArenaEnemyFrame"..i-1, "BOTTOM", 0, -20);
                prepFrame:SetPoint("TOP", "ArenaPrepFrame"..i-1, "BOTTOM", 0, -20);
            end
        end
    end
end

-- Parent Frame

function sArenaMixin:OnLoad()
    auraList = self.auraList;
    interruptList = self.interruptList;
    drList = self.drList;

    self:RegisterEvent("PLAYER_LOGIN");
    self:RegisterEvent("PLAYER_ENTERING_WORLD");
end

function sArenaMixin:OnEvent(event)
    if ( event == "PLAYER_LOGIN" ) then
        self:Initialize();
        self:UnregisterEvent("PLAYER_LOGIN");
    elseif ( event == "PLAYER_ENTERING_WORLD" ) then
        local _, instanceType = IsInInstance();
        UpdateBlizzVisibility(instanceType);
        self:SetMouseState(true);

        if ( instanceType == "arena" ) then
            self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
        else
            self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
        end
    elseif ( event == "COMBAT_LOG_EVENT_UNFILTERED" ) then
        local _, combatEvent, _, _, _, _, _, destGUID, _, _, _, spellID, _, _, auraType = CombatLogGetCurrentEventInfo();

        for i = 1, 3 do
            if destGUID == UnitGUID("arena"..i) then
                self["arena"..i]:FindInterrupt(combatEvent, spellID);
                if ( auraType == "DEBUFF" ) then
                    self["arena"..i]:FindDR(combatEvent, spellID);
                end
                return;
            end
        end
    end
end

local function ChatCommand(input)
    if not input or input:trim() == "" then
        LibStub("AceConfigDialog-3.0"):Open("sArena");
    else
        LibStub("AceConfigCmd-3.0").HandleCommand("sArena", "sarena", "sArena", input);
    end
end

function sArenaMixin:Initialize()
    if ( db ) then return end

    self.db = LibStub("AceDB-3.0"):New("sArena3DB", self.defaultSettings, true)
    db = self.db;

    db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
    db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
    db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")
    self.optionsTable.handler = self;
    self.optionsTable.args.profile = LibStub("AceDBOptions-3.0"):GetOptionsTable(db)
    LibStub("AceConfig-3.0"):RegisterOptionsTable("sArena", self.optionsTable);
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("sArena");
    LibStub("AceConsole-3.0"):RegisterChatCommand("sarena", ChatCommand);

    self:SetLayout(nil, db.profile.currentLayout);

    SetCVar("showArenaEnemyFrames", 1);
end

function sArenaMixin:RefreshConfig()
    self:SetLayout(nil, db.profile.currentLayout);
end

function sArenaMixin:SetLayout(_, layout)
    if ( InCombatLockdown() ) then return end

    layout = sArenaMixin.layouts[layout] and layout or "BlizzArena";

    db.profile.currentLayout = layout;
    self.layoutdb = self.db.profile.layoutSettings[layout];

    for i = 1, 3 do
        local frame = self["arena"..i];
        frame:ResetLayout();
        self.layouts[layout]:Initialize(frame);
        frame:UpdatePlayer();
    end

    self.optionsTable.args.layoutSettingsGroup.args = self.layouts[layout].optionsTable and self.layouts[layout].optionsTable or emptyLayoutOptionsTable;
    LibStub("AceConfigRegistry-3.0"):NotifyChange("sArena");

    local _, instanceType = IsInInstance();
    if ( instanceType ~= "arena" and self.arena1:IsShown() ) then
        self:Test();
    end
end

function sArenaMixin:SetupDrag(frameToClick, frameToMove, settingsTable, updateMethod)
    frameToClick:HookScript("OnMouseDown", function()
        if ( InCombatLockdown() ) then return end

        if ( IsShiftKeyDown() and IsControlKeyDown() and not frameToMove.isMoving ) then
            frameToMove:StartMoving();
            frameToMove.isMoving = true;
        end
    end);

    frameToClick:HookScript("OnMouseUp", function()
        if ( InCombatLockdown() ) then return end

        if ( frameToMove.isMoving ) then
            frameToMove:StopMovingOrSizing();
            frameToMove.isMoving = false;

            local settings = db.profile.layoutSettings[db.profile.currentLayout];

            if ( settingsTable ) then
                settings = settings[settingsTable];
            end

            local parentX, parentY = frameToMove:GetParent():GetCenter();
            local frameX, frameY = frameToMove:GetCenter();
            local scale = frameToMove:GetScale();

            frameX = ((frameX * scale) - parentX) / scale;
            frameY = ((frameY * scale) - parentY) / scale;

            -- round to 1 decimal place
            frameX = floor(frameX * 10 + 0.5 ) / 10;
            frameY = floor(frameY * 10 + 0.5 ) / 10;

            settings.posX, settings.posY = frameX, frameY;
            self[updateMethod](self, settings);
            LibStub("AceConfigRegistry-3.0"):NotifyChange("sArena");
        end
    end);
end

function sArenaMixin:SetMouseState(state)
    for i = 1, 3 do
        local frame = self["arena"..i];
        frame.CastBar:EnableMouse(state);
        frame.Stun:EnableMouse(state);
        frame.SpecIcon:EnableMouse(state);
        frame.Trinket:EnableMouse(state);
    end
end

-- Arena Frames

local function ResetTexture(texturePool, t)
    if ( texturePool ) then
        t:SetParent(texturePool.parent);
    end

    t:SetTexture(nil);
    t:SetColorTexture(0, 0, 0, 0);
    t:SetVertexColor(1, 1, 1, 1);
    t:SetDesaturated();
    t:SetTexCoord(0, 1, 0, 1);
    t:ClearAllPoints();
    t:SetSize(0, 0);
    t:Hide();
end

function sArenaFrameMixin:OnLoad()
    local unit = "arena"..self:GetID();
    self.parent = self:GetParent();

    self:RegisterEvent("PLAYER_LOGIN");
    self:RegisterEvent("PLAYER_ENTERING_WORLD");
    self:RegisterEvent("UNIT_NAME_UPDATE");
    self:RegisterEvent("ARENA_PREP_OPPONENT_SPECIALIZATIONS");
    self:RegisterEvent("ARENA_OPPONENT_UPDATE");
    self:RegisterEvent("ARENA_COOLDOWNS_UPDATE");
    self:RegisterEvent("ARENA_CROWD_CONTROL_SPELL_UPDATE");
    self:RegisterUnitEvent("UNIT_HEALTH", unit);
    self:RegisterUnitEvent("UNIT_MAXHEALTH", unit);
    self:RegisterUnitEvent("UNIT_POWER_UPDATE", unit);
    self:RegisterUnitEvent("UNIT_MAXPOWER", unit);
    self:RegisterUnitEvent("UNIT_DISPLAYPOWER", unit);
    self:RegisterUnitEvent("UNIT_AURA", unit);
    self:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", unit);
    self:RegisterUnitEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", unit);

    self:RegisterForClicks("AnyUp");
    self:SetAttribute("*type1", "target");
    self:SetAttribute("*type2", "focus");
    self:SetAttribute("unit", unit);
    self.unit = unit;

    CastingBarFrame_SetUnit(self.CastBar, unit, false, true);

    self.healthbar = self.HealthBar;

    self.myHealPredictionBar:ClearAllPoints();
    self.otherHealPredictionBar:ClearAllPoints();
    self.totalAbsorbBar:ClearAllPoints();
    self.overAbsorbGlow:ClearAllPoints();
    self.healAbsorbBar:ClearAllPoints();
    self.overHealAbsorbGlow:ClearAllPoints();
    self.healAbsorbBarLeftShadow:ClearAllPoints();
    self.healAbsorbBarRightShadow:ClearAllPoints();

    self.totalAbsorbBar.overlay = self.totalAbsorbBarOverlay;
    self.totalAbsorbBarOverlay:SetAllPoints(self.totalAbsorbBar);
    self.totalAbsorbBarOverlay.tileSize = 32;

    self.overAbsorbGlow:SetPoint("TOPLEFT", self.healthbar, "TOPRIGHT", -7, 0);
    self.overAbsorbGlow:SetPoint("BOTTOMLEFT", self.healthbar, "BOTTOMRIGHT", -7, 0);

    self.healAbsorbBar:SetTexture("Interface\\RaidFrame\\Absorb-Fill", true, true);

    self.overHealAbsorbGlow:SetPoint("BOTTOMRIGHT", self.healthbar, "BOTTOMLEFT", 7, 0);
    self.overHealAbsorbGlow:SetPoint("TOPRIGHT", self.healthbar, "TOPLEFT", 7, 0);

    self.AuraText:SetPoint("CENTER", self.ClassIcon, "CENTER");

    self.TexturePool = CreateTexturePool(self, "ARTWORK", nil, nil, ResetTexture);
end

function sArenaFrameMixin:OnEvent(event, eventUnit, arg1)
    local unit = self.unit;

    if ( eventUnit and eventUnit == unit ) then
        if ( event == "UNIT_NAME_UPDATE" ) then
            self.Name:SetText(GetUnitName(unit));
        elseif ( event == "ARENA_OPPONENT_UPDATE" ) then
            -- arg1 == unitEvent ("seen", "unseen", etc)
            self:UpdateVisible();
            self:UpdatePlayer(arg1);
        elseif ( event == "ARENA_COOLDOWNS_UPDATE" ) then
            self:UpdateTrinket();
        elseif ( event == "ARENA_CROWD_CONTROL_SPELL_UPDATE" ) then
            -- arg1 == spellID
            if (arg1 ~= self.Trinket.spellID) then
                local _, spellTextureNoOverride = GetSpellTexture(arg1);
                self.Trinket.spellID = arg1;
                self.Trinket.Texture:SetTexture(spellTextureNoOverride);
            end
        elseif ( event == "UNIT_AURA" ) then
            self:FindAura();
        elseif ( event == "UNIT_HEALTH" ) then
            self:SetLifeState();
            self:SetStatusText();
            local currHp = UnitHealth(unit);
            if ( currHp ~= self.currHp ) then
                self.HealthBar:SetValue(currHp);
                UnitFrameHealPredictionBars_Update(self);
                self.currHp = currHp;
            end
        elseif ( event == "UNIT_MAXHEALTH" ) then
            self.HealthBar:SetMinMaxValues(0, UnitHealthMax(unit));
            self.HealthBar:SetValue(UnitHealth(unit));
            UnitFrameHealPredictionBars_Update(self);
        elseif ( event == "UNIT_POWER_UPDATE" ) then
            self:SetStatusText();
            self.PowerBar:SetValue(UnitPower(unit));
        elseif ( event == "UNIT_MAXPOWER" ) then
            self.PowerBar:SetMinMaxValues(0, UnitPowerMax(unit));
            self.PowerBar:SetValue(UnitPower(unit));
        elseif ( event == "UNIT_DISPLAYPOWER" ) then
            local _, powerType = UnitPowerType(unit);
            self:SetPowerType(powerType);
        elseif ( event == "UNIT_ABSORB_AMOUNT_CHANGED" ) then
            UnitFrameHealPredictionBars_Update(self);
        elseif ( event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" ) then
            UnitFrameHealPredictionBars_Update(self);
        end
    elseif ( event == "PLAYER_LOGIN" ) then
        self:UnregisterEvent("PLAYER_LOGIN");

        if ( not db ) then
            self.parent:Initialize();
        end

        self:Initialize();
    elseif ( event == "PLAYER_ENTERING_WORLD" ) then
        self.Name:SetText("");
        self.CastBar:Hide();
        self.specTexture = nil;
        self.class = nil;
        self.currentClassTexture = nil;
        self:UpdateVisible();
        self:UpdatePlayer();
        self:ResetTrinket();
        self:ResetDR();
        UnitFrameHealPredictionBars_Update(self);
    elseif ( event == "ARENA_PREP_OPPONENT_SPECIALIZATIONS" ) then
        self:UpdateVisible();
        self:UpdatePlayer();
    end
end

function sArenaFrameMixin:Initialize()
    self:SetMysteryPlayer();
    self.parent:SetupDrag(self, self.parent, nil, "UpdateFrameSettings");
    self.parent:SetupDrag(self.CastBar, self.CastBar, "castBar", "UpdateCastBarSettings");
    self.parent:SetupDrag(self.Stun, self.Stun, "dr", "UpdateDRSettings");
    self.parent:SetupDrag(self.SpecIcon, self.SpecIcon, "specIcon", "UpdateSpecIconSettings");
    self.parent:SetupDrag(self.Trinket, self.Trinket, "trinket", "UpdateTrinketSettings");
end

function sArenaFrameMixin:OnEnter()
    UnitFrame_OnEnter(self);

    self.HealthText:Show();
    self.PowerText:Show();
end

function sArenaFrameMixin:OnLeave()
    UnitFrame_OnLeave(self);

    self:UpdateStatusTextVisible();
end

function sArenaFrameMixin:OnUpdate()
    if ( self.currentAuraSpellID ) then
        local now = GetTime();
        local timeLeft = self.currentAuraExpirationTime - now;

        if ( timeLeft > 30 ) then
            self.AuraText:SetText("");
        elseif ( timeLeft >= 5 ) then
            self.AuraText:SetFormattedText("%i", timeLeft);
        elseif (timeLeft > 0 ) then
            self.AuraText:SetFormattedText("%.1f", timeLeft);
        end
    end
end

function sArenaFrameMixin:UpdateVisible()
    if ( InCombatLockdown() ) then return end

    local _, instanceType = IsInInstance();
    local id = self:GetID();
    if ( instanceType == "arena" and ( GetNumArenaOpponentSpecs() >= id or GetNumArenaOpponents() >= id ) ) then
        self:Show();
    else
        self:Hide();
    end
end

function sArenaFrameMixin:UpdatePlayer(unitEvent)
    local unit = self.unit;

    self:GetClassAndSpec();
    self:FindAura();

    if ( ( unitEvent and unitEvent ~= "seen" ) or not UnitExists(unit) ) then
            self:SetMysteryPlayer();
            return;
    end

    -- prevent castbar and other frames from intercepting mouse clicks during a match
    if ( unitEvent == "seen" ) then
        self.parent:SetMouseState(false);
    end

    self.hideStatusText = false;

    self.Name:SetText(GetUnitName(unit));
    self.Name:SetShown(db.profile.showNames);

    self:UpdateStatusTextVisible();
    self:SetStatusText();

    self:OnEvent("UNIT_MAXHEALTH", unit);
    self:OnEvent("UNIT_HEALTH", unit);
    self:OnEvent("UNIT_MAXPOWER", unit);
    self:OnEvent("UNIT_POWER_UPDATE", unit);
    self:OnEvent("UNIT_DISPLAYPOWER", unit);

    local color = RAID_CLASS_COLORS[select(2, UnitClass(unit))];

    if ( color and db.profile.classColors ) then
        self.HealthBar:SetStatusBarColor(color.r, color.g, color.b, 1.0);
    else
        self.HealthBar:SetStatusBarColor(0, 1.0, 0, 1.0);
    end
end

function sArenaFrameMixin:SetMysteryPlayer()
    local f = self.HealthBar;
    f:SetMinMaxValues(0,100);
    f:SetValue(100);
    f:SetStatusBarColor(0.5, 0.5, 0.5);

    f = self.PowerBar;
    f:SetMinMaxValues(0,100);
    f:SetValue(100);
    f:SetStatusBarColor(0.5, 0.5, 0.5);

    self.hideStatusText = true;
    self:SetStatusText();

    self.DeathIcon:Hide();
end

function sArenaFrameMixin:GetClassAndSpec()
    local _, instanceType = IsInInstance();

    if ( instanceType ~= "arena" ) then
        self.specTexture = nil;
        self.class = nil;
        self.SpecIcon:Hide();
    elseif ( not self.specTexture or not self.class ) then
        local id = self:GetID();
        if ( GetNumArenaOpponentSpecs() >= id ) then
            local specID = GetArenaOpponentSpec(id);
            if ( specID > 0 ) then
                self.SpecIcon:Show();
                self.specTexture = select(4, GetSpecializationInfoByID(specID));
                if ( self.parent.portraitSpecIcon ) then
                    SetPortraitToTexture(self.SpecIcon.Texture, self.specTexture);
                else
                    self.SpecIcon.Texture:SetTexture(self.specTexture);
                end

                self.class = select(6, GetSpecializationInfoByID(specID));
            end
        end

        if ( not self.class and UnitExists(self.unit) ) then
            _, self.class = UnitClass(self.unit);
        end
    end

    if ( not self.specTexture ) then
        self.SpecIcon:Hide();
    end
end

function sArenaFrameMixin:UpdateClassIcon()
    local texture = self.currentAuraSpellID and self.currentAuraTexture or self.class and "class" or 134400;

    if ( self.currentClassTexture == texture ) then return end

    self.currentClassTexture = texture;

    self.ClassIcon:SetTexCoord(0, 1, 0, 1);

    if ( self.parent.portraitClassIcon ) then
        if ( texture == "class" ) then
            self.ClassIcon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles");
            self.ClassIcon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[self.class]));
        else
            SetPortraitToTexture(self.ClassIcon, texture);
        end
    else
        if ( texture == "class" ) then
            texture = classIcons[self.class];
        end
        self.ClassIcon:SetTexture(texture);
    end
end

function sArenaFrameMixin:UpdateTrinket()
    local spellID, startTime, duration = C_PvP.GetArenaCrowdControlInfo(self.unit);
    if ( spellID ) then
        if ( spellID ~= self.Trinket.spellID ) then
            local _, spellTextureNoOverride = GetSpellTexture(spellID);
            self.Trinket.spellID = spellID;
            self.Trinket.Texture:SetTexture(spellTextureNoOverride);
        end
        if ( startTime ~= 0 and duration ~= 0 ) then
            self.Trinket.Cooldown:SetCooldown(startTime/1000.0, duration/1000.0);
        else
            self.Trinket.Cooldown:Clear();
        end
    end
end

function sArenaFrameMixin:ResetTrinket()
    self.Trinket.spellID = nil;
    self.Trinket.Texture:SetTexture(134400);
    self.Trinket.Cooldown:Clear();
    self:UpdateTrinket();
end

local function ResetStatusBar(f)
    f:SetStatusBarTexture(nil);
    f:ClearAllPoints();
    f:SetSize(0, 0);
    f:SetScale(1);
end

local function ResetFontString(f)
    f:SetDrawLayer("OVERLAY", 1);
    f:SetJustifyH("CENTER");
    f:SetJustifyV("MIDDLE");
    f:SetTextColor(1, 0.82, 0, 1);
    f:SetShadowColor(0, 0, 0, 1);
    f:SetShadowOffset(1, -1);
    f:ClearAllPoints();
    f:Hide();
end

function sArenaFrameMixin:ResetLayout()
    self.currentClassTexture = nil;

    ResetTexture(nil, self.ClassIcon);
    ResetStatusBar(self.HealthBar);
    ResetStatusBar(self.PowerBar);
    ResetStatusBar(self.CastBar);
    self.CastBar:SetHeight(16);

    local f = self.Trinket;
    f:ClearAllPoints();
    f:SetSize(0, 0);
    f.Texture:SetTexCoord(0, 1, 0, 1);

    f = self.SpecIcon;
    f:ClearAllPoints();
    f:SetSize(0, 0);
    f:SetScale(1);

    f = self.Name;
    ResetFontString(f);
    f:SetDrawLayer("ARTWORK", 2);
    f:SetFontObject("SystemFont_Shadow_Small2");

    f = self.AuraText;
    ResetFontString(f);
    f:SetFontObject("SystemFont_Shadow_Large_Outline");
    f:SetTextColor(1, 1, 1, 1);

    f = self.HealthText;
    ResetFontString(f);
    f:SetDrawLayer("ARTWORK", 2);
    f:SetFontObject("Game10Font_o1");
    f:SetTextColor(1, 1, 1, 1);

    f = self.PowerText;
    ResetFontString(f);
    f:SetDrawLayer("ARTWORK", 2);
    f:SetFontObject("Game10Font_o1");
    f:SetTextColor(1, 1, 1, 1);

    self.TexturePool:ReleaseAll();
end

function sArenaFrameMixin:SetPowerType(powerType)
    local color = PowerBarColor[powerType];
    if color then
        self.PowerBar:SetStatusBarColor(color.r, color.g, color.b);
    end
end

function sArenaFrameMixin:FindAura()
    local unit = self.unit;
    local currentSpellID, currentExpirationTime, currentTexture = nil, 0, nil;

    if ( self.currentInterruptSpellID ) then
        currentSpellID = self.currentInterruptSpellID;
        currentExpirationTime = self.currentInterruptExpirationTime;
        currentTexture = self.currentInterruptTexture;
    end

    for i = 1, 2 do
        local filter = (i == 1 and "HELPFUL" or "HARMFUL");

        for n = 1, 30 do
            local _, texture, _, _, _, expirationTime, _, _, _, spellID = UnitAura(unit, n, filter);

            if ( not spellID ) then break end

            if ( auraList[spellID] ) then
                if ( not currentSpellID or auraList[spellID] < auraList[currentSpellID] ) then
                    currentSpellID = spellID;
                    currentExpirationTime = expirationTime;
                    currentTexture = texture;
                end
            end
        end
    end

    if ( currentSpellID ) then
        self.currentAuraSpellID = currentSpellID;
        self.currentAuraExpirationTime = currentExpirationTime;
        self.currentAuraTexture = currentTexture;
    else
        self.currentAuraSpellID = nil;
        self.currentAuraExpirationTime = 0;
        self.currentAuraTexture = nil;
    end

    if ( self.currentAuraExpirationTime == 0 ) then
        self.AuraText:SetText("");
    end

    self:UpdateClassIcon();
end

function sArenaFrameMixin:FindInterrupt(event, spellID)
    local interruptDuration = interruptList[spellID];

    if ( not interruptDuration ) then return end
    if ( event ~= "SPELL_INTERRUPT" and event ~= "SPELL_CAST_SUCCESS" ) then return end

    local unit = self.unit;
    local _, _, _, _, _, _, notInterruptable = UnitChannelInfo(unit);

    if ( event == "SPELL_INTERRUPT" or notInterruptable == false ) then
        self.currentInterruptSpellID = spellID;
        self.currentInterruptExpirationTime = GetTime() + interruptDuration;
        self.currentInterruptTexture = GetSpellTexture(spellID);
        self:FindAura();
        After(interruptDuration, function()
            self.currentInterruptSpellID = nil;
            self.currentInterruptExpirationTime = 0;
            self.currentInterruptTexture = nil;
            self:FindAura();
        end);
    end
end

function sArenaFrameMixin:SetLifeState()
    local unit = self.unit;

    self.DeathIcon:SetShown(UnitIsDeadOrGhost(unit) and not FindAuraByName(FEIGN_DEATH, unit, "HELPFUL"));
    self.hideStatusText = self.DeathIcon:IsShown();
end

function sArenaFrameMixin:SetStatusText(unit)
    if ( self.hideStatusText ) then
        self.HealthText:SetText("");
        self.PowerText:SetText("");
        return;
    end

    if ( not unit ) then
        unit = self.unit;
    end

    local hp = UnitHealth(unit);
    local hpMax = UnitHealthMax(unit);
    local pp = UnitPower(unit);
    local ppMax = UnitPowerMax(unit);

    if ( db.profile.statusText.usePercentage ) then
        self.HealthText:SetText(ceil((hp / hpMax) * 100) .. "%");
        self.PowerText:SetText(ceil((pp / ppMax) * 100) .. "%");
    else
        self.HealthText:SetText(AbbreviateLargeNumbers(hp));
        self.PowerText:SetText(AbbreviateLargeNumbers(pp));
    end
end

function sArenaFrameMixin:UpdateStatusTextVisible()
    self.HealthText:SetShown(db.profile.statusText.alwaysShow);
    self.PowerText:SetShown(db.profile.statusText.alwaysShow);
end

function sArenaFrameMixin:FindDR(combatEvent, spellID)
    local category = drList[spellID];
    if ( not category ) then return end
    if ( not db.profile.drCategories[category] ) then return end

    local frame = self[category];
    local currTime = GetTime();

    if ( combatEvent == "SPELL_AURA_REMOVED" or combatEvent == "SPELL_AURA_BROKEN" ) then
        local startTime, startDuration = frame.Cooldown:GetCooldownTimes();
        startTime, startDuration = startTime/1000, startDuration/1000;

        local newDuration = drTime / (1 - ((currTime - startTime) / startDuration));
        local newStartTime = drTime + currTime - newDuration;

        frame:Show();
        frame.Cooldown:SetCooldown(newStartTime, newDuration);

        return;
    elseif ( combatEvent == "SPELL_AURA_APPLIED" or combatEvent == "SPELL_AURA_REFRESH" ) then
        local unit = self.unit;

        for i = 1, 30 do
            local _, _, _, _, duration, _, _, _, _, _spellID = UnitAura(unit, i, "HARMFUL");

            if ( not _spellID ) then break end

            if ( duration and spellID == _spellID ) then
                frame:Show();
                frame.Cooldown:SetCooldown(currTime, duration + drTime);
                break;
            end
        end
    end

    frame.Icon:SetTexture(GetSpellTexture(spellID));
    frame.Border:SetVertexColor(unpack(severityColor[frame.severity]));

    frame.severity = frame.severity + 1;
    if frame.severity > 3 then
        frame.severity = 3;
    end
end

function sArenaFrameMixin:UpdateDRPositions()
    local layoutdb = self.parent.layoutdb;
    local numActive = 0;
    local frame, prevFrame;
    local spacing = layoutdb.dr.spacing;
    local growthDirection = layoutdb.dr.growthDirection;

    for i = 1, #drCategories do
        frame = self[drCategories[i]];

        if ( frame:IsShown() ) then
            frame:ClearAllPoints();
            if ( numActive == 0 ) then
                frame:SetPoint("CENTER", self, "CENTER", layoutdb.dr.posX, layoutdb.dr.posY);
            else
                if ( growthDirection == 4 ) then frame:SetPoint("RIGHT", prevFrame, "LEFT", -spacing, 0);
                elseif ( growthDirection == 3 ) then frame:SetPoint("LEFT", prevFrame, "RIGHT", spacing, 0);
                elseif ( growthDirection == 1 ) then frame:SetPoint("TOP", prevFrame, "BOTTOM", 0, -spacing);
                elseif ( growthDirection == 2 ) then frame:SetPoint("BOTTOM", prevFrame, "TOP", 0, spacing);
                end
            end
            numActive = numActive + 1;
            prevFrame = frame;
        end
    end
end

function sArenaFrameMixin:ResetDR()
    for i = 1, #drCategories do
        self[drCategories[i]].Cooldown:SetCooldown(0, 0);
    end
end

function sArenaMixin:Test()
    if ( InCombatLockdown() ) then return end

    local currTime = GetTime();

    for i = 1,3 do
        local frame = self["arena"..i];
        frame:Show();

        if ( frame.parent.portraitClassIcon ) then
            SetPortraitToTexture(frame.ClassIcon, 626001);
        else
            frame.ClassIcon:SetTexture(626001);
        end

        frame.SpecIcon:Show();

        if ( frame.parent.portraitSpecIcon ) then
            SetPortraitToTexture(frame.SpecIcon.Texture, 135846);
        else
            frame.SpecIcon.Texture:SetTexture(135846);
        end

        frame.AuraText:SetText("5.3");
        frame.Name:SetText("arena"..i);
        frame.Name:SetShown(db.profile.showNames)

        frame.Trinket.Texture:SetTexture(1322720);
        frame.Trinket.Cooldown:SetCooldown(currTime, math.random(20, 60));

        for n = 1, #drCategories do
            local drFrame = frame[drCategories[n]];

            drFrame.Icon:SetTexture(136071);
            drFrame:Show();
            drFrame.Cooldown:SetCooldown(currTime, n == 1 and 60 or math.random(20, 50));

            if ( n == 1 ) then
                drFrame.Border:SetVertexColor(1, 0, 0, 1);
            else
                drFrame.Border:SetVertexColor(0, 1, 0, 1);
            end
        end

        frame.CastBar.fadeOut = nil;
        frame.CastBar:Show();
        frame.CastBar:SetAlpha(1);
        frame.CastBar.Icon:SetTexture(136071);
        frame.CastBar.Text:SetText("Polymorph");
        frame.CastBar:SetStatusBarColor(1, 0.7, 0, 1);

        frame.hideStatusText = false;
        frame:SetStatusText("player");
        frame:UpdateStatusTextVisible();
    end
end
