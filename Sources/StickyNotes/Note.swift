import AppKit
import Combine

// MARK: - 颜色主题

/// 透明度约束 0.15~1.0
func clampOpacity(_ v: Double) -> Double { min(1, max(0.15, v)) }

enum NoteTheme: String, Codable, CaseIterable {
    case lemon, peach, sky

    var displayName: String {
        switch self {
        case .lemon: return "柠檬黄"
        case .peach: return "蜜桃粉"
        case .sky:   return "天空蓝"
        }
    }

    /// 便签主体背景色 (低饱和莫兰迪色, 叠在磨砂玻璃上)
    var background: NSColor {
        switch self {
        case .lemon: return NSColor(red: 0.97, green: 0.95, blue: 0.88, alpha: 1)
        case .peach: return NSColor(red: 0.98, green: 0.93, blue: 0.91, alpha: 1)
        case .sky:   return NSColor(red: 0.92, green: 0.94, blue: 0.97, alpha: 1)
        }
    }

    /// 顶栏轻微加深的颜色
    var bar: NSColor {
        switch self {
        case .lemon: return NSColor(red: 0.93, green: 0.89, blue: 0.76, alpha: 1)
        case .peach: return NSColor(red: 0.95, green: 0.85, blue: 0.82, alpha: 1)
        case .sky:   return NSColor(red: 0.83, green: 0.88, blue: 0.94, alpha: 1)
        }
    }

    /// 同色系强调色 (勾选框、引用条、选中态)
    var accent: NSColor {
        switch self {
        case .lemon: return NSColor(red: 0.71, green: 0.58, blue: 0.22, alpha: 1)
        case .peach: return NSColor(red: 0.80, green: 0.47, blue: 0.40, alpha: 1)
        case .sky:   return NSColor(red: 0.34, green: 0.53, blue: 0.74, alpha: 1)
        }
    }

    /// 针对每种便签底色挑选的对比荧光色。
    /// 高亮只保存文字范围，切换主题时会自动改用这里的新颜色。
    var highlighter: NSColor {
        switch self {
        case .lemon: return NSColor(red: 1.00, green: 0.38, blue: 0.30, alpha: 0.44) // 珊瑚红
        case .peach: return NSColor(red: 1.00, green: 0.72, blue: 0.08, alpha: 0.56) // 琥珀黄
        case .sky:   return NSColor(red: 0.55, green: 0.86, blue: 0.22, alpha: 0.48) // 青柠绿
        }
    }

    /// 正文文字颜色 (暖墨色, 深一点保证醒目)
    var text: NSColor {
        NSColor(red: 0.16, green: 0.15, blue: 0.13, alpha: 1)
    }
}

// MARK: - 窗口层级模式

enum NoteMode: String, Codable, CaseIterable {
    case floating   // 置顶悬浮
    case normal     // 普通窗口
    case desktop    // 贴在桌面

    var displayName: String {
        switch self {
        case .floating: return "置顶悬浮"
        case .normal:   return "普通窗口"
        case .desktop:  return "贴在桌面"
        }
    }

    var symbol: String {
        switch self {
        case .floating: return "pin.fill"
        case .normal:   return "macwindow"
        case .desktop:  return "square.grid.3x3.bottomright.filled"
        }
    }
}

// MARK: - 便签类型

enum NoteKind: String, Codable, CaseIterable {
    case text     // 纯文字便签
    case todo     // 待办事项便签
    case calendar // 日历便签 (周历/月历, 可贴桌面)

    var displayName: String {
        switch self {
        case .text:     return "文字便签"
        case .todo:     return "待办事项"
        case .calendar: return "日历"
        }
    }
}

/// 日历便签的显示单元
enum CalendarUnit: String, Codable {
    case week, month
}

// MARK: - 折叠条吸附边

enum SnapEdge: String, Codable {
    case left, right
}

/// 文字便签中的一段荧光标记。范围使用 UTF-16，与 NSTextView/NSRange 一致。
struct TextHighlight: Codable, Equatable {
    var location: Int
    var length: Int

    var range: NSRange { NSRange(location: location, length: length) }

    init(_ range: NSRange) {
        location = range.location
        length = range.length
    }
}

extension Array where Element == TextHighlight {
    /// 并入一段, 与已有高亮相接的自动合成一段
    func adding(_ range: NSRange) -> [TextHighlight] {
        guard range.length > 0 else { return self }
        var out: [NSRange] = []
        for r in (map(\.range) + [range]).sorted(by: { $0.location < $1.location }) where r.length > 0 {
            if let last = out.last, r.location <= NSMaxRange(last) {
                out[out.count - 1] = NSUnionRange(last, r)
            } else {
                out.append(r)
            }
        }
        return out.map(TextHighlight.init)
    }

    /// 挖掉一段, 被从中间穿过的高亮断成两截
    func removing(_ range: NSRange) -> [TextHighlight] {
        guard range.length > 0 else { return self }
        return flatMap { h -> [NSRange] in
            let overlap = NSIntersectionRange(h.range, range)
            guard overlap.length > 0 else { return [h.range] }
            var parts: [NSRange] = []
            if h.location < overlap.location {
                parts.append(NSRange(location: h.location, length: overlap.location - h.location))
            }
            if NSMaxRange(overlap) < NSMaxRange(h.range) {
                parts.append(NSRange(location: NSMaxRange(overlap),
                                     length: NSMaxRange(h.range) - NSMaxRange(overlap)))
            }
            return parts
        }.map(TextHighlight.init)
    }

    func covers(_ range: NSRange) -> Bool {
        contains { NSIntersectionRange($0.range, range).length > 0 }
    }

    /// 整段都落在同一段标记之内 (adding 合并相邻段, 全覆盖时必在单段里)
    func coversFully(_ range: NSRange) -> Bool {
        guard range.length > 0 else { return false }
        return contains { NSLocationInRange(range.location, $0.range)
            && NSMaxRange(range) <= NSMaxRange($0.range) }
    }

    /// 文字被替换后平移。落进替换区里的部分直接丢掉,
    /// 所以全选改写会让高亮自然清空, 不需要额外判断。
    func shifting(replacing old: NSRange, newLength: Int) -> [TextHighlight] {
        let delta = newLength - old.length
        let oldEnd = NSMaxRange(old)
        return flatMap { h -> [NSRange] in
            let r = h.range, hEnd = NSMaxRange(r)
            if hEnd <= old.location { return [r] }
            if r.location >= oldEnd { return [NSRange(location: r.location + delta, length: r.length)] }
            // 在高亮内部打字: 新字一并纳进这段高亮
            if old.length == 0 { return [NSRange(location: r.location, length: r.length + delta)] }
            var parts: [NSRange] = []
            if r.location < old.location {
                parts.append(NSRange(location: r.location, length: old.location - r.location))
            }
            if hEnd > oldEnd {
                parts.append(NSRange(location: oldEnd + delta, length: hEnd - oldEnd))
            }
            return parts
        }.map(TextHighlight.init)
    }
}

// MARK: - 便签模型

final class Note: ObservableObject, Identifiable, Codable {
    let id: UUID
    @Published var text: String
    @Published var theme: NoteTheme
    @Published var mode: NoteMode
    @Published var isPreview: Bool   // true = 渲染 Markdown, false = 编辑原文
    @Published var isCollapsed: Bool // true = 折叠成一行标题
    @Published var snappedEdge: SnapEdge?  // 折叠条吸附在屏幕哪条边
    @Published var highlights: [TextHighlight]
    @Published var bolds: [TextHighlight]
    /// 日历便签: 显示周历还是月历
    @Published var calendarUnit: CalendarUnit
    /// 窗口整体透明度 (0.15...1)。贴在桌面时调低更像一块通透的日历卡片。
    @Published var opacity: Double
    /// 待办便签: 每条待办的归属日期, 与 text 里的非空行按序一一对齐。
    /// nil = 未排期。周历筛选器按它归属显示。
    @Published var dueDates: [Date?]
    /// 日历便签: 按日期标注的重要信息。key = "yyyy-MM-dd", value = 标注文字。
    /// 右键某天格子 → 输入, 小字显示在格子内。完全离线, 随便签持久化。
    @Published var dateMarks: [String: String]
    /// 荧光笔模式。纯 UI 状态不进 Codable, 但要放在这里,
    /// 窗口层才能统一处理 Esc / ⌘⇧H (待办和预览没有 NSTextView 接管按键)。
    @Published var highlighterMode = false
    let kind: NoteKind
    var frame: CGRect
    var expandedFrame: CGRect        // 折叠前的尺寸, 展开时恢复

    init(id: UUID = UUID(),
         text: String = "",
         kind: NoteKind = .text,
         theme: NoteTheme = .lemon,
         mode: NoteMode = .floating,
         isPreview: Bool = false,
         isCollapsed: Bool = false,
         snappedEdge: SnapEdge? = nil,
         highlights: [TextHighlight] = [],
         bolds: [TextHighlight] = [],
         calendarUnit: CalendarUnit = .month,
         opacity: Double = 1,
         dueDates: [Date?] = [],
         dateMarks: [String: String] = [:],
         frame: CGRect = .zero,
         expandedFrame: CGRect? = nil) {
        self.id = id
        self.text = text
        self.kind = kind
        self.theme = theme
        self.mode = mode
        self.isPreview = isPreview
        self.isCollapsed = isCollapsed
        self.snappedEdge = snappedEdge
        self.highlights = highlights
        self.bolds = bolds
        self.calendarUnit = calendarUnit
        self.opacity = clampOpacity(opacity)
        self.dueDates = dueDates
        self.dateMarks = dateMarks
        self.frame = frame
        self.expandedFrame = expandedFrame ?? frame
    }

    /// 日历便签的折叠标题: "9月" 或 "9/14–9/20"
    var calendarTitle: String {
        let greg = Calendar(identifier: .gregorian)
        let now = Date()
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        switch calendarUnit {
        case .month:
            f.dateFormat = "M月"
            return f.string(from: now)
        case .week:
            let week = greg.dateInterval(of: .weekOfYear, for: now)!
            f.dateFormat = "M/d"
            let s = f.string(from: week.start)
            let e = f.string(from: week.end.addingTimeInterval(-1))
            return "\(s)–\(e)"
        }
    }

    /// 折叠时显示的标题: 文字便签取第一行非空内容, 去掉 Markdown 符号;
    /// 待办便签取第一个未完成任务并加进度, 全部完成时显示"全部完成"
    var title: String {
        if kind == .calendar { return calendarTitle }
        if kind == .todo {
            let items = todoItems
            if !items.isEmpty {
                let done = items.filter(\.done).count
                let current = items.first { !$0.done }?.text ?? "全部完成"
                return "\(done)/\(items.count) · \(current)"
            }
        }
        var first = ""
        for line in text.components(separatedBy: "\n") {
            var t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            for p in ["# ", "## ", "### ", "- [x] ", "- [X] ", "- [ ] ",
                      "[x] ", "[X] ", "[ ] ", "- ", "* ", "> "] {
                if t.hasPrefix(p) { t = String(t.dropFirst(p.count)); break }
            }
            if !t.isEmpty { first = t; break }
        }
        return first.isEmpty ? "空便签" : first
    }

    // Codable (手动实现, 因为 @Published 不能自动合成)
    enum CodingKeys: String, CodingKey {
        case id, text, kind, theme, mode, isPreview, isCollapsed, snap, highlights, bolds
        case calendarUnit, opacity, dueDates, dateMarks
        case x, y, w, h, ex, ey, ew, eh
    }

    convenience init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let frame = CGRect(
            x: try c.decodeIfPresent(Double.self, forKey: .x) ?? 0,
            y: try c.decodeIfPresent(Double.self, forKey: .y) ?? 0,
            width: try c.decodeIfPresent(Double.self, forKey: .w) ?? 280,
            height: try c.decodeIfPresent(Double.self, forKey: .h) ?? 280
        )
        var expanded: CGRect? = nil
        if let ew = try c.decodeIfPresent(Double.self, forKey: .ew),
           let eh = try c.decodeIfPresent(Double.self, forKey: .eh) {
            expanded = CGRect(
                x: try c.decodeIfPresent(Double.self, forKey: .ex) ?? frame.origin.x,
                y: try c.decodeIfPresent(Double.self, forKey: .ey) ?? frame.origin.y,
                width: ew, height: eh)
        }
        let text = try c.decode(String.self, forKey: .text)
        let textLength = (text as NSString).length
        func ranges(_ key: CodingKeys) throws -> [TextHighlight] {
            (try c.decodeIfPresent([TextHighlight].self, forKey: key) ?? [])
                .filter { $0.location >= 0 && $0.length > 0 && NSMaxRange($0.range) <= textLength }
        }
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            text: text,
            kind: try c.decodeIfPresent(NoteKind.self, forKey: .kind) ?? .text,
            theme: try c.decodeIfPresent(NoteTheme.self, forKey: .theme) ?? .lemon,
            mode: try c.decodeIfPresent(NoteMode.self, forKey: .mode) ?? .floating,
            isPreview: try c.decodeIfPresent(Bool.self, forKey: .isPreview) ?? false,
            isCollapsed: try c.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false,
            snappedEdge: try c.decodeIfPresent(SnapEdge.self, forKey: .snap),
            highlights: try ranges(.highlights),
            bolds: try ranges(.bolds),
            calendarUnit: try c.decodeIfPresent(CalendarUnit.self, forKey: .calendarUnit) ?? .month,
            opacity: try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1,
            dueDates: try c.decodeIfPresent([Date?].self, forKey: .dueDates) ?? [],
            dateMarks: try c.decodeIfPresent([String: String].self, forKey: .dateMarks) ?? [:],
            frame: frame,
            expandedFrame: expanded
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encode(kind, forKey: .kind)
        try c.encode(theme, forKey: .theme)
        try c.encode(mode, forKey: .mode)
        try c.encode(isPreview, forKey: .isPreview)
        try c.encode(isCollapsed, forKey: .isCollapsed)
        try c.encodeIfPresent(snappedEdge, forKey: .snap)
        if !highlights.isEmpty { try c.encode(highlights, forKey: .highlights) }
        if !bolds.isEmpty { try c.encode(bolds, forKey: .bolds) }
        try c.encode(calendarUnit, forKey: .calendarUnit)
        try c.encode(opacity, forKey: .opacity)
        if !dueDates.isEmpty {
            try c.encode(dueDates, forKey: .dueDates)
        }
        if !dateMarks.isEmpty {
            try c.encode(dateMarks, forKey: .dateMarks)
        }
        try c.encode(frame.origin.x, forKey: .x)
        try c.encode(frame.origin.y, forKey: .y)
        try c.encode(frame.width, forKey: .w)
        try c.encode(frame.height, forKey: .h)
        try c.encode(expandedFrame.origin.x, forKey: .ex)
        try c.encode(expandedFrame.origin.y, forKey: .ey)
        try c.encode(expandedFrame.width, forKey: .ew)
        try c.encode(expandedFrame.height, forKey: .eh)
    }
}

// MARK: - 待办事项读写
// 待办便签把条目存在 text 里, 每行一条: "[ ] 内容" 或 "[x] 内容"
// 排期日期存在 note.dueDates 数组里, 与 text 非空行按序一一对齐 (nil = 未排期)。
// 周历筛选器按 dueDates 归属显示, 周历格子上的小圆点 = 那天有未完成的任务。

/// 把归档 (被删便签) 的排期对齐回原待办便签的当前行:
/// 每条归档条目找到原便签里"正文相同"的条目, 返回 (归档下标, 原便签下标或 -1)。
/// 原便签里已经没有这条 (被删了) → liveItem = -1, 该排期作废置 nil。
private func alignDuePairs(archItems: [TodoItem], liveItems: [TodoItem]) -> [(Int, Int)] {
    // 每条活条目按正文分组 (只取第一次出现的下标池)
    var pools = [String: [Int]]()
    for (i, item) in liveItems.enumerated() {
        let key = item.text.trimmingCharacters(in: .whitespaces)
        if !key.isEmpty { pools[key, default: []].append(i) }
    }
    var used = Set<Int>()
    var result: [(Int, Int)] = []
    for (i, item) in archItems.enumerated() {
        let key = item.text.trimmingCharacters(in: .whitespaces)
        var liveItem = -1
        if !key.isEmpty {
            liveItem = pools[key]?.first { !used.contains($0) } ?? -1
            if liveItem >= 0 { used.insert(liveItem) }
        }
        result.append((i, liveItem))
    }
    return result
}

struct TodoItem {
    var text: String
    var done: Bool
    /// 归属日期 (nil = 未排期)
    var due: Date?
}

extension Note {
    /// 解析 text 里的一行待办。
    /// 空行返回 nil; 其余返回 (是否完成, 正文, 正文在行内的起始偏移)。
    /// 允许 "[ ]"/"[x]" 后面不带空格 —— 那是刚用回车新建出来的空白条目。
    static func parseTodoLine(_ rawLine: String) -> (done: Bool, text: String, offset: Int)? {
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let lead = (rawLine as NSString).range(of: trimmed).location
        if trimmed.hasPrefix("[x] ") || trimmed.hasPrefix("[X] ") {
            return (true, String(trimmed.dropFirst(4)), lead + 4)
        }
        if trimmed.hasPrefix("[ ] ") {
            return (false, String(trimmed.dropFirst(4)), lead + 4)
        }
        // 空白条目: 只有复选框没正文
        if trimmed == "[x]" || trimmed == "[X]" { return (true, "", lead + 3) }
        if trimmed == "[ ]" { return (false, "", lead + 3) }
        return (false, trimmed, lead)
    }

    var todoItems: [TodoItem] {
        var index = 0
        return text.components(separatedBy: "\n").compactMap { line in
            guard let p = Note.parseTodoLine(line) else { return nil }
            let due = dueDates.indices.contains(index) ? dueDates[index] : nil
            index += 1
            return TodoItem(text: p.text, done: p.done, due: due)
        }
    }

    /// text 里非空行的个数, 与 todoItems / dueDates 的下标对齐
    private var todoLineCount: Int {
        text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    /// 按归属日期取该天的待办, 附带全局下标 (勾选/编辑/删除都要落回原位)
    func todos(on day: Date) -> [(index: Int, item: TodoItem)] {
        let cal = Calendar(identifier: .gregorian)
        return todoItems.enumerated().compactMap { i, item in
            guard let due = item.due,
                  cal.isDate(due, inSameDayAs: day) else { return nil }
            return (i, item)
        }
    }

    /// 未排期的待办 (due == nil)
    func unassignedTodos() -> [TodoItem] {
        todoItems.filter { $0.due == nil }
    }

    /// 给定一周的 7 天, 哪几天有未完成任务 (周历格子上的小圆点)
    func pendingDays(in days: [Date]) -> Set<Date> {
        let cal = Calendar(identifier: .gregorian)
        return Set(todoItems.compactMap { item in
            guard !item.done, let due = item.due else { return nil }
            return cal.startOfDay(for: due)
        })
    }

    // MARK: - 日历日期标注 (dateMarks)
    // key = "yyyy-MM-dd" (本地时区, 日粒度), value = 标注文字。
    // 完全离线, 随便签持久化, 适合标生日、课表、纪念日等。

    private static let markKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// 某天的标注 key (本地时区日粒度)
    static func dateMarkKey(for day: Date) -> String {
        markKeyFormatter.string(from: day)
    }

    /// 读某天标注; 没有则 nil
    func dateMark(on day: Date) -> String? {
        dateMarks[Self.dateMarkKey(for: day)].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// 写/改某天标注。传空串或 nil 视为清除。写完自动保存。
    /// 日历便签专用: 标注文字会同时变成一条待办 (追加到主待办便签, due=该天),
    /// 这样"重要日子"既在日历上有小字, 又在待办里待你处理。
    /// 首次标注 → 新增待办; 改标注文字 → 同步更新那条待办, 不重复生成。
    func setDateMark(_ text: String?, on day: Date, autoTodo: Bool = true) {
        let key = Self.dateMarkKey(for: day)
        let prev = dateMarks[key]
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            dateMarks.removeValue(forKey: key)
        } else {
            dateMarks[key] = trimmed
        }
        // 日历标注 → 待办联动
        if autoTodo && !trimmed.isEmpty {
            if prev == nil {
                NoteStore.shared.addTodoToPrimary(trimmed, due: gregStartOfDay(day))
            } else if prev != trimmed, let old = prev {
                NoteStore.shared.updateTodoFromMark(from: old, to: trimmed,
                                                    due: gregStartOfDay(day))
            }
        }
        NoteStore.shared.scheduleSave()
    }

    private func gregStartOfDay(_ day: Date) -> Date {
        Calendar(identifier: .gregorian).startOfDay(for: day)
    }

    /// 清除某天标注
    func clearDateMark(on day: Date) {
        dateMarks.removeValue(forKey: Self.dateMarkKey(for: day))
        NoteStore.shared.scheduleSave()
    }

    /// 条目一增删改字, 后面所有条目在 text 里的位置就整体平移。
    /// 高亮按「第几条 + 条内偏移」重新落位, 否则涂过的荧光会飘到别的字上。
    /// 归属日期 dueDates 也随条目整体重写, 保持一一对齐。
    private func rebuildText(_ items: [TodoItem]) {
        text = items
            .map { "\($0.done ? "[x]" : "[ ]") \($0.text)" }
            .joined(separator: "\n")
        dueDates = items.map(\.due)
    }

    private func writeTodos(_ items: [TodoItem],
                            keeping carried: (h: [HighlightAnchor], b: [HighlightAnchor])? = nil) {
        let kept = carried ?? (h: anchors(of: highlights), b: anchors(of: bolds))
        rebuildText(items)
        let h = rebuilt(from: kept.h)
        let b = rebuilt(from: kept.b)
        if highlights != h { highlights = h }
        if bolds != b { bolds = b }
    }

    private func rebuilt(from anchors: [HighlightAnchor]) -> [TextHighlight] {
        var out: [TextHighlight] = []
        for a in anchors {
            guard let r = todoContentRange(a.item) else { continue }
            let length = min(a.length, max(0, r.length - a.offset))
            guard length > 0 else { continue }
            out = out.adding(NSRange(location: r.location + a.offset, length: length))
        }
        return out
    }

    struct HighlightAnchor {
        let item: Int, offset: Int, length: Int
    }

    private func anchors(of marks: [TextHighlight]) -> [HighlightAnchor] {
        guard !marks.isEmpty else { return [] }
        return todoItems.indices.flatMap { i -> [HighlightAnchor] in
            guard let r = todoContentRange(i) else { return [] }
            return marks.compactMap {
                let overlap = NSIntersectionRange($0.range, r)
                guard overlap.length > 0 else { return nil }
                return HighlightAnchor(item: i, offset: overlap.location - r.location,
                                       length: overlap.length)
            }
        }
    }

    func toggleTodo(_ index: Int) {
        var items = todoItems
        guard items.indices.contains(index) else { return }
        items[index].done.toggle()
        writeTodos(items)
    }

    /// 只由条内直接编辑调用。高亮已经被编辑器按全局范围平移过了
    /// (后面条目的位置也一并挪好), 这里再按锚点重定位反而会把它算丢。
    /// 注意: 归日期不在这做 —— 编辑到结束 (失焦) 才由编辑器层统一处理,
    /// 否则每个按键都重写一次 text + dueDates。
    func setTodoText(_ index: Int, _ newText: String) {
        var items = todoItems
        guard items.indices.contains(index) else { return }
        items[index].text = newText.trimmingCharacters(in: .whitespaces)
        rebuildText(items)
    }

    /// 供周历筛选器改归属日期: 整批重写条目 (text + dueDates + 高亮重定位 + 保存)
    func rebuildTextForEditing(_ items: [TodoItem]) {
        writeTodos(items)
        NoteStore.shared.scheduleSave()
    }

    /// 一条已有待办被编辑结束后调用: 日期归到"今天", 位置不动。
    /// (用户确认: 改过的待办跟改动时间走, 但不用跳到最上面)
    /// 空白条目第一次写入不算"改动"——保留它继承来的日期, 由编辑器层判断。
    func touchTodo(at index: Int) {
        var items = todoItems
        guard items.indices.contains(index) else { return }
        items[index].due = Calendar.current.startOfDay(for: .now)
        rebuildTextForEditing(items)
    }

    /// 新增一条待办, due 为空 = 未排期。
    /// 新条目一律插在**最上面** (用户习惯: 刚建的/刚更新的在列表顶部, 不用滚到底部)
    func addTodo(_ itemText: String, due: Date? = nil) {
        let t = itemText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        var items = todoItems
        items.insert(TodoItem(text: t, done: false, due: due), at: 0)
        writeTodos(items)
    }

    func removeTodo(_ index: Int) {
        var items = todoItems
        guard items.indices.contains(index) else { return }
        // 删掉这条自己的标记, 它后面的条目整体前移一位
        func dropped(_ list: [HighlightAnchor]) -> [HighlightAnchor] {
            list.filter { $0.item != index }
                .map { HighlightAnchor(item: $0.item > index ? $0.item - 1 : $0.item,
                                       offset: $0.offset, length: $0.length) }
        }
        let carried = (h: dropped(anchors(of: highlights)), b: dropped(anchors(of: bolds)))
        items.remove(at: index)
        writeTodos(items, keeping: carried)
    }

    /// 在第 index 条**后面**插一条空白待办 (回车换行用), 沿用它的归属日期。
    /// 返回新条目的下标, 方便把光标挪过去。
    @discardableResult
    func insertTodo(after index: Int, due: Date?) -> Int {
        var items = todoItems
        let at = min(index + 1, items.count)
        items.insert(TodoItem(text: "", done: false, due: due), at: at)
        rebuildTextForEditing(items)
        return at
    }

    /// 第 index 条待办的文字在 text 里的范围 (不含 "[ ] " 前缀和行首空格)。
    /// 空白条目返回长度 0 的范围 —— 这样新条目也有可编辑的视图, 能直接打字。
    func todoContentRange(_ index: Int) -> NSRange? {
        var offset = 0, item = 0
        for line in text.components(separatedBy: "\n") {
            let lineLength = (line as NSString).length
            if let p = Note.parseTodoLine(line) {
                if item == index {
                    return NSRange(location: offset + p.offset,
                                   length: (p.text as NSString).length)
                }
                item += 1
            }
            offset += lineLength + 1
        }
        return nil
    }

    /// 文字便签 Markdown 里的任务行: 按行号切换 "- [ ]" ↔ "- [x]"
    func toggleTaskLine(_ lineIndex: Int) {
        var lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(lineIndex) else { return }
        let line = lines[lineIndex]
        if let r = line.range(of: "- [ ] ") {
            lines[lineIndex] = line.replacingCharacters(in: r, with: "- [x] ")
        } else if let r = line.range(of: "- [x] ") ?? line.range(of: "- [X] ") {
            lines[lineIndex] = line.replacingCharacters(in: r, with: "- [ ] ")
        } else {
            return
        }
        text = lines.joined(separator: "\n")
    }
}

// MARK: - 历史归档

struct ArchivedNote: Codable, Identifiable {
    let id: UUID
    let text: String
    let kind: NoteKind
    let theme: NoteTheme
    let highlights: [TextHighlight]
    let bolds: [TextHighlight]
    let deletedAt: Date
    /// 待办归档时一并存下每条的归属日期 (与 text 非空行对齐), 恢复时日期不丢
    var dueDates: [Date?]
    /// 未完成的条目是否已经被"新待办便签"领走过 —— 领过就不再重复领
    var carriedOver: Bool

    init(id: UUID, text: String, kind: NoteKind, theme: NoteTheme,
         highlights: [TextHighlight] = [], bolds: [TextHighlight] = [],
         dueDates: [Date?] = [], carriedOver: Bool = false, deletedAt: Date) {
        self.id = id
        self.text = text
        self.kind = kind
        self.theme = theme
        self.highlights = highlights
        self.bolds = bolds
        self.dueDates = dueDates
        self.carriedOver = carriedOver
        self.deletedAt = deletedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, text, kind, theme, highlights, bolds, deletedAt, dueDates, carriedOver
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        kind = try c.decodeIfPresent(NoteKind.self, forKey: .kind) ?? .text
        theme = try c.decodeIfPresent(NoteTheme.self, forKey: .theme) ?? .lemon
        let textLength = (text as NSString).length
        func ranges(_ key: CodingKeys) throws -> [TextHighlight] {
            (try c.decodeIfPresent([TextHighlight].self, forKey: key) ?? [])
                .filter { $0.location >= 0 && $0.length > 0 && NSMaxRange($0.range) <= textLength }
        }
        highlights = try ranges(.highlights)
        bolds = try ranges(.bolds)
        deletedAt = try c.decode(Date.self, forKey: .deletedAt)
        dueDates = try c.decodeIfPresent([Date?].self, forKey: .dueDates) ?? []
        carriedOver = try c.decodeIfPresent(Bool.self, forKey: .carriedOver) ?? false
    }
}

extension ArchivedNote {
    /// 归档正文里的待办条目 (和 Note 用同一套解析, 所以日期能跟着 dueDates 走)
    var todoItems: [TodoItem] {
        var index = 0
        return text.components(separatedBy: "\n").compactMap { line in
            guard let p = Note.parseTodoLine(line) else { return nil }
            let due = dueDates.indices.contains(index) ? dueDates[index] : nil
            index += 1
            return TodoItem(text: p.text, done: p.done, due: due)
        }
    }
}

// MARK: - 存储

final class NoteStore: ObservableObject {
    static let shared = NoteStore()

    private(set) var notes: [Note] = []
    @Published private(set) var archived: [ArchivedNote] = []
    private var cancellables: [UUID: AnyCancellable] = [:]
    private var saveWorkItem: DispatchWorkItem?

    private var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StickyNotes", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private var fileURL: URL { dir.appendingPathComponent("notes.json") }
    private var historyURL: URL { dir.appendingPathComponent("history.json") }

    func load() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Note].self, from: data) {
            notes = decoded
            notes.forEach(observe)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: historyURL),
           let decoded = try? decoder.decode([ArchivedNote].self, from: data) {
            archived = decoded
        }
    }

    func add(_ note: Note) {
        notes.append(note)
        observe(note)
        scheduleSave()
    }

    func remove(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        cancellables[note.id] = nil
        scheduleSave()
    }

    /// 删除时归档: 有内容的便签移入历史
    func archive(_ note: Note) {
        guard !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        archived.insert(
            ArchivedNote(id: UUID(), text: note.text, kind: note.kind,
                         theme: note.theme, highlights: note.highlights,
                         bolds: note.bolds, dueDates: note.dueDates,
                         deletedAt: Date()),
            at: 0)
        saveHistory()
    }

    /// 从历史中取回 (返回归档内容, 由调用方重建便签)
    func unarchive(_ id: UUID) -> ArchivedNote? {
        guard let index = archived.firstIndex(where: { $0.id == id }) else { return nil }
        let item = archived.remove(at: index)
        saveHistory()
        return item
    }

    /// 跨便签添加待办: 在指定日期 (due) 下, 往"当前主待办便签"追加一条任务。
    /// 主待办便签 = 第一张 kind=.todo 的便签; 没有就新建一张。
    /// 日历标注 → 待办联动 用这个。返回被写入的 note id。
    @discardableResult
    func addTodoToPrimary(_ text: String, due: Date?) -> UUID {
        var target = notes.first(where: { $0.kind == .todo })
        if target == nil {
            target = Note(text: "", kind: .todo, dueDates: [])
            add(target!)
        }
        let note = target!
        note.addTodo(text, due: due)
        return note.id
    }

    /// 未完成待办继承: 新建空白待办便签时调用, 把"别处还没做完的事"搬进新便签。
    /// 两个来源:
    ///   1) 现在还开着的其他待办便签 —— 未完成的搬走 (搬移, 不会两处都留)
    ///   2) 历史归档里的待办便签 —— 未完成的搬出来, 并标记已领, 不会重复领
    /// 这样即使误删了便签, 未完成的事也能回到新便签上, 不用重新敲一遍。
    func harvestUnfinishedTodos(into newNote: Note) {
        guard newNote.kind == .todo else { return }
        var collected: [TodoItem] = []
        var seen = Set(newNote.todoItems.map { $0.text })

        func take(_ item: TodoItem, due: Date? = nil) {
            guard !item.done, !item.text.isEmpty, !seen.contains(item.text) else { return }
            seen.insert(item.text)
            collected.append(TodoItem(text: item.text, done: item.done, due: due ?? item.due))
        }

        // 1) 还开着的其他待办便签: 未完成的搬走, 已完成的留在原处
        for src in notes where src.kind == .todo && src.id != newNote.id {
            let items = src.todoItems
            guard items.contains(where: { !$0.done }) else { continue }
            let dues = items.indices.map { src.dueDates.indices.contains($0) ? src.dueDates[$0] : nil }
            for (item, due) in zip(items, dues) {
                take(item, due: due)   // 条目自带的 due 优先; 丢了 due 的落到今天
            }
            src.rebuildTextForEditing(items.filter { $0.done })
        }

        // 2) 历史归档: 只领没领过的, 领完打标记
        //    排期对齐: 归档里的 dueDates 按"原便签删除那一刻"的行序存的;
        //    新便签可能已经领走了部分条目 (条目被删/被改过), 行序会漂。
        //    按正文逐条找回, 找不到的排期作废 (置 nil), 绝不按位置瞎对齐。
        for i in archived.indices where archived[i].kind == .todo && !archived[i].carriedOver {
            archived[i].carriedOver = true
            let arch = archived[i]
            let items = arch.todoItems
            let archDues = items.indices.map {
                arch.dueDates.indices.contains($0) ? arch.dueDates[$0] : nil
            }
            let pairs = alignDuePairs(archItems: items, liveItems: newNote.todoItems)
            for (k, item) in items.enumerated() {
                let live = pairs[k].1
                var realDue: Date? = archDues[k]
                if live >= 0, newNote.todoItems.indices.contains(live) {
                    // 原便签里这条还在 → 它的排期可能已被你在周历上改过, 以当前值为准
                    realDue = newNote.todoItems[live].due ?? realDue
                } else {
                    // 原便签里这条已经没了 → 归档里存的排期也作废 (防按位置错位)
                    realDue = nil
                }
                take(item, due: realDue)
            }
        }
        saveHistory()

        guard !collected.isEmpty else { return }
        var items = newNote.todoItems
        items.append(contentsOf: collected)
        newNote.rebuildTextForEditing(items)
        saveNow()
    }

    /// 日历标注改了文字: 把当天那条由标注生成的未完成待办同步改名, 不新增条目。
    func updateTodoFromMark(from old: String, to new: String, due: Date) {
        guard let target = notes.first(where: { $0.kind == .todo }) else { return }
        let cal = Calendar(identifier: .gregorian)
        let day = cal.startOfDay(for: due)
        var items = target.todoItems
        guard let idx = items.firstIndex(where: { item in
            guard !item.done, item.text == old, let d = item.due else { return false }
            return cal.startOfDay(for: d) == day
        }) else { return }
        items[idx].text = new
        target.rebuildTextForEditing(items)
        saveNow()
    }

    func removeArchived(_ id: UUID) {
        archived.removeAll { $0.id == id }
        saveHistory()
    }

    private func saveHistory() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(archived) {
            try? data.write(to: historyURL, options: .atomic)
        }
    }

    private func observe(_ note: Note) {
        // 内容/主题/模式变化后延迟自动保存
        cancellables[note.id] = note.objectWillChange
            .sink { [weak self] _ in self?.scheduleSave() }
    }

    /// 防抖: 停止输入 1 秒后写盘
    func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item)
    }

    func saveNow() {
        saveWorkItem?.cancel()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(notes) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
