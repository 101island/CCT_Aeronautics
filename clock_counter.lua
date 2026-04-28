local relay = peripheral.find("redstone_relay")

if not relay then
    error("redstone_relay not found")
end

local interval = 0.05
local counts = {
    [1] = 0,
    [3] = 0,
    other = 0,
}

local function waitForTimer(timerId)
    while true do
        local event, firedTimerId = os.pullEvent("timer")
        if event == "timer" and firedTimerId == timerId then
            return
        end
    end
end

while true do
    local timerId = os.startTimer(interval)
    waitForTimer(timerId)

    local level = relay.getAnalogInput("left")

    if level == 1 or level == 3 then
        counts[level] = counts[level] + 1
    else
        counts.other = counts.other + 1
    end

    term.clear()
    term.setCursorPos(1, 1)
    print(string.format("Sample interval: %.2f s", interval))
    print(string.format("Current level: %d", level))
    print(string.format("Count 1: %d", counts[1]))
    print(string.format("Count 3: %d", counts[3]))
    print(string.format("Other: %d", counts.other))
end
