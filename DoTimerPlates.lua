-- =========================================================================
-- DoTimer Plates v1.5
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
-- v1.5 : mobs DoTés gardés. Devant chaque bloc, un cadre à nous ("keep"),
-- 1 pixel d'habitude. Quand tu lances un de tes DoTs sur un mob (ton propre
-- lancer, lisible), son bloc devient "gardé" : le cadre keep prend la hauteur
-- d'un en-tête et le conteneur d'en-tête natif est désactivé (sinon deux
-- en-têtes s'additionneraient). L'en-tête reste donc affiché sans DoT, jusqu'à
-- la mort du mob, le retrait de sa barre de vie ou la fin du combat. Un DoT
-- seulement propagé (sans lancer) ne garde pas le mob : le Lua ne le voit pas.
--
-- Limites connues (le jeu, pas l'addon) : un mob sans barre de vie affichée
-- (trop loin, hors écran, retirée par le jeu en instance) sort de la liste ;
-- pas de barre de dégâts prévus (il faudrait connaître le temps restant en
-- Lua). L'alerte d'expiration fait clignoter le timer et le bord, pas l'icône.
--
-- Profils (v1.4) : profils nommés, partagés ou non entre personnages
-- (« Commun » par défaut), copie des réglages d'un profil à l'autre.
-- Réglages appliqués en direct (v1.4) : les boutons créés par le jeu sont
-- gardés en liste et remis en forme à chaque changement (hors combat).
-- Mode test (v1.4) : des cibles fictives, dessinées par l'addon, pour voir
-- l'apparence sans combattre.
--
-- Commandes : /dtp (réglages), /dtp test, /dtp lock, /dtp status, /dtp debug
-- =========================================================================

local issecret = issecretvalue or function() return false end
local ADDON_VERSION = "1.5"

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
    testCount      = 5,       -- v1.4 : nombre de cibles du mode test
    keepDotted     = true,    -- v1.5 : un mob DoTé reste listé jusqu'à sa mort
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
local BAND_COLOR  = { r = 1.00, g = 0.78, b = 0.10 }   -- v1.5 : bande de la cible, jaune doré
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
    cfg.keep        = db.keepDotted
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
    -- hauteur des éléments des conteneurs : +1, le pixel du conteneur vide
    cfg.headH = BLOCK_GAP + cfg.headerOffset + 1
    cfg.iconH = cfg.iconCellHeight + 1
    -- formateurs de texte refaits avec les nouveaux réglages
    cfg.textOptions, cfg.borderFormatter = nil, nil
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

-- keepPosition (curseur d'échelle) : les décalages d'un cadre sont comptés à
-- sa propre échelle, l'ancre glisserait donc vers le coin de l'écran. Son coin
-- de départ (haut-gauche, ou bas-gauche si la liste monte) reste en place.
-- Sans keepPosition (connexion, profil) : la position enregistrée correspond
-- déjà à l'échelle du profil.
local scalePending, scaleKeepPending = false, false
local function ApplyScale(keepPosition)
    if InCombatLockdown() then
        scalePending = true
        scaleKeepPending = scaleKeepPending or keepPosition == true
        return
    end
    keepPosition = keepPosition == true or scaleKeepPending
    scalePending, scaleKeepPending = false, false
    local old = Main:GetScale()
    local left, top, bottom = Main:GetLeft(), Main:GetTop(), Main:GetBottom()
    Main:SetScale(db.scale)
    if keepPosition and left and top and bottom and math.abs(old - db.scale) > 0.0001 then
        local k = old / db.scale
        local point, y = "TOPLEFT", top * k
        if db.growUp then point, y = "BOTTOMLEFT", bottom * k end
        Main:ClearAllPoints()
        Main:SetPoint(point, UIParent, "BOTTOMLEFT", left * k, y)
        db.point, db.relPoint, db.x, db.y = point, "BOTTOMLEFT", left * k, y
    end
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

-- [>>] [niveau] nom [<<] [marque] ; le nom ne dépasse jamais la largeur du
-- bloc (comme DoTimer). Commun aux vrais blocs et à ceux du mode test.
local function SetTitle(row, lvlText, name, target, hasMark, mark)
    row.arrow:SetText(target and "|cffff2020>>|r" or "")
    row.tail:SetText(target and "|cffff2020<<|r" or "")
    row.raid:SetText(hasMark and string.format(RAID_ICON_TEXT, mark) or "")
    row.band:SetShown(target and true or false)
    local room = cfg.width - TITLE_X - (target and 19 or 0) - (hasMark and 20 or 0)
    row.title:SetWidth(0)
    row.title:SetText(string.format("|cff%s[%s] %s|r", cfg.nameHex, lvlText, name))
    local natural = row.title:GetStringWidth()   -- secret pour un nom caché
    if issecret(natural) or (natural or 0) > room then row.title:SetWidth(math.max(room, 20)) end
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
        Write(SetTitle, row, lvlText, name, target, hasMark, mark)
    end
    if cfg.showHealth or cfg.showPct then SetHealth(row) end
end

-- En-tête : NOTRE cadre, découpé à la taille du conteneur d'en-tête (row.head).
-- Créé une fois ; tailles, positions et couleurs posées par StyleHeader.
local function CreateHeader(row, parent, index)
    local clip = NewPlainFrame(parent)
    -- v1.5 : du haut du cadre keep (1 px, sauf mob gardé) au bas de l'en-tête
    clip:SetPoint("TOPLEFT", row.keep or row.head, "TOPLEFT", 0, 0)
    -- Largeur posée par StyleHeader, jamais prise sur le conteneur natif :
    -- désactivé (mob gardé), il ne fait plus qu'1 pixel de large
    clip:SetPoint("BOTTOMLEFT", row.head, "BOTTOMLEFT", 0, 0)
    clip:SetClipsChildren(true)
    row.clip = clip

    local h = CreateFrame("Frame", nil, clip)
    h:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, -BLOCK_GAP)
    row.h = h

    -- v1.5 : bande derrière le nom de ta cible, dorée à gauche et qui
    -- s'estompe vers la droite (couleur et place posées par StyleHeader)
    row.band = h:CreateTexture(nil, "BACKGROUND")
    row.band:Hide()

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

    -- Barre de vie : couleur et fond de DoTimer
    row.health = CreateFrame("StatusBar", nil, h)
    row.health:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    row.health:SetMinMaxValues(0, 1)
    row.health:SetValue(1)
    local bg = row.health:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.12, 0.12, 0.12, 0.8)

    -- % de vie à droite de la barre, aligné sur le bord du bloc. Rattaché à
    -- h : visible même sans barre. Largeur libre : « 100% » jamais coupé.
    row.pct = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.pct:SetPoint("RIGHT", row.health, "RIGHT", PCT_WIDTH, 0)
    row.pct:SetJustifyH("RIGHT")
    row.pct:SetWordWrap(false)
    -- Police des chiffres de vie du cadre de joueur de Blizzard
    -- (TextStatusBarText : Arial Narrow, contour fin, sans ombre)
    local fo = TextStatusBarText or NumberFontNormalSmall
    if fo then pcall(row.pct.SetFontObject, row.pct, fo) end

    -- Mode debug : numéro du jeton de barre de vie
    if index then
        row.token = h:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.token:SetPoint("TOPRIGHT", h, "TOPRIGHT", 0, 0)
        row.token:SetText("np" .. index)
        row.token:SetShown(root.debug == true)
    end
end

local function StyleHeader(row)
    row.clip:SetWidth(cfg.width)
    row.h:SetSize(cfg.width, math.max(cfg.headerOffset, 1))
    for _, fs in ipairs({ row.title, row.arrow, row.tail, row.raid }) do fs:SetShown(cfg.showNames) end
    -- bande de la cible : sur la ligne du nom, 2 px de marge au-dessus
    row.band:ClearAllPoints()
    row.band:SetPoint("TOPLEFT", row.h, "TOPLEFT", 0, 2)
    row.band:SetSize(cfg.width, cfg.titleHeight + 1)
    local tb = BAND_COLOR
    row.band:SetColorTexture(1, 1, 1, 1)
    if not (CreateColor and pcall(row.band.SetGradient, row.band, "HORIZONTAL",
        CreateColor(tb.r, tb.g, tb.b, 0.65), CreateColor(tb.r, tb.g, tb.b, 0.10))) then
        row.band:SetColorTexture(tb.r, tb.g, tb.b, 0.45)   -- sans dégradé
    end
    if not cfg.showNames then row.band:Hide() end   -- pas de nom, pas de bande
    local c = db.healthColor
    -- Avec le % : barre de 5 px raccourcie ; sinon la fine ligne de 3 px de DoTimer
    row.health:ClearAllPoints()
    row.health:SetPoint("TOPLEFT", row.h, "TOPLEFT", 0, cfg.healthY)
    row.health:SetSize(cfg.barWidth, cfg.barHeight)
    row.health:SetStatusBarColor(c.r, c.g, c.b)
    row.health:SetShown(cfg.showHealth)
    row.pct:SetShown(cfg.showPct)
end

-- Boutons créés par le jeu, gardés pour être remis en forme quand un réglage
-- change (comme ForeverAuras)
local headButtons, iconButtons = {}, {}

-- Bouton d'en-tête : seulement dimensionné, rien dessus. Sa présence
-- (1 aura au plus) donne la taille du conteneur d'en-tête.
local function StyleHead(button)
    Try("taille bouton en-tête", button, "SetSize", cfg.width, cfg.headH)
end

local function InitHead(button)
    stats.headButtons = stats.headButtons + 1
    headButtons[#headButtons + 1] = button
    pcall(button.EnableMouse, button, false)
    StyleHead(button)
end

-- Case d'icône comme DoTimer (icône rognée sur un bord noir de 1 px, voile,
-- timer dessous). Icône, voile et texte sont remplis par le jeu.
-- Couches, de l'arrière vers l'avant (v1.3) :
--   ring     : cadre découpé (clip) à la taille exacte de la case, qui
--              reçoit le carré d'alerte : seule la bande d'1 px autour de
--              l'icône reste visible = bord fin, comme DoTimer
--   iconLayer: l'icône (rognée d'1 px) et le voile, au-dessus du carré
local function CreateIconParts(button)
    pcall(button.EnableMouse, button, false)
    local p = {}
    button.dtp = p

    local cell = CreateFrame("Frame", nil, button)
    cell:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    p.cell = cell
    local border = cell:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0, 0, 0, 1)

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
    p.icon = icon
    Try("icône (SetIcon)", button, "SetIcon", icon)
    pcall(icon.SetTexCoord, icon, 0.08, 0.92, 0.08, 0.92)

    -- Voile et bord d'alerte : tous deux portés par le cooldown, créé dans
    -- tous les cas pour pouvoir les activer plus tard sans recharger
    local ok, cd = pcall(CreateFrame, "Cooldown", nil, iconLayer, "CooldownFrameTemplate")
    if ok and cd then
        p.cd = cd
        cd:SetAllPoints(icon)
        pcall(cd.SetReverse, cd, true)
        pcall(cd.SetDrawEdge, cd, false)
        pcall(cd.SetDrawBling, cd, false)
        pcall(cd.SetHideCountdownNumbers, cd, true)
        cd.noCooldownCount = true   -- pas de second timer d'OmniCC & co
        -- Les "chiffres" du cooldown (le bord d'alerte, voir BorderFormatter)
        -- passent dans la couche découpée, derrière l'icône : le carré, plus
        -- grand que la case, est coupé net à ses bords
        local numbers = cd.GetCountdownFontString and cd:GetCountdownFontString()
        if numbers and pcall(function()
            numbers:SetParent(ringHolder)
            numbers:SetDrawLayer("ARTWORK")
            numbers:ClearAllPoints()
            numbers:SetPoint("CENTER", cell, "CENTER", 0, 0)
        end) then p.numbers = numbers end
    end

    -- v1.3 : créé depuis le modèle du jeu, comme DoTimer : il garde l'ombre
    -- portée du modèle en plus du contour, d'où un texte plus contrasté
    p.text = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    p.text:SetPoint("TOP", cell, "BOTTOM", 0, -2)
end

local function StyleIcon(button)
    local p = button.dtp
    local size = cfg.iconSize
    Try("taille bouton icône", button, "SetSize", size, cfg.iconH)
    p.cell:SetSize(size, size)

    local cd = p.cd
    if cd then
        pcall(cd.SetDrawSwipe, cd, cfg.showSwipe)
        local border = cfg.warn and p.numbers and BorderFormatter()
        if border then
            pcall(cd.SetHideCountdownNumbers, cd, false)
            if not button.fake then pcall(cd.SetUseAuraDisplayTime, cd, true) end
            pcall(cd.SetMinimumCountdownDuration, cd, 0)
            Try("bord d'alerte (SetCountdownFormatter)", cd, "SetCountdownFormatter", border)
        else
            pcall(cd.SetHideCountdownNumbers, cd, true)
        end
    end

    local font = GameFontHighlightSmall:GetFont()
    p.text:SetFont(font, cfg.iconFontSize, "OUTLINE")
    local tc = db.timerTextColor
    p.text:SetTextColor(tc.r, tc.g, tc.b)
    local opts = TextOptions()
    if not (opts and pcall(button.SetDurationText, button, p.text, opts)) then
        Try("timer (SetDurationText)", button, "SetDurationText", p.text)
    end
end

local function InitIcon(button)
    stats.iconButtons = stats.iconButtons + 1
    iconButtons[#iconButtons + 1] = button
    CreateIconParts(button)
    StyleIcon(button)
    if button.dtp.cd then Try("voile (SetDurationCooldown)", button, "SetDurationCooldown", button.dtp.cd) end
end

-- Empile des blocs { head, icons } à partir de prev ; renvoie le dernier
-- cadre de la chaîne. Chaque élément a 1 pixel de plus que son contenu,
-- chaque ancrage le retire (un conteneur vide ne prend aucune place).
-- v1.5 : le cadre keep (vrais blocs seulement) se place juste au-dessus de
-- l'en-tête, avec la même règle du pixel en plus.
local function ChainBlocks(list, prev, first)
    for _, b in ipairs(list) do
        b.head:ClearAllPoints()
        b.icons:ClearAllPoints()
        if b.keep then b.keep:ClearAllPoints() end
        if cfg.growUp then
            -- vers le haut : icônes posées sur le bloc précédent, en-tête au-dessus
            b.icons:SetPoint("BOTTOMLEFT", prev, "TOPLEFT", 0, first and BLOCK_GAP or -1)
            b.head:SetPoint("BOTTOMLEFT", b.icons, "TOPLEFT", 0, -1)
            prev = b.head
            if b.keep then
                b.keep:SetPoint("BOTTOMLEFT", b.head, "TOPLEFT", 0, -1)
                prev = b.keep
            end
        else
            if b.keep then
                b.keep:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, first and 0 or 1)
                b.head:SetPoint("TOPLEFT", b.keep, "BOTTOMLEFT", 0, 1)
            else
                b.head:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, first and 0 or 1)
            end
            b.icons:SetPoint("TOPLEFT", b.head, "BOTTOMLEFT", 0, 1)
            prev = b.icons
        end
        first = false
    end
    return prev
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

-- Fonds colorés du mode debug (bleu = en-tête, rouge = icônes, vert = keep)
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

-- Mise en page d'un groupe : une file horizontale d'éléments w x h
local function GroupLayout(c, group, w, h, spacing)
    Try("mise en page " .. group, c, "SetAuraGroupLayout", group, { elementWidth = w, elementHeight = h, elementSpacing = spacing })
end

-- Règle un conteneur : unité, filtre, mise en page
local function Setup(c, unit, group, maxCount, w, h, spacing, init, sorted)
    if not Try("politique d'aura", c, "SetAuraProcessingPolicy", CustomAuraContainerAuraProcessingPolicy.None) then return false end
    Try("axe", c, "SetFlowLayoutAxis", AnchorUtil.FlowLayoutAxis.Horizontal)
    Try("coin", c, "SetFlowLayoutAnchorPoint", "TOPLEFT")
    Try("direction", c, "SetFlowLayoutGrowthDirection", AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
    if not Try("groupe " .. group, c, "AddAuraGroup", group, FILTER, {
        maxFrameCount = maxCount, candidateFilters = Candidates(), initializeFrame = init,
    }) then return false end
    GroupLayout(c, group, w, h, spacing)
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
local chainTail = Main      -- dernier cadre de la liste (le mode test s'y accroche)
local builtAll              -- valeur de « Tous mes debuffs » posée sur les conteneurs
local builtUp               -- sens d'empilement des ancrages posés
local function Build()
    if built then return end
    if InCombatLockdown() then return end   -- refait à la fin du combat
    built = true
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        local ok, reason = C_AddOns.LoadAddOn("Blizzard_AuraContainer")
        if not ok then Fail("chargement de Blizzard_AuraContainer", reason) return end
    end
    Main:SetWidth(cfg.width)
    builtAll, builtUp = cfg.all, cfg.growUp

    local prev = Main
    for i = 1, MAX_PLATES do
        local row = { unit = "nameplate" .. i, serial = 0 }
        row.keep = NewPlainFrame(Main)
        row.keep:SetSize(cfg.width, 1)
        DebugBackground(row.keep, 0, 1, 0)
        row.head = NewContainer(0, 0.4, 1)
        row.icons = NewContainer(1, 0, 0)
        if not (row.head and row.icons) then break end
        prev = ChainBlocks({ row }, prev, i == 1)

        local okH = Setup(row.head, row.unit, "Head", 1, cfg.width, cfg.headH, 0, InitHead)
        local okI = Setup(row.icons, row.unit, "Auras", MAX_ICONS, cfg.iconSize, cfg.iconH, cfg.iconSpacing, InitIcon, true)
        if not (okH and okI) then break end
        CreateHeader(row, Main, i)
        StyleHeader(row)

        rows[i] = row
        rowByUnit[row.unit] = row
        stats.built = i
    end
    chainTail = prev
end

-- -------------------------------------------------------------------------
-- v1.5 : mobs DoTés gardés dans la liste (voir l'en-tête du fichier).
-- Le seul signal lisible est TON lancer : UNIT_SPELLCAST_* du joueur donne
-- le sort, et UnitIsUnit(cible, nameplateN) reste lisible en instance.
-- -------------------------------------------------------------------------
local trackedIDs = {}          -- ID de sort suivi -> true (classe du joueur)

-- Mort lisible ? Une réponse cachée (secrète) compte comme vivant.
local function IsDead(unit)
    local ok, dead = pcall(UnitIsDead, unit)
    return ok and not issecret(dead) and dead == true
end

-- Hors instance, l'identifiant (GUID) d'un mob est lisible : un mob gardé
-- qui perd sa barre de vie (trop loin) est de nouveau gardé à son retour.
-- En instance il est caché : la garde se perd avec la barre de vie.
local keptGUIDs = {}           -- GUID lisible -> true
local function ReadableGUID(unit)
    local ok, guid = pcall(UnitGUID, unit)
    if ok and type(guid) == "string" and not issecret(guid) then return guid end
end

-- forget : le mob est mort, il ne sera pas regardé à son retour
local function SetSticky(row, on, forget)
    on = (on and cfg.keep) and true or false
    if forget and row.guid then keptGUIDs[row.guid] = nil end
    if (row.sticky or false) == on then return end
    row.sticky = on
    row.guid = on and ReadableGUID(row.unit) or nil
    if row.guid then keptGUIDs[row.guid] = true end
    Write(row.keep.SetHeight, row.keep, on and cfg.headH or 1)
    -- En-tête natif coupé tant que le mob est gardé : l'en-tête vient alors
    -- du cadre keep, qu'il y ait des DoTs ou non (jamais deux en-têtes)
    Try("en-tête natif (mob gardé)", row.head, "SetEnabled", not on)
    if not on then pcall(row.head.UpdateAllAuras, row.head) end
    RefreshRow(row)
    if root.debug then
        Say(string.format("[%.1f] %s %s", GetTime(), row.unit,
            on and "|cff40ff40gardé (DoT lancé)|r" or "|cffffd040n'est plus gardé|r"))
    end
end

local function UnstickAll()
    for _, row in ipairs(rows) do SetSticky(row, false) end
end

-- Bloc dont la barre de vie est cette unité (target, mouseover...)
local function RowOf(unit)
    if not unit or not UnitExists(unit) then return nil end
    for _, row in ipairs(rows) do
        if UnitExists(row.unit) then
            local ok, same = pcall(UnitIsUnit, unit, row.unit)
            if ok and not issecret(same) and same then return row end
        end
    end
end

local function ReadableName(unit)
    local ok, name = pcall(UnitName, unit)
    if ok and type(name) == "string" and not issecret(name) then return name end
end

-- true / false, ou nil si la réponse est cachée
local function CanAttack(unit)
    local ok, hostile = pcall(UnitCanAttack, "player", unit)
    if not ok or issecret(hostile) then return nil end
    return hostile and true or false
end

-- Unité visée par un lancer, comme DoTimer : nom envoyé par
-- UNIT_SPELLCAST_SENT (macros @mouseover / @focus, lisible hors instance),
-- sinon la cible, sinon la cible de la cible (cible amicale)
local CAST_UNITS = { "target", "mouseover", "focus", "targettarget" }
local function CastUnit(sentName)
    if sentName then
        for _, unit in ipairs(CAST_UNITS) do
            if ReadableName(unit) == sentName and CanAttack(unit) then return unit end
        end
    end
    if CanAttack("target") ~= false then return "target" end
    if CanAttack("targettarget") then return "targettarget" end
end

local sentNames = {}           -- castGUID -> nom de la destination
local castRows = {}            -- castGUID -> { row, serial } au début d'un lancer long

local function Readable(v) return v ~= nil and not issecret(v) end

local function OnPlayerCast(event, castGUID, a, b)
    if not cfg.keep then return end
    if not Readable(castGUID) then castGUID = nil end
    if event == "UNIT_SPELLCAST_SENT" then
        -- arguments : nom de la destination, castGUID, spellID
        local name, guid = castGUID, a
        if Readable(guid) and type(name) == "string" and name ~= "" then sentNames[guid] = name end
        return
    end
    local spellID = a
    if not castGUID then return end
    if event == "UNIT_SPELLCAST_START" then
        -- lancer long : le mob visé au début compte, même si la cible change
        if Readable(spellID) and trackedIDs[spellID] then
            local row = RowOf(CastUnit(sentNames[castGUID]))
            castRows[castGUID] = row and { row = row, serial = row.serial } or nil
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local started = castRows[castGUID]
        local sent = sentNames[castGUID]
        castRows[castGUID], sentNames[castGUID] = nil, nil
        if not (Readable(spellID) and trackedIDs[spellID]) then return end
        if started then
            -- la barre de vie a changé de mob pendant le lancer : rien
            if started.row.serial == started.serial then SetSticky(started.row, true) end
        else
            local row = RowOf(CastUnit(sent))
            if row then SetSticky(row, true) end
        end
    else   -- STOP / FAILED / INTERRUPTED
        castRows[castGUID], sentNames[castGUID] = nil, nil
    end
end

-- -------------------------------------------------------------------------
-- v1.4 : mode test. Des blocs fictifs, faits de NOS cadres (le cadre natif
-- n'affiche que de vraies auras), avec la même mise en forme que les vrais.
-- Ils s'accrochent après la liste réelle : ils ne la cachent jamais.
-- Les timers sont calculés en Lua (ce sont de fausses auras) avec les mêmes
-- règles que le formateur du jeu ; chaque fausse aura recommence à expiration.
-- -------------------------------------------------------------------------
local TEST_SPELLS = {   -- { sort, durée en s } : un DoT de chaque sorte
    PRIEST  = { { 10894, 18 }, { 19280, 24 }, { 402668, 15 }, { 425204, 12 }, { 19285, 120 } },
    WARLOCK = { { 25311, 18 }, { 11713, 24 }, { 25309, 15 }, { 18881, 30 }, { 11717, 120 } },
}
local TEST_HEALTH = { 100, 76, 52, 31, 12, 88, 64, 43, 20, 95 }
local TEST_COUNTS = { 3, 2, 4, 1, 5 }
local TEST_MAX    = 10
local testList              -- TEST_SPELLS de la classe du personnage
local testMode = false      -- jamais sauvegardé : coupé au rechargement
local testBlocks = {}
local Preview = CreateFrame("Frame", nil, Main)
Preview:SetAllPoints(Main)
Preview:Hide()

local function SpellTexture(id)
    local tex
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, t = pcall(C_Spell.GetSpellTexture, id)
        if ok then tex = t end
    end
    if not tex and GetSpellTexture then
        local ok, t = pcall(GetSpellTexture, id)
        if ok then tex = t end
    end
    return tex or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Imite un bouton du jeu : les liaisons sont gardées, pas exécutées
local function FakeButton(parent)
    local b = CreateFrame("Frame", nil, parent)
    b.fake = true
    b.SetIcon = function() end
    b.SetDurationCooldown = function() end
    b.SetDurationText = function() end
    return b
end

local function TestTimerText(rem)
    local s
    if rem >= 60 then
        s = string.format("%d:%02d", math.floor(rem / 60), math.floor(rem % 60))
    elseif cfg.tenthsBelow > 0 and rem < cfg.tenthsBelow then
        s = string.format("%.1fs", rem)
    else
        s = string.format("%ds", math.ceil(rem))
    end
    if cfg.warn and rem < cfg.warnTime then
        local c = db.warningColor
        local k = math.floor(rem / (cfg.blinkPeriod / 2)) % 2 == 0 and 255 or 115
        s = string.format("|cff%02x%02x%02x%s|r", math.floor(c.r * k), math.floor(c.g * k), math.floor(c.b * k), s)
    end
    return s
end

local function NewTestBlock(i)
    local b = { auras = {}, order = {} }
    b.head = NewPlainFrame(Preview)
    b.icons = NewPlainFrame(Preview)
    CreateHeader(b, Preview)
    local now = GetTime()
    local count = math.min(TEST_COUNTS[(i - 1) % #TEST_COUNTS + 1], #testList)
    for k = 1, count do
        local spell = testList[(i + k - 2) % #testList + 1]
        local btn = FakeButton(b.icons)
        CreateIconParts(btn)
        btn.dtp.icon:SetTexture(SpellTexture(spell[1]))
        -- départs décalés : certaines auras sont déjà proches de la fin
        local a = { btn = btn, dur = spell[2], start = now - spell[2] * (((i * 7 + k * 3) % 10) / 10) * 0.9 }
        if btn.dtp.cd then pcall(btn.dtp.cd.SetCooldown, btn.dtp.cd, a.start, a.dur) end
        b.auras[k], b.order[k] = a, a
    end
    return b
end

local function FillTestHeader(b, i)
    local mark = db.showRaidMarks and ({ [2] = 8, [3] = 1 })[i] or nil   -- crâne, étoile
    local lvl = UnitLevel("player") or 60
    if cfg.showNames then SetTitle(b, tostring(lvl + (i % 3)), "Cible de test " .. i, i == 1, mark ~= nil, mark) end
    local v = TEST_HEALTH[(i - 1) % #TEST_HEALTH + 1]
    b.health:SetMinMaxValues(0, 100)
    b.health:SetValue(v)
    b.pct:SetFormattedText("%d%%", v)
end

-- Timers des fausses auras, triés par temps restant comme ceux du jeu
local function TickTestBlock(b, now)
    for _, a in ipairs(b.auras) do
        if now - a.start >= a.dur then
            a.start = now
            if a.btn.dtp.cd then pcall(a.btn.dtp.cd.SetCooldown, a.btn.dtp.cd, now, a.dur) end
        end
        a.rem = a.dur - (now - a.start)
    end
    table.sort(b.order, function(x, y) return x.rem < y.rem end)
    for k, a in ipairs(b.order) do
        a.btn:ClearAllPoints()
        a.btn:SetPoint("TOPLEFT", b.icons, "TOPLEFT", (k - 1) * (cfg.iconSize + cfg.iconSpacing), 0)
        a.btn.dtp.text:SetText(TestTimerText(a.rem))
    end
end

local function LayoutPreview()
    if not (testMode and testList) then Preview:Hide() return end
    local n = math.min(math.max(db.testCount or 5, 1), TEST_MAX)
    local list = {}
    for i = 1, n do
        local b = testBlocks[i] or NewTestBlock(i)
        testBlocks[i] = b
        list[i] = b
        b.head:SetSize(cfg.width, cfg.headH)
        b.icons:SetSize(cfg.width, cfg.iconH)
        StyleHeader(b)
        for _, a in ipairs(b.auras) do StyleIcon(a.btn) end
        FillTestHeader(b, i)
    end
    for i, b in ipairs(testBlocks) do
        local on = i <= n
        b.head:SetShown(on)
        b.icons:SetShown(on)
        b.clip:SetShown(on)
    end
    ChainBlocks(list, chainTail, chainTail == Main)
    Preview:Show()
end

local testElapsed = 0
Preview:SetScript("OnUpdate", function(_, elapsed)
    testElapsed = testElapsed + elapsed
    if testElapsed < 0.05 then return end
    testElapsed = 0
    local now = GetTime()
    for _, b in ipairs(testBlocks) do
        if b.head:IsShown() then TickTestBlock(b, now) end
    end
end)

local function SetTestMode(on)
    testMode = on and testList ~= nil
    LayoutPreview()
end

-- -------------------------------------------------------------------------
-- v1.4 : réglages appliqués en direct. Hors combat, conteneurs, boutons du
-- jeu et en-têtes sont remis en forme ; en combat, à la fin du combat.
-- -------------------------------------------------------------------------
local function Relayout()
    Main:SetWidth(cfg.width)
    -- les ancrages ne dépendent que du sens d'empilement
    if cfg.growUp ~= builtUp then
        builtUp = cfg.growUp
        chainTail = ChainBlocks(rows, Main, true)
    end
    local filtersChanged = cfg.all ~= builtAll
    builtAll = cfg.all
    if not cfg.keep then UnstickAll() end
    for _, row in ipairs(rows) do
        row.keep:SetSize(cfg.width, row.sticky and cfg.headH or 1)
        GroupLayout(row.head, "Head", cfg.width, cfg.headH, 0)
        GroupLayout(row.icons, "Auras", cfg.iconSize, cfg.iconH, cfg.iconSpacing)
        if filtersChanged then
            Try("filtre Head", row.head, "SetAuraGroupCandidateFilters", "Head", Candidates())
            Try("filtre Auras", row.icons, "SetAuraGroupCandidateFilters", "Auras", Candidates())
        end
        StyleHeader(row)
    end
    for _, b in ipairs(headButtons) do StyleHead(b) end
    for _, b in ipairs(iconButtons) do StyleIcon(b) end
    for _, row in ipairs(rows) do
        pcall(row.head.UpdateAllAuras, row.head)
        pcall(row.icons.UpdateAllAuras, row.icons)
        RefreshRow(row)
    end
    LayoutPreview()
end

local applyPending = false
local function ApplySettings()
    if not SPELL_IDS then return end
    if InCombatLockdown() then applyPending = true return end
    applyPending = false
    ComputeConfig()
    if built then Relayout() else Build() end
end

-- Pour les curseurs : appliqué quand on arrête de le bouger
local applyToken = 0
local function ScheduleApply()
    applyToken = applyToken + 1
    local token = applyToken
    C_Timer.After(0.25, function() if token == applyToken then ApplySettings() end end)
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
-- Panneau de réglages (/dtp ou clic droit sur l'ancre). v1.4 : onglets,
-- sur le modèle de la fenêtre de DoTimer Forever 0.9.6.
-- -------------------------------------------------------------------------
local Options
local refreshers, loading = {}, false

-- key : clé du profil, ou { get = fn, set = fn } pour un état hors profil
local function AddCheck(parent, label, x, y, key, onChange)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", Options, "TOPLEFT", x, y)
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    cb.label:SetText(label)
    local get = type(key) == "table" and key.get or function() return db[key] == true end
    local set = type(key) == "table" and key.set or function(v) db[key] = v end
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        if onChange then onChange() end
    end)
    refreshers[#refreshers + 1] = function() cb:SetChecked(get()) end
    return cb
end

local function AddSlider(parent, label, lo, hi, step, x, y, key, fmt, onChange, fallback)
    local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", Options, "TOPLEFT", x, y)
    s:SetWidth(170)
    s:SetMinMaxValues(lo, hi)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s.Low:SetText(fmt(lo))
    s.High:SetText(fmt(hi))
    local function Label(v) s.Text:SetText(label .. " : " .. fmt(v)) end
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v / step + 0.5) * step
        Label(v)
        if loading or db[key] == v then return end
        db[key] = v
        if onChange then onChange() end
    end)
    refreshers[#refreshers + 1] = function()
        local v = db[key]
        if v == nil and fallback then v = fallback() end   -- valeur actuelle du jeu
        v = math.min(math.max(v or lo, lo), hi)
        s:SetValue(v)
        Label(v)
    end
    return s
end

local function AddText(parent, font, text, x, y, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", font)
    fs:SetPoint("TOPLEFT", Options, "TOPLEFT", x, y)
    if width then
        fs:SetWidth(width)
        fs:SetJustifyH("LEFT")
    end
    fs:SetText(text)
    return fs
end

local function AddButton(parent, label, w, h)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h)
    b:SetText(label)
    return b
end

-- Bouton en deux clics : le second, dans les 3 s, confirme
local function Confirmable(b, label, action)
    b:SetScript("OnClick", function(self)
        if not self.confirm then
            self.confirm = true
            self:SetText("|cffff4040Confirmer ?|r")
            C_Timer.After(3, function()
                if self.confirm then self.confirm = nil; self:SetText(label) end
            end)
            return
        end
        self.confirm = nil
        self:SetText(label)
        action()
    end)
end

-- Liste déroulante légère (comme DoTimer : pas d'UIDropDownMenu, source de
-- taint connue)
local ROW_HEIGHT = 18
local function AddDropdown(parent, x, y, width, onPick)
    local button = AddButton(parent, "", width, 22)
    button:SetPoint("TOPLEFT", Options, "TOPLEFT", x, y)
    local arrow = button:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(16, 16)
    arrow:SetPoint("RIGHT", button, "RIGHT", -4, 0)
    arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    local fs = button:GetFontString()
    if fs then   -- un nom long est coupé au lieu de déborder du bouton
        fs:SetWidth(width - 30)
        fs:SetWordWrap(false)
        fs:SetJustifyH("LEFT")
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", button, "LEFT", 8, 0)
    end

    local menu = CreateFrame("Frame", nil, button, "BackdropTemplate")
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
    menu:SetWidth(width)
    menu:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    menu:SetBackdropColor(0, 0, 0, 0.95)
    menu:Hide()
    menu.rows = {}
    button.menu = menu

    button.Fill = function(names, current)
        for i, name in ipairs(names) do
            local row = menu.rows[i]
            if not row then
                row = CreateFrame("Button", nil, menu)
                row:SetHeight(ROW_HEIGHT)
                row:SetPoint("TOPLEFT", menu, "TOPLEFT", 6, -6 - (i - 1) * ROW_HEIGHT)
                row:SetPoint("RIGHT", menu, "RIGHT", -6, 0)
                row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                row.check = row:CreateTexture(nil, "ARTWORK")
                row.check:SetSize(14, 14)
                row.check:SetPoint("LEFT", row, "LEFT", 0, 0)
                row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
                row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.label:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
                row.label:SetPoint("RIGHT", row, "RIGHT", 0, 0)
                row.label:SetJustifyH("LEFT")
                row.label:SetWordWrap(false)
                row:SetScript("OnClick", function(self)
                    menu:Hide()
                    onPick(self.name)
                end)
                menu.rows[i] = row
            end
            row.name = name
            row.label:SetText(name)
            row.check:SetShown(name == current)
            row:Show()
        end
        for i = #names + 1, #menu.rows do menu.rows[i]:Hide() end
        menu:SetHeight(12 + math.max(#names, 1) * ROW_HEIGHT)
    end
    return button
end

local function RefreshOptions()
    if not (Options and Options:IsShown()) then return end
    loading = true
    for _, fn in ipairs(refreshers) do fn() end
    loading = false
end

local function SwitchProfile(name)
    if InCombatLockdown() then Say("changement de profil impossible en combat.") return false end
    UseProfile(name)
    PlaceAnchor()
    UpdateAnchorVisual()
    ApplyScale()
    ApplyPlateRange(false)
    RefreshOptions()
    ApplySettings()
    return true
end

local function BuildOptions()
    Options = CreateFrame("Frame", "DoTimerPlatesOptions", UIParent, "BackdropTemplate")
    Options:SetSize(460, 470)
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
    local logo = Options:CreateTexture(nil, "ARTWORK")   -- icône de l'addon, comme DoTimer
    logo:SetSize(28, 28)
    logo:SetPoint("RIGHT", title, "LEFT", -6, 0)
    logo:SetTexture("Interface\\AddOns\\DoTimerPlates\\media\\icon.tga")

    -- Onglets : une page par onglet, coordonnées relatives à la fenêtre
    local tabs = {}
    local function SelectTab(index)
        for i, tab in ipairs(tabs) do
            local on = i == index
            tab.page:SetShown(on)
            tab.bg:SetColorTexture(on and 0.35 or 0.12, on and 0.30 or 0.12, on and 0.50 or 0.14, 0.95)
            tab.label:SetTextColor(on and 1 or 0.7, on and 0.82 or 0.7, on and 0 or 0.7)
            tab.underline:SetShown(on)
        end
    end
    local function AddTab(label)
        local index = #tabs + 1
        local page = CreateFrame("Frame", nil, Options)
        page:SetAllPoints(Options)
        page:Hide()
        local tab = CreateFrame("Button", nil, Options)
        tab:SetHeight(22)
        tab.bg = tab:CreateTexture(nil, "BACKGROUND")
        tab.bg:SetAllPoints(tab)
        tab.underline = tab:CreateTexture(nil, "ARTWORK")
        tab.underline:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
        tab.underline:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)
        tab.underline:SetHeight(2)
        tab.underline:SetColorTexture(0.58, 0.51, 0.79, 1)   -- violet DoTimer
        tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tab.label:SetPoint("CENTER", tab, "CENTER", 0, 1)
        tab.label:SetText(label)
        tab:SetWidth(math.max(80, (tab.label:GetStringWidth() or 0) + 24))
        if index == 1 then
            tab:SetPoint("TOPLEFT", Options, "TOPLEFT", 20, -46)
        else
            tab:SetPoint("LEFT", tabs[index - 1], "RIGHT", 4, 0)
        end
        tab.page = page
        tab:SetScript("OnClick", function() SelectTab(index) end)
        tabs[index] = tab
        return page
    end
    local pGeneral = AddTab("Général")
    local pLayout  = AddTab("Disposition")
    local pIcons   = AddTab("Icônes")
    local pProf    = AddTab("Profils")

    local function plain(v) return tostring(v) end
    local function seconds(v) return v .. " s" end

    -- --- Général --------------------------------------------------------
    AddCheck(pGeneral, "Verrouiller le cadre", 20, -84, "locked", UpdateAnchorVisual)
    AddCheck(pGeneral, "Noms des cibles", 20, -110, "showNames", ApplySettings)
    AddCheck(pGeneral, "Barre de vie", 20, -136, "showHealth", ApplySettings)
    AddCheck(pGeneral, "% de vie", 20, -162, "showHealthPct", ApplySettings)
    AddCheck(pGeneral, "Marqueurs de raid", 20, -188, "showRaidMarks", ApplySettings)
    AddCheck(pGeneral, "Tous mes debuffs", 20, -214, "all", ApplySettings)
    AddCheck(pGeneral, "Alerte de fin", 250, -84, "warnEnabled", ApplySettings)
    AddSlider(pGeneral, "Seuil d'alerte", 1, 10, 1, 258, -134, "warnTime", seconds, ScheduleApply)
    AddSlider(pGeneral, "Portée barres de vie", 10, 60, 1, 258, -186, "plateRange",
        function(v) return v .. " m" end, function()
            -- appliqué une fois le curseur relâché (pas un message par cran)
            local token = (Options.rangeToken or 0) + 1
            Options.rangeToken = token
            C_Timer.After(0.6, function() if Options.rangeToken == token then ApplyPlateRange(true) end end)
        end, GetPlateRange)
    AddCheck(pGeneral, "Garder les mobs DoTés", 250, -228, "keepDotted", ApplySettings)
    local copy = AddButton(pGeneral, "Reprendre l'apparence de DoTimer", 240, 22)
    copy:SetPoint("TOPLEFT", Options, "TOPLEFT", 22, -256)
    copy:SetScript("OnClick", function()
        if CopyFromDoTimer() then
            RefreshOptions()
            ApplyScale(true)   -- l'ancre reste en place
            ApplySettings()
            Say("apparence de DoTimer recopiée dans le profil « " .. CurrentProfile() .. " ».")
        else
            Say("DoTimer n'est pas chargé : rien à recopier.")
        end
    end)
    AddText(pGeneral, "GameFontDisableSmall",
        "Les réglages s'appliquent tout de suite (à la fin du combat si tu combats).\n"
        .. "Tous mes debuffs : affiche aussi tes affaiblissements qui ne sont pas des DoTs.\n"
        .. "Garder les mobs DoTés : un mob sur lequel tu lances un DoT reste listé "
        .. "jusqu'à sa mort ou la fin du combat.\n"
        .. "Portée : distance d'affichage des barres de vie du jeu ; un mob plus loin "
        .. "sort de la liste.", 24, -296, 410)

    -- --- Disposition ----------------------------------------------------
    AddSlider(pLayout, "Largeur des blocs", 80, 300, 5, 28, -98, "width", plain, ScheduleApply)
    AddSlider(pLayout, "Échelle", 0.5, 2, 0.05, 28, -150, "scale",
        function(v) return string.format("%.2f", v) end, function() ApplyScale(true) end)
    AddSlider(pLayout, "Dixièmes de seconde sous", 0, 60, 1, 28, -202, "tenthsBelow", function(v)
        if v <= 0 then return "jamais" elseif v >= 60 then return "toujours" end
        return v .. " s"
    end, ScheduleApply)
    AddText(pLayout, "GameFontHighlight", "Sens d'empilement", 252, -84)
    AddCheck(pLayout, "Vers le haut", 250, -102, "growUp", ApplySettings)

    -- --- Icônes ---------------------------------------------------------
    AddSlider(pIcons, "Taille des icônes", 14, 40, 1, 28, -98, "iconSize", plain, ScheduleApply)
    AddSlider(pIcons, "Espacement des icônes", 0, 10, 1, 28, -150, "iconSpacing", plain, ScheduleApply)
    AddCheck(pIcons, "Balayage de recharge", 250, -84, "showSwipe", ApplySettings)

    -- --- Profils (comme DoTimer) ----------------------------------------
    local RefreshProfiles
    AddText(pProf, "GameFontHighlight", "Profil de ce personnage", 26, -84)
    local current = AddDropdown(pProf, 24, -101, 230, function(name)
        if name ~= CurrentProfile() and SwitchProfile(name) then Say("profil « " .. name .. " ».") end
        RefreshProfiles()
    end)
    AddText(pProf, "GameFontDisableSmall",
        "Plusieurs personnages peuvent utiliser le même profil (les changements "
        .. "s'appliquent alors à tous). « Commun » est celui des personnages sans profil choisi.",
        26, -130, 410)

    AddText(pProf, "GameFontHighlight", "Nouveau profil (à partir des réglages actuels)", 26, -172)
    local edit = CreateFrame("EditBox", nil, pProf, "InputBoxTemplate")
    edit:SetSize(180, 20)
    edit:SetPoint("TOPLEFT", Options, "TOPLEFT", 32, -189)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(32)
    local create = AddButton(pProf, "Créer", 110, 22)
    create:SetPoint("LEFT", edit, "RIGHT", 10, 0)
    local function CreateProfile()
        local name = (edit:GetText() or ""):match("^%s*(.-)%s*$")
        if name == "" then return end
        if root.profiles[name] then Say("le profil « " .. name .. " » existe déjà.") return end
        if InCombatLockdown() then Say("changement de profil impossible en combat.") return end
        root.profiles[name] = DeepCopy(db)
        edit:SetText("")
        edit:ClearFocus()
        if SwitchProfile(name) then Say("profil « " .. name .. " » créé.") end
        RefreshProfiles()
    end
    create:SetScript("OnClick", CreateProfile)
    edit:SetScript("OnEnterPressed", CreateProfile)
    edit:SetScript("OnEscapePressed", edit.ClearFocus)

    AddText(pProf, "GameFontHighlight", "Autre profil", 26, -228)
    local selected
    local other = AddDropdown(pProf, 24, -245, 230, function(name)
        selected = name
        RefreshProfiles()
    end)
    local copyP = AddButton(pProf, "Copier ses réglages ici", 170, 22)
    copyP:SetPoint("TOPLEFT", Options, "TOPLEFT", 24, -275)
    Confirmable(copyP, "Copier ses réglages ici", function()
        if not (selected and root.profiles[selected]) then return end
        if InCombatLockdown() then Say("copie impossible en combat.") return end
        local cur = CurrentProfile()
        root.profiles[cur] = DeepCopy(root.profiles[selected])
        if SwitchProfile(cur) then Say("réglages de « " .. selected .. " » copiés dans « " .. cur .. " ».") end
        RefreshProfiles()
    end)
    local delP = AddButton(pProf, "Supprimer", 110, 22)
    delP:SetPoint("LEFT", copyP, "RIGHT", 10, 0)
    -- Les persos qui utilisaient le profil supprimé reviennent à « Commun »
    Confirmable(delP, "Supprimer", function()
        if not selected or selected == DEFAULT_PROFILE then return end
        root.profiles[selected] = nil
        for k, name in pairs(root.chars) do if name == selected then root.chars[k] = nil end end
        Say("profil « " .. selected .. " » supprimé.")
        selected = nil
        RefreshProfiles()
    end)

    local resetP = AddButton(pProf, "Réinitialiser ce profil", 200, 22)
    resetP:SetPoint("TOPLEFT", Options, "TOPLEFT", 24, -322)
    -- Réglages par défaut ; l'ancre reste où elle est
    Confirmable(resetP, "Réinitialiser ce profil", function()
        if InCombatLockdown() then Say("réinitialisation impossible en combat.") return end
        local keep = { point = db.point, relPoint = db.relPoint, x = db.x, y = db.y, copiedFromDoTimer = true }
        local cur = CurrentProfile()
        root.profiles[cur] = keep
        if SwitchProfile(cur) then Say("profil « " .. cur .. " » réinitialisé.") end
    end)

    RefreshProfiles = function()
        local cur = CurrentProfile()
        local names = ProfileNames()
        current:SetText(cur)
        current.Fill(names, cur)
        local others = {}
        for _, n in ipairs(names) do if n ~= cur then others[#others + 1] = n end end
        local still = false
        for _, n in ipairs(others) do if n == selected then still = true end end
        if not still then selected = nil end
        other:SetText(selected or "|cff808080choisis un profil|r")
        other.Fill(others, selected)
        copyP:SetEnabled(selected ~= nil)
        delP:SetEnabled(selected ~= nil and selected ~= DEFAULT_PROFILE)
    end
    refreshers[#refreshers + 1] = RefreshProfiles
    for _, dd in ipairs({ current, other }) do
        dd:SetScript("OnClick", function(self)
            if self.menu:IsShown() then self.menu:Hide() else RefreshProfiles(); self.menu:Show() end
        end)
    end
    pProf:SetScript("OnHide", function() current.menu:Hide(); other.menu:Hide() end)

    -- --- Bas de fenêtre, sur toutes les pages ---------------------------
    -- Mode test : jamais sauvegardé, coupé en combat et à la fermeture
    AddCheck(Options, "Aperçu avec des cibles fictives", 20, -372,
        { get = function() return testMode end, set = SetTestMode })
    AddSlider(Options, "Cibles fictives", 1, TEST_MAX, 1, 270, -380, "testCount", plain, LayoutPreview)

    local close = AddButton(Options, "Fermer", 100, 22)
    close:SetPoint("BOTTOMRIGHT", -20, 20)
    close:SetScript("OnClick", function() Options:Hide() end)

    Options:SetScript("OnShow", RefreshOptions)
    Options:SetScript("OnHide", function() if testMode then SetTestMode(false) end end)
    SelectTab(1)
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
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
ev:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("UNIT_HEALTH")
ev:RegisterEvent("RAID_TARGET_UPDATE")
-- v1.5 : tes lancers, pour garder les mobs DoTés
for _, e in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
    ev:RegisterUnitEvent(e, "player")
end

ev:SetScript("OnEvent", function(self, event, unit, a1, a2, a3)
    if event:find("^UNIT_SPELLCAST_") then
        if unit == "player" and built then OnPlayerCast(event, a1, a2, a3) end
        return
    end
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
        testList = TEST_SPELLS[class]
        for _, id in ipairs(SPELL_IDS or {}) do trackedIDs[id] = true end
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
        -- fin du combat : plus aucun mob gardé (tes DoTs ne tournent plus)
        UnstickAll()
        wipe(sentNames)
        wipe(castRows)
        wipe(keptGUIDs)
        if applyPending then ApplySettings() elseif not built then Build() end
        if scalePending then ApplyScale() end
        if rangePending then ApplyPlateRange(true) end

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- le mode test est coupé en combat : seule la vraie liste compte
        if testMode then
            SetTestMode(false)
            RefreshOptions()
            Say("aperçu coupé (combat).")
        end

    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
        -- Un autre mob a pris (ou quitté) ce jeton : en-tête à jour, et on
        -- demande au jeu de relire ses auras
        local row = rowByUnit[unit]
        if row then
            -- v1.5 : nouveau mob (ou plus de mob) sur ce jeton : plus gardé
            row.serial = row.serial + 1
            SetSticky(row, false)
            -- hors instance : mob gardé revenu à portée, de nouveau gardé
            local guid = event == "NAME_PLATE_UNIT_ADDED" and ReadableGUID(unit)
            if guid and keptGUIDs[guid] and not IsDead(unit) then SetSticky(row, true) end
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
        if row and row.sticky and IsDead(unit) then SetSticky(row, false, true) end
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
    for _, row in ipairs(rows) do
        -- mob gardé mort (ou barre disparue sans événement) : plus gardé
        if row.sticky and not UnitExists(row.unit) then SetSticky(row, false)
        elseif row.sticky and IsDead(row.unit) then SetSticky(row, false, true) end
        RefreshRow(row)
    end
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
    elseif cmd == "test" then
        if InCombatLockdown() then Say("aperçu impossible en combat.") return end
        SetTestMode(not testMode)
        RefreshOptions()
        Say(testMode and "aperçu avec des cibles fictives (/dtp test pour l'arrêter)." or "aperçu arrêté.")
    elseif cmd == "debug" then
        -- fonds colorés (bleu = en-tête, rouge = icônes, vert = keep), jetons npN, journal
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
        Say("/dtp (réglages), /dtp test (aperçu), /dtp lock, /dtp status (diagnostic), /dtp debug")
    end
end
