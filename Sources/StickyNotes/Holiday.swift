import Foundation

/// 节假日/农历标注。全部离线现算, 不依赖任何网络或额外数据源:
/// - 农历节日: 用系统 Chinese 历法查每月的节日 (春节/元宵/端午/七夕/重阳/腊八/除夕)
/// - 公历固定假日: 元旦/劳动节/国庆
enum Holiday {
    /// 农历月节日: (农历月, 农历日) -> 节日名
    private static let lunarFestivals: [(month: Int, day: Int, name: String)] = [
        (1, 1, "春节"), (1, 15, "元宵"), (5, 5, "端午"),
        (7, 7, "七夕"), (9, 9, "重阳"), (12, 8, "腊八"),
    ]

    private static let gregorianFestivals: [(month: Int, day: Int, name: String)] = [
        (1, 1, "元旦"), (5, 1, "劳动节"), (10, 1, "国庆"),
    ]

    private static let chinese = Calendar(identifier: .chinese)
    private static let gregorian = Calendar(identifier: .gregorian)

    /// 某天的节日名。优先级: 除夕 > 农历节日 > 公历固定假日
    static func name(for date: Date) -> String? {
        let m = chinese.component(.month, from: date)
        let d = chinese.component(.day, from: date)
        // 除夕: 农历腊月最后一天
        if m == 12, let next = chinese.date(byAdding: DateComponents(day: 1), to: date),
           chinese.component(.month, from: next) == 1,
           chinese.component(.day, from: next) == 1 {
            return "除夕"
        }
        if let f = lunarFestivals.first(where: { $0.month == m && $0.day == d }) {
            return f.name
        }
        let gm = gregorian.component(.month, from: date)
        let gd = gregorian.component(.day, from: date)
        return gregorianFestivals.first { $0.month == gm && $0.day == gd }?.name
    }

    /// 农历小字: 初一显示月名 (正月/二月...腊月), 其余显示日名 (十五/廿三...)
    static func lunarLabel(for date: Date) -> String {
        let m = chinese.component(.month, from: date)
        let d = chinese.component(.day, from: date)
        let monthNames = ["正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊"]
        let dayNames = ["初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
                        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
                        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"]
        if d == 1 { return monthNames[m - 1] + "月" }
        return dayNames[d - 1]
    }

    /// 某日是否为"大日子"(节日), 用于格子高亮判断
    static func isHoliday(_ date: Date) -> Bool {
        name(for: date) != nil
    }
}

/// 双字星期标题, 周日起始 (周日在最左)
let weekdayLabels = ["日", "一", "二", "三", "四", "五", "六"]
