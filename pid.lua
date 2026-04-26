-- 控制参数
local Kp = 1.8
local Ki = 0.02
local Kd = 0.5

local pressure = {
    points = {}
}

function pressure:addPoint(altitude, value, slope)
    table.insert(self.points, {
        altitude = altitude,
        value = value,
        slope = slope
    })
end

function pressure:evaluate(h)
    local pts = self.points
    local n = #pts

    if n == 0 then
        return 1.0
    end

    if n == 1 then
        return pts[1].value
    end

    -- 找区间
    local index = -1
    for i = 1, n do
        if h < pts[i].altitude then
            break
        end
        index = i
    end

    -- 边界情况
    if index == -1 then
        return pts[1].value
    end

    if index >= n then
        return pts[n].value
    end

    local p1 = pts[index]
    local p2 = pts[index + 1]

    local dx = p2.altitude - p1.altitude
    local dy = p2.value - p1.value

    -- 防止除0（非常重要）
    if dx == 0 then
        return p1.value
    end

    local t = (h - p1.altitude) / dx

    local s1 = p1.slope
    local s2 = p2.slope

    local cubic = (s1 + s2) * dx - 2 * dy
    local quadratic = 3 * dy - (2 * s1 + s2) * dx
    local linear = dx * s1

    local result = ((cubic * t + quadratic) * t + linear) * t + p1.value

    return math.max(result, 0)
end


local p = pressure

p:addPoint(-38.366277, 1.500000, -0.006000)
p:addPoint(63.000000, 1.000000, -0.004000)
p:addPoint(263.000000, 0.449329, -0.0017973)
p:addPoint(280.000000, 0.419790, -0.001679)
p:addPoint(320.000000, 0.000000, -0.020989)


local altimeter = peripheral.wrap("right")
local engine = peripheral.wrap("left")

-- ===== 已知：一个标定点 =====
local h0 = 70.3
local n0 = 50

target = 200

-- 气压函数
local function rho(h)
    return p:evaluate(h)
end

-- hover推力
local function hover_speed(h)
    return n0 * (rho(h0) / rho(h))
end



local last_h = altimeter.getHeight()

local dt = 0.1

local integral = 0

while true do
    os.startTimer(0.05)
    os.pullEvent("timer")


    local h = altimeter.getHeight()
    local v = (h - last_h) / dt
    last_h = h

    local error = target - h

    local base = hover_speed(target)

    integral = integral + error * dt

    integral = math.max(-50, math.min(50, integral))

    -- PID 控制
    local control = Kp * error + Ki * integral - Kd * v

    local speed = base + control
    speed = math.max(1, math.min(256, speed))

    engine.setGeneratedSpeed(speed)

    print(string.format(
        "H=%.2f T=%.2f control=%.2f",
        h, target, control
    ))
end