// ============================================================================
// EventRecurrenceLogic.js — 青云志愿服务队 · 活动日期与重复规则引擎
//
// 纯 JavaScript 共享模块（.pragma library），供所有 QML 视图通过
//   import "js/EventRecurrenceLogic.js" as EventLogic
// 引入使用。无 Qt 依赖，可独立单测。
//
// 核心职责：
//   1. 日期格式化与解析
//   2. 星期几 / 教学周 计算
//   3. 重复规则展开：单次 / 每周 / 每两周 → EventInstance[]
//   4. 日历网格辅助（某月有多少天、第一天星期几）
// ============================================================================
.pragma library

// ---- 重复类型常量 ----
var RECUR_ONCE     = "once"
var RECUR_WEEKLY   = "weekly"
var RECUR_BIWEEKLY = "biweekly"

// ---- 星期中文 ----
var DAY_LABELS = ["", "周一","周二","周三","周四","周五","周六","周日"]

// ============================================================================
// 基础工具
// ============================================================================

// Date → "YYYY-MM-DD"
function formatDate(d) {
    if (!d || !(d instanceof Date) || isNaN(d.getTime())) return ""
    var y = d.getFullYear()
    var m = d.getMonth() + 1
    var day = d.getDate()
    return y + "-" + (m < 10 ? "0" + m : m) + "-" + (day < 10 ? "0" + day : day)
}

// 年/月/日 → Date（month 是 1-12 的人类自然月）
function makeDate(year, month, day) {
    return new Date(year, month - 1, day)
}

// "YYYY-MM-DD" → Date (local time)
function parseDate(str) {
    if (!str) return new Date(NaN)
    var parts = str.split("-")
    if (parts.length !== 3) return new Date(NaN)
    return new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]))
}

// Date → 星期几 (1=周一, 7=周日)
function dayOfWeek(d) {
    var jsDay = d.getDay()  // 0=Sun
    return jsDay === 0 ? 7 : jsDay
}

// 时分 → "HH:MM:SS"
function formatTime(h, m) {
    return (h < 10 ? "0" + h : h) + ":" + (m < 10 ? "0" + m : m) + ":00"
}

// 计算时间差（小时）
function durationHours(startH, startM, endH, endM) {
    var s = startH + startM / 60.0
    var e = endH + endM / 60.0
    return e > s ? e - s : 0
}

// ============================================================================
// 教学周计算
// ============================================================================

// 根据开学日期计算 targetDate 所在的 teaching week (1-based)
// 开学第一周 = week 1
function teachingWeek(targetDate, termStartDate) {
    if (!targetDate || !termStartDate) return 1
    var t = targetDate instanceof Date ? targetDate : parseDate(targetDate)
    var s = termStartDate instanceof Date ? termStartDate : parseDate(termStartDate)
    if (isNaN(t.getTime()) || isNaN(s.getTime())) return 1
    var diffDays = Math.floor((t.getTime() - s.getTime()) / 86400000)
    return Math.floor(diffDays / 7) + 1
}

// ============================================================================
// 日历网格辅助
// ============================================================================

// 某年某月有多少天
function daysInMonth(year, month) {
    // month: 1-12
    return new Date(year, month, 0).getDate()
}

// 某年某月第一天是星期几 (1=Mon, 7=Sun)
function firstDayOfMonth(year, month) {
    return dayOfWeek(new Date(year, month - 1, 1))
}

// 生成某月的日历网格（6行 × 7列）
// 返回 [{day: int, date: Date, isCurrentMonth: bool}, ...] 共 42 项
function buildCalendarGrid(year, month) {
    var firstDow = firstDayOfMonth(year, month)
    var totalDays = daysInMonth(year, month)
    var grid = []

    // 上月填充（firstDow=1表示周一，前面没有上月日期）
    var prevMonth = month === 1 ? 12 : month - 1
    var prevYear = month === 1 ? year - 1 : year
    var prevDays = daysInMonth(prevYear, prevMonth)
    for (var i = firstDow - 2; i >= 0; i--) {
        grid.push({
            day: prevDays - i,
            date: new Date(prevYear, prevMonth - 1, prevDays - i),
            isCurrentMonth: false
        })
    }

    // 当月
    for (var d = 1; d <= totalDays; d++) {
        grid.push({
            day: d,
            date: new Date(year, month - 1, d),
            isCurrentMonth: true
        })
    }

    // 下月填充至 42 格
    var remaining = 42 - grid.length
    var nextMonth = month === 12 ? 1 : month + 1
    var nextYear = month === 12 ? year + 1 : year
    for (var nd = 1; nd <= remaining; nd++) {
        grid.push({
            day: nd,
            date: new Date(nextYear, nextMonth - 1, nd),
            isCurrentMonth: false
        })
    }

    return grid
}

// ============================================================================
// 重复规则展开引擎
// ============================================================================

// 根据重复规则生成所有 EventInstance
//   startDate: Date   — 活动首次日期
//   endDate:   Date   — 重复截止日期（once 时与 startDate 相同）
//   startH, startM: int — 开始时间 (时, 分)
//   endH,   endM:   int — 结束时间 (时, 分)
//   recurrence: string — "once" | "weekly" | "biweekly"
//
// 返回：[{ date: "YYYY-MM-DD", day_of_week: int, start_time: "HH:MM:SS", end_time: "HH:MM:SS" }, ...]
function generateInstances(startDate, endDate, startH, startM, endH, endM, recurrence) {
    var instances = []
    var startTime = formatTime(startH, startM)
    var endTime = formatTime(endH, endM)
    var dur = durationHours(startH, startM, endH, endM)

    if (!startDate || isNaN(startDate.getTime())) return instances
    if (dur <= 0) return instances

    var step = 0
    switch (recurrence) {
        case RECUR_ONCE:     step = 0; break
        case RECUR_WEEKLY:   step = 7; break
        case RECUR_BIWEEKLY: step = 14; break
        default:             step = 0; break
    }

    var cursor = new Date(startDate.getTime())
    var stop = endDate instanceof Date && !isNaN(endDate.getTime())
               ? new Date(endDate.getTime())
               : new Date(startDate.getTime())

    // 重置 stop 到当天 23:59:59 以确保包含当天
    stop.setHours(23, 59, 59, 999)

    while (cursor <= stop) {
        instances.push({
            date:        formatDate(cursor),
            day_of_week: dayOfWeek(cursor),
            start_time:  startTime,
            end_time:    endTime,
            duration_h:  dur
        })

        if (step === 0) break
        cursor.setDate(cursor.getDate() + step)
    }

    return instances
}

// ============================================================================
// 为排班/筛选视图提供的单日期工具
// ============================================================================

// 构建单个时间槽描述对象
function buildTimeSlot(date, startH, startM, endH, endM) {
    return {
        date:        formatDate(date),
        day_of_week: dayOfWeek(date),
        start_time:  formatTime(startH, startM),
        end_time:    formatTime(endH, endM)
    }
}

// 检查两个 Date 是否是同一天
function isSameDay(a, b) {
    if (!a || !b) return false
    return a.getFullYear() === b.getFullYear()
        && a.getMonth() === b.getMonth()
        && a.getDate() === b.getDate()
}

// ============================================================================
// 后端协议兼容工具：time_mask / teaching week 计算
// ============================================================================

// 学期开学第一天（学期周一），与后端 sys_config.term_start_date 保持同步
var TERM_START_DATE = "2026-03-02"

// 映射重复类型到后端 period_type 整数
function periodType(recurrence) {
    switch (recurrence) {
        case RECUR_ONCE:     return 0
        case RECUR_WEEKLY:   return 1
        case RECUR_BIWEEKLY: return 2
        default:             return 0
    }
}

// 计算 15-bit hour mask（与后端 TimeConverter::calculateHourMask 完全一致）
// 位定义：bit 0 = 7:00-8:00, bit 14 = 21:00-22:00
// 算法：区间交集判断 —— 活动时间与每个整点档位是否有重叠
function calculateTimeMask(startHour, startMin, endHour, endMin) {
    var mask = 0
    var actStart = startHour + startMin / 60.0
    var actEnd   = endHour   + endMin   / 60.0
    for (var i = 0; i < 15; i++) {
        var slotStart = 7 + i
        var slotEnd   = slotStart + 1
        if (actStart < slotEnd && actEnd > slotStart) {
            mask |= (1 << i)
        }
    }
    return mask
}
