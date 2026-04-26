-- crystal.lua

-- === 参数设置 ===

-- 目标数量  Certus石英水晶，粉末，充能水晶
local FINAL_CRYSTAL_TARGET = 100000 + 1024
local FINAL_DUST_TARGET = 200000
local FINAL_CHARGED_TARGET = 100000
-- Fluix水晶  Fluix粉末
local FINAL_FLUIX_TARGET = 10000
local FINAL_FLUIX_DUST_TARGET = 50000
-- Entro水晶  Entro粉末
local FINAL_ENTRO_TARGET = 10000
local FINAL_ENTRO_DUST_TARGET = 10000

-- 控制参数
local RATIO_LIMIT = 1.25          -- 充能/粉 粉/充能 的最大比例 超过则不运行充能/粉合成
local POLLING_INTERVAL = 5        -- 循环间隔（秒）
local KEEP_RUNNING = true         -- 开启持续运行模式
local KEEP_RUNNING_POLL_RATE = 30 -- 目标达成后多久检查一次库存（秒）

-- 批次倍数 需要是样板产物数量的正整数倍
local BATCH_SIZES = {
    crystal = 64,
    charged = 128,
    dust = 128,
    f_crystal = 64,
    f_dust = 64,
    e_crystal = 64,
    e_dust = 64
}

-- 单次最大合成请求数量（会向下取整到BATCH_SIZES的倍数）
-- 确保CPU存储容量足够大
local MAX_BATCH = {
    crystal = 4096,
    charged = 4096,
    dust = 4096,
    f_crystal = 4096,
    f_dust = 4096,
    e_crystal = 4096,
    e_dust = 4096
}

-- === 获取外设 ===
local ME = peripheral.find("me_bridge")
local monitor = peripheral.find("monitor")

if not ME then
    error("No ME Bridge found! Please connect one.")
end
if not monitor then
    error("No Monitor found! Please connect one.")
end


-- 物品定义
local ITEMS = {
    crystal = "ae2:certus_quartz_crystal",
    charged = "ae2:charged_certus_quartz_crystal",
    dust = "ae2:certus_quartz_dust",
    f_crystal = "ae2:fluix_crystal",
    f_dust = "ae2:fluix_dust",
    e_crystal = "extendedae:entro_crystal",
    e_dust = "extendedae:entro_dust"
}

local ITEM_ORDER = {
    "crystal",
    "charged",
    "dust",
    "f_crystal",
    "f_dust",
    "e_crystal",
    "e_dust"
}


-- 如果组内任何物品正在合成则不会提交组内任何物品新的合成请求
local ITEM_TO_GROUP = {
    crystal = "reaction",
    charged = nil,
    dust = "crush",
    f_crystal = "reaction",
    f_dust = "crush",
    e_crystal = "reaction",
    e_dust = "crush"
}

local GROUP_TO_ITEMS = {}
for item, group in pairs(ITEM_TO_GROUP) do
    if group then
        GROUP_TO_ITEMS[group] = GROUP_TO_ITEMS[group] or {}
        table.insert(GROUP_TO_ITEMS[group], item)
    end
end

-- === 显示器输出 ===

monitor.setTextScale(0.5)
local w, h = monitor.getSize()
local maxLines = h
local logLines = {}
local logColors = {}

--- 将消息记录到显示器（从下往上滚动）
local function log(msg, color)
    print(msg)
    color = color or colors.white
    local timestamp = string.format("[%s] ", os.date("%H:%M:%S"))
    local line = timestamp .. msg
    table.insert(logLines, line)
    table.insert(logColors, color)
    while #logLines > maxLines do
        table.remove(logLines, 1)
        table.remove(logColors, 1)
    end
    monitor.clear()
    for i = 1, #logLines do
        monitor.setCursorPos(1, i)
        monitor.setTextColor(logColors[i])
        monitor.write(logLines[i]:sub(1, w))
    end
    monitor.setTextColor(colors.white)
end


-- === 辅助函数 ===

--- 将数量向下取整到最近的批次大小
local function floorBatch(amount, batchSize)
    if not amount or not batchSize or batchSize == 0 then return 0 end
    return math.floor(amount / batchSize) * batchSize
end

--- 检查 AE 系统当前是否正在合成某物品
local function isCrafting(itemName)
    return ME.isCrafting({ name = itemName })
end

--- 安全提交合成请求
local function safeCraft(item_key, desired_amount, color)
    local item_name = ITEMS[item_key]
    local batch_size = BATCH_SIZES[item_key]
    local max_batch = MAX_BATCH[item_key]
    local group_name = ITEM_TO_GROUP[item_key]

    -- 检查是否已有合成在进行中（包括同组物品）
    if isCrafting(item_name) then
        log(string.format("Skip: %s is still crafting...", item_name), colors.red)
        return
    elseif group_name then
        local conflict_group = GROUP_TO_ITEMS[group_name]
        if conflict_group then
            for _, conflict_key in ipairs(conflict_group) do
                if isCrafting(ITEMS[conflict_key]) then
                    log(
                        string.format("Skip: Machine group '%s' is busy with %s, cannot craft %s.", group_name,
                            conflict_key,
                            item_key), colors.red)
                    return
                end
            end
        end
    end

    -- 计算实际合成数量 向下取整
    local capped_amount = math.min(desired_amount, max_batch)
    local craft_amount = floorBatch(capped_amount, batch_size)
    if craft_amount > 0 then
        log(string.format("Task: Crafting %d %s", craft_amount, item_name), color)
        ME.craftItem({ name = item_name, count = craft_amount })
    end
end


--- 带向上取整的安全合成
local function craftWithRounding(item, need, available, color)
    if need <= 0 then return end
    -- 实际合成数量是可合成数量/需求数量的最小值
    local amount_to_craft = math.min(need, available)
    local batch_size = BATCH_SIZES[item]
    if amount_to_craft > 0 and amount_to_craft < batch_size then
        log(string.format("Rounding up final %s batch from %d to %d", item, amount_to_craft, batch_size), colors.yellow)
        amount_to_craft = batch_size
    end
    safeCraft(item, amount_to_craft, color)
end


--- 获取当前物品的库存
local function getInventory()
    local counts = {}
    for i, key in ipairs(ITEM_ORDER) do
        local item = ME.getItem({ name = ITEMS[key] })
        counts[i] = item and item.count or 0
    end
    return table.unpack(counts)
end

local function waitingLog(seconds, msg)
    log(string.format("--- Waiting %d seconds (%s) ---", seconds, msg), colors.gray)
    sleep(seconds)
end


-- === 状态判定逻辑 ===

--- 根据当前库存确定状态
local function determineState(c, cc, d, f, fd, e, ed, dynamic_charged_target, dynamic_fluix_target, growth_target,
                              consolidation_trigger)
    -- 检查是否已达成最终目标
    if c >= FINAL_CRYSTAL_TARGET and cc >= FINAL_CHARGED_TARGET and d >= FINAL_DUST_TARGET and
        f >= FINAL_FLUIX_TARGET and fd >= FINAL_FLUIX_DUST_TARGET and
        e >= FINAL_ENTRO_TARGET and ed >= FINAL_ENTRO_DUST_TARGET then
        return "done"
    end

    -- 1. 如果Certus石英水晶目标未达成，则进入Certus增长/合成/平衡阶段
    local certus_target_met = cc >= dynamic_charged_target and d >= FINAL_DUST_TARGET and c >= FINAL_CRYSTAL_TARGET
    if not certus_target_met then
        -- 检查是否拥有足够资源完成最终平衡（最高优先级检查）
        local need_charged = math.max(0, dynamic_charged_target - cc)
        local need_dust = math.max(0, FINAL_DUST_TARGET - d)
        local crystal_needed_for_balance = need_charged + need_dust
        if (c - crystal_needed_for_balance) >= FINAL_CRYSTAL_TARGET then
            log("State Logic: Sufficient resources to complete final targets. State: balance", colors.cyan)
            return "balance"
        end
        -- 检查是否达到增长目标
        if c >= growth_target then
            log("State Logic: Growth target met. State: balance", colors.cyan)
            return "balance"
        end
        -- 检查是否需要合成水晶
        if math.min(cc, d) >= consolidation_trigger then
            log("State Logic: Buffers full. State: consolidate", colors.blue)
            return "consolidate"
        end
        -- 默认进入增长阶段
        log("State Logic: Default to growth phase. State: growth", colors.green)
        return "growth"
    end

    -- 2. Certus水晶目标达成后进入Fluix生产阶段
    local fluix_target_met = f >= dynamic_fluix_target and fd >= FINAL_FLUIX_DUST_TARGET
    if not fluix_target_met then
        log("State Logic: Proceeding to Fluix production. State: produce_fluix", colors.purple)
        return "produce_fluix"
    end

    -- 3. Fluix水晶目标达成后进入Entro生产阶段
    local entro_target_met = e >= FINAL_ENTRO_TARGET and ed >= FINAL_ENTRO_DUST_TARGET
    if certus_target_met and fluix_target_met and not entro_target_met then
        log("State Logic: Proceeding to Entro production. State: produce_entro", colors.lime)
        return "produce_entro"
    end


    -- 默认返回
    return "unknown"
end


-- === 阶段 1：增长Certus水晶 ===
-- 所有充能/粉都用于合成水晶，所有水晶50%合成充能水晶，50%合成粉
local function runGrowth(c, cc, d)
    log("--- Phase 1: Growth ---", colors.green)

    -- 比例检查 比例过大则不允许合成充能水晶或粉
    -- 防止合成充能/粉的速度不同导致库存只剩充能/粉
    local can_charge = false
    local can_crush = false
    if d == 0 and cc == 0 then
        can_charge = true
        can_crush = true
        log("Status: Startup phase (cc=0, d=0)", colors.yellow)
    elseif d == 0 then
        can_crush = true
        log(string.format("Ratio: Pausing Charged (Dust=0, Ratio=%.2f)", (cc / (d + 1))), colors.orange)
    elseif cc == 0 then
        can_charge = true
        log(string.format("Ratio: Pausing Dust (Charged=0, Ratio=%.2f)", (d / (cc + 1))), colors.orange)
    else
        local ratio_cc_d = cc / d
        local ratio_d_cc = d / cc
        if ratio_cc_d <= RATIO_LIMIT then
            can_charge = true
        else
            log(string.format("Ratio: Pausing Charged (Ratio=%.2f > %.1f)", ratio_cc_d, RATIO_LIMIT), colors.orange)
        end
        if ratio_d_cc <= RATIO_LIMIT then
            can_crush = true
        else
            log(string.format("Ratio: Pausing Dust (Ratio=%.2f > %.1f)", ratio_d_cc, RATIO_LIMIT), colors.orange)
        end
    end

    -- 计算计划合成数量
    local amount_to_charge = math.floor(c * 0.5)
    local amount_to_crush = math.floor(c * 0.5)
    local amount_to_crystal = math.min(cc, d) * 4

    -- 执行合成
    if can_charge then
        safeCraft("charged", amount_to_charge, colors.lightBlue)
    end
    if can_crush then
        safeCraft("dust", amount_to_crush, colors.brown)
    end
    safeCraft("crystal", amount_to_crystal, colors.pink)
end

-- === 阶段 1.5：合成水晶阶段 ===
-- 阶段1中如果合成水晶的速度<合成充能/粉的速度，则库存水晶数量约为0
-- 而充能/粉数量足够完成水晶的growth_target则进入该阶段
local function runConsolidation(c, cc, d)
    log("--- Phase 1.5: Consolidation ---", colors.blue)

    -- 只合成水晶
    local amount_to_crystal = math.min(cc, d) * 4
    safeCraft("crystal", amount_to_crystal, colors.pink)
end

-- === 阶段 2：库存平衡 ===
-- 阶段1中如果合成水晶的速度>合成充能/粉的速度
-- 则水晶水晶数量足够后开始合成充能/粉以达到最终目标
local function runBalancing(c, cc, d, dynamic_charged_target)
    log("--- Phase 2: Inventory Balancing ---", colors.cyan)

    local need_charged = dynamic_charged_target - cc
    local need_dust = FINAL_DUST_TARGET - d

    log(string.format("Balancing: Need Charged=%d, Need Dust=%d", need_charged, need_dust), colors.yellow)

    craftWithRounding("charged", need_charged, need_charged, colors.lightBlue)
    craftWithRounding("dust", need_dust, need_dust, colors.brown)
end

-- === 阶段 3：Fluix水晶生产 ===
-- Certus生产完毕后开始生产Fluix水晶和粉末
local function runFluixProduction(f, fd, dynamic_fluix_target)
    log("--- Phase 3: Fluix Production ---", colors.purple)

    -- 所需要的Fluix粉末/水晶和数量
    local need_f_dust = FINAL_FLUIX_DUST_TARGET - fd
    local need_f_crystal = dynamic_fluix_target - f
    -- 可合成的Fluix粉末/水晶数量
    local amount_to_f_crush = f
    local amount_to_f_crystal = fd * 2

    craftWithRounding("f_dust", need_f_dust, amount_to_f_crush, colors.magenta)
    craftWithRounding("f_crystal", need_f_crystal, amount_to_f_crystal, colors.purple)
end

-- === 阶段 4：Entro水晶生产 ===
-- Fluix生产完毕后开始生产Entro水晶和粉末
local function runEntroProduction(e, ed)
    log("--- Phase 4: Entro Production ---", colors.lime)

    -- 所需要的Entro粉末/水晶和数量
    local need_e_dust = FINAL_ENTRO_DUST_TARGET - ed
    local need_e_crystal = FINAL_ENTRO_TARGET - e
    -- 可合成的Entro粉末/水晶数量
    local amount_to_e_crush = e
    local amount_to_e_crystal = ed * 2

    craftWithRounding("e_dust", need_e_dust, amount_to_e_crush, colors.green)
    craftWithRounding("e_crystal", need_e_crystal, amount_to_e_crystal, colors.lime)
end

-- === 主程序 ===
log("================================", colors.white)
log(" Starting Crystal Automation", colors.white)
log(string.format("Keep Running Mode: %s", tostring(KEEP_RUNNING)), colors.white)
log("================================", colors.white)


-- 主循环
while true do
    -- 1. 在每次循环开始时获取一次最新库存
    local c, cc, d, f, fd, e, ed = getInventory()
    log(string.format("Inventory: Crystal=%d, Charged=%d, Dust=%d", c, cc, d), colors.white)
    log(string.format("Inventory: Fluix=%d, Dust=%d, Entro=%d, Dust=%d", f, fd, e, ed), colors.white)

    -- 2. 计算目标

    -- 计算缺少的Entro水晶和粉末数量，需要的Fluix水晶数量和缺少的Entro数量为1:1
    local fluix_for_entro = math.max(0, FINAL_ENTRO_TARGET - e) + math.max(0, FINAL_ENTRO_DUST_TARGET - ed)
    -- 计算缺少的Fluix水晶和粉末数量，需要的充能水晶数量和缺少的Fluix数量为1:1
    local needed_f_total = math.max(0, FINAL_FLUIX_TARGET - f) + math.max(0, FINAL_FLUIX_DUST_TARGET - fd)
    -- 求和得出需要的充能水晶总量 (1充能->1Fluix, 1Fluix->1Entro)
    local needed_charged_total = needed_f_total + fluix_for_entro

    -- 计算出本次循环的最终充能水晶目标和Fluix水晶目标
    local dynamic_charged_target = FINAL_CHARGED_TARGET + needed_charged_total
    local dynamic_fluix_target = FINAL_FLUIX_TARGET + fluix_for_entro

    -- 更新Certus阶段的阈值
    -- growth_target是所有物品需要的水晶总和
    local growth_target = FINAL_CRYSTAL_TARGET + FINAL_DUST_TARGET + dynamic_charged_target
    -- 25%充能水晶+25%的粉末即可合成100%水晶
    local consolidation_trigger = math.max(0, math.floor((growth_target - c) * 0.26))

    log(string.format("Growth Target: %d (Consolidation Trigger: %d)", growth_target, consolidation_trigger),
        colors.lightGray)
    log(string.format("Dynamic Needs: Charged for Fluix=%d, Fluix for Entro=%d", needed_charged_total, fluix_for_entro),
        colors.lightGray)
    log(string.format("Dynamic Targets: Charged=%d, Fluix=%d", dynamic_charged_target, dynamic_fluix_target),
        colors.lightGray)

    -- 3. 根据当前状态决定操作
    local state = determineState(c, cc, d, f, fd, e, ed, dynamic_charged_target, dynamic_fluix_target, growth_target,
        consolidation_trigger)

    local state_actions = {
        growth = function()
            runGrowth(c, cc, d)
        end,

        consolidate = function()
            runConsolidation(c, cc, d)
        end,

        balance = function()
            runBalancing(c, cc, d, dynamic_charged_target)
        end,

        produce_fluix = function()
            runFluixProduction(f, fd, dynamic_fluix_target)
        end,

        produce_entro = function()
            runEntroProduction(e, ed)
        end,

        done = function()
            log("======= All Tasks Complete =======", colors.green)
            if KEEP_RUNNING then
                log(string.format("Entering maintenance mode. Re-checking in %d seconds.", KEEP_RUNNING_POLL_RATE),
                    colors.gray)
                sleep(KEEP_RUNNING_POLL_RATE)
            else
                return true
            end
        end
    }

    -- 4. 执行该状态对应的操作
    local action = state_actions[state]
    if action then
        local exit_loop = action()
        if exit_loop then
            break
        end
        if state ~= "done" then
            waitingLog(POLLING_INTERVAL, state)
        end
    else
        log(string.format("======= Script Aborted in Unknown State (%s) =======", tostring(state)), colors.red)
        break
    end
end

log("Script finished.", colors.gray)
