local args = {...}

------------------------------------------------
-- CONFIG
------------------------------------------------
local PAGE = 18
local MAX_DEPTH = 4
local AUTO_CALL = true

------------------------------------------------
-- COLOR SAFE
------------------------------------------------
local color = term.isColor and term.isColor()

local function c(t)
    if color then term.setTextColor(t) end
end

local function reset()
    if color then term.setTextColor(colors.white) end
end

------------------------------------------------
-- PAGER
------------------------------------------------
local lines = 0

local function println(txt)
    print(txt or "")
    lines = lines + 1
    if lines >= PAGE then
        c(colors.gray)
        write("--More-- Press Enter")
        reset()
        read()
        term.clear()
        term.setCursorPos(1,1)
        lines = 0
    end
end

------------------------------------------------
-- TABLE PRETTY PRINT
------------------------------------------------
local function seenTable()
    return setmetatable({}, {__mode="k"})
end

local function dump(value, depth, seen, prefix)
    depth = depth or 0
    prefix = prefix or ""

    local t = type(value)

    if t ~= "table" then
        println(prefix .. tostring(value))
        return
    end

    if seen[value] then
        println(prefix .. "<recursive table>")
        return
    end

    if depth >= MAX_DEPTH then
        println(prefix .. "{...}")
        return
    end

    seen[value] = true

    println(prefix .. "{")

    local keys = {}
    for k in pairs(value) do table.insert(keys, k) end

    table.sort(keys, function(a,b)
        return tostring(a) < tostring(b)
    end)

    for _,k in ipairs(keys) do
        local v = value[k]
        local head = string.rep(" ", depth*2+2) .. "["..tostring(k).."] = "

        if type(v) == "table" then
            dump(v, depth+1, seen, head)
        else
            println(head .. tostring(v))
        end
    end

    println(string.rep(" ", depth*2) .. "}")
end

local function parseArg(value)
    local first = value:sub(1, 1)
    local last = value:sub(-1)

    if #value >= 2 and ((first == '"' and last == '"') or (first == "'" and last == "'")) then
        return value:sub(2, -2)
    end

    local num = tonumber(value)
    if num ~= nil then
        return num
    end

    return value
end

local function formatArg(value)
    if type(value) == "string" then
        return string.format("%q", value)
    end

    return tostring(value)
end

------------------------------------------------
-- MAIN
------------------------------------------------
if not args[1] then
    print("Usage:")
    print("inspect <side>")
    print("inspect <side> <method> <arg1> ...")
    return
end

local side = args[1]

if not peripheral.isPresent(side) then
    print("No peripheral: "..side)
    return
end

local p = peripheral.wrap(side)

------------------------------------------------
-- METHOD MODE
------------------------------------------------
if args[2] then
    local method = args[2]
    local methodArgs = {}

    for i = 3, #args do
        methodArgs[#methodArgs + 1] = parseArg(args[i])
    end

    local previewArgs = {}
    for i = 1, #methodArgs do
        previewArgs[i] = formatArg(methodArgs[i])
    end

    c(colors.cyan)
    println("Calling "..method.."("..table.concat(previewArgs, ", ")..")")
    reset()

    local results = table.pack(pcall(function()
        return p[method](table.unpack(methodArgs, 1, #methodArgs))
    end))

    local ok = results[1]

    if not ok then
        c(colors.red)
        println("ERROR: "..tostring(results[2]))
        reset()
        return
    end

    if results.n == 1 then
        println("<no return values>")
        return
    end

    if results.n == 2 then
        dump(results[2],0,seenTable(),"")
        return
    end

    for i = 2, results.n do
        println("return #"..(i - 1)..":")
        dump(results[i],0,seenTable(),"  ")
    end

    return
end

------------------------------------------------
-- INSPECT MODE
------------------------------------------------
c(colors.yellow)
println("=== "..side.." ===")
reset()

c(colors.lime)
println("Types:")
reset()

local types = { peripheral.getType(side) }
for _,v in ipairs(types) do
    println(" - "..v)
end

println("")

local methods = peripheral.getMethods(side) or {}
table.sort(methods)

c(colors.orange)
println("Methods: "..#methods)
reset()

for _,m in ipairs(methods) do
    write(" - "..m)

    if AUTO_CALL then
        local ok, result = pcall(function()
            return p[m]()
        end)

        if ok then
            if result ~= nil then
                print(" -> "..type(result) .. " " .. tostring(result))
            else
                print()
            end
        else
            print()
        end
    else
        print()
    end
end

println("")
c(colors.gray)
println("Tip: inspect "..side.." <method> <arg1> ...")
reset()
