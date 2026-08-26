-- ============================================================
--  TRPcomm MANAGER | Автор: Богдан Номинов
--  Актуальная версия: 1.0
-- ============================================================

imgui = require 'imgui'
fa = require 'faIcons'
fa_glyph_ranges = imgui.ImGlyphRanges({ fa.min_range, fa.max_range })
fa_font = nil
fa_font_large = nil
arial_font = nil
arial_font_small = nil
arial_font_failed = false
encoding = require 'encoding'
encoding.default = 'CP1251'
u8 = encoding.UTF8
inicfg = require 'inicfg'
sampev = require 'samp.events'
requests = require 'requests'
cjson = require 'cjson.safe'

local GCAL_ID = "e750c65e6ebd96513d62dca03f7b23a0746137364a24d4daba502a4e555756bc@group.calendar.google.com"
local GCAL_API_KEY = "AIzaSyBtsyCi9A0ikrclVl919OfPC2z5rlaHZs4"
local TG_BOT_TOKEN = "8515415643:AAEOzuIFq1gJdWeRY27Ux4ItbdHzI9UOUEI"
local TG_CHAT_ID = "-1003174705842"
local TG_THREAD_ID = "9"

-- ============================================================
--  АВТООБНОВЛЕНИЕ
-- ============================================================
SCRIPT_VERSION = "1.0"
UPDATE_MANIFEST_URL = "https://raw.githubusercontent.com/ТВОЙ_ЮЗЕР/ТВОЙ_РЕПО/main/version.txt"
local UPDATE_TEMP_PATH = getWorkingDirectory() .. "\\moonloader\\trpcomm_update_manifest.txt"

local function parseVersion(v)
    local parts = {}
    for num in v:gmatch("%d+") do
        parts[#parts + 1] = tonumber(num)
    end
    return parts
end

local function isNewerVersion(remote, current)
    local r, c = parseVersion(remote), parseVersion(current)
    for i = 1, math.max(#r, #c) do
        local rv, cv = r[i] or 0, c[i] or 0
        if rv > cv then return true end
        if rv < cv then return false end
    end
    return false
end

local function checkForUpdates()
    downloadUrlToFile(UPDATE_MANIFEST_URL, UPDATE_TEMP_PATH, function(id, status)
        if status ~= 6 then return end

        local f = io.open(UPDATE_TEMP_PATH, "r")
        if not f then return end
        local remoteVersion = f:read("*l")
        local downloadUrl = f:read("*l")
        f:close()
        os.remove(UPDATE_TEMP_PATH)
        if not remoteVersion or not downloadUrl then return end

        if isNewerVersion(remoteVersion, SCRIPT_VERSION) then
            sampAddChatMessage('{5B85C4}[TRPcomm] {FFFFFF}Найдена новая версия ' .. remoteVersion .. ', скачиваю...', -1)
            downloadUrlToFile(downloadUrl, thisScript().path, function(id2, status2)
                if status2 == 6 then
                    sampAddChatMessage('{5B85C4}[TRPcomm] {FFFFFF}Обновление скачано! Перезайди на сервер (или F4 -> reload), чтобы применить.', -1)
                else
                    sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Не удалось скачать обновление.', -1)
                end
            end)
        end
    end)
end

local ffi = require 'ffi'
ffi.cdef[[
    typedef struct { unsigned long dwLowDateTime; unsigned long dwHighDateTime; } FILETIME;
    typedef struct {
        unsigned long dwFileAttributes;
        FILETIME ftCreationTime;
        FILETIME ftLastAccessTime;
        FILETIME ftLastWriteTime;
        unsigned long nFileSizeHigh;
        unsigned long nFileSizeLow;
        unsigned long dwReserved0;
        unsigned long dwReserved1;
        char cFileName[260];
        char cAlternateFileName[14];
    } WIN32_FIND_DATAA;
    void* FindFirstFileA(const char* lpFileName, WIN32_FIND_DATAA* lpFindFileData);
    bool  FindNextFileA(void* hFindFile, WIN32_FIND_DATAA* lpFindFileData);
    bool  FindClose(void* hFindFile);
]]

local function findFilesByMask(mask)
    local result = {}
    local data = ffi.new("WIN32_FIND_DATAA")
    local handle = ffi.C.FindFirstFileA(mask, data)
    if handle == nil or ffi.cast("intptr_t", handle) == -1 then
        return result
    end
    repeat
        local name = ffi.string(data.cFileName)
        if name ~= "." and name ~= ".." then
            local mtime = data.ftLastWriteTime.dwHighDateTime * 4294967296.0 + data.ftLastWriteTime.dwLowDateTime
            result[#result + 1] = { name = name, mtime = mtime }
        end
    until not ffi.C.FindNextFileA(handle, data)
    ffi.C.FindClose(handle)
    return result
end

-- ============================================================
--  ТЕМЫ ОФОРМЛЕНИЯ
-- ============================================================
local themes = {
    {
        name       = u8"TRPcomm (синяя)",
        windowBg   = imgui.ImVec4(0.05, 0.08, 0.14, 0.97),
        titleBg    = imgui.ImVec4(0.196, 0.349, 0.573, 1.00),
        panelBg    = imgui.ImVec4(0.08, 0.13, 0.22, 1.00),
        button     = imgui.ImVec4(0.196, 0.349, 0.573, 1.00),
        buttonHov  = imgui.ImVec4(0.27, 0.45, 0.68, 1.00),
        buttonAct  = imgui.ImVec4(0.14, 0.26, 0.44, 1.00),
        header     = imgui.ImVec4(0.196, 0.349, 0.573, 1.00),
        headerHov  = imgui.ImVec4(0.27, 0.45, 0.68, 1.00),
        headerAct  = imgui.ImVec4(0.14, 0.26, 0.44, 1.00),
        frameBg    = imgui.ImVec4(0.09, 0.14, 0.23, 1.00),
        border     = imgui.ImVec4(0.30, 0.45, 0.65, 0.45),
        accent     = imgui.ImVec4(0.42, 0.62, 0.92, 1.00),
        text       = imgui.ImVec4(0.92, 0.95, 1.00, 1.00),
        textDim    = imgui.ImVec4(0.55, 0.63, 0.75, 1.00),
    },

    -- 1. Кровавая (красная)
    {
        name       = u8"Кровавая",
        windowBg   = imgui.ImVec4(0.08, 0.05, 0.05, 0.97),
        titleBg    = imgui.ImVec4(0.50, 0.15, 0.15, 1.00),
        panelBg    = imgui.ImVec4(0.14, 0.08, 0.08, 1.00),
        button     = imgui.ImVec4(0.50, 0.15, 0.15, 1.00),
        buttonHov  = imgui.ImVec4(0.65, 0.20, 0.20, 1.00),
        buttonAct  = imgui.ImVec4(0.40, 0.10, 0.10, 1.00),
        header     = imgui.ImVec4(0.50, 0.15, 0.15, 1.00),
        headerHov  = imgui.ImVec4(0.65, 0.20, 0.20, 1.00),
        headerAct  = imgui.ImVec4(0.40, 0.10, 0.10, 1.00),
        frameBg    = imgui.ImVec4(0.18, 0.10, 0.10, 1.00),
        border     = imgui.ImVec4(0.65, 0.25, 0.25, 0.45),
        accent     = imgui.ImVec4(0.90, 0.30, 0.30, 1.00),
        text       = imgui.ImVec4(1.00, 0.92, 0.92, 1.00),
        textDim    = imgui.ImVec4(0.75, 0.55, 0.55, 1.00),
    },
    
    -- 2. Изумрудная (Зеленые и лесные оттенки)
    {
        name       = u8"Изумрудная",
        windowBg   = imgui.ImVec4(0.05, 0.08, 0.06, 0.97),
        titleBg    = imgui.ImVec4(0.15, 0.45, 0.25, 1.00),
        panelBg    = imgui.ImVec4(0.08, 0.13, 0.09, 1.00),
        button     = imgui.ImVec4(0.15, 0.45, 0.25, 1.00),
        buttonHov  = imgui.ImVec4(0.20, 0.55, 0.32, 1.00),
        buttonAct  = imgui.ImVec4(0.10, 0.35, 0.18, 1.00),
        header     = imgui.ImVec4(0.15, 0.45, 0.25, 1.00),
        headerHov  = imgui.ImVec4(0.20, 0.55, 0.32, 1.00),
        headerAct  = imgui.ImVec4(0.10, 0.35, 0.18, 1.00),
        frameBg    = imgui.ImVec4(0.10, 0.16, 0.12, 1.00),
        border     = imgui.ImVec4(0.25, 0.55, 0.35, 0.45),
        accent     = imgui.ImVec4(0.35, 0.85, 0.45, 1.00),
        text       = imgui.ImVec4(0.92, 1.00, 0.95, 1.00),
        textDim    = imgui.ImVec4(0.55, 0.75, 0.60, 1.00),
    },

    -- 3. Аметистовая (Неоново-фиолетовая)
    {
        name       = u8"Аметистовая",
        windowBg   = imgui.ImVec4(0.06, 0.05, 0.09, 0.97),
        titleBg    = imgui.ImVec4(0.40, 0.20, 0.60, 1.00),
        panelBg    = imgui.ImVec4(0.10, 0.08, 0.15, 1.00),
        button     = imgui.ImVec4(0.40, 0.20, 0.60, 1.00),
        buttonHov  = imgui.ImVec4(0.50, 0.25, 0.75, 1.00),
        buttonAct  = imgui.ImVec4(0.30, 0.15, 0.45, 1.00),
        header     = imgui.ImVec4(0.40, 0.20, 0.60, 1.00),
        headerHov  = imgui.ImVec4(0.50, 0.25, 0.75, 1.00),
        headerAct  = imgui.ImVec4(0.30, 0.15, 0.45, 1.00),
        frameBg    = imgui.ImVec4(0.13, 0.10, 0.19, 1.00),
        border     = imgui.ImVec4(0.55, 0.35, 0.75, 0.45),
        accent     = imgui.ImVec4(0.70, 0.40, 0.95, 1.00),
        text       = imgui.ImVec4(0.96, 0.92, 1.00, 1.00),
        textDim    = imgui.ImVec4(0.65, 0.55, 0.75, 1.00),
    },

    -- 4. Янтарная (Современный темный дизайн)
    {
        name       = u8"Янтарная",
        windowBg   = imgui.ImVec4(0.06, 0.06, 0.06, 0.98),
        titleBg    = imgui.ImVec4(0.08, 0.08, 0.08, 1.00),
        panelBg    = imgui.ImVec4(0.09, 0.09, 0.09, 1.00),
        button     = imgui.ImVec4(0.65, 0.35, 0.05, 1.00),
        buttonHov  = imgui.ImVec4(0.80, 0.45, 0.10, 1.00),
        buttonAct  = imgui.ImVec4(0.45, 0.22, 0.03, 1.00),
        header     = imgui.ImVec4(0.18, 0.12, 0.06, 1.00),
        headerHov  = imgui.ImVec4(0.28, 0.18, 0.08, 1.00),
        headerAct  = imgui.ImVec4(0.12, 0.08, 0.04, 1.00),
        frameBg    = imgui.ImVec4(0.12, 0.12, 0.12, 1.00),
        border     = imgui.ImVec4(0.70, 0.40, 0.05, 0.35),
        accent     = imgui.ImVec4(0.95, 0.60, 0.15, 1.00),
        text       = imgui.ImVec4(0.95, 0.92, 0.88, 1.00),
        textDim    = imgui.ImVec4(0.55, 0.50, 0.45, 1.00),
    },

    -- 5. Строгая монохромная (Черно-бело-серая, минимализм)
    {
        name       = u8"Монохромная",
        windowBg   = imgui.ImVec4(0.06, 0.06, 0.06, 0.97),
        titleBg    = imgui.ImVec4(0.20, 0.20, 0.20, 1.00),
        panelBg    = imgui.ImVec4(0.10, 0.10, 0.10, 1.00),
        button     = imgui.ImVec4(0.25, 0.25, 0.25, 1.00),
        buttonHov  = imgui.ImVec4(0.35, 0.35, 0.35, 1.00),
        buttonAct  = imgui.ImVec4(0.15, 0.15, 0.15, 1.00),
        header     = imgui.ImVec4(0.25, 0.25, 0.25, 1.00),
        headerHov  = imgui.ImVec4(0.35, 0.35, 0.35, 1.00),
        headerAct  = imgui.ImVec4(0.15, 0.15, 0.15, 1.00),
        frameBg    = imgui.ImVec4(0.14, 0.14, 0.14, 1.00),
        border     = imgui.ImVec4(0.40, 0.40, 0.40, 0.45),
        accent     = imgui.ImVec4(0.85, 0.85, 0.85, 1.00),
        text       = imgui.ImVec4(0.95, 0.95, 0.95, 1.00),
        textDim    = imgui.ImVec4(0.60, 0.60, 0.60, 1.00),
    },
}

currentThemeIdx = 1
local function getTheme() return themes[currentThemeIdx] end

THEME_COLOR_COUNT = 13 -- сколько цветов пушим в pushThemeColors(), для симметричного PopStyleColor
THEME_ROUNDING_COUNT = 4 -- сколько StyleVar пушим для скруглений, для симметричного PopStyleVar

local function pushThemeColors()
    local t = getTheme()
    imgui.PushStyleColor(imgui.Col.WindowBg,       t.windowBg)
    imgui.PushStyleColor(imgui.Col.ChildWindowBg,  t.panelBg)
    imgui.PushStyleColor(imgui.Col.TitleBgActive,  t.titleBg)
    imgui.PushStyleColor(imgui.Col.Button,         t.button)
    imgui.PushStyleColor(imgui.Col.ButtonHovered,  t.buttonHov)
    imgui.PushStyleColor(imgui.Col.ButtonActive,   t.buttonAct)
    imgui.PushStyleColor(imgui.Col.Header,         t.header)
    imgui.PushStyleColor(imgui.Col.HeaderHovered,  t.headerHov)
    imgui.PushStyleColor(imgui.Col.HeaderActive,   t.headerAct)
    imgui.PushStyleColor(imgui.Col.FrameBg,        t.frameBg)
    imgui.PushStyleColor(imgui.Col.Border,         t.border)
    imgui.PushStyleColor(imgui.Col.Text,           t.text)
    imgui.PushStyleColor(imgui.Col.ScrollbarGrab,  t.accent)
end

local function pushThemeRounding()
    imgui.PushStyleVar(imgui.StyleVar.WindowRounding,       12.0)
    imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding,  10.0)
    imgui.PushStyleVar(imgui.StyleVar.FrameRounding,        8.0)
    imgui.PushStyleVar(imgui.StyleVar.GrabMinSize,          8.0)
end

-- ============================================================
--  СОСТОЯНИЕ ОКНА
-- ============================================================
local main_window_state = imgui.ImBool(false)
-- Открытые вкладки
local open_tabs = {
    { kind = "home", title = u8"Домашняя страница", closable = false },
}
active_tab_idx = 1

local function openTab(kind, title)
    for i, tb in ipairs(open_tabs) do
        if tb.kind == kind then
            active_tab_idx = i
            return
        end
    end
    open_tabs[#open_tabs + 1] = { kind = kind, title = title, closable = true }
    active_tab_idx = #open_tabs
end

local function closeTab(idx)
    if not open_tabs[idx] or not open_tabs[idx].closable then return end
    table.remove(open_tabs, idx)
    if active_tab_idx >= idx then
        active_tab_idx = math.max(1, active_tab_idx - 1)
    end
end

-- ============================================================
--  НАСТРОЙКИ / КОНФИГ (сохранение в ini)
-- ============================================================
CONFIG_DIR  = "moonloader\\config\\TRPcomm Manager Config"
CONFIG_PATH = "moonloader\\config\\TRPcomm Manager Config\\trpcomm-manager.ini"
NOTES_DIR        = "moonloader\\config\\TRPcomm Manager Config\\notes"
NOTES_INDEX_PATH = "moonloader\\config\\TRPcomm Manager Config\\notes\\index.ini"
REPORTS_DIR        = "moonloader\\config\\TRPcomm Manager Config\\reports"
REPORTS_INDEX_PATH = "moonloader\\config\\TRPcomm Manager Config\\reports\\index.ini"
TRACKER_REPORTS_DIR        = "moonloader\\config\\TRPcomm Manager Config\\tracker_reports"
TRACKER_REPORTS_INDEX_PATH = "moonloader\\config\\TRPcomm Manager Config\\tracker_reports\\index.ini"
local addReport -- форвард-объявление

local defaultSettings = {
    settings = {
        theme        = "1",
        hotkey_alt   = "true",
        hotkey_ctrl  = "false",
        hotkey_shift = "false",
        hotkey_key   = "80", -- P
        hotkey2_alt   = "false",
        hotkey2_ctrl  = "false",
        hotkey2_shift = "false",
        hotkey2_key   = "0",
        radio_freq   = "",
        radio_pass   = "",
        teleport_pass = "",
        send_as_document = "false",
    }
}

if not doesDirectoryExist(CONFIG_DIR) then createDirectory(CONFIG_DIR) end

local f = io.open(CONFIG_PATH, "r")
if f then
    f:close()
else
    local fw = io.open(CONFIG_PATH, "w")
    if fw then
        fw:write("[settings]\n")
        fw:write("theme=1\n")
        fw:write("hotkey_alt=true\n")
        fw:write("hotkey_ctrl=false\n")
        fw:write("hotkey_shift=false\n")
        fw:write("hotkey_key=80\n")
        fw:write("radio_freq=\n")
        fw:write("radio_pass=\n")
        fw:write("teleport_pass=\n")
        fw:write("send_as_document=false\n")
        fw:close()
    end
end

local mainIni = inicfg.load(defaultSettings, CONFIG_PATH) or defaultSettings

if not doesDirectoryExist(NOTES_DIR) then createDirectory(NOTES_DIR) end
if not doesDirectoryExist(REPORTS_DIR) then createDirectory(REPORTS_DIR) end
if not doesDirectoryExist(TRACKER_REPORTS_DIR) then createDirectory(TRACKER_REPORTS_DIR) end

local function boolFromSetting(v)
    return v == "true" or v == true
end

currentThemeIdx = tonumber(mainIni.settings.theme) or currentThemeIdx
local selected_theme_combo = imgui.ImInt(currentThemeIdx - 1)

local KEY_NAMES = {
    [1]="ЛКМ",[2]="ПКМ",[4]="СКМ",
    [8]="Backspace",[9]="Tab",[13]="Enter",[27]="Esc",[32]="Space",
    [112]="F1",[113]="F2",[114]="F3",[115]="F4",[116]="F5",[117]="F6",
    [118]="F7",[119]="F8",[120]="F9",[121]="F10",[122]="F11",[123]="F12",
    [186]=";",[187]="=",[188]=",",[189]="-",[190]=".",[191]="/",[192]="`",
    [219]="[",[220]="\\",[221]="]",[222]="'",
}
for i = 48, 57 do KEY_NAMES[i] = string.char(i) end -- 0-9
for i = 65, 90 do KEY_NAMES[i] = string.char(i) end -- A-Z

hotkey_alt   = imgui.ImBool(boolFromSetting(mainIni.settings.hotkey_alt))
hotkey_ctrl  = imgui.ImBool(boolFromSetting(mainIni.settings.hotkey_ctrl))
hotkey_shift = imgui.ImBool(boolFromSetting(mainIni.settings.hotkey_shift))
hotkey_key   = imgui.ImInt(tonumber(mainIni.settings.hotkey_key) or 0x50)
hotkey_display = imgui.ImBuffer("", 64)
waiting_for_key = false

local function updateHotkeyDisplay()
    local parts = {}
    if hotkey_alt.v   then parts[#parts+1] = "Alt"   end
    if hotkey_ctrl.v  then parts[#parts+1] = "Ctrl"  end
    if hotkey_shift.v then parts[#parts+1] = "Shift" end
    parts[#parts+1] = KEY_NAMES[hotkey_key.v] or ("VK_" .. hotkey_key.v)
    hotkey_display.v = table.concat(parts, " + ")
end
updateHotkeyDisplay()

hotkey2_alt   = imgui.ImBool(boolFromSetting(mainIni.settings.hotkey2_alt))
hotkey2_ctrl  = imgui.ImBool(boolFromSetting(mainIni.settings.hotkey2_ctrl))
hotkey2_shift = imgui.ImBool(boolFromSetting(mainIni.settings.hotkey2_shift))
hotkey2_key   = imgui.ImInt(tonumber(mainIni.settings.hotkey2_key) or 0)
hotkey2_display = imgui.ImBuffer("", 64)
waiting_for_key2 = false

local function updateHotkey2Display()
    if hotkey2_key.v == 0 then
        hotkey2_display.v = u8"Не назначено"
        return
    end 
    local parts = {}
    if hotkey2_alt.v   then parts[#parts+1] = "Alt"   end
    if hotkey2_ctrl.v  then parts[#parts+1] = "Ctrl"  end
    if hotkey2_shift.v then parts[#parts+1] = "Shift" end
    parts[#parts+1] = KEY_NAMES[hotkey2_key.v] or ("VK_" .. hotkey2_key.v)
    hotkey2_display.v = table.concat(parts, " + ")
end
updateHotkey2Display()

radio_freq = imgui.ImBuffer(u8(mainIni.settings.radio_freq or ""), 32)
radio_pass = imgui.ImBuffer(u8(mainIni.settings.radio_pass or ""), 32)
teleport_pass = imgui.ImBuffer(u8(mainIni.settings.teleport_pass or ""), 32)
send_as_document = imgui.ImBool(boolFromSetting(mainIni.settings.send_as_document))

local function saveSettings()
    local cfg = {
        settings = {
            theme        = tostring(currentThemeIdx),
            hotkey_alt   = tostring(hotkey_alt.v),
            hotkey_ctrl  = tostring(hotkey_ctrl.v),
            hotkey_shift = tostring(hotkey_shift.v),
            hotkey_key   = tostring(hotkey_key.v),
            hotkey2_alt   = tostring(hotkey2_alt.v),
            hotkey2_ctrl  = tostring(hotkey2_ctrl.v),
            hotkey2_shift = tostring(hotkey2_shift.v),
            hotkey2_key   = tostring(hotkey2_key.v),
            radio_freq   = u8:decode(radio_freq.v),
            radio_pass   = u8:decode(radio_pass.v),
            teleport_pass = u8:decode(teleport_pass.v),
            send_as_document = tostring(send_as_document.v),
        }
    }
    inicfg.save(cfg, CONFIG_PATH)
    mainIni = cfg
end

-- ============================================================
--  ЗАГРУЗКА ИЗОБРАЖЕНИЙ СКИНОВ
-- ============================================================
-- moonloader/resource/TRPcomm Manager/images/skins/skin_<id>.png
local IMAGES_DIR = getWorkingDirectory() .. "\\resource\\TRPcomm Manager\\images\\skins\\"
local skin_textures = {} -- кэш: [skinId] = texture | false (если файл не найден)

local function loadSkinTexture(skinId)
    if skin_textures[skinId] ~= nil then
        return skin_textures[skinId] or nil
    end
    local path = IMAGES_DIR .. "skin_" .. tostring(skinId) .. ".png"
    if doesFileExist(path) then
        local tex = imgui.CreateTextureFromFile(path)
        skin_textures[skinId] = tex
        return tex
    end
    skin_textures[skinId] = false
    return nil
end

-- ============================================================
--  ВСПОМОГАТЕЛЬНОЕ
-- ============================================================
local function drawInfoCard(t, label, value, thumbTexture)
    imgui.BeginChild("card_" .. label, imgui.ImVec2(0, 56), true)
        imgui.TextColored(t.textDim, label)
        imgui.TextColored(t.text, value)
        if thumbTexture then
            imgui.SameLine(imgui.GetWindowWidth() - 50)
            imgui.SetCursorPosY(4)
            imgui.Image(thumbTexture, imgui.ImVec2(40, 40))
        end
    imgui.EndChild()
end

-- ============================================================
--  ДОМАШНЯЯ СТРАНИЦА
-- ============================================================
trpcomm_logo_texture = nil
trpcomm_logo_checked = false

upcoming_event_name = u8"Пока не подключено"
upcoming_event_time = "--:--"

local function loadLogoTexture()
    if trpcomm_logo_checked then return trpcomm_logo_texture end
    trpcomm_logo_checked = true
    local path = getWorkingDirectory() .. "\\resource\\TRPcomm Manager\\images\\trpcomm-logo.png"
    if doesFileExist(path) then
        trpcomm_logo_texture = imgui.CreateTextureFromFile(path)
    end
    return trpcomm_logo_texture
end

local function centeredLabel(id, text, width, height, colorOverride)
    local textPushed = 0
    if colorOverride then
        imgui.PushStyleColor(imgui.Col.Text, colorOverride)
        textPushed = 1
    end
    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0, 0, 0, 0))
    imgui.Button(text .. "##" .. id, imgui.ImVec2(width, height))
    imgui.PopStyleColor(3)
    if textPushed > 0 then imgui.PopStyleColor(textPushed) end
end

-- ============================================================
--  HR ОТДЕЛ: Объявления
-- ============================================================
AD_TEXT_MAX = 120 -- лимит символов

local AD_CITIES = {
    { code = "ls", name = u8"Los Santos" },
    { code = "sf", name = u8"San Fierro" },
    { code = "lv", name = u8"Las Venturas" },
}
ad_city_idx = imgui.ImInt(0)
ad_text = imgui.ImBuffer("", AD_TEXT_MAX)
ad_pending = false      -- ждём ли сейчас диалогов после отправки команды
ad_pending_text = ""    -- текст, который подставим во второй диалог (CP1251, без u8)

local function formatMMSS(sec)
    if sec < 0 then sec = 0 end
    sec = math.floor(sec)
    local m = math.floor(sec / 60)
    local s = sec % 60
    return string.format("%02d:%02d", m, s)
end

-- ---------- Список объявлений (хранится в moonloader\config\TRPcomm Manager Config\ads.ini) ----------
local ADS_LIST_PATH = "moonloader\\config\\TRPcomm Manager Config\\ads.ini"

do
    local f = io.open(ADS_LIST_PATH, "r")
    if f then
        f:close()
    else
        local fw = io.open(ADS_LIST_PATH, "w")
        if fw then
            fw:write("[ads]\ncount=0\n")
            fw:close()
        end
    end
end

local defaultAdsIndex = { ads = { count = "0" } }
local adsIndexIni = inicfg.load(defaultAdsIndex, ADS_LIST_PATH) or defaultAdsIndex
local ads_list = {} -- { {text=(CP1251), enabled=bool}, ... }

local function saveAdsList()
    local cfg = { ads = { count = tostring(#ads_list) } }
    for i, ad in ipairs(ads_list) do
        cfg.ads["ad" .. i .. "_text"]    = ad.text
        cfg.ads["ad" .. i .. "_enabled"] = tostring(ad.enabled)
    end
    inicfg.save(cfg, ADS_LIST_PATH)
    adsIndexIni = cfg
end

do
    local adsCount = tonumber(adsIndexIni.ads.count) or 0
    for i = 1, adsCount do
        local text = adsIndexIni.ads["ad" .. i .. "_text"]
        local enabledRaw = adsIndexIni.ads["ad" .. i .. "_enabled"]
        if text then
            ads_list[#ads_list + 1] = { text = text, enabled = boolFromSetting(enabledRaw) }
        end
    end
end

-- ---------- Форма добавления объявления ----------
local ad_add_form_open = false
local ad_new_text = imgui.ImBuffer("", AD_TEXT_MAX)

local function drawAdAddForm(t)
    if not ad_add_form_open then return end

    local sw, sh = getScreenResolution()
    imgui.SetNextWindowSize(imgui.ImVec2(420, 220), imgui.Cond.Always)
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))

    pushThemeColors()
    pushThemeRounding()

    local open = imgui.ImBool(true)
    imgui.Begin(u8"Новое объявление##ad_add_form", open,
        imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize)
    if not open.v then ad_add_form_open = false end

    imgui.TextColored(t.textDim, u8"Текст (до " .. AD_TEXT_MAX .. u8" символов):")
    imgui.PushItemWidth(-1)
    imgui.InputTextMultiline("##ad_new_text", ad_new_text, imgui.ImVec2(-1, 90))
    imgui.PopItemWidth()

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    if imgui.Button(u8"Добавить##ad_add_confirm", imgui.ImVec2(140, 30)) then
        local raw = u8:decode(ad_new_text.v)
        if raw ~= "" then
            ads_list[#ads_list + 1] = { text = raw, enabled = true }
            saveAdsList()
            ad_new_text.v = ""
            ad_add_form_open = false
        end
    end
    imgui.SameLine()
    if imgui.Button(u8"Отмена##ad_add_cancel", imgui.ImVec2(120, 30)) then
        ad_add_form_open = false
    end

    imgui.End()
    imgui.PopStyleVar(THEME_ROUNDING_COUNT)
    imgui.PopStyleColor(THEME_COLOR_COUNT)
end

-- ---------- Автоотправка по очереди ----------
ad_auto_send = imgui.ImBool(false)
ad_interval_minutes = imgui.ImInt(30)
ad_next_send_time = 0
ad_rotation_idx = 0

local function sendAdNow(textRaw)
    ad_pending_text = textRaw
    ad_pending = true
    local city = AD_CITIES[ad_city_idx.v + 1].code
    sampSendChat("/sms radio" .. city)
end

local function triggerNextAdSend()
    if #ads_list == 0 then return end
    for i = 1, #ads_list do
        local idx = ((ad_rotation_idx + i - 1) % #ads_list) + 1
        local ad = ads_list[idx]
        if ad.enabled then
            ad_rotation_idx = idx
            sendAdNow(ad.text)
            return
        end
    end
end

local hr_subtab = "ads" -- "ads" | "messages" | "calendar"

local function drawHRAdsTab(t)
    imgui.TextColored(t.accent, u8"Быстрая отправка")
    imgui.Spacing()

    imgui.TextColored(t.textDim, u8"Текст объявления (до " .. AD_TEXT_MAX .. u8" символов):")
    imgui.PushItemWidth(-1)
    imgui.InputTextMultiline("##ad_text", ad_text, imgui.ImVec2(-1, 80))
    imgui.PopItemWidth()

    imgui.Spacing()
    imgui.TextColored(t.textDim, u8"Город:")
    local cityNames = {}
    for _, c in ipairs(AD_CITIES) do cityNames[#cityNames + 1] = c.name end
    imgui.PushItemWidth(200)
    imgui.Combo("##ad_city", ad_city_idx, cityNames)
    imgui.PopItemWidth()

    imgui.Spacing()

    if ad_pending then
        imgui.TextColored(t.textDim, u8"Ожидание диалогов сервера...")
    else
        if imgui.Button(fa.ICON_BULLHORN .. u8" Отправить объявление##ad_send", imgui.ImVec2(220, 32)) then
            local textRaw = u8:decode(ad_text.v)
            if textRaw == "" then
                sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Сначала введи текст объявления.', -1)
            else
                sendAdNow(textRaw)
            end
        end
    end

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    imgui.TextColored(t.accent, u8"Список объявлений")
    imgui.SameLine(imgui.GetWindowWidth() - 140)
    if imgui.Button(u8"+ Добавить##ad_add_open", imgui.ImVec2(130, 26)) then
        ad_add_form_open = true
    end
    imgui.Spacing()

    -- ---------- Полупрозрачные подсказки из календаря — прямо над списком ----------
    local faded = imgui.ImVec4(t.textDim.x, t.textDim.y, t.textDim.z, 0.55)
    for i, ev in ipairs(calendar_events) do
        if ev.location and ev.location ~= "" then
            local alreadyAdded = false
            for _, ad in ipairs(ads_list) do
                if ad.text == u8:decode(ev.location) then
                    alreadyAdded = true
                    break
                end
            end

            if not alreadyAdded then
                imgui.PushID("cal_suggest_" .. i)
                imgui.PushStyleColor(imgui.Col.Text, faded)
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(t.buttonHov.x, t.buttonHov.y, t.buttonHov.z, 0.35))
                if imgui.Button(ev.location .. u8"   —   Добавить?##cal_suggest_btn", imgui.ImVec2(-1, 24)) then
                    local raw = u8:decode(ev.location)
                    if #raw > AD_TEXT_MAX then raw = raw:sub(1, AD_TEXT_MAX) end
                    ads_list[#ads_list + 1] = { text = raw, enabled = true }
                    saveAdsList()
                end
                imgui.PopStyleColor(3)
                imgui.PopID()
            end
        end
    end

    if #ads_list == 0 then
        imgui.TextColored(t.textDim, u8"Список пуст.")
    end

    local deleteAdIdx = nil
    for i, ad in ipairs(ads_list) do
        imgui.PushID("ad_" .. i)

        local en = imgui.ImBool(ad.enabled)
        if imgui.Checkbox("##ad_enabled", en) then
            ad.enabled = en.v
            saveAdsList()
        end
        imgui.SameLine()

        local previewRaw = ad.text:sub(1, 40)
        if #ad.text > 40 then previewRaw = previewRaw .. "..." end
        if imgui.Button(u8(previewRaw) .. "##ad_row_send", imgui.ImVec2(300, 28)) then
            if not ad_pending then
                sendAdNow(ad.text)
            end
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip(u8"ЛКМ — Отправить объявление | Колёсико — Удалить объявление")
        end
        if imgui.IsItemClicked(2) then
            deleteAdIdx = i
        end
        imgui.SameLine()
        if imgui.Button(fa.ICON_TIMES .. "##ad_delete", imgui.ImVec2(28, 28)) then
            deleteAdIdx = i
        end

        imgui.PopID()
        imgui.Spacing()
    end
    if deleteAdIdx then
        table.remove(ads_list, deleteAdIdx)
        saveAdsList()
    end

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    imgui.TextColored(t.accent, u8"Автоотправка по очереди")
    imgui.Spacing()

    if imgui.Checkbox(u8"Включить автоотправку", ad_auto_send) then
        if ad_auto_send.v then
            ad_next_send_time = os.time() + (ad_interval_minutes.v * 60)
        end
    end

    imgui.TextColored(t.textDim, u8"Интервал (минут):")
    imgui.PushItemWidth(100)
    imgui.InputInt("##ad_interval", ad_interval_minutes)
    imgui.PopItemWidth()

    if ad_auto_send.v then
        imgui.TextColored(t.textDim, u8"Следующая отправка через: " .. formatMMSS(ad_next_send_time - os.time()))
    end
end

local function drawHRMessagesTab(t)
    imgui.TextColored(t.textDim, u8"Раздел в разработке.")
end

calendar_events = {}     -- { {summary=, description=, location=, y=,mo=,d=,h=,mi=, isAllDay=bool}, ... }
calendar_loading = false
calendar_loaded_once = false
calendar_view_year = tonumber(os.date("%Y"))
calendar_view_month = tonumber(os.date("%m"))

CAL_CELL_W = 118
CAL_CELL_H = 56
CAL_GAP = 4

WEEKDAY_NAMES = { u8"Пн", u8"Вт", u8"Ср", u8"Чт", u8"Пт", u8"Сб", u8"Вс" }
MONTH_NAMES = {
    u8"Январь", u8"Февраль", u8"Март", u8"Апрель", u8"Май", u8"Июнь",
    u8"Июль", u8"Август", u8"Сентябрь", u8"Октябрь", u8"Ноябрь", u8"Декабрь",
}

-- Разбирает "2026-08-20T18:00:00+03:00" или "2026-08-20" (весь день)
local function parseISODateTime(iso)
    if not iso then return nil end
    local y, mo, d, h, mi = iso:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+)")
    if y then
        return tonumber(y), tonumber(mo), tonumber(d), tonumber(h), tonumber(mi)
    end
    local y2, mo2, d2 = iso:match("(%d+)-(%d+)-(%d+)")
    if y2 then
        return tonumber(y2), tonumber(mo2), tonumber(d2), nil, nil
    end
    return nil
end

local function daysInMonth(year, month)
    local nextMonth, nextYear = month + 1, year
    if nextMonth > 12 then nextMonth = 1; nextYear = year + 1 end
    local t = os.time({ year = nextYear, month = nextMonth, day = 1, hour = 12 }) - 86400
    return tonumber(os.date("%d", t))
end

-- 0 = Понедельник ... 6 = Воскресенье
local function weekdayOfFirst(year, month)
    local t = os.time({ year = year, month = month, day = 1, hour = 12 })
    local wd = tonumber(os.date("%w", t)) -- 0=Вс..6=Сб
    return (wd + 6) % 7
end

local function fetchCalendarEvents()
    if GCAL_ID == "ВСТАВЬ_СЮДА_CALENDAR_ID" or GCAL_API_KEY == "ВСТАВЬ_СЮДА_API_KEY" then
        sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Calendar ID / API-ключ не заданы в коде скрипта.', -1)
        return
    end

    calendar_loading = true
    lua_thread.create(function()
        local timeMin = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time() - 90 * 86400) -- 90 дней назад
        local url = "https://www.googleapis.com/calendar/v3/calendars/"
            .. GCAL_ID:gsub(":", "%%3A")
            .. "/events?key=" .. GCAL_API_KEY
            .. "&singleEvents=true&orderBy=startTime&timeMin=" .. timeMin
            .. "&maxResults=250"

        local ok, response = pcall(requests.get, url, { timeout = 15 })
        calendar_loading = false
        calendar_loaded_once = true

        if not ok then
            sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Ошибка запроса к календарю: ' .. tostring(response), -1)
            return
        end

        if response.status_code ~= 200 then
            sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Google Calendar вернул ошибку ' .. tostring(response.status_code) .. ': ' .. tostring(response.text), -1)
            return
        end

        local data = cjson.decode(response.text)
        if not data or not data.items then
            sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Не удалось разобрать ответ календаря.', -1)
            return
        end

        calendar_events = {}
        for _, item in ipairs(data.items) do
            -- summary/description/location приходят от Google уже в UTF-8 — оборачивать в u8() НЕ нужно
            local startRaw = item.start and (item.start.dateTime or item.start.date)
            local isAllDay = item.start and item.start.date ~= nil
            local y, mo, d, h, mi = parseISODateTime(startRaw)
            calendar_events[#calendar_events + 1] = {
                summary     = (item.summary and item.summary ~= "") and item.summary or u8"Без названия",
                description = item.description,
                location    = item.location,
                y = y, mo = mo, d = d, h = h, mi = mi,
                isAllDay = isAllDay,
            }
        end

        local nowTime = os.time()
        local nextEvent = nil
        for _, ev in ipairs(calendar_events) do
            if ev.y then
                local evTime = os.time({
                    year = ev.y, month = ev.mo, day = ev.d,
                    hour = ev.h or 23, min = ev.mi or 59, sec = 0,
                })
                if evTime >= nowTime then
                    nextEvent = ev
                    break
                end
            end
        end

        if nextEvent then
            upcoming_event_name = nextEvent.summary
            upcoming_event_time = nextEvent.h and string.format("%02d:%02d", nextEvent.h, nextEvent.mi) or u8"весь день"
        else
            upcoming_event_name = u8"Нет предстоящих ивентов"
            upcoming_event_time = "--:--"
        end

    end)
end

local function drawHRCalendarTab(t)
    if calendar_loading then
        imgui.TextColored(t.textDim, u8"Загрузка...")
        imgui.Spacing(); imgui.Separator(); imgui.Spacing()
    end

    if not calendar_loaded_once then
        imgui.TextColored(t.textDim, u8"Загрузка календаря...")
        return
    end

    -- ---------- Шапка: месяц + навигация ----------
    if imgui.Button(fa.ICON_ARROW_LEFT .. "##cal_prev", imgui.ImVec2(30, 26)) then
        calendar_view_month = calendar_view_month - 1
        if calendar_view_month < 1 then calendar_view_month = 12; calendar_view_year = calendar_view_year - 1 end
    end
    imgui.SameLine()
    imgui.Text(MONTH_NAMES[calendar_view_month] .. "  " .. calendar_view_year)
    imgui.SameLine()
    if imgui.Button(fa.ICON_ARROW_RIGHT .. "##cal_next", imgui.ImVec2(30, 26)) then
        calendar_view_month = calendar_view_month + 1
        if calendar_view_month > 12 then calendar_view_month = 1; calendar_view_year = calendar_view_year + 1 end
    end

    imgui.Spacing()

    -- ---------- Заголовки дней недели ----------
    for col = 1, 7 do
        if col > 1 then imgui.SameLine(0, CAL_GAP) end
        imgui.BeginChild("cal_wd_" .. col, imgui.ImVec2(CAL_CELL_W, 20), false)
            imgui.TextColored(t.textDim, WEEKDAY_NAMES[col])
        imgui.EndChild()
    end

    imgui.Spacing()

    -- ---------- Сетка дней ----------
    local firstWeekday = weekdayOfFirst(calendar_view_year, calendar_view_month)
    local totalDays = daysInMonth(calendar_view_year, calendar_view_month)
    local totalRows = math.ceil((firstWeekday + totalDays) / 7)

    for row = 0, totalRows - 1 do
        for col = 0, 6 do
            if col > 0 then imgui.SameLine(0, CAL_GAP) end
            local cellDay = row * 7 + col - firstWeekday + 1
            imgui.PushID("cal_cell_" .. row .. "_" .. col)

            if cellDay >= 1 and cellDay <= totalDays then
                local dayEvents = {}
                for _, ev in ipairs(calendar_events) do
                    if ev.y == calendar_view_year and ev.mo == calendar_view_month and ev.d == cellDay then
                        dayEvents[#dayEvents + 1] = ev
                    end
                end

                local hasEvents = #dayEvents > 0
                local pushed = 0
                if hasEvents then
                    local todayY  = tonumber(os.date("%Y"))
                    local todayMo = tonumber(os.date("%m"))
                    local todayD  = tonumber(os.date("%d"))
                    local isPast = (calendar_view_year < todayY)
                        or (calendar_view_year == todayY and calendar_view_month < todayMo)
                        or (calendar_view_year == todayY and calendar_view_month == todayMo and cellDay < todayD)

                    if isPast then
                        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.30, 0.30, 0.32, 1.0))
                        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.36, 0.36, 0.38, 1.0))
                    else
                        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.20, 0.65, 0.35, 1.0))
                        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.28, 0.75, 0.45, 1.0))
                    end
                    pushed = 2
                end

                imgui.Button(tostring(cellDay), imgui.ImVec2(CAL_CELL_W, CAL_CELL_H))

                if pushed > 0 then imgui.PopStyleColor(pushed) end

                if hasEvents and imgui.IsItemHovered() then
                    local white = imgui.ImVec4(1, 1, 1, 1)
                    imgui.BeginTooltip()
                    imgui.PushTextWrapPos(350)

                    for idx, ev in ipairs(dayEvents) do
                        if idx > 1 then imgui.Separator() end

                        imgui.TextColored(t.accent, u8"«")
                        imgui.SameLine(0, 0)
                        imgui.TextColored(white, ev.summary)
                        imgui.SameLine(0, 0)
                        imgui.TextColored(t.accent, u8"»")

                        if ev.description and ev.description ~= "" then
                            imgui.TextColored(t.accent, u8"Описание:")
                            imgui.PushStyleColor(imgui.Col.Text, white)
                            imgui.TextWrapped(ev.description)
                            imgui.PopStyleColor()
                        end

                        imgui.TextColored(t.accent, u8"Время:")
                        imgui.SameLine()
                        imgui.TextColored(white, ev.h and string.format("%02d:%02d", ev.h, ev.mi) or u8"Весь день")
                    end

                    imgui.PopTextWrapPos()
                    imgui.EndTooltip()
                end
            else
                imgui.Dummy(imgui.ImVec2(CAL_CELL_W, CAL_CELL_H))
            end

            imgui.PopID()
        end
        imgui.Spacing()
    end
end

local function drawHRTab(t)
    imgui.TextColored(t.accent, fa.ICON_BULLHORN .. u8" HR ОТДЕЛ")
    imgui.Spacing()

    local pushed = 0
    if hr_subtab == "ads" then
        imgui.PushStyleColor(imgui.Col.Button, t.accent)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, t.accent)
        pushed = 2
    end
    if imgui.Button(u8"Реклама##hr_sub_ads", imgui.ImVec2(140, 30)) then
        hr_subtab = "ads"
    end
    if pushed > 0 then imgui.PopStyleColor(pushed) end

    imgui.SameLine()

    pushed = 0
    if hr_subtab == "messages" then
        imgui.PushStyleColor(imgui.Col.Button, t.accent)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, t.accent)
        pushed = 2
    end
    if imgui.Button(u8"Сообщения##hr_sub_messages", imgui.ImVec2(140, 30)) then
        hr_subtab = "messages"
    end
    if pushed > 0 then imgui.PopStyleColor(pushed) end

    imgui.SameLine()

    pushed = 0
    if hr_subtab == "calendar" then
        imgui.PushStyleColor(imgui.Col.Button, t.accent)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, t.accent)
        pushed = 2
    end
    if imgui.Button(u8"Календарь##hr_sub_calendar", imgui.ImVec2(140, 30)) then
        hr_subtab = "calendar"
    end
    if pushed > 0 then imgui.PopStyleColor(pushed) end

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    if hr_subtab == "ads" then
        drawHRAdsTab(t)
    elseif hr_subtab == "messages" then
        drawHRMessagesTab(t)
    else
        drawHRCalendarTab(t)
    end
end

local function drawHomeTab(t)
    local avail = imgui.GetContentRegionAvail()
    local centerX = avail.x / 2
    local tint = imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.12)

    imgui.Dummy(imgui.ImVec2(1, 40))

    -- ---------- Ореол за иконкой ----------
    local haloSize = 130
    local haloY = imgui.GetCursorPosY()
    imgui.PushStyleColor(imgui.Col.ChildWindowBg, tint)
    imgui.SetCursorPosX(centerX - haloSize / 2)
    imgui.BeginChild("HomeHalo", imgui.ImVec2(haloSize, haloSize), false)
    imgui.EndChild()
    imgui.PopStyleColor()

    local logoTex = loadLogoTexture()
    if logoTex then
        local logoSize = 96
        imgui.SetCursorPos(imgui.ImVec2(centerX - logoSize / 2, haloY + (haloSize - logoSize) / 2))
        imgui.Image(logoTex, imgui.ImVec2(logoSize, logoSize))
    elseif fa_font_large then
        imgui.PushFont(fa_font_large)
        imgui.SetCursorPos(imgui.ImVec2(centerX - 42, haloY + 20))
        imgui.TextColored(t.accent, fa.ICON_USER)
        imgui.PopFont()
    end

    imgui.SetCursorPosY(haloY + haloSize)
    imgui.Dummy(imgui.ImVec2(1, 10))

    -- ---------- Заголовок ----------
    if arial_font then imgui.PushFont(arial_font) end
    centeredLabel("home_title", u8"Trinity Roleplay Community Manager", avail.x, 30, t.accent)
    if arial_font then imgui.PopFont() end

    -- ---------- Акцентная полоска-разделитель ----------
    imgui.Dummy(imgui.ImVec2(1, 6))
    local underlineW = 220
    imgui.SetCursorPosX(centerX - underlineW / 2)
    imgui.PushStyleColor(imgui.Col.ChildWindowBg, t.accent)
    imgui.BeginChild("HomeTitleUnderline", imgui.ImVec2(underlineW, 3), false)
    imgui.EndChild()
    imgui.PopStyleColor()

    imgui.Dummy(imgui.ImVec2(1, 10))

    local ok, myId = sampGetPlayerIdByCharHandle(playerPed)
    local nickname = (ok and myId and myId >= 0) and sampGetPlayerNickname(myId) or "—"

    if arial_font_small then imgui.PushFont(arial_font_small) end
    centeredLabel("home_welcome", u8"Добро пожаловать, " .. nickname, avail.x, 20, t.textDim)
    if arial_font_small then imgui.PopFont() end

    imgui.Dummy(imgui.ImVec2(1, 30))

    -- ---------- Плитки-должности, каждая в своём цвете ----------
    local tileW, tileH = 160, 90
    local gap = 20
    local totalW = tileW * 4 + gap * 3
    imgui.SetCursorPosX(centerX - totalW / 2)

    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.20, 0.45, 0.75, 1.0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.30, 0.55, 0.85, 1.0))
    if imgui.Button(fa.ICON_USER .. "" .. u8" Актёр##home_actor", imgui.ImVec2(tileW, tileH)) then
        openTab("roles", u8"Актёр")
    end
    imgui.PopStyleColor(2)

    imgui.SameLine(0, gap)

    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.20, 0.55, 0.60, 1.0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.28, 0.65, 0.70, 1.0))
    if imgui.Button(fa.ICON_DESKTOP .. "" .. u8" Фотограф##home_photo", imgui.ImVec2(tileW, tileH)) then
        openTab("photographer", u8"Фотограф")
    end
    imgui.PopStyleColor(2)

    imgui.SameLine(0, gap)

        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.75, 0.20, 0.20, 1.0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.85, 0.28, 0.28, 1.0))
    if imgui.Button(fa.ICON_CROSSHAIRS .. "" .. u8" Кураторы##home_tracker", imgui.ImVec2(tileW, tileH)) then
        openTab("tracker", u8"Кураторы")
    end
    imgui.PopStyleColor(2)

    imgui.SameLine(0, gap)

    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.75, 0.55, 0.20, 1.0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.85, 0.65, 0.30, 1.0))
    if imgui.Button(fa.ICON_BULLHORN .. "" .. u8" HR отдел##home_hr", imgui.ImVec2(tileW, tileH)) then
        openTab("hr", u8"HR отдел")
    end
    imgui.PopStyleColor(2)

    imgui.Dummy(imgui.ImVec2(1, 24))

    local eventBarWidth = math.min(avail.x - 80, 520)
    imgui.SetCursorPosX(centerX - eventBarWidth / 2)
    imgui.BeginChild("HomeUpcomingEvent", imgui.ImVec2(eventBarWidth, 50), true)
        imgui.SetCursorPos(imgui.ImVec2(16, 14))
        imgui.TextColored(t.accent, fa.ICON_STAR .. u8" Ближайший ивент: ")
        imgui.SameLine(0, 4)
        imgui.Text(upcoming_event_name .. u8"   |   Время: " .. upcoming_event_time)
    imgui.EndChild()
end

-- ============================================================
--  Заметки : хранение
--  Каждая заметка - moonloader\config\TRPcomm Manager Config\notes\<id>.txt
--  Индекс (порядок, названия, кол-во) - notes\index.ini
-- ============================================================
local defaultNotesIndex = { notes = { count = "0" } }

local function ensureIniFile(path, header, lines)
    local f = io.open(path, "r")
    if f then
        f:close()
        return
    end
    local fw = io.open(path, "w")
    if fw then
        fw:write("[" .. header .. "]\n")
        for _, l in ipairs(lines) do fw:write(l .. "\n") end
        fw:close()
    end
end

ensureIniFile(NOTES_INDEX_PATH, "notes", { "count=0" })

local notesIndexIni = inicfg.load(defaultNotesIndex, NOTES_INDEX_PATH) or defaultNotesIndex

local notes = {}          -- { {id=.., title=.., buffer=ImBuffer}, ... }
local activeNoteIdx = 1
local notes_rename_active = false
local notes_rename_buf = imgui.ImBuffer("", 64)
local notes_delete_pending = false
local note_id_counter = 0

local function generateNoteId()
    note_id_counter = note_id_counter + 1
    return "note_" .. os.time() .. "_" .. note_id_counter
end

local function loadNoteContentFromDisk(id)
    local f = io.open(NOTES_DIR .. "\\" .. id .. ".txt", "rb")
    if not f then return "" end
    local raw = f:read("*a")
    f:close()
    return u8(raw or "")
end

local function saveNoteContentToDisk(id, utf8text)
    local fw = io.open(NOTES_DIR .. "\\" .. id .. ".txt", "wb")
    if fw then
        fw:write(u8:decode(utf8text or ""))
        fw:close()
    end
end

local function saveNotesIndex()
    local cfg = { notes = { count = tostring(#notes) } }
    for i, n in ipairs(notes) do
        cfg.notes["note" .. i .. "_id"]    = n.id
        cfg.notes["note" .. i .. "_title"] = u8:decode(n.title)
    end
    inicfg.save(cfg, NOTES_INDEX_PATH)
    notesIndexIni = cfg
end

local function saveActiveNote()
    local n = notes[activeNoteIdx]
    if n then saveNoteContentToDisk(n.id, n.buffer.v) end
end

local function addNote(titleUtf8)
    local id = generateNoteId()
    notes[#notes + 1] = {
        id = id,
        title = titleUtf8,
        buffer = imgui.ImBuffer("", 16384),
    }
    saveNoteContentToDisk(id, "")
    saveNotesIndex()
    activeNoteIdx = #notes
end

local function deleteNote(idx)
    local n = notes[idx]
    if not n then return end
    os.remove(NOTES_DIR .. "\\" .. n.id .. ".txt")
    table.remove(notes, idx)
    if #notes == 0 then
        addNote(u8"Заметка 1")
    else
        saveNotesIndex()
        if activeNoteIdx > #notes then activeNoteIdx = #notes end
    end
end

-- загружаем список заметок при первом запуске
local notesCount = tonumber(notesIndexIni.notes.count) or 0
for i = 1, notesCount do
    local id    = notesIndexIni.notes["note" .. i .. "_id"]
    local title = notesIndexIni.notes["note" .. i .. "_title"]
    if id then
        local content = loadNoteContentFromDisk(id)
        notes[#notes + 1] = {
            id = id,
            title = u8(title or ("Заметка " .. i)),
            buffer = imgui.ImBuffer(content, 16384),
        }
    end
end
if #notes == 0 then
    addNote(u8"Заметка 1")
end

local function drawNotesTab(t)
    imgui.TextColored(t.accent, u8"Заметки")
    imgui.Separator()
    imgui.Spacing()

    -- ------- левая колонка: список заметок -------
    imgui.BeginChild("NotesList", imgui.ImVec2(180, 0), true)
        for i, n in ipairs(notes) do
            local isActive = (i == activeNoteIdx)
            local pushed = 0
            if isActive then
                imgui.PushStyleColor(imgui.Col.Button, t.accent)
                imgui.PushStyleColor(imgui.Col.ButtonHovered, t.accent)
                pushed = 2
            end
            if imgui.Button(n.title .. "##note_" .. i, imgui.ImVec2(-1, 30)) then
                if activeNoteIdx ~= i then saveActiveNote() end
                activeNoteIdx = i
                notes_rename_active = false
                notes_delete_pending = false
            end
            if pushed > 0 then imgui.PopStyleColor(pushed) end
            imgui.Spacing()
        end
        imgui.Separator()
        if imgui.Button(fa.ICON_PLUS .. u8"  Добавить##note_add", imgui.ImVec2(-1, 28)) then
            addNote(u8("Заметка " .. (#notes + 1)))
        end
    imgui.EndChild()

    imgui.SameLine()

    -- ------- правая колонка: редактор -------
    imgui.BeginChild("NotesEditor", imgui.ImVec2(0, 0), true)
        local n = notes[activeNoteIdx]
        if not n then
            imgui.TextColored(t.textDim, u8"Нет заметок")
            imgui.EndChild()
            return
        end

        -- переименование
        if notes_rename_active then
            imgui.PushItemWidth(240)
            imgui.InputText("##note_rename", notes_rename_buf)
            imgui.PopItemWidth()
            imgui.SameLine()
            if imgui.Button(u8"OK##rename_ok", imgui.ImVec2(50, 24)) then
                n.title = notes_rename_buf.v ~= "" and notes_rename_buf.v or n.title
                saveNotesIndex()
                notes_rename_active = false
            end
            imgui.SameLine()
            if imgui.Button(u8"Отмена##rename_cancel", imgui.ImVec2(70, 24)) then
                notes_rename_active = false
            end
        else
            imgui.TextColored(t.text, n.title)
            imgui.SameLine()
            if imgui.Button(fa.ICON_PENCIL .. "##note_rename_btn", imgui.ImVec2(28, 24)) then
                notes_rename_buf.v = n.title
                notes_rename_active = true
            end
            imgui.SameLine()
            if not notes_delete_pending then
                if imgui.Button(fa.ICON_TRASH .. "##note_del_btn", imgui.ImVec2(28, 24)) then
                    notes_delete_pending = true
                end
            else
                if imgui.Button(u8"Удалить?##note_del_confirm", imgui.ImVec2(90, 24)) then
                    deleteNote(activeNoteIdx)
                    notes_delete_pending = false
                end
                imgui.SameLine()
                if imgui.Button(u8"Отмена##note_del_cancel", imgui.ImVec2(70, 24)) then
                    notes_delete_pending = false
                end
            end
        end

        imgui.SameLine()
        -- сохранить
        if imgui.Button(fa.ICON_FLOPPY_O .. u8"  Сохранить##note_save", imgui.ImVec2(120, 26)) then
            saveActiveNote()
        end

        imgui.Spacing(); imgui.Separator(); imgui.Spacing()

        imgui.InputTextMultiline("##note_content", n.buffer, imgui.ImVec2(-1, -1))
    imgui.EndChild()
end

-- ============================================================
--  Каталог оружия и цветов (для шаблонов ролей)
-- ============================================================
local colorNames = {
    [0]  = u8"#0 - Красный",
    [1]  = u8"#1 - Фиолетовый",
    [2]  = u8"#2 - Бордовый",
    [3]  = u8"#3 - Тёмно-красный",
    [4]  = u8"#4 - Серый",
    [5]  = u8"#5 - Тёмно-серый",
    [6]  = u8"#6 - Светло-серый",
    [7]  = u8"#7 - Розовый",
    [8]  = u8"#8 - Светло-розовый",
    [9]  = u8"#9 - Оранжево-красный",
    [10] = u8"#10 - Оранжевый",
    [11] = u8"#11 - Жёлтый",
    [12] = u8"#12 - Светло-зелёный",
    [13] = u8"#13 - Зелёный",
    [14] = u8"#14 - Мятный",
    [15] = u8"#15 - Белый",
    [16] = u8"#16 - Небесный",
    [17] = u8"#17 - Травяной",
    [18] = u8"#18 - Синий",
    [19] = u8"#19 - Тёмно-синий",
    [20] = u8"#20 - Электрик",
    [21] = u8"#21 - Лимонный",
    [22] = u8"#22 - Изумрудный",
    [23] = u8"#23 - Коричневый",
    [24] = u8"#24 - Бежевый",
    [25] = u8"#25 - Пурпурный",
    [26] = u8"#26 - Сиреневый",
    [27] = u8"#27 - Аметист",
    [28] = u8"#28 - Золотой",
    [29] = u8"#29 - Шоколадный",
    [30] = u8"#30 - Голубовато-серый",
    [31] = u8"#31 - Ярко-зелёный",
    [32] = u8"#32 - Оливковый",
    [33] = u8"#33 - Аквамарин",
    [34] = u8"#34 - Карамельный",
    [35] = u8"#35 - Лавандовый",
    [36] = u8"#36 - Весенний",
    [37] = u8"#37 - Коралловый",
    [38] = u8"#38 - Кирпичный",
    [39] = u8"#39 - Лаймовый",
    [40] = u8"#40 - Индиго",
    [41] = u8"#41 - Орхидея",
    [42] = u8"#42 - Янтарный",
    [43] = u8"#43 - Сиреневый светлый",
    [44] = u8"#44 - Бронзовый",
    [45] = u8"#45 - Персиковый",
    [46] = u8"#46 - Стальной синий",
    [47] = u8"#47 - Хаки",
    [48] = u8"#48 - Лососевый",
    [49] = u8"#49 - Нефритовый",
    [50] = u8"#50 - Платиновый",
    [51] = u8"#51 - Серебряный",
    [52] = u8"#52 - Алмазный",
    [53] = u8"#53 - Неоново-зелёный",
    [54] = u8"#54 - Джинсовый",
    [55] = u8"#55 - Нежно-фиолетовый",
    [56] = u8"#56 - Ледяной",
    [57] = u8"#57 - Абрикосовый",
    [58] = u8"#58 - Бирюзовый",
    [59] = u8"#59 - Ментоловый",
    [60] = u8"#60 - Сливовый",
    [61] = u8"#61 - Медовый",
    [62] = u8"#62 - Сапфировый",
    [63] = u8"#63 - Малахитовый",
    [64] = u8"#64 - Солнечный",
    [65] = u8"#65 - Фламинго",
    [66] = u8"#66 - Малиновый",
    [67] = u8"#67 - Болотный",
    [68] = u8"#68 - Шалфей",
    [69] = u8"#69 - Жасмин",
    [70] = u8"#70 - Лазурный",
    [71] = u8"#71 - Магента",
    [72] = u8"#72 - Шафрановый",
    [73] = u8"#73 - Ванильный",
    [74] = u8"#74 - Нежно-розовый",
    [75] = u8"#75 - Туманный",
    [76] = u8"#76 - Льняной",
    [77] = u8"#77 - Слоновая кость",
    [78] = u8"#78 - Гелиотроп",
    [79] = u8"#79 - Перламутровый",
    [80] = u8"#80 - Полночный",
    [81] = u8"#81 - Папоротниковый",
    [82] = u8"#82 - Лиловый",
    [83] = u8"#83 - Виноградный",
    [84] = u8"#84 - Сиренево-розовый",
    [85] = u8"#85 - Алый",
    [86] = u8"#86 - Тыквенный",
    [87] = u8"#87 - Апельсиновый",
    [88] = u8"#88 - Канареечный",
    [89] = u8"#89 - Кислотный",
    [90] = u8"#90 - Морской",
    [91] = u8"#91 - Васильковый",
    [92] = u8"#92 - Неоновый",
    [93] = u8"#93 - Ультрафиолет",
    [94] = u8"#94 - Астровый",
    [95] = u8"#95 - Туманно-розовый",
    [96] = u8"#96 - Пшеничный",
    [97] = u8"#97 - Вишнёвый",
    [98] = u8"#98 - Кремовый",
    [99] = u8"#99 - Бриллиантовый",
}
local color_list = {}
for i = 0, 99 do
    color_list[i+1] = colorNames[i]
end

local weapon_list = {
    u8"1 - Кастет", u8"2 - Клюшка", u8"3 - Дубинка", u8"4 - Нож",
    u8"5 - Бита", u8"6 - Лопата", u8"7 - Кий", u8"8 - Катана", u8"9 - Бензопила",
    u8"10 - Розовый вибратор", u8"11 - Карманный вибратор",
    u8"12 - Дилдо", u8"13 - Вибратор", u8"15 - Трость", u8"16 - Гранаты",
    u8"17 - Дымовые шашки", u8"18 - Коктейль молотова",
    u8"22 - Glock 18", u8"23 - Glock 18 (глуш.)", u8"24 - Desert Eagle",
    u8"25 - Дробовик", u8"26 - Обрез", u8"27 - Spas-12", u8"28 - UZI", u8"29 - MP5",
    u8"30 - AK-47", u8"31 - M4", u8"32 - TEC9",
    u8"33 - Винтовка", u8"34 - Снайперка", u8"35 - РПГ-7",
    u8"36 - Гранатомёт", u8"37 - Огнемёт", u8"38 - Миниган", u8"39 - C4",
    u8"41 - Баллончик", u8"42 - Огнетушитель",
    u8"43 - Фотоаппарат", u8"44 - ПНВ", u8"45 - Тепловизор", u8"46 - Парашют"
}

-- ============================================================
--  Роли: хранение кастомных шаблонов (roles.ini)
-- ============================================================
local ROLES_PATH = CONFIG_DIR .. "\\roles.ini"
local defaultRolesIndex = { roles = { count = "0" } }

ensureIniFile(ROLES_PATH, "roles", { "count=0" })
local rolesIni = inicfg.load(defaultRolesIndex, ROLES_PATH) or defaultRolesIndex

local customRoleTemplates = {}

local function saveRoleTemplates()
    local cfg = { roles = { count = tostring(#customRoleTemplates) } }
    for i, r in ipairs(customRoleTemplates) do
        cfg.roles["role" .. i .. "_name"]   = u8:decode(r.name)
        cfg.roles["role" .. i .. "_skin"]   = tostring(r.skinId)
        cfg.roles["role" .. i .. "_weapon"] = u8:decode(r.weaponLabel)
        cfg.roles["role" .. i .. "_color"]  = tostring(r.colorId)
    end
    inicfg.save(cfg, ROLES_PATH)
    rolesIni = cfg
end

local function addRoleTemplate(nameUtf8, skinId, weaponLabelUtf8, colorId)
    customRoleTemplates[#customRoleTemplates + 1] = {
        name = nameUtf8, skinId = skinId, weaponLabel = weaponLabelUtf8, colorId = colorId
    }
    saveRoleTemplates()
end

local function deleteRoleTemplate(idx)
    table.remove(customRoleTemplates, idx)
    saveRoleTemplates()
end

-- загружаем сохранённые кастомные шаблоны при старте
local rolesCount = tonumber(rolesIni.roles.count) or 0
for i = 1, rolesCount do
    local nm = rolesIni.roles["role" .. i .. "_name"]
    local sk = tonumber(rolesIni.roles["role" .. i .. "_skin"])
    local wp = rolesIni.roles["role" .. i .. "_weapon"]
    local cl = tonumber(rolesIni.roles["role" .. i .. "_color"])
    if nm and sk and wp and cl then
        customRoleTemplates[#customRoleTemplates + 1] = {
            name = u8(nm), skinId = sk, weaponLabel = u8(wp), colorId = cl
        }
    end
end

-- ============================================================
--  Готовые шаблоны ролей
-- ============================================================
local builtinRoleTemplates = {
    { name = u8"Охранник", skinId = 285, weaponLabel = u8"24 - Desert Eagle", colorId = 15 },
}

local function sendRoleTemplate(tmpl)
    local ok, myId = sampGetPlayerIdByCharHandle(playerPed)
    if not ok then
        sampAddChatMessage(u8"{FF6B6B}[TRPcomm] Не удалось определить свой ID.", -1)
        return
    end
    local weaponCp1251 = u8:decode(tmpl.weaponLabel)
    local msg = string.format("/rc Мой ID: %d | Скин: %d | Оружие: %s | Клист: %d",
        myId, tmpl.skinId, weaponCp1251, tmpl.colorId)
    sampSendChat(msg)
end

-- ------------------------------------------------------------
-- каталог скинов с постраничным листанием
-- ------------------------------------------------------------
ROLE_SKIN_MIN, ROLE_SKIN_MAX = 0, 311
ROLE_SKINS_PER_PAGE = 30
roleCreateSkinId = imgui.ImInt(0)
roleCatalogPage = 0

local function drawSkinCatalogPopup(t)
    if imgui.BeginPopupModal("Каталог скинов##skin_catalog_popup", nil, imgui.WindowFlags.AlwaysAutoResize) then
        local totalSkins = ROLE_SKIN_MAX - ROLE_SKIN_MIN + 1
        local totalPages = math.ceil(totalSkins / ROLE_SKINS_PER_PAGE)
        local pageStart  = ROLE_SKIN_MIN + roleCatalogPage * ROLE_SKINS_PER_PAGE
        local pageEnd    = math.min(pageStart + ROLE_SKINS_PER_PAGE - 1, ROLE_SKIN_MAX)

        local col = 0
        for id = pageStart, pageEnd do
            local tex = loadSkinTexture(id)
            imgui.PushID("catalog_skin_" .. id)
            imgui.BeginGroup()
                if tex then
                    imgui.Image(tex, imgui.ImVec2(56, 56))
                end
                if imgui.Button(tostring(id), imgui.ImVec2(56, 20)) then
                    roleCreateSkinId.v = id
                    imgui.CloseCurrentPopup()
                end
            imgui.EndGroup()
            imgui.PopID()
            col = col + 1
            if col < 6 then
                imgui.SameLine()
            else
                col = 0
            end
        end

        imgui.Spacing(); imgui.Separator(); imgui.Spacing()

        if imgui.Button(u8"<< Назад##catalog_prev", imgui.ImVec2(90, 26)) then
            if roleCatalogPage > 0 then roleCatalogPage = roleCatalogPage - 1 end
        end
        imgui.SameLine()
        imgui.TextColored(t.textDim, u8"Страница " .. (roleCatalogPage + 1) .. u8" из " .. totalPages)
        imgui.SameLine()
        if imgui.Button(u8"Вперёд >>##catalog_next", imgui.ImVec2(90, 26)) then
            if roleCatalogPage < totalPages - 1 then roleCatalogPage = roleCatalogPage + 1 end
        end

        imgui.Spacing()
        if imgui.Button(u8"Закрыть##close_catalog", imgui.ImVec2(-1, 26)) then
            imgui.CloseCurrentPopup()
        end

        imgui.EndPopup()
    end
end

-- ------------------------------------------------------------
-- отрисовка вкладки "Роли"
-- ------------------------------------------------------------
roles_new_name = imgui.ImBuffer("", 64)
roles_new_weapon_combo = imgui.ImInt(0)
roles_new_color_combo = imgui.ImInt(0)
roles_delete_pending_idx = nil
roles_edit_idx = nil
roles_want_open_popup = false

local function drawBuiltinRoleRow(t, tmpl)
    imgui.BeginChild("builtin_role_" .. tmpl.name, imgui.ImVec2(0, 60), true)
        local tex = loadSkinTexture(tmpl.skinId)
        if tex then
            imgui.Image(tex, imgui.ImVec2(32, 32))
            imgui.SameLine()
        end
        imgui.BeginGroup()
            imgui.TextColored(t.text, tmpl.name)
            local weaponName = tmpl.weaponLabel:match("%- (.+)$") or tmpl.weaponLabel
            local colorLabel = colorNames[tmpl.colorId] or ""
            local colorName  = colorLabel:match("%- (.+)$") or colorLabel
            imgui.TextColored(t.textDim, u8"Оружие: " .. weaponName .. u8"  |  Цвет: " .. colorName)
        imgui.EndGroup()
        imgui.SameLine(imgui.GetWindowWidth() - 100)
        if imgui.Button(u8"Выдать##builtin_" .. tmpl.name, imgui.ImVec2(90, 28)) then
            sendRoleTemplate(tmpl)
        end
    imgui.EndChild()
end

local function drawCustomRoleRow(t, idx, tmpl)
    imgui.BeginChild("custom_role_" .. idx, imgui.ImVec2(0, 60), true)
        local tex = loadSkinTexture(tmpl.skinId)
        if tex then
            imgui.Image(tex, imgui.ImVec2(32, 32))
            imgui.SameLine()
        end
        imgui.BeginGroup()
            imgui.TextColored(t.text, tmpl.name)
            local weaponName = tmpl.weaponLabel:match("%- (.+)$") or tmpl.weaponLabel
            local colorLabel = colorNames[tmpl.colorId] or ""
            local colorName  = colorLabel:match("%- (.+)$") or colorLabel
            imgui.TextColored(t.textDim, u8"Оружие: " .. weaponName .. u8"  |  Цвет: " .. colorName)
        imgui.EndGroup()
        imgui.SameLine(imgui.GetWindowWidth() - 170)
        if imgui.Button(u8"Выдать##custom_" .. idx, imgui.ImVec2(90, 28)) then
            sendRoleTemplate(tmpl)
        end
        imgui.SameLine()
        if imgui.Button(fa.ICON_PENCIL .. "##custom_edit_" .. idx, imgui.ImVec2(28, 28)) then
            roles_edit_idx = idx
            roles_new_name.v = tmpl.name
            roleCreateSkinId.v = tmpl.skinId
            roles_new_weapon_combo.v = 0
            for i, w in ipairs(weapon_list) do
                if w == tmpl.weaponLabel then
                    roles_new_weapon_combo.v = i - 1
                    break
                end
            end
            roles_new_color_combo.v = tmpl.colorId
            roles_want_open_popup = true
        end
        imgui.SameLine()
        if roles_delete_pending_idx == idx then
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.8, 0.15, 0.15, 1))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.9, 0.2, 0.2, 1))
            if imgui.Button(fa.ICON_TRASH .. "##custom_del_" .. idx, imgui.ImVec2(28, 28)) then
                deleteRoleTemplate(idx)
                roles_delete_pending_idx = nil
            end
            imgui.PopStyleColor(2)
        else
            if imgui.Button(fa.ICON_TRASH .. "##custom_del_" .. idx, imgui.ImVec2(28, 28)) then
                roles_delete_pending_idx = idx
            end
        end
    imgui.EndChild()
end

local function drawAddRolePopup(t)
    local popupTitle = roles_edit_idx and u8"Редактировать шаблон" or u8"Новый шаблон"
    if imgui.BeginPopupModal(popupTitle .. "###add_role_popup", nil, imgui.WindowFlags.AlwaysAutoResize) then
        imgui.TextColored(t.textDim, u8"Название:")
        imgui.PushItemWidth(240)
        imgui.InputText("##new_role_name", roles_new_name)
        imgui.PopItemWidth()

        imgui.Spacing()
        imgui.TextColored(t.textDim, u8"ID скина:")
        imgui.PushItemWidth(100)
        imgui.InputInt("##new_role_skin_id", roleCreateSkinId, 0, 0)
        imgui.PopItemWidth()
        imgui.SameLine()
        if imgui.Button(u8"Каталог##open_skin_catalog", imgui.ImVec2(100, 24)) then
            roleCatalogPage = 0
            imgui.OpenPopup("Каталог скинов##skin_catalog_popup")
        end
        local previewTex = loadSkinTexture(roleCreateSkinId.v)
        if previewTex then
            imgui.SameLine()
            imgui.Image(previewTex, imgui.ImVec2(28, 28))
        end

        imgui.Spacing()
        imgui.TextColored(t.textDim, u8"Оружие:")
        imgui.PushItemWidth(260)
        imgui.Combo("##new_role_weapon", roles_new_weapon_combo, weapon_list)
        imgui.PopItemWidth()

        imgui.Spacing()
        imgui.TextColored(t.textDim, u8"Клист (цвет ника):")
        imgui.PushItemWidth(260)
        imgui.Combo("##new_role_color", roles_new_color_combo, color_list)
        imgui.PopItemWidth()

        imgui.Spacing(); imgui.Separator(); imgui.Spacing()

        if imgui.Button(u8"Сохранить##save_new_role", imgui.ImVec2(120, 28)) then
            if roles_new_name.v ~= "" then
                if roles_edit_idx then
                    local tmpl = customRoleTemplates[roles_edit_idx]
                    tmpl.name        = roles_new_name.v
                    tmpl.skinId      = roleCreateSkinId.v
                    tmpl.weaponLabel = weapon_list[roles_new_weapon_combo.v + 1]
                    tmpl.colorId     = roles_new_color_combo.v
                    saveRoleTemplates()
                    roles_edit_idx = nil
                else
                    addRoleTemplate(
                        roles_new_name.v,
                        roleCreateSkinId.v,
                        weapon_list[roles_new_weapon_combo.v + 1],
                        roles_new_color_combo.v
                    )
                end
                roles_new_name.v = ""
                imgui.CloseCurrentPopup()
            end
        end
        imgui.SameLine()
        if imgui.Button(u8"Отмена##cancel_new_role", imgui.ImVec2(100, 28)) then
            roles_edit_idx = nil
            imgui.CloseCurrentPopup()
        end

        drawSkinCatalogPopup(t)

        imgui.EndPopup()
    end
end

local function drawRolesTab(t)
    imgui.TextColored(t.accent, u8"Роли")
    imgui.SameLine(imgui.GetWindowWidth() - 150)
    if imgui.Button(fa.ICON_PLUS .. u8"  Добавить##add_role", imgui.ImVec2(140, 26)) then
        roles_edit_idx = nil
        roles_new_name.v = ""
        roleCreateSkinId.v = 0
        roles_new_weapon_combo.v = 0
        roles_new_color_combo.v = 0
        imgui.OpenPopup("###add_role_popup")
    end
    imgui.Separator()
    imgui.Spacing()

    imgui.TextColored(t.accent, u8"Готовые шаблоны")
    imgui.Spacing()
    for _, tmpl in ipairs(builtinRoleTemplates) do
        drawBuiltinRoleRow(t, tmpl)
        imgui.Spacing()
    end

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    imgui.TextColored(t.accent, u8"Мои шаблоны")
    imgui.Spacing()
    for idx, tmpl in ipairs(customRoleTemplates) do
        drawCustomRoleRow(t, idx, tmpl)
        imgui.Spacing()
    end

    if roles_want_open_popup then
        imgui.OpenPopup("###add_role_popup")
        roles_want_open_popup = false
    end

    drawAddRolePopup(t)
end

-- ============================================================
--  НАСТРОЙКИ
-- ============================================================

local function drawSettingsTab(t)
    imgui.TextColored(t.accent, u8"НАСТРОЙКИ")
    imgui.Separator()
    imgui.Spacing()

    -- ---------- Бинд на открытие меню ----------
    imgui.TextColored(t.accent, fa.ICON_KEYBOARD_O .. u8" Открытие меню")
    imgui.TextColored(t.textDim, u8"Текущая комбинация:")
    imgui.SameLine()
    imgui.Text(hotkey_display.v)

    if waiting_for_key then
        imgui.TextColored(imgui.ImVec4(1, 0.6, 0.2, 1), u8"Нажмите клавишу или комбинацию...")
    else
        if imgui.Button(u8"Изменить##hotkey_change", imgui.ImVec2(180, 25)) then
            waiting_for_key2 = false
            waiting_for_key = true
        end
        imgui.SameLine()
        if imgui.Button(u8"Сброс на Alt + P##hotkey_reset", imgui.ImVec2(180, 25)) then
            hotkey_alt.v   = true
            hotkey_ctrl.v  = false
            hotkey_shift.v = false
            hotkey_key.v   = 0x50
            updateHotkeyDisplay()
            saveSettings()
        end
    end

    if waiting_for_key then
        for vk = 1, 254 do
            if isKeyDown(vk) and vk ~= 0x12 and vk ~= 0x11 and vk ~= 0x10
               and vk ~= 0xA0 and vk ~= 0xA1 and vk ~= 0xA2 and vk ~= 0xA3 and vk ~= 0xA4 and vk ~= 0xA5 then
                hotkey_key.v   = vk
                hotkey_alt.v   = isKeyDown(0x12) or isKeyDown(0xA4) or isKeyDown(0xA5)
                hotkey_ctrl.v  = isKeyDown(0x11) or isKeyDown(0xA2) or isKeyDown(0xA3)
                hotkey_shift.v = isKeyDown(0x10) or isKeyDown(0xA0) or isKeyDown(0xA1)
                waiting_for_key = false
                updateHotkeyDisplay()
                saveSettings()
                break
            end
        end
    end

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    -- ---------- Бинд на подключение к рации ----------
    imgui.TextColored(t.accent, fa.ICON_WIFI .. u8" Подключение к рации")
    imgui.TextColored(t.textDim, u8"Текущая комбинация:")
    imgui.SameLine()
    imgui.Text(hotkey2_display.v)

    if waiting_for_key2 then
        imgui.TextColored(imgui.ImVec4(1, 0.6, 0.2, 1), u8"Нажмите клавишу или комбинацию...")
    else
        if imgui.Button(u8"Изменить##hotkey2_change", imgui.ImVec2(180, 25)) then
            waiting_for_key = false
            waiting_for_key2 = true
        end
        imgui.SameLine()
        if imgui.Button(u8"Убрать бинд##hotkey2_clear", imgui.ImVec2(180, 25)) then
            hotkey2_alt.v   = false
            hotkey2_ctrl.v  = false
            hotkey2_shift.v = false
            hotkey2_key.v   = 0
            updateHotkey2Display()
            saveSettings()
        end
    end

    if waiting_for_key2 then
        for vk = 1, 254 do
            if isKeyDown(vk) and vk ~= 0x12 and vk ~= 0x11 and vk ~= 0x10
               and vk ~= 0xA0 and vk ~= 0xA1 and vk ~= 0xA2 and vk ~= 0xA3 and vk ~= 0xA4 and vk ~= 0xA5 then
                hotkey2_key.v   = vk
                hotkey2_alt.v   = isKeyDown(0x12) or isKeyDown(0xA4) or isKeyDown(0xA5)
                hotkey2_ctrl.v  = isKeyDown(0x11) or isKeyDown(0xA2) or isKeyDown(0xA3)
                hotkey2_shift.v = isKeyDown(0x10) or isKeyDown(0xA0) or isKeyDown(0xA1)
                waiting_for_key2 = false
                updateHotkey2Display()
                saveSettings()
                break
            end
        end
    end

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    -- ---------- Тема оформления ----------
    imgui.TextColored(t.accent, fa.ICON_PAINT_BRUSH .. u8" Тема оформления")
    local theme_names = {}
    for _, th in ipairs(themes) do theme_names[#theme_names + 1] = th.name end
    if imgui.Combo("##theme_select", selected_theme_combo, theme_names) then
        currentThemeIdx = selected_theme_combo.v + 1
        saveSettings()
    end

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    -- ---------- Рация ----------
    imgui.TextColored(t.accent, fa.ICON_WRENCH .. u8" Рация")
    imgui.TextColored(t.textDim, u8"Частота рации:")
    imgui.PushItemWidth(200)
    imgui.InputText("##radio_freq", radio_freq)
    imgui.PopItemWidth()

    imgui.TextColored(t.textDim, u8"Пароль рации:")
    imgui.PushItemWidth(200)
    imgui.InputText("##radio_pass", radio_pass)
    imgui.PopItemWidth()

    imgui.TextColored(t.textDim, u8"Пароль к телепорту:")
    imgui.PushItemWidth(200)
    imgui.InputText("##teleport_pass", teleport_pass)
    imgui.PopItemWidth()

imgui.Spacing(); imgui.Separator(); imgui.Spacing()
    imgui.TextColored(t.accent, fa.ICON_SLIDERS .. u8" Дополнительные настройки")

    if imgui.Checkbox(u8"Отправлять скриншоты документом (лучшее качество)", send_as_document) then
        saveSettings()
    end

    imgui.Spacing()
    if imgui.Button(u8"Сохранить##radio_save", imgui.ImVec2(150, 28)) then
        saveSettings()
    end
end

-- ============================================================
--  ГАЛЕРЕЯ СКРИНШОТОВ (Фотограф)
-- ============================================================
-- Папка со скриншотами SAMP — стандартная папка "Документы" пользователя
local SCREENS_DIR = (os.getenv("USERPROFILE") or "") .. "\\Documents\\GTA San Andreas User Files\\SAMP\\screens\\"

GALLERY_SCAN_LIMIT = 60 -- сколько последних файлов вообще ищем
GALLERY_PER_PAGE   = 9  -- 3x3 на странице
GALLERY_MAX_SELECT = 10

gallery_textures      = {}
gallery_files         = {}
gallery_scanned       = false
gallery_page          = 1
gallery_loaded_pages  = {}
gallery_selected      = {}   -- [filename] = true
gallery_preview_open  = false
gallery_preview_file  = nil

local function gallerySelectedCount()
    local n = 0
    for _ in pairs(gallery_selected) do n = n + 1 end
    return n
end

local function scanGallery()
    local all = {}
    for _, entry in ipairs(findFilesByMask(SCREENS_DIR .. "*.jpg")) do all[#all + 1] = entry end
    for _, entry in ipairs(findFilesByMask(SCREENS_DIR .. "*.png")) do all[#all + 1] = entry end

    table.sort(all, function(a, b) return a.mtime > b.mtime end)

    gallery_files = {}
    for i = 1, math.min(GALLERY_SCAN_LIMIT, #all) do
        gallery_files[#gallery_files + 1] = all[i].name
    end
    gallery_scanned      = true
    gallery_loaded_pages = {}
    gallery_textures     = {}
    gallery_page          = 1
    gallery_selected      = {}
end

-- Собирает тело multipart/form-data запроса вручную (requests.lua это не умеет сама)
local function buildMultipartBody(boundary, fields, fileFieldName, filePath, fileMime)
    local f = io.open(filePath, "rb")
    if not f then return nil end
    local fileData = f:read("*a")
    f:close()

    local parts = {}
    for name, value in pairs(fields) do
        parts[#parts + 1] = "--" .. boundary .. "\r\n"
        parts[#parts + 1] = 'Content-Disposition: form-data; name="' .. name .. '"\r\n\r\n'
        parts[#parts + 1] = tostring(value) .. "\r\n"
    end

    local filename = filePath:match("[^\\/]+$") or "file"
    parts[#parts + 1] = "--" .. boundary .. "\r\n"
    parts[#parts + 1] = 'Content-Disposition: form-data; name="' .. fileFieldName .. '"; filename="' .. filename .. '"\r\n'
    parts[#parts + 1] = "Content-Type: " .. fileMime .. "\r\n\r\n"
    parts[#parts + 1] = fileData
    parts[#parts + 1] = "\r\n--" .. boundary .. "--\r\n"

    return table.concat(parts)
end

local function buildReportCaption(eventName)
    local ok, myId = sampGetPlayerIdByCharHandle(playerPed)
    local nickname = u8((ok and myId and myId >= 0) and sampGetPlayerNickname(myId) or "-")
    if eventName and eventName ~= "" then
        return nickname .. " | " .. eventName
    end
    return nickname
end

local function sendScreenshotToTelegram(filePath, caption)
    local token = TG_BOT_TOKEN
    local chatId = TG_CHAT_ID

    if token == "" or chatId == "" then
        sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Укажи токен бота и ID чата в настройках.', -1)
        return false
    end

    local boundary = "----TRPcommBoundary" .. tostring(os.time()) .. tostring(math.random(1000, 9999))
    local ext = (filePath:match("%.([^.]+)$") or "jpg"):lower()
    local mime = (ext == "png") and "image/png" or "image/jpeg"
    local asDocument = send_as_document.v

    local fields = { chat_id = chatId }
    caption = caption or buildReportCaption()
    if caption and caption ~= "" then
        fields.caption = caption
    end

    if TG_THREAD_ID and TG_THREAD_ID ~= "" then
        fields.message_thread_id = TG_THREAD_ID
    end

    local fieldName = asDocument and "document" or "photo"
    local body = buildMultipartBody(boundary, fields, fieldName, filePath, mime)
    if not body then
        sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Не удалось прочитать файл: ' .. filePath, -1)
        return false
    end

    local apiMethod = asDocument and "sendDocument" or "sendPhoto"
    local url = "https://api.telegram.org/bot" .. token .. "/" .. apiMethod
    local ok, response = pcall(requests.post, url, {
        data = body,
        headers = { ["Content-Type"] = "multipart/form-data; boundary=" .. boundary },
        timeout = 20,
    })

    if not ok then
        sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Ошибка отправки: ' .. tostring(response), -1)
        return false
    end

    if response.status_code == 200 then
        return true
    else
        sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Telegram вернул ошибку ' .. tostring(response.status_code) .. ': ' .. tostring(response.text), -1)
        return false
    end
end

-- Собирает multipart-тело для sendMediaGroup (несколько файлов одним запросом)
local function buildMediaGroupBody(boundary, chatId, filePaths, caption)
    local asDocument = send_as_document.v
    local mediaType = asDocument and "document" or "photo"

    local mediaArray = {}
    for i = 1, #filePaths do
        mediaArray[i] = { type = mediaType, media = "attach://file" .. i }
        if i == 1 and caption and caption ~= "" then
            mediaArray[i].caption = caption
        end
    end
    local mediaJson = cjson.encode(mediaArray)
    if not mediaJson then return nil end

    local parts = {}
    local function addField(name, value)
        parts[#parts + 1] = "--" .. boundary .. "\r\n"
        parts[#parts + 1] = 'Content-Disposition: form-data; name="' .. name .. '"\r\n\r\n'
        parts[#parts + 1] = tostring(value) .. "\r\n"
    end

    addField("chat_id", chatId)
    if TG_THREAD_ID and TG_THREAD_ID ~= "" then
        addField("message_thread_id", TG_THREAD_ID)
    end
    addField("media", mediaJson)

    for i, filePath in ipairs(filePaths) do
        local f = io.open(filePath, "rb")
        if not f then return nil end
        local fileData = f:read("*a")
        f:close()

        local filename = filePath:match("[^\\/]+$") or ("file" .. i)
        local ext = (filePath:match("%.([^.]+)$") or "jpg"):lower()
        local mime = (ext == "png") and "image/png" or "image/jpeg"

        parts[#parts + 1] = "--" .. boundary .. "\r\n"
        parts[#parts + 1] = 'Content-Disposition: form-data; name="file' .. i .. '"; filename="' .. filename .. '"\r\n'
        parts[#parts + 1] = "Content-Type: " .. mime .. "\r\n\r\n"
        parts[#parts + 1] = fileData
        parts[#parts + 1] = "\r\n"
    end

    parts[#parts + 1] = "--" .. boundary .. "--\r\n"
    return table.concat(parts)
end

-- Отправляет несколько скриншотов одним альбомом (2-10 штук). Возвращает true/false.
local function sendMediaGroupToTelegram(filePaths, caption)
    local token = TG_BOT_TOKEN
    local chatId = TG_CHAT_ID

    if token == "" or chatId == "" then
        sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Укажи токен бота и ID чата в настройках.', -1)
        return false
    end

    local boundary = "----TRPcommBoundary" .. tostring(os.time()) .. tostring(math.random(1000, 9999))
    local body = buildMediaGroupBody(boundary, chatId, filePaths, caption)
    if not body then
        sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Не удалось собрать альбом (проверь файлы).', -1)
        return false
    end

    local url = "https://api.telegram.org/bot" .. token .. "/sendMediaGroup"
    local ok, response = pcall(requests.post, url, {
        data = body,
        headers = { ["Content-Type"] = "multipart/form-data; boundary=" .. boundary },
        timeout = 30,
    })

    if not ok then
        sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Ошибка отправки: ' .. tostring(response), -1)
        return false
    end

    if response.status_code == 200 then
        return true
    else
        sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Telegram вернул ошибку ' .. tostring(response.status_code) .. ': ' .. tostring(response.text), -1)
        return false
    end
end

local function loadGalleryTexture(filename)
    if gallery_textures[filename] ~= nil then
        return gallery_textures[filename] or nil
    end
    local path = SCREENS_DIR .. filename
    if doesFileExist(path) then
        local tex = imgui.CreateTextureFromFile(path)
        gallery_textures[filename] = tex
        return tex
    end
    gallery_textures[filename] = false
    return nil
end

-- грузит картинки только для конкретной страницы, растягивая по кадрам
local function loadGalleryPage(page)
    if gallery_loaded_pages[page] then return end
    gallery_loaded_pages[page] = true
    local startIdx = (page - 1) * GALLERY_PER_PAGE + 1
    local endIdx   = math.min(startIdx + GALLERY_PER_PAGE - 1, #gallery_files)
    lua_thread.create(function()
        for i = startIdx, endIdx do
            loadGalleryTexture(gallery_files[i])
            wait(0)
        end
    end)
end

-- ---------- Окно "Название ивента перед отправкой" ----------
gallery_send_form_open = false
gallery_send_event_name = imgui.ImBuffer("", 64)
gallery_pending_files = {}

local function sendGalleryReport(filesToSend, eventNameUtf8)
    sampAddChatMessage('{5B85C4}[TRPcomm] {FFFFFF}Отправляю {5B85C4}' .. #filesToSend .. ' {FFFFFF}скриншот(ов) в Telegram...', -1)
    lua_thread.create(function()
        local paths = {}
        for _, fname in ipairs(filesToSend) do
            paths[#paths + 1] = SCREENS_DIR .. fname
        end

        local caption = buildReportCaption(eventNameUtf8)

        local ok
        if #paths == 1 then
            ok = sendScreenshotToTelegram(paths[1], caption)
        else
            ok = sendMediaGroupToTelegram(paths, caption)
        end

        if ok then
            sampAddChatMessage('{5B85C4}[TRPcomm] {FFFFFF}Готово: отправлено {5B85C4}' .. #paths .. ' {FFFFFF}скрин(ов) одним альбомом.', -1)
            addReport(eventNameUtf8, filesToSend)
            gallery_selected = {}
        else
            sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Отправка не удалась.', -1)
        end
    end)
end

local function drawGallerySendReportForm(t)
    if not gallery_send_form_open then return end

    local sw, sh = getScreenResolution()
    imgui.SetNextWindowSize(imgui.ImVec2(400, 180), imgui.Cond.Always)
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))

    pushThemeColors()
    pushThemeRounding()

    local open = imgui.ImBool(true)
    imgui.Begin(u8"Отправка отчёта##gallery_send_form", open,
        imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize)
    if not open.v then gallery_send_form_open = false end

    imgui.TextColored(t.textDim, u8"Название ивента:")
    imgui.PushItemWidth(360)
    imgui.InputText("##gallery_send_event_name", gallery_send_event_name)
    imgui.PopItemWidth()

    imgui.Spacing()
    imgui.TextColored(t.textDim, u8"Скриншотов: " .. #gallery_pending_files)

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    if imgui.Button(u8"Отправить##gallery_send_confirm", imgui.ImVec2(160, 30)) then
        local nameText = u8:decode(gallery_send_event_name.v)
        local eventNameUtf8 = (nameText == "") and u8"Без названия" or u8(nameText)
        sendGalleryReport(gallery_pending_files, eventNameUtf8)
        gallery_send_event_name.v = ""
        gallery_send_form_open = false
    end
    imgui.SameLine()
    if imgui.Button(u8"Отмена##gallery_send_cancel", imgui.ImVec2(120, 30)) then
        gallery_send_form_open = false
    end

    imgui.End()
    imgui.PopStyleVar(THEME_ROUNDING_COUNT)
    imgui.PopStyleColor(THEME_COLOR_COUNT)
end

local function drawGalleryPreview(t)
    if not gallery_preview_open or not gallery_preview_file then return end

    local tex = gallery_textures[gallery_preview_file]
    if not tex then
        gallery_preview_open = false
        return
    end

    local sw, sh = getScreenResolution()
    imgui.SetNextWindowSize(imgui.ImVec2(sw * 0.7, sh * 0.75), imgui.Cond.Always)
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))

    pushThemeColors()
    pushThemeRounding()

    local open = imgui.ImBool(true)
    imgui.Begin(u8"Скриншот##gallery_preview", open,
        imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize)
    if not open.v then gallery_preview_open = false end

    local avail = imgui.GetContentRegionAvail()
    imgui.Image(tex, imgui.ImVec2(avail.x, avail.y - 40))

    if imgui.Button(u8"Закрыть##gallery_preview_close", imgui.ImVec2(-1, 30)) then
        gallery_preview_open = false
    end

    imgui.End()
    imgui.PopStyleVar(THEME_ROUNDING_COUNT)
    imgui.PopStyleColor(THEME_COLOR_COUNT)
end

photographer_subtab = "gallery" -- "gallery" | "reports"
local drawGalleryTab   -- форвард-объявление, тела ниже
local drawReportsTab

local function drawPhotographerTab(t)
    imgui.TextColored(t.accent, fa.ICON_DESKTOP .. u8" ФОТОГРАФ")
    imgui.Spacing()

    local pushed = 0
    if photographer_subtab == "gallery" then
        imgui.PushStyleColor(imgui.Col.Button, t.accent)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, t.accent)
        pushed = 2
    end
    if imgui.Button(u8"Галерея##photo_sub_gallery", imgui.ImVec2(140, 30)) then
        photographer_subtab = "gallery"
    end
    if pushed > 0 then imgui.PopStyleColor(pushed) end

    imgui.SameLine()

    pushed = 0
    if photographer_subtab == "reports" then
        imgui.PushStyleColor(imgui.Col.Button, t.accent)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, t.accent)
        pushed = 2
    end
    if imgui.Button(u8"Отчёты##photo_sub_reports", imgui.ImVec2(140, 30)) then
        photographer_subtab = "reports"
    end
    if pushed > 0 then imgui.PopStyleColor(pushed) end

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    if photographer_subtab == "gallery" then
        drawGalleryTab(t)
    else
        drawReportsTab(t)
    end
end

local tracker_subtab = "radius" -- "radius" | "reports"

-- ---------- Подсчёт игроков в радиусе + таймер ----------
tracker_active  = false
TRACKER_RADIUS = 300 -- метров, максимальный радиус стрима игроков
tracker_players = {} -- [pid] = { nickname=, totalSeconds=, inRadius=, lastTick= }
tracker_last_update = 0

local function formatDuration(sec)
    sec = math.floor(sec)
    local m = math.floor(sec / 60)
    local s = sec % 60
    return string.format("%02d:%02d", m, s)
end

-- дёргается раз в секунду из main(), работает даже если вкладка сейчас закрыта
local function updateTrackerRadius()
    local myX, myY, myZ = getCharCoordinates(playerPed)
    local seenNow = {}

    for pid = 0, sampGetMaxPlayerId() do
        if sampIsPlayerConnected(pid) and pid ~= select(2, sampGetPlayerIdByCharHandle(playerPed)) then
            local ok, ped = sampGetCharHandleBySampPlayerId(pid)
            if ok then
                local px, py, pz = getCharCoordinates(ped)
                local dx, dy, dz = px - myX, py - myY, pz - myZ
                local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                if dist <= TRACKER_RADIUS then
                    seenNow[pid] = true
                    local entry = tracker_players[pid]
                    if not entry then
                        entry = {
                            nickname = sampGetPlayerNickname(pid),
                            totalSeconds = 0,
                            inRadius = true,
                            lastTick = os.time(),
                        }
                        tracker_players[pid] = entry
                    elseif not entry.inRadius then
                        entry.inRadius = true
                        entry.lastTick = os.time()
                    else
                        entry.totalSeconds = entry.totalSeconds + (os.time() - entry.lastTick)
                        entry.lastTick = os.time()
                    end
                end
            end
        end
    end

    for pid, entry in pairs(tracker_players) do
        if not seenNow[pid] and entry.inRadius then
            entry.totalSeconds = entry.totalSeconds + (os.time() - entry.lastTick)
            entry.inRadius = false
        end
    end
end

local function drawTrackerRadiusTab(t)

    if tracker_active then
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.75, 0.25, 0.25, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.85, 0.35, 0.35, 1.0))
        if imgui.Button(fa.ICON_TIMES .. u8" Остановить сбор##tracker_toggle", imgui.ImVec2(200, 32)) then
            tracker_active = false
        end
        imgui.PopStyleColor(2)
    else
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.25, 0.65, 0.35, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.35, 0.75, 0.45, 1.0))
        if imgui.Button(fa.ICON_CROSSHAIRS .. u8" Начать сбор##tracker_toggle", imgui.ImVec2(200, 32)) then
            tracker_active = true
        end
        imgui.PopStyleColor(2)
    end

    imgui.SameLine()
    if imgui.Button(u8"Сбросить##tracker_reset", imgui.ImVec2(120, 32)) then
        tracker_players = {}
    end

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    local ids = {}
    for pid in pairs(tracker_players) do ids[#ids + 1] = pid end
    table.sort(ids)

    if #ids == 0 then
        imgui.TextColored(t.textDim, u8"Пока никто не попал в радиус.")
        return
    end

    for _, pid in ipairs(ids) do
        local entry = tracker_players[pid]
        local displaySec = entry.totalSeconds
        if entry.inRadius then
            displaySec = displaySec + (os.time() - entry.lastTick)
        end
        imgui.BeginChild("tp_" .. pid, imgui.ImVec2(0, 32), true)
            local statusColor = entry.inRadius and t.accent or t.textDim
            imgui.TextColored(statusColor, entry.nickname .. u8" (ID " .. pid .. u8")")
            imgui.SameLine(imgui.GetWindowWidth() - 70)
            imgui.Text(formatDuration(displaySec))
        imgui.EndChild()
        imgui.Spacing()
    end
end

-- ============================================================
--  ОТЧЁТЫ СЛЕДЯЩЕГО: хранение
--  moonloader\config\TRPcomm Manager Config\tracker_reports\index.ini
-- ============================================================
local defaultTrackerReportsIndex = { reports = { count = "0" } }

ensureIniFile(TRACKER_REPORTS_INDEX_PATH, "reports", { "count=0" })

trackerReportsIndexIni = inicfg.load(defaultTrackerReportsIndex, TRACKER_REPORTS_INDEX_PATH) or defaultTrackerReportsIndex
trackerReports = {} -- { {id=, event=(u8), time=os.time(), players={ {nickname=, seconds=}, ... }}, ... }

local function saveTrackerReportsIndex()
    local cfg = { reports = { count = tostring(#trackerReports) } }
    for i, r in ipairs(trackerReports) do
        cfg.reports["report" .. i .. "_id"]    = r.id
        cfg.reports["report" .. i .. "_event"] = u8:decode(r.event)
        cfg.reports["report" .. i .. "_time"]  = tostring(r.time)

        local playerParts = {}
        for _, p in ipairs(r.players) do
            playerParts[#playerParts + 1] = p.nickname .. ":" .. tostring(math.floor(p.seconds))
        end
        cfg.reports["report" .. i .. "_players"] = table.concat(playerParts, "|")
    end
    inicfg.save(cfg, TRACKER_REPORTS_INDEX_PATH)
    trackerReportsIndexIni = cfg
end

local function addTrackerReport(eventNameUtf8, players)
    trackerReports[#trackerReports + 1] = {
        id = "tracker_report_" .. os.time() .. "_" .. tostring(math.random(1000, 9999)),
        event = eventNameUtf8,
        time = os.time(),
        players = players,
    }
    saveTrackerReportsIndex()
end

local function deleteTrackerReport(idx)
    if not trackerReports[idx] then return end
    table.remove(trackerReports, idx)
    saveTrackerReportsIndex()
end

-- загружаем список при первом запуске
local trackerReportsCount = tonumber(trackerReportsIndexIni.reports.count) or 0
for i = 1, trackerReportsCount do
    local id        = trackerReportsIndexIni.reports["report" .. i .. "_id"]
    local eventRaw  = trackerReportsIndexIni.reports["report" .. i .. "_event"]
    local timeRaw   = trackerReportsIndexIni.reports["report" .. i .. "_time"]
    local playersRaw = trackerReportsIndexIni.reports["report" .. i .. "_players"]
    if id then
        local players = {}
        if playersRaw and playersRaw ~= "" then
            for chunk in playersRaw:gmatch("[^|]+") do
                local nick, sec = chunk:match("^(.-):(%d+)$")
                if nick then
                    players[#players + 1] = { nickname = nick, seconds = tonumber(sec) or 0 }
                end
            end
        end
        trackerReports[#trackerReports + 1] = {
            id = id,
            event = u8(eventRaw or ""),
            time = tonumber(timeRaw) or 0,
            players = players,
        }
    end
end

-- ---------- Форма создания отчёта ----------
local tracker_report_form_open = false
local tracker_report_name = imgui.ImBuffer("", 64)

local function drawTrackerCreateReportForm(t)
    if not tracker_report_form_open then return end

    local sw, sh = getScreenResolution()
    imgui.SetNextWindowSize(imgui.ImVec2(420, 260), imgui.Cond.Always)
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))

    pushThemeColors()
    pushThemeRounding()

    local open = imgui.ImBool(true)
    imgui.Begin(u8"Новый отчёт##tracker_report_form", open,
        imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize)
    if not open.v then tracker_report_form_open = false end

    imgui.TextColored(t.textDim, u8"Название ивента:")
    imgui.PushItemWidth(380)
    imgui.InputText("##tracker_report_name", tracker_report_name)
    imgui.PopItemWidth()

    imgui.Spacing()
    imgui.TextColored(t.textDim, u8"Дата и время: " .. os.date("%d.%m.%Y  %H:%M"))

    imgui.Spacing()
    local count = 0
    for _ in pairs(tracker_players) do count = count + 1 end
    imgui.TextColored(t.textDim, u8"Игроков собрано: " .. count)

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    if imgui.Button(u8"Сохранить отчёт##tracker_report_save", imgui.ImVec2(180, 30)) then
        local nameText = u8:decode(tracker_report_name.v)
        if nameText == "" then nameText = u8"Без названия" end

        local players = {}
        for pid, entry in pairs(tracker_players) do
            local sec = entry.totalSeconds
            if entry.inRadius then
                sec = sec + (os.time() - entry.lastTick)
            end
            players[#players + 1] = { nickname = entry.nickname, seconds = sec }
        end
        table.sort(players, function(a, b) return a.seconds > b.seconds end)

        addTrackerReport(u8(nameText), players)
        tracker_players = {}
        tracker_report_name.v = ""
        tracker_report_form_open = false
    end
    imgui.SameLine()
    if imgui.Button(u8"Отмена##tracker_report_cancel", imgui.ImVec2(120, 30)) then
        tracker_report_form_open = false
    end

    imgui.End()
    imgui.PopStyleVar(THEME_ROUNDING_COUNT)
    imgui.PopStyleColor(THEME_COLOR_COUNT)
end

-- ---------- Окно просмотра отчёта ----------
local tracker_report_viewer_open = false
local tracker_report_viewer_idx = nil

local function drawTrackerReportViewer(t)
    if not tracker_report_viewer_open or not tracker_report_viewer_idx then return end
    local r = trackerReports[tracker_report_viewer_idx]
    if not r then tracker_report_viewer_open = false; return end

    local sw, sh = getScreenResolution()
    imgui.SetNextWindowSize(imgui.ImVec2(sw * 0.5, sh * 0.6), imgui.Cond.Always)
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))

    pushThemeColors()
    pushThemeRounding()

    local open = imgui.ImBool(true)
    imgui.Begin(r.event .. "##tracker_report_viewer", open,
        imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize)
    if not open.v then tracker_report_viewer_open = false end

    imgui.TextColored(t.textDim, os.date("%d.%m.%Y  %H:%M", r.time))
    imgui.Separator()
    imgui.Spacing()

    imgui.BeginChild("TrackerReportPlayers", imgui.ImVec2(0, 0), false)
        if #r.players == 0 then
            imgui.TextColored(t.textDim, u8"Список пуст.")
        end
        for i, p in ipairs(r.players) do
            imgui.BeginChild("trp_" .. i, imgui.ImVec2(0, 32), true)
                imgui.Text(p.nickname)
                imgui.SameLine(imgui.GetWindowWidth() - 70)
                imgui.Text(formatDuration(p.seconds))
            imgui.EndChild()
            imgui.Spacing()
        end
    imgui.EndChild()

    imgui.End()
    imgui.PopStyleVar(THEME_ROUNDING_COUNT)
    imgui.PopStyleColor(THEME_COLOR_COUNT)
end

local function drawTrackerReportsTab(t)
    if imgui.Button(fa.ICON_BULLHORN .. u8" Создать отчёт##tracker_create_report", imgui.ImVec2(180, 32)) then
        tracker_report_form_open = true
    end

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    if #trackerReports == 0 then
        imgui.TextColored(t.textDim, u8"Отчётов пока нет.")
        return
    end

    for i = #trackerReports, 1, -1 do
        local r = trackerReports[i]
        imgui.PushID("tracker_report_" .. i)
        local label = r.event .. u8"   |   Время " .. os.date("%H:%M", r.time) .. u8"   |   Дата " .. os.date("%d.%m.%Y", r.time)
        if imgui.Button(label, imgui.ImVec2(-1, 32)) then
            tracker_report_viewer_open = true
            tracker_report_viewer_idx = i
        end
        if imgui.IsItemClicked(2) then
            deleteTrackerReport(i)
        end
        imgui.PopID()
        imgui.Spacing()
    end
end

local CURATOR_SECTIONS = {
    u8"Сбор участников ивента",
    u8"Автозаполнение кураторов на ивенте",
    u8"Автозаполнение актёров на ивенте",
    u8"Менеджер выдачи ролей актёрам",
}
local curators_selected_section = 1

-- пункт 1: старый функционал "Радиус"/"Отчётность" целиком, без изменений
local function drawCuratorsCollectSection(t)
    local pushed = 0
    if tracker_subtab == "radius" then
        imgui.PushStyleColor(imgui.Col.Button, t.accent)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, t.accent)
        pushed = 2
    end
    if imgui.Button(u8"Радиус##tracker_sub_radius", imgui.ImVec2(140, 30)) then
        tracker_subtab = "radius"
    end
    if pushed > 0 then imgui.PopStyleColor(pushed) end

    imgui.SameLine()

    pushed = 0
    if tracker_subtab == "reports" then
        imgui.PushStyleColor(imgui.Col.Button, t.accent)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, t.accent)
        pushed = 2
    end
    if imgui.Button(u8"Отчётность##tracker_sub_reports", imgui.ImVec2(140, 30)) then
        tracker_subtab = "reports"
    end
    if pushed > 0 then imgui.PopStyleColor(pushed) end

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    if tracker_subtab == "radius" then
        drawTrackerRadiusTab(t)
    else
        drawTrackerReportsTab(t)
    end
end

-- ============================================================
--  КУРАТОРЫ: автозаполнение посещаемости (пункт 2)
-- ============================================================
local CURATOR_LIST_URL = "https://script.google.com/macros/s/AKfycbwhudcprJVYxSnMN0f57kaFGD9O4Fy3nPpGJwztmywrZL5CZCHT8M9EEQE2vaxGiQFn2g/exec"
local CURATOR_LIST_PATH = "moonloader\\config\\curators.txt"

curator_list = {}
curator_active = false
curator_event_name = imgui.ImBuffer("", 64)
curator_captured = {}       -- список ников (raw CP1251)
curator_last_scan = 0
curator_list_loading = false

local function encodeUrlComponent(str)
    if not str then return "" end
    str = str:gsub("([^%w %-%_%.%~])", function(c) return ("%%%02X"):format(string.byte(c)) end)
    str = str:gsub(" ", "+")
    return str
end

local function updateCuratorList()
    curator_list_loading = true
    downloadUrlToFile(CURATOR_LIST_URL .. "?action=getList", CURATOR_LIST_PATH, function(id, status)
        curator_list_loading = false
        if status == 6 then
            local f = io.open(CURATOR_LIST_PATH, "r")
            if f then
                local content = f:read("*a")
                f:close()
                curator_list = {}
                for nick in content:gmatch("([^,]+)") do
                    curator_list[#curator_list + 1] = nick:match("^%s*(.-)%s*$")
                end

            end
        else

        end
    end)
end

local function isCuratorNick(name)
    for _, v in ipairs(curator_list) do
        if v:lower() == name:lower() then return true end
    end
    return false
end

local function scanForCurators()
    for pid = 0, sampGetMaxPlayerId() do
        if sampIsPlayerConnected(pid) then
            local name = sampGetPlayerNickname(pid)
            if isCuratorNick(name) then
                local already = false
                for _, v in ipairs(curator_captured) do
                    if v == name then already = true; break end
                end
                if not already then
                    curator_captured[#curator_captured + 1] = name
                    sampAddChatMessage('{5B85C4}[TRPcomm] {FFFFFF}Куратор зафиксирован: {5B85C4}' .. name, -1)
                end
            end
        end
    end
end

local function sendCuratorReport()
    curator_active = false
    if #curator_captured == 0 then
        sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Кураторы не найдены, отправка отменена.', -1)
        return
    end

    local eventText = u8:decode(curator_event_name.v)
    local nicksString = table.concat(curator_captured, ", ")
    local finalUrl = string.format("%s?event=%s&nicknames=%s",
        CURATOR_LIST_URL, encodeUrlComponent(u8(eventText)), encodeUrlComponent(u8(nicksString)))

    sampAddChatMessage('{5B85C4}[TRPcomm] {FFFFFF}Отправка отчёта по кураторам...', -1)
    downloadUrlToFile(finalUrl, "moonloader\\config\\trp_temp.txt", function(id, status)
        if status == 6 then
            sampAddChatMessage('{5B85C4}[TRPcomm] {FFFFFF}Данные по кураторам занесены в таблицу.', -1)
            curator_captured = {}
        else
            sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Ошибка отправки отчёта по кураторам.', -1)
        end
    end)
end

local function drawCuratorsFillCuratorsSection(t)
    imgui.TextColored(t.accent, u8"Автозаполнение кураторов")
    imgui.Spacing()

    if imgui.Button(fa.ICON_RANDOM .. u8" Обновить список кураторов##curator_list_refresh", imgui.ImVec2(230, 28)) then
        if not curator_list_loading then updateCuratorList() end
    end
    imgui.SameLine()
    imgui.TextColored(t.textDim, u8"В списке: " .. #curator_list)

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    imgui.TextColored(t.textDim, u8"Название ивента:")
    imgui.PushItemWidth(300)
    imgui.InputText("##curator_event_name", curator_event_name)
    imgui.PopItemWidth()

    imgui.Spacing()

    if curator_active then
        if imgui.Button(fa.ICON_BULLHORN .. u8" Завершить и отправить##curator_finish", imgui.ImVec2(230, 32)) then
            sendCuratorReport()
        end
        imgui.SameLine()
        imgui.TextColored(t.textDim, u8"Идёт сбор...")
    else
        if imgui.Button(fa.ICON_CROSSHAIRS .. u8" Начать сбор##curator_start", imgui.ImVec2(230, 32)) then
            local nameText = u8:decode(curator_event_name.v)
            if nameText == "" then
                sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Сначала укажи название ивента.', -1)
            else
                curator_active = true
                curator_captured = {}
                sampAddChatMessage('{5B85C4}[TRPcomm] {FFFFFF}Мониторинг кураторов запущен: ' .. nameText, -1)
            end
        end
    end

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    imgui.TextColored(t.textDim, u8"Зафиксированные кураторы:")
    imgui.Spacing()
    if #curator_captured == 0 then
        imgui.TextColored(t.textDim, u8"Пока никого.")
    end
    for i, name in ipairs(curator_captured) do
        imgui.Text(i .. ". " .. name)
    end
end

-- ============================================================
--  КУРАТОРЫ: автозаполнение посещаемости актёров (пункт 3)
-- ============================================================
local ACTORS_GOOGLE_URL = "https://script.google.com/macros/s/AKfycbzAeXxqpPiaK70P9OqI0EgdpzoM0skt-84xiYzLR8Sp5cLLfZMwRsssx4APiaq2pca1eQ/exec"

actors_event_name = imgui.ImBuffer("", 64)
actors_active     = false
actors_captured   = {}      -- список ников (raw CP1251)

local function sendActorsReport()
    if #actors_captured == 0 then
        sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Список актёров пуст, отправка отменена.', -1)
        return
    end

    local eventText = u8:decode(actors_event_name.v)
    local membersUtf8 = {}
    for i, nick in ipairs(actors_captured) do
        membersUtf8[i] = u8(nick)
    end
    local json_data = cjson.encode({ event = u8(eventText), members = membersUtf8 })

    sampAddChatMessage('{5B85C4}[TRPcomm] {FFFFFF}Отправка данных по актёрам...', -1)
    lua_thread.create(function()
        local ok, response = pcall(requests.post, ACTORS_GOOGLE_URL, {
            headers = { ["Content-Type"] = "application/json; charset=UTF-8" },
            data = json_data,
            timeout = 15,
        })

        if not ok then
            sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Ошибка отправки! Проверь интернет или URL.', -1)
            return
        end

        if response.status_code == 200 then
            sampAddChatMessage('{5B85C4}[TRPcomm] {FFFFFF}Данные по актёрам занесены в таблицу.', -1)
            actors_captured = {}
        else
            sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Сервер вернул ошибку ' .. tostring(response.status_code), -1)
        end
    end)
end

local function startActorsCollection()
    local nameText = u8:decode(actors_event_name.v)
    if nameText == "" then
        sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Сначала укажи название ивента.', -1)
        return
    end

    actors_active   = true
    actors_captured = {}
    sampAddChatMessage('{5B85C4}[TRPcomm] {FFFFFF}Сбор актёров запущен: ' .. nameText, -1)
    sampSendChat("/rwave members")

    lua_thread.create(function()
        wait(2500)
        actors_active = false
        sendActorsReport()
    end)
end

local function drawCuratorsFillActorsSection(t)
    imgui.TextColored(t.accent, u8"Автозаполнение актёров")
    imgui.Spacing()

    imgui.TextColored(t.textDim, u8"Название ивента:")
    imgui.PushItemWidth(300)
    imgui.InputText("##actors_event_name", actors_event_name)
    imgui.PopItemWidth()

    imgui.Spacing()

    if actors_active then
        imgui.TextColored(t.textDim, u8"Идёт сбор...")
    else
        if imgui.Button(fa.ICON_CROSSHAIRS .. u8" Начать сбор##actors_start", imgui.ImVec2(230, 32)) then
            startActorsCollection()
        end
    end

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    imgui.TextColored(t.textDim, u8"Зафиксированные актёры:")
    imgui.Spacing()
    if #actors_captured == 0 then
        imgui.TextColored(t.textDim, u8"Пока никого.")
    end
    for i, name in ipairs(actors_captured) do
        imgui.Text(i .. ". " .. name)
    end
end

local function drawCuratorsRoleManagerSection(t)
    imgui.TextColored(t.textDim, u8"Раздел в разработке.")
end

local function drawTrackerTab(t)
    imgui.TextColored(t.accent, fa.ICON_CROSSHAIRS .. u8" КУРАТОРЫ")
    imgui.Separator()
    imgui.Spacing()

    -- ------- левая колонка: список разделов -------
    imgui.BeginChild("CuratorsList", imgui.ImVec2(220, 0), true)
        for i, name in ipairs(CURATOR_SECTIONS) do
            local isActive = (curators_selected_section == i)
            local pushed = 0
            if isActive then
                imgui.PushStyleColor(imgui.Col.Button, t.accent)
                imgui.PushStyleColor(imgui.Col.ButtonHovered, t.accent)
                pushed = 2
            end
            if imgui.Button(name .. "##curator_sec_" .. i, imgui.ImVec2(-1, 36)) then
                curators_selected_section = i
            end
            if pushed > 0 then imgui.PopStyleColor(pushed) end
            imgui.Spacing()
        end
    imgui.EndChild()

    imgui.SameLine()

    -- ------- правая колонка: содержимое выбранного раздела -------
    imgui.BeginChild("CuratorsContent", imgui.ImVec2(0, 0), true)
        if curators_selected_section == 1 then
            drawCuratorsCollectSection(t)
        elseif curators_selected_section == 2 then
            drawCuratorsFillCuratorsSection(t)
        elseif curators_selected_section == 3 then
            drawCuratorsFillActorsSection(t)
        else
            drawCuratorsRoleManagerSection(t)
        end
    imgui.EndChild()
end

drawGalleryTab = function(t)
    if imgui.Button(fa.ICON_RANDOM .. u8" Обновить##gallery_refresh", imgui.ImVec2(150, 28)) then
        scanGallery()
    end
    imgui.SameLine()
    imgui.TextColored(t.textDim, u8"Выбрано: " .. gallerySelectedCount() .. "/" .. GALLERY_MAX_SELECT)
    imgui.Spacing()
    imgui.TextColored(t.textDim, u8"Папка: " .. SCREENS_DIR)

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    if not gallery_scanned then
        scanGallery()
    end

    if #gallery_files == 0 then
        imgui.TextColored(t.textDim, u8"Скриншоты не найдены (или папка недоступна).")
        return
    end

    loadGalleryPage(gallery_page)

    local total_pages = math.ceil(#gallery_files / GALLERY_PER_PAGE)
    local startIdx = (gallery_page - 1) * GALLERY_PER_PAGE + 1
    local endIdx   = math.min(startIdx + GALLERY_PER_PAGE - 1, #gallery_files)

    imgui.BeginChild("GalleryGrid", imgui.ImVec2(0, -46), false)
        local gridAvail = imgui.GetContentRegionAvail()
        local gap = 8
        local cardW = (gridAvail.x - gap * 2) / 3
        local cardH = 140

        local col = 0
        for i = startIdx, endIdx do
            local filename = gallery_files[i]
            imgui.PushID(i)

            local isSelected = gallery_selected[filename]
            if isSelected then
                imgui.PushStyleColor(imgui.Col.Border, t.accent)
            end

            imgui.BeginChild("gcard", imgui.ImVec2(cardW, cardH), true)
                local tex = gallery_textures[filename]
                if tex then
                    local avail = imgui.GetContentRegionAvail()
                    imgui.Image(tex, imgui.ImVec2(avail.x, avail.y))

                    if imgui.IsItemClicked() then
                        gallery_preview_open = true
                        gallery_preview_file = filename
                    end

                    if imgui.IsItemClicked(2) then
                        if isSelected then
                            gallery_selected[filename] = nil
                        else
                            if gallerySelectedCount() < GALLERY_MAX_SELECT then
                                gallery_selected[filename] = true
                            else
                                sampAddChatMessage(u8"{FF6B6B}[TRPcomm] {FFFFFF}Можно выбрать не более 10 скриншотов.", -1)
                            end
                        end
                    end

                    if imgui.BeginPopupContextItem("##gctx") then
                        if isSelected then
                            if imgui.MenuItem(fa.ICON_TIMES .. u8" Снять выбор") then
                                gallery_selected[filename] = nil
                            end
                        else
                            if imgui.MenuItem(fa.ICON_STAR .. u8" Выбрать") then
                                if gallerySelectedCount() < GALLERY_MAX_SELECT then
                                    gallery_selected[filename] = true
                                else
                                    sampAddChatMessage(u8"{FF6B6B}[TRPcomm] {FFFFFF}Можно выбрать не более 10 скриншотов.", -1)
                                end
                            end
                        end
                        imgui.Separator()
                        if imgui.MenuItem(fa.ICON_BULLHORN .. u8" Отправить отчёт") then
                            local filesToSend = {}
                            for fname in pairs(gallery_selected) do
                                filesToSend[#filesToSend + 1] = fname
                            end
                            if #filesToSend == 0 then
                                sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Сначала выбери хотя бы один скриншот {5B85C4}(ПКМ -> Выбрать).', -1)
                            else
                                gallery_pending_files = filesToSend
                                gallery_send_form_open = true
                            end
                        end
                        imgui.EndPopup()
                    end
                elseif tex == false then
                    imgui.SetCursorPos(imgui.ImVec2(10, 55))
                    imgui.TextColored(t.textDim, u8"нет превью")
                else
                    imgui.SetCursorPos(imgui.ImVec2(10, 55))
                    imgui.TextColored(t.textDim, u8"загрузка...")
                end
            imgui.EndChild()

            if isSelected then imgui.PopStyleColor() end
            imgui.PopID()
            col = col + 1
            if col < 3 then imgui.SameLine(0, gap) else col = 0 end
        end
    imgui.EndChild()

    imgui.Spacing()
    if gallery_page > 1 then
        if imgui.Button(fa.ICON_ARROW_LEFT .. "##gal_prev", imgui.ImVec2(40, 28)) then
            gallery_page = gallery_page - 1
        end
        imgui.SameLine()
    end
    imgui.Text(u8"Стр. " .. gallery_page .. " / " .. total_pages)
    if gallery_page < total_pages then
        imgui.SameLine()
        if imgui.Button(fa.ICON_ARROW_RIGHT .. "##gal_next", imgui.ImVec2(40, 28)) then
            gallery_page = gallery_page + 1
        end
    end
end

-- ============================================================
--  ОТЧЁТЫ: их хранение
--  moonloader\config\TRPcomm Manager Config\reports\index.ini
-- ============================================================
local defaultReportsIndex = { reports = { count = "0" } }

ensureIniFile(REPORTS_INDEX_PATH, "reports", { "count=0" })

local reportsIndexIni = inicfg.load(defaultReportsIndex, REPORTS_INDEX_PATH) or defaultReportsIndex

local reports = {} -- { {id=, event=(u8-текст), time=os.time(), files={filename, ...}}, ... }

local function saveReportsIndex()
    local cfg = { reports = { count = tostring(#reports) } }
    for i, r in ipairs(reports) do
        cfg.reports["report" .. i .. "_id"]    = r.id
        cfg.reports["report" .. i .. "_event"] = u8:decode(r.event)
        cfg.reports["report" .. i .. "_time"]  = tostring(r.time)
        cfg.reports["report" .. i .. "_files"] = table.concat(r.files, "|")
    end
    inicfg.save(cfg, REPORTS_INDEX_PATH)
    reportsIndexIni = cfg
end

addReport = function(eventNameUtf8, files)
    reports[#reports + 1] = {
        id = "report_" .. os.time() .. "_" .. tostring(math.random(1000, 9999)),
        event = eventNameUtf8,
        time = os.time(),
        files = files,
    }
    saveReportsIndex()
end

local function deleteReport(idx)
    if not reports[idx] then return end
    table.remove(reports, idx)
    saveReportsIndex()
end

-- загружаем список отчётов при первом запуске
local reportsCount = tonumber(reportsIndexIni.reports.count) or 0
for i = 1, reportsCount do
    local id       = reportsIndexIni.reports["report" .. i .. "_id"]
    local eventRaw = reportsIndexIni.reports["report" .. i .. "_event"]
    local timeRaw  = reportsIndexIni.reports["report" .. i .. "_time"]
    local filesRaw = reportsIndexIni.reports["report" .. i .. "_files"]
    if id then
        local files = {}
        if filesRaw and filesRaw ~= "" then
            for fname in filesRaw:gmatch("[^|]+") do
                files[#files + 1] = fname
            end
        end
        reports[#reports + 1] = {
            id = id,
            event = u8(eventRaw or ""),
            time = tonumber(timeRaw) or 0,
            files = files,
        }
    end
end

-- ---------- Окно просмотра отчёта ----------
report_viewer_open = false
report_viewer_idx = nil

local function drawReportViewer(t)
    if not report_viewer_open or not report_viewer_idx then return end
    local r = reports[report_viewer_idx]
    if not r then report_viewer_open = false; return end

    local sw, sh = getScreenResolution()
    imgui.SetNextWindowSize(imgui.ImVec2(sw * 0.6, sh * 0.7), imgui.Cond.Always)
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))

    pushThemeColors()
    pushThemeRounding()

    local open = imgui.ImBool(true)
    imgui.Begin(r.event .. "##report_viewer", open,
        imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize)
    if not open.v then report_viewer_open = false end

    imgui.TextColored(t.textDim, os.date("%d.%m.%Y  %H:%M", r.time))
    imgui.Separator()
    imgui.Spacing()

    imgui.BeginChild("ReportViewerGrid", imgui.ImVec2(0, 0), false)
        local gridAvail = imgui.GetContentRegionAvail()
        local gap = 8
        local cardW = (gridAvail.x - gap * 3) / 4
        local col = 0
        for i, filename in ipairs(r.files) do
            imgui.PushID(i)
            local tex = loadGalleryTexture(filename)
            imgui.BeginChild("rcard", imgui.ImVec2(cardW, 100), true)
                if tex then
                    local avail = imgui.GetContentRegionAvail()
                    imgui.Image(tex, imgui.ImVec2(avail.x, avail.y))
                    if imgui.IsItemClicked() then
                        gallery_preview_open = true
                        gallery_preview_file = filename
                    end
                else
                    imgui.SetCursorPos(imgui.ImVec2(10, 40))
                    imgui.TextColored(t.textDim, u8"нет файла")
                end
            imgui.EndChild()
            imgui.PopID()
            col = col + 1
            if col < 4 then imgui.SameLine(0, gap) else col = 0 end
        end
    imgui.EndChild()

    imgui.End()
    imgui.PopStyleVar(THEME_ROUNDING_COUNT)
    imgui.PopStyleColor(THEME_COLOR_COUNT)
end

drawReportsTab = function(t)
    imgui.TextColored(t.textDim, u8"История отправленных отчётов:")
    imgui.Spacing()

    if #reports == 0 then
        imgui.TextColored(t.textDim, u8"Отчётов пока нет.")
        return
    end

    for i = #reports, 1, -1 do
        local r = reports[i]
        imgui.PushID("report_" .. i)
        local label = r.event .. u8"   |   Время " .. os.date("%H:%M", r.time) .. u8"   |   Дата " .. os.date("%d.%m.%Y", r.time)
        if imgui.Button(label, imgui.ImVec2(-1, 32)) then
            report_viewer_open = true
            report_viewer_idx = i
        end
        if imgui.IsItemClicked(2) then
            deleteReport(i)
        end
        imgui.PopID()
        imgui.Spacing()
    end
end

-- ============================================================
--  ОТРИСОВКА ОКНА
-- ============================================================

function imgui.BeforeDrawFrame()
    if fa_font == nil then
        local font_config = imgui.ImFontConfig()
        font_config.MergeMode = true
        fa_font = imgui.GetIO().Fonts:AddFontFromFileTTF(
            'moonloader/resource/fonts/fontawesome-webfont.ttf',
            14.0, font_config, fa_glyph_ranges)
    end
    if fa_font_large == nil then
        local font_config_large = imgui.ImFontConfig()
        fa_font_large = imgui.GetIO().Fonts:AddFontFromFileTTF(
            'moonloader/resource/fonts/fontawesome-webfont.ttf',
            84.0, font_config_large, fa_glyph_ranges)
    end
    if arial_font == nil and not arial_font_failed then
        local font_path = getFolderPath(0x14) .. '\\arial.ttf'
        if doesFileExist(font_path) then
            local builder = imgui.ImFontAtlasGlyphRangesBuilder()
            builder:AddRanges(imgui.GetIO().Fonts:GetGlyphRangesCyrillic())
            local arial_ranges = builder:BuildRanges()
            arial_font = imgui.GetIO().Fonts:AddFontFromFileTTF(font_path, 20.0, nil, arial_ranges)

            local builder_small = imgui.ImFontAtlasGlyphRangesBuilder()
            builder_small:AddRanges(imgui.GetIO().Fonts:GetGlyphRangesCyrillic())
            local arial_ranges_small = builder_small:BuildRanges()
            arial_font_small = imgui.GetIO().Fonts:AddFontFromFileTTF(font_path, 15.0, nil, arial_ranges_small)
        else
            arial_font_failed = true
        end
    end
end

calendar_tab_active_last_frame = false
curator_section_active_last_frame = false

function imgui.OnDrawFrame()
        if not main_window_state.v then
        calendar_tab_active_last_frame = false
        curator_section_active_last_frame = false
        return
    end

    local t = getTheme()
    local sw, sh = getScreenResolution()
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(900, 600), imgui.Cond.FirstUseEver)

    pushThemeColors()
    pushThemeRounding()

    imgui.Begin("##trpcomm_main", main_window_state,
        imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar)

        imgui.TextColored(t.accent, u8 "TRPcomm MANAGER | Актуальная версия: 1.0")
        imgui.SameLine(imgui.GetWindowWidth() - 34)
        if imgui.Button(fa.ICON_TIMES, imgui.ImVec2(24, 24)) then
            main_window_state.v = false
        end

        imgui.Separator()
        imgui.Spacing()

        -- ---------- Строка вкладок (как в браузере) ----------
        imgui.BeginChild("TabStrip", imgui.ImVec2(0, 28), false)
            imgui.PushStyleVar(imgui.StyleVar.FrameRounding, 3.0)
            imgui.PushStyleVar(imgui.StyleVar.FramePadding, imgui.ImVec2(10, 4))
            imgui.PushStyleColor(imgui.Col.Button, t.panelBg)
            imgui.PushStyleColor(imgui.Col.ButtonHovered, t.buttonHov)

            local closeIdx = nil
            local tabW = 120

            for i, tb in ipairs(open_tabs) do
                if i > 1 then imgui.SameLine(0, 1) end
                local isActive = (i == active_tab_idx)
                local pushed = 0
                if isActive then
                    imgui.PushStyleColor(imgui.Col.Button, t.accent)
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, t.accent)
                    pushed = 2
                end
                imgui.PushID("tabbtn" .. i)

                local w = tb.closable and tabW or (tabW + 30)
                if imgui.Button(tb.title, imgui.ImVec2(w, 22)) then
                    active_tab_idx = i
                end

                if imgui.IsItemHovered() then
                    if tb.closable then
                        imgui.SetTooltip(tb.title .. u8" | ЛКМ — Открыть страницу | Колёсико — Закрыть страницу")
                    else
                        imgui.SetTooltip(tb.title .. u8" | ЛКМ — Открыть страницу")
                    end
                end

                if tb.closable then
                    -- закрытие колёсиком мыши
                    if imgui.IsItemClicked(2) then
                        closeIdx = i
                    end

                    -- перетаскивание ЛКМ для смены порядка (не даём утащить на место "Домашней")
                    if imgui.IsItemActive() and not imgui.IsItemHovered() then
                        local delta = imgui.GetMouseDragDelta(0)
                        if delta.x < -(w / 2) and i > 2 then
                            open_tabs[i], open_tabs[i - 1] = open_tabs[i - 1], open_tabs[i]
                            if active_tab_idx == i then active_tab_idx = i - 1
                            elseif active_tab_idx == i - 1 then active_tab_idx = i end
                            imgui.ResetMouseDragDelta(0)
                        elseif delta.x > (w / 2) and i < #open_tabs then
                            open_tabs[i], open_tabs[i + 1] = open_tabs[i + 1], open_tabs[i]
                            if active_tab_idx == i then active_tab_idx = i + 1
                            elseif active_tab_idx == i + 1 then active_tab_idx = i end
                            imgui.ResetMouseDragDelta(0)
                        end
                    end
                end

                imgui.PopID()
                if pushed > 0 then imgui.PopStyleColor(pushed) end
            end

            imgui.PopStyleColor(2)

            imgui.SameLine(imgui.GetWindowWidth() - 100)
            if imgui.Button(fa.ICON_CALENDAR, imgui.ImVec2(30, 22)) then
                openTab("calendar", u8"Календарь")
            end
            imgui.SameLine(0, 2)
            if imgui.Button(fa.ICON_STICKY_NOTE, imgui.ImVec2(30, 22)) then
                openTab("notes", u8"Нотатки")
            end
            imgui.SameLine(0, 2)
            if imgui.Button(fa.ICON_COG, imgui.ImVec2(30, 22)) then
                openTab("settings", u8"Настройки")
            end

            imgui.PopStyleVar(2)

            if closeIdx then closeTab(closeIdx) end
        imgui.EndChild()

        imgui.Spacing()

                -- ---------- Содержимое активной вкладки ----------
        local calendarShouldBeVisible = open_tabs[active_tab_idx] and (
            open_tabs[active_tab_idx].kind == "calendar"
            or open_tabs[active_tab_idx].kind == "hr"
        )
        if calendarShouldBeVisible and not calendar_tab_active_last_frame and not calendar_loading then
            fetchCalendarEvents()
        end
        calendar_tab_active_last_frame = calendarShouldBeVisible

        local curatorsSectionShouldBeVisible = open_tabs[active_tab_idx]
            and open_tabs[active_tab_idx].kind == "tracker"
            and curators_selected_section == 2
        if curatorsSectionShouldBeVisible and not curator_section_active_last_frame and not curator_list_loading then
            updateCuratorList()
        end
        curator_section_active_last_frame = curatorsSectionShouldBeVisible

        imgui.BeginChild("TabContent", imgui.ImVec2(0, 0), true)
            local activeTab = open_tabs[active_tab_idx]
            if activeTab then
                if activeTab.kind == "home" then
                    drawHomeTab(t)
                elseif activeTab.kind == "notes" then
                    drawNotesTab(t)
                elseif activeTab.kind == "roles" then
                    drawRolesTab(t)
                elseif activeTab.kind == "settings" then
                    drawSettingsTab(t)
                elseif activeTab.kind == "photographer" then
                    drawPhotographerTab(t)
                elseif activeTab.kind == "tracker" then
                    drawTrackerTab(t)
                elseif activeTab.kind == "hr" then
                    drawHRTab(t)
                elseif activeTab.kind == "calendar" then
                    drawHRCalendarTab(t)
                end
            end
        imgui.EndChild()

    imgui.End()
    imgui.PopStyleVar(THEME_ROUNDING_COUNT)
    imgui.PopStyleColor(THEME_COLOR_COUNT)

    drawGalleryPreview(t)
    drawGallerySendReportForm(t)
    drawReportViewer(t)
    drawTrackerCreateReportForm(t)
    drawTrackerReportViewer(t)
    drawAdAddForm(t)
end

sampev.onShowDialog = function(dialogId, style, title, button1, button2, text)
    if ad_pending then
        if dialogId == 3409 and title:find("Создание объявления") then
            sampSendDialogResponse(dialogId, 1, 0, "")
            return false
        end
        if dialogId == 3410 and title:find("Отправка рекламы на радио") then
            sampSendDialogResponse(dialogId, 1, 0, ad_pending_text)
            sampAddChatMessage('{5B85C4}[TRPcomm] {FFFFFF}Объявление отправлено на модерацию.', -1)
            ad_pending = false
            ad_text.v = ""
            if ad_auto_send.v then
                ad_next_send_time = os.time() + (ad_interval_minutes.v * 60)
            end
            return false
        end
    end

    if dialogId == 45 and text and text:find("Ваше объявление") then
        sampSendDialogResponse(dialogId, 1, 65535, "")
        return false
    end
end

sampev.onServerMessage = function(color, text)
    if ad_pending then
        if text:find("Одно из ваших объявлений уже находится в очереди на модерацию") then
            sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Одно из объявлений уже в очереди на модерацию.', -1)
            ad_pending = false
        elseif text:find("Нельзя отправлять рекламу на радио слишком часто") then
            sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Слишком часто — подожди немного и попробуй снова.', -1)
            ad_pending = false
            if ad_auto_send.v then
                local secs = tonumber(text:match("через (%d+)"))
                ad_next_send_time = os.time() + (secs and (secs + 2) or 60)
            end
        end
    end

    if actors_active then
        local clean = text:gsub("{%x%x%x%x%x%x}", "")
        local nick = clean:match("Ник%s+([%w_]+)")
        if nick then
            nick = nick:gsub("%.", "")
            actors_captured[#actors_captured + 1] = nick
            return false
        end
    end
end

-- ============================================================
--  ТОЧКА ВХОДА
-- ============================================================
function main()
    repeat wait(0) until isSampAvailable()

    local result, my1id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    clientName = sampGetPlayerNickname(my1id)

    checkForUpdates()

    sampAddChatMessage('{5B85C4}[TRPcomm Manager]{FFFFFF} Добро пожаловать на сервер, {5B85C4}' .. clientName .. '{FFFFFF}.', -1)
    sampAddChatMessage('{FFFFFF}Для активации скрипта используйте команду — {5B85C4}/trpcomm {FFFFFF}или {5B85C4}' .. hotkey_display.v .. '{FFFFFF}.', -1)

        sampRegisterChatCommand('trpcomm', function()
        main_window_state.v = not main_window_state.v
    end)

    while true do
        wait(0)
        imgui.Process = main_window_state.v

                if tracker_active and os.time() ~= tracker_last_update then
            tracker_last_update = os.time()
            updateTrackerRadius()
        end

        if curator_active and os.time() ~= curator_last_scan then
            curator_last_scan = os.time()
            scanForCurators()
        end

        if ad_auto_send.v and not ad_pending and os.time() >= ad_next_send_time then
            triggerNextAdSend()
        end

        if not waiting_for_key and not waiting_for_key2 and not sampIsChatInputActive() and not sampIsDialogActive() then
            local altOk   = (isKeyDown(0x12) or isKeyDown(0xA4) or isKeyDown(0xA5)) == hotkey_alt.v
            local ctrlOk  = (isKeyDown(0x11) or isKeyDown(0xA2) or isKeyDown(0xA3)) == hotkey_ctrl.v
            local shiftOk = (isKeyDown(0x10) or isKeyDown(0xA0) or isKeyDown(0xA1)) == hotkey_shift.v
            if altOk and ctrlOk and shiftOk and isKeyJustPressed(hotkey_key.v) then
                main_window_state.v = not main_window_state.v
            end

            if hotkey2_key.v ~= 0 then
                local alt2Ok   = (isKeyDown(0x12) or isKeyDown(0xA4) or isKeyDown(0xA5)) == hotkey2_alt.v
                local ctrl2Ok  = (isKeyDown(0x11) or isKeyDown(0xA2) or isKeyDown(0xA3)) == hotkey2_ctrl.v
                local shift2Ok = (isKeyDown(0x10) or isKeyDown(0xA0) or isKeyDown(0xA1)) == hotkey2_shift.v
                if alt2Ok and ctrl2Ok and shift2Ok and isKeyJustPressed(hotkey2_key.v) then
                    local freq = u8:decode(radio_freq.v)
                    local pass = u8:decode(radio_pass.v)
                    local tpPass = u8:decode(teleport_pass.v)
                    if freq ~= "" then
                        if pass ~= "" then
                            sampSendChat(string.format("/rwave join %s %s", freq, pass))
                        else
                            sampSendChat(string.format("/rwave join %s", freq))
                        end
                        if tpPass ~= "" then
                            sampSendChat(string.format("/video %s", tpPass))
                        end
                    else
                        sampAddChatMessage(u8"{FF6B6B}[TRPcomm] Сначала укажи частоту рации в настройках.", -1)

                    end
                end
            end
        end
    end
end
