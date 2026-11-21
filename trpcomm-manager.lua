-- =========================
--  TRPcomm MANAGER
--  Актуальная версия: 3.0
-- =========================

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
base64 = require 'base64'

GCAL_ID = "e750c65e6ebd96513d62dca03f7b23a0746137364a24d4daba502a4e555756bc@group.calendar.google.com"
GCAL_API_KEY = "AIzaSyBtsyCi9A0ikrclVl919OfPC2z5rlaHZs4"
TG_BOT_TOKEN = "text"
TG_CHAT_ID = "-1003174705842"
TG_THREAD_ID = "9"

local ACCESS_BASE_URL = "https://raw.githubusercontent.com/squaliee/TRPcomm-Manager-Updates/main/"
local ACCESS_SECTIONS = { "photographers", "curators", "advertising", "actors" }

local ACCESS_KEY_ALIASES = {
    roles = "actors",
    actors = "actors",
    photographer = "photographers",
    photographers = "photographers",
    tracker = "curators",
    curators = "curators",
    hr = "advertising",
    advertising = "advertising",
    quicksms = "advertising",
}

access_lists = {} -- access_lists["photographers"] = {"Nick_One", ...} ; nil = ещё не загружен

function performHttpGet(url, args, onSuccess, onError)
    args = args or { timeout = 12 }
    local ok_effil, effil = pcall(require, 'effil')
    if ok_effil and effil and effil.thread then
        local runner = effil.thread(function(u, a)
            local req = require 'requests'
            local ok, resp = pcall(req.request, "GET", u, a)
            if ok and resp then
                return {
                    status_code = resp.status_code,
                    text = resp.text,
                    headers = resp.headers,
                    url = resp.url
                }
            else
                return nil, tostring(resp)
            end
        end)
        local thread = runner(url, args)
        lua_thread.create(function()
            while thread:status() == 'running' do
                wait(0)
            end
            local ok, result, err = pcall(thread.get, thread)
            if ok and result then
                if onSuccess then onSuccess(result) end
            else
                if onError then onError(err or result) end
            end
        end)
        return
    end
    local asyncHttpAvailable, asyncHttp = pcall(require, 'asyncHttpRequest')
    if asyncHttpAvailable and asyncHttp and asyncHttp.request then
        asyncHttp.request("GET", url, args, function(response)
            if onSuccess then onSuccess(response) end
        end, function(err)
            if onError then onError(err) end
        end)
    else
        lua_thread.create(function()
            local ok, response = pcall(requests.get, url, args)
            if ok and response then
                if onSuccess then onSuccess(response) end
            else
                if onError then onError(response) end
            end
        end)
    end
end

local function loadAccessList(sectionKey)
    local filename = "access_" .. sectionKey .. ".txt"
    local url = ACCESS_BASE_URL .. filename .. "?cb=" .. os.time()
    performHttpGet(url, { timeout = 12 }, function(response)
        if not response or response.status_code ~= 200 then
            access_lists[sectionKey] = {}
            if sectionKey == "photographers" then access_lists["photographer"] = {} end
            if sectionKey == "curators" then access_lists["tracker"] = {} end
            if sectionKey == "actors" then access_lists["roles"] = {} end
            if sectionKey == "advertising" then access_lists["hr"] = {} end
            return
        end

        local list = {}
        for nick in response.text:gmatch("[^,%s]+") do
            list[#list + 1] = nick
        end
        access_lists[sectionKey] = list
        if sectionKey == "photographers" then access_lists["photographer"] = list end
        if sectionKey == "curators" then access_lists["tracker"] = list end
        if sectionKey == "actors" then access_lists["roles"] = list end
        if sectionKey == "advertising" then access_lists["hr"] = list end
    end, function(err)
        access_lists[sectionKey] = {}
        if sectionKey == "photographers" then access_lists["photographer"] = {} end
        if sectionKey == "curators" then access_lists["tracker"] = {} end
        if sectionKey == "actors" then access_lists["roles"] = {} end
        if sectionKey == "advertising" then access_lists["hr"] = {} end
    end)
end

local function loadAllAccessLists()
    for _, key in ipairs(ACCESS_SECTIONS) do
        loadAccessList(key)
    end
end

local function hasAccess(sectionKey)
    local realKey = ACCESS_KEY_ALIASES[sectionKey] or sectionKey
    local list = access_lists[realKey] or access_lists[sectionKey]
    if not list then return false end
    if not clientName or clientName == "" then
        local ok, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
        if ok and myId and myId >= 0 then
            clientName = sampGetPlayerNickname(myId)
        end
    end
    if not clientName then return false end
    for _, nick in ipairs(list) do
        if nick:lower() == clientName:lower() then return true end
    end
    return false
end

SCRIPT_VERSION = "3.0"
UPDATE_MANIFEST_URL = "https://raw.githubusercontent.com/squaliee/TRPcomm-Manager-Updates/main/version.txt"

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

local function normalizeRawUrl(url)
    local user, repo, branch, path = url:match("^https?://github%.com/([^/]+)/([^/]+)/raw/refs/heads/([^/]+)/(.+)$")
    if user then
        return "https://raw.githubusercontent.com/" .. user .. "/" .. repo .. "/" .. branch .. "/" .. path
    end
    return url
end

local function checkForUpdates()
    performHttpGet(UPDATE_MANIFEST_URL .. "?cb=" .. os.time(), { timeout = 12 }, function(response)
        if not response or response.status_code ~= 200 then return end

        local lines = {}
        for line in response.text:gmatch("[^\r\n]+") do
            lines[#lines + 1] = line
        end
        local remoteVersion, downloadUrl = lines[1], lines[2]
        if not remoteVersion or not downloadUrl then return end
        downloadUrl = normalizeRawUrl(downloadUrl)

        if isNewerVersion(remoteVersion, SCRIPT_VERSION) then
            lua_thread.create(function()
                sampAddChatMessage('{5B85C4}[TRPcomm] {FFFFFF}Найдена новая версия ' .. remoteVersion .. ', скачиваю...', -1)

                local tempPath = "moonloader\\trpcomm_update_tmp.lua"
                os.remove(tempPath)
                downloadUrlToFile(downloadUrl .. "?cb=" .. os.time(), tempPath, function() end)

                local lastSize, stableTicks, waitedMs = -1, 0, 0
                while waitedMs < 20000 and stableTicks < 3 do
                    wait(500)
                    waitedMs = waitedMs + 500
                    local f = io.open(tempPath, "rb")
                    if f then
                        local size = f:seek("end")
                        f:close()
                        stableTicks = (size == lastSize and size > 0) and (stableTicks + 1) or 0
                        lastSize = size
                    end
                end

                local fr = io.open(tempPath, "rb")
                local content = fr and fr:read("*a")
                if fr then fr:close() end

                local looksValid = content
                    and #content > 5000
                    and content:find("function main()", 1, true)
                    and not content:find("\239\187\191", 1, true)

                if looksValid then
                    local targetPath = thisScript().path
                    os.remove(targetPath)
                    os.rename(tempPath, targetPath)
                    sampAddChatMessage('{5B85C4}[TRPcomm] {FFFFFF}Скрипт успешно обновлён, перезайдите в игру чтобы применить изменения.', -1)
                else
                    sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Скачанный файл выглядит битым, обновление отменено — рабочий скрипт не тронут.', -1)
                    os.remove(tempPath)
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
    typedef void* LPDIRECT3DDEVICE9;
    typedef void* LPDIRECT3DTEXTURE9;
    typedef unsigned int UINT;
    typedef unsigned long DWORD;
    typedef int HRESULT;
    HRESULT __stdcall D3DXCreateTextureFromFileExA(
        LPDIRECT3DDEVICE9 pDevice,
        const char* pSrcFile,
        UINT Width,
        UINT Height,
        UINT MipLevels,
        DWORD Usage,
        int Format,
        int Pool,
        DWORD Filter,
        DWORD MipFilter,
        DWORD ColorKey,
        void* pSrcInfo,
        void* pPalette,
        LPDIRECT3DTEXTURE9* ppTexture
    );
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

    -- 6. Киберпанк (Глубокий темный фон с неоново-розовыми и циановыми акцентами)
    {
        name       = u8"Киберпанк",
        windowBg   = imgui.ImVec4(0.05, 0.04, 0.07, 0.97),
        titleBg    = imgui.ImVec4(0.55, 0.10, 0.40, 1.00),
        panelBg    = imgui.ImVec4(0.09, 0.07, 0.12, 1.00),
        button     = imgui.ImVec4(0.55, 0.10, 0.40, 1.00),
        buttonHov  = imgui.ImVec4(0.70, 0.15, 0.55, 1.00),
        buttonAct  = imgui.ImVec4(0.40, 0.05, 0.30, 1.00),
        header     = imgui.ImVec4(0.55, 0.10, 0.40, 1.00),
        headerHov  = imgui.ImVec4(0.70, 0.15, 0.55, 1.00),
        headerAct  = imgui.ImVec4(0.40, 0.05, 0.30, 1.00),
        frameBg    = imgui.ImVec4(0.12, 0.09, 0.16, 1.00),
        border     = imgui.ImVec4(0.70, 0.20, 0.55, 0.45),
        accent     = imgui.ImVec4(0.10, 0.90, 0.90, 1.00),
        text       = imgui.ImVec4(0.95, 0.92, 1.00, 1.00),
        textDim    = imgui.ImVec4(0.60, 0.50, 0.75, 1.00),
    },

    -- 7. Бирюзовая (Морская бездна, темный сине-зеленый)
    {
        name       = u8"Бирюзовая",
        windowBg   = imgui.ImVec4(0.03, 0.06, 0.07, 0.97),
        titleBg    = imgui.ImVec4(0.10, 0.40, 0.45, 1.00),
        panelBg    = imgui.ImVec4(0.06, 0.10, 0.12, 1.00),
        button     = imgui.ImVec4(0.10, 0.40, 0.45, 1.00),
        buttonHov  = imgui.ImVec4(0.15, 0.55, 0.60, 1.00),
        buttonAct  = imgui.ImVec4(0.05, 0.30, 0.35, 1.00),
        header     = imgui.ImVec4(0.10, 0.40, 0.45, 1.00),
        headerHov  = imgui.ImVec4(0.15, 0.55, 0.60, 1.00),
        headerAct  = imgui.ImVec4(0.05, 0.30, 0.35, 1.00),
        frameBg    = imgui.ImVec4(0.08, 0.14, 0.16, 1.00),
        border     = imgui.ImVec4(0.20, 0.60, 0.65, 0.45),
        accent     = imgui.ImVec4(0.25, 0.85, 0.90, 1.00),
        text       = imgui.ImVec4(0.90, 0.98, 1.00, 1.00),
        textDim    = imgui.ImVec4(0.50, 0.70, 0.75, 1.00),
    },

    -- 8. Золотая (Премиальная, почти черный фон с приглушенным золотом)
    {
        name       = u8"Золотая",
        windowBg   = imgui.ImVec4(0.07, 0.07, 0.07, 0.98),
        titleBg    = imgui.ImVec4(0.45, 0.35, 0.10, 1.00),
        panelBg    = imgui.ImVec4(0.10, 0.10, 0.10, 1.00),
        button     = imgui.ImVec4(0.45, 0.35, 0.10, 1.00),
        buttonHov  = imgui.ImVec4(0.60, 0.45, 0.15, 1.00),
        buttonAct  = imgui.ImVec4(0.35, 0.25, 0.05, 1.00),
        header     = imgui.ImVec4(0.45, 0.35, 0.10, 1.00),
        headerHov  = imgui.ImVec4(0.60, 0.45, 0.15, 1.00),
        headerAct  = imgui.ImVec4(0.35, 0.25, 0.05, 1.00),
        frameBg    = imgui.ImVec4(0.13, 0.13, 0.13, 1.00),
        border     = imgui.ImVec4(0.65, 0.50, 0.15, 0.40),
        accent     = imgui.ImVec4(0.90, 0.70, 0.20, 1.00),
        text       = imgui.ImVec4(0.98, 0.95, 0.90, 1.00),
        textDim    = imgui.ImVec4(0.65, 0.60, 0.50, 1.00),
    },

    -- 9. Токсичная (Матовый черный с кислотно-зелеными элементами)
    {
        name       = u8"Токсичная",
        windowBg   = imgui.ImVec4(0.04, 0.04, 0.04, 0.97),
        titleBg    = imgui.ImVec4(0.30, 0.50, 0.10, 1.00),
        panelBg    = imgui.ImVec4(0.08, 0.08, 0.08, 1.00),
        button     = imgui.ImVec4(0.30, 0.50, 0.10, 1.00),
        buttonHov  = imgui.ImVec4(0.40, 0.65, 0.15, 1.00),
        buttonAct  = imgui.ImVec4(0.20, 0.35, 0.05, 1.00),
        header     = imgui.ImVec4(0.30, 0.50, 0.10, 1.00),
        headerHov  = imgui.ImVec4(0.40, 0.65, 0.15, 1.00),
        headerAct  = imgui.ImVec4(0.20, 0.35, 0.05, 1.00),
        frameBg    = imgui.ImVec4(0.12, 0.12, 0.12, 1.00),
        border     = imgui.ImVec4(0.45, 0.75, 0.15, 0.40),
        accent     = imgui.ImVec4(0.65, 0.95, 0.20, 1.00),
        text       = imgui.ImVec4(0.90, 1.00, 0.90, 1.00),
        textDim    = imgui.ImVec4(0.55, 0.70, 0.55, 1.00),
    },

    -- 10. Бордовая (Благородный винный оттенок, темнее и холоднее красной)
    {
        name       = u8"Бордовая",
        windowBg   = imgui.ImVec4(0.07, 0.04, 0.05, 0.97),
        titleBg    = imgui.ImVec4(0.35, 0.10, 0.15, 1.00),
        panelBg    = imgui.ImVec4(0.11, 0.07, 0.08, 1.00),
        button     = imgui.ImVec4(0.35, 0.10, 0.15, 1.00),
        buttonHov  = imgui.ImVec4(0.45, 0.15, 0.22, 1.00),
        buttonAct  = imgui.ImVec4(0.25, 0.05, 0.10, 1.00),
        header     = imgui.ImVec4(0.35, 0.10, 0.15, 1.00),
        headerHov  = imgui.ImVec4(0.45, 0.15, 0.22, 1.00),
        headerAct  = imgui.ImVec4(0.25, 0.05, 0.10, 1.00),
        frameBg    = imgui.ImVec4(0.15, 0.09, 0.11, 1.00),
        border     = imgui.ImVec4(0.50, 0.15, 0.25, 0.45),
        accent     = imgui.ImVec4(0.80, 0.25, 0.35, 1.00),
        text       = imgui.ImVec4(0.98, 0.90, 0.92, 1.00),
        textDim    = imgui.ImVec4(0.70, 0.50, 0.55, 1.00),
    },

    -- 11. Терминал (Абсолютно черный фон, хакерский зеленый)
    {
        name       = u8"Терминал",
        windowBg   = imgui.ImVec4(0.02, 0.02, 0.02, 0.98),
        titleBg    = imgui.ImVec4(0.05, 0.25, 0.10, 1.00),
        panelBg    = imgui.ImVec4(0.05, 0.05, 0.05, 1.00),
        button     = imgui.ImVec4(0.05, 0.25, 0.10, 1.00),
        buttonHov  = imgui.ImVec4(0.10, 0.35, 0.15, 1.00),
        buttonAct  = imgui.ImVec4(0.02, 0.15, 0.05, 1.00),
        header     = imgui.ImVec4(0.05, 0.25, 0.10, 1.00),
        headerHov  = imgui.ImVec4(0.10, 0.35, 0.15, 1.00),
        headerAct  = imgui.ImVec4(0.02, 0.15, 0.05, 1.00),
        frameBg    = imgui.ImVec4(0.08, 0.08, 0.08, 1.00),
        border     = imgui.ImVec4(0.15, 0.45, 0.20, 0.50),
        accent     = imgui.ImVec4(0.20, 0.85, 0.30, 1.00),
        text       = imgui.ImVec4(0.70, 1.00, 0.70, 1.00),
        textDim    = imgui.ImVec4(0.40, 0.65, 0.40, 1.00),
    },

    -- 12. Ретровейв (Смесь темного индиго и мадженты)
    {
        name       = u8"Ретровейв",
        windowBg   = imgui.ImVec4(0.06, 0.03, 0.10, 0.97),
        titleBg    = imgui.ImVec4(0.45, 0.15, 0.60, 1.00),
        panelBg    = imgui.ImVec4(0.10, 0.05, 0.15, 1.00),
        button     = imgui.ImVec4(0.45, 0.15, 0.60, 1.00),
        buttonHov  = imgui.ImVec4(0.60, 0.20, 0.75, 1.00),
        buttonAct  = imgui.ImVec4(0.30, 0.10, 0.45, 1.00),
        header     = imgui.ImVec4(0.45, 0.15, 0.60, 1.00),
        headerHov  = imgui.ImVec4(0.60, 0.20, 0.75, 1.00),
        headerAct  = imgui.ImVec4(0.30, 0.10, 0.45, 1.00),
        frameBg    = imgui.ImVec4(0.14, 0.08, 0.20, 1.00),
        border     = imgui.ImVec4(0.65, 0.25, 0.85, 0.45),
        accent     = imgui.ImVec4(0.95, 0.35, 0.75, 1.00),
        text       = imgui.ImVec4(0.95, 0.90, 1.00, 1.00),
        textDim    = imgui.ImVec4(0.65, 0.50, 0.80, 1.00),
    },

    -- 13. Кофейная (Мягкие оттенки темного шоколада и латте)
    {
        name       = u8"Кофейная",
        windowBg   = imgui.ImVec4(0.08, 0.06, 0.05, 0.97),
        titleBg    = imgui.ImVec4(0.30, 0.20, 0.15, 1.00),
        panelBg    = imgui.ImVec4(0.12, 0.10, 0.09, 1.00),
        button     = imgui.ImVec4(0.30, 0.20, 0.15, 1.00),
        buttonHov  = imgui.ImVec4(0.40, 0.28, 0.22, 1.00),
        buttonAct  = imgui.ImVec4(0.20, 0.12, 0.08, 1.00),
        header     = imgui.ImVec4(0.30, 0.20, 0.15, 1.00),
        headerHov  = imgui.ImVec4(0.40, 0.28, 0.22, 1.00),
        headerAct  = imgui.ImVec4(0.20, 0.12, 0.08, 1.00),
        frameBg    = imgui.ImVec4(0.16, 0.13, 0.11, 1.00),
        border     = imgui.ImVec4(0.45, 0.35, 0.25, 0.45),
        accent     = imgui.ImVec4(0.70, 0.50, 0.35, 1.00),
        text       = imgui.ImVec4(0.95, 0.92, 0.88, 1.00),
        textDim    = imgui.ImVec4(0.65, 0.60, 0.55, 1.00),
    },

    -- 14. Сапфировая (Глубокий синий, более насыщенный и контрастный чем стандартная)
    {
        name       = u8"Сапфировая",
        windowBg   = imgui.ImVec4(0.02, 0.03, 0.06, 0.97),
        titleBg    = imgui.ImVec4(0.10, 0.20, 0.50, 1.00),
        panelBg    = imgui.ImVec4(0.05, 0.07, 0.12, 1.00),
        button     = imgui.ImVec4(0.10, 0.20, 0.50, 1.00),
        buttonHov  = imgui.ImVec4(0.15, 0.30, 0.70, 1.00),
        buttonAct  = imgui.ImVec4(0.05, 0.10, 0.35, 1.00),
        header     = imgui.ImVec4(0.10, 0.20, 0.50, 1.00),
        headerHov  = imgui.ImVec4(0.15, 0.30, 0.70, 1.00),
        headerAct  = imgui.ImVec4(0.05, 0.10, 0.35, 1.00),
        frameBg    = imgui.ImVec4(0.07, 0.10, 0.18, 1.00),
        border     = imgui.ImVec4(0.25, 0.40, 0.80, 0.45),
        accent     = imgui.ImVec4(0.35, 0.55, 0.95, 1.00),
        text       = imgui.ImVec4(0.90, 0.95, 1.00, 1.00),
        textDim    = imgui.ImVec4(0.55, 0.65, 0.85, 1.00),
    },

    -- 15. Ледяная (Угольно-серый фон со строгими холодно-голубыми элементами)
    {
        name       = u8"Ледяная",
        windowBg   = imgui.ImVec4(0.05, 0.06, 0.07, 0.97),
        titleBg    = imgui.ImVec4(0.15, 0.20, 0.25, 1.00),
        panelBg    = imgui.ImVec4(0.08, 0.09, 0.10, 1.00),
        button     = imgui.ImVec4(0.15, 0.20, 0.25, 1.00),
        buttonHov  = imgui.ImVec4(0.20, 0.28, 0.35, 1.00),
        buttonAct  = imgui.ImVec4(0.10, 0.14, 0.18, 1.00),
        header     = imgui.ImVec4(0.15, 0.20, 0.25, 1.00),
        headerHov  = imgui.ImVec4(0.20, 0.28, 0.35, 1.00),
        headerAct  = imgui.ImVec4(0.10, 0.14, 0.18, 1.00),
        frameBg    = imgui.ImVec4(0.11, 0.13, 0.15, 1.00),
        border     = imgui.ImVec4(0.30, 0.40, 0.50, 0.45),
        accent     = imgui.ImVec4(0.40, 0.60, 0.80, 1.00),
        text       = imgui.ImVec4(0.92, 0.96, 1.00, 1.00),
        textDim    = imgui.ImVec4(0.60, 0.65, 0.70, 1.00),
    },

    -- 16. Сакура (Нежно-розовый цветущий сакуровый оттенок на темно-сливовом фоне)
    {
        name       = u8"Сакура",
        windowBg   = imgui.ImVec4(0.08, 0.05, 0.07, 0.97),
        titleBg    = imgui.ImVec4(0.48, 0.22, 0.34, 1.00),
        panelBg    = imgui.ImVec4(0.13, 0.08, 0.11, 1.00),
        button     = imgui.ImVec4(0.48, 0.22, 0.34, 1.00),
        buttonHov  = imgui.ImVec4(0.60, 0.28, 0.43, 1.00),
        buttonAct  = imgui.ImVec4(0.36, 0.15, 0.25, 1.00),
        header     = imgui.ImVec4(0.48, 0.22, 0.34, 1.00),
        headerHov  = imgui.ImVec4(0.60, 0.28, 0.43, 1.00),
        headerAct  = imgui.ImVec4(0.36, 0.15, 0.25, 1.00),
        frameBg    = imgui.ImVec4(0.17, 0.10, 0.14, 1.00),
        border     = imgui.ImVec4(0.75, 0.38, 0.55, 0.45),
        accent     = imgui.ImVec4(1.00, 0.55, 0.72, 1.00),
        text       = imgui.ImVec4(1.00, 0.94, 0.96, 1.00),
        textDim    = imgui.ImVec4(0.78, 0.60, 0.68, 1.00),
    },

    -- 17. Коралловая (Теплый закатный коралл и лососевый неон)
    {
        name       = u8"Коралловая",
        windowBg   = imgui.ImVec4(0.08, 0.05, 0.05, 0.97),
        titleBg    = imgui.ImVec4(0.55, 0.22, 0.18, 1.00),
        panelBg    = imgui.ImVec4(0.13, 0.08, 0.08, 1.00),
        button     = imgui.ImVec4(0.55, 0.22, 0.18, 1.00),
        buttonHov  = imgui.ImVec4(0.68, 0.28, 0.24, 1.00),
        buttonAct  = imgui.ImVec4(0.42, 0.16, 0.13, 1.00),
        header     = imgui.ImVec4(0.55, 0.22, 0.18, 1.00),
        headerHov  = imgui.ImVec4(0.68, 0.28, 0.24, 1.00),
        headerAct  = imgui.ImVec4(0.42, 0.16, 0.13, 1.00),
        frameBg    = imgui.ImVec4(0.18, 0.11, 0.10, 1.00),
        border     = imgui.ImVec4(0.80, 0.35, 0.30, 0.45),
        accent     = imgui.ImVec4(1.00, 0.45, 0.38, 1.00),
        text       = imgui.ImVec4(1.00, 0.95, 0.93, 1.00),
        textDim    = imgui.ImVec4(0.78, 0.60, 0.56, 1.00),
    },

    -- 18. Вулканическая (Раскаленная магма и обсидиан)
    {
        name       = u8"Вулканическая",
        windowBg   = imgui.ImVec4(0.06, 0.04, 0.03, 0.98),
        titleBg    = imgui.ImVec4(0.58, 0.18, 0.05, 1.00),
        panelBg    = imgui.ImVec4(0.11, 0.07, 0.05, 1.00),
        button     = imgui.ImVec4(0.58, 0.18, 0.05, 1.00),
        buttonHov  = imgui.ImVec4(0.72, 0.24, 0.08, 1.00),
        buttonAct  = imgui.ImVec4(0.44, 0.12, 0.03, 1.00),
        header     = imgui.ImVec4(0.58, 0.18, 0.05, 1.00),
        headerHov  = imgui.ImVec4(0.72, 0.24, 0.08, 1.00),
        headerAct  = imgui.ImVec4(0.44, 0.12, 0.03, 1.00),
        frameBg    = imgui.ImVec4(0.16, 0.09, 0.06, 1.00),
        border     = imgui.ImVec4(0.82, 0.28, 0.08, 0.45),
        accent     = imgui.ImVec4(1.00, 0.36, 0.10, 1.00),
        text       = imgui.ImVec4(1.00, 0.94, 0.90, 1.00),
        textDim    = imgui.ImVec4(0.75, 0.56, 0.48, 1.00),
    },

    -- 19. Солнечная (Ярко-желтый кибер-акцент на графитовом фоне)
    {
        name       = u8"Солнечная",
        windowBg   = imgui.ImVec4(0.06, 0.06, 0.04, 0.98),
        titleBg    = imgui.ImVec4(0.52, 0.44, 0.06, 1.00),
        panelBg    = imgui.ImVec4(0.10, 0.10, 0.07, 1.00),
        button     = imgui.ImVec4(0.52, 0.44, 0.06, 1.00),
        buttonHov  = imgui.ImVec4(0.66, 0.56, 0.10, 1.00),
        buttonAct  = imgui.ImVec4(0.38, 0.32, 0.04, 1.00),
        header     = imgui.ImVec4(0.52, 0.44, 0.06, 1.00),
        headerHov  = imgui.ImVec4(0.66, 0.56, 0.10, 1.00),
        headerAct  = imgui.ImVec4(0.38, 0.32, 0.04, 1.00),
        frameBg    = imgui.ImVec4(0.15, 0.14, 0.09, 1.00),
        border     = imgui.ImVec4(0.78, 0.68, 0.12, 0.45),
        accent     = imgui.ImVec4(1.00, 0.86, 0.15, 1.00),
        text       = imgui.ImVec4(1.00, 0.98, 0.90, 1.00),
        textDim    = imgui.ImVec4(0.74, 0.70, 0.52, 1.00),
    },

    -- 20. Мятная (Свежий пастельно-аквамариновый ментол)
    {
        name       = u8"Мятная",
        windowBg   = imgui.ImVec4(0.04, 0.08, 0.07, 0.97),
        titleBg    = imgui.ImVec4(0.14, 0.46, 0.36, 1.00),
        panelBg    = imgui.ImVec4(0.07, 0.13, 0.11, 1.00),
        button     = imgui.ImVec4(0.14, 0.46, 0.36, 1.00),
        buttonHov  = imgui.ImVec4(0.18, 0.58, 0.46, 1.00),
        buttonAct  = imgui.ImVec4(0.10, 0.34, 0.26, 1.00),
        header     = imgui.ImVec4(0.14, 0.46, 0.36, 1.00),
        headerHov  = imgui.ImVec4(0.18, 0.58, 0.46, 1.00),
        headerAct  = imgui.ImVec4(0.10, 0.34, 0.26, 1.00),
        frameBg    = imgui.ImVec4(0.10, 0.17, 0.15, 1.00),
        border     = imgui.ImVec4(0.24, 0.68, 0.54, 0.45),
        accent     = imgui.ImVec4(0.32, 0.95, 0.74, 1.00),
        text       = imgui.ImVec4(0.92, 1.00, 0.97, 1.00),
        textDim    = imgui.ImVec4(0.56, 0.76, 0.68, 1.00),
    },

    -- 21. Оливковая (Тактический милитари хаки)
    {
        name       = u8"Оливковая",
        windowBg   = imgui.ImVec4(0.06, 0.07, 0.04, 0.97),
        titleBg    = imgui.ImVec4(0.28, 0.34, 0.16, 1.00),
        panelBg    = imgui.ImVec4(0.10, 0.11, 0.07, 1.00),
        button     = imgui.ImVec4(0.28, 0.34, 0.16, 1.00),
        buttonHov  = imgui.ImVec4(0.36, 0.44, 0.20, 1.00),
        buttonAct  = imgui.ImVec4(0.20, 0.25, 0.11, 1.00),
        header     = imgui.ImVec4(0.28, 0.34, 0.16, 1.00),
        headerHov  = imgui.ImVec4(0.36, 0.44, 0.20, 1.00),
        headerAct  = imgui.ImVec4(0.20, 0.25, 0.11, 1.00),
        frameBg    = imgui.ImVec4(0.14, 0.16, 0.10, 1.00),
        border     = imgui.ImVec4(0.45, 0.54, 0.26, 0.45),
        accent     = imgui.ImVec4(0.68, 0.78, 0.38, 1.00),
        text       = imgui.ImVec4(0.94, 0.96, 0.88, 1.00),
        textDim    = imgui.ImVec4(0.64, 0.68, 0.54, 1.00),
    },

    -- 22. Лавандовая (Мягкий пастельный сиренево-голубой)
    {
        name       = u8"Лавандовая",
        windowBg   = imgui.ImVec4(0.06, 0.06, 0.10, 0.97),
        titleBg    = imgui.ImVec4(0.32, 0.30, 0.56, 1.00),
        panelBg    = imgui.ImVec4(0.10, 0.10, 0.16, 1.00),
        button     = imgui.ImVec4(0.32, 0.30, 0.56, 1.00),
        buttonHov  = imgui.ImVec4(0.42, 0.40, 0.70, 1.00),
        buttonAct  = imgui.ImVec4(0.24, 0.22, 0.44, 1.00),
        header     = imgui.ImVec4(0.32, 0.30, 0.56, 1.00),
        headerHov  = imgui.ImVec4(0.42, 0.40, 0.70, 1.00),
        headerAct  = imgui.ImVec4(0.24, 0.22, 0.44, 1.00),
        frameBg    = imgui.ImVec4(0.14, 0.14, 0.22, 1.00),
        border     = imgui.ImVec4(0.50, 0.48, 0.82, 0.45),
        accent     = imgui.ImVec4(0.68, 0.65, 1.00, 1.00),
        text       = imgui.ImVec4(0.95, 0.95, 1.00, 1.00),
        textDim    = imgui.ImVec4(0.65, 0.64, 0.82, 1.00),
    },

    -- 23. Ультрамарин (Электрический кобальт и глубокий космос)
    {
        name       = u8"Ультрамарин",
        windowBg   = imgui.ImVec4(0.03, 0.04, 0.10, 0.98),
        titleBg    = imgui.ImVec4(0.14, 0.22, 0.68, 1.00),
        panelBg    = imgui.ImVec4(0.06, 0.08, 0.17, 1.00),
        button     = imgui.ImVec4(0.14, 0.22, 0.68, 1.00),
        buttonHov  = imgui.ImVec4(0.20, 0.30, 0.84, 1.00),
        buttonAct  = imgui.ImVec4(0.10, 0.16, 0.52, 1.00),
        header     = imgui.ImVec4(0.14, 0.22, 0.68, 1.00),
        headerHov  = imgui.ImVec4(0.20, 0.30, 0.84, 1.00),
        headerAct  = imgui.ImVec4(0.10, 0.16, 0.52, 1.00),
        frameBg    = imgui.ImVec4(0.09, 0.12, 0.24, 1.00),
        border     = imgui.ImVec4(0.25, 0.38, 0.95, 0.45),
        accent     = imgui.ImVec4(0.32, 0.52, 1.00, 1.00),
        text       = imgui.ImVec4(0.92, 0.95, 1.00, 1.00),
        textDim    = imgui.ImVec4(0.56, 0.64, 0.88, 1.00),
    },

    -- 24. Небесная (Кристально-голубой лазурный неон)
    {
        name       = u8"Небесная",
        windowBg   = imgui.ImVec4(0.04, 0.07, 0.10, 0.97),
        titleBg    = imgui.ImVec4(0.12, 0.44, 0.64, 1.00),
        panelBg    = imgui.ImVec4(0.07, 0.12, 0.17, 1.00),
        button     = imgui.ImVec4(0.12, 0.44, 0.64, 1.00),
        buttonHov  = imgui.ImVec4(0.18, 0.56, 0.78, 1.00),
        buttonAct  = imgui.ImVec4(0.08, 0.32, 0.48, 1.00),
        header     = imgui.ImVec4(0.12, 0.44, 0.64, 1.00),
        headerHov  = imgui.ImVec4(0.18, 0.56, 0.78, 1.00),
        headerAct  = imgui.ImVec4(0.08, 0.32, 0.48, 1.00),
        frameBg    = imgui.ImVec4(0.10, 0.16, 0.22, 1.00),
        border     = imgui.ImVec4(0.24, 0.66, 0.90, 0.45),
        accent     = imgui.ImVec4(0.35, 0.80, 1.00, 1.00),
        text       = imgui.ImVec4(0.92, 0.98, 1.00, 1.00),
        textDim    = imgui.ImVec4(0.58, 0.74, 0.85, 1.00),
    },

    -- 25. Сливовая (Глубокий бархатный пурпур и орхидея)
    {
        name       = u8"Сливовая",
        windowBg   = imgui.ImVec4(0.08, 0.04, 0.08, 0.97),
        titleBg    = imgui.ImVec4(0.44, 0.14, 0.44, 1.00),
        panelBg    = imgui.ImVec4(0.13, 0.07, 0.13, 1.00),
        button     = imgui.ImVec4(0.44, 0.14, 0.44, 1.00),
        buttonHov  = imgui.ImVec4(0.56, 0.20, 0.56, 1.00),
        buttonAct  = imgui.ImVec4(0.32, 0.10, 0.32, 1.00),
        header     = imgui.ImVec4(0.44, 0.14, 0.44, 1.00),
        headerHov  = imgui.ImVec4(0.56, 0.20, 0.56, 1.00),
        headerAct  = imgui.ImVec4(0.32, 0.10, 0.32, 1.00),
        frameBg    = imgui.ImVec4(0.17, 0.09, 0.17, 1.00),
        border     = imgui.ImVec4(0.68, 0.26, 0.68, 0.45),
        accent     = imgui.ImVec4(0.88, 0.38, 0.88, 1.00),
        text       = imgui.ImVec4(0.98, 0.92, 0.98, 1.00),
        textDim    = imgui.ImVec4(0.74, 0.56, 0.74, 1.00),
    },

    -- 26. Медная (Теплая состаренная бронза и терракота)
    {
        name       = u8"Медная",
        windowBg   = imgui.ImVec4(0.08, 0.05, 0.04, 0.97),
        titleBg    = imgui.ImVec4(0.48, 0.26, 0.16, 1.00),
        panelBg    = imgui.ImVec4(0.13, 0.09, 0.07, 1.00),
        button     = imgui.ImVec4(0.48, 0.26, 0.16, 1.00),
        buttonHov  = imgui.ImVec4(0.60, 0.34, 0.22, 1.00),
        buttonAct  = imgui.ImVec4(0.36, 0.19, 0.11, 1.00),
        header     = imgui.ImVec4(0.48, 0.26, 0.16, 1.00),
        headerHov  = imgui.ImVec4(0.60, 0.34, 0.22, 1.00),
        headerAct  = imgui.ImVec4(0.36, 0.19, 0.11, 1.00),
        frameBg    = imgui.ImVec4(0.17, 0.12, 0.09, 1.00),
        border     = imgui.ImVec4(0.72, 0.42, 0.26, 0.45),
        accent     = imgui.ImVec4(0.90, 0.56, 0.36, 1.00),
        text       = imgui.ImVec4(0.98, 0.93, 0.90, 1.00),
        textDim    = imgui.ImVec4(0.74, 0.60, 0.52, 1.00),
    },

    -- 27. Песочная (Пустынный дюнный беж и теплое шампанское)
    {
        name       = u8"Песочная",
        windowBg   = imgui.ImVec4(0.08, 0.07, 0.05, 0.97),
        titleBg    = imgui.ImVec4(0.42, 0.36, 0.24, 1.00),
        panelBg    = imgui.ImVec4(0.13, 0.11, 0.09, 1.00),
        button     = imgui.ImVec4(0.42, 0.36, 0.24, 1.00),
        buttonHov  = imgui.ImVec4(0.54, 0.46, 0.32, 1.00),
        buttonAct  = imgui.ImVec4(0.32, 0.27, 0.18, 1.00),
        header     = imgui.ImVec4(0.42, 0.36, 0.24, 1.00),
        headerHov  = imgui.ImVec4(0.54, 0.46, 0.32, 1.00),
        headerAct  = imgui.ImVec4(0.32, 0.27, 0.18, 1.00),
        frameBg    = imgui.ImVec4(0.17, 0.15, 0.12, 1.00),
        border     = imgui.ImVec4(0.64, 0.56, 0.40, 0.45),
        accent     = imgui.ImVec4(0.92, 0.82, 0.58, 1.00),
        text       = imgui.ImVec4(0.98, 0.96, 0.90, 1.00),
        textDim    = imgui.ImVec4(0.72, 0.68, 0.58, 1.00),
    },

    -- 28. Малиновая (Яркая сочная фуксия-малина)
    {
        name       = u8"Малиновая",
        windowBg   = imgui.ImVec4(0.08, 0.03, 0.05, 0.97),
        titleBg    = imgui.ImVec4(0.56, 0.10, 0.28, 1.00),
        panelBg    = imgui.ImVec4(0.13, 0.06, 0.09, 1.00),
        button     = imgui.ImVec4(0.56, 0.10, 0.28, 1.00),
        buttonHov  = imgui.ImVec4(0.70, 0.14, 0.36, 1.00),
        buttonAct  = imgui.ImVec4(0.42, 0.07, 0.20, 1.00),
        header     = imgui.ImVec4(0.56, 0.10, 0.28, 1.00),
        headerHov  = imgui.ImVec4(0.70, 0.14, 0.36, 1.00),
        headerAct  = imgui.ImVec4(0.42, 0.07, 0.20, 1.00),
        frameBg    = imgui.ImVec4(0.18, 0.08, 0.12, 1.00),
        border     = imgui.ImVec4(0.82, 0.18, 0.44, 0.45),
        accent     = imgui.ImVec4(1.00, 0.20, 0.50, 1.00),
        text       = imgui.ImVec4(1.00, 0.92, 0.95, 1.00),
        textDim    = imgui.ImVec4(0.78, 0.52, 0.62, 1.00),
    },

    -- 29. Нефритовая (Глубокий восточный нефрит и морская хвоя)
    {
        name       = u8"Нефритовая",
        windowBg   = imgui.ImVec4(0.03, 0.07, 0.06, 0.97),
        titleBg    = imgui.ImVec4(0.08, 0.38, 0.30, 1.00),
        panelBg    = imgui.ImVec4(0.06, 0.11, 0.10, 1.00),
        button     = imgui.ImVec4(0.08, 0.38, 0.30, 1.00),
        buttonHov  = imgui.ImVec4(0.12, 0.48, 0.38, 1.00),
        buttonAct  = imgui.ImVec4(0.05, 0.28, 0.22, 1.00),
        header     = imgui.ImVec4(0.08, 0.38, 0.30, 1.00),
        headerHov  = imgui.ImVec4(0.12, 0.48, 0.38, 1.00),
        headerAct  = imgui.ImVec4(0.05, 0.28, 0.22, 1.00),
        frameBg    = imgui.ImVec4(0.08, 0.15, 0.13, 1.00),
        border     = imgui.ImVec4(0.16, 0.58, 0.46, 0.45),
        accent     = imgui.ImVec4(0.22, 0.78, 0.62, 1.00),
        text       = imgui.ImVec4(0.90, 0.98, 0.95, 1.00),
        textDim    = imgui.ImVec4(0.52, 0.72, 0.66, 1.00),
    },

    -- 30. Арктическая (Морозный бело-голубой неон на темном сланце)
    {
        name       = u8"Арктическая",
        windowBg   = imgui.ImVec4(0.05, 0.07, 0.09, 0.98),
        titleBg    = imgui.ImVec4(0.22, 0.34, 0.44, 1.00),
        panelBg    = imgui.ImVec4(0.09, 0.11, 0.14, 1.00),
        button     = imgui.ImVec4(0.22, 0.34, 0.44, 1.00),
        buttonHov  = imgui.ImVec4(0.30, 0.44, 0.56, 1.00),
        buttonAct  = imgui.ImVec4(0.16, 0.25, 0.34, 1.00),
        header     = imgui.ImVec4(0.22, 0.34, 0.44, 1.00),
        headerHov  = imgui.ImVec4(0.30, 0.44, 0.56, 1.00),
        headerAct  = imgui.ImVec4(0.16, 0.25, 0.34, 1.00),
        frameBg    = imgui.ImVec4(0.12, 0.15, 0.19, 1.00),
        border     = imgui.ImVec4(0.45, 0.65, 0.80, 0.45),
        accent     = imgui.ImVec4(0.72, 0.92, 1.00, 1.00),
        text       = imgui.ImVec4(0.96, 0.99, 1.00, 1.00),
        textDim    = imgui.ImVec4(0.66, 0.76, 0.84, 1.00),
    },

    -- 31. Гранатовая (Рубиново-алый неон на угольно-черном фоне)
    {
        name       = u8"Гранатовая",
        windowBg   = imgui.ImVec4(0.05, 0.02, 0.03, 0.98),
        titleBg    = imgui.ImVec4(0.46, 0.06, 0.14, 1.00),
        panelBg    = imgui.ImVec4(0.09, 0.04, 0.06, 1.00),
        button     = imgui.ImVec4(0.46, 0.06, 0.14, 1.00),
        buttonHov  = imgui.ImVec4(0.60, 0.10, 0.20, 1.00),
        buttonAct  = imgui.ImVec4(0.34, 0.04, 0.10, 1.00),
        header     = imgui.ImVec4(0.46, 0.06, 0.14, 1.00),
        headerHov  = imgui.ImVec4(0.60, 0.10, 0.20, 1.00),
        headerAct  = imgui.ImVec4(0.34, 0.04, 0.10, 1.00),
        frameBg    = imgui.ImVec4(0.14, 0.06, 0.08, 1.00),
        border     = imgui.ImVec4(0.75, 0.12, 0.24, 0.45),
        accent     = imgui.ImVec4(1.00, 0.16, 0.30, 1.00),
        text       = imgui.ImVec4(1.00, 0.92, 0.94, 1.00),
        textDim    = imgui.ImVec4(0.76, 0.50, 0.56, 1.00),
    }
}
currentThemeIdx = 1
local function getTheme() return themes[currentThemeIdx] end

THEME_COLOR_COUNT = 16
THEME_ROUNDING_COUNT = 4

local function pushThemeColors()
    local t = getTheme()
    imgui.PushStyleColor(imgui.Col.WindowBg,       t.windowBg)
    imgui.PushStyleColor(imgui.Col.ChildWindowBg,  t.panelBg)
    imgui.PushStyleColor(imgui.Col.PopupBg,        imgui.ImVec4(t.windowBg.x, t.windowBg.y, t.windowBg.z, 0.98))
    imgui.PushStyleColor(imgui.Col.ModalWindowDarkening, imgui.ImVec4(0.02, 0.04, 0.07, 0.74))
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
    imgui.PushStyleColor(imgui.Col.Separator,      t.border)
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
        acs_rem = "false",
        acs_rem_me = "false",
        remove_armour = "false",
        delete_textdraw = "false",
        notifications_enabled = "true",
        ad_schedule_enabled = "false",
        ad_schedule_from_hour = "21",
        ad_schedule_from_min = "5",
        ad_schedule_to_hour = "21",
        ad_schedule_to_min = "9",
        github_token = "",
        actors_google_url = "https://script.google.com/macros/s/AKfycbwAb8CpcQgee8dVZobbsZNTA1zDWQsF98B2glHXBurCPjfVwT7vsI_DOavIdQ0XEq1M-Q/exec",
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
        fw:write("acs_rem=false\n")
        fw:write("acs_rem_me=false\n")
        fw:write("remove_armour=false\n")
        fw:write("notifications_enabled=true\n")
        fw:write("delete_textdraw=false\n")
        fw:close()
    end
end

local mainIni = inicfg.load(defaultSettings, CONFIG_PATH) or defaultSettings

github_admin_token_buf = imgui.ImBuffer(u8(mainIni.settings.github_token or ""), 128)
github_token_show      = imgui.ImBool(false)
actors_google_url_buf  = imgui.ImBuffer(u8(mainIni.settings.actors_google_url or "https://script.google.com/macros/s/AKfycbwAb8CpcQgee8dVZobbsZNTA1zDWQsF98B2glHXBurCPjfVwT7vsI_DOavIdQ0XEq1M-Q/exec"), 256)
actors_manual_nick_buf = imgui.ImBuffer("", 32)

ad_interval_minutes = imgui.ImInt(30)
ad_city_ls  = imgui.ImBool(true)
ad_city_sf  = imgui.ImBool(false)
ad_city_lv  = imgui.ImBool(false)
ad_city_all = imgui.ImBool(false)

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

acs_rem = imgui.ImBool(boolFromSetting(mainIni.settings.acs_rem))
acs_rem_me = imgui.ImBool(boolFromSetting(mainIni.settings.acs_rem_me))
remove_armour = imgui.ImBool(boolFromSetting(mainIni.settings.remove_armour))
delete_textdraw = imgui.ImBool(boolFromSetting(mainIni.settings.delete_textdraw))
delete_textdraw_was_active = false
notifications_enabled = imgui.ImBool(mainIni.settings.notifications_enabled == nil or boolFromSetting(mainIni.settings.notifications_enabled))

local function deleteAllAcs(id)
    local bs = raknetNewBitStream()
    for i = 0, 7 do
        raknetBitStreamWriteInt16(bs, id)
        raknetBitStreamWriteInt32(bs, i)
        raknetBitStreamWriteBool(bs, false)
        raknetEmulRpcReceiveBitStream(113, bs)
        raknetResetBitStream(bs)

        raknetBitStreamWriteInt8(bs, 155)
        raknetBitStreamWriteInt16(bs, id)
        raknetBitStreamWriteInt32(bs, i)
        raknetBitStreamWriteBool(bs, false)
        raknetEmulPacketReceiveBitStream(220, bs)
        raknetResetBitStream(bs)
    end
    raknetDeleteBitStream(bs)
end

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
            acs_rem = tostring(acs_rem.v),
            acs_rem_me = tostring(acs_rem_me.v),
            remove_armour = tostring(remove_armour.v),
            delete_textdraw = tostring(delete_textdraw.v),
            notifications_enabled = tostring(notifications_enabled.v),
            ad_interval_minutes = tostring(ad_interval_minutes.v),
            ad_city_ls = tostring(ad_city_ls.v),
            ad_city_sf = tostring(ad_city_sf.v),
            ad_city_lv = tostring(ad_city_lv.v),
            ad_city_all = tostring(ad_city_all.v),
            ad_schedule_enabled = tostring(ad_schedule_enabled.v),
            ad_schedule_from_hour = tostring(ad_schedule_from_hour.v),
            ad_schedule_from_min = tostring(ad_schedule_from_min.v),
            ad_schedule_to_hour = tostring(ad_schedule_to_hour.v),
            ad_schedule_to_min = tostring(ad_schedule_to_min.v),
            ad_limit_enabled = tostring(ad_limit_enabled and ad_limit_enabled.v or false),
            ad_limit_max = tostring(ad_limit_max and ad_limit_max.v or 10),
            ad_shuffle_enabled = tostring(ad_shuffle_enabled and ad_shuffle_enabled.v or false),
            github_token = (github_admin_token_buf and u8:decode(github_admin_token_buf.v) or (mainIni.settings and mainIni.settings.github_token) or ""),
            actors_google_url = (actors_google_url_buf and u8:decode(actors_google_url_buf.v) or (mainIni.settings and mainIni.settings.actors_google_url) or ""),
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
upcoming_event_timestamp = nil

-- Toast-уведомления (статусы: успех по кураторам/актёрам/рекламе и т.п.)
toast_text = ""
toast_timer = 0
toast_font = nil
event_notify_30_sent = false
event_notify_10_sent = false
event_notify_last_check = 0

function showToast(text)
    toast_text = text
    toast_timer = 150
end

-- Крупная вертикальная карточка-напоминание о скором начале ивента (отдельно от обычных toast'ов)
event_card_timer      = 0
event_card_message    = "" -- нижняя строка: "Осталось 30 минут" / "Осталось 10 минут"
event_card_font_title = nil
event_card_font_name  = nil
event_card_font_time  = nil
event_card_logo_texture = nil

local function truncateToWidth(font, text, maxWidth)
    if renderGetFontDrawTextLength(font, text) <= maxWidth then
        return text
    end
    local ellipsis = "..."
    while #text > 0 and renderGetFontDrawTextLength(font, text .. ellipsis) > maxWidth do
        text = text:sub(1, -2)
    end
    return text .. ellipsis
end

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
--  РЕКЛАМНЫЙ ОТДЕЛ: Объявления
-- ============================================================
AD_TEXT_MAX = 119 -- лимит символов (реальных, проверенных на сервере)
AD_TEXT_BUFFER_SIZE = AD_TEXT_MAX * 3 -- запас байт для буфера ввода: кириллица в UTF-8 занимает 2 байта на символ

local AD_CITIES = {
    { code = "ls", name = u8"Los Santos" },
    { code = "sf", name = u8"San Fierro" },
    { code = "lv", name = u8"Las Venturas" },
}
ad_city_ls  = imgui.ImBool(boolFromSetting(mainIni.settings.ad_city_ls or "true"))
ad_city_sf  = imgui.ImBool(boolFromSetting(mainIni.settings.ad_city_sf or "false"))
ad_city_lv  = imgui.ImBool(boolFromSetting(mainIni.settings.ad_city_lv or "false"))
ad_city_all = imgui.ImBool(boolFromSetting(mainIni.settings.ad_city_all or "false"))

ad_pending_cities   = {} -- очередь кодов городов на текущую отправку
ad_pending_city_pos = 0

local function getSelectedCityCodes()
    if ad_city_all.v then
        local codes = {}
        for _, c in ipairs(AD_CITIES) do codes[#codes + 1] = c.code end
        return codes
    end
    local codes = {}
    if ad_city_ls.v then codes[#codes + 1] = "ls" end
    if ad_city_sf.v then codes[#codes + 1] = "sf" end
    if ad_city_lv.v then codes[#codes + 1] = "lv" end
    return codes
end
-- ---------- Автоотправка по очереди ----------
ad_auto_send = imgui.ImBool(false)
ad_interval_minutes = imgui.ImInt(tonumber(mainIni.settings.ad_interval_minutes) or 30)
ad_limit_enabled   = imgui.ImBool(boolFromSetting(mainIni.settings.ad_limit_enabled or "false"))
ad_limit_max       = imgui.ImInt(tonumber(mainIni.settings.ad_limit_max) or 10)
ad_limit_sent      = 0
ad_shuffle_enabled = imgui.ImBool(boolFromSetting(mainIni.settings.ad_shuffle_enabled or "false"))
ad_session_sent_count = 0
ad_session_spent   = 0

function safeU8(str)
    if not str or str == "" then return "" end
    local ok, res = pcall(u8, str)
    if ok and res then return res end
    return tostring(str)
end

function safeU8Decode(str)
    if not str or str == "" then return "" end
    local ok, res = pcall(u8.decode, u8, str)
    if ok and res then return res end
    return tostring(str)
end

function getNextCityName()
    local ok, cities = pcall(getSelectedCityCodes)
    if not ok or not cities or #cities == 0 then return u8"Город не выбран" end
    local cityNames = { ls = "Los Santos", sf = "San Fierro", lv = "Las Venturas" }
    local nextCode = cities[1]
    if #cities > 1 then
        local nextIdx = ((ad_city_rotation_idx or 0) % #cities) + 1
        nextCode = cities[nextIdx] or cities[1]
    end
    if not nextCode then return u8"Город не выбран" end
    local name = cityNames[nextCode] or tostring(nextCode):upper()
    return u8(name)
end

function appendToAdBuffer(buffer, insertText)
    local curRaw = safeU8Decode(buffer.v)
    if curRaw ~= "" and not curRaw:match("%s$") and not insertText:match("^[%.%!%?]") then
        curRaw = curRaw .. " "
    end
    local combined = curRaw .. insertText
    if #combined > AD_TEXT_MAX then
        combined = combined:sub(1, AD_TEXT_MAX)
        showToast("Достигнут лимит 119 символов")
    end
    buffer.v = safeU8(combined)
end

function drawAdQuickChips(buffer, tagId)
    imgui.PushStyleVar(imgui.StyleVar.FrameRounding, 4.0)
    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.14, 0.18, 0.26, 0.80))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.20, 0.26, 0.38, 0.95))
    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.75, 0.80, 0.90, 0.90))

    imgui.TextColored(imgui.ImVec4(0.55, 0.58, 0.65, 0.80), u8"Быстро:")
    imgui.SameLine()

    if imgui.Button(fa.ICON_MAP_MARKER .. u8" Навигатор##chip_nav_" .. tagId, imgui.ImVec2(0, 22)) then
        appendToAdBuffer(buffer, "Навигатор: ")
    end
    if imgui.IsItemHovered() then imgui.SetTooltip(u8"Вставить 'Навигатор: '") end

    imgui.SameLine()
    if imgui.Button(fa.ICON_COMMENTING .. u8" Звоните##chip_call_" .. tagId, imgui.ImVec2(0, 22)) then
        appendToAdBuffer(buffer, "Звоните.")
    end
    if imgui.IsItemHovered() then imgui.SetTooltip(u8"Вставить 'Звоните.'") end

    imgui.SameLine()
    if imgui.Button(u8"+ Точка [.]##chip_dot_" .. tagId, imgui.ImVec2(0, 22)) then
        local raw = safeU8Decode(buffer.v)
        if raw ~= "" and not raw:match("[%.%!%?]$") then
            buffer.v = safeU8(raw .. ".")
        end
    end
    if imgui.IsItemHovered() then imgui.SetTooltip(u8"Поставить точку в конце объявления (если нет)") end

    imgui.PopStyleColor(3)
    imgui.PopStyleVar()
end

-- ---------- Расписание автоотправки (автостарт и автостоп) ----------
ad_schedule_enabled   = imgui.ImBool(boolFromSetting(mainIni.settings.ad_schedule_enabled or "false"))
ad_schedule_from_hour = imgui.ImInt(tonumber(mainIni.settings.ad_schedule_from_hour) or 21)
ad_schedule_from_min  = imgui.ImInt(tonumber(mainIni.settings.ad_schedule_from_min) or 5)
ad_schedule_to_hour   = imgui.ImInt(tonumber(mainIni.settings.ad_schedule_to_hour) or 21)
ad_schedule_to_min    = imgui.ImInt(tonumber(mainIni.settings.ad_schedule_to_min) or 9)
local ad_schedule_was_in = nil

local SERVER_TZ_OFFSET_SEC = 3 * 3600 -- Время сервера Trinity GTA по МСК (UTC+3)
local server_time_offset = 0

local function getServerTime()
    return os.date("!*t", os.time() + SERVER_TZ_OFFSET_SEC + server_time_offset)
end

local function isServerTimeInSchedule()
    local s = getServerTime()
    local cur = s.hour * 60 + s.min
    local fromT = ad_schedule_from_hour.v * 60 + ad_schedule_from_min.v
    local toT = ad_schedule_to_hour.v * 60 + ad_schedule_to_min.v

    if fromT <= toT then
        return cur >= fromT and cur <= toT
    else
        -- Расписание переходит через полночь (например, с 22:00 до 06:00)
        return cur >= fromT or cur <= toT
    end
end

ad_text = imgui.ImBuffer("", AD_TEXT_BUFFER_SIZE)
ad_pending = false      -- ждём ли сейчас диалогов после отправки команды
ad_pending_text = ""    -- текст, который подставим во второй диалог (CP1251, без u8)
ad_news_confirm_until = 0 -- os.time(), до какого момента автожмём попап "без модерации" (появляется ПОСЛЕ ad_pending=false)

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
local ads_list = {} -- { {text=(CP1251), enabled=bool, sentCount=number}, ... }

local function saveAdsList()
    local cfg = { ads = { count = tostring(#ads_list) } }
    for i, ad in ipairs(ads_list) do
        cfg.ads["ad" .. i .. "_text"]      = ad.text
        cfg.ads["ad" .. i .. "_enabled"]   = tostring(ad.enabled)
        cfg.ads["ad" .. i .. "_sentcount"] = tostring(ad.sentCount or 0)
    end
    inicfg.save(cfg, ADS_LIST_PATH)
    adsIndexIni = cfg
end

do
    local adsCount = tonumber(adsIndexIni.ads.count) or 0
    for i = 1, adsCount do
        local text = adsIndexIni.ads["ad" .. i .. "_text"]
        local enabledRaw = adsIndexIni.ads["ad" .. i .. "_enabled"]
        local sentCountRaw = adsIndexIni.ads["ad" .. i .. "_sentcount"]
        if text then
            ads_list[#ads_list + 1] = { text = text, enabled = boolFromSetting(enabledRaw), sentCount = tonumber(sentCountRaw) or 0 }
        end
    end
end

-- ============================================================
--  ИСТОРИЯ ОТПРАВОК (журнал последних AD_HISTORY_LIMIT записей)
-- ============================================================
AD_HISTORY_LIMIT = 300
local AD_HISTORY_PATH = "moonloader\\config\\TRPcomm Manager Config\\ad-history.ini"

do
    local f = io.open(AD_HISTORY_PATH, "r")
    if f then
        f:close()
    else
        local fw = io.open(AD_HISTORY_PATH, "w")
        if fw then
            fw:write("[history]\ncount=0\n")
            fw:close()
        end
    end
end

local defaultHistoryIndex = { history = { count = "0" } }
local historyIndexIni = inicfg.load(defaultHistoryIndex, AD_HISTORY_PATH) or defaultHistoryIndex
ad_history_log = {} -- { {ts=number, text=(CP1251), source="manual"|"queue"|"campaign", eventLabel=(UTF8|nil)}, ... }, новые в конце

local function saveAdHistory()
    local cfg = { history = { count = tostring(#ad_history_log) } }
    for i, entry in ipairs(ad_history_log) do
        cfg.history["h" .. i .. "_ts"]     = tostring(entry.ts)
        cfg.history["h" .. i .. "_text"]   = entry.text
        cfg.history["h" .. i .. "_source"] = entry.source or "manual"
        cfg.history["h" .. i .. "_event"]  = entry.eventLabel or ""
    end
    inicfg.save(cfg, AD_HISTORY_PATH)
    historyIndexIni = cfg
end

local function logAdHistory(textRaw, source, eventLabel)
    ad_history_log[#ad_history_log + 1] = { ts = os.time(), text = textRaw, source = source or "manual", eventLabel = eventLabel }
    while #ad_history_log > AD_HISTORY_LIMIT do
        table.remove(ad_history_log, 1) -- убираем самую старую запись
    end
    saveAdHistory()
end

do
    local historyCount = tonumber(historyIndexIni.history.count) or 0
    for i = 1, historyCount do
        local ts     = tonumber(historyIndexIni.history["h" .. i .. "_ts"])
        local text   = historyIndexIni.history["h" .. i .. "_text"]
        local source = historyIndexIni.history["h" .. i .. "_source"]
        local ev     = historyIndexIni.history["h" .. i .. "_event"]
        if ts and text then
            ad_history_log[#ad_history_log + 1] = { ts = ts, text = text, source = source or "manual", eventLabel = (ev ~= "" and ev or nil) }
        end
    end
end

-- ---------- Форма добавления объявления ---------- ---------- ОБЪЯВЛЕНИЯ : ФОРМА ДОБАВЛЕНИЯ / ИЗМЕНЕНИЯ ----------
ad_add_form_open = false
ad_edit_idx = nil
ad_new_text = imgui.ImBuffer("", AD_TEXT_BUFFER_SIZE)
ad_modal_alpha = 0.0
ad_modal_just_opened = false

local function drawAdAddForm(t)
    local targetAlpha = ad_add_form_open and 1.0 or 0.0
    local dt = imgui.GetIO().DeltaTime
    if dt <= 0 or dt > 0.1 then dt = 0.016 end

    -- Плавная LERP-анимация затемнения фона (fade-in / fade-out ~180ms)
    if math.abs(ad_modal_alpha - targetAlpha) > 0.001 then
        ad_modal_alpha = ad_modal_alpha + (targetAlpha - ad_modal_alpha) * math.min(1.0, dt * 14.0)
        if math.abs(ad_modal_alpha - targetAlpha) < 0.008 then
            ad_modal_alpha = targetAlpha
        end
    end

    if ad_modal_alpha <= 0.005 and not ad_add_form_open then
        return
    end

    local sw, sh = getScreenResolution()

    -- 1. Полноэкранный плавный тёмный бэкдроп
    imgui.SetNextWindowPos(imgui.ImVec2(0, 0), imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(sw, sh), imgui.Cond.Always)
    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.02, 0.04, 0.07, ad_modal_alpha * 0.72))
    imgui.PushStyleVar(imgui.StyleVar.WindowRounding, 0.0)
    imgui.PushStyleVar(imgui.StyleVar.WindowPadding, imgui.ImVec2(0, 0))

    local bgFlags = imgui.WindowFlags.NoTitleBar
        + imgui.WindowFlags.NoResize
        + imgui.WindowFlags.NoMove
        + imgui.WindowFlags.NoScrollbar
        + imgui.WindowFlags.NoSavedSettings

    if not ad_add_form_open then
        bgFlags = bgFlags + imgui.WindowFlags.NoInputs
    end

    imgui.Begin("##ad_modal_backdrop", nil, bgFlags)
    -- Закрытие при клике по фону вне окна
    if ad_add_form_open and imgui.IsWindowHovered() and imgui.IsMouseClicked(0) then
        ad_add_form_open = false
        ad_edit_idx = nil
    end
    imgui.End()

    imgui.PopStyleVar(2)
    imgui.PopStyleColor()

    -- 2. Само модальное окно
    if ad_modal_alpha > 0.02 then
        local modalW, modalH = 470, 240
        local liftY = (1.0 - ad_modal_alpha) * 16.0
        imgui.SetNextWindowSize(imgui.ImVec2(modalW, modalH), imgui.Cond.Always)
        imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2 - liftY), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))

        pushThemeColors()
        pushThemeRounding()

        imgui.PushStyleVar(imgui.StyleVar.Alpha, math.min(1.0, ad_modal_alpha * 1.15))
        imgui.PushStyleVar(imgui.StyleVar.WindowRounding, 12.0)
        imgui.PushStyleVar(imgui.StyleVar.WindowPadding, imgui.ImVec2(18, 12))
        imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.10, 0.13, 0.19, 0.98))
        imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.55))
        imgui.PushStyleColor(imgui.Col.TitleBg, imgui.ImVec4(0.12, 0.16, 0.24, 1.0))
        imgui.PushStyleColor(imgui.Col.TitleBgActive, imgui.ImVec4(0.14, 0.19, 0.28, 1.0))

        if ad_modal_just_opened then
            imgui.SetNextWindowFocus()
        end

        local isEdit = ad_edit_idx ~= nil
        local titleIcon = isEdit and fa.ICON_PENCIL or fa.ICON_PLUS
        local titleText = isEdit and u8"  Изменить объявление" or u8"  Новое объявление"
        local winFlags = imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize
        if not ad_add_form_open then
            winFlags = winFlags + imgui.WindowFlags.NoInputs
        end

        -- Без крестика в заголовке (передаём nil вместо open)
        imgui.Begin(titleIcon .. titleText .. "##ad_modal_window", nil, winFlags)

        if ad_add_form_open and isKeyDown(0x1B) then -- ESC key
            ad_add_form_open = false
            ad_edit_idx = nil
        end

        -- Шапка формы: название и живой счётчик символов
        local curLen = #safeU8Decode(ad_new_text.v)
        local counterCol = curLen > 110 and imgui.ImVec4(0.95, 0.35, 0.35, 1.0)
                        or (curLen > 85 and imgui.ImVec4(0.95, 0.75, 0.20, 1.0) or t.textDim)

        imgui.TextColored(t.text, u8"Текст объявления:")
        imgui.SameLine(modalW - 170)
        imgui.TextColored(counterCol, string.format(u8"Символов: %d / %d", curLen, AD_TEXT_MAX))

        imgui.Spacing()

        -- Поле ввода
        imgui.PushItemWidth(-1)
        if ad_modal_just_opened then
            imgui.SetKeyboardFocusHere(0)
            ad_modal_just_opened = false
        end
        imgui.InputTextMultiline("##ad_new_text_input", ad_new_text, imgui.ImVec2(-1, 80))
        imgui.PopItemWidth()

        -- Перехват Ctrl + V
        if imgui.IsItemActive() then
            local ctrlVDown = isKeyDown(0x11) and isKeyDown(0x56)
            if ctrlVDown and not ad_new_text_ctrlv_was_down then
                local clip = getClipboardText()
                if clip and clip ~= "" then
                    local text = clip
                    if #text > AD_TEXT_MAX then text = text:sub(1, AD_TEXT_MAX) end
                    ad_new_text.v = u8(text)
                end
            end
            ad_new_text_ctrlv_was_down = ctrlVDown
        else
            ad_new_text_ctrlv_was_down = false
        end

        imgui.Spacing()
        drawAdQuickChips(ad_new_text, "modal")

        imgui.Spacing(); imgui.Separator(); imgui.Spacing()

        -- Кнопки: Сохранить и Отмена
        imgui.PushStyleColor(imgui.Col.Button, t.accent)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(t.buttonHov.x, t.buttonHov.y, t.buttonHov.z, 1.0))
        local confirmLabel = fa.ICON_CHECK .. (isEdit and u8"  Сохранить" or u8"  Создать") .. "##ad_add_confirm"
        if imgui.Button(confirmLabel, imgui.ImVec2(140, 30)) then
            local raw = safeU8Decode(ad_new_text.v)
            if raw ~= "" then
                if isEdit then
                    ads_list[ad_edit_idx].text = raw
                    ads_list[ad_edit_idx].sentCount = 0
                else
                    ads_list[#ads_list + 1] = { text = raw, enabled = true, sentCount = 0 }
                end
                saveAdsList()
                ad_new_text.v = ""
                ad_add_form_open = false
                ad_edit_idx = nil
            end
        end
        imgui.PopStyleColor(2)

        imgui.SameLine()

        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.18, 0.22, 0.30, 0.85))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.26, 0.32, 0.42, 1.0))
        if imgui.Button(fa.ICON_TIMES .. u8"  Закрыть##ad_add_cancel", imgui.ImVec2(120, 30)) then
            ad_add_form_open = false
            ad_edit_idx = nil
        end
        imgui.PopStyleColor(2)

        imgui.End()

        imgui.PopStyleColor(4)
        imgui.PopStyleVar(3)
        imgui.PopStyleVar(THEME_ROUNDING_COUNT)
        imgui.PopStyleColor(THEME_COLOR_COUNT)
    end
end

-- ---------- АВТООТПРАВКА ----------
ad_next_send_time = 0
ad_rotation_idx = 0

ad_pending_deadline    = 0     -- os.time(); если не сдвинется за 2 сек — сторож сбросит ожидание
ad_awaiting_next_city  = false -- ждём ли ещё попап "без модерации" перед следующим городом
ad_next_city_at        = 0     -- запасной срок, если попап так и не пришёл
ad_city_retry_count    = 0     -- сколько раз подряд повторили один и тот же город

local function sendToNextPendingCity()
    ad_pending_city_pos = ad_pending_city_pos + 1
    local cityCode = ad_pending_cities[ad_pending_city_pos]
    if not cityCode then
        ad_pending = false
        ad_pending_deadline = 0
        return
    end
    ad_city_retry_count = 0
    ad_pending = true
    ad_pending_deadline = os.time() + 4
    sampSendChat("/sms radio" .. cityCode)
end

local function retryCurrentCity()
    local cityCode = ad_pending_cities[ad_pending_city_pos]
    if not cityCode then
        ad_pending = false
        return
    end
    ad_city_retry_count = ad_city_retry_count + 1
    if ad_city_retry_count > 5 then
        sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Не удалось отправить в город после нескольких попыток, пропускаю его.', -1)
        sendToNextPendingCity()
        return
    end
    ad_pending = true
    ad_pending_deadline = os.time() + 2
    sampSendChat("/sms radio" .. cityCode)
end

local function advanceAfterNewsPopup()
    if not ad_awaiting_next_city then return end
    ad_awaiting_next_city = false
    ad_pending_deadline = 0
    lua_thread.create(function()
        wait(300)
        sendToNextPendingCity()
        if not ad_pending and ad_auto_send.v then
            ad_next_send_time = os.time() + (ad_interval_minutes.v * 60) + 2
        end
    end)
end

ad_city_rotation_idx = 0

local function sendAdNow(textRaw, source, eventLabel)
    local cities = getSelectedCityCodes()
    if #cities == 0 then
        sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Выбери хотя бы один город для отправки.', -1)
        return
    end
    local targetCities = cities
    if #cities > 1 then
        ad_city_rotation_idx = ((ad_city_rotation_idx or 0) % #cities) + 1
        targetCities = { cities[ad_city_rotation_idx] }
    end
    ad_pending_text = textRaw
    ad_pending_source = source or "manual"
    ad_pending_event_label = eventLabel
    ad_pending_cities = targetCities
    ad_pending_city_pos = 0
    sendToNextPendingCity()
end

local function incrementAdSentCount(textRaw)
    for _, ad in ipairs(ads_list) do
        if ad.text == textRaw then
            ad.sentCount = (ad.sentCount or 0) + 1
            saveAdsList()
            break
        end
    end
    ad_limit_sent = (ad_limit_sent or 0) + 1
    ad_session_sent_count = (ad_session_sent_count or 0) + 1
    local cost = math.max(20, #textRaw * 2)
    ad_session_spent = (ad_session_spent or 0) + cost

    if ad_limit_enabled.v and ad_limit_sent >= ad_limit_max.v then
        ad_auto_send.v = false
        saveSettings()
        showToast("Лимит отправок (" .. ad_limit_max.v .. ") достигнут. Автоотправка завершена!")
        sampAddChatMessage('{5B85C4}[TRPcomm] {FFFFFF}Лимит отправок ({5B85C4}' .. ad_limit_max.v .. '{FFFFFF}) достигнут. Циклическая отправка остановлена.', -1)
    end
end

local function triggerNextAdSend()
    if #ads_list == 0 then return end
    if ad_limit_enabled.v and ad_limit_sent >= ad_limit_max.v then
        ad_auto_send.v = false
        saveSettings()
        showToast("Лимит отправок исчерпан. Автоотправка остановлена.")
        return
    end

    ad_next_send_time = os.time() + (ad_interval_minutes.v * 60) + 2

    local enabledIndices = {}
    for i, ad in ipairs(ads_list) do
        if ad.enabled then enabledIndices[#enabledIndices + 1] = i end
    end
    if #enabledIndices == 0 then return end

    local targetIdx = enabledIndices[1]
    if ad_shuffle_enabled.v and #enabledIndices > 1 then
        local choices = {}
        for _, idx in ipairs(enabledIndices) do
            if idx ~= ad_rotation_idx or #enabledIndices == 1 then
                choices[#choices + 1] = idx
            end
        end
        if #choices == 0 then choices = enabledIndices end
        targetIdx = choices[math.random(1, #choices)]
    else
        for i = 1, #ads_list do
            local idx = ((ad_rotation_idx + i - 1) % #ads_list) + 1
            if ads_list[idx].enabled then
                targetIdx = idx
                break
            end
        end
    end

    ad_rotation_idx = targetIdx
    sendAdNow(ads_list[targetIdx].text, "queue")
end

local hr_subtab = "ads" -- "ads" | "messages"

AD_MANAGERS = {
    ["sean_verstein"] = true,
    ["brooks_wade"]   = true,
}
AD_RESTRICTIONS_RAW_URL = "https://raw.githubusercontent.com/squaliee/TRPcomm-Manager-Updates/main/ad_restrictions.json"
AD_RESTRICTIONS_API_URL = "https://api.github.com/repos/squaliee/TRPcomm-Manager-Updates/contents/ad_restrictions.json"

ad_restrictions = {
    auto_send_disabled = false,
    disabled_intervals = {
        ["1"]  = false,
        ["3"]  = false,
        ["5"]  = false,
        ["20"] = false,
        ["30"] = false,
        ["60"] = false,
    },
    updated_by = "None",
}
ad_restrictions_loading    = false
ad_restrictions_loaded     = false
ad_restrictions_last_fetch = 0
ad_restrictions_updating   = false

function isAdManager()
    if not clientName or clientName == "" then
        local ok, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
        if ok and myId and myId >= 0 then
            clientName = sampGetPlayerNickname(myId)
        end
    end
    if not clientName then return false end
    return AD_MANAGERS[clientName:lower()] == true
end

function fetchAdRestrictions(force)
    if ad_restrictions_loading then return end
    local now = os.time()
    if not force and (now - ad_restrictions_last_fetch < 60) then
        return
    end
    ad_restrictions_loading = true
    ad_restrictions_last_fetch = now
    local url = AD_RESTRICTIONS_RAW_URL .. "?cb=" .. os.time()
    performHttpGet(url, { timeout = 10 }, function(response)
        ad_restrictions_loading = false
        ad_restrictions_last_fetch = os.time()
        if response and response.status_code == 200 then
            local ok_json, data = pcall(cjson.decode, response.text)
            if ok_json and type(data) == "table" then
                ad_restrictions.auto_send_disabled = (data.auto_send_disabled == true)
                if type(data.disabled_intervals) == "table" then
                    ad_restrictions.disabled_intervals = data.disabled_intervals
                end
                ad_restrictions.updated_by = data.updated_by or "None"
                ad_restrictions_loaded = true

                if ad_restrictions.auto_send_disabled and ad_auto_send.v then
                    ad_auto_send.v = false
                    sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Автоотправка рекламы заблокирована руководством.', -1)
                end

                local curMinStr = tostring(ad_interval_minutes.v)
                if ad_restrictions.disabled_intervals[curMinStr] == true then
                    local presets = { 1, 3, 5, 20, 30, 60 }
                    for _, p in ipairs(presets) do
                        if ad_restrictions.disabled_intervals[tostring(p)] ~= true then
                            ad_interval_minutes.v = p
                            saveSettings()
                            break
                        end
                    end
                end
            end
        end
    end, function(err)
        ad_restrictions_loading = false
        ad_restrictions_last_fetch = os.time()
    end)
end

function pushAdRestrictionsToGithub()
    if ad_restrictions_updating then return end
    ad_restrictions_updating = true
    showToast("Отправка изменений на GitHub...")

    lua_thread.create(function()
        local token = ""
        if github_admin_token_buf and github_admin_token_buf.v ~= "" then
            token = u8:decode(github_admin_token_buf.v)
        elseif mainIni and mainIni.settings and mainIni.settings.github_token then
            token = tostring(mainIni.settings.github_token)
        end
        token = token:gsub("^%s+", ""):gsub("%s+$", "")

        if not token or token == "" then
            sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Ошибка: GitHub Token не задан! Введите его во вкладке "Настройки".', -1)
            showToast("Укажите GitHub токен в Настройках")
            ad_restrictions_updating = false
            return
        end

        local ok_get, get_resp = pcall(requests.get, AD_RESTRICTIONS_API_URL, {
            headers = {
                ["Authorization"] = "token " .. token,
                ["User-Agent"]    = "TRPcomm-Manager",
                ["Accept"]        = "application/vnd.github.v3+json",
            },
            timeout = 10
        })

        if not ok_get or get_resp.status_code ~= 200 then
            local code = ok_get and get_resp.status_code or 0
            if code == 401 then
                sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Ошибка GitHub: токен недействителен (401 Bad credentials). Обновите токен в Настройках.', -1)
            elseif code == 404 then
                sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Ошибка GitHub: файл ad_restrictions.json не найден (404).', -1)
            else
                sampAddChatMessage(string.format('{FF6B6B}[TRPcomm] {FFFFFF}Ошибка связи с GitHub API (HTTP %s).', tostring(code)), -1)
            end
            ad_restrictions_updating = false
            return
        end

        local ok_json, file_info = pcall(cjson.decode, get_resp.text)
        if not ok_json or not file_info or not file_info.sha then
            sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Ошибка: не удалось прочитать SHA файла на GitHub.', -1)
            ad_restrictions_updating = false
            return
        end
        local current_sha = file_info.sha

        local nick = clientName or "Admin"
        local payload_table = {
            auto_send_disabled = ad_restrictions.auto_send_disabled,
            disabled_intervals = ad_restrictions.disabled_intervals,
            updated_by = nick,
            updated_at = os.time(),
        }
        local json_str = cjson.encode(payload_table)
        local b64_mod = require 'base64'
        local b64_content = b64_mod.encode(json_str)

        local put_body = cjson.encode({
            message = "Update ad restrictions via TRPcomm by " .. nick,
            content = b64_content,
            sha = current_sha,
            branch = "main",
        })

        local ok_put, put_resp = pcall(requests.put, AD_RESTRICTIONS_API_URL, {
            headers = {
                ["Authorization"] = "token " .. token,
                ["User-Agent"]    = "TRPcomm-Manager",
                ["Content-Type"]  = "application/json",
                ["Accept"]        = "application/vnd.github.v3+json",
            },
            data = put_body,
            timeout = 15,
        })

        ad_restrictions_updating = false

        if ok_put and (put_resp.status_code == 200 or put_resp.status_code == 201) then
            showToast("Успешно! Изменения применены для всех пользователей.")
            sampAddChatMessage('{5B85C4}[TRPcomm] {FFFFFF}Ограничения рекламы успешно обновлены на GitHub!', -1)
            ad_restrictions_last_fetch = os.time()
        else
            local err_code = ok_put and tostring(put_resp.status_code) or "сеть"
            if err_code == "401" then
                sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Ошибка GitHub: доступ запрещен (401). Проверьте права токена (галочка repo).', -1)
            elseif err_code == "409" then
                sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Ошибка GitHub: конфликт версий (409 Conflict). Повторите попытку.', -1)
            else
                sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Ошибка сохранения на GitHub (' .. err_code .. ').', -1)
            end
        end
    end)
end


local function drawHRAdsTab(t)
    local dl = imgui.GetWindowDrawList()

    -- ============================================================
    --  КАРТОЧКА 1: БИБЛИОТЕКА ОБЪЯВЛЕНИЙ
    -- ============================================================
    local activeCount = 0
    for _, ad in ipairs(ads_list) do
        if ad.enabled then activeCount = activeCount + 1 end
    end

    imgui.TextColored(t.accent, fa.ICON_LIST .. u8" Библиотека объявлений")
    imgui.SameLine()
    imgui.TextColored(t.textDim, string.format(u8"(активно %d из %d)", activeCount, #ads_list))

    imgui.SameLine(imgui.GetWindowWidth() - 440)
    if imgui.Button(fa.ICON_CHECK .. u8" Вкл все##ad_all_on", imgui.ImVec2(80, 26)) then
        for _, a in ipairs(ads_list) do a.enabled = true end
        saveAdsList()
        showToast("Все объявления включены")
    end
    imgui.SameLine()
    if imgui.Button(fa.ICON_TIMES .. u8" Выкл все##ad_all_off", imgui.ImVec2(85, 26)) then
        for _, a in ipairs(ads_list) do a.enabled = false end
        saveAdsList()
        showToast("Все объявления выключены")
    end
    imgui.SameLine()
    if imgui.Checkbox(fa.ICON_RANDOM .. u8" Shuffle##ad_shuffle", ad_shuffle_enabled) then
        saveSettings()
    end
    if imgui.IsItemHovered() then
        imgui.SetTooltip(u8"Случайный порядок отправки (Shuffle)\nвместо строгой ротации по кругу")
    end

    imgui.SameLine(imgui.GetWindowWidth() - 125)
    if imgui.Button(fa.ICON_PLUS .. u8" Добавить##ad_add_open", imgui.ImVec2(110, 26)) then
        ad_edit_idx = nil
        ad_new_text.v = ""
        ad_add_form_open = true
        ad_modal_just_opened = true
    end
    imgui.Spacing()

    -- Подсказки из календаря событий
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
                if imgui.Button(ev.location .. u8"   —   Добавить в список?##cal_suggest_btn", imgui.ImVec2(-1, 24)) then
                    local raw = u8:decode(ev.location)
                    if #raw > AD_TEXT_MAX then raw = raw:sub(1, AD_TEXT_MAX) end
                    ads_list[#ads_list + 1] = { text = raw, enabled = true, sentCount = 0 }
                    saveAdsList()
                end
                imgui.PopStyleColor(3)
                imgui.PopID()
            end
        end
    end

    if #ads_list == 0 then
        imgui.PushStyleColor(imgui.Col.ChildWindowBg, imgui.ImVec4(0.12, 0.15, 0.22, 0.45))
        imgui.BeginChild("AdEmptyCard", imgui.ImVec2(-1, 55), true)
            imgui.SetCursorPos(imgui.ImVec2(16, 18))
            imgui.TextColored(t.textDim, fa.ICON_INFO_CIRCLE .. u8"  Список пуст. Нажмите «+ Добавить», чтобы создать заготовки объявлений.")
        imgui.EndChild()
        imgui.PopStyleColor()
    else
        local deleteAdIdx = nil
        for i, ad in ipairs(ads_list) do
            imgui.PushID("ad_card_" .. i)
            local p = imgui.GetCursorScreenPos()
            local rowW = imgui.GetWindowWidth() - 30

            -- Вычисляем высоту плашки под полный текст объявления
            local textUtf8 = safeU8(ad.text)
            local textMaxW = rowW - 250
            local textSize = imgui.CalcTextSize(textUtf8)
            local isMultiLine = textSize.x > textMaxW
            local rowH = isMultiLine and 50.0 or 38.0

            -- 1. Фоновая карточка строки
            local bgAlpha = ad.enabled and 0.45 or 0.20
            local rowBgCol = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.13, 0.17, 0.25, bgAlpha))
            dl:AddRectFilled(p, imgui.ImVec2(p.x + rowW, p.y + rowH), rowBgCol, 7.0)

            -- 2. Левый акцентный цветной маркер (без скругления тонкой полоски)
            local markerCol = ad.enabled and imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.25, 0.85, 0.45, 0.95))
                                          or imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.50, 0.50, 0.55, 0.50))
            dl:AddRectFilled(p, imgui.ImVec2(p.x + 4.0, p.y + rowH), markerCol)

            -- 3. Тонкая рамка карточки
            local borderCol = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.24, 0.32, 0.46, 0.50))
            dl:AddRect(p, imgui.ImVec2(p.x + rowW, p.y + rowH), borderCol, 7.0)

            -- 4. Перехват ПКМ по всей области карточки
            local mp = imgui.GetMousePos()
            local isCardHovered = mp.x >= p.x and mp.x <= (p.x + rowW) and mp.y >= p.y and mp.y <= (p.y + rowH)
            if isCardHovered and imgui.IsMouseClicked(1) then
                imgui.OpenPopup("##ad_ctx_" .. i)
            end

            -- 5. Кликабельный кружочек статуса (ВКЛ / ВЫКЛ при нажатии)
            local circleY = p.y + (rowH - 24) * 0.5
            imgui.SetCursorScreenPos(imgui.ImVec2(p.x + 10, circleY))
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(1, 1, 1, 0.15))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(1, 1, 1, 0.25))
            local circleCol = ad.enabled and imgui.ImVec4(0.25, 0.88, 0.45, 1.0) or imgui.ImVec4(0.55, 0.55, 0.60, 0.80)
            imgui.PushStyleColor(imgui.Col.Text, circleCol)
            local circleIcon = ad.enabled and fa.ICON_CIRCLE or fa.ICON_CIRCLE_O

            if imgui.Button(circleIcon .. "##toggle_ad_" .. i, imgui.ImVec2(24, 24)) then
                ad.enabled = not ad.enabled
                saveAdsList()
            end
            imgui.PopStyleColor(4)
            if imgui.IsItemHovered() then
                imgui.SetTooltip(ad.enabled and u8"Активно (нажмите, чтобы деактивировать)" or u8"Отключено (нажмите, чтобы активировать)")
            end

            -- 6. Полный текст объявления (без обрезки)
            local textY = p.y + (isMultiLine and 7.0 or (rowH - 18) * 0.5)
            imgui.SetCursorScreenPos(imgui.ImVec2(p.x + 40, textY))
            local textCol = ad.enabled and t.text or imgui.ImVec4(0.55, 0.58, 0.64, 0.70)
            imgui.PushTextWrapPos(imgui.GetCursorPosX() + textMaxW)
            imgui.TextColored(textCol, textUtf8)
            imgui.PopTextWrapPos()

            if imgui.IsItemHovered() then
                local tipText = u8"Текст: " .. textUtf8 .. string.format(u8"\nОтправлено: %d раз\n\n[Клик по кружку] - вкл/выкл\n[ПКМ по строке] - меню опций", ad.sentCount or 0)
                imgui.SetTooltip(tipText)
            end

            -- 7. Правые элементы управления (по центру строки)
            local actionsY = p.y + (rowH - 24) * 0.5

            -- Счётчик отправок
            imgui.SetCursorScreenPos(imgui.ImVec2(p.x + rowW - 195, actionsY + 3))
            imgui.TextColored(t.textDim, string.format(u8"%d отпр.", ad.sentCount or 0))

            -- Кнопка быстрой отправки
            imgui.SetCursorScreenPos(imgui.ImVec2(p.x + rowW - 125, actionsY))
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.20, 0.45, 0.80, 0.85))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.28, 0.55, 0.95, 1.0))
            if imgui.Button(fa.ICON_BULLHORN .. u8" Послать##send_row_" .. i, imgui.ImVec2(80, 24)) then
                if not ad_pending then
                    sendAdNow(ad.text, "manual")
                end
            end
            imgui.PopStyleColor(2)

            -- Кнопка изменения (карандаш)
            imgui.SetCursorScreenPos(imgui.ImVec2(p.x + rowW - 36, actionsY))
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.18, 0.24, 0.34, 0.80))
            if imgui.Button(fa.ICON_PENCIL .. "##edit_row_" .. i, imgui.ImVec2(26, 24)) then
                ad_edit_idx = i
                ad_new_text.v = u8(ad.text)
                ad_add_form_open = true
                ad_modal_just_opened = true
            end
            imgui.PopStyleColor()

            -- 8. Контекстное меню ПКМ
            if imgui.BeginPopup("##ad_ctx_" .. i) then
                imgui.TextColored(t.textDim, u8"Отправлено: " .. (ad.sentCount or 0) .. u8" раз")
                imgui.Separator()
                if imgui.MenuItem(ad.enabled and (fa.ICON_TIMES .. u8" Выключить") or (fa.ICON_CHECK .. u8" Включить")) then
                    ad.enabled = not ad.enabled
                    saveAdsList()
                end
                if imgui.MenuItem(fa.ICON_PENCIL .. u8" Изменить") then
                    ad_edit_idx = i
                    ad_new_text.v = u8(ad.text)
                    ad_add_form_open = true
                    ad_modal_just_opened = true
                end
                imgui.Separator()
                if imgui.MenuItem(fa.ICON_TRASH .. u8" Удалить") then
                    deleteAdIdx = i
                end
                imgui.EndPopup()
            end

            -- Сдвигаем курсор после завершения отрисовки карточки
            imgui.SetCursorScreenPos(imgui.ImVec2(p.x, p.y + rowH + 6.0))
            imgui.Dummy(imgui.ImVec2(rowW, 1))

            imgui.PopID()
        end

        if deleteAdIdx then
            table.remove(ads_list, deleteAdIdx)
            saveAdsList()
        end
    end

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    -- ============================================================
    --  КАРТОЧКА 2: БЫСТРАЯ ОТПРАВКА
    -- ============================================================
    local curCharLen = #safeU8Decode(ad_text.v)
    local charColor = curCharLen > 110 and imgui.ImVec4(0.95, 0.35, 0.35, 1.0)
                   or (curCharLen > 85 and imgui.ImVec4(0.95, 0.75, 0.20, 1.0) or t.textDim)

    imgui.TextColored(t.accent, fa.ICON_PAPER_PLANE .. u8" Быстрая отправка")
    imgui.SameLine(imgui.GetWindowWidth() - 175)
    imgui.TextColored(charColor, string.format(u8"Символов: %d / %d", curCharLen, AD_TEXT_MAX))

    imgui.Spacing()
    imgui.PushItemWidth(-1)
    imgui.InputTextMultiline("##ad_text", ad_text, imgui.ImVec2(-1, 68))
    imgui.PopItemWidth()

    if imgui.IsItemActive() then
        local ctrlVDown = isKeyDown(0x11) and isKeyDown(0x56)
        if ctrlVDown and not ad_text_ctrlv_was_down then
            local clip = getClipboardText()
            if clip and clip ~= "" then
                local text = clip
                if #text > AD_TEXT_MAX then text = text:sub(1, AD_TEXT_MAX) end
                ad_text.v = u8(text)
            end
        end
        ad_text_ctrlv_was_down = ctrlVDown
    else
        ad_text_ctrlv_was_down = false
    end

    imgui.Spacing()
    drawAdQuickChips(ad_text, "quick")

    imgui.Spacing()
    imgui.TextColored(t.textDim, u8"Города вещания:")
    imgui.Spacing()

    -- Стильные чипы городов (Pills)
    local function drawCityPill(name, boolVar, idStr)
        local isAct = boolVar.v
        local pushed = 0
        if isAct then
            imgui.PushStyleColor(imgui.Col.Button, t.accent)
            imgui.PushStyleColor(imgui.Col.ButtonHovered, t.accent)
            pushed = 2
        else
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.13, 0.17, 0.25, 0.90))
            pushed = 1
        end
        local prefix = isAct and (fa.ICON_CHECK .. " ") or "+ "
        if imgui.Button(prefix .. name .. "##" .. idStr, imgui.ImVec2(125, 26)) then
            boolVar.v = not boolVar.v
            saveSettings()
        end
        if pushed > 0 then imgui.PopStyleColor(pushed) end
    end

    drawCityPill(u8"Los Santos", ad_city_ls, "chip_ls")
    imgui.SameLine()
    drawCityPill(u8"San Fierro", ad_city_sf, "chip_sf")
    imgui.SameLine()
    drawCityPill(u8"Las Venturas", ad_city_lv, "chip_lv")
    imgui.SameLine()

    -- Чип "Все города"
    local allPushed = 0
    if ad_city_all.v then
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.25, 0.70, 0.50, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.30, 0.80, 0.58, 1.0))
        allPushed = 2
    else
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.13, 0.17, 0.25, 0.90))
        allPushed = 1
    end
    local allPrefix = ad_city_all.v and (fa.ICON_CHECK .. " ") or (fa.ICON_GLOBE .. " ")
    if imgui.Button(allPrefix .. u8"Все три города##chip_all", imgui.ImVec2(140, 26)) then
        ad_city_all.v = not ad_city_all.v
        saveSettings()
    end
    if allPushed > 0 then imgui.PopStyleColor(allPushed) end

    imgui.Spacing(); imgui.Spacing()

    if ad_pending then
        imgui.TextColored(t.textDim, fa.ICON_SPINNER .. u8"  Ожидание ответа сервера...")
    else
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.20, 0.48, 0.88, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.28, 0.58, 0.98, 1.0))
        if imgui.Button(fa.ICON_BULLHORN .. u8"  Отправить объявление сейчас##ad_send", imgui.ImVec2(260, 32)) then
            local textRaw = safeU8Decode(ad_text.v)
            if textRaw == "" then
                sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Сначала введи текст объявления.', -1)
            else
                sendAdNow(textRaw, "manual")
            end
        end
        imgui.PopStyleColor(2)
    end

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    -- ============================================================
    --  КАРТОЧКА 3: АВТОМАТИЗАЦИЯ И РАСПИСАНИЕ
    -- ============================================================
    imgui.TextColored(t.accent, fa.ICON_REFRESH .. u8" Автоотправка по очереди")
    if isAdManager() then
        if imgui.IsItemHovered() then
            imgui.SetTooltip(u8"[ПКМ] — управление автоотправкой (Админ)")
        end
        if imgui.IsItemClicked(1) then
            imgui.OpenPopup("##admin_autosend_ctx")
        end
    end

    if isAdManager() and imgui.BeginPopup("##admin_autosend_ctx") then
        imgui.TextColored(t.accent, fa.ICON_SHIELD .. u8" Управление автоотправкой (Админ)")
        imgui.Separator()
        local isDis = ad_restrictions.auto_send_disabled
        local label = isDis and (fa.ICON_CHECK .. u8" Разрешить автоотправку для всех")
                             or (fa.ICON_BAN .. u8" Заблокировать автоотправку для всех")
        if imgui.MenuItem(label) then
            ad_restrictions.auto_send_disabled = not isDis
            if ad_restrictions.auto_send_disabled then ad_auto_send.v = false end
            pushAdRestrictionsToGithub()
        end
        imgui.EndPopup()
    end

    imgui.SameLine(imgui.GetWindowWidth() - 290)

    -- Живой индикатор статуса в шапке
    if ad_restrictions.auto_send_disabled then
        imgui.TextColored(imgui.ImVec4(0.95, 0.35, 0.35, 1.0), fa.ICON_BAN .. u8" ЗАБЛОКИРОВАНО РУКОВОДСТВОМ")
    elseif ad_auto_send.v then
        local secLeft = math.max(0, ad_next_send_time - os.time())
        local statusTxt = fa.ICON_CHECK_CIRCLE .. u8" АКТИВНО (" .. formatMMSS(secLeft) .. u8")  |  " .. getNextCityName()
        if ad_limit_enabled.v then
            local left = math.max(0, ad_limit_max.v - ad_limit_sent)
            statusTxt = statusTxt .. string.format(u8"  |  Осталось: %d", left)
        end
        imgui.TextColored(imgui.ImVec4(0.30, 0.88, 0.45, 1.0), statusTxt)
    else
        imgui.TextColored(t.textDim, fa.ICON_MINUS_CIRCLE .. u8" ВЫКЛЮЧЕНО")
    end

    imgui.Spacing()

    -- Чекбокс включения автоотправки
    if ad_restrictions.auto_send_disabled then
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.55, 0.55, 0.60, 0.65))
        imgui.Text(fa.ICON_LOCK .. u8"  Циклическая отправка отключена руководством TRPcomm")
        imgui.PopStyleColor()
        if isAdManager() then
            if imgui.IsItemHovered() then imgui.SetTooltip(u8"[ПКМ] — разблокировать автоотправку (Админ)") end
            if imgui.IsItemClicked(1) then imgui.OpenPopup("##admin_autosend_ctx") end
        end
    else
        if imgui.Checkbox(u8"Включить циклическую отправку всех объявлений из списка", ad_auto_send) then
            if ad_auto_send.v then
                if ad_limit_enabled.v and ad_limit_sent >= ad_limit_max.v then
                    ad_limit_sent = 0
                end
                if ad_schedule_enabled.v and not isServerTimeInSchedule() then
                    showToast("Внимание: сейчас вне расписания (отправка начнётся по времени)")
                else
                    ad_next_send_time = os.time()
                end
            end
        end
        if isAdManager() then
            if imgui.IsItemHovered() then imgui.SetTooltip(u8"[ПКМ] — заблокировать автоотправку для всех (Админ)") end
            if imgui.IsItemClicked(1) then imgui.OpenPopup("##admin_autosend_ctx") end
        end
    end

    imgui.Spacing()
    imgui.TextColored(t.textDim, u8"Интервал между отправками:")
    imgui.Spacing()

    local intervalPresets = {1, 3, 5, 20, 30, 60}
    for i, minutes in ipairs(intervalPresets) do
        local minKey = tostring(minutes)
        local isIntervalDisabled = (ad_restrictions.disabled_intervals[minKey] == true)
        local isActive = (ad_interval_minutes.v == minutes)
        local pushed = 0

        if isIntervalDisabled then
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.12, 0.14, 0.18, 0.60))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.14, 0.16, 0.20, 0.70))
            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.50, 0.52, 0.58, 0.55))
            pushed = 3
        elseif isActive then
            imgui.PushStyleColor(imgui.Col.Button, t.accent)
            imgui.PushStyleColor(imgui.Col.ButtonHovered, t.accent)
            pushed = 2
        else
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.13, 0.17, 0.25, 0.90))
            pushed = 1
        end

        local btnLabel = isIntervalDisabled and (fa.ICON_LOCK .. " " .. minutes .. u8" мин") or (minutes .. u8" мин")
        if imgui.Button(btnLabel .. "##ad_interval_" .. minutes, imgui.ImVec2(76, 26)) then
            if isIntervalDisabled then
                sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Этот интервал временно отключен руководством.', -1)
            else
                ad_interval_minutes.v = minutes
                saveSettings()
                if ad_auto_send.v then
                    ad_next_send_time = os.time() + (minutes * 60) + 2
                end
            end
        end

        if pushed > 0 then imgui.PopStyleColor(pushed) end

        if imgui.IsItemHovered() then
            if isIntervalDisabled then
                if isAdManager() then
                    imgui.SetTooltip(u8"Отключено руководством\n[ПКМ] — включить для всех (Админ)")
                else
                    imgui.SetTooltip(u8"Интервал отключен руководством TRPcomm")
                end
            else
                if isAdManager() then
                    imgui.SetTooltip(u8"Интервал " .. minutes .. u8" мин\n[ПКМ] — отключить для всех (Админ)")
                end
            end
        end

        if isAdManager() and imgui.IsItemClicked(1) then
            imgui.OpenPopup("##admin_btn_ctx_" .. minutes)
        end

        if isAdManager() and imgui.BeginPopup("##admin_btn_ctx_" .. minutes) then
            imgui.TextColored(t.accent, fa.ICON_SHIELD .. string.format(u8" Интервал %d мин (Админ)", minutes))
            imgui.Separator()
            local optLabel = isIntervalDisabled and (fa.ICON_CHECK .. u8" Включить кнопку для всех")
                                                or (fa.ICON_BAN .. u8" Отключить кнопку для всех")
            if imgui.MenuItem(optLabel) then
                ad_restrictions.disabled_intervals[minKey] = not isIntervalDisabled
                if ad_restrictions.disabled_intervals[minKey] and ad_interval_minutes.v == minutes then
                    for _, m in ipairs(intervalPresets) do
                        if ad_restrictions.disabled_intervals[tostring(m)] ~= true then
                            ad_interval_minutes.v = m
                            saveSettings()
                            break
                        end
                    end
                end
                pushAdRestrictionsToGithub()
            end
            imgui.EndPopup()
        end

        if i < #intervalPresets then imgui.SameLine() end
    end

    imgui.Spacing()
    imgui.AlignTextToFramePadding()
    if imgui.Checkbox(u8"Остановить после##ad_limit_cb", ad_limit_enabled) then
        saveSettings()
    end
    imgui.SameLine()

    imgui.PushItemWidth(44)
    if imgui.InputInt("##ad_limit_val", ad_limit_max, 0, 0) then
        if ad_limit_max.v < 1 then ad_limit_max.v = 1 end
        if ad_limit_max.v > 9999 then ad_limit_max.v = 9999 end
        saveSettings()
    end
    imgui.PopItemWidth()
    imgui.SameLine()

    local limBtnW, limBtnH = 22, 22
    if imgui.Button("-##ad_limit_minus", imgui.ImVec2(limBtnW, limBtnH)) then
        if ad_limit_max.v > 1 then
            ad_limit_max.v = ad_limit_max.v - 1
            saveSettings()
        end
    end
    imgui.SameLine()
    if imgui.Button("+##ad_limit_plus", imgui.ImVec2(limBtnW, limBtnH)) then
        if ad_limit_max.v < 9999 then
            ad_limit_max.v = ad_limit_max.v + 1
            saveSettings()
        end
    end
    imgui.SameLine()

    local limitInfo = u8"отправок"
    if ad_limit_enabled.v then
        limitInfo = string.format(u8"отправок (отправлено: %d из %d)", ad_limit_sent, ad_limit_max.v)
    end
    imgui.Text(limitInfo)
    if ad_limit_sent > 0 then
        imgui.SameLine()
        if imgui.SmallButton(u8"Сбросить##ad_reset_limit") then
            ad_limit_sent = 0
        end
    end
    imgui.SameLine(imgui.GetWindowWidth() - 250)
    imgui.TextColored(t.textDim, string.format(u8"За сессию: %d отпр. (~$%d)", ad_session_sent_count or 0, ad_session_spent or 0))

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    -- ============================================================
    --  БЛОК РАСПИСАНИЯ
    -- ============================================================
    imgui.TextColored(t.accent, fa.ICON_CLOCK_O .. u8" Расписание (автостарт и автостоп)")
    imgui.Spacing()

    if imgui.Checkbox(u8"Отправлять рекламу только в заданное время", ad_schedule_enabled) then
        saveSettings()
        if ad_schedule_enabled.v then
            local inSched = isServerTimeInSchedule()
            ad_schedule_was_in = inSched
            if inSched then
                ad_auto_send.v = true
                ad_next_send_time = os.time()
                showToast("Реклама: автостарт по расписанию")
            else
                ad_auto_send.v = false
            end
        else
            ad_schedule_was_in = nil
        end
    end

    imgui.Spacing()

    local btnW, btnH = 22, 22
    local boxW = 38

    -- Строка "С:"
    imgui.AlignTextToFramePadding()
    imgui.Text(u8"С:")
    imgui.SameLine(36)

    imgui.PushItemWidth(boxW)
    if imgui.InputInt("##sched_from_h", ad_schedule_from_hour, 0, 0) then
        if ad_schedule_from_hour.v < 0 then ad_schedule_from_hour.v = 0 end
        if ad_schedule_from_hour.v > 23 then ad_schedule_from_hour.v = 23 end
        saveSettings()
    end
    imgui.PopItemWidth()
    imgui.SameLine()

    if imgui.Button("-##sched_from_h_minus", imgui.ImVec2(btnW, btnH)) then
        ad_schedule_from_hour.v = (ad_schedule_from_hour.v - 1 + 24) % 24
        saveSettings()
    end
    imgui.SameLine()

    if imgui.Button("+##sched_from_h_plus", imgui.ImVec2(btnW, btnH)) then
        ad_schedule_from_hour.v = (ad_schedule_from_hour.v + 1) % 24
        saveSettings()
    end
    imgui.SameLine()

    imgui.Text(":")
    imgui.SameLine()

    imgui.PushItemWidth(boxW)
    if imgui.InputInt("##sched_from_m", ad_schedule_from_min, 0, 0) then
        if ad_schedule_from_min.v < 0 then ad_schedule_from_min.v = 0 end
        if ad_schedule_from_min.v > 59 then ad_schedule_from_min.v = 59 end
        saveSettings()
    end
    imgui.PopItemWidth()
    imgui.SameLine()

    if imgui.Button("-##sched_from_m_minus", imgui.ImVec2(btnW, btnH)) then
        ad_schedule_from_min.v = (ad_schedule_from_min.v - 1 + 60) % 60
        saveSettings()
    end
    imgui.SameLine()

    if imgui.Button("+##sched_from_m_plus", imgui.ImVec2(btnW, btnH)) then
        ad_schedule_from_min.v = (ad_schedule_from_min.v + 1) % 60
        saveSettings()
    end

    -- Строка "До:"
    imgui.AlignTextToFramePadding()
    imgui.Text(u8"До:")
    imgui.SameLine(36)

    imgui.PushItemWidth(boxW)
    if imgui.InputInt("##sched_to_h", ad_schedule_to_hour, 0, 0) then
        if ad_schedule_to_hour.v < 0 then ad_schedule_to_hour.v = 0 end
        if ad_schedule_to_hour.v > 23 then ad_schedule_to_hour.v = 23 end
        saveSettings()
    end
    imgui.PopItemWidth()
    imgui.SameLine()

    if imgui.Button("-##sched_to_h_minus", imgui.ImVec2(btnW, btnH)) then
        ad_schedule_to_hour.v = (ad_schedule_to_hour.v - 1 + 24) % 24
        saveSettings()
    end
    imgui.SameLine()

    if imgui.Button("+##sched_to_h_plus", imgui.ImVec2(btnW, btnH)) then
        ad_schedule_to_hour.v = (ad_schedule_to_hour.v + 1) % 24
        saveSettings()
    end
    imgui.SameLine()

    imgui.Text(":")
    imgui.SameLine()

    imgui.PushItemWidth(boxW)
    if imgui.InputInt("##sched_to_m", ad_schedule_to_min, 0, 0) then
        if ad_schedule_to_min.v < 0 then ad_schedule_to_min.v = 0 end
        if ad_schedule_to_min.v > 59 then ad_schedule_to_min.v = 59 end
        saveSettings()
    end
    imgui.PopItemWidth()
    imgui.SameLine()

    if imgui.Button("-##sched_to_m_minus", imgui.ImVec2(btnW, btnH)) then
        ad_schedule_to_min.v = (ad_schedule_to_min.v - 1 + 60) % 60
        saveSettings()
    end
    imgui.SameLine()

    if imgui.Button("+##sched_to_m_plus", imgui.ImVec2(btnW, btnH)) then
        ad_schedule_to_min.v = (ad_schedule_to_min.v + 1) % 60
        saveSettings()
    end

    imgui.Spacing()

    local inSched = isServerTimeInSchedule()
    local schedStatus = inSched and "в расписании" or "вне расписания"
    local schedText = string.format("%02d:%02d - %02d:%02d  |  Сейчас: %s",
        ad_schedule_from_hour.v, ad_schedule_from_min.v,
        ad_schedule_to_hour.v, ad_schedule_to_min.v,
        schedStatus)
    imgui.TextColored(inSched and imgui.ImVec4(0.3, 0.88, 0.5, 1.0) or t.textDim, u8(schedText))
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
    local timeMin = os.date("!%Y-%m-%dT%H:%M:%SZ", os.time() - 90 * 86400) -- 90 дней назад
    local url = "https://www.googleapis.com/calendar/v3/calendars/"
        .. GCAL_ID:gsub(":", "%%3A")
        .. "/events?key=" .. GCAL_API_KEY
        .. "&singleEvents=true&orderBy=startTime&timeMin=" .. timeMin
        .. "&maxResults=250"

    performHttpGet(url, { timeout = 15 }, function(response)
        calendar_loading = false
        calendar_loaded_once = true

        if not response or response.status_code ~= 200 then
            return
        end

        local ok_json, data = pcall(cjson.decode, response.text)
        if not ok_json or not data or not data.items then
            return
        end

        local function cleanEventDescription(desc)
            if not desc or desc == "" then return desc end
            desc = desc:gsub("<[Bb][Rr]%s*/?>", "\n")   -- <br>, <br/>, <br /> -> перенос строки
            desc = desc:gsub("</[Pp]>", "\n")
            desc = desc:gsub("</[Dd][Ii][Vv]>", "\n")
            desc = desc:gsub("<[^>]+>", "")
            desc = desc:gsub("&nbsp;", " ")
            desc = desc:gsub("&amp;", "&")
            desc = desc:gsub("&lt;", "<")
            desc = desc:gsub("&gt;", ">")
            desc = desc:gsub("&quot;", '"')
            desc = desc:gsub("&#39;", "'")
            desc = desc:gsub("\n\n\n+", "\n\n")
            desc = desc:gsub("^%s+", ""):gsub("%s+$", "")
            return desc
        end

        calendar_events = {}
        for _, item in ipairs(data.items) do

            local startRaw = item.start and (item.start.dateTime or item.start.date)
            local isAllDay = item.start and item.start.date ~= nil
            local y, mo, d, h, mi = parseISODateTime(startRaw)
            calendar_events[#calendar_events + 1] = {
                summary     = (item.summary and item.summary ~= "") and item.summary or u8"Без названия",
                description = cleanEventDescription(item.description),
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

            if nextEvent.h and not nextEvent.isAllDay then
                local newTimestamp = os.time({
                    year = nextEvent.y, month = nextEvent.mo, day = nextEvent.d,
                    hour = nextEvent.h, min = nextEvent.mi, sec = 0,
                })
                if newTimestamp ~= upcoming_event_timestamp then
                    event_notify_30_sent = false
                    event_notify_10_sent = false
                end
                upcoming_event_timestamp = newTimestamp
            else
                upcoming_event_timestamp = nil -- ивент "весь день" — время начала не определено, уведомлять не о чем
            end
        else
            upcoming_event_name = u8"Нет предстоящих ивентов"
            upcoming_event_time = "--:--"
            upcoming_event_timestamp = nil
        end

    end, function(err)
        calendar_loading = false
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
    local firstWeekday = weekdayOfFirst(calendar_view_year, calendar_view_month)
    local totalDays = daysInMonth(calendar_view_year, calendar_view_month)
    local totalRows = math.ceil((firstWeekday + totalDays) / 7)

    local avail = imgui.GetContentRegionAvail()
    local cellW = math.floor((avail.x - CAL_GAP * 6) / 7)
    if cellW < 80 then cellW = CAL_CELL_W end

    for col = 1, 7 do
        if col > 1 then imgui.SameLine(0, CAL_GAP) end
        imgui.BeginChild("cal_wd_" .. col, imgui.ImVec2(cellW, 20), false)
            local tw = imgui.CalcTextSize(WEEKDAY_NAMES[col]).x
            imgui.SetCursorPosX(math.max(0, (cellW - tw) * 0.5))
            imgui.TextColored(t.textDim, WEEKDAY_NAMES[col])
        imgui.EndChild()
    end

    imgui.Spacing()

    local availH = imgui.GetContentRegionAvail().y
    local spacingY = imgui.GetStyle().ItemSpacing.y
    local cellH = math.floor((availH - (totalRows - 1) * (spacingY * 2)) / math.max(1, totalRows))
    if cellH < 44 then cellH = 44 elseif cellH > 82 then cellH = 82 end

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

                imgui.Button(tostring(cellDay), imgui.ImVec2(cellW, cellH))

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
                imgui.Dummy(imgui.ImVec2(cellW, cellH))
            end

            imgui.PopID()
        end
        imgui.Spacing()
    end
end

local function getAdsStatsSummary()
    local totalSent = 0
    local topAd, topCount = nil, 0
    local totalSpent = 0
    for _, ad in ipairs(ads_list) do
        local c = ad.sentCount or 0
        totalSent = totalSent + c
        totalSpent = totalSpent + (c * math.max(20, #ad.text * 2))
        if c > topCount then
            topCount = c
            topAd = ad
        end
    end
    return totalSent, topAd, topCount, totalSpent
end

local function drawAnalyticsListTab(t)
    if #ads_list == 0 then
        imgui.TextColored(t.textDim, u8"Список объявлений пуст.")
        return
    end

    local sorted = {}
    for _, ad in ipairs(ads_list) do sorted[#sorted + 1] = ad end
    table.sort(sorted, function(a, b) return (a.sentCount or 0) > (b.sentCount or 0) end)

    for i, ad in ipairs(sorted) do
        imgui.PushID("analytics_list_" .. i)
        local preview = ad.text:sub(1, 70)
        if #ad.text > 70 then preview = preview .. "..." end
        imgui.TextColored(ad.enabled and t.text or t.textDim, u8(preview))
        imgui.SameLine(imgui.GetWindowWidth() - 90)
        imgui.TextColored(t.accent, tostring(ad.sentCount or 0) .. u8" раз")
        imgui.PopID()
        imgui.Spacing()
    end
end

local function drawAnalyticsHistoryTab(t)
    if #ad_history_log == 0 then
        imgui.TextColored(t.textDim, u8"История пуста — пока не отправлено ни одного объявления.")
        return
    end

    imgui.TextColored(t.textDim, u8"Последние " .. #ad_history_log .. u8" из " .. AD_HISTORY_LIMIT .. u8" (лимит)")
    imgui.Spacing()

    local sourceLabels = { manual = u8"Вручную", queue = u8"Очередь", campaign = u8"Кампания" }

    for i = #ad_history_log, 1, -1 do
        local entry = ad_history_log[i]
        imgui.PushID("analytics_hist_" .. i)
        imgui.TextColored(t.textDim, os.date("%d.%m %H:%M", entry.ts))
        imgui.SameLine()
        imgui.TextColored(t.accent, "[" .. (sourceLabels[entry.source] or entry.source or "?") .. "]")
        imgui.SameLine()
        imgui.TextColored(t.text, u8(entry.text))
        imgui.PopID()
    end
end

local analytics_chart_mode = "pie" -- "pie" | "bars"

local CHART_PALETTE = {
    imgui.ImVec4(0.24, 0.52, 0.95, 1.0), -- Royal Blue
    imgui.ImVec4(0.12, 0.75, 0.65, 1.0), -- Teal
    imgui.ImVec4(0.95, 0.40, 0.25, 1.0), -- Coral / Orange
    imgui.ImVec4(0.92, 0.70, 0.18, 1.0), -- Amber / Gold
    imgui.ImVec4(0.68, 0.38, 0.95, 1.0), -- Purple
    imgui.ImVec4(0.20, 0.82, 0.45, 1.0), -- Emerald
    imgui.ImVec4(0.92, 0.30, 0.55, 1.0), -- Rose / Pink
    imgui.ImVec4(0.10, 0.80, 0.90, 1.0), -- Cyan
    imgui.ImVec4(0.85, 0.25, 0.25, 1.0), -- Crimson
    imgui.ImVec4(0.55, 0.85, 0.20, 1.0), -- Lime
    imgui.ImVec4(0.40, 0.50, 0.95, 1.0), -- Indigo
    imgui.ImVec4(0.70, 0.70, 0.75, 1.0), -- Silver
}

local function drawAnalyticsChartTab(t)
    local totalSent, topAd, topCount = getAdsStatsSummary()

    if #ads_list == 0 or totalSent == 0 then
        imgui.TextColored(t.textDim, u8"Пока нет статистики отправок для построения графика.")
        imgui.Spacing()
        imgui.TextColored(t.textDim, u8"Отправьте хотя бы одно объявление, чтобы здесь появилась интерактивная статистика.")
        return
    end

    -- Переключатель режима: Круговой / Столбчатый график
    local isPie = (analytics_chart_mode == "pie")
    local pushed = 0
    if isPie then
        imgui.PushStyleColor(imgui.Col.Button, t.accent)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, t.accent)
        pushed = 2
    end
    if imgui.Button(fa.ICON_PIE_CHART .. u8" Круговая диаграмма##chart_mode_pie", imgui.ImVec2(180, 28)) then
        analytics_chart_mode = "pie"
    end
    if pushed > 0 then imgui.PopStyleColor(pushed) end

    imgui.SameLine()

    pushed = 0
    if not isPie then
        imgui.PushStyleColor(imgui.Col.Button, t.accent)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, t.accent)
        pushed = 2
    end
    if imgui.Button(fa.ICON_BAR_CHART .. u8" Столбчатый график##chart_mode_bars", imgui.ImVec2(180, 28)) then
        analytics_chart_mode = "bars"
    end
    if pushed > 0 then imgui.PopStyleColor(pushed) end

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    -- Подготовка данных: только объявления с ненулевым счётчиком отправок
    local activeAds = {}
    for _, ad in ipairs(ads_list) do
        if (ad.sentCount or 0) > 0 then
            activeAds[#activeAds + 1] = ad
        end
    end
    table.sort(activeAds, function(a, b) return (a.sentCount or 0) > (b.sentCount or 0) end)

    if #activeAds == 0 then
        imgui.TextColored(t.textDim, u8"Нет данных для отображения.")
        return
    end

    if analytics_chart_mode == "bars" then
        -- Столбчатый режим
        local maxCount = math.max(topCount, 1)
        local barMaxWidth = 360
        local barHeight = 22

        for i, ad in ipairs(activeAds) do
            imgui.PushID("analytics_bar_" .. i)
            local pct = ((ad.sentCount or 0) / totalSent) * 100.0
            local col = CHART_PALETTE[((i - 1) % #CHART_PALETTE) + 1]
            local colU32 = imgui.ColorConvertFloat4ToU32(col)

            local preview = ad.text:sub(1, 45)
            if #ad.text > 45 then preview = preview .. "..." end
            imgui.TextColored(t.text, u8(preview))
            imgui.SameLine(imgui.GetWindowWidth() - 170)
            imgui.TextColored(col, string.format("%.1f%%", pct) .. u8" (" .. (ad.sentCount or 0) .. u8" раз)")

            local barWidth = math.max(6, ((ad.sentCount or 0) / maxCount) * barMaxWidth)
            local barPos = imgui.GetCursorScreenPos()
            imgui.GetWindowDrawList():AddRectFilled(
                barPos,
                imgui.ImVec2(barPos.x + barWidth, barPos.y + barHeight),
                colU32, 4.0
            )
            imgui.Dummy(imgui.ImVec2(barMaxWidth, barHeight + 4))

            imgui.PopID()
            imgui.Spacing()
        end
        return
    end

    -- ============================================================
    --  КРУГОВАЯ ДИАГРАММА (DONUT CHART С ИНТЕРАКТИВНЫМ НАВЕДЕНИЕМ)
    -- ============================================================
    local slices = {}
    local currentAngle = -math.pi * 0.5 -- начинаем строго сверху (12 часов)
    for i, ad in ipairs(activeAds) do
        local count = ad.sentCount or 0
        local share = count / totalSent
        local span = share * (2 * math.pi)
        local a1 = currentAngle
        local a2 = currentAngle + span
        currentAngle = a2
        local col = CHART_PALETTE[((i - 1) % #CHART_PALETTE) + 1]
        slices[#slices + 1] = {
            idx = i,
            ad = ad,
            count = count,
            percent = share * 100.0,
            a1 = a1,
            a2 = a2,
            midAngle = (a1 + a2) * 0.5,
            span = span,
            color = col,
        }
    end

    local dl = imgui.GetWindowDrawList()
    local chartOrigin = imgui.GetCursorScreenPos()
    local chartSize = 220.0
    local center = imgui.ImVec2(chartOrigin.x + chartSize * 0.5, chartOrigin.y + chartSize * 0.5)
    local outerRadius = 92.0
    local innerRadius = 52.0

    -- Невидимый виджет для регистрации событий мыши в зоне диаграммы
    imgui.InvisibleButton("##donut_chart_canvas", imgui.ImVec2(chartSize, chartSize))
    local isCanvasHovered = imgui.IsItemHovered()

    local mousePos = imgui.GetIO().MousePos
    local dx = mousePos.x - center.x
    local dy = mousePos.y - center.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local hoveredIdx = nil

    -- Определение сектора под курсором мыши
    if isCanvasHovered and dist >= (innerRadius - 6) and dist <= (outerRadius + 14) then
        local rawAngle = math.atan2(dy, dx)
        local startAngle0 = -math.pi * 0.5
        local normAngle = startAngle0 + ((rawAngle - startAngle0) % (2 * math.pi))
        for i, s in ipairs(slices) do
            if normAngle >= s.a1 and normAngle < s.a2 then
                hoveredIdx = i
                break
            end
        end
    end

    -- Правая колонка: Интерактивная легенда
    imgui.SameLine(chartSize + 20)
    imgui.BeginChild("DonutLegend", imgui.ImVec2(0, chartSize), true)
        imgui.TextColored(t.accent, u8"Доли объявлений в эфире:")
        imgui.Spacing()

        for i, s in ipairs(slices) do
            imgui.PushID("legend_slice_" .. i)
            local p = imgui.GetCursorScreenPos()

            -- Выделение, если этот сектор наведён на круге или в списке
            local isThisHovered = (hoveredIdx == i)
            if isThisHovered then
                dl:AddRectFilled(
                    imgui.ImVec2(p.x - 4, p.y - 2),
                    imgui.ImVec2(p.x + imgui.GetWindowWidth() - 15, p.y + 24),
                    imgui.ColorConvertFloat4ToU32(imgui.ImVec4(s.color.x, s.color.y, s.color.z, 0.16)),
                    6.0
                )
                dl:AddRect(
                    imgui.ImVec2(p.x - 4, p.y - 2),
                    imgui.ImVec2(p.x + imgui.GetWindowWidth() - 15, p.y + 24),
                    imgui.ColorConvertFloat4ToU32(imgui.ImVec4(s.color.x, s.color.y, s.color.z, 0.60)),
                    6.0, 15, 1.2
                )
            end

            -- Цветовой маркер
            local colU32 = imgui.ColorConvertFloat4ToU32(s.color)
            dl:AddRectFilled(imgui.ImVec2(p.x, p.y + 4), imgui.ImVec2(p.x + 12, p.y + 16), colU32, 3.0)

            imgui.SetCursorPosX(imgui.GetCursorPosX() + 18)
            imgui.TextColored(s.color, string.format("%5.1f%%", s.percent))

            imgui.SameLine()
            imgui.TextColored(t.textDim, "(" .. s.count .. u8" раз)")

            imgui.SameLine()
            local preview = s.ad.text:sub(1, 38)
            if #s.ad.text > 38 then preview = preview .. "..." end
            imgui.TextColored(isThisHovered and imgui.ImVec4(1, 1, 1, 1) or t.text, u8(preview))

            if imgui.IsItemHovered() then
                hoveredIdx = i
                imgui.BeginTooltip()
                imgui.TextColored(s.color, u8(string.format("Отправлено: %d раз (%.1f%% от всех)", s.count, s.percent)))
                imgui.Separator()
                imgui.PushTextWrapPos(350)
                imgui.Text(u8(s.ad.text))
                imgui.PopTextWrapPos()
                imgui.EndTooltip()
            end

            imgui.PopID()
            imgui.Spacing()
        end
    imgui.EndChild()

    -- Отрисовка секторов круга
    for i, s in ipairs(slices) do
        local isThisHovered = (hoveredIdx == i)
        local shift = isThisHovered and 7.0 or 0.0
        local segCenter = imgui.ImVec2(
            center.x + math.cos(s.midAngle) * shift,
            center.y + math.sin(s.midAngle) * shift
        )
        local curOuterR = outerRadius + (isThisHovered and 6.0 or 0.0)
        local curInnerR = innerRadius - (isThisHovered and 2.5 or 0.0)

        local alpha = 1.0
        if hoveredIdx ~= nil and not isThisHovered then
            alpha = 0.45
        end

        local col = imgui.ImVec4(s.color.x, s.color.y, s.color.z, alpha)
        local colU32 = imgui.ColorConvertFloat4ToU32(col)
        local numSegments = math.max(6, math.floor(36 * (s.span / (2 * math.pi))))

        -- Неоновое свечение сектора при наведении
        if isThisHovered then
            local glowCol = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(col.x, col.y, col.z, 0.40))
            dl:PathClear()
            dl:PathArcTo(segCenter, curOuterR + 5.0, s.a1, s.a2, numSegments)
            dl:PathArcTo(segCenter, math.max(0, curInnerR - 4.0), s.a2, s.a1, numSegments)
            dl:PathFillConvex(glowCol)
        end

        -- Заливка сектора
        dl:PathClear()
        dl:PathArcTo(segCenter, curOuterR, s.a1, s.a2, numSegments)
        dl:PathArcTo(segCenter, curInnerR, s.a2, s.a1, numSegments)
        dl:PathFillConvex(colU32)

        -- Разделительный контур
        if #slices > 1 then
            dl:PathClear()
            dl:PathArcTo(segCenter, curOuterR, s.a1, s.a2, numSegments)
            dl:PathArcTo(segCenter, curInnerR, s.a2, s.a1, numSegments)
            dl:PathStroke(imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.08, 0.10, 0.14, 0.95)), true, 1.5)
        end
    end

    -- Центр кольца (Glass Center Core)
    local centerHoleR = innerRadius - 4.0
    local centerBgCol = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.08, 0.11, 0.16, 0.96))
    dl:AddCircleFilled(center, centerHoleR, centerBgCol, 32)
    local centerBorderCol = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.22, 0.28, 0.40, 0.85))
    dl:AddCircle(center, centerHoleR, centerBorderCol, 32, 1.5)

    -- Текст внутри центра кольца
    if hoveredIdx and slices[hoveredIdx] then
        local s = slices[hoveredIdx]
        local pctStr = string.format("%.1f%%", s.percent)
        local countStr = s.count .. u8" раз"

        local pctSize = imgui.CalcTextSize(pctStr)
        local countSize = imgui.CalcTextSize(countStr)

        dl:AddText(imgui.ImVec2(center.x - pctSize.x * 0.5, center.y - 15.0), imgui.ColorConvertFloat4ToU32(s.color), pctStr)
        dl:AddText(imgui.ImVec2(center.x - countSize.x * 0.5, center.y + 4.0), imgui.ColorConvertFloat4ToU32(t.text), countStr)

        -- Всплывающая подсказка при наведении на сектор
        if isCanvasHovered then
            imgui.BeginTooltip()
            imgui.TextColored(s.color, u8"Доля в эфире: " .. pctStr .. " (" .. countStr .. ")")
            imgui.Separator()
            imgui.PushTextWrapPos(350)
            imgui.Text(u8(s.ad.text))
            imgui.PopTextWrapPos()
            imgui.EndTooltip()
        end
    else
        local totalStr = tostring(totalSent)
        local subStr = u8"отправок"

        local totalSize = imgui.CalcTextSize(totalStr)
        local subSize = imgui.CalcTextSize(subStr)

        dl:AddText(imgui.ImVec2(center.x - totalSize.x * 0.5, center.y - 15.0), imgui.ColorConvertFloat4ToU32(t.accent), totalStr)
        dl:AddText(imgui.ImVec2(center.x - subSize.x * 0.5, center.y + 4.0), imgui.ColorConvertFloat4ToU32(t.textDim), subStr)
    end
end

analytics_subtab = "list" -- "list" | "history" | "chart"

local function drawHRAnalyticsTab(t)
    imgui.TextColored(t.accent, u8"Аналитика по объявлениям")
    imgui.Spacing()

    local totalSent, topAd, topCount = getAdsStatsSummary()
    imgui.TextColored(t.textDim, u8"Всего отправлено объявлений: ")
    imgui.SameLine()
    imgui.TextColored(t.accent, tostring(totalSent))

    if topAd then
        imgui.TextColored(t.textDim, u8"Самое частое: ")
        imgui.SameLine()
        local topPreview = topAd.text:sub(1, 50)
        if #topAd.text > 50 then topPreview = topPreview .. "..." end
        imgui.TextColored(t.accent, u8(topPreview) .. " (" .. topCount .. ")")
    end

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    local pushed = 0
    if analytics_subtab == "list" then
        imgui.PushStyleColor(imgui.Col.Button, t.accent)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, t.accent)
        pushed = 2
    end
    if imgui.Button(u8"Список##analytics_sub_list", imgui.ImVec2(120, 28)) then
        analytics_subtab = "list"
    end
    if pushed > 0 then imgui.PopStyleColor(pushed) end

    imgui.SameLine()

    pushed = 0
    if analytics_subtab == "history" then
        imgui.PushStyleColor(imgui.Col.Button, t.accent)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, t.accent)
        pushed = 2
    end
    if imgui.Button(u8"История##analytics_sub_history", imgui.ImVec2(120, 28)) then
        analytics_subtab = "history"
    end
    if pushed > 0 then imgui.PopStyleColor(pushed) end

    imgui.SameLine()

    pushed = 0
    if analytics_subtab == "chart" then
        imgui.PushStyleColor(imgui.Col.Button, t.accent)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, t.accent)
        pushed = 2
    end
    if imgui.Button(u8"График##analytics_sub_chart", imgui.ImVec2(120, 28)) then
        analytics_subtab = "chart"
    end
    if pushed > 0 then imgui.PopStyleColor(pushed) end

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    if analytics_subtab == "list" then
        drawAnalyticsListTab(t)
    elseif analytics_subtab == "history" then
        drawAnalyticsHistoryTab(t)
    else
        drawAnalyticsChartTab(t)
    end
end

local function drawHRTab(t)
    imgui.TextColored(t.accent, fa.ICON_BULLHORN .. u8" РЕКЛАМНЫЙ ОТДЕЛ")

    -- Живой бейдж серверного времени по МСК в правом верхнем углу
    local st = getServerTime()
    local clockStr = string.format(u8"  Время сервера: %02d:%02d:%02d МСК", st.hour, st.min, st.sec)
    imgui.SameLine(imgui.GetWindowWidth() - 225)
    imgui.TextColored(t.accent, fa.ICON_CLOCK_O .. clockStr)

    imgui.Spacing()

    local pushed = 0
    if hr_subtab == "ads" then
        imgui.PushStyleColor(imgui.Col.Button, t.accent)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, t.accent)
        pushed = 2
    else
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.14, 0.18, 0.26, 0.85))
        pushed = 1
    end
    if imgui.Button(fa.ICON_BULLHORN .. u8" Реклама##hr_sub_ads", imgui.ImVec2(140, 30)) then
        hr_subtab = "ads"
    end
    if pushed > 0 then imgui.PopStyleColor(pushed) end

    imgui.SameLine()

    pushed = 0
    if hr_subtab == "analytics" then
        imgui.PushStyleColor(imgui.Col.Button, t.accent)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, t.accent)
        pushed = 2
    else
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.14, 0.18, 0.26, 0.85))
        pushed = 1
    end
    if imgui.Button(fa.ICON_PIE_CHART .. u8" Аналитика##hr_sub_analytics", imgui.ImVec2(140, 30)) then
        hr_subtab = "analytics"
    end
    if pushed > 0 then imgui.PopStyleColor(pushed) end

    imgui.Spacing(); imgui.Separator(); imgui.Spacing()

    if hr_subtab == "ads" then
        drawHRAdsTab(t)
    elseif hr_subtab == "messages" then
        drawHRMessagesTab(t)
    else
        drawHRAnalyticsTab(t)
    end
end

-- ============================================================
--  ДОМАШНЯЯ СТРАНИЦА : ПЛИТКИ С GLASSMORPHISM И АНИМАЦИЯМИ
-- ============================================================
local home_tiles_anim = { 0.0, 0.0, 0.0, 0.0 }
home_tiles_def = {
    {
        id = "home_actor",
        icon = fa.ICON_USER,
        title = u8"Актёр",
        tab = "roles",
        tabTitle = u8"Актёр",
        color = imgui.ImVec4(0.20, 0.46, 0.76, 1.0), -- Solid Sapphire Blue
    },
    {
        id = "home_photo",
        icon = fa.ICON_DESKTOP,
        title = u8"Фотограф",
        tab = "photographer",
        tabTitle = u8"Фотограф",
        color = imgui.ImVec4(0.18, 0.58, 0.64, 1.0), -- Solid Turquoise / Teal
    },
    {
        id = "home_tracker",
        icon = fa.ICON_GAVEL,
        title = u8"Кураторы",
        tab = "tracker",
        tabTitle = u8"Кураторы",
        color = imgui.ImVec4(0.78, 0.22, 0.24, 1.0), -- Solid Ruby / Coral Red
    },
    {
        id = "home_hr",
        icon = fa.ICON_BULLHORN,
        title = u8"Реклама",
        tab = "hr",
        tabTitle = u8"Реклама",
        color = imgui.ImVec4(0.80, 0.56, 0.18, 1.0), -- Solid Amber / Gold
    },
}

local function drawHomeTab(t)
    local avail = imgui.GetContentRegionAvail()
    local centerX = avail.x / 2
    local tint = imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.12)

    imgui.Dummy(imgui.ImVec2(1, 15))

    -- ---------- ЛОГОТИП И ОРЕОЛ ----------
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
    else
        imgui.SetCursorPos(imgui.ImVec2(centerX - 16, haloY + 45))
        imgui.TextColored(t.accent, fa.ICON_USER)
    end

    imgui.SetCursorPosY(haloY + haloSize)
    imgui.Dummy(imgui.ImVec2(1, 8))

    -- ---------- ЗАГОЛОВОК ----------
    if arial_font then imgui.PushFont(arial_font) end
    centeredLabel("home_title", u8"Trinity Roleplay Community Manager", avail.x, 30, t.accent)
    if arial_font then imgui.PopFont() end

    -- ---------- ЛИНИЯ ПОД ЗАГОЛОВКОМ ----------
    imgui.Dummy(imgui.ImVec2(1, 4))
    local underlineW = 220
    imgui.SetCursorPosX(centerX - underlineW / 2)
    imgui.PushStyleColor(imgui.Col.ChildWindowBg, t.accent)
    imgui.BeginChild("HomeTitleUnderline", imgui.ImVec2(underlineW, 3), false)
    imgui.EndChild()
    imgui.PopStyleColor()

    imgui.Dummy(imgui.ImVec2(1, 8))

    local ok, myId = sampGetPlayerIdByCharHandle(playerPed)
    local nickname = (ok and myId and myId >= 0) and sampGetPlayerNickname(myId) or "Игрок"

    if arial_font_small then imgui.PushFont(arial_font_small) end
    centeredLabel("home_welcome", u8"Добро пожаловать, " .. nickname, avail.x, 20, t.textDim)
    if arial_font_small then imgui.PopFont() end

    imgui.Dummy(imgui.ImVec2(1, 20))

    -- ---------- ПЛИТКИ: СПЛОШНОЙ ЦВЕТ + АНИМАЦИИ (БЕЗ ОБВОДКИ) ----------
    local tileW, tileH = 160, 90
    local gap = 20
    local totalW = tileW * 4 + gap * 3
    imgui.SetCursorPosX(centerX - totalW / 2)

    local dl = imgui.GetWindowDrawList()
    local dt = imgui.GetIO().DeltaTime
    if dt <= 0 or dt > 0.1 then dt = 0.016 end

    for i, tile in ipairs(home_tiles_def) do
        if i > 1 then imgui.SameLine(0, gap) end

        local p = imgui.GetCursorScreenPos()
        imgui.InvisibleButton("##" .. tile.id, imgui.ImVec2(tileW, tileH))
        local isHovered = imgui.IsItemHovered()
        local isActive  = imgui.IsItemActive()

        if imgui.IsItemClicked(0) then
            openTab(tile.tab, tile.tabTitle)
        end

        -- Плавная LERP-анимация (0.0 -> 1.0)
        local target = isHovered and 1.0 or 0.0
        home_tiles_anim[i] = home_tiles_anim[i] + (target - home_tiles_anim[i]) * math.min(1.0, dt * 12.0)
        local a = home_tiles_anim[i]

        -- Масштабирование и подъём плитки
        local expand = a * 4.5
        if isActive then expand = expand - 2.0 end
        local liftY = a * 3.5

        local p_min = imgui.ImVec2(p.x - expand, p.y - expand - liftY)
        local p_max = imgui.ImVec2(p.x + tileW + expand, p.y + tileH + expand - liftY)
        local rounding = 12.0
        local cardCenterX = (p_min.x + p_max.x) * 0.5
        local col = tile.color

        -- 1. Мягкая цветная тень при наведении (Ambient Glow)
        if a > 0.01 then
            local bloomCol = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(col.x, col.y, col.z, a * 0.40))
            dl:AddRectFilled(
                imgui.ImVec2(p_min.x - 5.0 * a, p_min.y - 5.0 * a),
                imgui.ImVec2(p_max.x + 5.0 * a, p_max.y + 5.0 * a),
                bloomCol, rounding + 4.0
            )
        end

        -- 2. Чистый сплошной цвет плитки (БЕЗ белой обводки)
        local hoverBoost = a * 0.08
        local bgR = math.min(1.0, col.x + hoverBoost)
        local bgG = math.min(1.0, col.y + hoverBoost)
        local bgB = math.min(1.0, col.z + hoverBoost)
        local solidBgCol = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(bgR, bgG, bgB, 1.0))
        dl:AddRectFilled(p_min, p_max, solidBgCol, rounding)

        -- 3. Контрастная тёмная круглая плашка под иконку
        local badgeCenterY = p_min.y + 30.0 - a * 2.0
        local badgeR = 17.0 + a * 1.5
        local badgeBgCol = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.0, 0.0, 0.0, 0.20 + a * 0.10))
        dl:AddCircleFilled(imgui.ImVec2(cardCenterX, badgeCenterY), badgeR, badgeBgCol, 24)

        -- Иконка (FontAwesome)
        local iconSize = imgui.CalcTextSize(tile.icon)
        local iconCol = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1.0, 1.0, 1.0, 0.95))
        dl:AddText(
            imgui.ImVec2(cardCenterX - iconSize.x * 0.5, badgeCenterY - iconSize.y * 0.5),
            iconCol, tile.icon
        )

        -- 4. Текст названия роли
        local titleY = p_min.y + 58.0
        if arial_font_small then imgui.PushFont(arial_font_small) end
        local titleSize = imgui.CalcTextSize(tile.title)
        local titleCol = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1.0, 1.0, 1.0, 0.98))
        dl:AddText(
            imgui.ImVec2(cardCenterX - titleSize.x * 0.5, titleY),
            titleCol, tile.title
        )
        if arial_font_small then imgui.PopFont() end
    end

    imgui.Dummy(imgui.ImVec2(1, 16))

    local eventBarWidth = math.min(avail.x - 80, 520)
    imgui.SetCursorPosX(centerX - eventBarWidth / 2)
    imgui.BeginChild("HomeUpcomingEvent", imgui.ImVec2(eventBarWidth, 50), true)
        imgui.SetCursorPos(imgui.ImVec2(16, 14))
        imgui.TextColored(t.accent, fa.ICON_STAR .. u8" Ближайший ивент:")
        imgui.SameLine(0, 6)
        imgui.Text(upcoming_event_name .. u8"  |  Время: " .. upcoming_event_time)
    imgui.EndChild()
end

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
do
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
local color_list = { u8"Нет" }
for i = 0, 99 do
    color_list[i+2] = colorNames[i]
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
    u8"43 - Фотоаппарат", u8"44 - ПНВ", u8"45 - Тепловизор", u8"46 - Парашют",
    u8"Нет"
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
        cfg.roles["role" .. i .. "_armor"]  = r.armor and "1" or "0"
    end
    inicfg.save(cfg, ROLES_PATH)
    rolesIni = cfg
end

local function addRoleTemplate(nameUtf8, skinId, weaponLabelUtf8, colorId, armor)
    customRoleTemplates[#customRoleTemplates + 1] = {
        name = nameUtf8, skinId = skinId, weaponLabel = weaponLabelUtf8, colorId = colorId, armor = armor or false
    }
    saveRoleTemplates()
end

local function deleteRoleTemplate(idx)
    table.remove(customRoleTemplates, idx)
    saveRoleTemplates()
end

-- загружаем сохранённые кастомные шаблоны при старте
do
    local rolesCount = tonumber(rolesIni.roles.count) or 0
    for i = 1, rolesCount do
        local nm = rolesIni.roles["role" .. i .. "_name"]
        local sk = tonumber(rolesIni.roles["role" .. i .. "_skin"])
        local wp = rolesIni.roles["role" .. i .. "_weapon"]
        local cl = tonumber(rolesIni.roles["role" .. i .. "_color"])
        local ar = rolesIni.roles["role" .. i .. "_armor"] == "1"
        if nm and sk and wp and cl then
            customRoleTemplates[#customRoleTemplates + 1] = {
                name = u8(nm), skinId = sk, weaponLabel = u8(wp), colorId = cl, armor = ar
            }
        end
    end
end

-- ============================================================
--  Шаблоны ролей (подгружаются с GitHub)
-- ============================================================
local ROLES_GITHUB_URL = "https://raw.githubusercontent.com/squaliee/TRPcomm-Manager-Updates/main/actor-roles.json"

builtinRoleTemplates = {}
builtin_roles_loading = false

local function fetchBuiltinRoleTemplates()
    builtin_roles_loading = true
    performHttpGet(ROLES_GITHUB_URL, { timeout = 15 }, function(response)
        builtin_roles_loading = false
        if not response or response.status_code ~= 200 then return end

        local ok_json, data = pcall(cjson.decode, response.text)
        if not ok_json or not data then return end

        local parsed = {}
        for _, item in ipairs(data) do
            if item.name and item.skinId and item.weaponLabel and item.colorId ~= nil then
                parsed[#parsed + 1] = {
                    name        = item.name,
                    skinId      = item.skinId,
                    weaponLabel = item.weaponLabel,
                    colorId     = item.colorId,
                    armor       = item.armor or false,
                }
            end
        end

        if #parsed > 0 then
            builtinRoleTemplates = parsed
        end
    end, function(err)
        builtin_roles_loading = false
    end)
end

local function sendRoleTemplate(tmpl)
    local ok, myId = sampGetPlayerIdByCharHandle(playerPed)
    if not ok then
        sampAddChatMessage(u8"{FF6B6B}[TRPcomm] Не удалось определить свой ID.", -1)
        return
    end
    local skinText   = (tmpl.skinId and tmpl.skinId >= 0) and tostring(tmpl.skinId) or "нет"
    local weaponName = tmpl.weaponLabel:match("%- (.+)$") or tmpl.weaponLabel
    local weaponText = u8:decode(weaponName)
    local colorText  = (tmpl.colorId and tmpl.colorId >= 0) and tostring(tmpl.colorId) or "нет"
    local armorText  = tmpl.armor and "да" or "нет"
    local msg = string.format("/rc Мой ID: %d | Скин: %s | Оружие: %s | Клист: %s | Бронежилет: %s",
        myId, skinText, weaponText, colorText, armorText)
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
    imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.65))
    if imgui.BeginPopupModal("Каталог скинов##skin_catalog_popup", nil, imgui.WindowFlags.AlwaysAutoResize + imgui.WindowFlags.NoTitleBar) then
        imgui.TextColored(t.accent, fa.ICON_USERS .. u8"  КАТАЛОГ СКИНОВ GTA:SA")
        imgui.Separator()
        imgui.Spacing()

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

        if imgui.Button(fa.ICON_ARROW_LEFT .. u8" Назад##catalog_prev", imgui.ImVec2(105, 26)) then
            if roleCatalogPage > 0 then roleCatalogPage = roleCatalogPage - 1 end
        end
        imgui.SameLine()
        imgui.TextColored(t.textDim, u8"  Страница " .. (roleCatalogPage + 1) .. u8" из " .. totalPages .. "  ")
        imgui.SameLine()
        if imgui.Button(u8"Вперёд " .. fa.ICON_ARROW_RIGHT .. "##catalog_next", imgui.ImVec2(105, 26)) then
            if roleCatalogPage < totalPages - 1 then roleCatalogPage = roleCatalogPage + 1 end
        end

        imgui.Spacing()
        if imgui.Button(fa.ICON_TIMES .. u8"  Закрыть##close_catalog", imgui.ImVec2(-1, 28)) then
            imgui.CloseCurrentPopup()
        end

        imgui.EndPopup()
    end
    imgui.PopStyleColor()
end
-- ------------------------------------------------------------
-- отрисовка вкладки "Роли"
-- ------------------------------------------------------------
roles_new_name = imgui.ImBuffer("", 64)
roles_new_no_skin = imgui.ImBool(false)
roles_new_weapon_combo = imgui.ImInt(0)
roles_new_color_combo = imgui.ImInt(0)
roles_new_armor = imgui.ImBool(false)
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
            local colorLabel = (tmpl.colorId == -1) and u8"Нет" or (colorNames[tmpl.colorId] or "")
            local colorName  = colorLabel:match("%- (.+)$") or colorLabel
            local armorLabel = tmpl.armor and u8"да" or u8"нет"
            imgui.TextColored(t.textDim, u8"Оружие: " .. weaponName .. u8"  |  Цвет: " .. colorName .. u8"  |  Броня: " .. armorLabel)
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
            roles_new_no_skin.v = (tmpl.skinId == -1)
            roleCreateSkinId.v = (tmpl.skinId == -1) and 0 or tmpl.skinId
            roles_new_weapon_combo.v = 0
            for i, w in ipairs(weapon_list) do
                if w == tmpl.weaponLabel then
                    roles_new_weapon_combo.v = i - 1
                    break
                end
            end
            roles_new_color_combo.v = (tmpl.colorId == -1) and 0 or (tmpl.colorId + 1)
            roles_new_armor.v = tmpl.armor or false
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
    imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.65))
    if imgui.BeginPopupModal(popupTitle .. "###add_role_popup", nil, imgui.WindowFlags.AlwaysAutoResize + imgui.WindowFlags.NoTitleBar) then
        imgui.TextColored(t.accent, (roles_edit_idx and fa.ICON_PENCIL or fa.ICON_PLUS) .. "  " .. popupTitle)
        imgui.Separator()
        imgui.Spacing()

        imgui.TextColored(t.textDim, fa.ICON_TAG .. u8"  Название роли:")
        imgui.PushItemWidth(280)
        imgui.InputText("##new_role_name", roles_new_name)
        imgui.PopItemWidth()

        imgui.Spacing()
        imgui.TextColored(t.textDim, fa.ICON_USER .. u8"  ID скина:")
        imgui.PushItemWidth(110)
        imgui.InputInt("##new_role_skin_id", roleCreateSkinId, 0, 0)
        imgui.PopItemWidth()
        imgui.SameLine()
        if imgui.Button(fa.ICON_TH .. u8" Каталог##open_skin_catalog", imgui.ImVec2(115, 24)) then
            roleCatalogPage = 0
            imgui.OpenPopup("Каталог скинов##skin_catalog_popup")
        end
        if not roles_new_no_skin.v then
            local previewTex = loadSkinTexture(roleCreateSkinId.v)
            if previewTex then
                imgui.SameLine()
                imgui.Image(previewTex, imgui.ImVec2(28, 28))
            end
        end
        imgui.Checkbox(u8"Без скина##new_role_no_skin", roles_new_no_skin)

        imgui.Spacing()
        imgui.TextColored(t.textDim, fa.ICON_CROSSHAIRS .. u8"  Оружие:")
        imgui.PushItemWidth(280)
        imgui.Combo("##new_role_weapon", roles_new_weapon_combo, weapon_list)
        imgui.PopItemWidth()

        imgui.Spacing()
        imgui.TextColored(t.textDim, fa.ICON_PAINT_BRUSH .. u8"  Клист (цвет ника):")
        imgui.PushItemWidth(280)
        imgui.Combo("##new_role_color", roles_new_color_combo, color_list)
        imgui.PopItemWidth()

        imgui.Spacing()
        imgui.Checkbox(u8"Бронежилет##new_role_armor", roles_new_armor)

        imgui.Spacing(); imgui.Separator(); imgui.Spacing()

        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.20, 0.62, 0.35, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.28, 0.72, 0.44, 1.0))
        if imgui.Button(fa.ICON_CHECK .. u8"  Сохранить##save_new_role", imgui.ImVec2(145, 30)) then
            if roles_new_name.v ~= "" then
                local finalSkinId  = roles_new_no_skin.v and -1 or roleCreateSkinId.v
                local finalColorId = (roles_new_color_combo.v == 0) and -1 or (roles_new_color_combo.v - 1)
                local finalArmor   = roles_new_armor.v
                if roles_edit_idx then
                    local tmpl = customRoleTemplates[roles_edit_idx]
                    tmpl.name        = roles_new_name.v
                    tmpl.skinId      = finalSkinId
                    tmpl.weaponLabel = weapon_list[roles_new_weapon_combo.v + 1]
                    tmpl.colorId     = finalColorId
                    tmpl.armor       = finalArmor
                    saveRoleTemplates()
                    roles_edit_idx = nil
                else
                    addRoleTemplate(
                        roles_new_name.v,
                        finalSkinId,
                        weapon_list[roles_new_weapon_combo.v + 1],
                        finalColorId,
                        finalArmor
                    )
                end
                roles_new_name.v = ""
                imgui.CloseCurrentPopup()
            end
        end
        imgui.PopStyleColor(2)

        imgui.SameLine(0, 8)
        if imgui.Button(fa.ICON_TIMES .. u8"  Закрыть##cancel_new_role", imgui.ImVec2(125, 30)) then
            roles_edit_idx = nil
            imgui.CloseCurrentPopup()
        end

        drawSkinCatalogPopup(t)

        imgui.EndPopup()
    end
    imgui.PopStyleColor()
end
local function drawRolesTab(t)
    imgui.TextColored(t.accent, u8"Роли")
    imgui.SameLine(imgui.GetWindowWidth() - 150)
        if imgui.Button(fa.ICON_PLUS .. u8"  Добавить##add_role", imgui.ImVec2(140, 26)) then
        roles_edit_idx = nil
        roles_new_name.v = ""
        roleCreateSkinId.v = 0
        roles_new_no_skin.v = false
        roles_new_weapon_combo.v = 0
        roles_new_color_combo.v = 0
        roles_new_armor.v = false
        imgui.OpenPopup("###add_role_popup")
    end
    imgui.Separator()
    imgui.Spacing()

    imgui.TextColored(t.accent, u8"Готовые шаблоны")
    imgui.SameLine()
    if builtin_roles_loading then
        imgui.TextColored(t.textDim, u8"обновляю...")
    else
        if imgui.Button(fa.ICON_RANDOM .. "##refresh_builtin_roles", imgui.ImVec2(28, 22)) then
            fetchBuiltinRoleTemplates()
        end
    end
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
    local avail = imgui.GetContentRegionAvail()
    local gap = 12
    local colW = math.floor((avail.x - gap) * 0.5)
    local cardBg = imgui.ImVec4(t.windowBg.x, t.windowBg.y, t.windowBg.z, 0.80)
    local cardBorder = imgui.ImVec4(t.border.x, t.border.y, t.border.z, 0.45)
    local pillDefaultBg = imgui.ImVec4(t.frameBg.x, t.frameBg.y, t.frameBg.z, 0.90)
    local rowBg = imgui.ImVec4(t.frameBg.x, t.frameBg.y, t.frameBg.z, 0.45)

    local function drawCardHeader(icon, title)
        imgui.TextColored(t.accent, icon .. "  " .. title)
        imgui.Separator()
        imgui.Spacing()
    end

    local function drawToggleRow(id, icon, label, boolVar, onToggle)
        local dl = imgui.GetWindowDrawList()
        local p = imgui.GetCursorScreenPos()
        local w = imgui.GetContentRegionAvailWidth()
        local h = 28
        imgui.InvisibleButton("##tgl_" .. id, imgui.ImVec2(w, h))
        local hov = imgui.IsItemHovered()
        if imgui.IsItemClicked(0) then
            boolVar.v = not boolVar.v
            if onToggle then onToggle(boolVar.v) end
        end

        local bgAlpha = hov and 0.75 or (boolVar.v and 0.50 or 0.30)
        local bgCol = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.frameBg.x, t.frameBg.y, t.frameBg.z, bgAlpha))
        dl:AddRectFilled(p, imgui.ImVec2(p.x + w, p.y + h), bgCol, 6.0)
        if boolVar.v then
            local barCol = imgui.ColorConvertFloat4ToU32(t.accent)
            dl:AddRectFilled(p, imgui.ImVec2(p.x + 3, p.y + h), barCol, 3.0)
        end

        local icCol = imgui.ColorConvertFloat4ToU32(boolVar.v and t.accent or t.textDim)
        local txtCol = imgui.ColorConvertFloat4ToU32(boolVar.v and t.text or t.textDim)
        dl:AddText(imgui.ImVec2(p.x + 12, p.y + 6), icCol, icon)
        dl:AddText(imgui.ImVec2(p.x + 34, p.y + 6), txtCol, label)

        -- Стилизованный тумблер (pill switch) справа
        local swW, swH = 34, 18
        local swX = p.x + w - swW - 10
        local swY = p.y + (h - swH) * 0.5
        local swBg = boolVar.v
            and imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.90))
            or imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.22, 0.25, 0.30, 0.90))
        dl:AddRectFilled(imgui.ImVec2(swX, swY), imgui.ImVec2(swX + swW, swY + swH), swBg, swH * 0.5)
        local knobX = boolVar.v and (swX + swW - swH * 0.5) or (swX + swH * 0.5)
        local knobY = swY + swH * 0.5
        dl:AddCircleFilled(imgui.ImVec2(knobX, knobY), (swH * 0.5) - 2.5, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1, 1, 1, 0.95)), 16)
    end

    -- ============================================================
    --  ЛЕВАЯ КОЛОНКА (КЛАВИШИ, ТЕМА, РАДИОСВЯЗЬ)
    -- ============================================================
    imgui.BeginGroup()

        -- 1. Карточка горячих клавиш (компактная, в одну строку на бинд)
        imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
        imgui.PushStyleColor(imgui.Col.Border, cardBorder)
        imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, 8.0)
        imgui.BeginChild("card_hotkeys", imgui.ImVec2(colW, 114), true)

            drawCardHeader(fa.ICON_KEYBOARD_O, u8"Управление и клавиши")

            -- Главное меню
            imgui.AlignTextToFramePadding()
            imgui.TextColored(t.text, u8"Главное меню:")
            imgui.SameLine(235)

            local isHk1Wait = waiting_for_key
            local hk1Col = isHk1Wait and imgui.ImVec4(0.95, 0.65, 0.20, 1.0) or t.accent
            local hk1Bg = isHk1Wait and imgui.ImVec4(0.35, 0.25, 0.10, 0.85) or pillDefaultBg
            local pillW = math.max(95, colW - 385)

            imgui.PushStyleColor(imgui.Col.Button, hk1Bg)
            imgui.PushStyleColor(imgui.Col.Text, hk1Col)
            imgui.Button((isHk1Wait and (fa.ICON_SPINNER .. u8" Клавиша...") or hotkey_display.v) .. "##hk1_disp", imgui.ImVec2(pillW, 24))
            imgui.PopStyleColor(2)

            imgui.SameLine(0, 4)
            if isHk1Wait then
                if imgui.Button(fa.ICON_TIMES .. u8" Отмена##hk1_cancel", imgui.ImVec2(126, 24)) then
                    waiting_for_key = false
                end
            else
                if imgui.Button(fa.ICON_PENCIL .. u8" Задать##hk1_change", imgui.ImVec2(72, 24)) then
                    waiting_for_key2 = false
                    waiting_for_key = true
                end
                imgui.SameLine(0, 4)
                if imgui.Button(fa.ICON_UNDO .. "##hk1_reset", imgui.ImVec2(50, 24)) then
                    hotkey_alt.v   = true
                    hotkey_ctrl.v  = false
                    hotkey_shift.v = false
                    hotkey_key.v   = 0x50
                    updateHotkeyDisplay()
                    saveSettings()
                end
                if imgui.IsItemHovered() then imgui.SetTooltip(u8"Сбросить клавишу меню на Alt + P") end
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

            imgui.Spacing()

            -- Радио + Мегафон
            imgui.AlignTextToFramePadding()
            imgui.TextColored(t.text, u8"Телепорт + подключение к рации:")
            imgui.SameLine(235)

            local isHk2Wait = waiting_for_key2
            local hk2Text = hotkey2_key.v == 0 and u8"Не задано" or hotkey2_display.v
            local hk2Col = isHk2Wait and imgui.ImVec4(0.95, 0.65, 0.20, 1.0) or (hotkey2_key.v == 0 and t.textDim or t.accent)
            local hk2Bg = isHk2Wait and imgui.ImVec4(0.35, 0.25, 0.10, 0.85) or pillDefaultBg

            imgui.PushStyleColor(imgui.Col.Button, hk2Bg)
            imgui.PushStyleColor(imgui.Col.Text, hk2Col)
            imgui.Button((isHk2Wait and (fa.ICON_SPINNER .. u8" Клавиша...") or hk2Text) .. "##hk2_disp", imgui.ImVec2(pillW, 24))
            imgui.PopStyleColor(2)

            imgui.SameLine(0, 4)
            if isHk2Wait then
                if imgui.Button(fa.ICON_TIMES .. u8" Отмена##hk2_cancel", imgui.ImVec2(126, 24)) then
                    waiting_for_key2 = false
                end
            else
                if imgui.Button(fa.ICON_PENCIL .. u8" Задать##hk2_change", imgui.ImVec2(72, 24)) then
                    waiting_for_key = false
                    waiting_for_key2 = true
                end
                imgui.SameLine(0, 4)
                if imgui.Button(fa.ICON_TRASH .. "##hk2_clear", imgui.ImVec2(50, 24)) then
                    hotkey2_alt.v   = false
                    hotkey2_ctrl.v  = false
                    hotkey2_shift.v = false
                    hotkey2_key.v   = 0
                    updateHotkey2Display()
                    saveSettings()
                end
                if imgui.IsItemHovered() then imgui.SetTooltip(u8"Очистить горячую клавишу радио") end
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

        imgui.EndChild()
        imgui.PopStyleVar()
        imgui.PopStyleColor(2)

        imgui.Spacing()

        -- 2. Карточка оформления интерфейса (компактная + быстрые цветовые точки тем)
        imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
        imgui.PushStyleColor(imgui.Col.Border, cardBorder)
        imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, 8.0)
        imgui.BeginChild("card_theme", imgui.ImVec2(colW, 134), true)

            drawCardHeader(fa.ICON_PAINT_BRUSH, u8"Оформление интерфейса")

            imgui.AlignTextToFramePadding()
            imgui.TextColored(t.textDim, u8"Тема:")
            imgui.SameLine(65)

            local theme_names = {}
            for _, th in ipairs(themes) do theme_names[#theme_names + 1] = th.name end
            imgui.PushItemWidth(-1)
            if imgui.Combo("##theme_select", selected_theme_combo, theme_names) then
                currentThemeIdx = selected_theme_combo.v + 1
                saveSettings()
            end
            imgui.PopItemWidth()

            imgui.Spacing()
            -- Быстрая палитра тем в два ряда по 16 цветов
            local dl = imgui.GetWindowDrawList()
            local availW = imgui.GetContentRegionAvailWidth()
            local perRow = 16
            local dotGap = 6
            local dotW = math.floor((availW - (perRow - 1) * dotGap) / perRow)
            local dotH = 18
            for idx, th in ipairs(themes) do
                local colIdx = (idx - 1) % perRow
                if colIdx > 0 then
                    imgui.SameLine(0, dotGap)
                elseif idx > 1 then
                    imgui.Dummy(imgui.ImVec2(1, 2))
                end
                local p = imgui.GetCursorScreenPos()
                imgui.InvisibleButton("##th_dot_" .. idx, imgui.ImVec2(dotW, dotH))
                local hov = imgui.IsItemHovered()
                if imgui.IsItemClicked(0) then
                    currentThemeIdx = idx
                    selected_theme_combo.v = idx - 1
                    saveSettings()
                end
                if hov then imgui.SetTooltip(th.name) end

                local isSel = (idx == currentThemeIdx)
                local colU32 = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(th.accent.x, th.accent.y, th.accent.z, isSel and 1.0 or (hov and 0.85 or 0.55)))
                dl:AddRectFilled(p, imgui.ImVec2(p.x + dotW, p.y + dotH), colU32, 4.0)
                if isSel then
                    local brdU32 = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1, 1, 1, 0.95))
                    dl:AddRect(p, imgui.ImVec2(p.x + dotW, p.y + dotH), brdU32, 4.0)
                end
            end

        imgui.EndChild()
        imgui.PopStyleVar()
        imgui.PopStyleColor(2)

        imgui.Spacing()

        -- 3. Карточка радиосвязи и служебных доступов (горизонтальные поля ввода)
        local leftRemH = math.max(160, imgui.GetContentRegionAvail().y)
        imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
        imgui.PushStyleColor(imgui.Col.Border, cardBorder)
        imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, 8.0)
        imgui.BeginChild("card_radio", imgui.ImVec2(colW, leftRemH), true)

            drawCardHeader(fa.ICON_RSS, u8"Радиосвязь и доступы")

            local labelColW = 195
            imgui.AlignTextToFramePadding()
            imgui.TextColored(t.textDim, fa.ICON_VOLUME_UP .. u8"  Частота рации:")
            imgui.SameLine(labelColW)
            imgui.PushItemWidth(-1)
            if imgui.InputText("##radio_freq", radio_freq) then
                saveSettings()
            end
            imgui.PopItemWidth()

            imgui.Spacing()
            imgui.AlignTextToFramePadding()
            imgui.TextColored(t.textDim, fa.ICON_LOCK .. u8"  Пароль от волны:")
            imgui.SameLine(labelColW)
            imgui.PushItemWidth(-1)
            if imgui.InputText("##radio_pass", radio_pass) then
                saveSettings()
            end
            imgui.PopItemWidth()

            imgui.Spacing()
            imgui.AlignTextToFramePadding()
            imgui.TextColored(t.textDim, fa.ICON_MAP_MARKER .. u8"  Пароль телепорта:")
            imgui.SameLine(labelColW)
            imgui.PushItemWidth(-1)
            if imgui.InputText("##teleport_pass", teleport_pass) then
                saveSettings()
            end
            imgui.PopItemWidth()

            imgui.Spacing()
            imgui.TextColored(imgui.ImVec4(t.textDim.x, t.textDim.y, t.textDim.z, 0.65),
                u8"Автоматически используются для подключения к волне и телепорта на ивенты.")

        imgui.EndChild()
        imgui.PopStyleVar()
        imgui.PopStyleColor(2)

    imgui.EndGroup()

    -- ============================================================
    --  ПРАВАЯ КОЛОНКА (ОПТИМИЗАЦИЯ, МЕССЕНДЖЕР, АДМИН-ТОКЕН)
    -- ============================================================
    imgui.SameLine(0, gap)
    imgui.BeginGroup()

        local showSmsCard = hasAccess("advertising")
        local showGhCard  = isAdManager()

        -- 4. Карточка игрового процесса и оптимизации (стильные строки-тумблеры)
        local tweaksH = 214
        if not showSmsCard and not showGhCard then
            tweaksH = math.max(214, imgui.GetContentRegionAvail().y)
        end

        imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
        imgui.PushStyleColor(imgui.Col.Border, cardBorder)
        imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, 8.0)
        imgui.BeginChild("card_tweaks", imgui.ImVec2(colW, tweaksH), true)

            drawCardHeader(fa.ICON_SLIDERS, u8"Игровой процесс и оптимизация")

            drawToggleRow("acs_rem", fa.ICON_USERS, u8"Скрыть аксессуары других игроков", acs_rem, function(val)
                saveSettings()
                if val then
                    for k, v in ipairs(getAllChars()) do
                        local res, id = sampGetPlayerIdByCharHandle(v)
                        if v ~= 1 and res and not sampIsPlayerNpc(id) then deleteAllAcs(id) end
                    end
                else
                    sampAddChatMessage('{5B85C4}[TRPcomm] {FFFFFF}Аксессуары снова отображаются (после рестрима)', -1)
                end
            end)

            imgui.Dummy(imgui.ImVec2(1, 2))
            drawToggleRow("acs_rem_me", fa.ICON_USER, u8"Скрыть аксессуары на своем персонаже", acs_rem_me, function(val)
                saveSettings()
                if val then
                    local res, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
                    if res then deleteAllAcs(id) end
                else
                    sampAddChatMessage('{5B85C4}[TRPcomm] {FFFFFF}Аксессуары вернутся после смены скина или респавна', -1)
                end
            end)

            imgui.Dummy(imgui.ImVec2(1, 2))
            drawToggleRow("rem_armour", fa.ICON_SHIELD, u8"Скрыть бронежилет на персонаже", remove_armour, function()
                saveSettings()
            end)

            imgui.Dummy(imgui.ImVec2(1, 2))
            drawToggleRow("del_td", fa.ICON_GLOBE, u8"Удалить логотип сервера (gta-trinity.com)", delete_textdraw, function()
                saveSettings()
            end)

            imgui.Dummy(imgui.ImVec2(1, 2))
            drawToggleRow("toasts", fa.ICON_BELL, u8"Всплывающие уведомления (Toasts)", notifications_enabled, function()
                saveSettings()
            end)

        imgui.EndChild()
        imgui.PopStyleVar()
        imgui.PopStyleColor(2)

        -- 5. Карточка Мессенджера (доступна сотрудникам Рекламного отдела)
        if showSmsCard then
            imgui.Spacing()
            local smsH = showGhCard and 112 or math.max(112, imgui.GetContentRegionAvail().y)
            imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
            imgui.PushStyleColor(imgui.Col.Border, cardBorder)
            imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, 8.0)
            imgui.BeginChild("card_quicksms", imgui.ImVec2(colW, smsH), true)

                drawCardHeader(fa.ICON_ENVELOPE, u8"Мессенджер (/smss)")

                if qsms and qsms.img then
                    drawToggleRow("qsms_ooc", fa.ICON_COMMENT_O, u8"Отправлять OOC SMS (( текст ))", qsms.img.ooc, function(val)
                        qsms.set.ooc = val
                        qsms.mcfg.save(qsms.set, qsms.filename_set)
                    end)

                    imgui.Dummy(imgui.ImVec2(1, 2))
                    drawToggleRow("qsms_overlay", fa.ICON_WINDOW_MAXIMIZE, u8"Всплывающая панель под чатом (/sms, /t)", qsms.img.show_overlay, function(val)
                        qsms.set.show_chat_overlay = val
                        qsms.mcfg.save(qsms.set, qsms.filename_set)
                    end)
                end

            imgui.EndChild()
            imgui.PopStyleVar()
            imgui.PopStyleColor(2)
        end

        -- 6. Карточка GitHub API (Только руководство)
        if showGhCard then
            imgui.Spacing()
            local ghH = math.max(98, imgui.GetContentRegionAvail().y)
            imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
            imgui.PushStyleColor(imgui.Col.Border, cardBorder)
            imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, 8.0)
            imgui.BeginChild("card_github", imgui.ImVec2(colW, ghH), true)

                drawCardHeader(fa.ICON_GITHUB, u8"GitHub API Token (Руководство)")

                local ghInputW = colW - 155
                imgui.PushItemWidth(math.max(120, ghInputW))
                local inputFlags = github_token_show.v and 0 or (imgui.InputTextFlags.Password or 32768)
                if imgui.InputText("##github_token_field", github_admin_token_buf, inputFlags) then
                    saveSettings()
                end
                imgui.PopItemWidth()

                imgui.SameLine(0, 6)
                local eyeIcon = github_token_show.v and fa.ICON_EYE_SLASH or fa.ICON_EYE
                if imgui.Button(eyeIcon .. "##gh_show_tok", imgui.ImVec2(30, 24)) then
                    github_token_show.v = not github_token_show.v
                end
                if imgui.IsItemHovered() then imgui.SetTooltip(github_token_show.v and u8"Скрыть токен" or u8"Показать токен") end

                imgui.SameLine(0, 6)
                if imgui.Button(fa.ICON_CHECK .. u8" Сохранить##btn_save_ghtoken", imgui.ImVec2(95, 24)) then
                    saveSettings()
                    showToast("GitHub токен сохранен")
                end

                imgui.Spacing()
                imgui.TextColored(imgui.ImVec4(t.textDim.x, t.textDim.y, t.textDim.z, 0.70),
                    u8"Синхронизация глобальных ограничений (доступно руководителям).")

            imgui.EndChild()
            imgui.PopStyleVar()
            imgui.PopStyleColor(2)
        end

    imgui.EndGroup()
end
-- ============================================================
-- Папка со скриншотами SAMP — стандартная папка "Документы" пользователя
local SCREENS_DIR = (os.getenv("USERPROFILE") or "") .. "\\Documents\\GTA San Andreas User Files\\SAMP\\screens\\"

GALLERY_SCAN_LIMIT = 60 -- сколько последних файлов вообще ищем
GALLERY_PER_PAGE   = 9  -- 3x3 на странице
GALLERY_MAX_SELECT = 10

gallery_thumbnails    = {}
gallery_full_textures = {}
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
    gallery_thumbnails    = {}
    gallery_full_textures = {}
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

local d3dx9_ok, d3dx9 = pcall(ffi.load, "d3dx9_43.dll")
if not d3dx9_ok then d3dx9 = nil end

-- Загрузка миниатюры скриншота в низком качестве (быстро и легко для памяти)
local function loadGalleryThumbnail(filename)
    if gallery_thumbnails[filename] ~= nil then
        return gallery_thumbnails[filename] or nil
    end
    local path = SCREENS_DIR .. filename
    if doesFileExist(path) then
        local tex = nil
        -- 1. Создаём сжатую низкокачественную текстуру через DirectX 9 D3DX
        if d3dx9 and d3dx9.D3DXCreateTextureFromFileExA and getD3DDevicePtr then
            local pDev = getD3DDevicePtr()
            if pDev then
                local ppTex = ffi.new("LPDIRECT3DTEXTURE9[1]")
                -- 240x135 - низкое разрешение, D3DX_FILTER_NONE (1) для быстрого сжатия и низкого качества
                local hr = d3dx9.D3DXCreateTextureFromFileExA(
                    ffi.cast("LPDIRECT3DDEVICE9", pDev),
                    path,
                    240, 135,
                    1, 0, 0, 1, 1, 0, 0,
                    nil, nil, ppTex
                )
                if hr == 0 and ppTex[0] ~= nil then
                    local addr = tonumber(ffi.cast("uintptr_t", ppTex[0]))
                    tex = imgui.GetTextureFromAddress(addr)
                end
            end
        end

        -- 2. Если D3DX недоступен, fallback на обычный загрузчик
        if not tex then
            tex = imgui.CreateTextureFromFile(path)
        end

        gallery_thumbnails[filename] = tex
        return tex
    end
    gallery_thumbnails[filename] = false
    return nil
end

-- Загрузка оригинального скриншота в 100% максимальном качестве (для полного просмотра)
local function loadGalleryFull(filename)
    if gallery_full_textures[filename] ~= nil then
        return gallery_full_textures[filename] or nil
    end
    local path = SCREENS_DIR .. filename
    if doesFileExist(path) then
        local tex = imgui.CreateTextureFromFile(path)
        gallery_full_textures[filename] = tex
        return tex
    end
    gallery_full_textures[filename] = false
    return nil
end

-- Предзагрузка миниатюр текущей страницы (легкие текстуры)
local function loadGalleryPage(page)
    if gallery_loaded_pages[page] then return end
    gallery_loaded_pages[page] = true
    local startIdx = (page - 1) * GALLERY_PER_PAGE + 1
    local endIdx   = math.min(startIdx + GALLERY_PER_PAGE - 1, #gallery_files)
    lua_thread.create(function()
        for i = startIdx, endIdx do
            loadGalleryThumbnail(gallery_files[i])
            wait(0)
        end
    end)
end

-- ---------- ОКНО "ОТПРАВИТЬ ОТЧЕТ В ТЕЛЕГРАМ" ----------
gallery_send_form_open = false
gallery_send_event_name = imgui.ImBuffer("", 64)
gallery_pending_files = {}

local function sendGalleryReport(filesToSend, eventNameUtf8)

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
            showToast('Готово: отправлено ' .. #paths .. ' скрин(ов) одним альбомом.')
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
    local bgFlags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoSavedSettings

    -- 1. Полноэкранный затемняющий фон
    imgui.SetNextWindowPos(imgui.ImVec2(0, 0), imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(sw, sh), imgui.Cond.Always)
    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.02, 0.04, 0.07, 0.74))
    imgui.PushStyleVar(imgui.StyleVar.WindowRounding, 0.0)
    imgui.Begin("##gal_send_backdrop", nil, bgFlags)
    if imgui.IsWindowHovered() and imgui.IsMouseClicked(0) then
        gallery_send_form_open = false
    end
    imgui.End()
    imgui.PopStyleVar()
    imgui.PopStyleColor()

    -- 2. Модальное окно без крестика и стандартного заголовка
    local modalW, modalH = 440, 215
    imgui.SetNextWindowSize(imgui.ImVec2(modalW, modalH), imgui.Cond.Always)
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))

    pushThemeColors()
    pushThemeRounding()
    imgui.PushStyleVar(imgui.StyleVar.WindowPadding, imgui.ImVec2(18, 14))
    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(t.windowBg.x, t.windowBg.y, t.windowBg.z, 0.99))
    imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.65))

    imgui.Begin("##gallery_send_form_modal", nil, imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoScrollbar)

        imgui.TextColored(t.accent, fa.ICON_PAPER_PLANE .. u8"  ОТПРАВКА ФОТООТЧЁТА")
        imgui.Separator()
        imgui.Spacing()

        imgui.TextColored(t.textDim, fa.ICON_TAG .. u8"  Название ивента:")
        imgui.PushItemWidth(-1)
        imgui.InputText("##gallery_send_event_name", gallery_send_event_name)
        imgui.PopItemWidth()

        imgui.Spacing()
        imgui.PushStyleColor(imgui.Col.ChildWindowBg, imgui.ImVec4(t.frameBg.x, t.frameBg.y, t.frameBg.z, 0.55))
        imgui.BeginChild("##gal_send_info_pill", imgui.ImVec2(-1, 32), false)
            imgui.SetCursorPos(imgui.ImVec2(10, 7))
            imgui.TextColored(t.textDim, fa.ICON_PICTURE_O .. u8"  Выбрано скриншотов:")
            imgui.SameLine(0, 6)
            imgui.TextColored(t.accent, tostring(#gallery_pending_files) .. u8" шт.")
            imgui.SameLine(230)
            imgui.TextColored(t.textDim, fa.ICON_CLOCK_O .. "  " .. os.date("%d.%m.%Y %H:%M"))
        imgui.EndChild()
        imgui.PopStyleColor()

        imgui.Spacing(); imgui.Separator(); imgui.Spacing()

        local btnW = math.floor((modalW - 36 - 8) * 0.5)
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.20, 0.62, 0.35, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.28, 0.72, 0.44, 1.0))
        if imgui.Button(fa.ICON_CHECK .. u8"  Отправить отчёт##gallery_send_confirm", imgui.ImVec2(btnW + 15, 32)) then
            local nameText = u8:decode(gallery_send_event_name.v)
            local eventNameUtf8 = (nameText == "") and u8"Без названия" or u8(nameText)
            sendGalleryReport(gallery_pending_files, eventNameUtf8)
            gallery_send_event_name.v = ""
            gallery_send_form_open = false
        end
        imgui.PopStyleColor(2)

        imgui.SameLine(0, 8)
        if imgui.Button(fa.ICON_TIMES .. u8"  Закрыть##gallery_send_cancel", imgui.ImVec2(btnW - 15, 32)) then
            gallery_send_form_open = false
        end

    imgui.End()
    imgui.PopStyleColor(2)
    imgui.PopStyleVar()
    imgui.PopStyleVar(THEME_ROUNDING_COUNT)
    imgui.PopStyleColor(THEME_COLOR_COUNT)
end

local function drawGalleryPreview(t)
    if not gallery_preview_open or not gallery_preview_file then return end

    local tex = gallery_full_textures[gallery_preview_file]
    if not tex then
        tex = loadGalleryFull(gallery_preview_file)
    end
    if not tex then
        tex = gallery_thumbnails[gallery_preview_file]
    end
    if not tex then
        gallery_preview_open = false
        return
    end

    local sw, sh = getScreenResolution()
    local bgFlags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoSavedSettings

    -- 1. Полноэкранный затемняющий фон
    imgui.SetNextWindowPos(imgui.ImVec2(0, 0), imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(sw, sh), imgui.Cond.Always)
    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.02, 0.04, 0.07, 0.78))
    imgui.PushStyleVar(imgui.StyleVar.WindowRounding, 0.0)
    imgui.Begin("##gal_prev_backdrop", nil, bgFlags)
    if imgui.IsWindowHovered() and imgui.IsMouseClicked(0) then
        gallery_preview_open = false
    end
    imgui.End()
    imgui.PopStyleVar()
    imgui.PopStyleColor()

    -- 2. Модальное окно просмотра скриншота без крестика
    imgui.SetNextWindowSize(imgui.ImVec2(sw * 0.75, sh * 0.82), imgui.Cond.Always)
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))

    pushThemeColors()
    pushThemeRounding()
    imgui.PushStyleVar(imgui.StyleVar.WindowPadding, imgui.ImVec2(16, 12))
    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(t.windowBg.x, t.windowBg.y, t.windowBg.z, 0.99))
    imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.65))

    imgui.Begin("##gallery_preview_modal", nil, imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar)

        imgui.TextColored(t.accent, fa.ICON_PICTURE_O .. u8"  Просмотр скриншота: ")
        imgui.SameLine(0, 4)
        imgui.TextColored(t.text, u8(gallery_preview_file))
        imgui.Separator()
        imgui.Spacing()

        local avail = imgui.GetContentRegionAvail()
        imgui.Image(tex, imgui.ImVec2(avail.x, avail.y - 40))

        imgui.Spacing()
        if imgui.Button(fa.ICON_TIMES .. u8"  Закрыть окно просмотра##gallery_preview_close", imgui.ImVec2(-1, 32)) then
            gallery_preview_open = false
        end

    imgui.End()
    imgui.PopStyleColor(2)
    imgui.PopStyleVar()
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

local function sampColorToImVec4(argb)
    argb = argb or -1
    if argb < 0 then argb = argb + 0x100000000 end -- на случай знакового int32
    argb = argb % 0x1000000 -- отбрасываем альфа-байт
    local r = math.floor(argb / 0x10000) % 0x100
    local g = math.floor(argb / 0x100) % 0x100
    local b = argb % 0x100
    return imgui.ImVec4(r / 255.0, g / 255.0, b / 255.0, 1.0)
end

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
    local ids = {}
    local inRadCount = 0
    for pid, entry in pairs(tracker_players) do
        ids[#ids + 1] = pid
        if entry.inRadius then inRadCount = inRadCount + 1 end
    end
    table.sort(ids)

    local cardBg = imgui.ImVec4(t.windowBg.x, t.windowBg.y, t.windowBg.z, 0.80)
    local cardBorder = imgui.ImVec4(t.border.x, t.border.y, t.border.z, 0.45)

    -- Панель управления и живых счётчиков
    imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
    imgui.PushStyleColor(imgui.Col.Border, cardBorder)
    imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, 8.0)
    imgui.BeginChild("##tr_ctrl_card", imgui.ImVec2(0, 68), true)
        local dl = imgui.GetWindowDrawList()
        local p = imgui.GetCursorScreenPos()

        -- Индикатор статуса
        local stCol = tracker_active and imgui.ImVec4(0.25, 0.85, 0.45, 1.0) or t.textDim
        dl:AddCircleFilled(imgui.ImVec2(p.x + 8, p.y + 9), 5, imgui.ColorConvertFloat4ToU32(stCol), 16)
        imgui.SetCursorPosX(imgui.GetCursorPosX() + 18)
        imgui.TextColored(stCol, tracker_active and u8"Сканирование активно (радиус 300 м)" or u8"Сканирование остановлено")

        imgui.SameLine(310)
        imgui.TextColored(t.textDim, fa.ICON_USERS .. u8" Всего собрано: ")
        imgui.SameLine(0, 2)
        imgui.TextColored(t.accent, tostring(#ids))

        imgui.SameLine(465)
        imgui.TextColored(t.textDim, fa.ICON_STREET_VIEW .. u8" Сейчас рядом: ")
        imgui.SameLine(0, 2)
        imgui.TextColored(imgui.ImVec4(0.30, 0.85, 0.45, 1.0), tostring(inRadCount))

        imgui.Spacing()

        if tracker_active then
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.75, 0.22, 0.22, 1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.85, 0.30, 0.30, 1.0))
            if imgui.Button(fa.ICON_STOP .. u8" Остановить сбор##tracker_toggle", imgui.ImVec2(170, 26)) then
                tracker_active = false
            end
            imgui.PopStyleColor(2)
        else
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.20, 0.62, 0.35, 1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.28, 0.72, 0.44, 1.0))
            if imgui.Button(fa.ICON_PLAY .. u8" Начать сбор##tracker_toggle", imgui.ImVec2(170, 26)) then
                tracker_active = true
            end
            imgui.PopStyleColor(2)
        end

        imgui.SameLine(0, 6)
        if imgui.Button(fa.ICON_FILE_TEXT_O .. u8" Сохранить в отчёт##tracker_to_rep", imgui.ImVec2(165, 26)) then
            tracker_report_form_open = true
        end
        if imgui.IsItemHovered() then imgui.SetTooltip(u8"Сохранить текущий список участников в отчёт") end

        imgui.SameLine(0, 6)
        if imgui.Button(fa.ICON_TRASH_O .. u8" Очистить список##tracker_reset", imgui.ImVec2(145, 26)) then
            tracker_players = {}
            ids = {}
            inRadCount = 0
        end
    imgui.EndChild()
    imgui.PopStyleVar()
    imgui.PopStyleColor(2)

    imgui.Spacing()

    if #ids == 0 then
        local avail = imgui.GetContentRegionAvail()
        imgui.PushStyleColor(imgui.Col.ChildWindowBg, imgui.ImVec4(t.windowBg.x, t.windowBg.y, t.windowBg.z, 0.45))
        imgui.PushStyleColor(imgui.Col.Border, cardBorder)
        imgui.BeginChild("##tr_empty_state", imgui.ImVec2(0, avail.y), true)
            local dl = imgui.GetWindowDrawList()
            local wp = imgui.GetCursorScreenPos()
            local cx, cy = wp.x + avail.x * 0.5, wp.y + avail.y * 0.42
            dl:AddCircleFilled(imgui.ImVec2(cx, cy - 18), 26, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.14)), 28)
            local icSz = imgui.CalcTextSize(fa.ICON_CROSSHAIRS)
            dl:AddText(imgui.ImVec2(cx - icSz.x * 0.5, cy - 18 - icSz.y * 0.5), imgui.ColorConvertFloat4ToU32(t.accent), fa.ICON_CROSSHAIRS)

            local msg1 = tracker_active and u8"Ожидание игроков в радиусе 300 метров..." or u8"Список участников в радиусе пуст"
            local msg2 = u8"Нажмите «Начать сбор», чтобы автоматически фиксировать всех игроков рядом и время их присутствия"
            local sz1 = imgui.CalcTextSize(msg1)
            local sz2 = imgui.CalcTextSize(msg2)
            dl:AddText(imgui.ImVec2(cx - sz1.x * 0.5, cy + 18), imgui.ColorConvertFloat4ToU32(t.text), msg1)
            dl:AddText(imgui.ImVec2(cx - sz2.x * 0.5, cy + 40), imgui.ColorConvertFloat4ToU32(t.textDim), msg2)
        imgui.EndChild()
        imgui.PopStyleColor(2)
        return
    end

    imgui.BeginChild("##tr_players_scroll", imgui.ImVec2(0, 0), false)
        for idx, pid in ipairs(ids) do
            local entry = tracker_players[pid]
            local displaySec = entry.totalSeconds
            if entry.inRadius then
                displaySec = displaySec + (os.time() - entry.lastTick)
            end

            imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
            imgui.PushStyleColor(imgui.Col.Border, entry.inRadius and imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.55) or cardBorder)
            imgui.BeginChild("tp_" .. pid, imgui.ImVec2(0, 36), true)
                local dl = imgui.GetWindowDrawList()
                local p = imgui.GetCursorScreenPos()
                local dotCol = entry.inRadius and imgui.ImVec4(0.25, 0.85, 0.45, 1.0) or imgui.ImVec4(0.55, 0.55, 0.60, 0.7)
                dl:AddCircleFilled(imgui.ImVec2(p.x + 6, p.y + 10), 4, imgui.ColorConvertFloat4ToU32(dotCol), 14)

                imgui.SetCursorPosX(imgui.GetCursorPosX() + 16)
                local nameColor = sampColorToImVec4(sampGetPlayerColor(pid))
                imgui.TextColored(nameColor, entry.nickname)
                imgui.SameLine(0, 6)
                imgui.TextColored(t.textDim, u8"[ID: " .. pid .. "]")

                imgui.SameLine(imgui.GetWindowWidth() - 185)
                imgui.TextColored(entry.inRadius and imgui.ImVec4(0.30, 0.85, 0.45, 1.0) or t.textDim,
                    entry.inRadius and u8"В радиусе" or u8"Вне радиуса")

                imgui.SameLine(imgui.GetWindowWidth() - 80)
                local timeColor = entry.inRadius and t.accent or t.textDim
                imgui.TextColored(timeColor, fa.ICON_CLOCK_O .. " " .. formatDuration(displaySec))

                if imgui.BeginPopupContextWindow() then
                    if imgui.MenuItem(fa.ICON_STICKY_NOTE .. u8" Скопировать никнейм") then
                        imgui.SetClipboardText(entry.nickname)
                    end
                    imgui.Separator()
                    if imgui.MenuItem(fa.ICON_TRASH .. u8" Удалить из списка") then
                        tracker_players[pid] = nil
                    end
                    imgui.EndPopup()
                end
            imgui.EndChild()
            imgui.PopStyleColor(2)
            imgui.Dummy(imgui.ImVec2(1, 2))
        end
    imgui.EndChild()
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
do
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
end

-- ---------- Форма создания отчёта ----------
tracker_report_form_open = false
local tracker_report_name = imgui.ImBuffer("", 64)

local function drawTrackerCreateReportForm(t)
    if not tracker_report_form_open then return end

    local sw, sh = getScreenResolution()
    local bgFlags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoSavedSettings

    -- 1. Полноэкранный затемняющий фон
    imgui.SetNextWindowPos(imgui.ImVec2(0, 0), imgui.Cond.Always)
    imgui.SetNextWindowSize(imgui.ImVec2(sw, sh), imgui.Cond.Always)
    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.02, 0.04, 0.07, 0.74))
    imgui.PushStyleVar(imgui.StyleVar.WindowRounding, 0.0)
    imgui.Begin("##trk_rep_backdrop", nil, bgFlags)
    if imgui.IsWindowHovered() and imgui.IsMouseClicked(0) then
        tracker_report_form_open = false
    end
    imgui.End()
    imgui.PopStyleVar()
    imgui.PopStyleColor()

    -- 2. Модальное окно создания отчёта без крестика
    local modalW, modalH = 440, 222
    imgui.SetNextWindowSize(imgui.ImVec2(modalW, modalH), imgui.Cond.Always)
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))

    pushThemeColors()
    pushThemeRounding()
    imgui.PushStyleVar(imgui.StyleVar.WindowPadding, imgui.ImVec2(18, 14))
    imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(t.windowBg.x, t.windowBg.y, t.windowBg.z, 0.99))
    imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.65))

    imgui.Begin("##tracker_report_form_modal", nil, imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar)

        imgui.TextColored(t.accent, fa.ICON_FILE_TEXT_O .. u8"  СОЗДАНИЕ НОВОГО ОТЧЁТА")
        imgui.Separator()
        imgui.Spacing()

        imgui.TextColored(t.textDim, fa.ICON_TAG .. u8"  Название ивента:")
        imgui.PushItemWidth(-1)
        imgui.InputText("##tracker_report_name", tracker_report_name)
        imgui.PopItemWidth()

        imgui.Spacing()

        local count = 0
        for _ in pairs(tracker_players) do count = count + 1 end

        imgui.PushStyleColor(imgui.Col.ChildWindowBg, imgui.ImVec4(t.frameBg.x, t.frameBg.y, t.frameBg.z, 0.55))
        imgui.BeginChild("##trk_rep_info_pill", imgui.ImVec2(-1, 34), false)
            imgui.SetCursorPos(imgui.ImVec2(12, 8))
            imgui.TextColored(t.textDim, fa.ICON_USERS .. u8"  Игроков собрано:")
            imgui.SameLine(0, 6)
            imgui.TextColored(t.accent, tostring(count) .. u8" чел.")
            imgui.SameLine(225)
            imgui.TextColored(t.textDim, fa.ICON_CALENDAR .. "  " .. os.date("%d.%m.%Y  %H:%M"))
        imgui.EndChild()
        imgui.PopStyleColor()

        imgui.Spacing(); imgui.Separator(); imgui.Spacing()

        local btnW = math.floor((modalW - 36 - 8) * 0.5)
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.20, 0.62, 0.35, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.28, 0.72, 0.44, 1.0))
        if imgui.Button(fa.ICON_CHECK .. u8"  Сохранить отчёт##tracker_report_save", imgui.ImVec2(btnW + 20, 32)) then
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
        imgui.PopStyleColor(2)

        imgui.SameLine(0, 8)
        if imgui.Button(fa.ICON_TIMES .. u8"  Закрыть##tracker_report_cancel", imgui.ImVec2(btnW - 20, 32)) then
            tracker_report_form_open = false
        end

    imgui.End()
    imgui.PopStyleColor(2)
    imgui.PopStyleVar()
    imgui.PopStyleVar(THEME_ROUNDING_COUNT)
    imgui.PopStyleColor(THEME_COLOR_COUNT)
end
-- ---------- Окно просмотра отчёта ----------
local tracker_report_viewer_idx = nil

local function drawTrackerReportsTab(t)
    local cardBg = imgui.ImVec4(t.windowBg.x, t.windowBg.y, t.windowBg.z, 0.80)
    local cardBorder = imgui.ImVec4(t.border.x, t.border.y, t.border.z, 0.45)

    if tracker_report_viewer_idx then
        local r = trackerReports[tracker_report_viewer_idx]
        if not r then
            tracker_report_viewer_idx = nil
        else
            if imgui.Button(fa.ICON_ARROW_LEFT .. u8" Назад к списку##tracker_report_back", imgui.ImVec2(150, 28)) then
                tracker_report_viewer_idx = nil
            end
            imgui.SameLine()
            if imgui.Button(fa.ICON_STICKY_NOTE .. u8" Скопировать всех##tracker_rep_copy_all", imgui.ImVec2(160, 28)) then
                local lines = {}
                for _, p in ipairs(r.players) do
                    lines[#lines + 1] = p.nickname .. " (" .. formatDuration(p.seconds) .. ")"
                end
                imgui.SetClipboardText(table.concat(lines, "\n"))
                showToast("Список участников скопирован")
            end

            imgui.Spacing()
            imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
            imgui.PushStyleColor(imgui.Col.Border, cardBorder)
            imgui.BeginChild("##tr_rep_head", imgui.ImVec2(0, 42), true)
                imgui.TextColored(t.accent, fa.ICON_CALENDAR_CHECK_O .. "  " .. r.event)
                imgui.SameLine(imgui.GetWindowWidth() - 250)
                imgui.TextColored(t.textDim, fa.ICON_CLOCK_O .. " " .. os.date("%d.%m.%Y %H:%M", r.time) .. u8"  |  Участников: " .. #r.players)
            imgui.EndChild()
            imgui.PopStyleColor(2)
            imgui.Spacing()

            if #r.players == 0 then
                imgui.TextColored(t.textDim, u8"Список участников в этом отчёте пуст.")
            else
                imgui.BeginChild("##tr_rep_players_scroll", imgui.ImVec2(0, 0), false)
                    for i, p in ipairs(r.players) do
                        imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
                        imgui.PushStyleColor(imgui.Col.Border, cardBorder)
                        imgui.BeginChild("trp_" .. i, imgui.ImVec2(0, 34), true)
                            imgui.TextColored(t.textDim, tostring(i) .. ".")
                            imgui.SameLine(34)
                            imgui.Text(p.nickname)
                            imgui.SameLine(imgui.GetWindowWidth() - 85)
                            imgui.TextColored(t.accent, fa.ICON_CLOCK_O .. " " .. formatDuration(p.seconds))
                        imgui.EndChild()
                        imgui.PopStyleColor(2)
                        imgui.Dummy(imgui.ImVec2(1, 2))
                    end
                imgui.EndChild()
            end
            return
        end
    end

    imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
    imgui.PushStyleColor(imgui.Col.Border, cardBorder)
    imgui.BeginChild("##tr_rep_top", imgui.ImVec2(0, 46), true)
        imgui.AlignTextToFramePadding()
        imgui.TextColored(t.textDim, fa.ICON_ARCHIVE .. u8" Сохранено отчётов по радиусу: ")
        imgui.SameLine(0, 2)
        imgui.TextColored(t.accent, tostring(#trackerReports))
        imgui.SameLine(imgui.GetWindowWidth() - 185)
        if imgui.Button(fa.ICON_PLUS .. u8" Создать отчёт##tracker_create_report", imgui.ImVec2(170, 28)) then
            tracker_report_form_open = true
        end
    imgui.EndChild()
    imgui.PopStyleColor(2)

    imgui.Spacing()

    if #trackerReports == 0 then
        local avail = imgui.GetContentRegionAvail()
        imgui.PushStyleColor(imgui.Col.ChildWindowBg, imgui.ImVec4(t.windowBg.x, t.windowBg.y, t.windowBg.z, 0.45))
        imgui.PushStyleColor(imgui.Col.Border, cardBorder)
        imgui.BeginChild("##tr_rep_empty", imgui.ImVec2(0, avail.y), true)
            local dl = imgui.GetWindowDrawList()
            local wp = imgui.GetCursorScreenPos()
            local cx, cy = wp.x + avail.x * 0.5, wp.y + avail.y * 0.45
            local msg = u8"Сохранённых отчётов пока нет. Нажмите «Создать отчёт», чтобы сохранить собранных игроков."
            local sz = imgui.CalcTextSize(msg)
            dl:AddText(imgui.ImVec2(cx - sz.x * 0.5, cy), imgui.ColorConvertFloat4ToU32(t.textDim), msg)
        imgui.EndChild()
        imgui.PopStyleColor(2)
        return
    end

    imgui.BeginChild("##tr_rep_list_scroll", imgui.ImVec2(0, 0), false)
        for i = #trackerReports, 1, -1 do
            local r = trackerReports[i]
            imgui.PushID("tracker_report_" .. i)
            local pCount = r.players and #r.players or 0
            local label = fa.ICON_FILE_TEXT_O .. "  " .. r.event .. u8"   |   " .. os.date("%d.%m.%Y в %H:%M", r.time) .. u8"   |   Участников: " .. pCount
            if imgui.Button(label, imgui.ImVec2(-1, 36)) then
                tracker_report_viewer_idx = i
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip(u8"ЛКМ — открыть отчёт | Колёсико мыши — удалить отчёт")
            end
            if imgui.IsItemClicked(2) then
                deleteTrackerReport(i)
            end
            imgui.PopID()
            imgui.Dummy(imgui.ImVec2(1, 2))
        end
    imgui.EndChild()
end

local CURATOR_SECTIONS = {
    { icon = fa.ICON_CROSSHAIRS, title = u8"Сбор участников", sub = u8"Радиус 300м и таймер" },
    { icon = fa.ICON_USER,       title = u8"Кураторы (авто)", sub = u8"Посещаемость кураторов" },
    { icon = fa.ICON_STAR,       title = u8"Актёры (авто)",   sub = u8"Сбор из /rwave в таблицу" },
    { icon = fa.ICON_SLIDERS,    title = u8"Менеджер ролей",  sub = u8"Выдача скинов и оружия" },
}
local curators_selected_section = 1

local function drawCuratorsCollectSection(t)
    imgui.AlignTextToFramePadding()
    imgui.TextColored(t.accent, fa.ICON_CROSSHAIRS .. u8"  Мониторинг участников ивента в радиусе")
    imgui.SameLine(imgui.GetWindowWidth() - 285)

    local pushed = 0
    if tracker_subtab == "radius" then
        imgui.PushStyleColor(imgui.Col.Button, t.accent)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, t.accent)
        pushed = 2
    end
    if imgui.Button(fa.ICON_STREET_VIEW .. u8" Радиус##tracker_sub_radius", imgui.ImVec2(130, 26)) then
        tracker_subtab = "radius"
    end
    if pushed > 0 then imgui.PopStyleColor(pushed) end

    imgui.SameLine(0, 6)

    pushed = 0
    if tracker_subtab == "reports" then
        imgui.PushStyleColor(imgui.Col.Button, t.accent)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, t.accent)
        pushed = 2
    end
    if imgui.Button(fa.ICON_ARCHIVE .. u8" Отчётность (" .. #trackerReports .. ")##tracker_sub_reports", imgui.ImVec2(140, 26)) then
        tracker_subtab = "reports"
    end
    if pushed > 0 then imgui.PopStyleColor(pushed) end

    imgui.Separator()
    imgui.Spacing()

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

    local attendeesSnapshot = {}
    for _, nick in ipairs(curator_captured) do attendeesSnapshot[#attendeesSnapshot + 1] = nick end
    local eventNameForReport = u8(eventText)

        sampAddChatMessage('{5B85C4}[TRPcomm] {FFFFFF}Отправка отчёта по кураторам...', -1)
    downloadUrlToFile(finalUrl, "moonloader\\config\\trp_temp.txt", function(id, status)
        if status == 6 then
            showToast('Данные по кураторам занесены в таблицу.')
            addCuratorFillReport(eventNameForReport, attendeesSnapshot)
            curator_captured = {}
        else

        end
    end)
end

-- ============================================================
--  ОТЧЁТЫ АВТОЗАПОЛНЕНИЯ КУРАТОРОВ: хранение
--  moonloader\config\TRPcomm Manager Config\curator_fill_reports\index.ini
-- ============================================================
CURATOR_FILL_REPORTS_INDEX_PATH = "moonloader\\config\\TRPcomm Manager Config\\curator_fill_reports\\index.ini"

local defaultCuratorFillReportsIndex = { reports = { count = "0" } }
ensureIniFile(CURATOR_FILL_REPORTS_INDEX_PATH, "reports", { "count=0" })
local curatorFillReportsIndexIni = inicfg.load(defaultCuratorFillReportsIndex, CURATOR_FILL_REPORTS_INDEX_PATH) or defaultCuratorFillReportsIndex
curatorFillReports = {} -- { {id=, event=(u8), time=os.time(), attendees={nickname, ...}}, ... }

local function saveCuratorFillReportsIndex()
    local cfg = { reports = { count = tostring(#curatorFillReports) } }
    for i, r in ipairs(curatorFillReports) do
        cfg.reports["report" .. i .. "_id"]        = r.id
        cfg.reports["report" .. i .. "_event"]     = u8:decode(r.event)
        cfg.reports["report" .. i .. "_time"]      = tostring(r.time)
        cfg.reports["report" .. i .. "_attendees"] = table.concat(r.attendees, "|")
    end
    inicfg.save(cfg, CURATOR_FILL_REPORTS_INDEX_PATH)
    curatorFillReportsIndexIni = cfg
end

local function addCuratorFillReport(eventNameUtf8, attendees)
    curatorFillReports[#curatorFillReports + 1] = {
        id = "curator_fill_report_" .. os.time() .. "_" .. tostring(math.random(1000, 9999)),
        event = eventNameUtf8,
        time = os.time(),
        attendees = attendees,
    }
    saveCuratorFillReportsIndex()
end

local function deleteCuratorFillReport(idx)
    if not curatorFillReports[idx] then return end
    table.remove(curatorFillReports, idx)
    saveCuratorFillReportsIndex()
end

do
    local cnt = tonumber(curatorFillReportsIndexIni.reports.count) or 0
    for i = 1, cnt do
        local id           = curatorFillReportsIndexIni.reports["report" .. i .. "_id"]
        local eventRaw     = curatorFillReportsIndexIni.reports["report" .. i .. "_event"]
        local timeRaw      = curatorFillReportsIndexIni.reports["report" .. i .. "_time"]
        local attendeesRaw = curatorFillReportsIndexIni.reports["report" .. i .. "_attendees"]
        if id then
            local attendees = {}
            if attendeesRaw and attendeesRaw ~= "" then
                for nick in attendeesRaw:gmatch("[^|]+") do
                    attendees[#attendees + 1] = nick
                end
            end
            curatorFillReports[#curatorFillReports + 1] = {
                id = id,
                event = u8(eventRaw or ""),
                time = tonumber(timeRaw) or 0,
                attendees = attendees,
            }
        end
    end
end

local curator_fill_report_viewer_idx = nil

local function drawCuratorFillReportsTab(t)
    if curator_fill_report_viewer_idx then
        local r = curatorFillReports[curator_fill_report_viewer_idx]
        if not r then
            curator_fill_report_viewer_idx = nil
        else
            if imgui.Button(fa.ICON_ARROW_LEFT .. u8" Назад##curator_fill_report_back", imgui.ImVec2(110, 28)) then
                curator_fill_report_viewer_idx = nil
            end
            imgui.Spacing()
            imgui.TextColored(t.accent, r.event)
            imgui.TextColored(t.textDim, os.date("%d.%m.%Y  %H:%M", r.time))
            imgui.Spacing(); imgui.Separator(); imgui.Spacing()

            if #r.attendees == 0 then
                imgui.TextColored(t.textDim, u8"Список пуст.")
            end
            for i, nick in ipairs(r.attendees) do
                imgui.BeginChild("cfr_" .. i, imgui.ImVec2(0, 32), true)
                    imgui.Text(i .. ". " .. nick)
                imgui.EndChild()
                imgui.Spacing()
            end
            return
        end
    end

    imgui.TextColored(t.textDim, u8"История отчётов по кураторам:")
    imgui.Spacing()

    if #curatorFillReports == 0 then
        imgui.TextColored(t.textDim, u8"Отчётов пока нет.")
        return
    end

    for i = #curatorFillReports, 1, -1 do
        local r = curatorFillReports[i]
        imgui.PushID("curator_fill_report_" .. i)
        local label = r.event .. u8"   |   Время " .. os.date("%H:%M", r.time) .. u8"   |   Дата " .. os.date("%d.%m.%Y", r.time) .. u8"   |   " .. #r.attendees .. u8" чел."
        if imgui.Button(label, imgui.ImVec2(-1, 32)) then
            curator_fill_report_viewer_idx = i
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip(u8"ЛКМ — открыть | Колёсико — удалить отчёт")
        end
        if imgui.IsItemClicked(2) then
            deleteCuratorFillReport(i)
        end
        imgui.PopID()
        imgui.Spacing()
    end
end

curator_fill_subtab = "fill" -- "fill" | "reports"

local function drawCuratorFillMainTab(t)
    local cardBg = imgui.ImVec4(t.windowBg.x, t.windowBg.y, t.windowBg.z, 0.80)
    local cardBorder = imgui.ImVec4(t.border.x, t.border.y, t.border.z, 0.45)

    imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
    imgui.PushStyleColor(imgui.Col.Border, cardBorder)
    imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, 8.0)
    imgui.BeginChild("##cur_auto_ctrl", imgui.ImVec2(0, 82), true)
        imgui.AlignTextToFramePadding()
        imgui.TextColored(t.textDim, fa.ICON_TAG .. u8"  Название ивента:")
        imgui.SameLine(160)
        imgui.PushItemWidth(260)
        imgui.InputText("##curator_event_name", curator_event_name)
        imgui.PopItemWidth()

        imgui.SameLine()
        if curator_active then
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.20, 0.62, 0.35, 1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.28, 0.72, 0.44, 1.0))
            if imgui.Button(fa.ICON_CLOUD_UPLOAD .. u8" Завершить и отправить##curator_finish", imgui.ImVec2(210, 26)) then
                sendCuratorReport()
            end
            imgui.PopStyleColor(2)
        else
            if imgui.Button(fa.ICON_PLAY .. u8" Начать мониторинг##curator_start", imgui.ImVec2(190, 26)) then
                local nameText = u8:decode(curator_event_name.v)
                if nameText == "" then
                    sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Сначала укажи название ивента.', -1)
                else
                    curator_active = true
                    curator_captured = {}
                    showToast('Мониторинг кураторов запущен: ' .. nameText)
                end
            end
        end

        imgui.Spacing()
        imgui.TextColored(t.textDim, fa.ICON_DATABASE .. u8" База кураторов: ")
        imgui.SameLine(0, 2)
        imgui.TextColored(t.accent, tostring(#curator_list) .. u8" чел.")
        imgui.SameLine(200)
        imgui.TextColored(t.textDim, fa.ICON_CHECK_CIRCLE .. u8" Зафиксировано на ивенте: ")
        imgui.SameLine(0, 2)
        imgui.TextColored(imgui.ImVec4(0.30, 0.85, 0.45, 1.0), tostring(#curator_captured) .. u8" чел.")
        if curator_active then
            imgui.SameLine(430)
            imgui.TextColored(imgui.ImVec4(0.95, 0.75, 0.25, 1.0), fa.ICON_SPINNER .. u8" Идёт автоматический сбор...")
        end
    imgui.EndChild()
    imgui.PopStyleVar()
    imgui.PopStyleColor(2)

    imgui.Spacing()

    if #curator_captured == 0 then
        local avail = imgui.GetContentRegionAvail()
        imgui.PushStyleColor(imgui.Col.ChildWindowBg, imgui.ImVec4(t.windowBg.x, t.windowBg.y, t.windowBg.z, 0.45))
        imgui.PushStyleColor(imgui.Col.Border, cardBorder)
        imgui.BeginChild("##cur_auto_empty", imgui.ImVec2(0, avail.y), true)
            local dl = imgui.GetWindowDrawList()
            local wp = imgui.GetCursorScreenPos()
            local cx, cy = wp.x + avail.x * 0.5, wp.y + avail.y * 0.44
            local msg1 = curator_active and u8"Ожидание появления кураторов из базы..." or u8"Зафиксированных кураторов пока нет"
            local msg2 = u8"Укажите название ивента и нажмите «Начать мониторинг» для автозаполнения посещаемости"
            local sz1 = imgui.CalcTextSize(msg1)
            local sz2 = imgui.CalcTextSize(msg2)
            dl:AddText(imgui.ImVec2(cx - sz1.x * 0.5, cy - 10), imgui.ColorConvertFloat4ToU32(t.text), msg1)
            dl:AddText(imgui.ImVec2(cx - sz2.x * 0.5, cy + 14), imgui.ColorConvertFloat4ToU32(t.textDim), msg2)
        imgui.EndChild()
        imgui.PopStyleColor(2)
        return
    end

    imgui.BeginChild("##cur_captured_scroll", imgui.ImVec2(0, 0), false)
        for i, name in ipairs(curator_captured) do
            imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
            imgui.PushStyleColor(imgui.Col.Border, cardBorder)
            imgui.BeginChild("cur_cap_" .. i, imgui.ImVec2(0, 34), true)
                imgui.TextColored(imgui.ImVec4(0.30, 0.85, 0.45, 1.0), fa.ICON_CHECK_CIRCLE)
                imgui.SameLine(30)
                imgui.Text(i .. ".  " .. name)
            imgui.EndChild()
            imgui.PopStyleColor(2)
            imgui.Dummy(imgui.ImVec2(1, 2))
        end
    imgui.EndChild()
end

local function drawCuratorsFillCuratorsSection(t)
    imgui.AlignTextToFramePadding()
    imgui.TextColored(t.accent, fa.ICON_USER .. u8"  Автозаполнение посещаемости кураторов")
    imgui.SameLine(imgui.GetWindowWidth() - 305)

    local pushed = 0
    if curator_fill_subtab == "fill" then
        imgui.PushStyleColor(imgui.Col.Button, t.accent)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, t.accent)
        pushed = 2
    end
    if imgui.Button(fa.ICON_PLAY_CIRCLE .. u8" Мониторинг##curator_fill_sub_fill", imgui.ImVec2(145, 26)) then
        curator_fill_subtab = "fill"
    end
    if pushed > 0 then imgui.PopStyleColor(pushed) end

    imgui.SameLine(0, 6)

    pushed = 0
    if curator_fill_subtab == "reports" then
        imgui.PushStyleColor(imgui.Col.Button, t.accent)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, t.accent)
        pushed = 2
    end
    if imgui.Button(fa.ICON_ARCHIVE .. u8" Отчётность (" .. #curatorFillReports .. ")##curator_fill_sub_reports", imgui.ImVec2(145, 26)) then
        curator_fill_subtab = "reports"
    end
    if pushed > 0 then imgui.PopStyleColor(pushed) end

    imgui.Separator()
    imgui.Spacing()

    if curator_fill_subtab == "fill" then
        drawCuratorFillMainTab(t)
    else
        drawCuratorFillReportsTab(t)
    end
end
-- ============================================================
--  КУРАТОРЫ: АВТОЗАПОЛНЕНИЕ ПОСЕЩАЕМОСТИ АКТЁРОВ (v3.0)
-- ============================================================
ACTORS_DEFAULT_URL = "https://script.google.com/macros/s/AKfycbwAb8CpcQgee8dVZobbsZNTA1zDWQsF98B2glHXBurCPjfVwT7vsI_DOavIdQ0XEq1M-Q/exec"

actors_event_name = imgui.ImBuffer("", 64)
actors_active     = false
actors_sending    = false
actors_captured   = {}

local function sendActorsReport()
    if #actors_captured == 0 then
        sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Список участников пуст! Сначала соберите их кнопкой "Собрать участников" или добавьте вручную.', -1)
        return
    end

    local eventTitle = actors_event_name.v
    if not eventTitle or eventTitle == "" or eventTitle:gsub("%s+", "") == "" then
        sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Укажите название ивента перед отправкой в таблицу!', -1)
        return
    end

    local membersUtf8 = {}
    for i, nick in ipairs(actors_captured) do
        membersUtf8[i] = u8(nick)
    end
    local json_data = cjson.encode({ event = eventTitle, members = membersUtf8 })

    local targetUrl = ACTORS_DEFAULT_URL
    targetUrl = targetUrl:gsub("^%s+", ""):gsub("%s+$", "")

    actors_sending = true
    sampAddChatMessage('{5B85C4}[TRPcomm] {FFFFFF}Отправка посещаемости в Google Таблицу ({5B85C4}' .. #actors_captured .. '{FFFFFF} чел.)...', -1)

    local function handleResponse(resp)
        actors_sending = false
        if not resp then
            sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Ошибка: нет ответа от Google Таблицы.', -1)
            return
        end

        local text = resp.text or ""
        local ok_json, resData = pcall(cjson.decode, text)
        if ok_json and type(resData) == "table" and resData.status == "ok" then
            local col = resData.colLetter or ("#" .. tostring(resData.colIndex or "?"))
            local count = tostring(resData.presentCount or 0)
            local total = tostring(resData.totalActors or 0)
            local displayTitle = eventTitle
            local p_ok, dec = pcall(u8.decode, u8, eventTitle)
            if p_ok and dec then displayTitle = dec end
            showToast('Успешно! Колонка ' .. col .. ' (' .. count .. ' чел.)')
            sampAddChatMessage(string.format('{5B85C4}[TRPcomm] {FFFFFF}Успешно! Ивент "%s" записан в колонку {5B85C4}%s{FFFFFF} (отмечено {5B85C4}%s/%s{FFFFFF} чел.).', displayTitle, col, count, total), -1)
            actors_captured = {}
        elseif ok_json and type(resData) == "table" and resData.status == "error" then
            local msg = tostring(resData.message or "Неизвестная ошибка")
            local p_ok, dec = pcall(u8.decode, u8, msg)
            sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Ошибка Google таблицы: ' .. (p_ok and dec or msg), -1)
        else
            local errClean = text:match('ErrorMessage">(.-)</div>') or text:match('Error:%s*([^%c<]+)')
            if errClean then
                local p_ok, dec = pcall(u8.decode, u8, errClean)
                sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Ошибка в скрипте таблицы: ' .. (p_ok and dec or errClean), -1)
            elseif resp.status_code == 200 or resp.status_code == 302 then
                showToast('Посещаемость отправлена!')
                sampAddChatMessage('{5B85C4}[TRPcomm] {FFFFFF}Запрос успешно доставлен в Google Таблицу.', -1)
                actors_captured = {}
            else
                sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Ошибка отправки: HTTP код ' .. tostring(resp.status_code), -1)
            end
        end
    end

    local ok_req, https = pcall(require, 'asyncHttpRequest')
    if ok_req and https and https.request then
        https.request("POST", targetUrl, {
            headers = { ["Content-Type"] = "application/json; charset=UTF-8" },
            data = json_data
        },
        function(response)
            local loc = response and response.headers and (response.headers.location or response.headers.Location)
            if (response.status_code == 302 or response.status_code == 301) and loc and loc ~= "" then
                https.request("GET", loc, {}, function(redir_resp)
                    handleResponse(redir_resp or response)
                end,
                function(err)
                    handleResponse(response)
                end)
            else
                handleResponse(response)
            end
        end,
        function(err)
            actors_sending = false
            sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Сетевая ошибка: ' .. tostring(err or "таймаут"), -1)
        end)
    else
        lua_thread.create(function()
            local ok, response = pcall(requests.post, targetUrl, {
                headers = { ["Content-Type"] = "application/json; charset=UTF-8" },
                data = json_data,
                timeout = 15,
            })
            if not ok or not response then
                actors_sending = false
                sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Ошибка сети! Проверьте подключение к интернету.', -1)
                return
            end
            local loc = response.headers and (response.headers.location or response.headers.Location)
            if (response.status_code == 302 or response.status_code == 301) and loc and loc ~= "" then
                local ok2, redir_resp = pcall(requests.get, loc, { timeout = 10 })
                if ok2 and redir_resp then
                    handleResponse(redir_resp)
                    return
                end
            end
            handleResponse(response)
        end)
    end
end

local function startActorsCollection()
    local nameText = u8:decode(actors_event_name.v)
    if nameText == "" or nameText:gsub("%s+", "") == "" then
        sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Введите название ивента перед запуском сбора!', -1)
        return
    end

    actors_active   = true
    actors_captured = {}
    sampAddChatMessage('{5B85C4}[TRPcomm] {FFFFFF}Сбор участников для ивента {5B85C4}"' .. nameText .. '"{FFFFFF}... Отправка /rwave members.', -1)
    showToast('Сбор участников: ' .. nameText)
    sampSendChat("/rwave members")

    lua_thread.create(function()
        wait(2500)
        actors_active = false
        if #actors_captured > 0 then
            sampAddChatMessage(string.format('{5B85C4}[TRPcomm] {FFFFFF}Сбор завершён! Найдено участников: {5B85C4}%d{FFFFFF} чел. Нажмите "Отправить в таблицу".', #actors_captured), -1)
            showToast('Найдено: ' .. #actors_captured .. ' участников')
        else
            sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Члены радиоволны не ответили на /rwave members. Вы можете ввести ники вручную в окне скрипта.', -1)
            showToast('Участники не найдены')
        end
    end)
end

local function drawCuratorsFillActorsSection(t)
    local cardBg = imgui.ImVec4(t.windowBg.x, t.windowBg.y, t.windowBg.z, 0.80)
    local cardBorder = imgui.ImVec4(t.border.x, t.border.y, t.border.z, 0.45)

    imgui.AlignTextToFramePadding()
    imgui.TextColored(t.accent, fa.ICON_STAR .. u8"  Посещаемость актёров и фотографов (Google Таблица)")
    imgui.Separator()
    imgui.Spacing()

    -- Карточка шагов 1 и 2
    imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
    imgui.PushStyleColor(imgui.Col.Border, cardBorder)
    imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, 8.0)
    imgui.BeginChild("##actors_ctrl_card", imgui.ImVec2(0, 118), true)
        imgui.AlignTextToFramePadding()
        imgui.TextColored(t.textDim, fa.ICON_TAG .. u8"  Название ивента:")
        imgui.SameLine(160)
        imgui.PushItemWidth(270)
        imgui.InputText("##actors_event_name", actors_event_name)
        imgui.PopItemWidth()

        imgui.SameLine(445)
        imgui.TextColored(t.textDim, fa.ICON_USERS .. u8" Собрано: ")
        imgui.SameLine(0, 2)
        imgui.TextColored(t.accent, tostring(#actors_captured) .. u8" чел.")

        imgui.Spacing()

        if actors_active then
            imgui.Button(fa.ICON_SPINNER .. u8" Сбор ников из /rwave members (2.5 сек)...", imgui.ImVec2(285, 30))
        else
            if imgui.Button(fa.ICON_CROSSHAIRS .. u8" 1. Собрать из /rwave members##actors_start", imgui.ImVec2(285, 30)) then
                startActorsCollection()
            end
        end

        imgui.SameLine(0, 8)

        if actors_sending then
            imgui.Button(fa.ICON_REFRESH .. u8" Отправка в Google Таблицу...", imgui.ImVec2(285, 30))
        else
            local canSend = (#actors_captured > 0) and not actors_active
            if not canSend then
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.2, 0.22, 0.28, 0.5))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.2, 0.22, 0.28, 0.5))
                imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.5, 0.5, 0.5, 0.6))
            else
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.20, 0.62, 0.35, 1.0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.28, 0.72, 0.44, 1.0))
                imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1, 1, 1, 1))
            end
            if imgui.Button(fa.ICON_CLOUD_UPLOAD .. u8" 2. Отправить в Google Таблицу##actors_send", imgui.ImVec2(285, 30)) then
                if canSend then
                    sendActorsReport()
                else
                    sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Сначала соберите участников кнопкой 1!', -1)
                end
            end
            imgui.PopStyleColor(3)
        end

        imgui.Spacing()
        imgui.AlignTextToFramePadding()
        imgui.TextColored(t.textDim, fa.ICON_USER_PLUS .. u8"  Добавить вручную:")
        imgui.SameLine(160)
        imgui.PushItemWidth(220)
        imgui.InputText("##actors_manual_add", actors_manual_nick_buf)
        imgui.PopItemWidth()
        imgui.SameLine(0, 6)
        if imgui.Button(fa.ICON_PLUS .. u8" Добавить##actors_btn_add", imgui.ImVec2(100, 24)) then
            local addNick = u8:decode(actors_manual_nick_buf.v)
            addNick = addNick:gsub("^%s+", ""):gsub("%s+$", "")
            if addNick ~= "" then
                actors_captured[#actors_captured + 1] = addNick
                actors_manual_nick_buf.v = ""
                showToast('Добавлен: ' .. addNick)
            end
        end
        if #actors_captured > 0 then
            imgui.SameLine(0, 6)
            if imgui.Button(fa.ICON_TRASH_O .. u8" Очистить##actors_clear", imgui.ImVec2(105, 24)) then
                actors_captured = {}
            end
        end
    imgui.EndChild()
    imgui.PopStyleVar()
    imgui.PopStyleColor(2)

    imgui.Spacing()

    local listH = imgui.GetContentRegionAvail().y
    if #actors_captured == 0 then
        imgui.PushStyleColor(imgui.Col.ChildWindowBg, imgui.ImVec4(t.windowBg.x, t.windowBg.y, t.windowBg.z, 0.45))
        imgui.PushStyleColor(imgui.Col.Border, cardBorder)
        imgui.BeginChild("##actors_empty_box", imgui.ImVec2(0, math.max(100, listH)), true)
            local dl = imgui.GetWindowDrawList()
            local wp = imgui.GetCursorScreenPos()
            local avail = imgui.GetContentRegionAvail()
            local cx, cy = wp.x + avail.x * 0.5, wp.y + avail.y * 0.45
            local msg = u8"Список участников пуст. Нажмите «1. Собрать из /rwave members» или добавьте ники вручную."
            local sz = imgui.CalcTextSize(msg)
            dl:AddText(imgui.ImVec2(cx - sz.x * 0.5, cy), imgui.ColorConvertFloat4ToU32(t.textDim), msg)
        imgui.EndChild()
        imgui.PopStyleColor(2)
    else
        imgui.BeginChild("##actors_captured_list", imgui.ImVec2(0, math.max(100, listH)), false)
            for i, name in ipairs(actors_captured) do
                imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
                imgui.PushStyleColor(imgui.Col.Border, cardBorder)
                imgui.BeginChild("act_cap_" .. i, imgui.ImVec2(0, 32), true)
                    imgui.TextColored(imgui.ImVec4(0.3, 0.85, 0.45, 1.0), fa.ICON_CHECK_CIRCLE)
                    imgui.SameLine(28)
                    imgui.Text(string.format("%d.  %s", i, name))
                    imgui.SameLine(imgui.GetWindowWidth() - 42)
                    if imgui.Button(fa.ICON_TIMES .. "##del_act_" .. i, imgui.ImVec2(26, 20)) then
                        table.remove(actors_captured, i)
                    end
                imgui.EndChild()
                imgui.PopStyleColor(2)
                imgui.Dummy(imgui.ImVec2(1, 2))
            end
        imgui.EndChild()
    end

end
-- ============================================================
--  УПРАВЛЕНИЕ РОЛЯМИ АКТЁРОВ (Вкладка 4 в "Кураторы")
-- ============================================================
role_requests = {} -- { {id=числоStr, nick=, skin=, weapon=, weaponName=, color=}, ... }
role_approve_distance_error = false -- флаг "сервер только что написал 'вы слишком далеко'"
role_approve_cooldown_until = 0     -- os.clock(), до какого момента кнопки "Одобрить" серые

local function addOrUpdateRoleRequest(req)
    for i, existing in ipairs(role_requests) do
        if existing.id == req.id then
            role_requests[i] = req
            return
        end
    end
    role_requests[#role_requests + 1] = req
end

local function removeRoleRequest(index)
    table.remove(role_requests, index)
end

local function removeRoleRequestByRef(req)
    for i, r in ipairs(role_requests) do
        if r == req then
            table.remove(role_requests, i)
            return
        end
    end
end

local function approveRoleRequest(index)
    local req = role_requests[index]
    if not req then return end

    role_approve_cooldown_until = os.clock() + 2

    lua_thread.create(function()
        role_approve_distance_error = false

        if req.skin then
            sampSendChat("/videoskin " .. req.id .. " " .. req.skin)
            wait(500)
        end
        if req.color then
            sampSendChat("/videocolor " .. req.id .. " " .. req.color)
            wait(500)
        end
        if req.weapon then
            sampSendChat("/vgun " .. req.id .. " " .. req.weapon)
            wait(500)
        end
        if req.armor then
            sampSendChat("/varm " .. req.id)
            wait(500)
        end

        if role_approve_distance_error then
            sampAddChatMessage('{FF6B6B}[TRPcomm] {FFFFFF}Не удалось выдать роль ' .. req.nick .. ' {FFFFFF}— слишком далеко. Подойди ближе и одобри заявку ещё раз.', -1)
        else
            removeRoleRequestByRef(req)
        end
    end)
end

local function drawCuratorsRoleManagerSection(t)
    local cardBg = imgui.ImVec4(t.windowBg.x, t.windowBg.y, t.windowBg.z, 0.80)
    local cardBorder = imgui.ImVec4(t.border.x, t.border.y, t.border.z, 0.45)

    imgui.AlignTextToFramePadding()
    imgui.TextColored(t.accent, fa.ICON_SLIDERS .. u8"  Менеджер выдачи ролей актёрам")
    imgui.SameLine(imgui.GetWindowWidth() - 180)
    imgui.TextColored(t.textDim, u8"Активных заявок: ")
    imgui.SameLine(0, 2)
    imgui.TextColored(t.accent, tostring(#role_requests))
    imgui.Separator()
    imgui.Spacing()

    if #role_requests == 0 then
        local avail = imgui.GetContentRegionAvail()
        imgui.PushStyleColor(imgui.Col.ChildWindowBg, imgui.ImVec4(t.windowBg.x, t.windowBg.y, t.windowBg.z, 0.45))
        imgui.PushStyleColor(imgui.Col.Border, cardBorder)
        imgui.BeginChild("##rm_empty", imgui.ImVec2(0, avail.y), true)
            local dl = imgui.GetWindowDrawList()
            local wp = imgui.GetCursorScreenPos()
            local cx, cy = wp.x + avail.x * 0.5, wp.y + avail.y * 0.42
            dl:AddCircleFilled(imgui.ImVec2(cx, cy - 18), 26, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.14)), 28)
            local icSz = imgui.CalcTextSize(fa.ICON_SLIDERS)
            dl:AddText(imgui.ImVec2(cx - icSz.x * 0.5, cy - 18 - icSz.y * 0.5), imgui.ColorConvertFloat4ToU32(t.accent), fa.ICON_SLIDERS)

            local msg1 = u8"Очередь заявок на выдачу ролей пуста"
            local msg2 = u8"Когда актёры отправят запрос на роль в рацию, заявка со скином и оружием появится здесь"
            local sz1 = imgui.CalcTextSize(msg1)
            local sz2 = imgui.CalcTextSize(msg2)
            dl:AddText(imgui.ImVec2(cx - sz1.x * 0.5, cy + 18), imgui.ColorConvertFloat4ToU32(t.text), msg1)
            dl:AddText(imgui.ImVec2(cx - sz2.x * 0.5, cy + 40), imgui.ColorConvertFloat4ToU32(t.textDim), msg2)
        imgui.EndChild()
        imgui.PopStyleColor(2)
        return
    end

    imgui.BeginChild("##rm_list_scroll", imgui.ImVec2(0, 0), false)
        for i, req in ipairs(role_requests) do
            imgui.PushID("role_req_" .. i)
            imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
            imgui.PushStyleColor(imgui.Col.Border, cardBorder)
            imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, 8.0)
            imgui.BeginChild("role_card_" .. i, imgui.ImVec2(0, 68), true)
                local tex = req.skin and loadSkinTexture(tonumber(req.skin))
                if tex then
                    imgui.Image(tex, imgui.ImVec2(48, 48))
                    imgui.SameLine(0, 12)
                end

                imgui.BeginGroup()
                    imgui.TextColored(t.accent, req.nick)
                    imgui.SameLine(0, 6)
                    imgui.TextColored(t.textDim, u8"[ID: " .. req.id .. "]")

                    local skinText   = req.skin or u8"нет"
                    local weaponText = req.weapon and (req.weapon .. " - " .. req.weaponName) or req.weaponName
                    local colorText  = req.color or u8"нет"
                    local armorText  = req.armor and u8"да" or u8"нет"
                    imgui.TextColored(t.textDim, u8"Скин: " .. skinText .. u8"   |   Оружие: " .. weaponText .. u8"   |   Клиcт: " .. colorText .. u8"   |   Броня: " .. armorText)
                imgui.EndGroup()

                imgui.SameLine(imgui.GetWindowWidth() - 175)
                local onCooldown = os.clock() < role_approve_cooldown_until
                if onCooldown then
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.35, 0.35, 0.35, 1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.35, 0.35, 0.35, 1.0))
                else
                    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.20, 0.65, 0.35, 1.0))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.28, 0.75, 0.44, 1.0))
                end
                if imgui.Button(fa.ICON_CHECK .. u8" Выдать##approve", imgui.ImVec2(115, 32)) and not onCooldown then
                    approveRoleRequest(i)
                end
                imgui.PopStyleColor(2)

                imgui.SameLine(0, 6)
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.65, 0.20, 0.20, 1.0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.78, 0.28, 0.28, 1.0))
                if imgui.Button(fa.ICON_TIMES .. "##cancel", imgui.ImVec2(36, 32)) then
                    removeRoleRequest(i)
                end
                imgui.PopStyleColor(2)
            imgui.EndChild()
            imgui.PopStyleVar()
            imgui.PopStyleColor(2)
            imgui.Dummy(imgui.ImVec2(1, 4))
            imgui.PopID()
        end
    imgui.EndChild()
end

local function drawTrackerTab(t)
    local cardBg = imgui.ImVec4(t.windowBg.x, t.windowBg.y, t.windowBg.z, 0.80)
    local cardBorder = imgui.ImVec4(t.border.x, t.border.y, t.border.z, 0.45)

    -- ------- левая колонка: стильное навигационное меню и сводка -------
    imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
    imgui.PushStyleColor(imgui.Col.Border, cardBorder)
    imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, 8.0)
    imgui.BeginChild("CuratorsList", imgui.ImVec2(245, 0), true)
        imgui.TextColored(t.accent, fa.ICON_CROSSHAIRS .. u8"  КУРАТОРЫ ИВЕНТОВ")
        imgui.Separator()
        imgui.Spacing()

        local dl = imgui.GetWindowDrawList()
        local w = imgui.GetContentRegionAvailWidth()

        local radCount = 0
        for _ in pairs(tracker_players) do radCount = radCount + 1 end
        local badges = {
            radCount > 0 and tostring(radCount) or (tracker_active and "ON" or nil),
            #curator_captured > 0 and tostring(#curator_captured) or (curator_active and "ON" or nil),
            #actors_captured > 0 and tostring(#actors_captured) or nil,
            #role_requests > 0 and tostring(#role_requests) or nil,
        }

        for i, sec in ipairs(CURATOR_SECTIONS) do
            local isActive = (curators_selected_section == i)
            local p = imgui.GetCursorScreenPos()
            local h = 50
            imgui.InvisibleButton("##curator_nav_" .. i, imgui.ImVec2(w, h))
            local hov = imgui.IsItemHovered()
            if imgui.IsItemClicked(0) then
                curators_selected_section = i
            end

            local bgAlpha = isActive and 0.65 or (hov and 0.50 or 0.28)
            dl:AddRectFilled(p, imgui.ImVec2(p.x + w, p.y + h),
                imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.frameBg.x, t.frameBg.y, t.frameBg.z, bgAlpha)), 6.0)

            if isActive then
                dl:AddRectFilled(p, imgui.ImVec2(p.x + 3.5, p.y + h), imgui.ColorConvertFloat4ToU32(t.accent), 3.0)
            end

            local cx, cy = p.x + 24, p.y + h * 0.5
            dl:AddCircleFilled(imgui.ImVec2(cx, cy), 13,
                imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, isActive and 0.28 or 0.14)), 20)
            local icSz = imgui.CalcTextSize(sec.icon)
            dl:AddText(imgui.ImVec2(cx - icSz.x * 0.5, cy - icSz.y * 0.5),
                imgui.ColorConvertFloat4ToU32(isActive and t.accent or t.textDim), sec.icon)

            dl:AddText(imgui.ImVec2(p.x + 45, p.y + 8),
                imgui.ColorConvertFloat4ToU32(isActive and t.text or t.textDim), sec.title)
            dl:AddText(imgui.ImVec2(p.x + 45, p.y + 27),
                imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.textDim.x, t.textDim.y, t.textDim.z, 0.72)), sec.sub)

            local bText = badges[i]
            if bText then
                local bSz = imgui.CalcTextSize(bText)
                local bW = math.max(22, bSz.x + 10)
                local bH = 18
                local bX = p.x + w - bW - 8
                local bY = p.y + 8
                dl:AddRectFilled(imgui.ImVec2(bX, bY), imgui.ImVec2(bX + bW, bY + bH),
                    imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.28)), 9.0)
                dl:AddText(imgui.ImVec2(bX + (bW - bSz.x) * 0.5, bY + 2), imgui.ColorConvertFloat4ToU32(t.accent), bText)
            end

            imgui.Dummy(imgui.ImVec2(1, 3))
        end

        -- Мини-сводка внизу боковой панели
        local remY = imgui.GetContentRegionAvail().y
        if remY > 90 then
            imgui.Dummy(imgui.ImVec2(1, remY - 88))
            imgui.Separator()
            imgui.Spacing()
            imgui.TextColored(t.textDim, fa.ICON_INFO_CIRCLE .. u8" Статус систем:")
            imgui.TextColored(tracker_active and imgui.ImVec4(0.30, 0.85, 0.45, 1.0) or t.textDim,
                u8"• Сбор радиуса: " .. (tracker_active and u8"Активен" or u8"Выкл"))
            imgui.TextColored(curator_active and imgui.ImVec4(0.30, 0.85, 0.45, 1.0) or t.textDim,
                u8"• Сбор кураторов: " .. (curator_active and u8"Активен" or u8"Выкл"))
            imgui.TextColored(#role_requests > 0 and imgui.ImVec4(0.95, 0.75, 0.25, 1.0) or t.textDim,
                u8"• Заявок на роли: " .. tostring(#role_requests))
        end
    imgui.EndChild()
    imgui.PopStyleVar()
    imgui.PopStyleColor(2)

    imgui.SameLine(0, 10)

    -- ------- правая колонка: содержимое выбранного раздела -------
    imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
    imgui.PushStyleColor(imgui.Col.Border, cardBorder)
    imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, 8.0)
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
    imgui.PopStyleVar()
    imgui.PopStyleColor(2)
end
drawGalleryTab = function(t)
    if imgui.Button(fa.ICON_RANDOM .. u8" Обновить##gallery_refresh", imgui.ImVec2(150, 28)) then
        scanGallery()
    end
    imgui.SameLine()
    imgui.TextColored(t.textDim, u8"Выбрано: " .. gallerySelectedCount() .. "/" .. GALLERY_MAX_SELECT)
    imgui.SameLine()
    if imgui.Checkbox(u8"Отправить лучшим качеством (документом)##gallery_send_as_doc", send_as_document) then
        saveSettings()
    end
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
                local tex = gallery_thumbnails[filename]
                if tex then
                    local avail = imgui.GetContentRegionAvail()
                    imgui.Image(tex, imgui.ImVec2(avail.x, avail.y))

                    if imgui.IsItemHovered() then
                        imgui.SetTooltip(u8"ЛКМ — открыть | Колёсико — выбрать | ПКМ — Действия")
                    end

                    if imgui.IsItemClicked() then
                        gallery_preview_open = true
                        gallery_preview_file = filename
                        loadGalleryFull(filename)
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
do
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
end

-- ---------- Окно просмотра отчёта ----------
report_viewer_idx = nil

drawReportsTab = function(t)
    if report_viewer_idx then
        local r = reports[report_viewer_idx]
        if not r then
            report_viewer_idx = nil
        else
            if imgui.Button(fa.ICON_ARROW_LEFT .. u8" Назад##report_back", imgui.ImVec2(110, 28)) then
                report_viewer_idx = nil
            end
            imgui.Spacing()
            imgui.TextColored(t.accent, r.event)
            imgui.TextColored(t.textDim, os.date("%d.%m.%Y  %H:%M", r.time))
            imgui.Spacing(); imgui.Separator(); imgui.Spacing()

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
            return
        end
    end

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
            report_viewer_idx = i
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip(u8"ЛКМ — открыть | Колёсико — удалить отчёт")
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
    imgui.GetIO().FontGlobalScale = 1.0
    if fa_font == nil then
        local font_config = imgui.ImFontConfig()
        font_config.MergeMode = true
        fa_font = imgui.GetIO().Fonts:AddFontFromFileTTF(
            'moonloader/resource/fonts/fontawesome-webfont.ttf',
            14.0, font_config, fa_glyph_ranges)
    end
    if arial_font == nil and not arial_font_failed then
        local font_path = getFolderPath(0x14) .. '\\arial.ttf'
        if doesFileExist(font_path) then
            local builder = imgui.ImFontAtlasGlyphRangesBuilder()
            builder:AddRanges(imgui.GetIO().Fonts:GetGlyphRangesCyrillic())
            local cyrillic_ranges = builder:BuildRanges()
            arial_font = imgui.GetIO().Fonts:AddFontFromFileTTF(font_path, 20.0, nil, cyrillic_ranges)
            arial_font_small = imgui.GetIO().Fonts:AddFontFromFileTTF(font_path, 15.0, nil, cyrillic_ranges)
        else
            arial_font_failed = true
        end
    end
end

-- ============================================================
--  ЛОГ РАЦИИ ИВЕНТА (/r и /rc) + ОТМЕТКИ РУКОВОДСТВА TRPCOMM
-- ============================================================
rlog = {
    messages = {},
    unread = false,
    filter_buf = imgui.ImBuffer("", 64),
    chat_input_buf = imgui.ImBuffer("", 144),
    only_staff = imgui.ImBool(false),
    only_ic = imgui.ImBool(false),
    auto_scroll = true,
    do_scroll = false,
    staff = {
        ["winfered_brown"]     = { role = u8"Глава TRPcomm",                color = imgui.ImVec4(0.96, 0.32, 0.32, 1.0), icon = fa.ICON_STAR },
        ["marquis_inferno"]    = { role = u8"Заместитель главы TRPcomm",    color = imgui.ImVec4(0.96, 0.56, 0.22, 1.0), icon = fa.ICON_STAR },
        ["sean_verstein"]      = { role = u8"Куратор актёров",              color = imgui.ImVec4(0.38, 0.76, 1.00, 1.0), icon = fa.ICON_USERS },
        ["hajimurad_ghaziyev"] = { role = u8"Заместитель куратора актёров", color = imgui.ImVec4(0.32, 0.86, 0.68, 1.0), icon = fa.ICON_USER_PLUS },
        ["brooks_wade"]        = { role = u8"Куратор HR отдела",            color = imgui.ImVec4(0.76, 0.52, 0.98, 1.0), icon = fa.ICON_BULLHORN },
    },
    staff_order = {
        { nick = "Winfered_Brown",     key = "winfered_brown" },
        { nick = "Marquis_Inferno",    key = "marquis_inferno" },
        { nick = "Sean_Verstein",      key = "sean_verstein" },
        { nick = "Hajimurad_Ghaziyev", key = "hajimurad_ghaziyev" },
        { nick = "Brooks_Wade",        key = "brooks_wade" },
    }
}

function rlog.reset()
    rlog.messages = {}
    rlog.unread = false
end

function rlog.onServerMessage(color, text)
    local clean = text:gsub("{%x%x%x%x%x%x}", "")
    if clean:find("^Connecting to ") or clean:find("^Connected%. Joining the game") or clean:find("Добро пожаловать на Trinity") then
        rlog.reset()
        return
    end
    local tag, nick, body = clean:match("^%[(R[C]?)%]%s*([^:]+):%s*(.+)$")
    if not tag then
        local freq, fnick, fbody = clean:match("^%[([%d%.]+%s*Hz)%]%s*([^:]+):%s*(.+)$")
        if freq then
            tag, nick, body = freq, fnick, fbody
        end
    end
    if not tag or not nick or not body then return end

    -- Извлекаем чистый Ник_Игрока (на случай если перед ним звание или после него [ID])
    local pureNick = nick:match("([%a%d]+_[%a%d]+)") or nick:gsub("^%s+", ""):gsub("%s+$", "")
    local isOoc = (body:match("^%(%(.*%)%)$") ~= nil)
    local staffInfo = rlog.staff[pureNick:lower()]

    rlog.messages[#rlog.messages + 1] = {
        time = os.date("%H:%M:%S"),
        tag = tag,
        nick = pureNick,
        rawNick = nick:gsub("^%s+", ""):gsub("%s+$", ""),
        text = body,
        isOoc = isOoc,
        isStaff = (staffInfo ~= nil),
    }
    if #rlog.messages > 300 then
        table.remove(rlog.messages, 1)
    end
    rlog.do_scroll = true

    local activeTab = open_tabs[active_tab_idx]
    if not main_window_state.v or not activeTab or activeTab.kind ~= "radiolog" then
        rlog.unread = true
    end
end

function rlog.drawTab(t)
    rlog.unread = false
    local avail = imgui.GetContentRegionAvail()
    local gap = 12
    local rightW = 265
    local leftW = avail.x - rightW - gap
    local cardBg = imgui.ImVec4(t.windowBg.x, t.windowBg.y, t.windowBg.z, 0.80)
    local cardBorder = imgui.ImVec4(t.border.x, t.border.y, t.border.z, 0.45)

    local online = {}
    for id = 0, sampGetMaxPlayerId(false) do
        if sampIsPlayerConnected(id) and not sampIsPlayerNpc(id) then
            local n = sampGetPlayerNickname(id)
            online[n:lower()] = id
        end
    end

    -- ============================================================
    --  ЛЕВАЯ КОЛОНКА: ПАНЕЛЬ ФИЛЬТРОВ, ЛЕНТА РАЦИИ И БЫСТРАЯ ОТПРАВКА
    -- ============================================================
    imgui.BeginGroup()

        -- 1. Верхняя панель управления логом
        imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
        imgui.PushStyleColor(imgui.Col.Border, cardBorder)
        imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, 8.0)
        imgui.BeginChild("##rlog_toolbar", imgui.ImVec2(leftW, 44), true)
            imgui.AlignTextToFramePadding()
            imgui.TextColored(t.accent, fa.ICON_BULLHORN .. u8" Рация")
            imgui.SameLine(85)
            imgui.PushItemWidth(175)
            imgui.InputText("##rlog_filter", rlog.filter_buf)
            imgui.PopItemWidth()
            if imgui.IsItemHovered() then imgui.SetTooltip(u8"Поиск по нику или тексту сообщения в рации") end

            imgui.SameLine(0, 8)
            if imgui.Checkbox(u8"Только руководство##rlog_only_staff", rlog.only_staff) then end
            imgui.SameLine(0, 8)
            if imgui.Checkbox(u8"Без OOC (/rc!)##rlog_only_ic", rlog.only_ic) then end

            imgui.SameLine(leftW - 102)
            if imgui.Button(fa.ICON_TRASH_O .. u8" Очистить##rlog_clear", imgui.ImVec2(92, 24)) then
                rlog.messages = {}
            end
        imgui.EndChild()
        imgui.PopStyleVar()
        imgui.PopStyleColor(2)

        imgui.Spacing()

        -- 2. Лента сообщений рации
        local feedH = imgui.GetContentRegionAvail().y - 46
        imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
        imgui.PushStyleColor(imgui.Col.Border, cardBorder)
        imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, 8.0)
        imgui.BeginChild("##rlog_feed", imgui.ImVec2(leftW, feedH), true)

            local rawFilter = u8:decode(rlog.filter_buf.v):gsub("^%s+", ""):gsub("%s+$", ""):lower()
            local shown = 0
            local dl = imgui.GetWindowDrawList()

            for idx, m in ipairs(rlog.messages) do
                local passStaff = (not rlog.only_staff.v) or m.isStaff
                local passIc    = (not rlog.only_ic.v) or (not m.isOoc)
                local passText  = (rawFilter == "") or m.nick:lower():find(rawFilter, 1, true) or m.text:lower():find(rawFilter, 1, true)

                if passStaff and passIc and passText then
                    shown = shown + 1
                    local st = rlog.staff[m.nick:lower()]
                    local rowBgCol = st
                        and imgui.ImVec4(st.color.x * 0.25, st.color.y * 0.25, st.color.z * 0.25, 0.55)
                        or imgui.ImVec4(t.frameBg.x, t.frameBg.y, t.frameBg.z, 0.35)
                    local brdCol = st
                        and imgui.ImVec4(st.color.x, st.color.y, st.color.z, 0.65)
                        or imgui.ImVec4(t.border.x, t.border.y, t.border.z, 0.30)

                    imgui.PushStyleColor(imgui.Col.ChildWindowBg, rowBgCol)
                    imgui.PushStyleColor(imgui.Col.Border, brdCol)
                    imgui.BeginChild("##rlog_msg_" .. idx, imgui.ImVec2(-1, 50), true)
                        local p = imgui.GetCursorScreenPos()
                        if st then
                            dl:AddRectFilled(imgui.ImVec2(p.x - 8, p.y - 6), imgui.ImVec2(p.x - 4, p.y + 42),
                                imgui.ColorConvertFloat4ToU32(st.color), 2.0)
                        end

                        -- Строка 1: Время, канал [R]/[RC], Никнейм и бейдж должности
                        imgui.TextColored(t.textDim, m.time)
                        imgui.SameLine(0, 6)
                        local tagCol = m.isOoc and imgui.ImVec4(0.65, 0.72, 0.82, 0.9) or imgui.ImVec4(0.35, 0.88, 0.50, 1.0)
                        imgui.TextColored(tagCol, "[" .. u8(m.tag) .. "]")
                        imgui.SameLine(0, 6)
                        imgui.TextColored(st and st.color or t.text, u8(m.nick))

                        if st then
                            imgui.SameLine(0, 8)
                            local badgeStr = st.icon .. " " .. st.role
                            local bSz = imgui.CalcTextSize(badgeStr)
                            local bp = imgui.GetCursorScreenPos()
                            dl:AddRectFilled(imgui.ImVec2(bp.x, bp.y - 1), imgui.ImVec2(bp.x + bSz.x + 12, bp.y + 17),
                                imgui.ColorConvertFloat4ToU32(imgui.ImVec4(st.color.x, st.color.y, st.color.z, 0.24)), 4.0)
                            dl:AddText(imgui.ImVec2(bp.x + 6, bp.y), imgui.ColorConvertFloat4ToU32(st.color), badgeStr)
                            imgui.Dummy(imgui.ImVec2(bSz.x + 14, 16))
                        end

                        -- Строка 2: Текст сообщения
                        imgui.TextColored(m.isOoc and t.textDim or imgui.ImVec4(0.96, 0.98, 1.0, 1.0), u8(m.text))

                        if imgui.IsWindowHovered() and imgui.IsMouseClicked(1) then
                            imgui.SetClipboardText(u8(m.nick .. ": " .. m.text))
                            showToast("Сообщение скопировано")
                        end
                    imgui.EndChild()
                    imgui.PopStyleColor(2)
                    imgui.Dummy(imgui.ImVec2(1, 2))
                end
            end

            if shown == 0 then
                local eAvail = imgui.GetContentRegionAvail()
                local wp = imgui.GetCursorScreenPos()
                local cx, cy = wp.x + eAvail.x * 0.5, wp.y + eAvail.y * 0.42
                dl:AddCircleFilled(imgui.ImVec2(cx, cy - 16), 24,
                    imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.14)), 24)
                local icSz = imgui.CalcTextSize(fa.ICON_COMMENTS_O)
                dl:AddText(imgui.ImVec2(cx - icSz.x * 0.5, cy - 16 - icSz.y * 0.5),
                    imgui.ColorConvertFloat4ToU32(t.accent), fa.ICON_COMMENTS_O)
                local msg1 = u8"Сообщений в логе рации пока нет"
                local msg2 = u8"Все сообщения из рации (/rc и /rc!) автоматически записываются сюда с отметками руководства"
                local sz1, sz2 = imgui.CalcTextSize(msg1), imgui.CalcTextSize(msg2)
                dl:AddText(imgui.ImVec2(cx - sz1.x * 0.5, cy + 16), imgui.ColorConvertFloat4ToU32(t.text), msg1)
                dl:AddText(imgui.ImVec2(cx - sz2.x * 0.5, cy + 36), imgui.ColorConvertFloat4ToU32(t.textDim), msg2)
            end

            if rlog.do_scroll then
                imgui.SetScrollHere(1.0)
                rlog.do_scroll = false
            end

        imgui.EndChild()
        imgui.PopStyleVar()
        imgui.PopStyleColor(2)

        imgui.Spacing()

        -- 3. Нижняя строка быстрой отправки в рацию (/r или /rc)
        imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
        imgui.PushStyleColor(imgui.Col.Border, cardBorder)
        imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, 8.0)
        imgui.BeginChild("##rlog_send_bar", imgui.ImVec2(leftW, 38), true)
            imgui.PushItemWidth(leftW - 210)
            local enterPressed = imgui.InputText("##rlog_input_msg", rlog.chat_input_buf, imgui.InputTextFlags.EnterReturnsTrue)
            imgui.PopItemWidth()

            local function sendToRadio(cmdPrefix)
                local raw = u8:decode(rlog.chat_input_buf.v):gsub("^%s+", ""):gsub("%s+$", "")
                if raw ~= "" then
                    sampSendChat(cmdPrefix .. " " .. raw)
                    rlog.chat_input_buf.v = ""
                end
            end

            if enterPressed then sendToRadio("/rc") end

            imgui.SameLine(0, 6)
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.20, 0.62, 0.35, 1.0))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.28, 0.72, 0.44, 1.0))
            if imgui.Button(fa.ICON_PAPER_PLANE .. u8" В /rc##rlog_btn_r", imgui.ImVec2(88, 24)) then
                sendToRadio("/rc")
            end
            imgui.PopStyleColor(2)

            imgui.SameLine(0, 6)
            if imgui.Button(fa.ICON_COMMENT_O .. u8" В /rc!##rlog_btn_rc", imgui.ImVec2(88, 24)) then
                sendToRadio("/rc!")
            end
        imgui.EndChild()
        imgui.PopStyleVar()
        imgui.PopStyleColor(2)

    imgui.EndGroup()

    -- ============================================================
    --  ПРАВАЯ КОЛОНКА: ОТМЕТКИ РУКОВОДСТВА И КУРАТОРОВ TRPCOMM
    -- ============================================================
    imgui.SameLine(0, gap)
    imgui.BeginGroup()

        imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
        imgui.PushStyleColor(imgui.Col.Border, cardBorder)
        imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, 8.0)
        imgui.BeginChild("##rlog_staff_panel", imgui.ImVec2(rightW, 0), true)

            imgui.TextColored(t.accent, fa.ICON_SHIELD .. u8"  РУКОВОДСТВО TRPCOMM")
            imgui.Separator()
            imgui.Spacing()

            local dl = imgui.GetWindowDrawList()
            local w = imgui.GetContentRegionAvailWidth()

            for i, item in ipairs(rlog.staff_order) do
                local st = rlog.staff[item.key]
                local pid = online[item.key]
                local isOn = (pid ~= nil)
                local p = imgui.GetCursorScreenPos()
                local h = 52
                imgui.InvisibleButton("##staff_card_" .. i, imgui.ImVec2(w, h))
                local hov = imgui.IsItemHovered()
                if imgui.IsItemClicked(0) then
                    -- Клик по карточке фильтрует лог по этому руководителю (повторный клик сбрасывает)
                    local curF = u8:decode(rlog.filter_buf.v)
                    if curF:lower() == item.key then
                        rlog.filter_buf.v = ""
                    else
                        rlog.filter_buf.v = u8(item.nick)
                    end
                end
                if hov then
                    imgui.SetTooltip(u8"ЛКМ — показать в логе только сообщения от " .. item.nick)
                end

                local bgAlpha = hov and 0.65 or 0.38
                dl:AddRectFilled(p, imgui.ImVec2(p.x + w, p.y + h),
                    imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.frameBg.x, t.frameBg.y, t.frameBg.z, bgAlpha)), 6.0)
                dl:AddRectFilled(p, imgui.ImVec2(p.x + 3.5, p.y + h),
                    imgui.ColorConvertFloat4ToU32(st.color), 3.0)

                -- Иконка в кружке
                local cx, cy = p.x + 22, p.y + h * 0.5
                dl:AddCircleFilled(imgui.ImVec2(cx, cy), 13,
                    imgui.ColorConvertFloat4ToU32(imgui.ImVec4(st.color.x, st.color.y, st.color.z, 0.20)), 20)
                local icSz = imgui.CalcTextSize(st.icon)
                dl:AddText(imgui.ImVec2(cx - icSz.x * 0.5, cy - icSz.y * 0.5),
                    imgui.ColorConvertFloat4ToU32(st.color), st.icon)

                -- Никнейм + статус онлайн
                dl:AddText(imgui.ImVec2(p.x + 42, p.y + 8), imgui.ColorConvertFloat4ToU32(t.text), item.nick)

                -- Индикатор сети справа вверху
                local dotCol = isOn and imgui.ImVec4(0.28, 0.90, 0.48, 1.0) or imgui.ImVec4(0.50, 0.52, 0.58, 0.65)
                local statusStr = isOn and ("ID " .. tostring(pid)) or u8"Оффлайн"
                local stSz = imgui.CalcTextSize(statusStr)
                dl:AddCircleFilled(imgui.ImVec2(p.x + w - stSz.x - 16, p.y + 15), 3.5, imgui.ColorConvertFloat4ToU32(dotCol), 12)
                dl:AddText(imgui.ImVec2(p.x + w - stSz.x - 8, p.y + 8), imgui.ColorConvertFloat4ToU32(isOn and dotCol or t.textDim), statusStr)

                -- Должность
                dl:AddText(imgui.ImVec2(p.x + 42, p.y + 28), imgui.ColorConvertFloat4ToU32(st.color), st.role)

                imgui.Dummy(imgui.ImVec2(1, 3))
            end

            imgui.Spacing()
            imgui.Separator()
            imgui.Spacing()
            imgui.TextColored(t.textDim, fa.ICON_INFO_CIRCLE .. u8" Подсказка:")
            imgui.TextWrapped(u8"Сообщения руководства и кураторов автоматически выделяются цветом и именной плашкой в общем потоке рации. ПКМ по сообщению копирует его.")

        imgui.EndChild()
        imgui.PopStyleVar()
        imgui.PopStyleColor(2)

    imgui.EndGroup()
end
calendar_tab_active_last_frame = false
curator_section_active_last_frame = false

function imgui.OnDrawFrame()
    if qsms and qsms.onDrawFrame then
        qsms.onDrawFrame()
    end
    if not main_window_state.v then
        calendar_tab_active_last_frame = false
        curator_section_active_last_frame = false
        return
    end

    local t = getTheme()
    local sw, sh = getScreenResolution()
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(1060, 580), imgui.Cond.Always)

    pushThemeColors()
    pushThemeRounding()

    imgui.Begin("##trpcomm_main", main_window_state,
        imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoTitleBar)

        imgui.TextColored(t.accent, u8 "TRPCOMM MANAGER")
        imgui.SameLine()
        imgui.TextColored(t.textDim, u8 "•  Версия 3.0")

        -- Компактная квадратная кнопка закрытия
        imgui.SameLine(imgui.GetWindowWidth() - 28)
        imgui.PushStyleVar(imgui.StyleVar.FrameRounding, 2.0)
        imgui.PushStyleVar(imgui.StyleVar.FramePadding, imgui.ImVec2(0, 0))
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(t.panelBg.x, t.panelBg.y, t.panelBg.z, 0.45))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.85, 0.25, 0.25, 0.90))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.95, 0.30, 0.30, 1.0))
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.75, 0.80, 0.88, 0.90))
        if imgui.Button(fa.ICON_TIMES .. "##win_close", imgui.ImVec2(18, 18)) then
            main_window_state.v = false
        end
        imgui.PopStyleColor(4)
        imgui.PopStyleVar(2)
        if imgui.IsItemHovered() then
            imgui.SetTooltip(u8"Закрыть меню (ESC)")
        end

        imgui.Separator()
        imgui.Spacing()

        -- ---------- Строка вкладок ----------
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

            imgui.SameLine(imgui.GetWindowWidth() - 132)
            local hasNewRadio = rlog and rlog.unread
            if hasNewRadio then
                imgui.PushStyleColor(imgui.Col.Button, t.accent)
            end
            if imgui.Button(fa.ICON_BULLHORN, imgui.ImVec2(30, 22)) then
                openTab("radiolog", u8"Лог рации")
            end
            if hasNewRadio then
                imgui.PopStyleColor()
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip(u8"Лог рации ивента (/rc, /rc!) и руководство TRPcomm")
            end
            imgui.SameLine(0, 2)
            local hasNewSms = qsms and qsms.new
            if hasNewSms then
                imgui.PushStyleColor(imgui.Col.Button, t.accent)
            end
            if imgui.Button(fa.ICON_ENVELOPE, imgui.ImVec2(30, 22)) then
                openTab("quicksms", u8"Мессенджер")
            end
            if hasNewSms then
                imgui.PopStyleColor()
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip(u8"Мессенджер — Сообщения и автоответчик (/smss)")
            end
            imgui.SameLine(0, 2)
            if imgui.Button(fa.ICON_CALENDAR, imgui.ImVec2(30, 22)) then
                openTab("calendar", u8"Календарь")
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
            local RESTRICTED_SECTIONS = { photographer = true, tracker = true, hr = true, advertising = true, roles = true, quicksms = true }
            local ACCESS_KEY_BY_KIND = {
                roles = "actors",
                photographer = "photographers",
                tracker = "curators",
                hr = "advertising",
                advertising = "advertising",
                quicksms = "advertising",
            }

            if activeTab and RESTRICTED_SECTIONS[activeTab.kind] then
                local accessKey = ACCESS_KEY_BY_KIND[activeTab.kind] or activeTab.kind
                if access_lists[accessKey] == nil then
                    imgui.TextColored(t.textDim, u8"Проверка доступа...")
                elseif not hasAccess(accessKey) then
                    imgui.Spacing()
                    imgui.TextColored(t.textDim, u8"У вас нет доступа к этому разделу.")
                    activeTab = nil
                end
            end

            if activeTab then
                if activeTab.kind == "home" then
                    drawHomeTab(t)
                elseif activeTab.kind == "notes" then
                    drawNotesTab(t)
                elseif activeTab.kind == "roles" and hasAccess("actors") then
                    drawRolesTab(t)
                elseif activeTab.kind == "settings" then
                    drawSettingsTab(t)
                elseif activeTab.kind == "photographer" and hasAccess("photographers") then
                    drawPhotographerTab(t)
                elseif activeTab.kind == "tracker" and hasAccess("curators") then
                    drawTrackerTab(t)
                elseif (activeTab.kind == "hr" or activeTab.kind == "advertising") and (hasAccess("advertising") or hasAccess("hr")) then
                    drawHRTab(t)
                elseif activeTab.kind == "calendar" then
                    drawHRCalendarTab(t)
                elseif activeTab.kind == "radiolog" then
                    if rlog and rlog.drawTab then
                        rlog.drawTab(t)
                    end
                elseif activeTab.kind == "quicksms" and (hasAccess("advertising") or hasAccess("hr")) then
                    if qsms and qsms.drawTab then
                        qsms.drawTab(t)
                    end
                end
            end
        imgui.EndChild()

    imgui.End()
    imgui.PopStyleVar(THEME_ROUNDING_COUNT)
    imgui.PopStyleColor(THEME_COLOR_COUNT)

    drawGalleryPreview(t)
    drawGallerySendReportForm(t)
    drawTrackerCreateReportForm(t)
    drawAdAddForm(t)
end

sampev.onShowDialog = function(dialogId, style, title, button1, button2, text)
    local cleanText = text and text:gsub("{%x%x%x%x%x%x}", "") or ""
    local cleanTitle = title and title:gsub("{%x%x%x%x%x%x}", "") or ""

    -- 1. Предыдущее объявление ещё в очереди (только когда отправка объявлений TRPcomm активна)
    if (ad_pending or ad_awaiting_next_city or ad_auto_send.v) and (cleanText:find("уже находится в очереди") or cleanText:find("Одно из ваших объявлений уже") or (dialogId == 45 and cleanText:find("уже находится"))) then
        ad_pending = false
        ad_pending_deadline = 0
        ad_awaiting_next_city = false
        ad_pending_cities = {}
        ad_pending_city_pos = 0
        sampSendDialogResponse(dialogId, 1, 0, "")
        showToast("Предыдущее объявление ещё в очереди.")
        if ad_auto_send.v then
            ad_next_send_time = os.time() + (ad_interval_minutes.v * 60) + 2
        end
        return false
    end

    -- 2. В процессе отправки объявления
    if ad_pending then
        if dialogId == 3409 and (cleanTitle:find("Создание объявления") or cleanTitle:find("Создание")) then
            ad_pending_deadline = os.time() + 2
            sampSendDialogResponse(dialogId, 1, 0, "")
            return false
        end
        if dialogId == 3410 and (cleanTitle:find("Отправка рекламы") or cleanTitle:find("радио")) then
            ad_pending_deadline = 0
            sampSendDialogResponse(dialogId, 1, 0, ad_pending_text)
            showToast('Объявление отправлено.')
            incrementAdSentCount(ad_pending_text)
            logAdHistory(ad_pending_text, ad_pending_source, ad_pending_event_label)
            ad_text.v = ""
            ad_awaiting_next_city = true
            ad_next_city_at = os.time() + 3
            return false
        end
        -- Уведомление об успешной отправке (репортер / в очередь публикации / без модерации / диалог 3412 / диалог 45)
        if cleanText:find("репортер")
            or cleanText:find("отправлено в очередь")
            or cleanText:find("в очередь публикации")
            or cleanText:find("в очередь на публикацию")
            or cleanText:find("без модерации")
            or cleanTitle:find("без модерации")
            or dialogId == 3412
            or (dialogId == 45 and cleanText:find("Ваше объявление")) then
            sampSendDialogResponse(dialogId, 1, 0, "")
            advanceAfterNewsPopup()
            return false
        end
    elseif ad_awaiting_next_city then
        if cleanText:find("репортер")
            or cleanText:find("отправлено в очередь")
            or cleanText:find("в очередь публикации")
            or cleanText:find("в очередь на публикацию")
            or cleanText:find("без модерации")
            or cleanTitle:find("без модерации")
            or dialogId == 3412
            or (dialogId == 45 and cleanText:find("Ваше объявление")) then
            sampSendDialogResponse(dialogId, 1, 0, "")
            advanceAfterNewsPopup()
            return false
        end
    else
        -- Попап об авто-отправке репортёра, даже если пришёл вне ad_pending
        if cleanText:find("репортер") and (cleanText:find("очередь публикации") or cleanText:find("отправлено")) then
            sampSendDialogResponse(dialogId, 1, 0, "")
            return false
        end
    end
end

sampev.onSetPlayerAttachedObject = function(id, index, create, object)
    local ok, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if ok then
        if ((id == myId and acs_rem_me.v) or (id ~= myId and acs_rem.v)) and create then
            return false
        end
    end
end

function onReceivePacket(id, bs)
    if (id == 32 or id == 33 or id == 34 or id == 36 or id == 37) and rlog and rlog.reset then
        rlog.reset()
    end
    if id == 220 then
        raknetBitStreamIgnoreBits(bs, 8)
        local type = raknetBitStreamReadInt8(bs)
        if type == 155 then
            local playerId = raknetBitStreamReadInt16(bs)
            local index = raknetBitStreamReadInt32(bs)
            local create = raknetBitStreamReadBool(bs)
            local ok, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
            if ok then
                if ((playerId == myId and acs_rem_me.v) or (playerId ~= myId and acs_rem.v)) and create then
                    return false
                end
            end
        end
    end
end

local function parseRetrySeconds(text)
    local min = text:match("через (%d+) мин")
    if min then return tonumber(min) * 60 end
    local sec = text:match("через (%d+) сек")
    if sec then return tonumber(sec) end
    return nil
end

sampev.onServerMessage = function(color, text)
    if rlog and rlog.onServerMessage then
        rlog.onServerMessage(color, text)
    end
    if qsms and qsms.onServerMessage then
        if qsms.onServerMessage(color, text) == false then
            return false
        end
    end
    -- Синхронизация времени сервера (по МСК) при сообщениях сервера / командах
    local th, tm, ts = text:match("([012]?%d):([0-5]%d):?([0-5]?%d?)")
    if (text:find("Время") or text:find("время") or text:find("часах")) and th and tm then
        th, tm = tonumber(th), tonumber(tm)
        ts = tonumber(ts) or 0
        local expectedNow = os.date("!*t", os.time() + SERVER_TZ_OFFSET_SEC)
        local diffSec = (th * 3600 + tm * 60 + ts) - (expectedNow.hour * 3600 + expectedNow.min * 60 + expectedNow.sec)
        if math.abs(diffSec) < 43200 then
            server_time_offset = diffSec
        end
    end

    if text:find("Вы находитесь слишком далеко от игрока") then
        role_approve_distance_error = true
    end

    if (ad_pending or ad_awaiting_next_city or ad_auto_send.v) and text:find("Одно из ваших объявлений уже находится в очереди") then
        ad_pending = false
        ad_pending_deadline = 0
        ad_awaiting_next_city = false
        ad_pending_cities = {}
        ad_pending_city_pos = 0
        if ad_auto_send.v then
            ad_next_send_time = os.time() + (ad_interval_minutes.v * 60) + 2
        end
        showToast("Предыдущее объявление ещё в очереди.")
    elseif ad_pending then
        if text:find("Нельзя отправлять рекламу на радио слишком часто") then
            local waitSec = parseRetrySeconds(text) or 60
            ad_pending_deadline = 0
            lua_thread.create(function()
                wait((waitSec + 2) * 1000)
                retryCurrentCity()
            end)
        elseif text:find("Ваш мобильный телефон выключен") then
            ad_pending = false
            if ad_auto_send.v then
                ad_auto_send.v = false
                saveSettings()
            end
            showToast("Телефон выключен — отправка объявлений невозможна. Автоотправка остановлена.")
        end
    end

    if actors_active then
        local clean = text:gsub("{%x%x%x%x%x%x}", "")
        local nick = clean:match("Ник[:%s]+([%w_]+)") or clean:match("%[.+%]%s+([%w_]+)")
        if nick then
            nick = nick:gsub("%.", ""):gsub("%s+", "")
            local already = false
            for _, existing in ipairs(actors_captured) do
                if existing:lower() == nick:lower() then already = true; break end
            end
            if not already then
                actors_captured[#actors_captured + 1] = nick
            end
            return false
        end
    end

        do
                local clean = text:gsub("{%x%x%x%x%x%x}", "")
        local nick, pid, skinRaw, weaponRaw, colorRaw, armorRaw = clean:match(
            "%[RC%] ([%w_]+): Мой ID: (%d+) | Скин: ([^|]+) | Оружие: ([^|]+) | Клист: ([^|]+) | Бронежилет: ([^|]+)"
        )
        if nick then
            skinRaw   = skinRaw:match("^%s*(.-)%s*$")
            weaponRaw = weaponRaw:match("^%s*(.-)%s*$")
            colorRaw  = colorRaw:match("^%s*(.-)%s*$")
            armorRaw  = armorRaw:match("^%s*(.-)%s*$")

            local weaponUtf8 = u8(weaponRaw)
            local weaponId, weaponName = nil, weaponUtf8
            for _, w in ipairs(weapon_list) do
                local wid, wname = w:match("^(%d+) %- (.+)$")
                if wid and wname == weaponUtf8 then
                    weaponId = wid
                    break
                end
            end

            addOrUpdateRoleRequest({
                id = pid,
                nick = nick,
                skin = (skinRaw ~= "нет") and skinRaw or nil,
                weapon = weaponId,
                weaponName = weaponName,
                color = (colorRaw ~= "нет") and colorRaw or nil,
                armor = (armorRaw == "да"),
            })
            -- не возвращаем false — строка остаётся видна в обычном чате
        end
    end
end

-- ============================================================
--  ТОЧКА ВХОДА
-- ============================================================
-- ============================================================
--  МОДУЛЬ QUICK SMS - TRINITY (ВСТРОЕННЫЙ В МЕНЮ TRPCOMM)
-- ============================================================
qsms = {}
do
    local lfs = require("lfs")
    local ok_mcfg, mcfg_mod = pcall(require, "mcfg")
    if not ok_mcfg or not mcfg_mod then
        local function draw_string(str) return string.format("%q", str) end
        local function draw_key(key)
            if "string" == type(key) and key:match("^[_%a][_%a%d]*$") then return key
            elseif "number" == type(key) then return "["..key.."]"
            else return "["..draw_string(key).."]" end
        end
        local function draw_table(tbl, tab)
            tab = tab or ""
            local result = {}
            for key, value in pairs(tbl) do
                if type(value) == "string" then
                    if type(key) == "number" and key <= #tbl then table.insert(result, draw_string(value))
                    else table.insert(result, draw_key(key).." = "..draw_string(value)) end
                elseif type(value) == "number" or type(value) == "boolean" then
                    if type(key) == "number" and key <= #tbl then table.insert(result, tostring(value))
                    else table.insert(result, draw_key(key).." = "..tostring(value)) end
                elseif type(value) == "table" then
                    if type(key) == "number" and key <= #tbl then table.insert(result, draw_table(value, tab.."\t"))
                    else table.insert(result, draw_key(key).." = "..draw_table(value, tab.."\t")) end
                else
                    if type(key) == "number" and key <= #tbl then table.insert(result, draw_string(tostring(value)))
                    else table.insert(result, draw_key(key).." = "..draw_string(tostring(value))) end
                end
            end
            if #result == 0 and tab == "" then return ""
            elseif #result == 0 then return "{}"
            elseif tab == "" then return table.concat(result, ",\n")..",\n"
            else return "{\n"..tab..table.concat(result, ", \n"..tab)..",\n"..tab:sub(2).."}" end
        end
        local function draw_value(value, tab)
            if type(value) == "string" then return draw_string(value)
            elseif type(value) == "number" or type(value) == "boolean" or type(value) == "nil" then return tostring(value)
            elseif type(value) == "table" then return draw_table(value, tab)
            else return draw_string(tostring(value)) end
        end
        mcfg_mod = {}
        function mcfg_mod.mkpath(filename)
            local sep, pStr = package.config:sub(1, 1), ""
            local path = filename:match("(.+"..sep..").+$") or filename
            for dir in path:gmatch("[^" .. sep .. "]+") do
                pStr = pStr .. dir .. sep
                createDirectory(pStr)
            end
        end
        function mcfg_mod.load(filename)
            local file = io.open(filename, "r")
            if file then
                local text = file:read("*all")
                file:close()
                local lua_code = loadstring("return {"..text.."}")
                if lua_code then
                    local ok, result = pcall(lua_code)
                    if ok and type(result) == "table" then return result end
                end
            end
        end
        function mcfg_mod.save(updated, filename)
            mcfg_mod.mkpath(filename)
            local file = io.open(filename, "w+")
            if file then
                file:write(draw_table(updated))
                file:close()
                return true
            end
            return false
        end
        function mcfg_mod.append_value(value, filename)
            mcfg_mod.mkpath(filename)
            local file = io.open(filename, "a+")
            if file then
                file:write(draw_value(value, "\t")..",\n")
                file:close()
                return true
            end
            return false
        end
        function mcfg_mod.update(original, update, rewrite)
            if rewrite == nil then rewrite = true end
            local loaded = type(update) == "table" and update or (type(update) == "string" and mcfg_mod.load(update))
            if loaded then
                for key, value in pairs(loaded) do
                    if rewrite or not original[key] then original[key] = value end
                end
                return true
            end
            return false
        end
    end
    qsms.mcfg = mcfg_mod
    qsms.lfs = lfs
    qsms.__name__ = "Quick SMS - Trinity"
    qsms.MAIN_TITLE = "Мессенджер"
    qsms.MAIN_CMD = "smss"

    function imgui.ButtonActivated(activated, ...)
        if activated then
            local t = getTheme()
            imgui.PushStyleColor(imgui.Col.Button, t.accent)
            imgui.PushStyleColor(imgui.Col.ButtonHovered, t.accent)
            imgui.PushStyleColor(imgui.Col.ButtonActive, t.accent)
            local res = imgui.Button(...)
            imgui.PopStyleColor(3)
            return res
        else
            return imgui.Button(...)
        end
    end

    function imgui.DotGreen(bool)
        imgui.PushStyleColor(imgui.Col.FrameBgHovered, imgui.GetStyle().Colors[imgui.Col.Button])
        imgui.PushStyleColor(imgui.Col.FrameBgActive, imgui.GetStyle().Colors[imgui.Col.Button])
        imgui.PushStyleColor(imgui.Col.CheckMark, imgui.ImVec4(0.20, 0.85, 0.35, 1.00))
        if bool then
            imgui.RadioButton("", true)
        else
            imgui.RadioButton("", false)
        end
        imgui.PopStyleColor(3)
    end

    function imgui.WrapText(str, width)
        if imgui.CalcTextSize(str).x < width then
            return str
        end
        local lines = {}
        for word in str:gmatch("%s*%S*%s*") do
            if lines[#lines] and imgui.CalcTextSize(lines[#lines]..word).x < width then
                lines[#lines] = lines[#lines]..word
            else
                if imgui.CalcTextSize(word).x > width then
                    for symbol in u8:decode(word):gmatch(".") do
                        if lines[#lines] and imgui.CalcTextSize(lines[#lines]..u8(symbol)).x < width then
                            lines[#lines] = lines[#lines]..u8(symbol)
                        else
                            table.insert(lines, u8(symbol))
                        end
                    end
                else
                    table.insert(lines, word)
                end
            end
        end
        return table.concat(lines, "\n")
    end

    imgui.Bubble = {
        _clicked_clock = nil,
        _clicked_id = nil,
        _hovered_clock = nil,
        _hovered_id = nil,
    }
    setmetatable(imgui.Bubble, {__call = function(self, id, color, text, text_hovered, text_clicked, right)
        local ms = 1500
        local delay = 600
        local style = imgui.GetStyle()
        local border_heigth = (1*2) + (style.WindowPadding.y*2)
        local border_width = (1*2) + (style.WindowPadding.x*2)
        local field_width = imgui.GetWindowWidth() - style.ScrollbarSize - 10
        local bubble_max_width = math.floor(field_width/3*2)
        text = imgui.WrapText(text, math.max(60, bubble_max_width - border_width))
        local text_size = imgui.CalcTextSize(text)
        local bubble_width = math.min(math.max(text_size.x) + border_width, field_width)
        local bubble_heigth = text_size.y + border_heigth
        if right then
            imgui.SetCursorPosX(math.max(0, field_width - bubble_width))
        end
        imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, 8)
        imgui.PushStyleColor(imgui.Col.ChildWindowBg, color)
        imgui.BeginChild(id, imgui.ImVec2(bubble_width, bubble_heigth), true, imgui.WindowFlags.NoInputs)
            imgui.PushStyleVar(imgui.StyleVar.ItemSpacing, imgui.ImVec2(0, 0))
            imgui.PopStyleVar()
            imgui.Text(text)
        imgui.EndChild()
        imgui.PopStyleColor()
        imgui.PopStyleVar()
        local clicked = imgui.IsItemClicked()
        local hovered = imgui.IsItemHovered()
        if text_clicked then
            if clicked then
                self._clicked_clock = os.clock()
                self._clicked_id = id
            end
            if imgui.IsItemHovered() then
                if self._clicked_clock then
                    if self._clicked_id == id and (os.clock() - self._clicked_clock) < (ms / 1000) then
                        imgui.BeginTooltip()
                        imgui.Text(text_clicked)
                        imgui.EndTooltip()
                    else
                        self._clicked_clock = nil
                    end
                end
            elseif self._clicked_id == id then
                self._clicked_clock = nil
            end
        end
        if hovered then
            if self._hovered_id ~= id then
                self._hovered_clock = nil
            end
            if not self._hovered_clock then
                self._hovered_clock = os.clock()
                self._hovered_id = id
            end
            if text_hovered and not self._clicked_clock then
                if (os.clock() - self._hovered_clock) > (delay / 1000) then
                    imgui.BeginTooltip()
                    imgui.PushTextWrapPos(640)
                    imgui.TextUnformatted(text_hovered)
                    imgui.PopTextWrapPos()
                    imgui.EndTooltip()
                end
            end
        elseif self._hovered_id == id then
            self._hovered_clock = nil
        end
        return clicked
    end})

    function imgui.ButtonClickable(clickable, ...)
        if clickable then
            return imgui.Button(...)
        else
            local r, g, b, a = imgui.ImColor(imgui.GetStyle().Colors[imgui.Col.Button]):GetFloat4()
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(r, g, b, a/2))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(r, g, b, a/2))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(r, g, b, a/2))
            imgui.PushStyleColor(imgui.Col.Text, imgui.GetStyle().Colors[imgui.Col.TextDisabled])
                imgui.Button(...)
            imgui.PopStyleColor(4)
        end
    end

    local function initHKeys()
        local self = {}
        local vkeys = require 'vkeys'
        local wm = require 'lib.windows.message'
        local bitex = require "bitex"
        self.VK_WHEELDOWN = 0x100
        self.VK_WHEELUP = 0x101
        self.KEYS = {
            VK_WHEELDOWN = self.VK_WHEELDOWN,
            VK_WHEELUP = self.VK_WHEELUP
        }
        self.NAMES = {
            [self.KEYS.VK_WHEELDOWN] = "Wheel Down",
            [self.KEYS.VK_WHEELUP] = "Wheel Up",
        }
        for key, value in pairs(vkeys) do
            if key:sub(1, 3) == 'VK_' then
                self.KEYS[key] = value
                self[key] = value
            end
        end
        for key, value in pairs(vkeys.key_names) do
            self.NAMES[key] = value
        end
        function self.id_to_name(vkey)
            local name = self.NAMES[vkey]
            if type(name) == 'table' then
                return name[1]
            end
            return name
        end
        function self.name_to_id(keyname, case_sensitive)
            if not case_sensitive then
                keyname = string.upper(keyname)
            end
            for id, v in pairs(self.NAMES) do
                if type(v) == 'table' then
                    for _, v2 in pairs(v) do
                        v2 = (case_sensitive) and v2 or string.upper(v2)
                        if v2 == keyname then
                            return id
                        end
                    end
                else
                    local name = (case_sensitive) and v or string.upper(v)
                    if name == keyname then
                        return id
                    end
                end
            end
        end
        local HK_hotkeys = {}
        local HK_down_keycombo = {}
        local HK_last_down_combokey = nil
        local HK_key_counter = 0
        local KE_current_name = nil
        local KE_new_keycombo = nil
        local KE_tick_clock = os.clock()
        local KE_tick_state = true
        local KE_hovered = false
        local DOWN_MESSAGES = {
            [wm.WM_KEYDOWN] = true,
            [wm.WM_SYSKEYDOWN] = true,
            [wm.WM_LBUTTONDBLCLK] = true,
            [wm.WM_LBUTTONDOWN] = true,
            [wm.WM_RBUTTONDOWN] = true,
            [wm.WM_MBUTTONDOWN] = true,
            [wm.WM_XBUTTONDOWN] = true,
            [wm.WM_MOUSEWHEEL] = true
        }
        local UP_MESSAGES = {
            [wm.WM_KEYUP] = true,
            [wm.WM_SYSKEYUP] = true,
            [wm.WM_LBUTTONDBLCLK] = true,
            [wm.WM_LBUTTONUP] = true,
            [wm.WM_RBUTTONUP] = true,
            [wm.WM_MBUTTONUP] = true,
            [wm.WM_XBUTTONUP] = true,
            [wm.WM_MOUSEWHEEL] = true
        }
        local MBUTTON = {
            [wm.WM_LBUTTONDOWN] = self.VK_LBUTTON,
            [wm.WM_LBUTTONUP] = self.VK_LBUTTON,
            [wm.WM_RBUTTONDOWN] = self.VK_RBUTTON,
            [wm.WM_RBUTTONUP] = self.VK_RBUTTON,
            [wm.WM_MBUTTONDOWN] = self.VK_MBUTTON,
            [wm.WM_MBUTTONUP] = self.VK_MBUTTON,
        }
        local XBUTTON = {
            self.VK_XBUTTON1,
            self.VK_XBUTTON2
        }
        local function HIWORD(param)
            return bit.rshift(bit.band(param, 0xffff0000), 16)
        end
        local function compareKeyCombos(keycombo1, keycombo2)
            if #keycombo1 == 0 or #keycombo2 == 0 then
                return false
            end
            keycombo1 = {table.unpack(keycombo1)}
            keycombo2 = {table.unpack(keycombo2)}
            local last_key1 = table.remove(keycombo1, #keycombo1)
            local last_key2 = table.remove(keycombo2, #keycombo2)
            table.sort(keycombo1)
            table.sort(keycombo2)
            table.insert(keycombo1, last_key1)
            table.insert(keycombo2, last_key2)
            for index = 1, #keycombo1 do
                if keycombo1[index] ~= keycombo2[index] then
                    return false
                end
            end
            return true
        end
        local function isDublicateExist(keycombo, press_type)
            for index = 1, #HK_hotkeys do
                if compareKeyCombos(HK_hotkeys[index].keycombo, keycombo) and HK_hotkeys[index].press_type == press_type then
                    return index
                end
            end
            return false
        end
        local function getKeyID(message, wparam, lparam)
            if message == wm.WM_XBUTTONDOWN or message == wm.WM_XBUTTONUP then
                local btn = HIWORD(wparam)
                return XBUTTON[btn]
            elseif MBUTTON[message] then
                return MBUTTON[message]
            elseif message == wm.WM_MOUSEWHEEL then
                local keystate = bitex.bextract(wparam, 30, 1)
                if keystate == 1 then
                    return self.VK_WHEELDOWN
                elseif keystate == 0 then
                    return self.VK_WHEELUP
                end
            end
            local newKeyId = wparam
            local scancode = bitex.bextract(lparam, 16, 8)
            local extend = bitex.bextract(lparam, 24, 1)
            if wparam == self.VK_MENU then
                if extend == 1 then newKeyId = self.VK_RMENU else newKeyId = self.VK_LMENU end
            elseif wparam == self.VK_SHIFT then
                if scancode == 42 then newKeyId = self.VK_LSHIFT elseif scancode == 54 then newKeyId = self.VK_RSHIFT end
            elseif wparam == self.VK_CONTROL then
                if extend == 1 then newKeyId = self.VK_RCONTROL else newKeyId = self.VK_LCONTROL end
            end
            return newKeyId
        end
        addEventHandler("onWindowMessage",
            function(message, wparam, lparam)
                if DOWN_MESSAGES[message] then
                    local key_id = getKeyID(message, wparam, lparam)
                    if not HK_down_keycombo[key_id] then
                        HK_last_down_combokey = key_id
                        HK_key_counter = HK_key_counter + 1
                        HK_down_keycombo[key_id] = HK_key_counter
                        if KE_current_name then
                            if key_id == self.VK_ESCAPE then
                                KE_current_name = nil
                            end
                            consumeWindowMessage(true, true)
                        else
                            for index = 1, #HK_hotkeys do
                                if self.is_keycombo_down(HK_hotkeys[index].keycombo) and HK_hotkeys[index].press_type == self.DOWN then
                                    if HK_hotkeys[index].callback and HK_hotkeys[index].enabled and not (KE_hovered and compareKeyCombos({self.VK_LBUTTON}, HK_down_keycombo)) then
                                        HK_hotkeys[index].callback(table.unpack(HK_hotkeys[index].args))
                                    end
                                    if HK_hotkeys[index].blocked then
                                        consumeWindowMessage(true, true)
                                    end
                                end
                            end
                        end
                    else
                        if KE_current_name then
                            consumeWindowMessage(true, true)
                        else
                            for index = 1, #HK_hotkeys do
                                if self.is_keycombo_down(HK_hotkeys[index].keycombo) and HK_hotkeys[index].press_type == self.HOLD then
                                    if HK_hotkeys[index].callback and HK_hotkeys[index].enabled and not (KE_hovered and compareKeyCombos({self.VK_LBUTTON}, HK_down_keycombo)) then
                                        HK_hotkeys[index].callback(table.unpack(HK_hotkeys[index].args))
                                    end
                                    if HK_hotkeys[index].blocked then
                                        consumeWindowMessage()
                                    end
                                end
                            end
                        end
                    end
                end
                if UP_MESSAGES[message] then
                    local key_id = getKeyID(message, wparam, lparam)
                    HK_last_down_combokey = key_id
                    HK_key_counter = HK_key_counter + 1
                    HK_down_keycombo[key_id] = HK_key_counter
                    if HK_down_keycombo[key_id] then
                        if KE_current_name then
                            KE_new_keycombo = self.get_down_keycombo()
                            consumeWindowMessage(true, true)
                        else
                            for index = 1, #HK_hotkeys do
                                if self.is_keycombo_down(HK_hotkeys[index].keycombo) and HK_hotkeys[index].press_type == self.UP then
                                    if HK_hotkeys[index].callback and HK_hotkeys[index].enabled and not (KE_hovered and compareKeyCombos({self.VK_LBUTTON}, HK_down_keycombo)) then
                                        HK_hotkeys[index].callback(table.unpack(HK_hotkeys[index].args))
                                    end
                                    if HK_hotkeys[index].blocked then
                                        consumeWindowMessage()
                                    end
                                end
                            end
                        end
                    end
                    HK_last_down_combokey = nil
                    HK_down_keycombo[key_id] = nil
                    if not next(HK_down_keycombo) then
                        HK_key_counter = 0
                    end
                end
                if message == wm.WM_CHAR then
                    if KE_current_name then
                        consumeWindowMessage(true, true)
                    else
                        for index = 1, #HK_hotkeys do
                            if self.is_keycombo_down(HK_hotkeys[index].keycombo) and (HK_hotkeys[index].press_type == self.DOWN or HK_hotkeys[index].press_type == self.UP or HK_hotkeys[index].press_type == self.HOLD) then
                                if HK_hotkeys[index].blocked then
                                    consumeWindowMessage()
                                end
                            end
                        end
                    end
                end
                if message == wm.WM_KILLFOCUS then
                    HK_last_down_combokey = nil
                    HK_down_keycombo = {}
                    HK_key_counter = 0
                    KE_new_keycombo = nil
                    KE_current_name = nil
                    KE_tick_clock = os.clock()
                    KE_tick_state = true
                end
            end
        )

        self.DOWN = 1
        self.HOLD = 2
        self.UP = 3
        self.ImguiHotkeyEditorPromt = "..."
        function self.register(keycombo, press_type, blocked, enabled, callback, ...)
            local hotkey_data = {
                keycombo = {table.unpack(keycombo)},
                press_type = press_type,
                blocked = blocked,
                enabled = enabled,
                callback = callback,
                args = {...}
            }
            local index = isDublicateExist(keycombo, hotkey_data.press_type)
            if index then
                HK_hotkeys[index].keycombo = {}
            end
            table.insert(HK_hotkeys, hotkey_data)
            return hotkey_data
        end
        function self.is_registered(hotkey_data)
            for index = 1, #HK_hotkeys do
                if HK_hotkeys[index] == hotkey_data then return true end
            end
            return false
        end
        function self.is_keycombo_down(keycombo)
            if HK_last_down_combokey ~= keycombo[#keycombo] then return false end
            for index = 1, #keycombo do
                local l_key, r_key
                if keycombo[index] == self.VK_MENU then l_key, r_key = self.VK_LMENU, self.VK_RMENU
                elseif keycombo[index] == self.VK_SHIFT then l_key, r_key = self.VK_LSHIFT, self.VK_RSHIFT
                elseif keycombo[index] == self.VK_CONTROL then l_key, r_key = self.VK_LCONTROL, self.VK_RCONTROL end
                if l_key and r_key then
                    if not HK_down_keycombo[l_key] and not HK_down_keycombo[r_key] then return false end
                else
                    if not HK_down_keycombo[keycombo[index]] then return false end
                end
            end
            return true
        end
        function self.set_keycombo(hotkey_data, keycombo)
            local index = isDublicateExist(keycombo, hotkey_data.press_type)
            if index then HK_hotkeys[index].keycombo = {} end
            if self.is_registered(hotkey_data) then
                local old_keycombo = {table.unpack(hotkey_data.keycombo)}
                hotkey_data.keycombo = {table.unpack(keycombo)}
                return old_keycombo
            end
        end
        function self.get_keycombo(hotkey_data)
            return {table.unpack(hotkey_data.keycombo)}
        end
        function self.get_down_keycombo()
            local keys = {}
            for key, _ in pairs(HK_down_keycombo) do table.insert(keys, key) end
            table.sort(keys, function(a, b) return HK_down_keycombo[a] < HK_down_keycombo[b] end)
            return keys
        end
        function self.get_down_keynames()
            return self.keycombo_to_keynames(self.get_down_keycombo())
        end
        function self.keycombo_to_keynames(keys)
            local names = {}
            for index = 1, #keys do table.insert(names, self.id_to_name(keys[index])) end
            return names
        end
        function self.ImguiHotkeyEditor(str_id, str_id2, label, hotkey_data, width)
            width = width or 200
            local width2 = (width == 0) and 0 or 22
            local sKeys
            if (KE_current_name == str_id) and not KE_new_keycombo then
                local current_names = self.get_down_keynames()
                if #current_names ~= 0 then
                    sKeys = table.concat(current_names, " + ")
                else
                    if (os.clock() - KE_tick_clock) > 0.4 then
                        KE_tick_clock = os.clock()
                        KE_tick_state = not KE_tick_state
                    end
                    sKeys = (KE_tick_state and self.ImguiHotkeyEditorPromt) or " "
                end
            elseif (KE_current_name == str_id) and KE_new_keycombo then
                sKeys = table.concat(self.keycombo_to_keynames(KE_new_keycombo), " + ")
            else
                local names = self.keycombo_to_keynames(hotkey_data.keycombo); sKeys = (#names > 0) and table.concat(names, " + ") or u8"Не задано"
            end
            imgui.PushStyleVar(imgui.StyleVar.ItemSpacing, imgui.ImVec2(2, 0))
                imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.GetStyle().Colors[imgui.Col.ButtonHovered])
                imgui.PushStyleVar(imgui.StyleVar.ButtonTextAlign, imgui.ImVec2(0.5, 0.5))
                    if imgui.Button(sKeys..str_id, imgui.ImVec2(width - width2, 24)) then
                        if not KE_current_name then
                            KE_new_keycombo = nil
                            KE_tick_clock = os.clock()
                            KE_tick_state = true
                            KE_current_name = str_id
                        end
                    end
                    if imgui.IsItemHovered() then
                        if KE_hovered ~= str_id then KE_hovered = str_id end
                    elseif KE_hovered == str_id then
                        KE_hovered = nil
                    end
                imgui.PopStyleVar()
                imgui.PopStyleColor()
                imgui.SameLine()
            imgui.PopStyleVar()
            local clear = imgui.Button(" X "..str_id2, imgui.ImVec2(26, 24))
            if imgui.IsItemHovered() then
                if KE_hovered ~= " X "..str_id2 then KE_hovered = " X "..str_id2 end
            elseif KE_hovered == " X "..str_id2 then
                KE_hovered = nil
            end
            if label then
                imgui.SameLine(0, 8)
                imgui.Text(label)
            end
            if clear then
                KE_current_name = nil
                return self.set_keycombo(hotkey_data, {})
            end
            if (KE_current_name == str_id) and KE_new_keycombo then
                KE_current_name = nil
                return self.set_keycombo(hotkey_data, KE_new_keycombo)
            end
        end
        return self
    end

    qsms.hkeys = initHKeys()
    qsms.dirname_resources = getWorkingDirectory().."\\config\\"..qsms.__name__
    qsms.dirname_chats = qsms.dirname_resources.."\\chats"
    qsms.filename_set = qsms.dirname_resources.."\\set.cfg"
    if not doesDirectoryExist(qsms.dirname_resources) then createDirectory(qsms.dirname_resources) end
    if not doesDirectoryExist(qsms.dirname_chats) then createDirectory(qsms.dirname_chats) end

    qsms.set = {
        chat_size = {760, 420},
        current_tab = "all",
        new_sms = {0xA4, 0x45}, -- VK_LMENU, VK_E
        reply_sms = {0xA4, 0x51}, -- VK_LMENU, VK_Q
        ooc = false,
        show_chat_overlay = true,
        autoresponder = {
            enabled = false,
            text = "Я сейчас отошёл от игры. Вернусь через {time}.",
            duration = 0,
            end_time = 0,
            blist = {},
            cooldown = 300,
        }
    }
    qsms.mcfg.update(qsms.set, qsms.filename_set)
    if qsms.set.show_chat_overlay == nil then qsms.set.show_chat_overlay = true end
    if type(qsms.set.autoresponder) ~= "table" then
        qsms.set.autoresponder = {
            enabled = false,
            text = "Я сейчас отошёл от игры. Вернусь через {time}.",
            duration = 0,
            end_time = 0,
            blist = {},
            cooldown = 300,
        }
    end
    qsms.set.autoresponder.blist = qsms.set.autoresponder.blist or {}
    qsms.set.autoresponder.cooldown = qsms.set.autoresponder.cooldown or 300
    qsms.set.autoresponder.text = qsms.set.autoresponder.text or "Я сейчас отошёл от игры. Вернусь через {time}."

    qsms.indicator = nil
    qsms.server_name = nil
    qsms.current_server_name = nil
    qsms.current_nickname = nil
    qsms.lcurrent_nickname = nil
    qsms.last_chat_input_text = nil
    qsms.do_max_scroll = true
    qsms.do_min_scroll = true
    qsms.auto_scroll = false
    qsms.search = {}
    qsms.searching = false
    qsms.new = false
    qsms.part = nil
    qsms.who = nil
    qsms.sms = nil
    qsms.do_call = false
    qsms.popup_is_open = false
    qsms.close_current_popup = false
    qsms.ar_last_reply = {}
    qsms.chats = {}
    qsms.hotkeys = {}
    qsms.menu_search_buf = imgui.ImBuffer("", 64)
    qsms.menu_sms_buf = imgui.ImBuffer("", 256)

    qsms.img = {
        window_menu = imgui.ImBool(false),
        window_chat = imgui.ImBool(false),
        checkbox_contacts = imgui.ImBool(false),
        checkbox_important = imgui.ImBool(false),
        checkbox_hidden = imgui.ImBool(false),
        ooc = imgui.ImBool(qsms.set.ooc),
        show_overlay = imgui.ImBool(qsms.set.show_chat_overlay),
    }

    qsms.ar_ui = {
        text_buf = imgui.ImBuffer(1024),
        duration_idx = imgui.ImInt(0),
        durations = {
            {label = "Бессрочно", sec = 0},
            {label = "5 минут",  sec = 300},
            {label = "15 минут", sec = 900},
            {label = "30 минут", sec = 1800},
            {label = "1 час",    sec = 3600},
            {label = "2 часа",   sec = 7200},
            {label = "4 часа",   sec = 14400},
            {label = "8 часов",  sec = 28800},
        },
        _loaded = false,
    }
    qsms.ar_ui.text_buf.v = u8(qsms.set.autoresponder.text or "")

    function qsms.getServerName()
        if not isSampAvailable() then return nil end
        local srv = sampGetCurrentServerName()
        if not srv or srv == "SA-MP" then return nil end
        local name = srv:match("Trinity (.+)")
        if not name then return nil end
        name = name:gsub("[%s|]", "")
        if name ~= "" then
            return name:lower()
        end
        return nil
    end

    function qsms.sampGetMyNickname()
        local result, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
        if result then
            return sampGetPlayerNickname(id)
        else
            return ""
        end
    end

    function qsms.safe(str)
        return str:gsub("%.$", ".%%")
    end

    function qsms.sort_chats(chats_tbl)
        local items = {}
        for key, value in pairs(chats_tbl) do
            table.insert(items, {key, value})
        end
        table.sort(items, function(a, b)
            return (a[2].set.ctime or 0) > (b[2].set.ctime or 0)
        end)
        return items
    end

    function qsms.new_sms()
        if not hasAccess("advertising") then return end
        if not sampIsScoreboardOpen() then
            sampSetChatInputText("/sms ")
            sampSetChatInputEnabled(true)
        end
    end

    function qsms.reply_sms()
        if not hasAccess("advertising") then return end
        if not sampIsScoreboardOpen() then
            local nickname = ""
            local sorted_chats = qsms.sort_chats(qsms.chats)
            if sorted_chats[1] then
                nickname = sorted_chats[1][2].set.nickname.." "
            end
            sampSetChatInputText("/sms "..nickname)
            sampSetChatInputEnabled(true)
        end
    end

    function qsms.format_duration(sec)
        if sec <= 0 then return "0 сек" end
        local h = math.floor(sec / 3600)
        local m = math.floor((sec % 3600) / 60)
        local s = sec % 60
        if h > 0 then return string.format("%d ч %d мин", h, m) end
        if m > 0 then return string.format("%d мин", m) end
        return string.format("%d сек", s)
    end

    function qsms.try_autoresponder(nickname, lnickname)
        local ar = qsms.set.autoresponder
        if not ar or not ar.enabled then return end

        if ar.end_time > 0 and os.time() >= ar.end_time then
            ar.enabled = false
            ar.end_time = 0
            qsms.mcfg.save(qsms.set, qsms.filename_set)
            return
        end
        local my_nick = qsms.sampGetMyNickname()
        if my_nick and my_nick:lower() == lnickname then return end
        if ar.blist[lnickname] then return end
        local now = os.time()
        if qsms.ar_last_reply[lnickname] and (now - qsms.ar_last_reply[lnickname]) < (ar.cooldown or 300) then
            return
        end
        qsms.ar_last_reply[lnickname] = now
        local text = (ar.text ~= "" and ar.text) or "Я отошёл."
        if ar.end_time and ar.end_time > 0 then
            local remain = ar.end_time - os.time()
            if remain > 0 then
                text = text:gsub("%{time%}", qsms.format_duration(remain))
            else
                text = text:gsub("%{time%}", "скоро")
            end
        else
            text = text:gsub("%{time%}", "скоро")
        end
        lua_thread.create(function()
            wait(500)
            if qsms.set.ooc then
                qsms.sendServerCmd("/t "..nickname.." (( "..text.." ))")
            else
                qsms.sendServerCmd("/t "..nickname.." "..text)
            end
        end)
    end

    function qsms.render_list_section(sorted_chats, list, height, t)
        t = t or getTheme()
        if not qsms.ar_ui.blist_search_buf then
            qsms.ar_ui.blist_search_buf = imgui.ImBuffer("", 64)
        end

        local blockedCount = 0
        for _, v in pairs(list) do
            if v then blockedCount = blockedCount + 1 end
        end

        imgui.AlignTextToFramePadding()
        imgui.TextColored(t.textDim, fa.ICON_SEARCH .. u8" Фильтр:")
        imgui.SameLine(80)
        imgui.PushItemWidth(imgui.GetContentRegionAvailWidth() - (blockedCount > 0 and 115 or 0))
        imgui.InputText("##ar_blist_search", qsms.ar_ui.blist_search_buf)
        imgui.PopItemWidth()

        if blockedCount > 0 then
            imgui.SameLine(0, 6)
            if imgui.Button(fa.ICON_TRASH_O .. u8" Очистить (" .. blockedCount .. ")##ar_blist_clear", imgui.ImVec2(109, 24)) then
                for k in pairs(list) do list[k] = nil end
                pcall(qsms.mcfg.save, qsms.set, qsms.filename_set)
            end
        end

        imgui.Spacing()

        local rawFilter = u8:decode(qsms.ar_ui.blist_search_buf.v):gsub("^%s+", ""):gsub("%s+$", ""):lower()
        local shown = 0
        local dl = imgui.GetWindowDrawList()

        imgui.BeginChild("##blist_child", imgui.ImVec2(0, height or 200), true)
            local w = imgui.GetContentRegionAvailWidth()
            for _, item in ipairs(sorted_chats) do
                local nickname = item[2] and item[2].set and item[2].set.nickname
                if nickname then
                    local lnickname = nickname:lower()
                    if rawFilter == "" or lnickname:find(rawFilter, 1, true) then
                        shown = shown + 1
                        local isBlocked = (list[lnickname] == true)
                        local p = imgui.GetCursorScreenPos()
                        local h = 30
                        imgui.InvisibleButton("##blist_row_" .. qsms.safe(lnickname), imgui.ImVec2(w, h))
                        local hov = imgui.IsItemHovered()
                        if imgui.IsItemClicked(0) then
                            if isBlocked then
                                list[lnickname] = nil
                            else
                                list[lnickname] = true
                            end
                            pcall(qsms.mcfg.save, qsms.set, qsms.filename_set)
                            isBlocked = not isBlocked
                        end

                        local bgAlpha = hov and 0.72 or (isBlocked and 0.48 or 0.26)
                        local bgCol = isBlocked
                            and imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.38, 0.14, 0.16, bgAlpha))
                            or imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.frameBg.x, t.frameBg.y, t.frameBg.z, bgAlpha))
                        dl:AddRectFilled(p, imgui.ImVec2(p.x + w, p.y + h), bgCol, 6.0)

                        if isBlocked then
                            dl:AddRectFilled(p, imgui.ImVec2(p.x + 3, p.y + h),
                                imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.95, 0.35, 0.35, 1.0)), 3.0)
                        end

                        local ic = isBlocked and fa.ICON_BAN or fa.ICON_USER
                        local icCol = isBlocked and imgui.ImVec4(0.95, 0.38, 0.38, 1.0) or t.textDim
                        local txtCol = isBlocked and imgui.ImVec4(1.0, 0.85, 0.85, 1.0) or t.text
                        dl:AddText(imgui.ImVec2(p.x + 12, p.y + 7), imgui.ColorConvertFloat4ToU32(icCol), ic)
                        dl:AddText(imgui.ImVec2(p.x + 32, p.y + 7), imgui.ColorConvertFloat4ToU32(txtCol), u8(nickname))

                        local badgeTxt = isBlocked and u8"Игнорируется" or u8"Отвечать"
                        local bSz = imgui.CalcTextSize(badgeTxt)
                        local bW = bSz.x + 12
                        local bH = 18
                        local bX = p.x + w - bW - 8
                        local bY = p.y + 6
                        local bBg = isBlocked
                            and imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.85, 0.25, 0.25, 0.30))
                            or imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.18))
                        local bFg = isBlocked
                            and imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1.0, 0.45, 0.45, 1.0))
                            or imgui.ColorConvertFloat4ToU32(t.textDim)
                        dl:AddRectFilled(imgui.ImVec2(bX, bY), imgui.ImVec2(bX + bW, bY + bH), bBg, 4.0)
                        dl:AddText(imgui.ImVec2(bX + 6, bY + 2), bFg, badgeTxt)

                        imgui.Dummy(imgui.ImVec2(1, 2))
                    end
                end
            end
            if shown == 0 then
                imgui.Spacing()
                imgui.TextColored(t.textDim, u8"  Контактов не найдено.")
            end
        imgui.EndChild()
    end

    function qsms.render_autoresponder_tab(sorted_chats, isCompactOverlay)
        local t = getTheme()
        local ar = qsms.set.autoresponder
        local cardBg = imgui.ImVec4(t.windowBg.x, t.windowBg.y, t.windowBg.z, 0.80)
        local cardBorder = imgui.ImVec4(t.border.x, t.border.y, t.border.z, 0.45)

        if isCompactOverlay then
            -- Компактный вид для маленького всплывающего окна под чатом F6
            local stCol = ar.enabled and imgui.ImVec4(0.25, 0.88, 0.45, 1.0) or imgui.ImVec4(0.90, 0.35, 0.35, 1.0)
            local stText = ar.enabled
                and (ar.end_time > 0 and (u8"Активен (осталось " .. u8(qsms.format_duration(math.max(0, ar.end_time - os.time()))) .. ")") or u8"Активен (бессрочно)")
                or u8"Выключен"
            imgui.AlignTextToFramePadding()
            imgui.TextColored(t.textDim, fa.ICON_CLOCK_O .. u8" Автоответчик:")
            imgui.SameLine()
            imgui.TextColored(stCol, stText)
            imgui.SameLine(330)
            if imgui.Button((ar.enabled and (fa.ICON_POWER_OFF .. u8" Выключить") or (fa.ICON_PLAY .. u8" Включить")) .. "##ov_ar_tgl", imgui.ImVec2(130, 24)) then
                ar.enabled = not ar.enabled
                if ar.enabled then
                    local sec = qsms.ar_ui.durations[qsms.ar_ui.duration_idx.v + 1].sec
                    ar.end_time = (sec > 0) and (os.time() + sec) or 0
                else
                    ar.end_time = 0
                end
                qsms.mcfg.save(qsms.set, qsms.filename_set)
            end
            imgui.Spacing()
            imgui.TextColored(t.textDim, u8"Текст автоответа ({time} — время до возвращения):")
            imgui.PushItemWidth(-1)
            if imgui.InputText("##ar_text_ov", qsms.ar_ui.text_buf, 1024) then
                ar.text = u8:decode(qsms.ar_ui.text_buf.v)
                qsms.mcfg.save(qsms.set, qsms.filename_set)
            end
            imgui.PopItemWidth()
            return
        end

        local avail = imgui.GetContentRegionAvail()
        local gap = 12
        local leftW = math.floor((avail.x - gap) * 0.56)
        local rightW = avail.x - leftW - gap

        local function drawCardHeader(icon, title)
            imgui.TextColored(t.accent, icon .. "  " .. title)
            imgui.Separator()
            imgui.Spacing()
        end

        -- ============================================================
        --  ЛЕВАЯ КОЛОНКА: СТАТУС, ТАЙМЕР И ШАБЛОН АВТООТВЕТА
        -- ============================================================
        imgui.BeginGroup()

            -- 1. Карточка статуса и таймера
            imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
            imgui.PushStyleColor(imgui.Col.Border, cardBorder)
            imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, 8.0)
            imgui.BeginChild("##ar_card_status", imgui.ImVec2(leftW, 196), true)

                drawCardHeader(fa.ICON_CLOCK_O, u8"Управление автоответчиком")

                -- Крупная интерактивная плашка включения/выключения
                local dl = imgui.GetWindowDrawList()
                local p = imgui.GetCursorScreenPos()
                local w = imgui.GetContentRegionAvailWidth()
                local h = 46
                imgui.InvisibleButton("##ar_main_toggle_btn", imgui.ImVec2(w, h))
                local hov = imgui.IsItemHovered()
                if imgui.IsItemClicked(0) then
                    ar.enabled = not ar.enabled
                    if ar.enabled then
                        local sec = qsms.ar_ui.durations[qsms.ar_ui.duration_idx.v + 1].sec
                        ar.end_time = (sec > 0) and (os.time() + sec) or 0
                    else
                        ar.end_time = 0
                    end
                    qsms.mcfg.save(qsms.set, qsms.filename_set)
                end

                local bannerBg = ar.enabled
                    and imgui.ImVec4(0.14, 0.36, 0.22, hov and 0.85 or 0.68)
                    or imgui.ImVec4(t.frameBg.x, t.frameBg.y, t.frameBg.z, hov and 0.75 or 0.45)
                dl:AddRectFilled(p, imgui.ImVec2(p.x + w, p.y + h), imgui.ColorConvertFloat4ToU32(bannerBg), 6.0)
                local barCol = ar.enabled and imgui.ImVec4(0.28, 0.90, 0.48, 1.0) or imgui.ImVec4(0.85, 0.30, 0.30, 0.85)
                dl:AddRectFilled(p, imgui.ImVec2(p.x + 4, p.y + h), imgui.ColorConvertFloat4ToU32(barCol), 3.0)

                dl:AddCircleFilled(imgui.ImVec2(p.x + 24, p.y + h * 0.5), 13,
                    imgui.ColorConvertFloat4ToU32(imgui.ImVec4(barCol.x, barCol.y, barCol.z, 0.22)), 20)
                local pwrSz = imgui.CalcTextSize(fa.ICON_POWER_OFF)
                dl:AddText(imgui.ImVec2(p.x + 24 - pwrSz.x * 0.5, p.y + h * 0.5 - pwrSz.y * 0.5),
                    imgui.ColorConvertFloat4ToU32(barCol), fa.ICON_POWER_OFF)

                local statusTitle = ar.enabled and u8"Автоответчик ВКЛЮЧЁН" or u8"Автоответчик ВЫКЛЮЧЕН"
                local statusSub
                if ar.enabled then
                    if ar.end_time > 0 then
                        local rem = math.max(0, ar.end_time - os.time())
                        statusSub = u8("Автоматически отключится через: " .. qsms.format_duration(rem))
                    else
                        statusSub = u8"Работает в бессрочном режиме (пока вы не отключите)"
                    end
                else
                    statusSub = u8"Нажмите здесь, чтобы активировать автоматические ответы на входящие SMS"
                end

                dl:AddText(imgui.ImVec2(p.x + 46, p.y + 7), imgui.ColorConvertFloat4ToU32(t.text), statusTitle)
                dl:AddText(imgui.ImVec2(p.x + 46, p.y + 25), imgui.ColorConvertFloat4ToU32(t.textDim), statusSub)

                -- Тумблер справа
                local swW, swH = 38, 20
                local swX = p.x + w - swW - 14
                local swY = p.y + (h - swH) * 0.5
                local swBg = ar.enabled
                    and imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.28, 0.85, 0.45, 0.95))
                    or imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.22, 0.25, 0.30, 0.90))
                dl:AddRectFilled(imgui.ImVec2(swX, swY), imgui.ImVec2(swX + swW, swY + swH), swBg, swH * 0.5)
                local knobX = ar.enabled and (swX + swW - swH * 0.5) or (swX + swH * 0.5)
                dl:AddCircleFilled(imgui.ImVec2(knobX, swY + swH * 0.5), (swH * 0.5) - 2.5,
                    imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1, 1, 1, 0.95)), 16)

                imgui.Spacing()
                imgui.Spacing()

                -- Время работы
                imgui.AlignTextToFramePadding()
                imgui.TextColored(t.textDim, fa.ICON_HOURGLASS_HALF .. u8"  Вернусь через:")
                imgui.SameLine(205)
                local items = {}
                for i, d in ipairs(qsms.ar_ui.durations) do
                    items[i] = u8(d.label)
                end
                imgui.PushItemWidth(ar.enabled and (leftW - 335) or -1)
                local cur_idx = imgui.ImInt(qsms.ar_ui.duration_idx.v)
                if imgui.Combo("##ar_dur", cur_idx, items, #items) then
                    qsms.ar_ui.duration_idx.v = cur_idx.v
                    if ar.enabled then
                        local d = qsms.ar_ui.durations[cur_idx.v + 1]
                        ar.end_time = (d.sec > 0) and (os.time() + d.sec) or 0
                        qsms.mcfg.save(qsms.set, qsms.filename_set)
                    end
                end
                imgui.PopItemWidth()

                if ar.enabled then
                    imgui.SameLine(0, 6)
                    if imgui.Button(fa.ICON_UNDO .. u8" Сброс##ar_reset_timer", imgui.ImVec2(105, 24)) then
                        local sec = qsms.ar_ui.durations[qsms.ar_ui.duration_idx.v + 1].sec
                        ar.end_time = (sec > 0) and (os.time() + sec) or 0
                        qsms.mcfg.save(qsms.set, qsms.filename_set)
                    end
                    if imgui.IsItemHovered() then imgui.SetTooltip(u8"Перезапустить отсчёт времени заново") end
                end

                imgui.Spacing()

                -- Кулдаун
                imgui.AlignTextToFramePadding()
                imgui.TextColored(t.textDim, fa.ICON_SHIELD .. u8"  Кулдаун на игрока (сек):")
                imgui.SameLine(205)
                imgui.PushItemWidth(-1)
                local cool = imgui.ImInt(ar.cooldown or 300)
                if imgui.InputInt("##ar_cooldown", cool, 30, 300) then
                    ar.cooldown = math.max(10, cool.v)
                    qsms.mcfg.save(qsms.set, qsms.filename_set)
                end
                imgui.PopItemWidth()

            imgui.EndChild()
            imgui.PopStyleVar()
            imgui.PopStyleColor(2)

            imgui.Spacing()

            -- 2. Карточка текста автоответа и готовых шаблонов
            local msgCardH = math.max(195, imgui.GetContentRegionAvail().y)
            imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
            imgui.PushStyleColor(imgui.Col.Border, cardBorder)
            imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, 8.0)
            imgui.BeginChild("##ar_card_msg", imgui.ImVec2(leftW, msgCardH), true)

                drawCardHeader(fa.ICON_COMMENTING_O, u8"Текст сообщения и быстрые шаблоны")

                imgui.TextColored(t.textDim, u8"Сообщение автоответа (тег {time} заменится на оставшееся время):")
                imgui.PushItemWidth(-1)
                if imgui.InputText("##ar_text", qsms.ar_ui.text_buf, 1024) then
                    ar.text = u8:decode(qsms.ar_ui.text_buf.v)
                    qsms.mcfg.save(qsms.set, qsms.filename_set)
                end
                imgui.PopItemWidth()

                imgui.Spacing()
                imgui.TextColored(t.textDim, fa.ICON_BOLT .. u8" Быстрые шаблоны (клик для подстановки):")
                imgui.Spacing()

                local presets = {
                    { btn = u8"Отошёл от ПК",   txt = "Я сейчас отошёл от игры. Вернусь через {time}." },
                    { btn = u8"На ивенте",      txt = "Сейчас провожу ивент, не могу ответить. Освобожусь через {time}." },
                    { btn = u8"Занят / РП",     txt = "Сейчас занят на ситуации, отвечу вам через {time}." },
                    { btn = u8"Скоро буду",     txt = "Временно недоступен, напишу вам как только освобожусь!" },
                }
                local pW = math.floor((imgui.GetContentRegionAvailWidth() - 18) / 4)
                for idx, pr in ipairs(presets) do
                    if idx > 1 then imgui.SameLine(0, 6) end
                    if imgui.Button(pr.btn .. "##ar_pres_" .. idx, imgui.ImVec2(pW, 24)) then
                        ar.text = pr.txt
                        qsms.ar_ui.text_buf.v = u8(pr.txt)
                        qsms.mcfg.save(qsms.set, qsms.filename_set)
                    end
                end

                imgui.Spacing()
                -- Живой предпросмотр
                local previewRaw = (ar.text ~= "" and ar.text) or "Я отошёл."
                local sampleTime = "15 мин"
                if ar.enabled and ar.end_time and ar.end_time > 0 then
                    local rem = math.max(0, ar.end_time - os.time())
                    sampleTime = qsms.format_duration(rem)
                else
                    local selSec = qsms.ar_ui.durations[qsms.ar_ui.duration_idx.v + 1].sec
                    if selSec > 0 then sampleTime = qsms.format_duration(selSec) else sampleTime = "скоро" end
                end
                previewRaw = previewRaw:gsub("%{time%}", sampleTime)
                if qsms.set.ooc then previewRaw = "(( " .. previewRaw .. " ))" end

                imgui.PushStyleColor(imgui.Col.ChildWindowBg, imgui.ImVec4(t.frameBg.x, t.frameBg.y, t.frameBg.z, 0.45))
                imgui.BeginChild("##ar_live_preview", imgui.ImVec2(-1, 44), false)
                    imgui.SetCursorPos(imgui.ImVec2(10, 6))
                    imgui.TextColored(t.textDim, fa.ICON_EYE .. u8" Предпросмотр в игре:")
                    imgui.SetCursorPos(imgui.ImVec2(10, 23))
                    imgui.TextColored(imgui.ImVec4(0.95, 0.85, 0.35, 1.0), u8("SMS: " .. previewRaw))
                imgui.EndChild()
                imgui.PopStyleColor()

            imgui.EndChild()
            imgui.PopStyleVar()
            imgui.PopStyleColor(2)

        imgui.EndGroup()

        -- ============================================================
        --  ПРАВАЯ КОЛОНКА: ЧЁРНЫЙ СПИСОК (ИГНОР-ЛИСТ)
        -- ============================================================
        imgui.SameLine(0, gap)
        imgui.BeginGroup()

            local rightH = math.max(400, imgui.GetContentRegionAvail().y)
            imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
            imgui.PushStyleColor(imgui.Col.Border, cardBorder)
            imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, 8.0)
            imgui.BeginChild("##ar_card_blist", imgui.ImVec2(rightW, rightH), true)

                drawCardHeader(fa.ICON_BAN, u8"Чёрный список (не отвечать)")
                imgui.TextColored(t.textDim, u8"Выберите игроков, которым автоответчик НЕ будет отправлять SMS:")
                imgui.Spacing()

                qsms.render_list_section(sorted_chats, ar.blist, imgui.GetContentRegionAvail().y - 4, t)

            imgui.EndChild()
            imgui.PopStyleVar()
            imgui.PopStyleColor(2)

        imgui.EndGroup()
    end

    function qsms.render_hotkeys_and_help_tab(t)
        local avail = imgui.GetContentRegionAvail()
        local gap = 12
        local colW = math.floor((avail.x - gap) * 0.5)
        local cardBg = imgui.ImVec4(t.windowBg.x, t.windowBg.y, t.windowBg.z, 0.80)
        local cardBorder = imgui.ImVec4(t.border.x, t.border.y, t.border.z, 0.45)

        local function drawCardHeader(icon, title)
            imgui.TextColored(t.accent, icon .. "  " .. title)
            imgui.Separator()
            imgui.Spacing()
        end

        local function drawToggleRow(id, icon, title, subtitle, boolVar, onToggle)
            local dl = imgui.GetWindowDrawList()
            local p = imgui.GetCursorScreenPos()
            local w = imgui.GetContentRegionAvailWidth()
            local h = subtitle and 44 or 32
            imgui.InvisibleButton("##qsms_tgl_" .. id, imgui.ImVec2(w, h))
            local hov = imgui.IsItemHovered()
            if imgui.IsItemClicked(0) then
                boolVar.v = not boolVar.v
                if onToggle then onToggle(boolVar.v) end
            end

            local bgAlpha = hov and 0.75 or (boolVar.v and 0.50 or 0.30)
            local bgCol = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.frameBg.x, t.frameBg.y, t.frameBg.z, bgAlpha))
            dl:AddRectFilled(p, imgui.ImVec2(p.x + w, p.y + h), bgCol, 6.0)
            if boolVar.v then
                dl:AddRectFilled(p, imgui.ImVec2(p.x + 3, p.y + h), imgui.ColorConvertFloat4ToU32(t.accent), 3.0)
            end

            local icCol = imgui.ColorConvertFloat4ToU32(boolVar.v and t.accent or t.textDim)
            local txtCol = imgui.ColorConvertFloat4ToU32(boolVar.v and t.text or t.textDim)
            local subCol = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.textDim.x, t.textDim.y, t.textDim.z, 0.75))

            dl:AddText(imgui.ImVec2(p.x + 12, p.y + 8), icCol, icon)
            dl:AddText(imgui.ImVec2(p.x + 34, p.y + (subtitle and 6 or 8)), txtCol, title)
            if subtitle then
                dl:AddText(imgui.ImVec2(p.x + 34, p.y + 24), subCol, subtitle)
            end

            local swW, swH = 34, 18
            local swX = p.x + w - swW - 12
            local swY = p.y + (h - swH) * 0.5
            local swBg = boolVar.v
                and imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.90))
                or imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.22, 0.25, 0.30, 0.90))
            dl:AddRectFilled(imgui.ImVec2(swX, swY), imgui.ImVec2(swX + swW, swY + swH), swBg, swH * 0.5)
            local knobX = boolVar.v and (swX + swW - swH * 0.5) or (swX + swH * 0.5)
            dl:AddCircleFilled(imgui.ImVec2(knobX, swY + swH * 0.5), (swH * 0.5) - 2.5, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1, 1, 1, 0.95)), 16)
        end

        local function drawInfoTile(icon, cmdBadge, title, desc)
            local dl = imgui.GetWindowDrawList()
            local p = imgui.GetCursorScreenPos()
            local w = imgui.GetContentRegionAvailWidth()
            local h = 48
            imgui.Dummy(imgui.ImVec2(w, h))

            local bgCol = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.frameBg.x, t.frameBg.y, t.frameBg.z, 0.38))
            dl:AddRectFilled(p, imgui.ImVec2(p.x + w, p.y + h), bgCol, 6.0)
            dl:AddRectFilled(p, imgui.ImVec2(p.x + 3, p.y + h), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.75)), 3.0)

            local cx, cy = p.x + 24, p.y + h * 0.5
            dl:AddCircleFilled(imgui.ImVec2(cx, cy), 13, imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.18)), 20)
            local icSz = imgui.CalcTextSize(icon)
            dl:AddText(imgui.ImVec2(cx - icSz.x * 0.5, cy - icSz.y * 0.5), imgui.ColorConvertFloat4ToU32(t.accent), icon)

            local textX = p.x + 46
            dl:AddText(imgui.ImVec2(textX, p.y + 7), imgui.ColorConvertFloat4ToU32(t.text), title)

            if cmdBadge and cmdBadge ~= "" then
                local bSz = imgui.CalcTextSize(cmdBadge)
                local bW = bSz.x + 12
                local bH = 18
                local bX = p.x + w - bW - 10
                local bY = p.y + 6
                dl:AddRectFilled(imgui.ImVec2(bX, bY), imgui.ImVec2(bX + bW, bY + bH), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.22)), 4.0)
                dl:AddText(imgui.ImVec2(bX + 6, bY + 2), imgui.ColorConvertFloat4ToU32(t.accent), cmdBadge)
            end

            dl:AddText(imgui.ImVec2(textX, p.y + 26), imgui.ColorConvertFloat4ToU32(t.textDim), desc)
        end

        local totalChats, impChats, cntChats, hidChats, totalMsgs = 0, 0, 0, 0, 0
        for _, c in pairs(qsms.chats or {}) do
            totalChats = totalChats + 1
            if c.set then
                if c.set.important then impChats = impChats + 1 end
                if c.set.contacts then cntChats = cntChats + 1 end
                if c.set.hidden then hidChats = hidChats + 1 end
            end
            if c.chat then totalMsgs = totalMsgs + #c.chat end
        end

        -- ============================================================
        --  ЛЕВАЯ КОЛОНКА: ГОРЯЧИЕ КЛАВИШИ, РЕЖИМЫ И СТАТИСТИКА
        -- ============================================================
        imgui.BeginGroup()

            -- 1. Карточка горячих клавиш
            imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
            imgui.PushStyleColor(imgui.Col.Border, cardBorder)
            imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, 8.0)
            imgui.BeginChild("##qsms_card_hk", imgui.ImVec2(colW, 130), true)

                drawCardHeader(fa.ICON_KEYBOARD_O, u8"Горячие клавиши быстрого набора")

                imgui.AlignTextToFramePadding()
                imgui.TextColored(t.text, fa.ICON_PENCIL_SQUARE_O .. u8"  Новое SMS сообщение:")
                imgui.SameLine(235)
                if qsms.hotkeys.new_sms and qsms.hkeys.ImguiHotkeyEditor("##hotkeys.new_sms 1", "##hotkeys.new_sms 2", nil, qsms.hotkeys.new_sms, colW - 255) then
                    qsms.set.new_sms = qsms.hkeys.get_keycombo(qsms.hotkeys.new_sms)
                    qsms.mcfg.save(qsms.set, qsms.filename_set)
                end

                imgui.Spacing()

                imgui.AlignTextToFramePadding()
                imgui.TextColored(t.text, fa.ICON_REPLY .. u8"  Ответить на последнее SMS:")
                imgui.SameLine(235)
                if qsms.hotkeys.reply_sms and qsms.hkeys.ImguiHotkeyEditor("##hotkeys.reply_sms 1", "##hotkeys.reply_sms 2", nil, qsms.hotkeys.reply_sms, colW - 255) then
                    qsms.set.reply_sms = qsms.hkeys.get_keycombo(qsms.hotkeys.reply_sms)
                    qsms.mcfg.save(qsms.set, qsms.filename_set)
                end

            imgui.EndChild()
            imgui.PopStyleVar()
            imgui.PopStyleColor(2)

            imgui.Spacing()

            -- 2. Карточка параметров и режима отправки
            imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
            imgui.PushStyleColor(imgui.Col.Border, cardBorder)
            imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, 8.0)
            imgui.BeginChild("##qsms_card_modes", imgui.ImVec2(colW, 148), true)

                drawCardHeader(fa.ICON_SLIDERS, u8"Режим отправки и интерфейс чата")

                drawToggleRow("ooc_mode", fa.ICON_COMMENT_O,
                    u8"Отправлять OOC SMS (( текст ))",
                    u8"Оборачивает сообщения в двойные скобки для внеигрового общения",
                    qsms.img.ooc, function(val)
                        qsms.set.ooc = val
                        qsms.mcfg.save(qsms.set, qsms.filename_set)
                    end)

                imgui.Dummy(imgui.ImVec2(1, 4))

                drawToggleRow("chat_overlay", fa.ICON_WINDOW_MAXIMIZE,
                    u8"Всплывающая панель диалогов под чатом (F6)",
                    u8"Показывает быстрый поиск и историю при вводе /sms или /t",
                    qsms.img.show_overlay, function(val)
                        qsms.set.show_chat_overlay = val
                        qsms.mcfg.save(qsms.set, qsms.filename_set)
                    end)

            imgui.EndChild()
            imgui.PopStyleVar()
            imgui.PopStyleColor(2)

            imgui.Spacing()

            -- 3. Карточка статистики базы сообщений
            local statH = math.max(115, imgui.GetContentRegionAvail().y)
            imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
            imgui.PushStyleColor(imgui.Col.Border, cardBorder)
            imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, 8.0)
            imgui.BeginChild("##qsms_card_stats", imgui.ImVec2(colW, statH), true)

                drawCardHeader(fa.ICON_BAR_CHART, u8"Статистика базы Мессенджера")

                local dl = imgui.GetWindowDrawList()
                local availW = imgui.GetContentRegionAvailWidth()
                local boxGap = 8
                local boxW = math.floor((availW - boxGap * 3) / 4)
                local boxH = math.max(54, imgui.GetContentRegionAvail().y - 6)

                local statsDef = {
                    { label = u8"Диалогов",  val = tostring(totalChats), icon = fa.ICON_COMMENTS,     col = t.accent },
                    { label = u8"Сообщений", val = tostring(totalMsgs),  icon = fa.ICON_ENVELOPE_O,   col = imgui.ImVec4(0.35, 0.80, 0.95, 1.0) },
                    { label = u8"Важных",    val = tostring(impChats),   icon = fa.ICON_STAR,         col = imgui.ImVec4(0.95, 0.75, 0.25, 1.0) },
                    { label = u8"Контактов", val = tostring(cntChats),   icon = fa.ICON_ADDRESS_BOOK, col = imgui.ImVec4(0.40, 0.85, 0.55, 1.0) },
                }

                for i, st in ipairs(statsDef) do
                    if i > 1 then imgui.SameLine(0, boxGap) end
                    local p = imgui.GetCursorScreenPos()
                    imgui.Dummy(imgui.ImVec2(boxW, boxH))
                    dl:AddRectFilled(p, imgui.ImVec2(p.x + boxW, p.y + boxH),
                        imgui.ColorConvertFloat4ToU32(imgui.ImVec4(t.frameBg.x, t.frameBg.y, t.frameBg.z, 0.45)), 6.0)
                    dl:AddRectFilled(p, imgui.ImVec2(p.x + boxW, p.y + 3),
                        imgui.ColorConvertFloat4ToU32(st.col), 3.0)

                    dl:AddText(imgui.ImVec2(p.x + 10, p.y + 10), imgui.ColorConvertFloat4ToU32(st.col), st.icon .. "  " .. st.val)
                    dl:AddText(imgui.ImVec2(p.x + 10, p.y + 30), imgui.ColorConvertFloat4ToU32(t.textDim), st.label)
                end

            imgui.EndChild()
            imgui.PopStyleVar()
            imgui.PopStyleColor(2)

        imgui.EndGroup()

        -- ============================================================
        --  ПРАВАЯ КОЛОНКА: СПРАВОЧНИК КОМАНД И ФИШЕК
        -- ============================================================
        imgui.SameLine(0, gap)
        imgui.BeginGroup()

            local rightH = math.max(400, imgui.GetContentRegionAvail().y)
            imgui.PushStyleColor(imgui.Col.ChildWindowBg, cardBg)
            imgui.PushStyleColor(imgui.Col.Border, cardBorder)
            imgui.PushStyleVar(imgui.StyleVar.ChildWindowRounding, 8.0)
            imgui.BeginChild("##qsms_card_help", imgui.ImVec2(colW, rightH), true)

                drawCardHeader(fa.ICON_BOOK, u8"Справочник команд и возможностей")

                drawInfoTile(fa.ICON_TERMINAL, u8"/smss  /sms  /t",
                    u8"Быстрое открытие Мессенджера",
                    u8"Ввод команды без аргументов сразу открывает этот раздел")

                imgui.Dummy(imgui.ImVec2(1, 4))
                drawInfoTile(fa.ICON_USER, u8"/sms [ID / Ник] [Текст]",
                    u8"Отправка по ID или никнейму игрока",
                    u8"Скрипт сам найдет номер через телефонную книгу (/number)")

                imgui.Dummy(imgui.ImVec2(1, 4))
                drawInfoTile(fa.ICON_PHONE, u8"/sms +123456 [Текст]",
                    u8"Прямая отправка по номеру телефона",
                    u8"Знак «+» перед номером отправляет SMS напрямую без поиска")

                imgui.Dummy(imgui.ImVec2(1, 4))
                drawInfoTile(fa.ICON_EXCHANGE, u8"Клавиша TAB",
                    u8"Умное управление в строке чата (F6)",
                    u8"При поиске переключает вкладки или подставляет найденный ник")

                imgui.Dummy(imgui.ImVec2(1, 4))
                drawInfoTile(fa.ICON_EYE_SLASH, u8"Иконка глаза у поиска",
                    u8"Приватный раздел «Скрытые диалоги»",
                    u8"Скрытые чаты прячутся под кнопкой глаза справа от строки поиска")

            imgui.EndChild()
            imgui.PopStyleVar()
            imgui.PopStyleColor(2)

        imgui.EndGroup()
    end

    function qsms.sendServerCmd(cmd)
        local bs = raknetNewBitStream()
        raknetBitStreamWriteInt32(bs, #cmd)
        raknetBitStreamWriteString(bs, cmd)
        raknetSendRpc(RPC_SERVERCOMMAND or 50, bs)
        raknetDeleteBitStream(bs)
    end

    function qsms.call_func(somebody)
        qsms.who = somebody
        qsms.do_call = true
        sampSetChatInputEnabled(false)
        if qsms.who:match("^%+[%d%-]+") then
            qsms.sendServerCmd("/call "..qsms.who:gsub("%+", ""))
            qsms.do_call = false
            qsms.who = nil
            return
        end
        if not qsms.who:match("^%d+$") then
            for id = 0, sampGetMaxPlayerId(false) do
                if sampIsPlayerConnected(id) then
                    if sampGetPlayerNickname(id):lower() == qsms.who:lower() then
                        qsms.who = tostring(id)
                        break
                    end
                end
            end
        end
        qsms.sendServerCmd("/number "..qsms.who)
    end

    function qsms.sms_func(args)
        args = args or ""
        qsms.do_call = false
        if args == "" then
            main_window_state.v = true
            openTab("quicksms", u8"Мессенджер")
            return
        end
        if not hasAccess("advertising") then
            qsms.sendServerCmd("/sms "..args)
            return
        end
        local exceptions = {
            ["radiols"] = true,
            ["radious"] = true,
            ["radiosf"] = true,
            ["radioaf"] = true,
            ["radiolv"] = true,
            ["radiorc"] = true,
            ["studiols"] = true,
            ["studious"] = true,
            ["studiosf"] = true,
            ["studioaf"] = true,
            ["studiolv"] = true,
            ["studiorc"] = true,
            ["radio"] = true,
            ["studio"] = true,
        }
        local radio = args:match("^(%S+)")
        if radio and exceptions[radio:lower()] then
            qsms.sendServerCmd("/sms "..args)
            return
        end
        local who_arg, sms_arg = args:match("^(%S+)%s+(.+)$")
        if who_arg then
            qsms.who = who_arg
            qsms.sms = sms_arg
            if qsms.who:match("^%+[%d%-]+") then
                if qsms.set.ooc then
                    qsms.sendServerCmd("/t "..qsms.who:gsub("%+", "").." (( "..qsms.sms.." ))")
                else
                    qsms.sendServerCmd("/t "..qsms.who:gsub("%+", "").." "..qsms.sms)
                end
                qsms.who = nil
                return
            end
            if not qsms.who:match("^%d+$") then
                for id = 0, sampGetMaxPlayerId(false) do
                    if sampIsPlayerConnected(id) then
                        if sampGetPlayerNickname(id):lower() == qsms.who:lower() then
                            qsms.who = tostring(id)
                            break
                        end
                    end
                end
            end
            qsms.sendServerCmd("/number "..qsms.who)
        end
    end

    function qsms.onServerMessage(color_int32, text)
        local ctext = text:gsub("{%x%x%x%x%x%x}", "")
        if qsms.who and ctext == "Телефонный справочник:" then
            return false
        elseif qsms.who and (
               ctext == "На сервере не найдено игроков по указанным вами параметрам."
            or ctext == "Абонентов по указанным вами параметрам в сети не найдено."
            or ctext == "Указанный вами игрок является ботом."
            or ctext == "Указанный вами игрок не залогинен."
            or ctext == "Человек, с указанным вами именем, не найден в телефонном справочнике."
            or ctext == "На сервере найдено несколько игроков по указанным вами параметрам."
            or ctext:find("не найден в телефонном справочнике")
            or ctext:find("не найдено игроков")
            or ctext:find("не имеет мобильного телефона")
        ) then
            qsms.who = nil
            qsms.do_call = false
        end
        if qsms.who then
            local number = ctext:match("Имя:%s*%S+%s+Телефон:%s*([%d%-]+)")
            if number then
                local sms_to_send = qsms.sms or ""
                local is_call = qsms.do_call
                qsms.who = nil
                qsms.do_call = false
                lua_thread.create(function()
                    wait(0)
                    if is_call then
                        qsms.sendServerCmd("/call "..number)
                    else
                        if qsms.set.ooc then
                            qsms.sendServerCmd("/t "..number.." (( "..sms_to_send.." ))")
                        else
                            qsms.sendServerCmd("/t "..number.." "..sms_to_send)
                        end
                    end
                end)
                return false
            end
        end
        if qsms.part then
            local check_part = ctext:match("^%.%.%.(.+)$")
            if check_part then
                ctext = qsms.part.." "..check_part
            end
        end
        local check_part = ctext:match("^(SMS: .+)%.%.%.$")
        if check_part then
            qsms.part = check_part
        end
        local srv_dir = qsms.current_server_name or qsms.getServerName() or "trinity"
        local outcoming_sms, nickname = ctext:match("^SMS: (.+) Для: (%S+) Тел: [%d%-]+$")
        if outcoming_sms then
            qsms.part = nil
            local lnickname = nickname:lower()
            if not qsms.chats[lnickname] then
                qsms.chats[lnickname] = {
                    set = {
                        nickname = nickname,
                        new = false
                    },
                    chat = {}
                }
            end
            qsms.chats[lnickname].set.nickname = nickname
            qsms.chats[lnickname].set.new = false
            qsms.chats[lnickname].set.ctime = os.time()
            qsms.chats[lnickname].set.hidden = false
            local value = {text = outcoming_sms, outcoming = true, nickname = qsms.sampGetMyNickname(), ctime = qsms.chats[lnickname].set.ctime}
            table.insert(qsms.chats[lnickname].chat, value)
            if qsms.auto_scroll then
                qsms.do_max_scroll = true
            end
            qsms.mcfg.append_value(value, qsms.dirname_chats.."\\"..srv_dir.."\\"..qsms.safe(lnickname).."\\chat.cfg")
            qsms.mcfg.save(qsms.chats[lnickname].set, qsms.dirname_chats.."\\"..srv_dir.."\\"..qsms.safe(lnickname).."\\set.cfg")
        end
        local incoming_sms, in_nickname = ctext:match("^SMS: (.+) От: (%S+) Тел: [%d%-]+$")
        if incoming_sms then
            qsms.part = nil
            local lnickname = in_nickname:lower()
            if not qsms.chats[lnickname] then
                qsms.chats[lnickname] = {
                    set = {
                        nickname = in_nickname,
                        new = true
                    },
                    chat = {}
                }
            end
            qsms.chats[lnickname].set.new = true
            qsms.chats[lnickname].set.nickname = in_nickname
            qsms.chats[lnickname].set.ctime = os.time()
            qsms.chats[lnickname].set.hidden = false
            local value = {text = incoming_sms, outcoming = false, nickname = in_nickname, ctime = qsms.chats[lnickname].set.ctime}
            table.insert(qsms.chats[lnickname].chat, value)
            if qsms.auto_scroll then
                qsms.do_max_scroll = true
            end
            qsms.mcfg.append_value(value, qsms.dirname_chats.."\\"..srv_dir.."\\"..qsms.safe(lnickname).."\\chat.cfg")
            qsms.mcfg.save(qsms.chats[lnickname].set, qsms.dirname_chats.."\\"..srv_dir.."\\"..qsms.safe(lnickname).."\\set.cfg")
            qsms.try_autoresponder(in_nickname, lnickname)
        end
    end

    function qsms.getChatInputPos()
        local in1 = sampGetInputInfoPtr()
        if not in1 or in1 == 0 then return 30, 300 end
        in1 = getStructElement(in1, 0x8, 4)
        if not in1 or in1 == 0 then return 30, 300 end
        local in2 = getStructElement(in1, 0x8, 4)
        local in3 = getStructElement(in1, 0xC, 4)
        return in2, in3 + 50
    end

    function qsms.isChatOverlayActive()
        if not hasAccess("advertising") then return false end
        if not qsms.set.show_chat_overlay then return false end
        if not isSampAvailable() or not sampIsChatInputActive() or sampIsScoreboardOpen() then
            return false
        end
        local chat_input_text = sampGetChatInputText()
        if not chat_input_text then return false end
        return (chat_input_text:match("^/[sS][mM][sS]%s+") ~= nil) or (chat_input_text:match("^/[tT]%s+") ~= nil)
    end

    function qsms.renderContactActions(lcur, srv_dir, t, popup_id)
        if not qsms.chats[lcur] then return end
        local chatSet = qsms.chats[lcur].set
        local isImp = chatSet.important and true or false
        local isCnt = chatSet.contacts and true or false
        local isHid = chatSet.hidden and true or false

        imgui.SameLine(0, 6)
        imgui.PushStyleVar(imgui.StyleVar.ItemSpacing, imgui.ImVec2(4, 4))
        imgui.PushStyleVar(imgui.StyleVar.FrameRounding, 5.0)

        -- 1. Звёздочка (Важные)
        if isImp then
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.85, 0.62, 0.12, 0.35))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.90, 0.68, 0.15, 0.50))
            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.00, 0.82, 0.25, 1.00))
        else
            imgui.PushStyleColor(imgui.Col.Button, t.frameBg)
            imgui.PushStyleColor(imgui.Col.ButtonHovered, t.buttonHov)
            imgui.PushStyleColor(imgui.Col.Text, t.textDim)
        end
        if imgui.Button((isImp and fa.ICON_STAR or fa.ICON_STAR_O) .. "##imp_" .. popup_id, imgui.ImVec2(26, 22)) then
            chatSet.important = not isImp
            qsms.mcfg.save(chatSet, qsms.dirname_chats.."\\"..srv_dir.."\\"..qsms.safe(lcur).."\\set.cfg")
        end
        imgui.PopStyleColor(3)
        if imgui.IsItemHovered() then
            imgui.SetTooltip(isImp and u8"Важные (нажмите, чтобы убрать)" or u8"Добавить в важные")
        end

        -- 2. Контакт (Контакты)
        imgui.SameLine()
        if isCnt then
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.35))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(t.accent.x, t.accent.y, t.accent.z, 0.55))
            imgui.PushStyleColor(imgui.Col.Text, t.accent)
        else
            imgui.PushStyleColor(imgui.Col.Button, t.frameBg)
            imgui.PushStyleColor(imgui.Col.ButtonHovered, t.buttonHov)
            imgui.PushStyleColor(imgui.Col.Text, t.textDim)
        end
        if imgui.Button((isCnt and fa.ICON_ADDRESS_BOOK or fa.ICON_USER_PLUS) .. "##cnt_" .. popup_id, imgui.ImVec2(26, 22)) then
            chatSet.contacts = not isCnt
            qsms.mcfg.save(chatSet, qsms.dirname_chats.."\\"..srv_dir.."\\"..qsms.safe(lcur).."\\set.cfg")
        end
        imgui.PopStyleColor(3)
        if imgui.IsItemHovered() then
            imgui.SetTooltip(isCnt and u8"В контактах (нажмите, чтобы убрать)" or u8"Добавить в контакты")
        end

        -- 3. Скрытые (Глаз)
        imgui.SameLine()
        if isHid then
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.85, 0.30, 0.30, 0.35))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.90, 0.35, 0.35, 0.55))
            imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.00, 0.45, 0.45, 1.00))
        else
            imgui.PushStyleColor(imgui.Col.Button, t.frameBg)
            imgui.PushStyleColor(imgui.Col.ButtonHovered, t.buttonHov)
            imgui.PushStyleColor(imgui.Col.Text, t.textDim)
        end
        if imgui.Button(fa.ICON_EYE_SLASH .. "##hid_" .. popup_id, imgui.ImVec2(26, 22)) then
            chatSet.hidden = not isHid
            qsms.mcfg.save(chatSet, qsms.dirname_chats.."\\"..srv_dir.."\\"..qsms.safe(lcur).."\\set.cfg")
        end
        imgui.PopStyleColor(3)
        if imgui.IsItemHovered() then
            imgui.SetTooltip(isHid and u8"Скрытый чат (нажмите, чтобы вернуть)" or u8"Скрыть чат")
        end

        -- 4. Меню действий (...)
        imgui.SameLine()
        imgui.PushStyleColor(imgui.Col.Button, t.frameBg)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, t.buttonHov)
        imgui.PushStyleColor(imgui.Col.Text, t.textDim)
        if imgui.Button(fa.ICON_ELLIPSIS_H .. "##more_btn_" .. popup_id, imgui.ImVec2(26, 22)) then
            imgui.OpenPopup(popup_id)
        end
        imgui.PopStyleColor(3)
        if imgui.IsItemHovered() then
            imgui.SetTooltip(u8"Управление перепиской")
        end

        imgui.PopStyleVar(2)

        if imgui.BeginPopup(popup_id) then
            if qsms.close_current_popup then
                qsms.close_current_popup = false
                imgui.CloseCurrentPopup()
            end
            if imgui.Selectable(fa.ICON_TRASH_O .. u8"  Очистить переписку") then
                qsms.chats[lcur].chat = {}
                qsms.mcfg.save(qsms.chats[lcur].chat, qsms.dirname_chats.."\\"..srv_dir.."\\"..qsms.safe(lcur).."\\chat.cfg")
            end
            if imgui.Selectable(fa.ICON_TRASH .. u8"  Удалить чат") then
                local target_dir = qsms.dirname_chats.."\\"..srv_dir.."\\"..qsms.safe(lcur)
                if doesDirectoryExist(target_dir) then
                    for name in lfs.dir(target_dir) do
                        if name ~= "." and name ~= ".." then
                            os.remove(target_dir.."\\"..name)
                        end
                    end
                    lfs.rmdir(target_dir)
                end
                qsms.chats[lcur] = nil
                qsms.lcurrent_nickname = nil
                qsms.current_nickname = nil
                qsms.last_chat_input_text = nil
            end
            imgui.EndPopup()
        end
        if popup_id == "qsms_more" then
            qsms.popup_is_open = imgui.IsPopupOpen(popup_id)
        end
        if qsms.lcurrent_nickname and qsms.chats[qsms.lcurrent_nickname] and qsms.chats[qsms.lcurrent_nickname].set.new then
            qsms.chats[qsms.lcurrent_nickname].set.new = false
            qsms.mcfg.save(qsms.chats[qsms.lcurrent_nickname].set, qsms.dirname_chats.."\\"..srv_dir.."\\"..qsms.safe(qsms.lcurrent_nickname).."\\set.cfg")
        end
    end

    -- Отрисовка вкладки Quick SMS прямо внутри окна TRPcomm Manager
    function qsms.drawTab(t)
        local sorted_chats = qsms.sort_chats(qsms.chats)
        local srv_dir = qsms.current_server_name or qsms.getServerName() or "trinity"
        local online = {}
        for id = 0, sampGetMaxPlayerId(false) do
            if sampIsPlayerConnected(id) and not sampIsPlayerNpc(id) then
                local nickname = sampGetPlayerNickname(id)
                online[nickname:lower()] = id
            end
        end

        -- Панель под-вкладок Quick SMS
        imgui.PushStyleVar(imgui.StyleVar.ItemSpacing, imgui.ImVec2(6, 8))
        if imgui.ButtonActivated(qsms.set.current_tab=="all", fa.ICON_COMMENTS .. u8" Все##qsms_tab_all", imgui.ImVec2(72, 28)) then
            qsms.set.current_tab = "all"
            qsms.mcfg.save(qsms.set, qsms.filename_set)
        end
        imgui.SameLine()
        if imgui.ButtonActivated(qsms.set.current_tab=="new", fa.ICON_ENVELOPE .. u8" Новые##qsms_tab_new", imgui.ImVec2(88, 28)) then
            qsms.set.current_tab = "new"
            qsms.mcfg.save(qsms.set, qsms.filename_set)
        end
        imgui.SameLine()
        if imgui.ButtonActivated(qsms.set.current_tab=="important", fa.ICON_STAR .. u8" Важные##qsms_tab_imp", imgui.ImVec2(95, 28)) then
            qsms.set.current_tab = "important"
            qsms.mcfg.save(qsms.set, qsms.filename_set)
        end
        imgui.SameLine()
        if imgui.ButtonActivated(qsms.set.current_tab=="contacts", fa.ICON_ADDRESS_BOOK .. u8" Контакты##qsms_tab_cnt", imgui.ImVec2(105, 28)) then
            qsms.set.current_tab = "contacts"
            qsms.mcfg.save(qsms.set, qsms.filename_set)
        end
        imgui.SameLine()
        if imgui.ButtonActivated(qsms.set.current_tab=="autoresponder", fa.ICON_CLOCK_O .. u8" Автоответчик##qsms_tab_ar", imgui.ImVec2(125, 28)) then
            qsms.set.current_tab = "autoresponder"
            qsms.mcfg.save(qsms.set, qsms.filename_set)
        end
        imgui.SameLine()
        if imgui.ButtonActivated(qsms.set.current_tab=="hotkeys_info", fa.ICON_COG .. u8" Клавиши и инфо##qsms_tab_hk", imgui.ImVec2(135, 28)) then
            qsms.set.current_tab = "hotkeys_info"
            qsms.mcfg.save(qsms.set, qsms.filename_set)
        end
        imgui.SameLine()
        if imgui.Checkbox(u8"OOC (( SMS ))##qsms_top_ooc", qsms.img.ooc) then
            qsms.set.ooc = qsms.img.ooc.v
            qsms.mcfg.save(qsms.set, qsms.filename_set)
        end
        imgui.PopStyleVar()
        imgui.Separator()

        if qsms.set.current_tab == "autoresponder" then
            qsms.render_autoresponder_tab(sorted_chats)
            return
        elseif qsms.set.current_tab == "hotkeys_info" then
            qsms.render_hotkeys_and_help_tab(t)
            return
        end

        imgui.Columns(2, "qsms_main_cols", true)
        local column_width = 250
        imgui.SetColumnWidth(-1, imgui.GetWindowWidth() - column_width)

        -- ЛЕВАЯ КОЛОНКА: Выбранный диалог и отправка сообщений
        imgui.BeginChild("qsms_tab_left", imgui.ImVec2(0, 0), false)
            local lcur = qsms.lcurrent_nickname
            if qsms.current_nickname and lcur then
                local displayNick = (qsms.chats[lcur] and qsms.chats[lcur].set.nickname) or qsms.current_nickname
                imgui.DotGreen(online[lcur])
                imgui.SameLine()
                imgui.TextColored(t.accent, u8(displayNick .. (online[lcur] and (" ["..online[lcur].."]") or "")))
                imgui.SameLine()
                if imgui.ButtonClickable(online[lcur], fa.ICON_PHONE .. u8" Позвонить##qsms_call_btn", imgui.ImVec2(95, 22)) then
                    qsms.call_func(lcur)
                end
                if qsms.set.ooc then
                    imgui.SameLine()
                    imgui.TextDisabled(u8"(( OOC SMS ))")
                end

                if qsms.chats[lcur] then
                    qsms.renderContactActions(lcur, srv_dir, t, "qsms_tab_more")
                end
            else
                imgui.TextColored(t.textDim, u8"Выберите диалог в списке справа или найдите игрока через поиск")
            end

            imgui.Separator()

            -- История сообщений
            imgui.BeginChild("qsms_tab_messages", imgui.ImVec2(0, -36), false)
                if qsms.current_nickname and qsms.lcurrent_nickname and qsms.chats[qsms.lcurrent_nickname] then
                    local last_date = nil
                    local outCol = imgui.ImVec4(t.button.x, t.button.y, t.button.z, 0.85)
                    local inCol  = imgui.ImVec4(t.frameBg.x, t.frameBg.y, t.frameBg.z, 0.95)
                    for index, item in ipairs(qsms.chats[qsms.lcurrent_nickname].chat) do
                        if os.date("%d.%m.%Y", item.ctime) ~= last_date then
                            last_date = os.date("%d.%m.%Y", item.ctime)
                            local calc = imgui.CalcTextSize(last_date)
                            imgui.SetCursorPosX(math.max(0, imgui.GetContentRegionMax().x / 2 - calc.x / 2))
                            imgui.TextDisabled(last_date)
                        end
                        if item.outcoming then
                            if imgui.Bubble("tab_msg_"..tostring(index), outCol, u8(item.text), u8(item.nickname).." | "..os.date("%H:%M:%S | %d.%m.%Y", item.ctime), u8"Сообщение скопировано", true) then
                                imgui.SetClipboardText(u8(item.text))
                            end
                        else
                            if imgui.Bubble("tab_msg_"..tostring(index), inCol, u8(item.text), u8(item.nickname).." | "..os.date("%H:%M:%S | %d.%m.%Y", item.ctime), u8"Сообщение скопировано", false) then
                                imgui.SetClipboardText(u8(item.text))
                            end
                        end
                    end
                    if qsms.do_max_scroll then
                        qsms.do_max_scroll = false
                        imgui.SetScrollHere()
                    end
                    qsms.auto_scroll = imgui.GetScrollY() == imgui.GetScrollMaxY()
                elseif qsms.current_nickname then
                    imgui.Spacing()
                    imgui.TextColored(t.textDim, u8"История переписки с этим игроком пока пуста. Напишите первое сообщение ниже!")
                end
            imgui.EndChild()

            -- Поле ввода и отправки SMS прямо из меню TRPcomm Manager
            if qsms.current_nickname then
                local availW = imgui.GetContentRegionAvail().x
                imgui.PushItemWidth(math.max(100, availW - 105))
                local enterPressed = imgui.InputText("##qsms_menu_sms_input", qsms.menu_sms_buf, imgui.InputTextFlags.EnterReturnsTrue)
                imgui.PopItemWidth()
                imgui.SameLine()
                local sendClicked = imgui.Button(fa.ICON_PAPER_PLANE .. u8" Отправить##qsms_menu_send", imgui.ImVec2(95, 24))
                if (enterPressed or sendClicked) and qsms.menu_sms_buf.v ~= "" then
                    local rawMsg = u8:decode(qsms.menu_sms_buf.v)
                    if rawMsg:gsub("%s+", "") ~= "" then
                        qsms.sms_func(qsms.current_nickname .. " " .. rawMsg)
                        qsms.menu_sms_buf.v = ""
                        qsms.do_max_scroll = true
                    end
                end
            end
        imgui.EndChild()

        imgui.NextColumn()
        imgui.SetColumnWidth(-1, column_width)

        -- ПРАВАЯ КОЛОНКА: Поиск и список диалогов
        imgui.BeginChild("qsms_tab_right", imgui.ImVec2(0, 0), false)
            imgui.TextColored(t.textDim, fa.ICON_SEARCH .. u8" Поиск игрока / чата:")
            local isHidActive = (qsms.set.current_tab == "hidden")
            imgui.PushItemWidth(imgui.GetContentRegionAvailWidth() - 32)
            imgui.InputText("##qsms_menu_search", qsms.menu_search_buf)
            imgui.PopItemWidth()
            imgui.SameLine(0, 4)
            local hidPushed = 0
            if isHidActive then
                imgui.PushStyleColor(imgui.Col.Button, t.accent)
                imgui.PushStyleColor(imgui.Col.ButtonHovered, t.accent)
                hidPushed = 2
            else
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(t.frameBg.x, t.frameBg.y, t.frameBg.z, 0.60))
                imgui.PushStyleColor(imgui.Col.Text, t.textDim)
                hidPushed = 2
            end
            if imgui.Button(fa.ICON_EYE_SLASH .. "##qsms_tab_hid_discreet", imgui.ImVec2(26, 20)) then
                qsms.set.current_tab = isHidActive and "all" or "hidden"
                qsms.mcfg.save(qsms.set, qsms.filename_set)
            end
            imgui.PopStyleColor(hidPushed)
            if imgui.IsItemHovered() then
                imgui.SetTooltip(isHidActive and u8"Скрытые диалоги (нажмите, чтобы вернуться ко всем)" or u8"Показать скрытые диалоги")
            end
            imgui.Separator()

            imgui.BeginChild("qsms_tab_contacts_scroll", imgui.ImVec2(0, 0), false)
                local rawSearch = u8:decode(qsms.menu_search_buf.v):gsub("^%s+", ""):gsub("%s+$", "")
                local function render_contact_item(nickname, lnickname)
                    local is_new = qsms.chats[lnickname] and qsms.chats[lnickname].set.new
                    if is_new then
                        imgui.PushStyleColor(imgui.Col.Text, t.accent)
                    end
                    imgui.DotGreen(online[lnickname])
                    imgui.SameLine()
                    if imgui.Selectable(" "..nickname..(online[lnickname] and " ["..online[lnickname].."]" or "").."##cnt_"..lnickname, qsms.lcurrent_nickname == lnickname) then
                        qsms.current_nickname = nickname
                        qsms.lcurrent_nickname = lnickname
                        qsms.do_max_scroll = true
                    end
                    if is_new then
                        imgui.PopStyleColor()
                    end
                end

                if rawSearch ~= "" then
                    local s_low = rawSearch:lower()
                    for _, item in ipairs(sorted_chats) do
                        local nickname = item[2].set.nickname
                        local lnickname = nickname:lower()
                        if lnickname:find(s_low, 1, true) or (tonumber(rawSearch) and online[lnickname] == tonumber(rawSearch)) then
                            render_contact_item(nickname, lnickname)
                        end
                    end
                    for lnickname, id in pairs(online) do
                        if not qsms.chats[lnickname] then
                            local nickname = sampGetPlayerNickname(id)
                            if lnickname:find(s_low, 1, true) or (tonumber(rawSearch) and id == tonumber(rawSearch)) then
                                render_contact_item(nickname, lnickname)
                            end
                        end
                    end
                else
                    for _, item in ipairs(sorted_chats) do
                        local nickname = item[2].set.nickname
                        local lnickname = nickname:lower()
                        if qsms.set.current_tab == "all" then
                            if not item[2].set.hidden then
                                render_contact_item(nickname, lnickname)
                            end
                        elseif qsms.set.current_tab == "new" then
                            if item[2].set.new or qsms.lcurrent_nickname == lnickname then
                                render_contact_item(nickname, lnickname)
                            end
                        elseif qsms.set.current_tab == "important" then
                            if item[2].set.important then
                                render_contact_item(nickname, lnickname)
                            end
                        elseif qsms.set.current_tab == "contacts" then
                            if item[2].set.contacts then
                                render_contact_item(nickname, lnickname)
                            end
                        elseif qsms.set.current_tab == "hidden" then
                            if item[2].set.hidden then
                                render_contact_item(nickname, lnickname)
                            end
                        end
                    end
                end
            imgui.EndChild()
        imgui.EndChild()
        imgui.Columns(1)
    end

    -- Отрисовка всплывающего помощника под чатом игры при вводе /sms или /t
    function qsms.onDrawFrame()
        local chatActive = qsms.isChatOverlayActive()
        if not chatActive then
            return
        end

        local px, py = qsms.getChatInputPos()
        local t = getTheme()

        pushThemeColors()
        pushThemeRounding()

        local chat_input_text = sampGetChatInputText() or ""
        local online = {}
        for id = 0, sampGetMaxPlayerId(false) do
            if sampIsPlayerConnected(id) and not sampIsPlayerNpc(id) then
                local nickname = sampGetPlayerNickname(id)
                online[nickname:lower()] = id
            end
        end
        if qsms.last_chat_input_text ~= chat_input_text then
            local input = chat_input_text:match("^/[sS][mM][sS]%s+(%S+)%s+") or chat_input_text:match("^/[tT]%s+(%S+)%s+")
            if input then
                if input:match("^[%d%-]+$") then
                    if sampIsPlayerConnected(tonumber(input)) then
                        input = sampGetPlayerNickname(tonumber(input))
                    end
                end
                if qsms.current_nickname ~= input then
                    qsms.current_nickname = input
                    qsms.lcurrent_nickname = qsms.current_nickname:lower()
                    qsms.do_max_scroll = true
                end
            else
                qsms.current_nickname = nil
                qsms.lcurrent_nickname = nil
            end
            if not qsms.current_nickname then
                qsms.search = {}
                local s_input = chat_input_text:match("^/[sS][mM][sS]%s+(%S*)$") or chat_input_text:match("^/[tT]%s+(%S*)$") or ""
                if s_input:match("^%+") or s_input:match("%-") then
                    s_input = ""
                end
                for lnickname, id in pairs(online) do
                    if not qsms.chats[lnickname] then
                        local nickname = sampGetPlayerNickname(id)
                        if lnickname:find(s_input:lower(), 1, true) or (tonumber(s_input) and sampIsPlayerConnected(tonumber(s_input)) and sampGetPlayerNickname(tonumber(s_input)) == nickname) then
                            table.insert(qsms.search, nickname)
                        end
                    end
                end
                for lnickname, item in pairs(qsms.chats) do
                    if lnickname:find(s_input:lower(), 1, true) or (tonumber(s_input) and sampIsPlayerConnected(tonumber(s_input)) and sampGetPlayerNickname(tonumber(s_input)) == item.set.nickname) then
                        table.insert(qsms.search, item.set.nickname)
                    end
                end
                qsms.searching = true
                qsms.do_min_scroll = true
            else
                qsms.searching = false
            end
        end
        qsms.last_chat_input_text = chat_input_text
        local srv_dir = qsms.current_server_name or qsms.getServerName() or "trinity"
        local isSearchCompact = qsms.searching and (qsms.set.current_tab ~= "autoresponder" and qsms.set.current_tab ~= "hotkeys_info")
        local winW = 720
        local winH = isSearchCompact and 170 or 230
        imgui.SetNextWindowSize(imgui.ImVec2(winW, winH), imgui.Cond.Always)
        imgui.SetNextWindowPos(imgui.ImVec2(px, py), imgui.Cond.Always)
        imgui.Begin(u8(qsms.MAIN_TITLE).."##qsms_window_chat", qsms.img.window_chat, imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar)
            local sorted_chats = qsms.sort_chats(qsms.chats)
            imgui.PushStyleVar(imgui.StyleVar.ItemSpacing, imgui.ImVec2(6, 8))
            if imgui.ButtonActivated(qsms.set.current_tab=="all", fa.ICON_COMMENTS .. u8" Все", imgui.ImVec2(70, 28)) then
                qsms.set.current_tab = "all"
                qsms.mcfg.save(qsms.set, qsms.filename_set)
            end
            imgui.SameLine()
            if imgui.ButtonActivated(qsms.set.current_tab=="new", fa.ICON_ENVELOPE .. u8" Новые", imgui.ImVec2(88, 28)) then
                qsms.set.current_tab = "new"
                qsms.mcfg.save(qsms.set, qsms.filename_set)
            end
            imgui.SameLine()
            if imgui.ButtonActivated(qsms.set.current_tab=="autoresponder", fa.ICON_COG .. u8" Настройки", imgui.ImVec2(110, 28)) then
                qsms.set.current_tab = "autoresponder"
                qsms.mcfg.save(qsms.set, qsms.filename_set)
            end
            imgui.SameLine()
            if imgui.ButtonActivated(qsms.set.current_tab=="important", fa.ICON_STAR .. u8" Важные", imgui.ImVec2(92, 28)) then
                qsms.set.current_tab = "important"
                qsms.mcfg.save(qsms.set, qsms.filename_set)
            end
            imgui.SameLine()
            if imgui.ButtonActivated(qsms.set.current_tab=="contacts", fa.ICON_ADDRESS_BOOK .. u8" Контакты", imgui.ImVec2(105, 28)) then
                qsms.set.current_tab = "contacts"
                qsms.mcfg.save(qsms.set, qsms.filename_set)
            end
            imgui.SameLine(imgui.GetWindowWidth() - 44)
            local isOvHid = (qsms.set.current_tab == "hidden")
            if imgui.ButtonActivated(isOvHid, fa.ICON_EYE_SLASH .. "##ov_hid", imgui.ImVec2(30, 28)) then
                qsms.set.current_tab = isOvHid and "all" or "hidden"
                qsms.mcfg.save(qsms.set, qsms.filename_set)
            end
            if imgui.IsItemHovered() then
                imgui.SetTooltip(isOvHid and u8"Скрытые диалоги (нажмите, чтобы вернуться)" or u8"Скрытые диалоги")
            end
            imgui.PopStyleVar()
            imgui.Separator()
            if qsms.set.current_tab == "autoresponder" or qsms.set.current_tab == "hotkeys_info" then
                imgui.BeginChild("qsms_ov_ar_scroll", imgui.ImVec2(0, 0), false); qsms.render_autoresponder_tab(sorted_chats, true); imgui.EndChild()
            else
                imgui.Columns(2, nil, true)
                local column_width = 230
                imgui.SetColumnWidth(-1, imgui.GetWindowWidth() - column_width)
                imgui.BeginChild("qsms_text_head", imgui.ImVec2(0, 0), false)
                    if qsms.searching then
                        imgui.TextDisabled(u8"Результаты поиска")
                        imgui.Separator()
                    elseif qsms.current_nickname then
                        local lcur = qsms.lcurrent_nickname
                        if qsms.chats[lcur] then
                            imgui.DotGreen(online[lcur])
                            imgui.SameLine()
                            imgui.TextColored(t.accent, u8(qsms.chats[lcur].set.nickname..(online[lcur] and " ["..online[lcur].."]" or "")))
                            imgui.SameLine()
                            if imgui.ButtonClickable(online[lcur], fa.ICON_PHONE .. u8" Позвонить", imgui.ImVec2(95, 22)) then
                                qsms.call_func(lcur)
                            end
                            qsms.renderContactActions(lcur, srv_dir, t, "qsms_more")
                            if qsms.set.ooc then
                                imgui.SameLine()
                                imgui.TextDisabled(u8"(( SMS ))")
                            end
                            imgui.Separator()
                        else
                            imgui.DotGreen(online[lcur])
                            imgui.SameLine()
                            imgui.TextColored(t.accent, u8(qsms.current_nickname..(online[lcur] and " ["..online[lcur].."]" or "")))
                            imgui.SameLine()
                            if imgui.ButtonClickable(online[lcur], fa.ICON_PHONE .. u8" Позвонить", imgui.ImVec2(95, 22)) then
                                qsms.call_func(lcur)
                            end
                            if qsms.set.ooc then
                                imgui.SameLine()
                                imgui.TextDisabled(u8"(( SMS ))")
                            end
                            imgui.Separator()
                        end
                    end
                    imgui.BeginChild("qsms_text", imgui.ImVec2(0, 0), false)
                        local outCol = imgui.ImVec4(t.button.x, t.button.y, t.button.z, 0.85)
                        local inCol  = imgui.ImVec4(t.frameBg.x, t.frameBg.y, t.frameBg.z, 0.95)
                        if qsms.current_nickname and qsms.chats[qsms.lcurrent_nickname] then
                            local last_date = nil
                            for index, item in ipairs(qsms.chats[qsms.lcurrent_nickname].chat) do
                                if os.date("%d.%m.%Y", item.ctime) ~= last_date then
                                    last_date = os.date("%d.%m.%Y", item.ctime)
                                    local calc = imgui.CalcTextSize(last_date)
                                    imgui.SetCursorPosX(math.max(0, imgui.GetContentRegionMax().x / 2 - calc.x / 2))
                                    imgui.TextDisabled(last_date)
                                end
                                if item.outcoming then
                                    if imgui.Bubble("ov_msg_"..tostring(index), outCol, u8(item.text), u8(item.nickname).." | "..os.date("%H:%M:%S | %d.%m.%Y", item.ctime), u8"Сообщение скопировано", true) then
                                        imgui.SetClipboardText(u8(item.text))
                                    end
                                else
                                    if imgui.Bubble("ov_msg_"..tostring(index), inCol, u8(item.text), u8(item.nickname).." | "..os.date("%H:%M:%S | %d.%m.%Y", item.ctime), u8"Сообщение скопировано", false) then
                                        imgui.SetClipboardText(u8(item.text))
                                    end
                                end
                            end
                            if qsms.do_max_scroll then
                                qsms.do_max_scroll = false
                                imgui.SetScrollHere()
                            end
                            qsms.auto_scroll = imgui.GetScrollY() == imgui.GetScrollMaxY()
                        elseif qsms.searching then
                            if qsms.do_min_scroll then
                                qsms.do_min_scroll = false
                                imgui.SetScrollHere()
                            end
                            imgui.PushStyleVar(imgui.StyleVar.ItemSpacing, imgui.ImVec2(6, 4))
                            local max_show = math.min(3, #qsms.search)
                            for idx = 1, max_show do
                                local nickname = qsms.search[idx]
                                local lnickname = nickname:lower()
                                imgui.DotGreen(online[lnickname])
                                imgui.SameLine()
                                if imgui.Selectable(" "..nickname..(online[lnickname] and " ["..online[lnickname].."]" or "")) then
                                    sampSetChatInputText("/sms "..nickname.." ")
                                end
                            end
                            imgui.PopStyleVar()
                        end
                    imgui.EndChild()
                imgui.EndChild()
                imgui.NextColumn()
                imgui.SetColumnWidth(-1, column_width)
                imgui.BeginChild("qsms_chats_head", imgui.ImVec2(0, 0), false)
                    imgui.BeginChild("qsms_chats", imgui.ImVec2(0, 0), false)
                        local function some_render(nickname, lnickname)
                            local is_new = qsms.chats[lnickname].set.new
                            if is_new then
                                imgui.PushStyleColor(imgui.Col.Text, t.accent)
                            end
                            imgui.DotGreen(online[lnickname])
                            imgui.SameLine()
                            if imgui.Selectable(" "..nickname..(online[lnickname] and " ["..online[lnickname].."]" or ""), qsms.lcurrent_nickname == lnickname) then
                                sampSetChatInputText("/sms "..nickname.." ")
                            end
                            if is_new then
                                imgui.PopStyleColor()
                            end
                        end
                        for _, item in ipairs(sorted_chats) do
                            local nickname = item[2].set.nickname
                            local lnickname = nickname:lower()
                            if qsms.set.current_tab == "all" then
                                if not item[2].set.hidden then
                                    some_render(nickname, lnickname)
                                end
                            elseif qsms.set.current_tab == "new" then
                                if item[2].set.new or qsms.lcurrent_nickname == lnickname then
                                    some_render(nickname, lnickname)
                                end
                            elseif qsms.set.current_tab == "important" then
                                if item[2].set.important then
                                    some_render(nickname, lnickname)
                                end
                            elseif qsms.set.current_tab == "contacts" then
                                if item[2].set.contacts then
                                    some_render(nickname, lnickname)
                                end
                            elseif qsms.set.current_tab == "hidden" then
                                if item[2].set.hidden then
                                    some_render(nickname, lnickname)
                                end
                            end
                        end
                    imgui.EndChild()
                imgui.EndChild()
                imgui.Columns(1)
            end
            local size = imgui.GetWindowSize()
            if size.x ~= qsms.set.chat_size[1] or size.y ~= qsms.set.chat_size[2] then
                qsms.set.chat_size = {size.x, size.y}
                qsms.mcfg.save(qsms.set, qsms.filename_set)
            end
        imgui.End()

        imgui.PopStyleVar(THEME_ROUNDING_COUNT)
        imgui.PopStyleColor(THEME_COLOR_COUNT)
    end

    function qsms.init()
        qsms.indicator = renderCreateFont("Arial", 12, 5)
        sampRegisterChatCommand("sms", qsms.sms_func)
        sampRegisterChatCommand("smss", qsms.sms_func)
        sampRegisterChatCommand("t", qsms.sms_func)
        qsms.hotkeys = {
            new_sms = qsms.hkeys.register(qsms.set.new_sms, qsms.hkeys.DOWN, false, true, qsms.new_sms),
            reply_sms = qsms.hkeys.register(qsms.set.reply_sms, qsms.hkeys.DOWN, false, true, qsms.reply_sms),
        }
    end

    function qsms.tick(chatOverlayActive)
        local inMenuTab = main_window_state.v and open_tabs[active_tab_idx] and open_tabs[active_tab_idx].kind == "quicksms"
        if not chatOverlayActive and not inMenuTab then
            if qsms.popup_is_open then
                qsms.close_current_popup = true
            end
            qsms.last_chat_input_text = nil
            qsms.searching = false
        end

        if qsms.set.autoresponder.enabled and qsms.set.autoresponder.end_time > 0
           and os.time() >= qsms.set.autoresponder.end_time then
            qsms.set.autoresponder.enabled = false
            qsms.set.autoresponder.end_time = 0
            qsms.mcfg.save(qsms.set, qsms.filename_set)
            sampAddChatMessage("• {FFC800}[Мессенджер]{FFFFFF} Автоответчик отключён по таймеру.", 0xFFFFFF)
        end

        qsms.current_server_name = qsms.getServerName()
        if qsms.current_server_name and qsms.current_server_name ~= qsms.server_name then
            qsms.chats = {}
            local srv_chats_dir = qsms.dirname_chats.."\\"..qsms.current_server_name
            if not doesDirectoryExist(srv_chats_dir) then
                createDirectory(srv_chats_dir)
            end
            local ok_dir, iter, dir_obj = pcall(lfs.dir, srv_chats_dir)
            if ok_dir and iter then
                for nickname in iter, dir_obj do
                    if nickname ~= "." and nickname ~= ".." then
                        local lnickname = nickname:lower()
                        local chat_cfg = qsms.mcfg.load(srv_chats_dir.."\\"..lnickname.."\\chat.cfg")
                        local set_cfg = qsms.mcfg.load(srv_chats_dir.."\\"..lnickname.."\\set.cfg")
                        if chat_cfg and set_cfg and set_cfg.nickname and set_cfg.ctime then
                            qsms.chats[set_cfg.nickname:lower()] = {
                                set = set_cfg,
                                chat = chat_cfg
                            }
                        end
                    end
                end
            end
            qsms.server_name = qsms.current_server_name
        end

        if chatOverlayActive and isKeyJustPressed(0x09) then -- VK_TAB: переключение разделов
            local overlay_tabs = { "all", "new", "autoresponder", "important", "contacts", "hidden" }
            local cur_idx = 1
            for i, tname in ipairs(overlay_tabs) do
                if tname == qsms.set.current_tab then
                    cur_idx = i
                    break
                end
            end
            local next_idx = (cur_idx % #overlay_tabs) + 1
            qsms.set.current_tab = overlay_tabs[next_idx]
            qsms.mcfg.save(qsms.set, qsms.filename_set)
        end

        qsms.new = false
        for _, item in pairs(qsms.chats) do
            if item.set and item.set.new then
                qsms.new = true
                break
            end
        end

        if qsms.new and qsms.indicator then
            local px, py = qsms.getChatInputPos()
            renderFontDrawText(qsms.indicator, "SMS", px + 50, py, 0xFFFF8800)
        end
    end
end

esc_consumed = false

function onWindowMessage(msg, wparam, lparam)
    if wparam == 0x1B then -- VK_ESCAPE
        if isSampAvailable() and (sampIsChatInputActive() or sampIsDialogActive()) then
            return
        end
        if msg == 0x0100 then -- WM_KEYDOWN
            local qsmsMenuOpen = qsms and qsms.img and qsms.img.window_menu.v
            if (main_window_state and main_window_state.v) or ad_add_form_open or gallery_preview_open or gallery_send_form_open or tracker_report_form_open or qsmsMenuOpen then
                esc_consumed = true
                if ad_add_form_open then
                    ad_add_form_open = false
                    ad_edit_idx = nil
                elseif gallery_preview_open then
                    gallery_preview_open = false
                elseif gallery_send_form_open then
                    gallery_send_form_open = false
                elseif tracker_report_form_open then
                    tracker_report_form_open = false
                elseif qsmsMenuOpen then
                    qsms.img.window_menu.v = false
                elseif main_window_state and main_window_state.v then
                    main_window_state.v = false
                end
                consumeWindowMessage(true, true)
            elseif esc_consumed then
                consumeWindowMessage(true, true)
            end
        elseif msg == 0x0101 then -- WM_KEYUP
            if esc_consumed then
                esc_consumed = false
                consumeWindowMessage(true, true)
            end
        end
    end
end

function main()
    repeat wait(0) until isSampAvailable()

    local result, my1id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    clientName = sampGetPlayerNickname(my1id)

    toast_font = renderCreateFont("Arial", 9, 1)
    event_card_font_title = renderCreateFont("Arial", 10, 1)
    event_card_font_name  = renderCreateFont("Arial", 13, 1)
    event_card_font_time  = renderCreateFont("Arial", 11, 1)
    event_card_logo_texture = renderLoadTextureFromFile(getWorkingDirectory() .. "\\resource\\TRPcomm Manager\\images\\trpcomm-logo.png")

    -- Фоновый прогрев ImGui: активируем на 2-3 кадра во время загрузки,
    -- чтобы скомпилировать шрифт (Cyrillic + FontAwesome) и Direct3D-текстуры в фоне.
    -- Так как main_window_state.v = false, визуально ничего не появится,
    -- зато при нажатии клавиши меню откроется МГНОВЕННО (0 мс задержки).
    loadLogoTexture()
    imgui.Process = true
    wait(60)
    imgui.Process = false

    -- Запуск сетевых запросов в фоновом потоке (effil/async) с задержкой 2 сек,
    -- чтобы не создавать ни малейшей нагрузки на игру при входе и спавне.
    lua_thread.create(function()
        wait(2000)
        checkForUpdates()
        loadAllAccessLists()
        fetchCalendarEvents()
        fetchBuiltinRoleTemplates()
        fetchAdRestrictions(true)

        while true do
            wait(60000)
            fetchAdRestrictions(false)
        end
    end)

    sampAddChatMessage('{5B85C4}[TRPcomm Manager]{FFFFFF} Добро пожаловать на сервер, {5B85C4}' .. clientName .. '{FFFFFF}.', -1)
    sampAddChatMessage('{FFFFFF}Для активации скрипта используйте команду — {5B85C4}/trpcomm {FFFFFF}или {5B85C4}' .. hotkey_display.v .. '{FFFFFF}.', -1)

        sampRegisterChatCommand('trpcomm', function()
        main_window_state.v = not main_window_state.v
    end)

        sampRegisterChatCommand('trpcard', function()
        event_card_message = "Осталось 30 минут"
        event_card_timer = 210
    end)

    if qsms and qsms.init then
        qsms.init()
    end

        while true do
        wait(0)
        local qsmsMenuOpen = (qsms and qsms.img and qsms.img.window_menu.v) or false
        local qsmsChatOpen = (qsms and qsms.isChatOverlayActive and qsms.isChatOverlayActive()) or false
        imgui.ShowCursor = main_window_state.v or qsmsMenuOpen
        imgui.Process = main_window_state.v or qsmsMenuOpen or qsmsChatOpen
        if qsms and qsms.tick then
            qsms.tick(qsmsChatOpen)
        end

        if ad_pending and not ad_awaiting_next_city and ad_pending_deadline > 0 and os.time() > ad_pending_deadline then
            ad_pending = false
            ad_pending_deadline = 0
            sampAddChatMessage('{FFAA00}[TRPcomm] {FFFFFF}Ожидание диалогов сервера прервано — ответа не было.', -1)
        end
        if ad_awaiting_next_city and os.time() > ad_next_city_at then
            advanceAfterNewsPopup()
        end

        if notifications_enabled.v and toast_timer > 0 then
            toast_timer = toast_timer - 1
            local sw, sh = getScreenResolution()

            local alpha
            if toast_timer > 135 then
                alpha = (150 - toast_timer) / 15.0   -- появление
            elseif toast_timer < 15 then
                alpha = toast_timer / 15.0            -- исчезание
            else
                alpha = 1.0                           -- полная видимость
            end
            alpha = math.max(0.0, math.min(1.0, alpha))

            local a_bg    = math.floor(alpha * 0xCC)
            local a_full  = math.floor(alpha * 0xFF)

            local col_bg     = a_bg   * 0x1000000 + 0x111111
            local col_accent = a_full * 0x1000000 + 0x5B85C4 -- фирменный синий TRPcomm вместо золотого из trinity
            local col_white  = a_full * 0x1000000 + 0xFFFFFF

            renderDrawBox(sw - 330, sh - 80, 320, 55, col_bg)
            renderDrawBox(sw - 330, sh - 80, 4, 55, col_accent)
            renderFontDrawText(toast_font, "TRPcomm Manager", sw - 318, sh - 75, col_accent)
            renderFontDrawText(toast_font, toast_text, sw - 318, sh - 58, col_white)
        end

        if notifications_enabled.v and event_card_timer > 0 then
            event_card_timer = event_card_timer - 1
            local sw, sh = getScreenResolution()

            local cardW, cardH = 280, 88
            local SLIDE_IN, SLIDE_OUT, TOTAL = 15, 15, 210

            -- p: 0 = карточка на месте, 1 = полностью за экраном справа (только этим двигаем, без fade)
            local p = 0.0
            local elapsed = TOTAL - event_card_timer
            if elapsed <= SLIDE_IN then
                local t = elapsed / SLIDE_IN
                p = 1.0 - (1.0 - (1.0 - t) ^ 3)
            elseif event_card_timer <= SLIDE_OUT then
                local t = (SLIDE_OUT - event_card_timer) / SLIDE_OUT
                p = t ^ 3
            end

            local x0 = (sw - cardW - 20) + p * (cardW + 40)
            local y0 = sh - cardH - 20

            local col_bg     = 0xD8 * 0x1000000 + 0x15151B
            local col_accent = 0xFF * 0x1000000 + 0x5B85C4
            local col_white  = 0xFF * 0x1000000 + 0xFFFFFF
            local col_dim    = 0xFF * 0x1000000 + 0x9A9AA5

            renderDrawBox(x0, y0, cardW, cardH, col_bg)
            renderDrawBox(x0, y0 + cardH - 2, cardW, 2, col_accent)

            if event_card_logo_texture then
                renderDrawTexture(event_card_logo_texture, x0 + 14, y0 + (cardH - 44) / 2, 44, 44, 0.0, col_white)
            end

            local textX = x0 + 14 + 44 + 14
            local nameFitted = truncateToWidth(event_card_font_name, u8:decode(upcoming_event_name), cardW - (textX - x0) - 12)
            renderFontDrawText(event_card_font_name, nameFitted, textX, y0 + 14, col_white)
            renderFontDrawText(event_card_font_time, "Начало: " .. upcoming_event_time, textX, y0 + 36, col_dim)
            renderFontDrawText(event_card_font_time, event_card_message, textX, y0 + 58, col_accent)
        end

                if tracker_active and os.time() ~= tracker_last_update then
            tracker_last_update = os.time()
            updateTrackerRadius()
        end

                if curator_active and os.time() ~= curator_last_scan then
            curator_last_scan = os.time()
            scanForCurators()
        end

        if upcoming_event_timestamp and os.time() ~= event_notify_last_check then
            event_notify_last_check = os.time()
            local secLeft = upcoming_event_timestamp - os.time()

            if not event_notify_30_sent and secLeft <= 1800 and secLeft > 1795 then
                event_notify_30_sent = true
                event_card_message = "Осталось 30 минут"
                event_card_timer = 210 -- ~3.5 сек
            elseif not event_notify_10_sent and secLeft <= 600 and secLeft > 595 then
                event_notify_10_sent = true
                event_card_message = "Осталось 10 минут"
                event_card_timer = 210
            end
        end

        -- Проверка расписания автоотправки (автостарт и автостоп)
        if ad_schedule_enabled.v then
            local inSched = isServerTimeInSchedule()
            if ad_schedule_was_in == nil then
                ad_schedule_was_in = inSched
            elseif not ad_schedule_was_in and inSched then
                ad_schedule_was_in = true
                if not ad_auto_send.v then
                    ad_auto_send.v = true
                    ad_next_send_time = os.time()
                    showToast("Реклама: автостарт по расписанию")
                end
            elseif ad_schedule_was_in and not inSched then
                ad_schedule_was_in = false
                if ad_auto_send.v then
                    ad_auto_send.v = false
                    showToast("Реклама: автостоп по расписанию")
                end
            end
        else
            ad_schedule_was_in = nil
        end

        if ad_auto_send.v and not ad_pending and os.time() >= ad_next_send_time then
            if not ad_schedule_enabled.v or isServerTimeInSchedule() then
                triggerNextAdSend()
            end
        end

        local px, py, pz = getCharCoordinates(PLAYER_PED)
        local result, object = findAllRandomObjectsInSphere(px, py, pz, 150.0, true)
        if result and doesObjectExist(object) then
            local modelId = getObjectModel(object)
            if modelId > 371 or modelId < 331 then
                if remove_armour.v then
                    if modelId == 19142 or modelId == 19515 then setObjectVisible(object, false) end
                else
                    if modelId == 19142 or modelId == 19515 then setObjectVisible(object, true) end
                end
            end
        end
        
        if delete_textdraw.v then
            for a = 0, 2304 do 
                if sampTextdrawIsExists(a) then 
                    if sampTextdrawGetString(a) == 'gta-trinity.com' then sampTextdrawSetString(a, '') end
                end
            end
            delete_textdraw_was_active = true
        elseif delete_textdraw_was_active then
            for a = 0, 2304 do 
                if sampTextdrawIsExists(a) then 
                    if sampTextdrawGetString(a) == '' then sampTextdrawSetString(a, 'gta-trinity.com') end
                end
            end
            delete_textdraw_was_active = false
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
                        sampAddChatMessage("{FF6B6B}[TRPcomm] Сначала укажи частоту рации в настройках.", -1)

                    end
                end
            end
        end
    end
end
