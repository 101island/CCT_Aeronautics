local altimeter = peripheral.wrap("right")
local engine = peripheral.wrap("left")

local target = 100   -- 目标高度

-- PID参数（需要调）
local Kp = 2.0
local Ki = 0
local Kd = 0

local integral = 0
local last_error = 0
local last_time = os.clock()

local hover = 120  -- 🔥 你必须测出来！

local dt = 0.05

while true do
    -- 用timer保证tick（避免卡死）
    os.startTimer(dt)
    os.pullEvent("timer")

    local now = os.clock()
    local dt = now - last_time
    print(string.format("dt=%.3f", dt))
    last_time = now

    local height = altimeter.getHeight()
    local error = target - height

    -- PID
    integral = integral + error * dt

    -- 防积分爆炸（关键）
    integral = math.max(-50, math.min(50, integral))

    local derivative = (error - last_error) / dt

    local pid = Kp * error + Ki * integral + Kd * derivative

    -- 输出
    local speed = hover + pid

    -- 限制范围
    speed = math.max(1, math.min(256, speed))

    engine.setGeneratedSpeed(speed)

    last_error = error

    print(string.format(
        "H=%.2f T=%.2f out=%.2f",
        height, target, speed
    ))
end