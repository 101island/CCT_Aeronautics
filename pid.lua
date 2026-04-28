-- 控制参数
local Kp = 0.6
local Ki = 0.0
local Kd = 1.2
local pwmWindowTicks = 5

target = 200
local targetStep = 1
local capacity = 122
local maxSteamOutput = 200

-- ===== 已知：一个标定点 =====
-- 在 h0 高度、红石信号为 hoverLevel 时可悬停
local h0 = 205
local hoverLevel = 7
local fill0 = maxSteamOutput * hoverLevel / 15

-- 获取高度计和热气球控制外设
local altimeter = peripheral.wrap("right")
local relay = peripheral.find("redstone_relay")
local monitor = peripheral.find("monitor")

if monitor then
    monitor.setTextScale(1)
    monitor.clear()
end

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

local function createDefaultPressureCurve(seaLevel, minY, logicalHeight)
    local currentAltitude = minY
    local maxAltitude = currentAltitude + logicalHeight

    local baseSlope = -0.004
    local maxPressure = 1.5
    local maxStep = 200.0
    local smoothingAltitude = maxAltitude - 40.0

    currentAltitude = math.max(currentAltitude, math.log(maxPressure) / baseSlope + seaLevel)

    local pressureFunction = {
        points = {}
    }

    function pressureFunction:addPoint(altitude, value, slope)
        table.insert(self.points, {
            altitude = altitude,
            value = value,
            slope = slope
        })
    end

    while true do
        local currentPressure = math.exp(baseSlope * (currentAltitude - seaLevel))
        local currentSlope = currentPressure * baseSlope
        pressureFunction:addPoint(currentAltitude, currentPressure, currentSlope)

        if currentAltitude < seaLevel and currentAltitude + maxStep >= seaLevel then
            currentAltitude = seaLevel
        elseif currentAltitude < smoothingAltitude and currentAltitude + maxStep >= smoothingAltitude then
            currentAltitude = smoothingAltitude
        elseif currentAltitude >= smoothingAltitude then
            break
        else
            currentAltitude = currentAltitude + maxStep
        end
    end

    local smoothingPressure = pressureFunction.points[#pressureFunction.points].value
    local finalSlope = -2.0 * smoothingPressure / (maxAltitude - smoothingAltitude)
    pressureFunction:addPoint(maxAltitude, 0.0, finalSlope)

    return pressureFunction
end


local p = pressure

local seaLevel = 63.0
local minY = -64.0
local logicalHeight = 704.0

p.points = createDefaultPressureCurve(seaLevel, minY, logicalHeight).points


-- 气压函数
local function rho(h)
    return p:evaluate(h)
end

-- 悬停填充量: 浮力与气压成正比，因此所需填充量与气压成反比
local function hover_fill(h)
    local density = rho(h)
    if density <= 0 then
        return capacity
    end

    return fill0 * (rho(h0) / density)
end

-- PWM
local pwmTickCounter = 0

local function quantizeLevelWithPWM(level)
    local clamped = math.max(0, math.min(15, level))
    local lower = math.floor(clamped)
    local upper = math.ceil(clamped)

    if lower == upper then
        return lower, clamped
    end

    local fraction = clamped - lower
    local upperTicks = math.floor(fraction * pwmWindowTicks + 0.5)

    pwmTickCounter = (pwmTickCounter + 1) % pwmWindowTicks

    if pwmTickCounter < upperTicks then
        return upper, clamped
    end

    return lower, clamped
end

local function setBalloonFillTarget(fillTarget)
    local desiredLevel = fillTarget / maxSteamOutput * 15
    local level, exactLevel = quantizeLevelWithPWM(desiredLevel)
    relay.setAnalogOutput("left", level)
    return level, exactLevel
end

local function waitForTimer(timerId)
    while true do
        local event, firedTimerId = os.pullEvent("timer")
        if event == "timer" and firedTimerId == timerId then
            return
        end
    end
end

-- os.startTimer(0.05)的实际dt是0.1而不是0.05
local dt = 0.1
local last_h = altimeter.getHeight()
local integral = 0.0

while true do
    local timerId = os.startTimer(0.05)
    waitForTimer(timerId)

    if relay.getInput("front") then
        target = target + targetStep
    end

    if relay.getInput("back") then
        target = target - targetStep
    end

    if monitor then
        monitor.setCursorPos(1, 1)
        monitor.clearLine()
        monitor.write(string.format("Target: %.2f", target))
    end


    local h = altimeter.getHeight()
    local v = (h - last_h) / dt
    last_h = h

    local error = target - h

    local base = hover_fill(target)

    -- 热气球自身已经有明显惯性，先使用 PD 避免积分累积导致超调
    integral = integral + error * dt

    -- 限制积分项
    integral = math.max(-50, math.min(50, integral))

    local control = Kp * error + Ki * integral - Kd * v

    -- 限制控制输出
    control = math.max(-capacity, math.min(capacity, control))

    local desiredFill = math.max(0, math.min(capacity, base + control))
    local level, desiredLevel = setBalloonFillTarget(desiredFill)

    print(string.format(
        "H=%.2f T=%.2f b=%.2f c=%.2f f=%.2f l=%d dl=%.2f",
        h, target, base, control, desiredFill, level, desiredLevel
    ))

    if monitor then
        monitor.setCursorPos(1, 2)
        monitor.clearLine()
        monitor.write(string.format("Fill: %.2f", desiredFill))
        monitor.setCursorPos(1, 3)
        monitor.clearLine()
        monitor.write(string.format("Level: %d (%.2f)", level, desiredLevel))
    end
end
