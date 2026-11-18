-- =========================================================================
-- DoTimer Plates v1.4
-- Liste des mobs qui portent tes DoTs (prêtre Ombre ou démoniste), avec nom,
-- barre de vie et timers, y compris les DoTs propagés par talent (Peste
-- dévorante, Douleur) ou posés sans lancer direct.
-- Compagnon de DoTimer Forever : DoTimer n'est pas modifié.
--
-- Pourquoi un fonctionnement différent de DoTimer :
--   sur WoW Forever, en combat, un addon ne peut ni lire les auras des ennemis
--   (GetAuraDataByIndex refusé : "tainted") ni recevoir le journal de combat.
--   DoTimer ne voit donc que tes lancers, pas les DoTs propagés.
--
-- Principe (le même que ForeverAuras "Aura (Moderne)") :
--   le jeu fournit un cadre natif, "AuraContainer", qu'on règle une fois
--   ("affiche les debuffs posés par moi sur l'unité nameplateN, pour ces
--   sorts"). Ensuite c'est LE JEU qui crée, montre, cache, trie et met à jour
--   les icônes et leurs timers. Le Lua ne sait jamais si une aura est là.
--
-- Pour chaque barre de vie possible (nameplate1 .. nameplate40), un bloc :
--   1) un conteneur "en-tête" limité à UNE aura : 1 pixel quand le mob ne porte
--      aucun de tes DoTs, sinon la hauteur d'un en-tête. Le nom, les flèches de
--      cible, la marque de raid et la barre de vie sont dans NOTRE cadre, qui
--      découpe (clip) son contenu à la taille de ce conteneur : invisible à
--      1 pixel, visible sinon. (Posés sur le bouton natif, le jeu refusait de
--      les mettre à jour en combat.)
--   2) un conteneur "icônes" : une icône + timer par DoT, triés par temps
--      restant par le jeu.
-- Les blocs sont empilés par ancrage. Un conteneur vide mesure 1 pixel :
-- chaque élément reçoit 1 pixel de plus et chaque ancrage le retire, donc un
-- bloc vide ne prend aucune place (technique reprise de ForeverAuras).
-- Le jeu place les boutons natifs mais ne les dimensionne pas : on le fait.
--
-- Limites connues (le jeu, pas l'addon) : un mob sans barre de vie affichée
-- (trop loin, hors écran, retirée par le jeu en instance) sort de la liste ;
-- pas de barre de dégâts prévus (il faudrait connaître le temps restant en
-- Lua). L'alerte d'expiration fait clignoter le timer et le bord, pas l'icône.
--
-- Profils (v1.4) : « Commun » partagé, ou un profil propre à un personnage.
--
-- Commandes : /dtp (réglages), /dtp lock, /dtp status, /dtp debug
-- =========================================================================

local issecret = issecretvalue or function() return false end
local ADDON_VERSION = "1.4"

-- -------------------------------------------------------------------------
-- Sorts suivis par classe : tous les rangs (le cadre natif compare les ID
-- exacts). Les canalisations (Fouet mental, Drains, Wrack) sont exclues :
-- ce ne sont pas des DoTs.
-- -------------------------------------------------------------------------
local CLASS_SPELLS = {
    PRIEST = {
        589, 594, 970, 992, 2767, 10892, 10893, 10894,        -- Mot de l'ombre : Douleur r1-r8
        2944, 19276, 19277, 19278, 19279, 19280,              -- Peste dévorante r1-r6
        402668,                                               -- Toucher vampirique (rune)
        425204,                                               -- Peste du Vide (rune)
        9035, 19281, 19282, 19283, 19284, 19285,              -- Maléfice de faiblesse
        15286,                                                -- Étreinte vampirique
    },
    -- v1.4 : rangs repris de DoTimer Forever (Warlock.lua, relevés sur Forever)
    WARLOCK = {
        172, 6222, 6223, 7648, 11671, 11672, 25311,           -- Corruption r1-r7
        980, 1014, 6217, 11711, 11712, 11713,                 -- Plaie / Malédiction d'agonie r1-r6
        80240,                                                -- second fléau de DoTimer (à vérifier en jeu)
        348, 707, 1094, 2941, 11665, 11667, 11668, 25309,     -- Immolation r1-r8
        18265, 18879, 18880, 18881,                           -- Siphon de vie r1-r4
        1490, 440892, 1311676, 1311677, 1311680,              -- Malédiction des éléments (ID Forever)
        702, 1108, 6205, 7646, 11707, 11708,                  -- Malédiction de faiblesse r1-r6
        704, 7658, 7659, 11717,                               -- Malédiction de témérité r1-r4
        1714, 11719,                                          -- Malédiction des langages r1-r2
        18223,                                                -- Malédiction d'épuisement
    },
}
local SPELL_IDS        -- liste de la classe du personnage, choisie à la connexion
local FILTER = "HARMFUL|PLAYER"   -- debuffs posés par toi

-- -------------------------------------------------------------------------
-- Réglages : valeurs par défaut = celles de DoTimer. Au premier lancement,
-- l'apparence de DoTimer est recopiée (s'il est installé).
-- -------------------------------------------------------------------------
local DEFAULTS = {
    locked         = false,
    scale          = 1.0,
    width          = 140,     -- = "Longueur des barres" de DoTimer
    iconSize       = 28,
    iconSpacing    = 2,
    growUp         = false,
    showNames      = true,
    showHealth     = true,
    showHealthPct  = true,    -- v1.4 : % de vie à droite de la barre de vie
    showRaidMarks  = true,
    showSwipe      = true,
    tenthsBelow    = 60,      -- dixièmes sous N s : 0 = jamais, 60 = toujours
    warnEnabled    = true,    -- v1.1 : alerte avant expiration (timer qui clignote)
    warnTime       = 3,       -- s, comme le seuil de DoTimer
    blinkPeriod    = 1.2,     -- s par clignotement, comme DoTimer
    all            = false,   -- true : tous tes debuffs, pas seulement les DoTs
    nameColor     = { r = 1.00, g = 1.00, b = 1.00 },
    healthColor    = { r = 0.25, g = 0.85, b = 0.25 },
    timerTextColor = { r = 1.00, g = 1.00, b = 1.00 },
    warningColor   = { r = 1.00, g = 0.35, b = 0.20 },
    -- plateRange : absent tant que tu n'as pas touché au réglage de portée
}
local MAX_PLATES  = 40
local MAX_ICONS   = 8
local TITLE_X     = 18     -- comme DoTimer
local PCT_WIDTH   = 34     -- place du % de vie à droite de la barre
local BLOCK_GAP   = 4      -- espace entre deux blocs, comme DoTimer
local REFRESH     = 0.25   -- s : rafraîchissement des noms / flèches / vie
local RAID_ICON_TEXT = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%d:16:16|t"

-- v1.4 : profils. DoTimerPlatesDB = {
--   profiles = { ["Commun"] = {réglages}, ["Perso - Royaume"] = {réglages} },
--   chars    = { ["Perso - Royaume"] = nom du profil utilisé },
--   version, debug }
-- Un personnage sans profil choisi utilise "Commun".
local DEFAULT_PROFILE = "Commun"
local root                 -- = DoTimerPlatesDB
local db                   -- profil actif du personnage
local charKey              -- "Perso - Royaume"
local cfg = {}             -- réglages figés au chargement (géométrie)

local function CopyColor(c) return { r = c.r, g = c.g, b = c.b } end

local function DeepCopy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = type(v) == "table" and DeepCopy(v) or v end
    return out
end

local function ApplyDefaults()
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = type(v) == "table" and CopyColor(v) or v end
    end
end

-- Ouvre la base ; les réglages des versions 1.0-1.3 (un seul jeu pour le
-- compte) deviennent le profil "Commun"
local function InitProfiles()
    DoTimerPlatesDB = DoTimerPlatesDB or {}
    root = DoTimerPlatesDB
    if type(root.profiles) ~= "table" then
        local old = {}
        for k, v in pairs(root) do old[k] = v end
        for k in pairs(old) do root[k] = nil end
        root.version, root.debug = old.version, old.debug
        old.version, old.debug = nil, nil
        root.profiles = { [DEFAULT_PROFILE] = old }
    end
    if type(root.chars) ~= "table" then root.chars = {} end
    if type(root.profiles[DEFAULT_PROFILE]) ~= "table" then root.profiles[DEFAULT_PROFILE] = {} end
    charKey = (UnitName("player") or "?") .. " - " .. (GetRealmName() or "?")
end

local function CurrentProfile()
    local name = root.chars[charKey]
    if not (name and root.profiles[name]) then name = DEFAULT_PROFILE end
    return name
end

local function UseProfile(name)
    if not root.profiles[name] then name = DEFAULT_PROFILE end
    root.chars[charKey] = name
    db = root.profiles[name]
    ApplyDefaults()
end

-- "Commun" d'abord, puis les autres par ordre alphabétique
local function ProfileNames()
    local list = {}
    for name in pairs(root.profiles) do
        if name ~= DEFAULT_PROFILE then list[#list + 1] = name end
    end
    table.sort(list)
    table.insert(list, 1, DEFAULT_PROFILE)
    return list
end

-- Reprend l'apparence de DoTimer (profil actif) ; false s'il est absent
local function CopyFromDoTimer()
    local src = type(DoTimerForeverDB) == "table" and DoTimerForeverDB
    if not src then return false end
    local function num(v, lo, hi)
        if type(v) == "number" then return math.min(math.max(v, lo), hi) end
    end
    db.width       = num(src.barLength, 80, 300) or db.width
    db.iconSize    = num(src.iconSize, 14, 40) or db.iconSize
    db.iconSpacing = num(src.iconSpacing, 0, 10) or db.iconSpacing
    db.scale       = num(src.scale, 0.5, 2) or db.scale
    if src.growUp ~= nil then db.growUp = src.growUp == true end
    for _, k in ipairs({ "showNames", "showHealth", "showRaidMarks", "showSwipe" }) do
        if src[k] ~= nil then db[k] = src[k] ~= false end
    end
    if src.timerTenths == "never" then
        db.tenthsBelow = 0
    elseif src.timerTenths == "below" then
        db.tenthsBelow = num(src.tenthsBelow, 1, 59) or 5
    else
        db.tenthsBelow = 60
    end
    -- v1.1 : alerte avant expiration de DoTimer (seuil, rythme, couleur)
    if src.expiryWarning ~= nil then db.warnEnabled = src.expiryWarning ~= false end
    db.warnTime    = num(src.expiryThreshold, 1, 10) or db.warnTime
    db.blinkPeriod = num(src.blinkPeriod, 0.4, 3) or db.blinkPeriod
    for _, k in ipairs({ "nameColor", "healthColor", "timerTextColor", "warningColor" }) do
        local c = src[k]
        if type(c) == "table" and c.r and c.g and c.b then db[k] = CopyColor(c) end
    end
    return true
end

-- Géométrie d'un bloc, calculée une fois (comme UpdateConfig de DoTimer)
local function ComputeConfig()
    cfg.width       = db.width
    cfg.iconSize    = db.iconSize
    cfg.iconSpacing = db.iconSpacing
    cfg.growUp      = db.growUp
    cfg.showNames   = db.showNames
    cfg.showHealth  = db.showHealth
    cfg.showPct     = db.showHealthPct
    cfg.showSwipe   = db.showSwipe
    cfg.tenthsBelow = db.tenthsBelow
    cfg.warn        = db.warnEnabled and db.warnTime > 0
    cfg.warnTime    = db.warnTime
    cfg.blinkPeriod = db.blinkPeriod
    cfg.all         = db.all
    cfg.titleHeight = cfg.showNames and 15 or 0
    -- Avec le % : barre de 5 px, raccourcie de PCT_WIDTH, centrée sur une
    -- ligne de 10 px (hauteur du texte) ; sinon la fine ligne de 3 px de DoTimer
    cfg.barHeight   = cfg.showPct and 5 or 3
    cfg.barWidth    = cfg.showPct and cfg.width - PCT_WIDTH or cfg.width
    cfg.healthY     = -cfg.titleHeight - (cfg.showPct and 2 or 0)
    if cfg.showHealth or cfg.showPct then
        cfg.headerOffset = cfg.titleHeight + (cfg.showPct and 12 or cfg.barHeight + 3)
    elseif cfg.showNames then
        cfg.headerOffset = 16
    else
        cfg.headerOffset = 0
    end
    cfg.iconFontSize   = math.max(9, math.floor(cfg.iconSize * 0.38))
    cfg.iconCellHeight = cfg.iconSize + cfg.iconFontSize + 3
    local nc = db.nameColor
    cfg.nameHex = string.format("%02x%02x%02x", math.floor(nc.r * 255), math.floor(nc.g * 255), math.floor(nc.b * 255))
end

-- -------------------------------------------------------------------------
-- Diagnostic (/dtp status) : ce que le jeu refuse est compté et affiché une fois
-- -------------------------------------------------------------------------
local stats = { built = 0, headButtons = 0, iconButtons = 0, writeFails = 0, errors = {} }

local function Say(msg) print("|cff9482c9DoTimer|r Plates: " .. msg) end

local function Fail(what, err)
    if stats.errors[what] then return end
    stats.errors[what] = tostring(err)
    Say("|cffff4040ERREUR|r " .. what .. " : " .. tostring(err))
end

-- Appel protégé d'une méthode du jeu ; renvoie true si accepté
local function Try(what, obj, method, ...)
    local fn = obj and obj[method]
    if not fn then Fail(what, "fonction " .. method .. " absente") return false end
    local ok, err = pcall(fn, obj, ...)
    if not ok then Fail(what, err) end
    return ok
end

-- Écriture protégée dans nos propres éléments ; un refus est compté
local function Write(fn, ...)
    if not pcall(fn, ...) then stats.writeFails = stats.writeFails + 1 end
end

-- Cadre accroché à des tailles secrètes : modèle de ForeverAuras s'il existe
local function NewPlainFrame(parent)
    local ok, f = pcall(CreateFrame, "Frame", nil, parent, "DisableUntrustedLayoutScriptsTemplate")
    if ok and f then return f end
    return CreateFrame("Frame", nil, parent)
end

-- -------------------------------------------------------------------------
-- Ancre (déplaçable hors combat, clic droit = réglages), comme celle de DoTimer
-- -------------------------------------------------------------------------
local Main = CreateFrame("Frame", "DoTimerPlatesAnchor", UIParent)
Main:SetSize(DEFAULTS.width, 24)
Main:SetMovable(true)
Main:EnableMouse(true)
Main:RegisterForDrag("LeftButton")
Main.bg = Main:CreateTexture(nil, "BACKGROUND")
Main.bg:SetAllPoints()
Main.bg:SetColorTexture(0, 0, 0, 0.4)
Main.title = Main:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
Main.title:SetPoint("CENTER")
Main.title:SetText("|cff9482c9DoTimer|r Plates")

local ToggleOptions   -- défini plus bas (panneau de réglages)

local function UpdateAnchorVisual()
    local locked = db and db.locked
    Main.bg:SetShown(not locked)
    Main.title:SetShown(not locked)
    Main:EnableMouse(not locked)
end

local function PlaceAnchor()
    Main:ClearAllPoints()
    Main:SetPoint(db.point or "CENTER", UIParent, db.relPoint or "CENTER", db.x or 250, db.y or 0)
end

local scalePending = false
local function ApplyScale()
    if InCombatLockdown() then scalePending = true return end
    scalePending = false
    Main:SetScale(db.scale)
end

Main:SetScript("OnDragStart", function(self)
    if not InCombatLockdown() and not db.locked then self:StartMoving() end
end)
Main:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    db.point, db.relPoint, db.x, db.y = point, relPoint, x, y
end)
Main:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" and ToggleOptions then ToggleOptions() end
end)

-- -------------------------------------------------------------------------
-- Contenu des blocs
-- -------------------------------------------------------------------------
local rows = {}          -- index -> bloc
local rowByUnit = {}     -- "nameplate3" -> bloc

-- Texte du timer, mêmes règles que DoTimer : "1:47" dès une minute, dixièmes
-- ("9.3s") sous le seuil choisi, secondes entières arrondies au-dessus sinon.
-- Formateur natif : le jeu calcule le texte, le Lua ne voit jamais le temps.
local function TextOptions()
    if cfg.textOptions ~= nil then return cfg.textOptions or nil end
    cfg.textOptions = false
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then return nil end
    local R = Enum.NumericRuleFormatRounding
    local up, down = R and R.Up, R and R.Down
    local tb = cfg.tenthsBelow
    local base = {}
    if tb > 0 then
        base[#base + 1] = { threshold = 0.000001, format = "%.1fs" }
        if tb < 60 then base[#base + 1] = { threshold = tb, format = "%ds", step = 1, rounding = up } end
    else
        base[#base + 1] = { threshold = 0.000001, format = "%ds", step = 1, rounding = up }
    end
    base[#base + 1] = { threshold = 60, format = "%d:%02d", step = 1, rounding = down,
        components = { { div = 60 }, { mod = 60 } } }

    -- v1.1 : alerte avant expiration. Les dernières secondes sont découpées en
    -- demi-périodes de clignotement, en couleur d'alerte vive puis atténuée :
    -- le texte clignote, calculé par le jeu (même technique que ForeverAuras,
    -- DurationText.lua : un code couleur dans le format de chaque tranche).
    local points = {}
    for _, r in ipairs(base) do points[#points + 1] = r.threshold end
    local bright, dim
    if cfg.warn then
        local c = db.warningColor
        bright = string.format("|cff%02x%02x%02x", math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255))
        dim = string.format("|cff%02x%02x%02x", math.floor(c.r * 115), math.floor(c.g * 115), math.floor(c.b * 115))
        local half = cfg.blinkPeriod / 2
        local t = half
        while t < cfg.warnTime - 0.0001 do points[#points + 1] = t; t = t + half end
        points[#points + 1] = cfg.warnTime
    end
    table.sort(points)

    local rules = { { threshold = 0, format = "" } }
    local last
    for _, p in ipairs(points) do
        if p ~= last then
            last = p
            local src = base[1]   -- règle de base qui couvre p (seuil le plus haut <= p)
            for _, r in ipairs(base) do if r.threshold <= p then src = r end end
            local rule = { threshold = p, format = src.format, step = src.step,
                rounding = src.rounding, components = src.components }
            if cfg.warn and p < cfg.warnTime - 0.0001 then
                local slice = math.floor(p / (cfg.blinkPeriod / 2) + 0.0001)
                rule.format = (slice % 2 == 0 and bright or dim) .. rule.format .. "|r"
            end
            rules[#rules + 1] = rule
        end
    end
    local ok, formatter = pcall(function()
        local f = C_StringUtil.CreateNumericRuleFormatter()
        f:SetBreakpoints(rules)
        return f
    end)
    if ok and formatter then cfg.textOptions = { textFormatter = formatter } else Fail("formateur du timer", formatter) end
    return cfg.textOptions or nil
end

-- v1.2 : bord d'alerte qui clignote, comme le bord orange de DoTimer.
-- Le voile a son propre texte de compte à rebours (les "chiffres" du
-- cooldown), lui aussi réglé par un formateur natif selon le temps restant
-- (ForeverAuras : SecretAuraSingle.lua, HandOffCountdown). Au lieu de
-- chiffres, ce formateur écrit un carré de couleur (image dans le texte,
-- |T...|t) placé DERRIÈRE l'icône : on le voit comme un bord de 1 px autour
-- d'elle. Rien au-dessus du seuil ; sous le seuil, couleur vive puis
-- atténuée à chaque demi-période, en même temps que le timer.
local function BorderFormatter()
    if cfg.borderFormatter ~= nil then return cfg.borderFormatter or nil end
    cfg.borderFormatter = false
    if not (cfg.warn and C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then return nil end
    -- carré volontairement plus grand que la case : il est découpé à sa taille
    -- exacte (voir InitIcon), quelle que soit l'échelle appliquée par le jeu
    local c, s = db.warningColor, cfg.iconSize + 12
    local function Square(k)
        return string.format("|TInterface\\Buttons\\WHITE8X8:%d:%d:0:0:8:8:0:8:0:8:%d:%d:%d|t", s, s,
            math.floor(c.r * 255 * k), math.floor(c.g * 255 * k), math.floor(c.b * 255 * k))
    end
    local bright, dim = Square(1), Square(0.45)
    local half = cfg.blinkPeriod / 2
    local rules = { { threshold = 0, format = "" } }
    local t, slice = 0.000001, 0
    while t < cfg.warnTime - 0.0001 do
        rules[#rules + 1] = { threshold = t, format = slice % 2 == 0 and bright or dim }
        slice = slice + 1
        t = slice * half
    end
    rules[#rules + 1] = { threshold = cfg.warnTime, format = "" }
    local ok, formatter = pcall(function()
        local f = C_StringUtil.CreateNumericRuleFormatter()
        f:SetBreakpoints(rules)
        return f
    end)
    if ok and formatter then cfg.borderFormatter = formatter else Fail("formateur du bord d'alerte", formatter) end
    return cfg.borderFormatter or nil
end

-- % de vie : UnitHealthPercent si le jeu le fournit (une valeur secrète est
-- transmise telle quelle à l'affichage), sinon calcul direct si lisible
local SCALE_100 = CurveConstants and CurveConstants.ScaleTo100
local function SetPercent(row, unit)
    if UnitHealthPercent and SCALE_100 then
        row.pct:SetFormattedText("%.0f%%", UnitHealthPercent(unit, true, SCALE_100))
        return
    end
    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    if issecret(cur) or issecret(max) then error("vie secrète") end
    row.pct:SetFormattedText("%.0f%%", (max and max > 0) and cur / max * 100 or 0)
end

local function SetHealth(row)
    local unit = row.unit
    if cfg.showHealth then
        Write(function()
            row.health:SetMinMaxValues(0, UnitHealthMax(unit))
            row.health:SetValue(UnitHealth(unit))
        end)
    end
    if cfg.showPct and not pcall(SetPercent, row, unit) then
        stats.writeFails = stats.writeFails + 1
        pcall(row.pct.SetText, row.pct, "")
    end
end

-- Nom, niveau, flèches de cible, marque de raid et vie d'un bloc. Les valeurs
-- secrètes (instances) sont seulement transmises à l'affichage, jamais lues.
local function RefreshRow(row)
    local unit = row.unit
    if not UnitExists(unit) then return end
    if cfg.showNames then
        local okN, name = pcall(UnitName, unit)
        if not (okN and type(name) == "string") then name = "?" end
        local okL, lvl = pcall(UnitEffectiveLevel or UnitLevel, unit)
        local lvlText = (okL and not issecret(lvl) and lvl and lvl > 0) and tostring(lvl) or "??"
        local okT, isTarget = pcall(UnitIsUnit, unit, "target")
        local target = okT and not issecret(isTarget) and isTarget

        -- Marque de raid : le numéro est secret sur Forever, seul nil est testé
        local mark, hasMark = nil, false
        if db.showRaidMarks then
            local okM, m = pcall(GetRaidTargetIndex, unit)
            if okM then mark, hasMark = m, issecret(m) or m ~= nil end
        end

        Write(function()
            row.arrow:SetText(target and "|cffff2020>>|r" or "")
            row.tail:SetText(target and "|cffff2020<<|r" or "")
            row.raid:SetText(hasMark and string.format(RAID_ICON_TEXT, mark) or "")
            -- Le nom ne dépasse jamais la largeur du bloc (comme DoTimer)
            local room = cfg.width - TITLE_X - (target and 19 or 0) - (hasMark and 20 or 0)
            row.title:SetWidth(0)
            row.title:SetText(string.format("|cff%s[%s] %s|r", cfg.nameHex, lvlText, name))
            local natural = row.title:GetStringWidth()   -- secret pour un nom caché
            if issecret(natural) or (natural or 0) > room then row.title:SetWidth(math.max(room, 20)) end
        end)
    end
    if cfg.showHealth or cfg.showPct then SetHealth(row) end
end

-- En-tête : NOTRE cadre, découpé à la taille du conteneur d'en-tête
local function BuildHeader(row, index)
    local clip = NewPlainFrame(Main)
    clip:SetPoint("TOPLEFT", row.head, "TOPLEFT", 0, 0)
    clip:SetPoint("BOTTOMRIGHT", row.head, "BOTTOMRIGHT", 0, 0)
    clip:SetClipsChildren(true)

    local h = CreateFrame("Frame", nil, clip)
    h:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, -BLOCK_GAP)
    h:SetSize(cfg.width, math.max(cfg.headerOffset, 1))

    -- [>>] [niveau] nom [<<] [marque], comme DoTimer
    row.title = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.title:SetPoint("TOPLEFT", h, "TOPLEFT", TITLE_X, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row.arrow = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.arrow:SetPoint("RIGHT", row.title, "LEFT", -3, 0)
    row.tail = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.tail:SetPoint("LEFT", row.title, "RIGHT", 3, 0)
    row.raid = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.raid:SetPoint("LEFT", row.tail, "RIGHT", 4, 0)
    row.title:SetShown(cfg.showNames)
    row.arrow:SetShown(cfg.showNames)
    row.tail:SetShown(cfg.showNames)
    row.raid:SetShown(cfg.showNames)

    -- Barre de vie : fine ligne de 3 px, couleur et fond de DoTimer
    local c = db.healthColor
    row.health = CreateFrame("StatusBar", nil, h)
    row.health:SetPoint("TOPLEFT", h, "TOPLEFT", 0, cfg.healthY)
    row.health:SetSize(cfg.barWidth, cfg.barHeight)
    row.health:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    row.health:SetStatusBarColor(c.r, c.g, c.b)
    row.health:SetMinMaxValues(0, 1)
    row.health:SetValue(1)
    local bg = row.health:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
    row.health:SetShown(cfg.showHealth)

    -- v1.4 : % de vie à droite de la barre, aligné sur le bord du bloc.
    -- Rattaché à h : visible même sans barre.
    row.pct = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- Largeur libre : le texte prend sa taille réelle (« 100% » jamais coupé)
    row.pct:SetPoint("RIGHT", row.health, "RIGHT", PCT_WIDTH, 0)
    row.pct:SetJustifyH("RIGHT")
    row.pct:SetWordWrap(false)
    -- Police des chiffres de vie du cadre de joueur de Blizzard
    -- (TextStatusBarText : Arial Narrow, contour fin, sans ombre)
    local fo = TextStatusBarText or NumberFontNormalSmall
    if fo then pcall(row.pct.SetFontObject, row.pct, fo) end
    row.pct:SetShown(cfg.showPct)

    -- Mode debug : numéro du jeton de barre de vie
    row.token = h:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.token:SetPoint("TOPRIGHT", h, "TOPRIGHT", 0, 0)
    row.token:SetText("np" .. index)
    row.token:SetShown(root.debug == true)
end

-- Bouton d'en-tête créé par le jeu : seulement dimensionné, rien dessus.
-- Sa présence (1 aura au plus) donne la taille du conteneur d'en-tête.
local function InitHead(button)
    stats.headButtons = stats.headButtons + 1
    pcall(button.EnableMouse, button, false)
    Try("taille bouton en-tête", button, "SetSize", cfg.width, BLOCK_GAP + cfg.headerOffset + 1)
end

-- Bouton d'icône créé par le jeu : case comme DoTimer (icône rognée sur un
-- bord noir de 1 px, voile, timer dessous). Icône, voile et texte sont
-- remplis par le jeu.
local function InitIcon(button)
    stats.iconButtons = stats.iconButtons + 1
    pcall(button.EnableMouse, button, false)
    local size = cfg.iconSize
    Try("taille bouton icône", button, "SetSize", size, cfg.iconCellHeight + 1)

    local cell = CreateFrame("Frame", nil, button)
    cell:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    cell:SetSize(size, size)
    local border = cell:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0, 0, 0, 1)

    -- v1.3 : trois couches, de l'arrière vers l'avant :
    --   ring     : cadre découpé (clip) à la taille exacte de la case, qui
    --              reçoit le carré d'alerte : seule la bande d'1 px autour de
    --              l'icône reste visible = bord fin, comme DoTimer
    --   iconLayer: l'icône (rognée d'1 px) et le voile, au-dessus du carré
    local ring = CreateFrame("Frame", nil, cell)
    ring:SetAllPoints(cell)
    ring:SetClipsChildren(true)
    ring:SetFrameLevel(cell:GetFrameLevel() + 1)
    local ringHolder = CreateFrame("Frame", nil, ring)
    ringHolder:SetAllPoints(ring)
    local iconLayer = CreateFrame("Frame", nil, cell)
    iconLayer:SetAllPoints(cell)
    iconLayer:SetFrameLevel(cell:GetFrameLevel() + 3)

    local icon = iconLayer:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", cell, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -1, 1)
    Try("icône (SetIcon)", button, "SetIcon", icon)
    pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)

    -- Voile et/ou bord d'alerte : tous deux portés par le cooldown
    if cfg.showSwipe or cfg.warn then
        local ok, cd = pcall(CreateFrame, "Cooldown", nil, iconLayer, "CooldownFrameTemplate")
        if ok and cd then
            cd:SetAllPoints(icon)
            pcall(cd.SetReverse, cd, true)
            pcall(cd.SetDrawEdge, cd, false)
            pcall(cd.SetDrawBling, cd, false)
            pcall(cd.SetDrawSwipe, cd, cfg.showSwipe)
            pcall(cd.SetHideCountdownNumbers, cd, true)
            cd.noCooldownCount = true   -- pas de second timer d'OmniCC & co
            local border = cfg.warn and BorderFormatter()
            local numbers = border and cd.GetCountdownFontString and cd:GetCountdownFontString()
            if numbers then
                -- Les "chiffres" du cooldown passent dans la couche découpée,
                -- derrière l'icône : le carré, plus grand que la case, est
                -- coupé net à ses bords
                pcall(function()
                    numbers:SetParent(ringHolder)
                    numbers:SetDrawLayer("ARTWORK")
                    numbers:ClearAllPoints()
                    numbers:SetPoint("CENTER", cell, "CENTER", 0, 0)
                end)
                pcall(cd.SetHideCountdownNumbers, cd, false)
                pcall(cd.SetUseAuraDisplayTime, cd, true)
                pcall(cd.SetMinimumCountdownDuration, cd, 0)
                Try("bord d'alerte (SetCountdownFormatter)", cd, "SetCountdownFormatter", border)
            end
            Try("voile (SetDurationCooldown)", button, "SetDurationCooldown", cd)
        end
    end

    -- v1.3 : créé depuis le modèle du jeu, comme DoTimer : il garde l'ombre
    -- portée du modèle en plus du contour, d'où un texte plus contrasté
    local text = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local font = GameFontHighlightSmall:GetFont()
    text:SetFont(font, cfg.iconFontSize, "OUTLINE")
    local tc = db.timerTextColor
    text:SetTextColor(tc.r, tc.g, tc.b)
    text:SetPoint("TOP", cell, "BOTTOM", 0, -2)
    local opts = TextOptions()
    if not (opts and pcall(button.SetDurationText, button, text, opts)) then
        Try("timer (SetDurationText)", button, "SetDurationText", text)
    end
end

-- -------------------------------------------------------------------------
-- Construction des 40 blocs (hors combat, une seule fois)
-- -------------------------------------------------------------------------
local function Candidates()
    if cfg.all then return {} end
    local ids = {}
    for _, id in ipairs(SPELL_IDS) do ids[id] = true end
    return { includeSpellIDs = ids }
end

-- Fonds colorés du mode debug (bleu = en-tête, rouge = icônes)
local debugTextures = {}
local function DebugBackground(c, r, g, b)
    local t = c:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(r, g, b, 0.45)
    t:SetShown(root.debug == true)
    debugTextures[#debugTextures + 1] = t
end

local function NewContainer(r, g, b)
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, Main,
        "CustomAuraContainerTemplate, DisableUntrustedLayoutScriptsTemplate")
    if not (ok and c) then
        ok, c = pcall(CreateFrame, "AuraContainer", nil, Main, "CustomAuraContainerTemplate")
    end
    if not (ok and c) then Fail("création du conteneur natif", c) return end
    DebugBackground(c, r, g, b)
    return c
end

-- Règle un conteneur : unité, filtre, une file horizontale d'éléments w x h
local function Setup(c, unit, group, maxCount, w, h, spacing, init, sorted)
    if not Try("politique d'aura", c, "SetAuraProcessingPolicy", CustomAuraContainerAuraProcessingPolicy.None) then return false end
    Try("axe", c, "SetFlowLayoutAxis", AnchorUtil.FlowLayoutAxis.Horizontal)
    Try("coin", c, "SetFlowLayoutAnchorPoint", "TOPLEFT")
    Try("direction", c, "SetFlowLayoutGrowthDirection", AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
    if not Try("groupe " .. group, c, "AddAuraGroup", group, FILTER, {
        maxFrameCount = maxCount, candidateFilters = Candidates(), initializeFrame = init,
    }) then return false end
    Try("mise en page " .. group, c, "SetAuraGroupLayout", group, { elementWidth = w, elementHeight = h, elementSpacing = spacing })
    -- Icônes triées par le jeu : la prochaine à expirer d'abord (comme DoTimer)
    if sorted and AuraContainerSortMethod and AuraContainerSortDirection then
        Try("tri par temps restant", c, "SetAuraGroupSortMethod", group,
            AuraContainerSortMethod.ExpirationOnly, AuraContainerSortDirection.Normal)
    end
    Try("unité", c, "SetUnit", unit)
    Try("activation", c, "SetEnabled", true)
    Try("lecture initiale", c, "UpdateAllAuras")
    return true
end

local built = false
local function Build()
    if built then return end
    if InCombatLockdown() then return end   -- refait à la fin du combat
    built = true
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        local ok, reason = C_AddOns.LoadAddOn("Blizzard_AuraContainer")
        if not ok then Fail("chargement de Blizzard_AuraContainer", reason) return end
    end
    Main:SetWidth(cfg.width)

    local headH = BLOCK_GAP + cfg.headerOffset + 1      -- +1 : pixel du conteneur vide
    local iconH = cfg.iconCellHeight + 1
    local prev, first = Main, true
    for i = 1, MAX_PLATES do
        local row = { unit = "nameplate" .. i }
        row.head = NewContainer(0, 0.4, 1)
        row.icons = NewContainer(1, 0, 0)
        if not (row.head and row.icons) then return end

        -- Chaîne d'ancrages ; chaque ancrage retire le pixel du conteneur précédent
        if cfg.growUp then
            -- vers le haut : icônes posées sur le bloc précédent, en-tête au-dessus
            row.icons:SetPoint("BOTTOMLEFT", prev, "TOPLEFT", 0, first and BLOCK_GAP or -1)
            row.head:SetPoint("BOTTOMLEFT", row.icons, "TOPLEFT", 0, -1)
            prev = row.head
        else
            row.head:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, first and 0 or 1)
            row.icons:SetPoint("TOPLEFT", row.head, "BOTTOMLEFT", 0, 1)
            prev = row.icons
        end
        first = false

        local okH = Setup(row.head, row.unit, "Head", 1, cfg.width, headH, 0, InitHead)
        local okI = Setup(row.icons, row.unit, "Auras", MAX_ICONS, cfg.iconSize, iconH, cfg.iconSpacing, InitIcon, true)
        if not (okH and okI) then return end
        BuildHeader(row, i)

        rows[i] = row
        rowByUnit[row.unit] = row
        stats.built = i
    end
end

-- -------------------------------------------------------------------------
-- v1.1 : portée des barres de vie du jeu (variable "nameplateMaxDistance").
-- Plus la portée est grande, plus longtemps un mob DoTé reste dans la liste.
-- Le jeu refuse ce changement en combat : il est alors fait à la fin du combat.
-- Tant que le réglage n'a jamais été touché (db.plateRange absent), l'addon
-- ne modifie rien.
-- -------------------------------------------------------------------------
local RANGE_CVAR = "nameplateMaxDistance"
local rangePending = false

local function GetPlateRange()
    local get = (C_CVar and C_CVar.GetCVar) or GetCVar
    local ok, v = pcall(get, RANGE_CVAR)
    return ok and tonumber(v) or nil
end

local function ApplyPlateRange(verbose)
    if not db.plateRange then return end
    if InCombatLockdown() then rangePending = true return end
    rangePending = false
    local set = (C_CVar and C_CVar.SetCVar) or SetCVar
    pcall(set, RANGE_CVAR, tostring(db.plateRange))
    local now = GetPlateRange()
    if verbose then
        if now and math.abs(now - db.plateRange) > 0.5 then
            Say(string.format("portée des barres de vie : le jeu a gardé %d m (demandé %d m, sans doute son maximum).", now, db.plateRange))
        else
            Say(string.format("portée des barres de vie : %d m.", now or db.plateRange))
        end
    end
end

-- -------------------------------------------------------------------------
-- Panneau de réglages (/dtp ou clic droit sur l'ancre)
-- -------------------------------------------------------------------------
local Options
local refreshers, loading, reloadPending = {}, false, false
local reloadButton

local function MarkReload()
    reloadPending = true
    if reloadButton then reloadButton:Enable() end
end

local function AddCheck(parent, label, x, y, key, needsReload, onChange)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    cb.label:SetText(label .. (needsReload and " |cff888888*|r" or ""))
    cb:SetScript("OnClick", function(self)
        db[key] = self:GetChecked() and true or false
        if needsReload then MarkReload() end
        if onChange then onChange() end
    end)
    refreshers[#refreshers + 1] = function() cb:SetChecked(db[key] == true) end
end

local function AddSlider(parent, label, lo, hi, step, x, y, key, needsReload, fmt, onChange, fallback)
    local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    s:SetWidth(150)
    s:SetMinMaxValues(lo, hi)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s.Low:SetText(fmt(lo))
    s.High:SetText(fmt(hi))
    local function Label(v) s.Text:SetText(label .. (needsReload and " |cff888888*|r" or "") .. " : " .. fmt(v)) end
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / step + 0.5) * step
        Label(v)
        if loading or db[key] == v then return end
        db[key] = v
        if needsReload then MarkReload() end
        if onChange then onChange() end
    end)
    refreshers[#refreshers + 1] = function()
        local v = db[key]
        if v == nil and fallback then v = fallback() end   -- valeur actuelle du jeu
        v = math.min(math.max(v or lo, lo), hi)
        s:SetValue(v)
        Label(v)
    end
end

local function BuildOptions()
    Options = CreateFrame("Frame", "DoTimerPlatesOptions", UIParent, "BackdropTemplate")
    Options:SetSize(400, 670)
    Options:SetPoint("CENTER")
    Options:SetFrameStrata("DIALOG")
    Options:SetMovable(true)
    Options:EnableMouse(true)
    Options:RegisterForDrag("LeftButton")
    Options:SetScript("OnDragStart", Options.StartMoving)
    Options:SetScript("OnDragStop", Options.StopMovingOrSizing)
    Options:Hide()
    table.insert(UISpecialFrames, "DoTimerPlatesOptions")   -- Échap ferme la fenêtre
    Options:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    local shade = Options:CreateTexture(nil, "BACKGROUND", nil, 7)
    shade:SetPoint("TOPLEFT", 8, -8)
    shade:SetPoint("BOTTOMRIGHT", -8, 8)
    shade:SetColorTexture(0, 0, 0, 0.45)

    local title = Options:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("|cff9482c9DoTimer|r Plates |cff888888v" .. ADDON_VERSION .. "|r")

    -- Colonne gauche : affichage
    AddCheck(Options, "Verrouiller", 20, -50, "locked", false, UpdateAnchorVisual)
    AddCheck(Options, "Empiler vers le haut", 20, -76, "growUp", true)
    AddCheck(Options, "Afficher les noms", 20, -102, "showNames", true)
    AddCheck(Options, "Barre de vie", 20, -128, "showHealth", true)
    AddCheck(Options, "Marques de raid", 20, -154, "showRaidMarks", false, function()
        for _, row in ipairs(rows) do RefreshRow(row) end
    end)
    AddCheck(Options, "Voile sur les icônes", 20, -180, "showSwipe", true)
    AddCheck(Options, "Tous mes debuffs", 20, -206, "all", true)
    AddCheck(Options, "Alerte avant expiration", 20, -232, "warnEnabled", true)   -- v1.1
    AddCheck(Options, "% de vie", 20, -258, "showHealthPct", true)                -- v1.4

    -- Colonne droite : tailles
    local function plain(v) return tostring(v) end
    AddSlider(Options, "Échelle", 0.5, 2, 0.05, 220, -60, "scale", false,
        function(v) return string.format("%.2f", v) end, ApplyScale)
    AddSlider(Options, "Largeur", 80, 300, 5, 220, -110, "width", true, plain)
    AddSlider(Options, "Taille des icônes", 14, 40, 1, 220, -160, "iconSize", true, plain)
    AddSlider(Options, "Espacement", 0, 10, 1, 220, -210, "iconSpacing", true, plain)
    AddSlider(Options, "Dixièmes sous", 0, 60, 1, 220, -260, "tenthsBelow", true, function(v)
        if v <= 0 then return "jamais" elseif v >= 60 then return "toujours" end
        return v .. " s"
    end)
    -- v1.1 : seuil de l'alerte (timer qui clignote) et portée des barres de vie
    AddSlider(Options, "Seuil d'alerte", 1, 10, 1, 220, -310, "warnTime", true, function(v) return v .. " s" end)
    AddSlider(Options, "Portée barres de vie", 10, 60, 1, 220, -360, "plateRange", false,
        function(v) return v .. " m" end, function()
            -- appliqué une fois le curseur relâché (pas un message par cran)
            local token = (Options.rangeToken or 0) + 1
            Options.rangeToken = token
            C_Timer.After(0.6, function() if Options.rangeToken == token then ApplyPlateRange(true) end end)
        end, GetPlateRange)

    local function RefreshAll()
        loading = true
        for _, fn in ipairs(refreshers) do fn() end
        loading = false
    end

    -- v1.4 : profils. "<" et ">" choisissent le profil de ce personnage parmi
    -- ceux qui existent ; plusieurs persos peuvent partager le même profil.
    local function Button(label, w, h)
        local b = CreateFrame("Button", nil, Options, "UIPanelButtonTemplate")
        b:SetSize(w, h)
        b:SetText(label)
        return b
    end

    local ph = Options:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ph:SetPoint("TOPLEFT", 20, -400)
    ph:SetText("Profil de ce personnage")

    local prevP = Button("<", 28, 22)
    prevP:SetPoint("TOPLEFT", 20, -420)
    local pname = Options:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pname:SetPoint("LEFT", prevP, "RIGHT", 4, 0)
    pname:SetWidth(164)
    pname:SetWordWrap(false)
    local nextP = Button(">", 28, 22)
    nextP:SetPoint("LEFT", pname, "RIGHT", 4, 0)
    local delP = Button("Supprimer", 112, 22)
    delP:SetPoint("TOPRIGHT", -20, -420)
    local ownP = Button("Profil propre à ce perso", 228, 22)
    ownP:SetPoint("TOPLEFT", 20, -448)

    local function RefreshProfileUI()
        local cur = CurrentProfile()
        pname:SetText(cur == charKey and (cur .. " |cff888888(perso)|r") or cur)
        local several = #ProfileNames() > 1
        prevP:SetEnabled(several)
        nextP:SetEnabled(several)
        delP:SetText("Supprimer")
        delP.confirm = nil
        delP:SetEnabled(cur ~= DEFAULT_PROFILE)
        ownP:SetEnabled(not root.profiles[charKey])
    end
    refreshers[#refreshers + 1] = RefreshProfileUI

    -- sameSettings : le nouveau profil est une copie de l'actuel, pas de rechargement
    local function SwitchProfile(name, sameSettings)
        if InCombatLockdown() then Say("changement de profil impossible en combat.") return false end
        UseProfile(name)
        PlaceAnchor()
        UpdateAnchorVisual()
        ApplyScale()
        ApplyPlateRange(false)
        RefreshAll()
        if not sameSettings then MarkReload() end
        return true
    end

    local function Step(dir)
        local list, cur = ProfileNames(), CurrentProfile()
        local i = 1
        for k, name in ipairs(list) do if name == cur then i = k end end
        i = (i - 1 + dir) % #list + 1
        if SwitchProfile(list[i]) then Say("profil « " .. list[i] .. " ».") end
    end
    prevP:SetScript("OnClick", function() Step(-1) end)
    nextP:SetScript("OnClick", function() Step(1) end)

    -- Copie du profil actuel, réservée à ce personnage
    ownP:SetScript("OnClick", function()
        if root.profiles[charKey] then return end
        if InCombatLockdown() then Say("changement de profil impossible en combat.") return end
        root.profiles[charKey] = DeepCopy(db)
        if SwitchProfile(charKey, true) then
            Say("profil propre à " .. charKey .. " créé (copie du profil précédent).")
        end
    end)

    -- Suppression en deux clics ; les persos qui l'utilisaient reviennent à "Commun"
    delP:SetScript("OnClick", function(self)
        local cur = CurrentProfile()
        if cur == DEFAULT_PROFILE then return end
        if not self.confirm then
            self.confirm = true
            self:SetText("|cffff4040Confirmer ?|r")
            C_Timer.After(3, function() if self.confirm then RefreshProfileUI() end end)
            return
        end
        if InCombatLockdown() then Say("changement de profil impossible en combat.") return end
        root.profiles[cur] = nil
        for k, name in pairs(root.chars) do if name == cur then root.chars[k] = nil end end
        if SwitchProfile(DEFAULT_PROFILE) then Say("profil « " .. cur .. " » supprimé, retour à « Commun ».") end
    end)

    local note = Options:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", 20, -482)
    note:SetWidth(360)
    note:SetJustifyH("LEFT")
    note:SetText("* appliqué après rechargement de l'interface.\n"
        .. "« Tous mes debuffs » : affiche aussi tes autres affaiblissements.\n"
        .. "Portée : distance d'affichage des barres de vie ; un mob plus loin sort de la liste.\n"
        .. "Profil : « Commun » est partagé par les persos qui l'utilisent ; « Profil propre à ce perso » "
        .. "en fait une copie modifiable pour ce seul personnage.")

    local copy = Button("Reprendre l'apparence de DoTimer", 230, 24)
    copy:SetPoint("BOTTOMLEFT", 20, 50)
    copy:SetScript("OnClick", function()
        if CopyFromDoTimer() then
            RefreshAll()
            ApplyScale()
            MarkReload()
            Say("apparence de DoTimer recopiée dans le profil « " .. CurrentProfile() .. " ».")
        else
            Say("DoTimer n'est pas chargé : rien à recopier.")
        end
    end)

    reloadButton = CreateFrame("Button", nil, Options, "UIPanelButtonTemplate")
    reloadButton:SetSize(170, 24)
    reloadButton:SetPoint("BOTTOMLEFT", 20, 20)
    reloadButton:SetText("Recharger pour appliquer")
    reloadButton:SetScript("OnClick", function() ReloadUI() end)

    local close = CreateFrame("Button", nil, Options, "UIPanelButtonTemplate")
    close:SetSize(100, 24)
    close:SetPoint("BOTTOMRIGHT", -20, 20)
    close:SetText("Fermer")
    close:SetScript("OnClick", function() Options:Hide() end)

    Options:SetScript("OnShow", function()
        RefreshAll()
        reloadButton:SetEnabled(reloadPending)
    end)
end

ToggleOptions = function()
    if not Options then BuildOptions() end
    Options:SetShown(not Options:IsShown())
end

-- -------------------------------------------------------------------------
-- Événements : seulement nom / vie / cible ; les auras sont gérées par le jeu
-- -------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
ev:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("UNIT_HEALTH")
ev:RegisterEvent("RAID_TARGET_UPDATE")

ev:SetScript("OnEvent", function(self, event, unit)
    if event == "PLAYER_LOGIN" then
        -- Base et profil ouverts ici : le nom du perso et du royaume sont connus
        InitProfiles()
        if root.version ~= ADDON_VERSION then
            root.debug = false        -- le mode debug des versions de test est coupé
            root.version = ADDON_VERSION
        end
        UseProfile(CurrentProfile())
        PlaceAnchor()
        UpdateAnchorVisual()

        local _, class = UnitClass("player")
        SPELL_IDS = CLASS_SPELLS[class]
        if not SPELL_IDS then
            Main:Hide()   -- classe sans liste de DoTs (prêtre et démoniste seulement)
            self:UnregisterAllEvents()
            return
        end
        -- Premier lancement : l'apparence de DoTimer est recopiée
        if not db.copiedFromDoTimer and CopyFromDoTimer() then db.copiedFromDoTimer = true end
        ComputeConfig()
        ApplyScale()
        ApplyPlateRange(false)
        Build()

    elseif event == "PLAYER_REGEN_ENABLED" then
        if not built then Build() end
        if scalePending then ApplyScale() end
        if rangePending then ApplyPlateRange(true) end

    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
        -- Un autre mob a pris (ou quitté) ce jeton : en-tête à jour, et on
        -- demande au jeu de relire ses auras
        local row = rowByUnit[unit]
        if row then
            RefreshRow(row)
            pcall(row.head.UpdateAllAuras, row.head)
            pcall(row.icons.UpdateAllAuras, row.icons)
        end
        if root.debug then
            Say(string.format("[%.1f] barre de vie %s %s", GetTime(), tostring(unit),
                event == "NAME_PLATE_UNIT_ADDED" and "|cff40ff40ajoutée|r" or "|cffff4040retirée par le jeu|r"))
        end

    elseif event == "PLAYER_TARGET_CHANGED" or event == "RAID_TARGET_UPDATE" then
        for _, row in ipairs(rows) do RefreshRow(row) end

    elseif event == "UNIT_HEALTH" then
        local row = rowByUnit[unit]
        if row and (cfg.showHealth or cfg.showPct) then SetHealth(row) end
    end
end)

-- Filet de sécurité : tous les blocs sont rafraîchis 4 fois par seconde
-- (nom, flèches, marque, vie), au cas où un événement serait manqué
local elapsedSince = 0
ev:SetScript("OnUpdate", function(self, elapsed)
    elapsedSince = elapsedSince + elapsed
    if elapsedSince < REFRESH then return end
    elapsedSince = 0
    for _, row in ipairs(rows) do RefreshRow(row) end
end)

-- -------------------------------------------------------------------------
-- Commandes
-- -------------------------------------------------------------------------
SLASH_DOTIMERPLATES1 = "/dtp"
SlashCmdList["DOTIMERPLATES"] = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "lock" then
        db.locked = not db.locked
        UpdateAnchorVisual()
        Say(db.locked and "verrouillé" or "déverrouillé (glisse l'ancre pour la déplacer, clic droit = réglages)")
    elseif cmd == "debug" then
        -- fonds colorés (bleu = en-tête, rouge = icônes), jetons npN, journal
        root.debug = not root.debug
        for _, t in ipairs(debugTextures) do t:SetShown(root.debug) end
        for _, row in ipairs(rows) do row.token:SetShown(root.debug) end
        Say("mode debug " .. (root.debug and "activé" or "désactivé"))
    elseif cmd == "status" then
        Say(string.format("v%s, blocs : %d/%d, boutons natifs : %d + %d, écritures refusées : %d, filtre : %s",
            ADDON_VERSION, stats.built, MAX_PLATES, stats.headButtons, stats.iconButtons, stats.writeFails,
            cfg.all and "tous tes debuffs" or "DoTs de ta classe"))
        local any = false
        for what, err in pairs(stats.errors) do any = true; Say("  erreur " .. what .. " : " .. err) end
        if not any then Say("  aucune erreur") end
    elseif cmd == "" or cmd == "opt" or cmd == "options" then
        ToggleOptions()
    else
        Say("/dtp (réglages), /dtp lock, /dtp status (diagnostic), /dtp debug")
    end
end
