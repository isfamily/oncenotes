import SwiftUI

// MARK: - 日历便签视图
// 月历: 6 周网格 (周日起始), 可翻月, 带农历/节日。
// 全部离线现算 (系统 Gregorian/Chinese 历法), 不依赖网络。

struct CalendarNoteView: View {
    @ObservedObject var note: Note
    /// 显示的锚点日期。@State 不持久化 —— 每次窗口重建自动回到今天,
    /// 翻月只是临时回看, 不写进便签数据。
    @State private var anchor: Date = .now
    /// 日期标注弹窗状态: 正在编辑哪一天 + 输入框文字
    @State private var markEditingDay: Date?
    @State private var markEditingText = ""
    @FocusState private var markFieldFocused: Bool

    private var accent: Color { Color(nsColor: note.theme.accent) }
    private var ink: Color { Color(nsColor: note.theme.text) }

    private var greg: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 1   // 周日起始
        c.locale = Locale(identifier: "zh_CN")
        return c
    }

    // MARK: 月历

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月"
        return f.string(from: anchor)
    }

    private var monthGrid: [[Date?]] {
        let cal = greg
        guard let first = cal.date(from: DateComponents(
            year: cal.component(.year, from: anchor),
            month: cal.component(.month, from: anchor), day: 1)) else { return [] }
        let firstWeekday = cal.component(.weekday, from: first)
        // 网格第 0 格对应的日期 (周日)
        guard let gridStart = cal.date(byAdding: .day,
                                       value: -(firstWeekday - 1), to: first) else { return [] }
        var rows: [[Date?]] = []
        var cur = gridStart
        for _ in 0..<6 {
            var row: [Date?] = []
            for _ in 0..<7 {
                row.append(cur)
                cur = cal.date(byAdding: .day, value: 1, to: cur) ?? cur
            }
            rows.append(row)
        }
        return rows
    }

    // MARK: 内容

    var body: some View {
        // 跨天时自动刷新 (今天高亮跟着挪); 用 Timer 驱动, 零依赖
        TimelineView(.periodic(from: .now, by: 3600)) { _ in
            monthView
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        // 标注输入弹窗: 浮在日历正下方
        .overlay(alignment: .top) {
            if markEditingDay != nil {
                markSheet
                    .offset(y: 30)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.18), value: markEditingDay != nil)
    }

    private var monthView: some View {
        VStack(spacing: 6) {
            navRow(title: monthTitle,
                   onPrev: { step(month: -1) },
                   onNext: { step(month: 1) })
            // 星期表头 (周日在最左)
            HStack(spacing: 4) {
                ForEach(weekdayLabels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ink.opacity(0.55))
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(monthGrid.indices, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(Array(monthGrid[row].enumerated()), id: \.offset) { _, day in
                        monthCell(day)
                    }
                }
            }
        }
    }

    private func navRow(title: String, onPrev: @escaping () -> Void,
                        onNext: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: onPrev) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ink.opacity(0.5))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(ink.opacity(0.06)))
            }.buttonStyle(.plain)

            Text(title)
                .font(.system(size: 15, weight: .bold, design: .serif))
                .foregroundStyle(ink)
                .fixedSize()

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ink.opacity(0.5))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(ink.opacity(0.06)))
            }.buttonStyle(.plain)

            Spacer()
        }
        .frame(height: 24)
    }

    private func monthCell(_ day: Date?) -> some View {
        Group {
            if let day, isCurrentMonth(day) {
                dayCell(day, compact: true)
            } else if let day {
                // 上/下月补位: 灰字, 不显示农历
                Text("\(greg.component(.day, from: day))")
                    .font(.system(size: 11))
                    .foregroundStyle(ink.opacity(0.18))
                    .frame(maxWidth: .infinity, minHeight: 40)
            } else {
                Color.clear.frame(minHeight: 40)
            }
        }
    }

    /// 一个日期格: 大号数字 + 小字 (标注 > 节日 > 农历)。
    /// 右键格子可添加/修改/清除日期标注。
    @ViewBuilder
    private func dayCell(_ day: Date, compact: Bool) -> some View {
        let isToday = greg.isDate(day, inSameDayAs: .now)
        let holiday = Holiday.name(for: day)
        let lunar = Holiday.lunarLabel(for: day)
        let isWeekend = greg.component(.weekday, from: day) >= 6
        let mark = note.dateMark(on: day)

        VStack(spacing: 2) {
            Text("\(greg.component(.day, from: day))")
                .font(.system(size: 13,
                              weight: isToday ? .bold : .semibold, design: .rounded))
                .foregroundStyle(isToday ? accent : (isWeekend ? accent.opacity(0.65) : ink))

            // 小字优先级: 标注 > 节日 > 农历。标注用强调色, 节日彩色, 农历灰字
            if let mark {
                Text(mark)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(mark)
            } else if let holiday {
                Text(holiday)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(accent)
                    .lineLimit(1)
            } else {
                Text(lunar)
                    .font(.system(size: 8))
                    .foregroundStyle(ink.opacity(0.42))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 40)
        .background {
            if isToday {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(accent.opacity(0.13))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(accent.opacity(0.5), lineWidth: 1)
                    }
            }
        }
        // 右键菜单: 标注 / 清除
        .contextMenu {
            Button(mark == nil ? "添加标注" : "修改标注") {
                startEditMark(for: day)
            }
            if mark != nil {
                Divider()
                Button("清除标注", role: .destructive) {
                    note.clearDateMark(on: day)
                }
            }
        }
    }

    private func dayString(_ day: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M/d"
        return f.string(from: day)
    }

    /// 弹出标注输入弹窗
    private func startEditMark(for day: Date) {
        markEditingDay = day
        markEditingText = note.dateMark(on: day) ?? ""
        DispatchQueue.main.async { markFieldFocused = true }
    }

    /// 标注输入弹窗 (浮在日历格子上的小卡片)
    private var markSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let day = markEditingDay {
                Text("\(dayString(day)) 标注")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ink)
            }
            TextField("输入重要信息…", text: $markEditingText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(ink)
                .focused($markFieldFocused)
                .onSubmit {
                    if let day = markEditingDay {
                        note.setDateMark(markEditingText, on: day)
                    }
                    markEditingDay = nil
                    markFieldFocused = false
                }
            HStack {
                Spacer()
                Button("取消") {
                    markEditingDay = nil
                    markFieldFocused = false
                }
                .font(.system(size: 11))
                .foregroundStyle(ink.opacity(0.5))
                Button("保存") {
                    if let day = markEditingDay {
                        note.setDateMark(markEditingText, on: day)
                    }
                    markEditingDay = nil
                    markFieldFocused = false
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .disabled(markEditingText.trimmingCharacters(in: .whitespaces).isEmpty)
                .background(RoundedRectangle(cornerRadius: 5).fill(accent))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 180)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
        }
    }

    private func isCurrentMonth(_ day: Date) -> Bool {
        greg.component(.month, from: day) == greg.component(.month, from: anchor)
            && greg.component(.year, from: day) == greg.component(.year, from: anchor)
    }

    private func step(month: Int) {
        withAnimation(.easeInOut(duration: 0.18)) {
            anchor = greg.date(byAdding: .month, value: month, to: anchor) ?? anchor
        }
    }

    private func step(days: Int) {
        withAnimation(.easeInOut(duration: 0.18)) {
            anchor = greg.date(byAdding: .day, value: days, to: anchor) ?? anchor
        }
    }
}
