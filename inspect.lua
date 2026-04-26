local side = ...

if not side then
    print("Usage: inspect <side>")
    return
end

if not peripheral.isPresent(side) then
    print("No peripheral.")
    return
end

local p = peripheral.wrap(side)

print("== "..side.." ==")

print("Types:")
for _,v in ipairs({peripheral.getType(side)}) do
    print(" "..v)
end

print("")
print("Methods:")

local methods = peripheral.getMethods(side)
table.sort(methods)

for _,name in ipairs(methods) do
    io.write(name)

    local ok, result = pcall(function()
        return p[name]()
    end)

    if ok and result ~= nil then
        print(" -> "..tostring(result))
    else
        print()
    end
end
