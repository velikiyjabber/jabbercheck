--[[
    DevTool v8.0 — Reverse Engineering Toolkit
    Часть 1/2 — Services, Highlight, GUI, Tree, Spy
]]

--=============================================================
-- SERVICES
--=============================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LogService = game:GetService("LogService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local TextService = game:GetService("TextService")

local LP = Players.LocalPlayer

--=============================================================
-- EXPLOIT FUNCTIONS (Delta-safe)
--=============================================================

local hookmetamethod = hookmetamethod or function(obj, name, func)
    local mt = getrawmetatable(obj)
    local old = mt[name]
    setreadonly(mt, false)
    mt[name] = func
    setreadonly(mt, true)
    return old
end

local getnamecallmethod = getnamecallmethod or function() return "?" end
local checkcaller = checkcaller or function() return false end
local cloneref = cloneref or function(o) return o end
local newcclosure = newcclosure or function(f) return f end
local setclipboard = setclipboard or toclipboard or function(t) warn("clipboard unsupported") end
local getgc = getgc or function() return {} end
local getupvalues = getupvalues or debug.getupvalues or function() return {} end
local isexploitclosure = isexploitclosure or function() return false end
local decompile = decompile or function(obj) return "-- decompile unsupported" end
local writefile = writefile or function(path, data) warn("writefile unsupported: " .. path) end
local makefolder = makefolder or function(path) warn("makefolder unsupported: " .. path) end

--=============================================================
-- PARENT
--=============================================================

local function getParentGui()
    local ok, hui = pcall(function() return gethui() end)
    if ok and hui then return hui end
    local ok2, cg = pcall(function() return CoreGui end)
    if ok2 and cg then
        local ok3 = pcall(function()
            local t = Instance.new("Frame")
            t.Parent = cg
            t:Destroy()
        end)
        if ok3 then return cg end
    end
    return LP:WaitForChild("PlayerGui", 5) or game:GetService("StarterGui")
end

local PARENT = getParentGui()

--=============================================================
-- CONFIG
--=============================================================

local CFG = {
    TITLE = "DevTool",
    SIZE = Vector2.new(560, 400),
    MIN_SIZE = Vector2.new(400, 280),
    MAX_SIZE = Vector2.new(1600, 1000),
    HIDDEN_SIZE = Vector2.new(80, 22),
    KEYBIND = Enum.KeyCode.RightControl,
    MAX_LOGS = 300,
    MAX_CHILDREN = 100,
    MAX_DEPTH = 6,
    MAX_REMOTES = 500,
    MAX_ATTRS = 500,
    MAX_MODULES = 500,
    MAX_SCAN_RESULTS = 200,
    MAX_STRING = 10000,
    MAX_TABLE = 1000,
    AUTO_HOOK_DELAY = 1,
    SPY_THROTTLE = 0.15,
    DUMP_FOLDER = "DevTool/Dumps",

    COLORS = {
        Bg = Color3.fromRGB(14, 14, 18),
        Panel = Color3.fromRGB(20, 20, 26),
        PanelLight = Color3.fromRGB(28, 28, 36),
        PanelDark = Color3.fromRGB(10, 10, 14),
        Border = Color3.fromRGB(36, 36, 48),
        Text = Color3.fromRGB(225, 225, 235),
        TextDim = Color3.fromRGB(120, 120, 140),
        TextFaint = Color3.fromRGB(75, 75, 95),
        Accent = Color3.fromRGB(120, 180, 255),
        AccentDim = Color3.fromRGB(55, 85, 125),
        Success = Color3.fromRGB(90, 210, 130),
        Danger = Color3.fromRGB(240, 90, 100),
        Warning = Color3.fromRGB(240, 180, 80),
        Hover = Color3.fromRGB(34, 34, 46),
        Selected = Color3.fromRGB(44, 54, 74),
        RemoteEvent = Color3.fromRGB(255, 242, 0),
        RemoteFunction = Color3.fromRGB(99, 86, 245),
        BindableEvent = Color3.fromRGB(120, 220, 220),
        LocalScript = Color3.fromRGB(90, 210, 130),
        ModuleScript = Color3.fromRGB(120, 180, 255),
        Script = Color3.fromRGB(240, 180, 80),
    },

    FONT_MONO = Enum.Font.Code,
    FONT_BOLD = Enum.Font.GothamBold,
    FONT_MED = Enum.Font.GothamMedium,
}

--=============================================================
-- HELPERS
--=============================================================

local function create(c, p)
    local i = Instance.new(c)
    for k, v in pairs(p or {}) do pcall(function() i[k] = v end) end
    return i
end

local function tw(i, d, g, s, dir)
    pcall(function()
        TweenService:Create(i, TweenInfo.new(d or 0.15, s or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), g):Play()
    end)
end

local function corner(i, r) return create("UICorner", {CornerRadius = UDim.new(0, r or 6), Parent = i}) end
local function stroke(i, c, t) return create("UIStroke", {Color = c or CFG.COLORS.Border, Thickness = t or 1, Parent = i}) end
local function pad(i, t, r, b, l) return create("UIPadding", {PaddingTop = UDim.new(0, t or 0), PaddingRight = UDim.new(0, r or 0), PaddingBottom = UDim.new(0, b or 0), PaddingLeft = UDim.new(0, l or 0), Parent = i}) end

local function getPath(inst)
    if not inst then return "nil" end
    local parts = {}
    local cur = inst
    while cur and cur ~= game do
        table.insert(parts, 1, cur.Name)
        cur = cur.Parent
    end
    return "game." .. table.concat(parts, ".")
end

local function getServicePath(inst)
    if not inst then return "nil" end
    local parts = {}
    local cur = inst
    while cur and cur ~= game do
        if cur.Parent == game then
            table.insert(parts, 1, string.format('game:GetService("%s")', cur.ClassName))
        else
            table.insert(parts, 1, string.format('[%q]', cur.Name))
        end
        cur = cur.Parent
    end
    return table.concat(parts)
end

local function copyToClipboard(text)
    pcall(function() setclipboard(text) end)
end

--=============================================================
-- HIGHLIGHT LIBRARY (exxtremewa, встроено)
--=============================================================

local H = {
    parentFrame = nil, scrollingFrame = nil, textFrame = nil, lineNumbersFrame = nil,
    lines = {}, tableContents = {}, line = 0, largestX = 0,
    lineSpace = 14, font = Enum.Font.Code, textSize = 12,
    backgroundColor = Color3.fromRGB(40, 44, 52),
    operatorColor = Color3.fromRGB(187, 85, 255),
    functionColor = Color3.fromRGB(97, 175, 239),
    stringColor = Color3.fromRGB(152, 195, 121),
    numberColor = Color3.fromRGB(209, 154, 102),
    booleanColor = Color3.fromRGB(209, 154, 102),
    objectColor = Color3.fromRGB(229, 192, 123),
    defaultColor = Color3.fromRGB(224, 108, 117),
    commentColor = Color3.fromRGB(148, 148, 148),
    lineNumberColor = Color3.fromRGB(148, 148, 148),
    genericColor = Color3.fromRGB(240, 240, 240),
    offLimits = {},
}

local hl_operators = {"^(function)[^%w_]", "^(local)[^%w_]", "^(if)[^%w_]", "^(for)[^%w_]", "^(while)[^%w_]", "^(then)[^%w_]", "^(do)[^%w_]", "^(else)[^%w_]", "^(elseif)[^%w_]", "^(return)[^%w_]", "^(end)[^%w_]", "^(continue)[^%w_]", "^(and)[^%w_]", "^(not)[^%w_]", "^(or)[^%w_]", "[^%w_](or)[^%w_]", "[^%w_](and)[^%w_]", "[^%w_](not)[^%w_]", "[^%w_](continue)[^%w_]", "[^%w_](function)[^%w_]", "[^%w_](local)[^%w_]", "[^%w_](if)[^%w_]", "[^%w_](for)[^%w_]", "[^%w_](while)[^%w_]", "[^%w_](then)[^%w_]", "[^%w_](do)[^%w_]", "[^%w_](else)[^%w_]", "[^%w_](elseif)[^%w_]", "[^%w_](return)[^%w_]", "[^%w_](end)[^%w_]"}
local hl_strings = {{"\"", "\""}, {"'", "'"}, {"%[%[", "%]%]", true}}
local hl_comments = {"%-%-%[%[[^%]%]]+%]?%]?", "(%-%-[^\n]+)"}
local hl_functions = {"[^%w_]([%a_][%a%d_]*)%s*%(", "^([%a_][%a%d_]*)%s*%(", "[:%.%(%[%p]([%a_][%a%d_]*)%s*%("}
local hl_numbers = {"[^%w_](%d+[eE]?%d*)", "[^%w_](%.%d+[eE]?%d*)", "[^%w_](%d+%.%d+[eE]?%d*)", "^(%d+[eE]?%d*)", "^(%.%d+[eE]?%d*)", "^(%d+%.%d+[eE]?%d*)"}
local hl_booleans = {"[^%w_](true)", "^(true)", "[^%w_](false)", "^(false)", "[^%w_](nil)", "^(nil)"}
local hl_objects = {"[^%w_:]([%a_][%a%d_]*):", "^([%a_][%a%d_]*):"}
local hl_other = {"[^_%s%w=>~<%-%+%*]", ">", "~", "<", "%-", "%+", "=", "%*"}

local function hlgfind(str, pattern)
    return coroutine.wrap(function()
        local start = 0
        while true do
            local fs, fe = str:find(pattern, start)
            if fs and fe ~= #str then
                start = fe + 1
                coroutine.yield(fs, fe)
            else
                return
            end
        end
    end)
end

local function hl_isOffLimits(idx)
    for _, v in next, H.offLimits do
        if idx >= v[1] and idx <= v[2] then return true end
    end
    return false
end

local function hl_autoEscape(s)
    return s:gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;"):gsub("&", "&amp;")
end

local function hl_renderComments()
    local str = H:getRaw()
    for _, pattern in next, hl_comments do
        for cs, ce in hlgfind(str, pattern) do
            if not hl_isOffLimits(cs) then
                for i = cs, ce do
                    table.insert(H.offLimits, {cs, ce})
                    if H.tableContents[i] then H.tableContents[i].Color = H.commentColor end
                end
            end
        end
    end
end

local function hl_renderStrings()
    local st, set, ib, ss, oi, skip
    for i, char in next, H.tableContents do
        if st then
            char.Color = H.stringColor
            local ps = ""
            for k = ss, i do ps = ps .. H.tableContents[k].Char end
            if char.Char:match(set) and not not ib or (ps:match("(\\*)" .. set .. "$") and #ps:match("(\\*)" .. set .. "$") % 2 == 0) then
                skip = true; st = nil; set = nil; ib = nil
                H.offLimits[oi][2] = i
            end
        end
        if not skip then
            for _, v in next, hl_strings do
                if char.Char:match(v[1]) and not hl_isOffLimits(i) then
                    st = v[1]; set = v[2]; ib = v[3]
                    char.Color = H.stringColor; ss = i
                    oi = #H.offLimits + 1
                    H.offLimits[oi] = {ss, math.huge}
                end
            end
        end
        skip = false
    end
end

local function hl_highlightPattern(patterns, color)
    local str = H:getRaw()
    for _, p in next, patterns do
        for fs, fe in hlgfind(str, p) do
            if not hl_isOffLimits(fs) and not hl_isOffLimits(fe) then
                for i = fs, fe do
                    if H.tableContents[i] then H.tableContents[i].Color = color end
                end
            end
        end
    end
end

local function hl_updateCanvas()
    if H.scrollingFrame then
        H.scrollingFrame.CanvasSize = UDim2.new(0, H.largestX, 0, H.line * H.lineSpace)
    end
end

local function hl_render()
    H.offLimits = {}
    H.lines = {}
    if not H.textFrame then return end
    H.textFrame:ClearAllChildren()
    H.lineNumbersFrame:ClearAllChildren()

    hl_highlightPattern(hl_functions, H.functionColor)
    hl_highlightPattern(hl_numbers, H.numberColor)
    hl_highlightPattern(hl_operators, H.operatorColor)
    hl_highlightPattern(hl_objects, H.objectColor)
    hl_highlightPattern(hl_booleans, H.booleanColor)
    hl_highlightPattern(hl_other, H.genericColor)
    hl_renderComments()
    hl_renderStrings()

    local lastColor, lineStr, rawStr = nil, "", ""
    H.largestX = 0
    H.line = 1

    for i = 1, #H.tableContents + 1 do
        local char = H.tableContents[i]
        if i == #H.tableContents + 1 or (char and char.Char == "\n") then
            lineStr = lineStr .. (lastColor and "</font>" or "")
            local lineText = create("TextLabel")
            local x = TextService:GetTextSize(rawStr, H.textSize, H.font, Vector2.new(math.huge, math.huge)).X + 50
            if x > H.largestX then H.largestX = x end
            lineText.TextXAlignment = Enum.TextXAlignment.Left
            lineText.TextYAlignment = Enum.TextYAlignment.Top
            lineText.Position = UDim2.new(0, 0, 0, H.line * H.lineSpace - H.lineSpace / 2)
            lineText.Size = UDim2.new(0, x, 0, H.textSize)
            lineText.RichText = true
            lineText.Font = H.font
            lineText.TextSize = H.textSize
            lineText.BackgroundTransparency = 1
            lineText.TextColor3 = H.genericColor
            lineText.Text = lineStr
            lineText.Parent = H.textFrame

            if i ~= #H.tableContents + 1 then
                local ln = create("TextLabel")
                ln.Text = H.line
                ln.Font = H.font
                ln.TextSize = H.textSize
                ln.Size = UDim2.new(1, 0, 0, H.lineSpace)
                ln.TextXAlignment = Enum.TextXAlignment.Right
                ln.TextColor3 = H.lineNumberColor
                ln.Position = UDim2.new(0, 0, 0, H.line * H.lineSpace - H.lineSpace / 2)
                ln.BackgroundTransparency = 1
                ln.Parent = H.lineNumbersFrame
            end

            lineStr = ""; rawStr = ""; lastColor = nil
            H.line = H.line + 1
            hl_updateCanvas()
        elseif char.Char == " " then
            lineStr = lineStr .. " "
            rawStr = rawStr .. " "
        elseif char.Char == "\t" then
            lineStr = lineStr .. string.rep(" ", 4)
            rawStr = rawStr .. "\t"
        else
            if char.Color == lastColor then
                lineStr = lineStr .. hl_autoEscape(char.Char)
            else
                lineStr = lineStr .. string.format('%s<font color="rgb(%d,%d,%d)">', lastColor and "</font>" or "", char.Color.R * 255, char.Color.G * 255, char.Color.B * 255)
                lineStr = lineStr .. hl_autoEscape(char.Char)
                lastColor = char.Color
            end
            rawStr = rawStr .. char.Char
        end
    end
    hl_updateCanvas()
end

function H:init(frame)
    frame:ClearAllChildren()
    H.parentFrame = frame
    H.scrollingFrame = create("ScrollingFrame", {Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = H.backgroundColor, BorderSizePixel = 0, ScrollBarThickness = 4})
    H.textFrame = create("Frame", {Size = UDim2.new(1, -40, 1, 0), Position = UDim2.new(0, 40, 0, 0), BackgroundTransparency = 1})
    H.lineNumbersFrame = create("Frame", {Size = UDim2.new(0, 25, 1, 0), BackgroundTransparency = 1})
    H.textFrame.Parent = H.scrollingFrame
    H.lineNumbersFrame.Parent = H.scrollingFrame
    H.scrollingFrame.Parent = frame
    hl_render()
    frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        if H.scrollingFrame then
            H.scrollingFrame.Size = UDim2.new(0, frame.AbsoluteSize.X, 0, frame.AbsoluteSize.Y)
        end
    end)
end

function H:setRaw(raw)
    raw = raw .. "\n"
    H.tableContents = {}
    for i = 1, #raw do
        table.insert(H.tableContents, {Char = raw:sub(i, i), Color = H.defaultColor})
    end
    hl_render()
end

function H:getString()
    local r = ""
    for _, c in next, H.tableContents do r = r .. c.Char:sub(1, 1) end
    return r
end

function H:getRaw()
    local r = ""
    for _, c in next, H.tableContents do r = r .. c.Char end
    return r
end

local Highlight = {}
function Highlight.new(frame)
    local box = setmetatable({}, {__index = H})
    box:init(frame)
    return box
end

--=============================================================
-- V2S (value to string — генерация Lua-кода)
--=============================================================

local function formatString(s, indent)
    indent = indent or 0
    local escaped = s:gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\t", "\\t"):gsub('"', '\\"')
    if #escaped > CFG.MAX_STRING then
        escaped = escaped:sub(1, CFG.MAX_STRING) .. "..."
    end
    return '"' .. escaped .. '"'
end

local v2s
v2s = function(v, depth, seen)
    depth = depth or 0
    seen = seen or {}
    if depth > 6 then return "..." end

    local t = typeof(v)
    if t == "string" then return formatString(v)
    elseif t == "number" then
        if v ~= v then return "0/0" end
        if v == math.huge then return "math.huge" end
        if v == -math.huge then return "-math.huge" end
        return tostring(v)
    elseif t == "boolean" then return tostring(v)
    elseif t == "Vector3" then return string.format("Vector3.new(%.3f, %.3f, %.3f)", v.X, v.Y, v.Z)
    elseif t == "Vector2" then return string.format("Vector2.new(%.3f, %.3f)", v.X, v.Y)
    elseif t == "CFrame" then
        local c = {v:GetComponents()}
        local parts = {}
        for i = 1, #c do table.insert(parts, string.format("%.4f", c[i])) end
        return "CFrame.new(" .. table.concat(parts, ", ") .. ")"
    elseif t == "Color3" then
        return string.format("Color3.new(%.4f, %.4f, %.4f)", v.R, v.G, v.B)
    elseif t == "BrickColor" then return string.format("BrickColor.new(%d)", v.Number)
    elseif t == "UDim" then return string.format("UDim.new(%.3f, %d)", v.Scale, v.Offset)
    elseif t == "UDim2" then return string.format("UDim2.new(%.3f, %d, %.3f, %d)", v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset)
    elseif t == "Rect" then return string.format("Rect.new(%d, %d, %d, %d)", v.Min.X, v.Min.Y, v.Max.X, v.Max.Y)
    elseif t == "Ray" then return string.format("Ray.new(%s, %s)", v2s(v.Origin, depth + 1, seen), v2s(v.Direction, depth + 1, seen))
    elseif t == "NumberRange" then return string.format("NumberRange.new(%s, %s)", v.Min, v.Max)
    elseif t == "TweenInfo" then
        return string.format("TweenInfo.new(%.3f, Enum.EasingStyle.%s, Enum.EasingDirection.%s, %d, %s, %.3f)",
            v.Time, tostring(v.EasingStyle), tostring(v.EasingDirection), v.RepeatCount, tostring(v.Reverses), v.DelayTime)
    elseif t == "EnumItem" then return "Enum." .. tostring(v.EnumType) .. "." .. v.Name
    elseif t == "Enum" then return "Enum." .. tostring(v)
    elseif t == "Instance" then
        if v == game then return "game" end
        if v == workspace then return "workspace" end
        if v == LP then return 'game:GetService("Players").LocalPlayer' end
        return getServicePath(v) or getPath(v)
    elseif t == "function" then
        local name = "?"
        pcall(function() name = debug.info(v, "n") or "?" end)
        if name ~= "?" and name ~= "" then return "--[[" .. name .. "]] function() end" end
        return "function() end --[[anonymous]]"
    elseif t == "table" then
        if seen[v] then return "--[[cycle]] nil" end
        seen[v] = true
        local parts, count = {}, 0
        for k, val in pairs(v) do
            count = count + 1
            if count > CFG.MAX_TABLE then
                table.insert(parts, "... --[[truncated]]")
                break
            end
            table.insert(parts, "[" .. v2s(k, depth + 1, seen) .. "] = " .. v2s(val, depth + 1, seen))
        end
        seen[v] = nil
        return "{" .. table.concat(parts, ", ") .. "}"
    else
        return "nil --[[" .. t .. ": " .. tostring(v) .. "]]"
    end
end

--=============================================================
-- SCREEN GUI
--=============================================================

local SG = create("ScreenGui", {
    Name = "DevTool_" .. tostring(math.random(1000, 9999)),
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
SG.Parent = PARENT

--=============================================================
-- STATE
--=============================================================

local State = {
    Open = true,
    Hidden = false,
    CurrentTab = 1,
    Tabs = {},
    Dragging = false,
    Resizing = false,
    DragStart = nil,
    StartPos = nil,
    StartSize = nil,
    SavedSize = Vector2.new(CFG.SIZE.X, CFG.SIZE.Y),
    Cache = {},
}

--=============================================================
-- WINDOW
--=============================================================

local Window = create("Frame", {
    Name = "Window",
    Size = UDim2.new(0, CFG.SIZE.X, 0, CFG.SIZE.Y),
    Position = UDim2.new(0.5, 0, 0.5, 0),
    AnchorPoint = Vector2.new(0.5, 0.5),
    BackgroundColor3 = CFG.COLORS.Bg,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    ZIndex = 10,
    Parent = SG,
})
corner(Window, 6)
local WStroke = stroke(Window, CFG.COLORS.Border, 1)

local TB = create("Frame", {Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = CFG.COLORS.Panel, BorderSizePixel = 0, ZIndex = 11, Parent = Window})
create("Frame", {Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = CFG.COLORS.Accent, BorderSizePixel = 0, ZIndex = 13, Parent = TB})
create("TextLabel", {Size = UDim2.new(1, -120, 1, 0), Position = UDim2.new(0, 8, 0, 0), BackgroundTransparency = 1, Text = CFG.TITLE, TextColor3 = CFG.COLORS.Text, TextSize = 10, Font = CFG.FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12, Parent = TB})

local function mkBtn(t, x, h)
    local b = create("TextButton", {
        Size = UDim2.new(0, 16, 0, 16),
        Position = UDim2.new(1, x, 0, 3),
        BackgroundColor3 = CFG.COLORS.PanelLight,
        BackgroundTransparency = 0.4,
        Text = t,
        TextColor3 = CFG.COLORS.TextDim,
        TextSize = 10,
        Font = CFG.FONT_BOLD,
        AutoButtonColor = false,
        ZIndex = 12,
        Parent = TB,
    })
    corner(b, 3)
    b.MouseEnter:Connect(function()
        tw(b, 0.1, {BackgroundTransparency = 0, BackgroundColor3 = h or CFG.COLORS.Hover, TextColor3 = CFG.COLORS.Text})
    end)
    b.MouseLeave:Connect(function()
        tw(b, 0.1, {BackgroundTransparency = 0.4, BackgroundColor3 = CFG.COLORS.PanelLight, TextColor3 = CFG.COLORS.TextDim})
    end)
    return b
end

local CloseBtn = mkBtn("✕", -20, CFG.COLORS.Danger)
local HideBtn = mkBtn("—", -40, CFG.COLORS.Warning)
local MinBtn = mkBtn("▼", -60, CFG.COLORS.Accent)

local Content = create("Frame", {Size = UDim2.new(1, 0, 1, -22), Position = UDim2.new(0, 0, 0, 22), BackgroundColor3 = CFG.COLORS.Bg, BorderSizePixel = 0, ZIndex = 10, Parent = Window})

local Sidebar = create("Frame", {Size = UDim2.new(0, 90, 1, 0), BackgroundColor3 = CFG.COLORS.Panel, BorderSizePixel = 0, ZIndex = 10, Parent = Content})
create("UIListLayout", {Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, FillDirection = Enum.FillDirection.Vertical, Parent = Sidebar})
pad(Sidebar, 4, 4, 4, 4)

local PageArea = create("Frame", {Size = UDim2.new(1, -90, 1, 0), Position = UDim2.new(0, 90, 0, 0), BackgroundColor3 = CFG.COLORS.Bg, BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 10, Parent = Content})

local RH = create("Frame", {Size = UDim2.new(0, 8, 0, 8), Position = UDim2.new(1, -8, 1, -8), BackgroundColor3 = CFG.COLORS.Accent, BackgroundTransparency = 0.6, BorderSizePixel = 0, ZIndex = 20, Parent = Window})
corner(RH, 2)

--=============================================================
-- TAB SYSTEM
--=============================================================

local function createTab(name, icon)
    local btn = create("TextButton", {Size = UDim2.new(1, 0, 0, 20), BackgroundColor3 = CFG.COLORS.Panel, BackgroundTransparency = 1, BorderSizePixel = 0, Text = "", AutoButtonColor = false, ZIndex = 11, Parent = Sidebar})
    corner(btn, 3)
    create("TextLabel", {Size = UDim2.new(0, 14, 1, 0), Position = UDim2.new(0, 4, 0, 0), BackgroundTransparency = 1, Text = icon or "", TextColor3 = CFG.COLORS.TextDim, TextSize = 10, Font = CFG.FONT_BOLD, ZIndex = 12, Parent = btn})
    local lbl = create("TextLabel", {Size = UDim2.new(1, -20, 1, 0), Position = UDim2.new(0, 20, 0, 0), BackgroundTransparency = 1, Text = name, TextColor3 = CFG.COLORS.TextDim, TextSize = 9, Font = CFG.FONT_MED, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 12, Parent = btn})
    local page = create("Frame", {Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false, ZIndex = 11, Parent = PageArea})
    local data = {Name = name, Button = btn, Label = lbl, Page = page}

    btn.MouseEnter:Connect(function()
        tw(btn, 0.1, {BackgroundTransparency = 0.7, BackgroundColor3 = CFG.COLORS.Hover})
        tw(lbl, 0.1, {TextColor3 = CFG.COLORS.Text})
    end)
    btn.MouseLeave:Connect(function()
        if State.CurrentTab ~= table.find(State.Tabs, data) then
            tw(btn, 0.1, {BackgroundTransparency = 1, BackgroundColor3 = CFG.COLORS.Panel})
            tw(lbl, 0.1, {TextColor3 = CFG.COLORS.TextDim})
        end
    end)
    btn.MouseButton1Click:Connect(function()
        local idx = table.find(State.Tabs, data)
        if idx and idx ~= State.CurrentTab then
            State.CurrentTab = idx
            for i, t in ipairs(State.Tabs) do
                t.Page.Visible = (i == idx)
                if i == idx then
                    tw(t.Button, 0.1, {BackgroundTransparency = 0.5, BackgroundColor3 = CFG.COLORS.Selected})
                    tw(t.Label, 0.1, {TextColor3 = CFG.COLORS.Accent})
                else
                    tw(t.Button, 0.1, {BackgroundTransparency = 1, BackgroundColor3 = CFG.COLORS.Panel})
                    tw(t.Label, 0.1, {TextColor3 = CFG.COLORS.TextDim})
                end
            end
        end
    end)
    table.insert(State.Tabs, data)
    return data
end

--=============================================================
-- UI HELPERS
--=============================================================

local UI = {}

function UI.iconBtn(parent, label, color, cb, width)
    local b = create("TextButton", {
        Size = UDim2.new(0, width or 22, 0, 18),
        BackgroundColor3 = color or CFG.COLORS.PanelLight,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        Text = label,
        TextColor3 = CFG.COLORS.Text,
        TextSize = 10,
        Font = CFG.FONT_BOLD,
        AutoButtonColor = false,
        ZIndex = 12,
        Parent = parent,
    })
    corner(b, 3)
    b.MouseEnter:Connect(function() tw(b, 0.1, {BackgroundTransparency = 0, BackgroundColor3 = CFG.COLORS.Hover}) end)
    b.MouseLeave:Connect(function() tw(b, 0.1, {BackgroundTransparency = 0.5, BackgroundColor3 = color or CFG.COLORS.PanelLight}) end)
    b.MouseButton1Click:Connect(function() if cb then pcall(cb) end end)
    return b
end

function UI.textBtn(parent, label, color, cb, width)
    local b = create("TextButton", {
        Size = UDim2.new(0, width or 90, 0, 18),
        BackgroundColor3 = color or CFG.COLORS.PanelLight,
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        Text = label,
        TextColor3 = CFG.COLORS.Text,
        TextSize = 9,
        Font = CFG.FONT_MED,
        AutoButtonColor = false,
        ZIndex = 12,
        Parent = parent,
    })
    corner(b, 3)
    b.MouseEnter:Connect(function() tw(b, 0.1, {BackgroundTransparency = 0, BackgroundColor3 = CFG.COLORS.Hover}) end)
    b.MouseLeave:Connect(function() tw(b, 0.1, {BackgroundTransparency = 0.5, BackgroundColor3 = color or CFG.COLORS.PanelLight}) end)
    b.MouseButton1Click:Connect(function() if cb then pcall(cb) end end)
    return b
end

function UI.scroll(parent, pos, size)
    local s = create("ScrollingFrame", {
        Size = size,
        Position = pos,
        BackgroundColor3 = CFG.COLORS.PanelDark,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = CFG.COLORS.AccentDim,
        ScrollBarImageTransparency = 0.4,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ZIndex = 11,
        Parent = parent,
    })
    corner(s, 3); stroke(s, CFG.COLORS.Border, 1)
    pad(s, 4, 4, 4, 4)
    local layout = create("UIListLayout", {
        Padding = UDim.new(0, 1),
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        Parent = s,
    })
    return s, layout
end

--=============================================================
-- MODAL (с подсветкой Highlight)
--=============================================================

local function showModal(title, content, buttons)
    local ov = create("Frame", {Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 190, Parent = SG})
    local box = create("Frame", {Size = UDim2.new(0, 560, 0, 420), Position = UDim2.new(0.5, -280, 0.5, -210), BackgroundColor3 = CFG.COLORS.Panel, BorderSizePixel = 0, ZIndex = 200, Parent = SG})
    corner(box, 6); stroke(box, CFG.COLORS.Accent, 1)

    create("TextLabel", {Size = UDim2.new(1, -40, 0, 20), Position = UDim2.new(0, 10, 0, 6), BackgroundTransparency = 1, Text = title, TextColor3 = CFG.COLORS.Text, TextSize = 10, Font = CFG.FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 201, Parent = box})
    local closeB = create("TextButton", {Size = UDim2.new(0, 16, 0, 16), Position = UDim2.new(1, -22, 0, 6), BackgroundColor3 = CFG.COLORS.PanelLight, BackgroundTransparency = 0.4, Text = "✕", TextColor3 = CFG.COLORS.TextDim, TextSize = 10, Font = CFG.FONT_BOLD, AutoButtonColor = false, ZIndex = 201, Parent = box})
    corner(closeB, 3)
    closeB.MouseButton1Click:Connect(function() ov:Destroy(); box:Destroy() end)

    -- Кнопки
    local btnRow = create("Frame", {Size = UDim2.new(1, -20, 0, 20), Position = UDim2.new(0, 10, 0, 30), BackgroundTransparency = 1, ZIndex = 201, Parent = box})
    create("UIListLayout", {Padding = UDim.new(0, 4), FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, Parent = btnRow})

    if buttons then
        for _, b in ipairs(buttons) do
            UI.textBtn(btnRow, b.label, b.color, b.cb, b.width or 85)
        end
    end

    -- Codebox с подсветкой
    local codeWrap = create("Frame", {
        Size = UDim2.new(1, -20, 1, -90),
        Position = UDim2.new(0, 10, 0, 56),
        BackgroundColor3 = Color3.fromRGB(40, 44, 52),
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 201,
        Parent = box,
    })
    corner(codeWrap, 3); stroke(codeWrap, CFG.COLORS.Border, 1)

    local codebox
    pcall(function()
        codebox = Highlight.new(codeWrap)
        codebox:setRaw(content)
    end)

    return ov, box, codebox
end

--=============================================================
-- REMOTE SPY V3
--=============================================================

local RemoteSpy = {
    Logs = {},
    Enabled = false,
    Count = 0,
    PendingRender = false,
    UI = nil,
    Filter = "",
    BlockList = {},
    BlackList = {},
    Watched = {},
    History = {},
    AutoBlock = false,
    FuncEnabled = true,
    LogCheckCaller = false,
    Selected = nil,
    Scheduled = {},
    OriginalNamecall = nil,
    Hooked = false,
}

local function schedule(f, ...)
    table.insert(RemoteSpy.Scheduled, {f, ...})
end

local function processScheduled()
    if #RemoteSpy.Scheduled > 0 then
        local cur = RemoteSpy.Scheduled[1]
        table.remove(RemoteSpy.Scheduled, 1)
        if type(cur[1]) == "function" then
            pcall(cur[1], unpack(cur[2] or {}))
        end
    end
end

local function isBlocked(remote)
    local id = tostring(remote)
    return RemoteSpy.BlockList[id] == true or RemoteSpy.BlockList[remote.Name] == true
end

local function isBlacklisted(remote)
    local id = tostring(remote)
    return RemoteSpy.BlackList[id] == true or RemoteSpy.BlackList[remote.Name] == true
end

local function addRemoteLog(remote, method, args, isFunc, callingscript, funcinfo)
    if not RemoteSpy.Enabled then return end
    if isBlacklisted(remote) then return end

    RemoteSpy.Count = RemoteSpy.Count + 1
    local safePath = getServicePath(remote)
    local argsStr = ""
    pcall(function()
        local parts = {}
        for i = 1, #args do
            table.insert(parts, v2s(args[i], 0, {}))
        end
        argsStr = table.concat(parts, ", ")
    end)

    local entry = {
        Id = RemoteSpy.Count,
        Time = os.date("%H:%M:%S"),
        Name = remote.Name,
        Class = remote.ClassName,
        Path = getPath(remote),
        SafePath = safePath,
        ArgsStr = argsStr,
        Args = args,
        Remote = remote,
        Method = method,
        IsFunc = isFunc,
        Callingscript = callingscript,
        Funcinfo = funcinfo,
        Blocked = isBlocked(remote),
    }

    if isFunc then
        entry.Code = string.format("local result = %s:InvokeServer(%s)", safePath, argsStr)
    else
        entry.Code = string.format("%s:FireServer(%s)", safePath, argsStr)
    end

    local fullCode = "-- " .. remote.Name .. " (" .. remote.ClassName .. ")\n"
    fullCode = fullCode .. "-- Path: " .. entry.Path .. "\n"
    fullCode = fullCode .. "-- Time: " .. entry.Time .. "\n\n"
    if #args > 0 then
        fullCode = fullCode .. "local args = {\n"
        for i = 1, #args do
            pcall(function()
                fullCode = fullCode .. "    " .. v2s(args[i], 0, {}) .. ",\n"
            end)
        end
        fullCode = fullCode .. "}\n\n"
        if isFunc then
            fullCode = fullCode .. safePath .. ":InvokeServer(unpack(args))"
        else
            fullCode = fullCode .. safePath .. ":FireServer(unpack(args))"
        end
    else
        if isFunc then
            fullCode = fullCode .. safePath .. ":InvokeServer()"
        else
            fullCode = fullCode .. safePath .. ":FireServer()"
        end
    end

    if entry.Blocked then
        fullCode = "-- !!! THIS REMOTE WAS BLOCKED BY DEVTOOL !!!\n\n" .. fullCode
    end

    entry.FullCode = fullCode

    table.insert(RemoteSpy.Logs, entry)
    if #RemoteSpy.Logs > CFG.MAX_LOGS then table.remove(RemoteSpy.Logs, 1) end

    if RemoteSpy.UI and not RemoteSpy.PendingRender then
        RemoteSpy.PendingRender = true
        task.delay(CFG.SPY_THROTTLE, function()
            RemoteSpy.PendingRender = false
            if RemoteSpy.UI then pcall(RemoteSpy.UI) end
        end)
    end
end

local function installHooks()
    if RemoteSpy.Hooked then return end

    local ok = pcall(function()
        local mt = getrawmetatable(game)
        if not mt then error("no metatable") end

        local original = mt.__namecall
        RemoteSpy.OriginalNamecall = original

        setreadonly(mt, false)
        mt.__namecall = newcclosure(function(self, ...)
            local method = getnamecallmethod()

            if method == "FireServer" or method == "InvokeServer" then
                if typeof(self) == "Instance" and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then
                    if not RemoteSpy.LogCheckCaller and checkcaller() then
                        return original(self, ...)
                    end

                    local remote = self
                    local args = table.pack(...)
                    local isFunc = (method == "InvokeServer")

                    local callsrc, funcinfo
                    if RemoteSpy.FuncEnabled then
                        pcall(function()
                            callsrc = getcallingscript and getcallingscript() or nil
                            funcinfo = debug.info(2, "sln")
                        end)
                    end

                    local clonedArgs = {}
                    for i = 1, #args do clonedArgs[i] = args[i] end

                    schedule(addRemoteLog, remote, method, clonedArgs, isFunc, callsrc, funcinfo)

                    if isBlocked(remote) then
                        if isFunc then return nil end
                        return
                    end
                end
            end

            return original(self, ...)
        end)
        setreadonly(mt, true)

        RemoteSpy.Hooked = true
    end)

    if not ok then
        warn("[DevTool] Failed to hook __namecall")
    end
end

local function uninstallHooks()
    if not RemoteSpy.Hooked then return end
    pcall(function()
        local mt = getrawmetatable(game)
        setreadonly(mt, false)
        mt.__namecall = RemoteSpy.OriginalNamecall
        setreadonly(mt, true)
    end)
    RemoteSpy.Hooked = false
end

--=============================================================
-- TAB: TREE
--=============================================================

local ExplorerTab = createTab("Tree", "▤")

local expTopBar = create("Frame", {Size = UDim2.new(1, -10, 0, 20), Position = UDim2.new(0, 5, 0, 5), BackgroundTransparency = 1, ZIndex = 12, Parent = ExplorerTab.Page})
local expSearchBox = create("TextBox", {
    Size = UDim2.new(1, -80, 1, 0),
    BackgroundColor3 = CFG.COLORS.PanelDark,
    BorderSizePixel = 0,
    Text = "",
    PlaceholderText = "Search name/class...",
    PlaceholderColor3 = CFG.COLORS.TextFaint,
    TextColor3 = CFG.COLORS.Text,
    TextSize = 9,
    Font = CFG.FONT_MONO,
    TextXAlignment = Enum.TextXAlignment.Left,
    ClearTextOnFocus = false,
    ZIndex = 12,
    Parent = expTopBar,
})
corner(expSearchBox, 3); stroke(expSearchBox, CFG.COLORS.Border, 1); pad(expSearchBox, 0, 5, 0, 5)

UI.iconBtn(expTopBar, "📋", CFG.COLORS.Success, function()
    local out = {}
    local function walk(inst, depth)
        if depth > 8 then return end
        table.insert(out, string.rep("  ", depth) .. inst.Name .. " [" .. inst.ClassName .. "]")
        for _, child in ipairs(inst:GetChildren()) do
            walk(child, depth + 1)
        end
    end
    for _, root in ipairs({game:GetService("Workspace"), game:GetService("Players"), ReplicatedStorage, game:GetService("Lighting")}) do
        walk(root, 0)
    end
    copyToClipboard(table.concat(out, "\n"))
end, 22).Position = UDim2.new(1, -46, 0, 0)

UI.iconBtn(expTopBar, "↻", nil, function() end, 22).Position = UDim2.new(1, -22, 0, 0)

local expTree = UI.scroll(ExplorerTab.Page, UDim2.new(0, 5, 0, 30), UDim2.new(1, -10, 1, -35))

local rowMap = {}
local orderCounter = 0

local function shiftOrdersAfter(threshold, delta)
    for _, data in pairs(rowMap) do
        if data.row and data.row.Parent and data.row.LayoutOrder > threshold then
            data.row.LayoutOrder = data.row.LayoutOrder + delta
        end
    end
end

local function makeRow(inst, depth)
    orderCounter = orderCounter + 1

    local row = create("Frame", {
        Size = UDim2.new(1, -3, 0, 18),
        BackgroundColor3 = CFG.COLORS.Panel,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = orderCounter,
        ZIndex = 12,
        Parent = expTree,
    })
    corner(row, 3)

    local iconColor = CFG.COLORS.Text
    local iconChar = "○"
    pcall(function()
        if inst:IsA("LocalScript") then iconColor = CFG.COLORS.LocalScript; iconChar = "L"
        elseif inst:IsA("ModuleScript") then iconColor = CFG.COLORS.ModuleScript; iconChar = "M"
        elseif inst:IsA("Script") then iconColor = CFG.COLORS.Script; iconChar = "S"
        elseif inst:IsA("RemoteEvent") then iconColor = CFG.COLORS.RemoteEvent; iconChar = "R"
        elseif inst:IsA("RemoteFunction") then iconColor = CFG.COLORS.RemoteFunction; iconChar = "F"
        elseif inst:IsA("BindableEvent") then iconColor = CFG.COLORS.BindableEvent; iconChar = "B"
        elseif inst:IsA("Model") then iconChar = "▢"
        elseif inst:IsA("Folder") then iconChar = "▣"
        elseif inst:IsA("Part") then iconChar = "■"
        elseif inst:IsA("GuiObject") then iconChar = "▭"
        elseif inst:IsA("Camera") then iconChar = "◉"
        elseif inst:IsA("Terrain") then iconChar = "▲"
        end
    end)

    local hasChildren = false
    pcall(function() hasChildren = #inst:GetChildren() > 0 end)

    local arrow = create("TextButton", {
        Size = UDim2.new(0, 12, 0, 18),
        Position = UDim2.new(0, 2 + depth * 12, 0, 0),
        BackgroundTransparency = 1,
        Text = hasChildren and "▶" or "",
        TextColor3 = CFG.COLORS.TextDim,
        TextSize = 7,
        Font = CFG.FONT_BOLD,
        AutoButtonColor = false,
        ZIndex = 14,
        Parent = row,
    })

    create("TextLabel", {Size = UDim2.new(0, 12, 0, 18), Position = UDim2.new(0, 14 + depth * 12, 0, 0), BackgroundTransparency = 1, Text = iconChar, TextColor3 = iconColor, TextSize = 9, Font = CFG.FONT_BOLD, ZIndex = 13, Parent = row})
    create("TextLabel", {Size = UDim2.new(0, 180, 0, 18), Position = UDim2.new(0, 26 + depth * 12, 0, 0), BackgroundTransparency = 1, Text = inst.Name, TextColor3 = CFG.COLORS.Text, TextSize = 9, Font = CFG.FONT_MONO, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 13, Parent = row})
    create("TextLabel", {Size = UDim2.new(0, 100, 0, 18), Position = UDim2.new(1, -105, 0, 0), BackgroundTransparency = 1, Text = inst.ClassName, TextColor3 = CFG.COLORS.TextFaint, TextSize = 8, Font = CFG.FONT_MONO, TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 13, Parent = row})

    rowMap[inst] = {row = row, arrow = arrow, depth = depth, expanded = false, children = {}, hasChildren = hasChildren}

    if hasChildren then
        arrow.MouseButton1Click:Connect(function()
            pcall(function()
                local data = rowMap[inst]
                if not data then return end
                if data.expanded then
                    local function collapse(inInst)
                        local d = rowMap[inInst]
                        if not d then return end
                        for _, child in ipairs(d.children) do collapse(child) end
                        for _, child in ipairs(d.children) do
                            local cd = rowMap[child]
                            if cd and cd.row then cd.row:Destroy() end
                            rowMap[child] = nil
                        end
                        d.children = {}
                        d.expanded = false
                        if d.arrow then d.arrow.Text = "▶" end
                    end
                    collapse(inst)
                else
                    local children = {}
                    pcall(function() children = inst:GetChildren() end)
                    local limit = math.min(#children, CFG.MAX_CHILDREN)
                    shiftOrdersAfter(data.row.LayoutOrder, limit)
                    local currentOrder = data.row.LayoutOrder
                    for i = 1, limit do
                        local child = children[i]
                        if rowMap[child] == nil then
                            orderCounter = orderCounter + 1
                            currentOrder = currentOrder + 1
                            local childRow = makeRow(child, depth + 1)
                            childRow.LayoutOrder = currentOrder
                            childRow.Parent = expTree
                            table.insert(data.children, child)
                        end
                    end
                    data.expanded = true
                    arrow.Text = "▼"
                end
            end)
        end)
    end

    local nameBtn = create("TextButton", {Size = UDim2.new(1, -105, 0, 18), Position = UDim2.new(0, 26 + depth * 12, 0, 0), BackgroundTransparency = 1, Text = "", ZIndex = 15, Parent = row})
    nameBtn.MouseButton1Click:Connect(function()
        pcall(function()
            local path = getServicePath(inst)
            copyToClipboard(path)
            local attrs = inst:GetAttributes()
            local attrLines = {}
            for k, v in pairs(attrs) do
                table.insert(attrLines, string.format("  %s = %s", k, v2s(v)))
            end
            local content = "-- Class: " .. inst.ClassName .. "\n-- Path: " .. path .. "\n-- Children: " .. #inst:GetChildren() .. "\n\n-- Attributes:\n" .. (#attrLines > 0 and table.concat(attrLines, "\n") or "  (none)")
            showModal(inst.Name .. " (path скопирован)", content, {
                {label = "Copy Path", color = CFG.COLORS.Success, cb = function() copyToClipboard(path) end},
                {label = "Copy Info", color = CFG.COLORS.Accent, cb = function() copyToClipboard(content) end},
            })
        end)
    end)

    row.MouseEnter:Connect(function() tw(row, 0.1, {BackgroundTransparency = 0.7, BackgroundColor3 = CFG.COLORS.Hover}) end)
    row.MouseLeave:Connect(function() tw(row, 0.1, {BackgroundTransparency = 1, BackgroundColor3 = CFG.COLORS.Panel}) end)

    return row
end

local ROOTS = {
    game:GetService("Workspace"),
    game:GetService("Players"),
    ReplicatedStorage,
    game:GetService("Lighting"),
    game:GetService("StarterGui"),
    game:GetService("SoundService"),
}

local function rebuildExplorer()
    for _, c in ipairs(expTree:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    rowMap = {}
    orderCounter = 0
    local filter = expSearchBox.Text:lower()
    for _, root in ipairs(ROOTS) do
        if root and (filter == "" or root.Name:lower():find(filter) or root.ClassName:lower():find(filter)) then
            makeRow(root, 0)
        end
    end
end

expSearchBox:GetPropertyChangedSignal("Text"):Connect(function() pcall(rebuildExplorer) end)
task.spawn(function() pcall(rebuildExplorer) end)

--=============================================================
-- TAB: SPY (SimpleSpy V3 style)
--=============================================================

local SpyTab = createTab("Spy", "↯")

local spyTopBar = create("Frame", {Size = UDim2.new(1, -10, 0, 20), Position = UDim2.new(0, 5, 0, 5), BackgroundTransparency = 1, ZIndex = 12, Parent = SpyTab.Page})
local spyFilterBox = create("TextBox", {
    Size = UDim2.new(1, -80, 1, 0),
    BackgroundColor3 = CFG.COLORS.PanelDark,
    BorderSizePixel = 0,
    Text = "",
    PlaceholderText = "Filter...",
    PlaceholderColor3 = CFG.COLORS.TextFaint,
    TextColor3 = CFG.COLORS.Text,
    TextSize = 9,
    Font = CFG.FONT_MONO,
    TextXAlignment = Enum.TextXAlignment.Left,
    ClearTextOnFocus = false,
    ZIndex = 12,
    Parent = spyTopBar,
})
corner(spyFilterBox, 3); stroke(spyFilterBox, CFG.COLORS.Border, 1); pad(spyFilterBox, 0, 5, 0, 5)

UI.iconBtn(spyTopBar, "📋", CFG.COLORS.Success, function()
    local out = {}
    for _, e in ipairs(RemoteSpy.Logs) do
        table.insert(out, string.format("[%s] %s(%s)", e.Time, e.Name, e.ArgsStr))
    end
    copyToClipboard(table.concat(out, "\n"))
end, 22).Position = UDim2.new(1, -46, 0, 0)

UI.iconBtn(spyTopBar, "×", CFG.COLORS.Danger, function()
    RemoteSpy.Logs = {}
    if RemoteSpy.UI then pcall(RemoteSpy.UI) end
end, 22).Position = UDim2.new(1, -22, 0, 0)

local spyBtnPanel = create("Frame", {Size = UDim2.new(1, -10, 0, 130), Position = UDim2.new(0, 5, 1, -135), BackgroundTransparency = 1, ZIndex = 12, Parent = SpyTab.Page})
create("UIGridLayout", {CellSize = UDim2.new(0, 95, 0, 18), CellPadding = UDim2.new(0, 3, 0, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = spyBtnPanel})

local spyLog = UI.scroll(SpyTab.Page, UDim2.new(0, 5, 0, 30), UDim2.new(1, -10, 1, -170))

local spyActions = {}

spyActions.CopyCode = function()
    if not RemoteSpy.Selected then return end
    copyToClipboard(RemoteSpy.Selected.FullCode or RemoteSpy.Selected.Code)
end

spyActions.CopyRemote = function()
    if not RemoteSpy.Selected then return end
    copyToClipboard(RemoteSpy.Selected.SafePath)
end

spyActions.RunCode = function()
    if not RemoteSpy.Selected then return end
    local e = RemoteSpy.Selected
    pcall(function()
        if e.IsFunc then
            local result = e.Remote:InvokeServer(unpack(e.Args))
            print("[DevTool] Result:", result)
        else
            e.Remote:FireServer(unpack(e.Args))
            print("[DevTool] Fired:", e.Name)
        end
    end)
end

spyActions.GetScript = function()
    if not RemoteSpy.Selected then return end
    local e = RemoteSpy.Selected
    if e.Callingscript then
        copyToClipboard(getServicePath(e.Callingscript))
    else
        copyToClipboard("-- calling script not found")
    end
end

spyActions.FunctionInfo = function()
    if not RemoteSpy.Selected then return end
    local e = RemoteSpy.Selected
    local info = e.Funcinfo or "-- no info"
    local content = "-- Function Info: " .. e.Name .. "\n-- Method: " .. tostring(e.Method) .. "\n-- Callingscript: " .. (e.Callingscript and getServicePath(e.Callingscript) or "nil") .. "\n\n" .. tostring(info)
    showModal("Function Info", content)
end

spyActions.ClrLogs = function()
    RemoteSpy.Logs = {}
    RemoteSpy.Selected = nil
    if RemoteSpy.UI then pcall(RemoteSpy.UI) end
end

spyActions.ExcludeI = function()
    if not RemoteSpy.Selected then return end
    RemoteSpy.BlackList[tostring(RemoteSpy.Selected.Remote)] = true
    RemoteSpy.BlackList[RemoteSpy.Selected.Name] = true
end

spyActions.ExcludeN = function()
    if not RemoteSpy.Selected then return end
    RemoteSpy.BlackList[RemoteSpy.Selected.Name] = true
end

spyActions.ClrBlacklist = function() RemoteSpy.BlackList = {} end

spyActions.BlockI = function()
    if not RemoteSpy.Selected then return end
    RemoteSpy.BlockList[tostring(RemoteSpy.Selected.Remote)] = true
end

spyActions.BlockN = function()
    if not RemoteSpy.Selected then return end
    RemoteSpy.BlockList[RemoteSpy.Selected.Name] = true
end

spyActions.ClrBlocklist = function() RemoteSpy.BlockList = {} end

local spyButtonsList = {
    {"Copy Code", CFG.COLORS.Success, spyActions.CopyCode},
    {"Copy Remote", CFG.COLORS.Accent, spyActions.CopyRemote},
    {"Run Code", CFG.COLORS.Warning, spyActions.RunCode},
    {"Get Script", CFG.COLORS.Accent, spyActions.GetScript},
    {"Function Info", CFG.COLORS.Accent, spyActions.FunctionInfo},
    {"Clr Logs", CFG.COLORS.Danger, spyActions.ClrLogs},
    {"Exclude (i)", CFG.COLORS.PanelLight, spyActions.ExcludeI},
    {"Exclude (n)", CFG.COLORS.PanelLight, spyActions.ExcludeN},
    {"Clr Blacklist", CFG.COLORS.PanelLight, spyActions.ClrBlacklist},
    {"Block (i)", CFG.COLORS.Danger, spyActions.BlockI},
    {"Block (n)", CFG.COLORS.Danger, spyActions.BlockN},
    {"Clr Blocklist", CFG.COLORS.PanelLight, spyActions.ClrBlocklist},
}

for _, btnData in ipairs(spyButtonsList) do
    UI.textBtn(spyBtnPanel, btnData[1], btnData[2], btnData[3], 95)
end

RemoteSpy.UI = function()
    for _, c in ipairs(spyLog:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    local filter = spyFilterBox.Text:lower()
    local filtered = {}
    for _, e in ipairs(RemoteSpy.Logs) do
        if filter == "" or e.Name:lower():find(filter) then
            table.insert(filtered, e)
        end
    end
    local start = math.max(1, #filtered - 199)
    for i = start, #filtered do
        local e = filtered[i]
        local isSelected = (RemoteSpy.Selected == e)
        local row = create("Frame", {
            Size = UDim2.new(1, -3, 0, 18),
            BackgroundColor3 = isSelected and CFG.COLORS.Selected or CFG.COLORS.Panel,
            BackgroundTransparency = isSelected and 0.3 or 0.5,
            BorderSizePixel = 0,
            ZIndex = 12,
            Parent = spyLog,
        })
        corner(row, 3)
        local color = e.IsFunc and CFG.COLORS.RemoteFunction or CFG.COLORS.RemoteEvent
        create("Frame", {Size = UDim2.new(0, 2, 1, -4), Position = UDim2.new(0, 2, 0, 2), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 13, Parent = row})
        create("TextLabel", {Size = UDim2.new(0, 45, 1, 0), Position = UDim2.new(0, 6, 0, 0), BackgroundTransparency = 1, Text = e.Time, TextColor3 = CFG.COLORS.TextFaint, TextSize = 8, Font = CFG.FONT_MONO, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13, Parent = row})
        create("TextLabel", {Size = UDim2.new(0, 100, 1, 0), Position = UDim2.new(0, 52, 0, 0), BackgroundTransparency = 1, Text = e.Name, TextColor3 = CFG.COLORS.Text, TextSize = 9, Font = CFG.FONT_MONO, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 13, Parent = row})
        create("TextLabel", {Size = UDim2.new(1, -160, 1, 0), Position = UDim2.new(0, 155, 0, 0), BackgroundTransparency = 1, Text = e.ArgsStr, TextColor3 = CFG.COLORS.TextDim, TextSize = 8, Font = CFG.FONT_MONO, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 13, Parent = row})

        local btn = create("TextButton", {Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 14, Parent = row})
        btn.MouseButton1Click:Connect(function()
            RemoteSpy.Selected = e
            if RemoteSpy.UI then pcall(RemoteSpy.UI) end
            showModal("Remote: " .. e.Name, e.FullCode, {
                {label = "Copy Code", color = CFG.COLORS.Success, cb = function() copyToClipboard(e.FullCode) end},
                {label = "Run", color = CFG.COLORS.Warning, cb = spyActions.RunCode},
            })
        end)
        btn.MouseEnter:Connect(function() tw(row, 0.1, {BackgroundTransparency = 0}) end)
        btn.MouseLeave:Connect(function() if not isSelected then tw(row, 0.1, {BackgroundTransparency = 0.5}) end end)
    end
end

spyFilterBox:GetPropertyChangedSignal("Text"):Connect(function()
    if RemoteSpy.UI then pcall(RemoteSpy.UI) end
end)
--=============================================================
-- ЧАСТЬ 2 — Remotes, Modules, Log, Attr, Scan, Search, Dumper, Init
--=============================================================

--=============================================================
-- TAB: REMOTES
--=============================================================

local RemotesTab = createTab("Remotes", "◈")

local remoteTopBar = create("Frame", {Size = UDim2.new(1, -10, 0, 20), Position = UDim2.new(0, 5, 0, 5), BackgroundTransparency = 1, ZIndex = 12, Parent = RemotesTab.Page})
local remoteFilterBox = create("TextBox", {
    Size = UDim2.new(1, -80, 1, 0),
    BackgroundColor3 = CFG.COLORS.PanelDark,
    BorderSizePixel = 0,
    Text = "",
    PlaceholderText = "Filter...",
    PlaceholderColor3 = CFG.COLORS.TextFaint,
    TextColor3 = CFG.COLORS.Text,
    TextSize = 9,
    Font = CFG.FONT_MONO,
    TextXAlignment = Enum.TextXAlignment.Left,
    ClearTextOnFocus = false,
    ZIndex = 12,
    Parent = remoteTopBar,
})
corner(remoteFilterBox, 3); stroke(remoteFilterBox, CFG.COLORS.Border, 1); pad(remoteFilterBox, 0, 5, 0, 5)

UI.iconBtn(remoteTopBar, "📋", CFG.COLORS.Success, function()
    local out = {}
    for _, r in ipairs(State.Cache.RemoteList or {}) do
        if r and r.Parent then table.insert(out, getServicePath(r)) end
    end
    copyToClipboard(table.concat(out, "\n"))
end, 22).Position = UDim2.new(1, -46, 0, 0)

UI.iconBtn(remoteTopBar, "↻", nil, function() State.Cache.RemoteList = nil end, 22).Position = UDim2.new(1, -22, 0, 0)

local remoteList = UI.scroll(RemotesTab.Page, UDim2.new(0, 5, 0, 30), UDim2.new(1, -10, 1, -35))

local function refreshRemotes()
    if not State.Cache.RemoteList then
        State.Cache.RemoteList = {}
        task.spawn(function()
            for _, obj in ipairs(game:GetDescendants()) do
                if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
                    table.insert(State.Cache.RemoteList, obj)
                end
            end
        end)
        task.wait(0.2)
    end
    for _, c in ipairs(remoteList:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    local filter = remoteFilterBox.Text:lower()
    local shown = 0
    for _, obj in ipairs(State.Cache.RemoteList) do
        if shown >= CFG.MAX_REMOTES then break end
        if obj and obj.Parent and (filter == "" or obj.Name:lower():find(filter)) then
            shown = shown + 1
            local row = create("Frame", {Size = UDim2.new(1, -3, 0, 20), BackgroundColor3 = CFG.COLORS.Panel, BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 12, Parent = remoteList})
            corner(row, 3)
            local color = obj:IsA("RemoteEvent") and CFG.COLORS.RemoteEvent or CFG.COLORS.RemoteFunction
            create("Frame", {Size = UDim2.new(0, 2, 1, -4), Position = UDim2.new(0, 2, 0, 2), BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 13, Parent = row})
            create("TextLabel", {Size = UDim2.new(0, 90, 1, 0), Position = UDim2.new(0, 6, 0, 0), BackgroundTransparency = 1, Text = obj.ClassName, TextColor3 = color, TextSize = 8, Font = CFG.FONT_MONO, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13, Parent = row})
            create("TextLabel", {Size = UDim2.new(1, -100, 1, 0), Position = UDim2.new(0, 97, 0, 0), BackgroundTransparency = 1, Text = obj.Name, TextColor3 = CFG.COLORS.Text, TextSize = 9, Font = CFG.FONT_MONO, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 13, Parent = row})
            local btn = create("TextButton", {Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 14, Parent = row})
            btn.MouseButton1Click:Connect(function()
                local content = string.format("-- %s: %s\n-- Path: %s\n\n%s:FireServer()", obj.ClassName, obj.Name, getPath(obj), getServicePath(obj))
                if obj:IsA("RemoteFunction") then
                    content = string.format("-- %s: %s\n-- Path: %s\n\nlocal result = %s:InvokeServer()", obj.ClassName, obj.Name, getPath(obj), getServicePath(obj))
                end
                showModal(obj.Name, content, {
                    {label = "Copy Path", color = CFG.COLORS.Success, cb = function() copyToClipboard(getServicePath(obj)) end},
                    {label = "Copy Code", color = CFG.COLORS.Accent, cb = function() copyToClipboard(content) end},
                })
            end)
            btn.MouseEnter:Connect(function() tw(row, 0.1, {BackgroundTransparency = 0}) end)
            btn.MouseLeave:Connect(function() tw(row, 0.1, {BackgroundTransparency = 0.5}) end)
        end
    end
end
remoteFilterBox:GetPropertyChangedSignal("Text"):Connect(function() pcall(refreshRemotes) end)

--=============================================================
-- TAB: MODULES (с кнопкой Dump)
--=============================================================

local ModTab = createTab("Mods", "◆")

local modTopBar = create("Frame", {Size = UDim2.new(1, -10, 0, 20), Position = UDim2.new(0, 5, 0, 5), BackgroundTransparency = 1, ZIndex = 12, Parent = ModTab.Page})
local modFilterBox = create("TextBox", {
    Size = UDim2.new(1, -110, 1, 0),
    BackgroundColor3 = CFG.COLORS.PanelDark,
    BorderSizePixel = 0,
    Text = "",
    PlaceholderText = "Search...",
    PlaceholderColor3 = CFG.COLORS.TextFaint,
    TextColor3 = CFG.COLORS.Text,
    TextSize = 9,
    Font = CFG.FONT_MONO,
    TextXAlignment = Enum.TextXAlignment.Left,
    ClearTextOnFocus = false,
    ZIndex = 12,
    Parent = modTopBar,
})
corner(modFilterBox, 3); stroke(modFilterBox, CFG.COLORS.Border, 1); pad(modFilterBox, 0, 5, 0, 5)

-- Кнопка DUMP
UI.iconBtn(modTopBar, "💾", CFG.COLORS.Warning, function()
    task.spawn(function()
        -- Создаём структуру папок
        pcall(function()
            makefolder("DevTool")
            makefolder("DevTool/Dumps")
            makefolder("DevTool/Dumps/Scripts")
            makefolder("DevTool/Dumps/Scripts/LocalScripts")
            makefolder("DevTool/Dumps/Scripts/ModuleScripts")
        end)

        local count = 0
        local saved = 0

        -- Дамп LocalScript и ModuleScript
        for _, obj in ipairs(game:GetDescendants()) do
            if obj:IsA("LocalScript") or obj:IsA("ModuleScript") then
                count = count + 1
                local ok, source = pcall(function()
                    if decompile then return decompile(obj) end
                    return obj.Source
                end)

                if ok and source then
                    local subfolder = obj:IsA("LocalScript") and "LocalScripts" or "ModuleScripts"
                    local path = obj:GetFullName():gsub("^game%.", ""):gsub("%.", "_"):gsub("/", "_")
                    if #path > 150 then path = path:sub(1, 150) end
                    local filepath = "DevTool/Dumps/Scripts/" .. subfolder .. "/" .. path .. ".lua"
                    pcall(function()
                        writefile(filepath, "-- " .. obj:GetFullName() .. "\n-- Class: " .. obj.ClassName .. "\n\n" .. source)
                        saved = saved + 1
                    end)
                end

                if count % 20 == 0 then task.wait() end
            end
        end

        showModal("Dump Complete", string.format("Просканировано: %d\nСохранено: %d\n\nПапка: DevTool/Dumps/Scripts/", count, saved))
    end)
end, 22).Position = UDim2.new(1, -76, 0, 0)

UI.iconBtn(modTopBar, "📋", CFG.COLORS.Success, function()
    local out = {}
    for _, m in ipairs(State.Cache.ModList or {}) do
        if m and m.Parent then table.insert(out, getServicePath(m)) end
    end
    copyToClipboard(table.concat(out, "\n"))
end, 22).Position = UDim2.new(1, -46, 0, 0)

UI.iconBtn(modTopBar, "↻", nil, function() State.Cache.ModList = nil end, 22).Position = UDim2.new(1, -22, 0, 0)

local modList = UI.scroll(ModTab.Page, UDim2.new(0, 5, 0, 30), UDim2.new(1, -10, 1, -35))

local function refreshModules()
    if not State.Cache.ModList then
        State.Cache.ModList = {}
        task.spawn(function()
            for _, obj in ipairs(game:GetDescendants()) do
                if obj:IsA("ModuleScript") then table.insert(State.Cache.ModList, obj) end
            end
        end)
        task.wait(0.2)
    end
    for _, c in ipairs(modList:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    local filter = modFilterBox.Text:lower()
    local shown = 0
    for _, obj in ipairs(State.Cache.ModList) do
        if shown >= CFG.MAX_MODULES then break end
        if obj and obj.Parent and (filter == "" or obj.Name:lower():find(filter)) then
            shown = shown + 1
            local row = create("Frame", {Size = UDim2.new(1, -3, 0, 20), BackgroundColor3 = CFG.COLORS.Panel, BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 12, Parent = modList})
            corner(row, 3)
            create("Frame", {Size = UDim2.new(0, 2, 1, -4), Position = UDim2.new(0, 2, 0, 2), BackgroundColor3 = CFG.COLORS.ModuleScript, BorderSizePixel = 0, ZIndex = 13, Parent = row})
            create("TextLabel", {Size = UDim2.new(0, 160, 1, 0), Position = UDim2.new(0, 6, 0, 0), BackgroundTransparency = 1, Text = obj.Name, TextColor3 = CFG.COLORS.Text, TextSize = 9, Font = CFG.FONT_MONO, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 13, Parent = row})
            create("TextLabel", {Size = UDim2.new(1, -170, 1, 0), Position = UDim2.new(0, 167, 0, 0), BackgroundTransparency = 1, Text = getServicePath(obj.Parent), TextColor3 = CFG.COLORS.TextFaint, TextSize = 8, Font = CFG.FONT_MONO, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 13, Parent = row})
            local btn = create("TextButton", {Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 14, Parent = row})
            btn.MouseButton1Click:Connect(function()
                local src = "-- Source unavailable"
                pcall(function()
                    if decompile then src = decompile(obj) else src = obj.Source end
                end)
                local content = string.format("-- Module: %s\n-- Path: %s\n\n%s", obj.Name, getServicePath(obj), src)
                showModal(obj.Name, content, {
                    {label = "Copy Source", color = CFG.COLORS.Accent, cb = function() copyToClipboard(src) end},
                    {label = "Copy Path", color = CFG.COLORS.Success, cb = function() copyToClipboard(getServicePath(obj)) end},
                    {label = "Save File", color = CFG.COLORS.Warning, cb = function()
                        task.spawn(function()
                            pcall(function()
                                makefolder("DevTool")
                                makefolder("DevTool/Dumps")
                                local path = "DevTool/Dumps/" .. obj.Name .. ".lua"
                                writefile(path, src)
                                print("[DevTool] Saved to " .. path)
                            end)
                        end)
                    end},
                })
            end)
            btn.MouseEnter:Connect(function() tw(row, 0.1, {BackgroundTransparency = 0}) end)
            btn.MouseLeave:Connect(function() tw(row, 0.1, {BackgroundTransparency = 0.5}) end)
        end
    end
end
modFilterBox:GetPropertyChangedSignal("Text"):Connect(function() pcall(refreshModules) end)

--=============================================================
-- TAB: SCAN (Upvalue Scanner)
--=============================================================

local ScanTab = createTab("Scan", "🔍")

local scanTopBar = create("Frame", {Size = UDim2.new(1, -10, 0, 20), Position = UDim2.new(0, 5, 0, 5), BackgroundTransparency = 1, ZIndex = 12, Parent = ScanTab.Page})
local scanInput = create("TextBox", {
    Size = UDim2.new(1, -70, 1, 0),
    BackgroundColor3 = CFG.COLORS.PanelDark,
    BorderSizePixel = 0,
    Text = "",
    PlaceholderText = "Enter variable name (e.g. Health, Damage, Money)...",
    PlaceholderColor3 = CFG.COLORS.TextFaint,
    TextColor3 = CFG.COLORS.Text,
    TextSize = 9,
    Font = CFG.FONT_MONO,
    TextXAlignment = Enum.TextXAlignment.Left,
    ClearTextOnFocus = false,
    ZIndex = 12,
    Parent = scanTopBar,
})
corner(scanInput, 3); stroke(scanInput, CFG.COLORS.Border, 1); pad(scanInput, 0, 5, 0, 5)

UI.iconBtn(scanTopBar, "🔍", CFG.COLORS.Success, function()
    local search = scanInput.Text
    if search == "" then return end
    scanInput.Text = ""

    task.spawn(function()
        local results = {}
        local searchLower = search:lower()
        local scanned = 0

        -- Сканируем GC
        local ok, gc = pcall(function() return getgc() end)
        if not ok then
            showModal("Scan", "-- getgc() недоступен в этом инжекторе")
            return
        end

        for _, obj in ipairs(gc) do
            if type(obj) == "function" then
                local isExploit = false
                pcall(function() isExploit = isexploitclosure(obj) end)
                if not isExploit then
                    local ok2, ups = pcall(function() return getupvalues(obj) end)
                    if ok2 and ups then
                        for idx, upv in pairs(ups) do
                            if type(upv) == "table" then
                                for k, v in pairs(upv) do
                                    if tostring(k):lower():find(searchLower) then
                                        local key = tostring(k)
                                        if not results[key] then
                                            results[key] = {
                                                value = v2s(v),
                                                holder = upv,
                                                count = 1,
                                            }
                                        else
                                            results[key].count = results[key].count + 1
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            scanned = scanned + 1
            if scanned % 500 == 0 then task.wait() end
        end

        -- Рендер результатов
        for _, c in ipairs(scanResults:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end

        local resultCount = 0
        for name, data in pairs(results) do
            resultCount = resultCount + 1
            if resultCount > CFG.MAX_SCAN_RESULTS then break end

            local row = create("Frame", {Size = UDim2.new(1, -3, 0, 22), BackgroundColor3 = CFG.COLORS.Panel, BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 12, Parent = scanResults})
            corner(row, 3)
            create("Frame", {Size = UDim2.new(0, 2, 1, -4), Position = UDim2.new(0, 2, 0, 2), BackgroundColor3 = CFG.COLORS.Warning, BorderSizePixel = 0, ZIndex = 13, Parent = row})
            create("TextLabel", {Size = UDim2.new(0, 140, 1, 0), Position = UDim2.new(0, 6, 0, 0), BackgroundTransparency = 1, Text = name, TextColor3 = CFG.COLORS.Warning, TextSize = 9, Font = CFG.FONT_MONO, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 13, Parent = row})
            create("TextLabel", {Size = UDim2.new(0, 60, 1, 0), Position = UDim2.new(0, 150, 0, 0), BackgroundTransparency = 1, Text = "x" .. data.count, TextColor3 = CFG.COLORS.TextFaint, TextSize = 8, Font = CFG.FONT_MONO, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13, Parent = row})
            create("TextLabel", {Size = UDim2.new(1, -220, 1, 0), Position = UDim2.new(0, 215, 0, 0), BackgroundTransparency = 1, Text = data.value, TextColor3 = CFG.COLORS.Text, TextSize = 8, Font = CFG.FONT_MONO, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 13, Parent = row})

            local btn = create("TextButton", {Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 14, Parent = row})
            btn.MouseButton1Click:Connect(function()
                local genScript = "-- Изменяет " .. name .. " во всех таблицах где найдено\n"
                genScript = genScript .. "local newVal = 100\n"
                genScript = genScript .. "local getgc = getgc or get_gc_objects\n"
                genScript = genScript .. "local getupvalues = debug.getupvalues or getupvalues or getupvals\n\n"
                genScript = genScript .. "for a, b in next, getgc() do\n"
                genScript = genScript .. "    if type(b) == 'function' then\n"
                genScript = genScript .. "        for c, d in next, getupvalues(b) do\n"
                genScript = genScript .. "            if type(d) == 'table' and rawget(d, '" .. name .. "') then\n"
                genScript = genScript .. "                d." .. name .. " = newVal\n"
                genScript = genScript .. "            end\n"
                genScript = genScript .. "        end\n"
                genScript = genScript .. "    end\n"
                genScript = genScript .. "end"

                showModal("Scan: " .. name, genScript, {
                    {label = "Copy Code", color = CFG.COLORS.Accent, cb = function() copyToClipboard(genScript) end},
                    {label = "Run", color = CFG.COLORS.Success, cb = function()
                        local fn = loadstring(genScript)
                        if fn then pcall(fn) end
                    end},
                })
            end)
            btn.MouseEnter:Connect(function() tw(row, 0.1, {BackgroundTransparency = 0}) end)
            btn.MouseLeave:Connect(function() tw(row, 0.1, {BackgroundTransparency = 0.5}) end)
        end

        if resultCount == 0 then
            showModal("Scan: " .. search, "-- Ничего не найдено для: " .. search)
        else
            print("[DevTool Scan] Found " .. resultCount .. " matches for: " .. search)
        end
    end)
end, 60).Position = UDim2.new(1, -60, 0, 0)

local scanResults = UI.scroll(ScanTab.Page, UDim2.new(0, 5, 0, 30), UDim2.new(1, -10, 1, -35))

--=============================================================
-- TAB: SEARCH (глобальный поиск)
--=============================================================

local SearchTab = createTab("Search", "🔎")

local searchTopBar = create("Frame", {Size = UDim2.new(1, -10, 0, 20), Position = UDim2.new(0, 5, 0, 5), BackgroundTransparency = 1, ZIndex = 12, Parent = SearchTab.Page})
local globalSearchInput = create("TextBox", {
    Size = UDim2.new(1, -70, 1, 0),
    BackgroundColor3 = CFG.COLORS.PanelDark,
    BorderSizePixel = 0,
    Text = "",
    PlaceholderText = "Search across all categories...",
    PlaceholderColor3 = CFG.COLORS.TextFaint,
    TextColor3 = CFG.COLORS.Text,
    TextSize = 9,
    Font = CFG.FONT_MONO,
    TextXAlignment = Enum.TextXAlignment.Left,
    ClearTextOnFocus = false,
    ZIndex = 12,
    Parent = searchTopBar,
})
corner(globalSearchInput, 3); stroke(globalSearchInput, CFG.COLORS.Border, 1); pad(globalSearchInput, 0, 5, 0, 5)

local searchResults = UI.scroll(SearchTab.Page, UDim2.new(0, 5, 0, 30), UDim2.new(1, -10, 1, -35))

local searchCategories = {
    {name = "Remotes", filter = function(o) return o:IsA("RemoteEvent") or o:IsA("RemoteFunction") end, color = CFG.COLORS.RemoteEvent},
    {name = "Modules", filter = function(o) return o:IsA("ModuleScript") end, color = CFG.COLORS.ModuleScript},
    {name = "LocalScripts", filter = function(o) return o:IsA("LocalScript") end, color = CFG.COLORS.LocalScript},
    {name = "Scripts", filter = function(o) return o:IsA("Script") end, color = CFG.COLORS.Script},
    {name = "Bindables", filter = function(o) return o:IsA("BindableEvent") or o:IsA("BindableFunction") end, color = CFG.COLORS.BindableEvent},
}

local function doGlobalSearch()
    local query = globalSearchInput.Text:lower()
    if query == "" then return end

    for _, c in ipairs(searchResults:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end

    task.spawn(function()
        local total = 0

        for _, cat in ipairs(searchCategories) do
            local found = {}
            for _, obj in ipairs(game:GetDescendants()) do
                if cat.filter(obj) and obj.Name:lower():find(query) then
                    table.insert(found, obj)
                    if #found >= 50 then break end
                end
            end

            if #found > 0 then
                -- Заголовок категории
                local header = create("Frame", {Size = UDim2.new(1, -3, 0, 18), BackgroundColor3 = CFG.COLORS.Selected, BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 12, Parent = searchResults})
                corner(header, 3)
                create("TextLabel", {Size = UDim2.new(1, -6, 1, 0), Position = UDim2.new(0, 6, 0, 0), BackgroundTransparency = 1, Text = cat.name .. " (" .. #found .. ")", TextColor3 = cat.color, TextSize = 9, Font = CFG.FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13, Parent = header})

                for _, obj in ipairs(found) do
                    total = total + 1
                    local row = create("Frame", {Size = UDim2.new(1, -3, 0, 18), BackgroundColor3 = CFG.COLORS.Panel, BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 12, Parent = searchResults})
                    corner(row, 3)
                    create("Frame", {Size = UDim2.new(0, 2, 1, -4), Position = UDim2.new(0, 2, 0, 2), BackgroundColor3 = cat.color, BorderSizePixel = 0, ZIndex = 13, Parent = row})
                    create("TextLabel", {Size = UDim2.new(0, 180, 1, 0), Position = UDim2.new(0, 8, 0, 0), BackgroundTransparency = 1, Text = obj.Name, TextColor3 = CFG.COLORS.Text, TextSize = 9, Font = CFG.FONT_MONO, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 13, Parent = row})
                    create("TextLabel", {Size = UDim2.new(1, -200, 1, 0), Position = UDim2.new(0, 195, 0, 0), BackgroundTransparency = 1, Text = getServicePath(obj.Parent), TextColor3 = CFG.COLORS.TextFaint, TextSize = 8, Font = CFG.FONT_MONO, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 13, Parent = row})

                    local btn = create("TextButton", {Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 14, Parent = row})
                    btn.MouseButton1Click:Connect(function()
                        copyToClipboard(getServicePath(obj))
                        print("[DevTool] Copied: " .. getServicePath(obj))
                    end)
                end
            end
            task.wait()
        end

        print("[DevTool Search] Found " .. total .. " total matches for: " .. query)
    end)
end

UI.iconBtn(searchTopBar, "🔎", CFG.COLORS.Success, doGlobalSearch, 60).Position = UDim2.new(1, -60, 0, 0)
globalSearchInput.FocusLost:Connect(doGlobalSearch)

--=============================================================
-- TAB: LOG (Console)
--=============================================================

local ConsoleTab = createTab("Log", ">_")
local logList = UI.scroll(ConsoleTab.Page, UDim2.new(0, 5, 0, 5), UDim2.new(1, -10, 0.6, -10))

local consoleInputWrap = create("Frame", {Size = UDim2.new(1, -10, 0.4, -10), Position = UDim2.new(0, 5, 0.6, 0), BackgroundTransparency = 1, ZIndex = 12, Parent = ConsoleTab.Page})
local consoleInput = create("TextBox", {
    Size = UDim2.new(1, 0, 0, 55),
    BackgroundColor3 = CFG.COLORS.PanelDark,
    BorderSizePixel = 0,
    Text = "",
    PlaceholderText = "Lua code...",
    PlaceholderColor3 = CFG.COLORS.TextFaint,
    TextColor3 = CFG.COLORS.Text,
    TextSize = 9,
    Font = CFG.FONT_MONO,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    TextWrapped = true,
    ClearTextOnFocus = false,
    MultiLine = true,
    ZIndex = 12,
    Parent = consoleInputWrap,
})
corner(consoleInput, 3); stroke(consoleInput, CFG.COLORS.Border, 1); pad(consoleInput, 5, 5, 5, 5)

UI.iconBtn(consoleInputWrap, "▶", CFG.COLORS.Success, function()
    local code = consoleInput.Text
    if code == "" then return end
    local fn, err = loadstring(code)
    if not fn then warn("[DevTool] " .. tostring(err)); return end
    local ok, result = pcall(fn)
    if not ok then warn("[DevTool] " .. tostring(result))
    elseif result ~= nil then print("[DevTool] " .. tostring(result)) end
end, 20).Position = UDim2.new(0, 0, 1, -22)

UI.iconBtn(consoleInputWrap, "×", CFG.COLORS.Danger, function()
    for _, c in ipairs(logList:GetChildren()) do if c:IsA("Frame") then c:Destroy() end end
end, 20).Position = UDim2.new(0, 24, 1, -22)

local logCount = 0
local function appendLog(message, msgType)
    if logCount > 100 then
        local first = logList:FindFirstChildWhichIsA("Frame")
        if first then first:Destroy(); logCount = logCount - 1 end
    end
    logCount = logCount + 1
    local row = create("Frame", {Size = UDim2.new(1, -3, 0, 16), BackgroundColor3 = CFG.COLORS.Panel, BackgroundTransparency = 0.7, BorderSizePixel = 0, ZIndex = 12, Parent = logList})
    corner(row, 3)
    local color = CFG.COLORS.Text
    if msgType == Enum.MessageType.MessageError then color = CFG.COLORS.Danger
    elseif msgType == Enum.MessageType.MessageWarning then color = CFG.COLORS.Warning
    end
    create("TextLabel", {Size = UDim2.new(0, 45, 1, 0), Position = UDim2.new(0, 5, 0, 0), BackgroundTransparency = 1, Text = os.date("%H:%M:%S"), TextColor3 = CFG.COLORS.TextFaint, TextSize = 8, Font = CFG.FONT_MONO, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13, Parent = row})
    create("TextLabel", {Size = UDim2.new(1, -55, 1, 0), Position = UDim2.new(0, 52, 0, 0), BackgroundTransparency = 1, Text = message, TextColor3 = color, TextSize = 8, Font = CFG.FONT_MONO, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 13, Parent = row})
end

pcall(function()
    LogService.MessageOut:Connect(function(message, msgType)
        pcall(function() appendLog(message, msgType) end)
    end)
end)

--=============================================================
-- TAB: ATTR
--=============================================================

local RefTab = createTab("Attr", "◈")

create("TextLabel", {Size = UDim2.new(1, -10, 0, 16), Position = UDim2.new(0, 5, 0, 3), BackgroundTransparency = 1, Text = "ATTRIBUTES", TextColor3 = CFG.COLORS.TextDim, TextSize = 9, Font = CFG.FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12, Parent = RefTab.Page})
local attrList = UI.scroll(RefTab.Page, UDim2.new(0, 5, 0, 20), UDim2.new(1, -10, 0.45, -25))

local function refreshAttributes()
    for _, c in ipairs(attrList:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    if not State.Cache.Attrs then
        State.Cache.Attrs = {}
        task.spawn(function()
            local count = 0
            for _, obj in ipairs(game:GetDescendants()) do
                if count >= CFG.MAX_ATTRS then break end
                local ok, attrs = pcall(function() return obj:GetAttributes() end)
                if ok and attrs and next(attrs) then
                    for name, value in pairs(attrs) do
                        count = count + 1
                        if count > CFG.MAX_ATTRS then break end
                        table.insert(State.Cache.Attrs, {name = name, value = value, inst = obj})
                    end
                end
                if count % 200 == 0 then task.wait() end
            end
        end)
        task.wait(0.3)
    end
    for _, item in ipairs(State.Cache.Attrs) do
        local row = create("Frame", {Size = UDim2.new(1, -3, 0, 18), BackgroundColor3 = CFG.COLORS.Panel, BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 12, Parent = attrList})
        corner(row, 3)
        create("TextLabel", {Size = UDim2.new(0, 120, 1, 0), Position = UDim2.new(0, 5, 0, 0), BackgroundTransparency = 1, Text = item.name, TextColor3 = CFG.COLORS.Warning, TextSize = 8, Font = CFG.FONT_MONO, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 13, Parent = row})
        create("TextLabel", {Size = UDim2.new(1, -130, 1, 0), Position = UDim2.new(0, 128, 0, 0), BackgroundTransparency = 1, Text = v2s(item.value), TextColor3 = CFG.COLORS.Text, TextSize = 8, Font = CFG.FONT_MONO, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 13, Parent = row})
    end
end

create("TextLabel", {Size = UDim2.new(1, -10, 0, 16), Position = UDim2.new(0, 5, 0.5, -8), BackgroundTransparency = 1, Text = "TAGS", TextColor3 = CFG.COLORS.TextDim, TextSize = 9, Font = CFG.FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12, Parent = RefTab.Page})
local tagList = UI.scroll(RefTab.Page, UDim2.new(0, 5, 0.5, 10), UDim2.new(1, -10, 0.5, -15))

local function refreshTags()
    for _, c in ipairs(tagList:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    local ok, allTags = pcall(function() return CollectionService:GetAllTags() end)
    if not ok then return end
    for _, tag in ipairs(allTags) do
        local ok2, objs = pcall(function() return CollectionService:GetTagged(tag) end)
        local count = ok2 and #objs or 0
        local row = create("Frame", {Size = UDim2.new(1, -3, 0, 18), BackgroundColor3 = CFG.COLORS.Panel, BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 12, Parent = tagList})
        corner(row, 3)
        create("TextLabel", {Size = UDim2.new(0, 120, 1, 0), Position = UDim2.new(0, 5, 0, 0), BackgroundTransparency = 1, Text = tag, TextColor3 = CFG.COLORS.Success, TextSize = 8, Font = CFG.FONT_MONO, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13, Parent = row})
        create("TextLabel", {Size = UDim2.new(1, -130, 1, 0), Position = UDim2.new(0, 128, 0, 0), BackgroundTransparency = 1, Text = count .. " obj", TextColor3 = CFG.COLORS.Text, TextSize = 8, Font = CFG.FONT_MONO, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13, Parent = row})
    end
end

--=============================================================
-- LAZY REFRESH
--=============================================================

local refreshedOnce = {}
local function lazyRefresh(name, fn)
    if refreshedOnce[name] then return end
    refreshedOnce[name] = true
    task.spawn(function() pcall(fn) end)
end

for _, tab in ipairs(State.Tabs) do
    tab.Button.MouseButton1Click:Connect(function()
        if tab.Name == "Remotes" then lazyRefresh("Remotes", refreshRemotes)
        elseif tab.Name == "Mods" then lazyRefresh("Modules", refreshModules)
        elseif tab.Name == "Attr" then
            lazyRefresh("Attrs", refreshAttributes)
            lazyRefresh("Tags", refreshTags)
        end
    end)
end

--=============================================================
-- HIDE / SHOW
--=============================================================

local function setHidden(hidden)
    State.Hidden = hidden
    if hidden then
        State.SavedSize = Vector2.new(Window.Size.X.Offset, Window.Size.Y.Offset)
        tw(Window, 0.2, {Size = UDim2.new(0, CFG.HIDDEN_SIZE.X, 0, CFG.HIDDEN_SIZE.Y)})
        Content.Visible = false
        RH.Visible = false
    else
        Content.Visible = true
        RH.Visible = true
        tw(Window, 0.2, {Size = UDim2.new(0, State.SavedSize.X, 0, State.SavedSize.Y)}, Enum.EasingStyle.Back)
    end
end

HideBtn.MouseButton1Click:Connect(function() setHidden(true) end)

TB.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        State.Dragging = true
        State.DragStart = input.Position
        State.StartPos = Window.Position
    end
end)

local function setOpen(open)
    State.Open = open
    if open then
        Window.Visible = true
        Window.Size = UDim2.new(0, CFG.SIZE.X, 0, CFG.SIZE.Y)
        Content.Visible = true
        RH.Visible = true
        State.Hidden = false
    else
        Window.Visible = false
    end
end

RH.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        State.Resizing = true; State.DragStart = i.Position; State.StartSize = Vector2.new(Window.Size.X.Offset, Window.Size.Y.Offset)
    end
end)

UserInputService.InputChanged:Connect(function(i)
    if State.Dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - State.DragStart
        Window.Position = UDim2.new(State.StartPos.X.Scale, State.StartPos.X.Offset + d.X, State.StartPos.Y.Scale, State.StartPos.Y.Offset + d.Y)
    end
    if State.Resizing and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - State.DragStart
        local nx = math.clamp(State.StartSize.X + d.X, CFG.MIN_SIZE.X, CFG.MAX_SIZE.X)
        local ny = math.clamp(State.StartSize.Y + d.Y, CFG.MIN_SIZE.Y, CFG.MAX_SIZE.Y)
        Window.Size = UDim2.new(0, nx, 0, ny)
    end
end)

UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        State.Dragging = false; State.Resizing = false
    end
end)

CloseBtn.MouseButton1Click:Connect(function() setOpen(false) end)
MinBtn.MouseButton1Click:Connect(function() setHidden(not State.Hidden) end)

UserInputService.InputBegan:Connect(function(i, p)
    if p then return end
    if i.KeyCode == CFG.KEYBIND then
        if not State.Open then setOpen(true)
        elseif State.Hidden then setHidden(false)
        else setOpen(false) end
    end
end)

State.Tabs[1].Page.Visible = true
tw(State.Tabs[1].Button, 0.1, {BackgroundTransparency = 0.5, BackgroundColor3 = CFG.COLORS.Selected})
tw(State.Tabs[1].Label, 0.1, {TextColor3 = CFG.COLORS.Accent})

--=============================================================
-- INIT
--=============================================================

Window.Visible = true
Window.Size = UDim2.new(0, CFG.SIZE.X, 0, CFG.SIZE.Y)

RunService.Heartbeat:Connect(function()
    processScheduled()
end)

task.spawn(function()
    task.wait(CFG.AUTO_HOOK_DELAY)
    pcall(function()
        installHooks()
        RemoteSpy.Enabled = true
    end)
end)

_G.DevTool = {
    Window = Window,
    Open = function() setOpen(true) end,
    Close = function() setOpen(false) end,
    Toggle = function() setOpen(not State.Open) end,
    Hide = function() setHidden(true) end,
    Show = function() setHidden(false) end,
    ToggleHide = function() setHidden(not State.Hidden) end,
    RemoteSpy = RemoteSpy,
    ShowModal = showModal,
    GetPath = getPath,
    v2s = v2s,
    ClearCache = function() State.Cache = {} end,
    HookSpy = installHooks,
    UnhookSpy = uninstallHooks,
    Dump = function()
        -- Быстрый дамп всего в папку DevTool
        task.spawn(function()
            pcall(function()
                makefolder("DevTool")
                makefolder("DevTool/Dumps")
            end)
            local count = 0
            for _, obj in ipairs(game:GetDescendants()) do
                if obj:IsA("LocalScript") or obj:IsA("ModuleScript") then
                    local ok, source = pcall(function()
                        if decompile then return decompile(obj) end
                        return obj.Source
                    end)
                    if ok and source then
                        local path = "DevTool/Dumps/" .. obj.Name .. "_" .. tostring(count) .. ".lua"
                        pcall(function() writefile(path, source) end)
                        count = count + 1
                    end
                end
            end
            print("[DevTool] Dumped " .. count .. " scripts to DevTool/Dumps/")
        end)
    end,
}

print("[DevTool v8.0] Loaded. RightCtrl to toggle.")
print("[DevTool v8.0] Parent: " .. tostring(SG.Parent))
print("[DevTool v8.0] hookmetamethod: " .. tostring(type(hookmetamethod) == "function"))
print("[DevTool v8.0] getgc: " .. tostring(type(getgc) == "function"))
print("[DevTool v8.0] decompile: " .. tostring(type(decompile) == "function"))
print("[DevTool v8.0] writefile: " .. tostring(type(writefile) == "function"))
print("[DevTool v8.0] Dump folder: DevTool/Dumps/")
