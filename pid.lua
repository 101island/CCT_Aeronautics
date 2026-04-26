local interval = 0.1
local last = os.clock()

while true do
    local timer = os.startTimer(interval)
    os.pullEvent("timer")

    local now = os.clock()
    local dt = now - last
    last = now

    -- PID(dt)
end