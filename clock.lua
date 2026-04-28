local interval = 0.1
local last = os.clock()
local relay = peripheral.find("redstone_relay")
local level = 1


local function waitForTimer(timerId)
    while true do
        local event, firedTimerId = os.pullEvent("timer")
        if event == "timer" and firedTimerId == timerId then
            return
        end
    end
end

while true do
    sleep(interval)

    relay.setAnalogOutput("right", level)
    level = level == 1 and 3 or 1

    local now = os.clock()
    local dt = now - last
    last = now
    print(string.format("Delta time: %.2f seconds", dt))


end
