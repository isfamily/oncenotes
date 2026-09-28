import AppKit
import SwiftUI
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var controllers: [UUID: NoteWindowController] = [:]
    private var historyWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 单实例保护: 如果已经有一份在运行, 激活它并退出自己
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.simony3.stickynotes")
        if running.count > 1 {
            running.first { $0 != NSRunningApplication.current }?
                .activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
            return
        }

        setupStatusItem()

        NoteStore.shared.load()
        if NoteStore.shared.notes.isEmpty {
            // 第一次使用给欢迎教程, 之后弹类型选择
            if UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
                promptNewNote()
            } else {
                createWelcomeNote()
                UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            }
        } else {
            NoteStore.shared.notes.forEach(showWindow)
        }

        if CommandLine.arguments.contains("--show-history") {
            showHistory()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NoteStore.shared.saveNow()
    }

    /// 在启动台/访达里再次点开 app 时:
    /// 没有便签 → 创建一张新的; 已有便签 → 全部带到前面
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // 通过 URL 创建便签时 open 也会触发 reopen, 跳过避免弹类型选择框
        if Date().timeIntervalSince(lastURLHandled) < 2 { return true }
        if controllers.isEmpty {
            promptNewNote()
        } else {
            showAll()
        }
        return true
    }

    // MARK: 菜单栏图标

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "note.text", accessibilityDescription: "一次便签")

        let menu = NSMenu()
        menu.addItem(withTitle: "新建文字便签", action: #selector(newTextNote), keyEquivalent: "n")
        menu.addItem(withTitle: "新建待办便签", action: #selector(newTodoNote), keyEquivalent: "t")
        menu.addItem(withTitle: "新建日历便签", action: #selector(newCalendarNote), keyEquivalent: "c")
        menu.addItem(withTitle: "历史便签", action: #selector(showHistory), keyEquivalent: "h")
        menu.addItem(.separator())

        let loginItem = NSMenuItem(
            title: "开机自动启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem(
            title: "加粗快捷键: \(BoldShortcut.display)",
            action: #selector(setBoldShortcut), keyEquivalent: ""))

        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    // MARK: 便签管理

    @objc private func newTextNote() { createNote(kind: .text) }
    @objc private func newTodoNote() { createNote(kind: .todo) }
    @objc private func newCalendarNote() { createNote(kind: .calendar) }

    /// 弹出类型选择, 再创建对应类型的便签
    private func promptNewNote() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "创建新便签"
        alert.informativeText = "选择便签类型:"
        alert.addButton(withTitle: "📝 文字便签")
        alert.addButton(withTitle: "✅ 待办便签")
        alert.addButton(withTitle: "📅 日历便签")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn:  createNote(kind: .text)
        case .alertSecondButtonReturn: createNote(kind: .todo)
        case .alertThirdButtonReturn:  createNote(kind: .calendar)
        default: break
        }
    }

    @discardableResult
    private func createNote(kind: NoteKind, text: String = "", theme: NoteTheme? = nil,
                            mode: NoteMode = .floating, preview: Bool = false,
                            collapsed: Bool = false,
                            highlights: [TextHighlight] = [],
                            bolds: [TextHighlight] = [],
                            calendarUnit: CalendarUnit? = nil,
                            opacity: Double? = nil,
                            dueDates: [Date?]? = nil,
                            dateMarks: [String: String]? = nil) -> Note {
        let cascade = CGFloat(controllers.count % 8) * 28
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        // 日历便签: 更宽、按月历默认高度, 且默认贴桌面 + 半透明, 像一块玻璃日历卡片
        // 待办便签: 多出一行周历筛选器, 高度相应加
        let defaultSize: (w: CGFloat, h: CGFloat)
        let defaultMode: NoteMode
        let defaultOpacity: Double
        if kind == .calendar {
            defaultSize = (320, 336)
            defaultMode = mode
            defaultOpacity = mode == .desktop ? 0.55 : 0.9
        } else if kind == .todo {
            defaultSize = (320, 360)
            defaultMode = mode
            defaultOpacity = 1
        } else {
            defaultSize = (280, 280)
            defaultMode = mode
            defaultOpacity = 1
        }
        let finalOpacity = opacity.map(clampOpacity) ?? defaultOpacity
        let frame = CGRect(
            x: screen.midX - defaultSize.w / 2 + cascade,
            y: screen.midY - defaultSize.h / 2 - cascade,
            width: defaultSize.w, height: defaultSize.h)

        // 未指定颜色时顺延取色, 避免全是黄色
        let usedThemes = NoteStore.shared.notes.map(\.theme)
        let nextTheme = theme
            ?? NoteTheme.allCases.first { !usedThemes.contains($0) }
            ?? NoteTheme.allCases[NoteStore.shared.notes.count % NoteTheme.allCases.count]

        let note = Note(text: text, kind: kind, theme: nextTheme,
                        mode: defaultMode, isPreview: preview,
                        highlights: highlights, bolds: bolds,
                        calendarUnit: calendarUnit ?? .month,
                        opacity: finalOpacity,
                        dueDates: dueDates ?? [],
                        dateMarks: dateMarks ?? [:],
                        frame: frame)
        NoteStore.shared.add(note)
        // 新建"空白"待办便签时, 把别处还没做完的待办收进来 ——
        // 包括还开着的其他待办便签, 以及历史归档里误删的待办。
        // 这样随时可以关掉/删掉旧待办便签, 未完成的事会自动续到新的这张上。
        // 只在空白新建时收 (菜单"新建待办"的场景); 带内容创建 (URL/API) 不收,
        // 免得外部调用把你正在用的待办搬走。日历/文字便签不参与。
        if kind == .todo, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            NoteStore.shared.harvestUnfinishedTodos(into: note)
        }
        showWindow(note)
        if collapsed {
            controllers[note.id]?.toggleCollapse()
        }
        return note
    }

    // MARK: URL Scheme (stickynotes://add?...)
    // 供命令行 / AI 工具以细粒度命令操作便签。
    // 数据始终由正在运行的 App 通过 NoteStore 修改和保存，
    // 避免外部工具直接重写 notes.json 造成竞争或数据丢失。
    //
    // 创建:
    //   open "stickynotes://add?kind=todo&theme=peach&text=%E5%86%85%E5%AE%B9"
    // 参数: kind=text|todo, theme=lemon|peach|sky,
    //       mode=floating|normal|desktop, preview=1, collapsed=1, text=百分号编码内容,
    //       highlight/bold=荧光和加粗范围, 格式 "起点,长度;起点,长度" (UTF-16), 空串=清空
    // 更新: stickynotes://update?id=<UUID>&text=...&theme=...&mode=...&preview=0|1&collapsed=0|1
    //       &highlight=...&bold=...  (改了 text 又不传标记, 旧标记会被清空)
    // 删除: stickynotes://delete?id=<UUID>
    // 恢复: stickynotes://restore?id=<历史记录 UUID>
    // 删除历史: stickynotes://history-delete?id=<历史记录 UUID>
    // 移动/缩放: stickynotes://frame?id=<UUID>&x=...&y=...&w=...&h=...

    private var lastURLHandled = Date.distantPast

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { handleURL(url) }
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "stickynotes",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        lastURLHandled = Date()

        var q: [String: String] = [:]
        comps.queryItems?.forEach { q[$0.name] = $0.value }

        switch url.host {
        case "add":
            let text = q["text"] ?? ""
            // 解析 due: 支持 "YYYY-MM-DD" (单条) 或 "YYYY-MM-DD;YYYY-MM-DD;..." (多条, 按行对齐)
            let dueDates = parseDueDates(q["due"], lineCount: max(1, text.components(separatedBy: "\n").count))
            // 解析 dateMarks: "YYYY-MM-DD:文字;YYYY-MM-DD:文字" (冒号分隔日期与文字, 分号分隔多条)
            let dateMarks = parseDateMarks(q["mark"])
            createNote(
                kind: NoteKind(rawValue: q["kind"] ?? "") ?? .text,
                text: text,
                theme: NoteTheme(rawValue: q["theme"] ?? ""),
                mode: NoteMode(rawValue: q["mode"] ?? "") ?? .floating,
                preview: q["preview"] == "1",
                collapsed: q["collapsed"] == "1",
                highlights: parseMarks(q["highlight"], in: text),
                bolds: parseMarks(q["bold"], in: text),
                calendarUnit: q["unit"].flatMap(CalendarUnit.init),
                opacity: q["opacity"].flatMap(queryDouble).map { clampOpacity($0) },
                dueDates: dueDates,
                dateMarks: dateMarks)

        case "update":
            guard let idStr = q["id"], let id = UUID(uuidString: idStr),
                  let note = NoteStore.shared.notes.first(where: { $0.id == id }) else { return }
            if let text = q["text"] {
                note.text = text
                // 外部入口是整段替换，旧文字范围已不再可靠;
                // 调用方要保留标记就自己算好新范围一起传进来。
                note.highlights = []
                note.bolds = []
            }
            if let marks = q["highlight"] { note.highlights = parseMarks(marks, in: note.text) }
            if let marks = q["bold"] { note.bolds = parseMarks(marks, in: note.text) }
            if let theme = NoteTheme(rawValue: q["theme"] ?? "") { note.theme = theme }
            if let mode = NoteMode(rawValue: q["mode"] ?? "") {
                note.mode = mode
                controllers[id]?.applyMode()
            }
            if let opacity = q["opacity"].flatMap(queryDouble) {
                note.opacity = clampOpacity(opacity)
                controllers[id]?.applyOpacity(note.opacity)
            }
            if note.kind == .todo {
                // 外部整段替换 text 时, dueDates 也要按新行数对齐
                let lineCount = note.text.components(separatedBy: "\n")
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
                if let dueStr = q["due"] {
                    note.dueDates = parseDueDates(dueStr, lineCount: lineCount)
                } else {
                    note.dueDates = []
                }
            }
            if note.kind == .calendar, let markStr = q["mark"] {
                // 日历便签的日期标注: 整段替换
                note.dateMarks = parseDateMarks(markStr)
                NoteStore.shared.scheduleSave()
            }
            if note.kind == .calendar, let unit = q["unit"].flatMap(CalendarUnit.init),
               unit != note.calendarUnit {
                note.calendarUnit = unit
                controllers[id]?.resizeForCalendarUnit()
            }
            if note.kind == .text, let preview = queryBool(q["preview"]) {
                note.isPreview = preview
            }
            if let collapsed = queryBool(q["collapsed"]), collapsed != note.isCollapsed {
                controllers[id]?.toggleCollapse()
            } else if note.isCollapsed, q["text"] != nil {
                // 折叠条宽度跟随新标题重算，不需要先展开再折叠。
                controllers[id]?.refreshCollapsedWidth()
            }

        case "setmark":
            // 日历日期标注 (与右键菜单同一条路径): 会同步生成/更新当天待办
            // stickynotes://setmark?id=<UUID>&date=YYYY-MM-DD&text=标注内容  (text 省略或空 = 清除)
            guard let idStr = q["id"], let id = UUID(uuidString: idStr),
                  let note = NoteStore.shared.notes.first(where: { $0.id == id }),
                  let dateStr = q["date"] else { return }
            let parser = DateFormatter()
            parser.dateFormat = "yyyy-MM-dd"
            parser.locale = Locale(identifier: "en_US_POSIX")
            guard let day = parser.date(from: dateStr) else { return }
            let markText = q["text"]
            note.setDateMark((markText?.isEmpty == true) ? nil : markText, on: day)

        case "insert-todo":
            // 在第 N 条待办后面插一条 (与"条内按回车"同一条模型路径)
            // stickynotes://insert-todo?id=<UUID>&after=0&text=内容  (text 可省, 留空 = 只插空白条)
            guard let idStr = q["id"], let id = UUID(uuidString: idStr),
                  let note = NoteStore.shared.notes.first(where: { $0.id == id }),
                  note.kind == .todo else { return }
            let after = Int(q["after"] ?? "0") ?? 0
            let items = note.todoItems
            guard items.indices.contains(after) else { return }
            let at = note.insertTodo(after: after, due: items[after].due)
            if let t = q["text"], !t.isEmpty { note.setTodoText(at, t) }
            NoteStore.shared.scheduleSave()

        case "login-item":
            // 开机启动开关 (与菜单栏那一项同一条路径)
            // stickynotes://login-item?on=1  注册;  ?on=0  取消
            let wantOn = q["on"] != "0"
            do {
                if wantOn {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("login-item \(wantOn ? "register" : "unregister") failed: \(error.localizedDescription)")
            }

        case "delete":
            guard let idStr = q["id"], let id = UUID(uuidString: idStr),
                  let note = NoteStore.shared.notes.first(where: { $0.id == id }) else { return }
            delete(note)

        case "restore":
            guard let idStr = q["id"], let id = UUID(uuidString: idStr),
                  let item = NoteStore.shared.archived.first(where: { $0.id == id }) else { return }
            restore(item)

        case "history-delete":
            guard let idStr = q["id"], let id = UUID(uuidString: idStr) else { return }
            NoteStore.shared.removeArchived(id)

        case "frame":
            guard let idStr = q["id"], let id = UUID(uuidString: idStr),
                  let note = NoteStore.shared.notes.first(where: { $0.id == id }),
                  let controller = controllers[id], let window = controller.window else { return }
            var frame = window.frame
            if let value = queryDouble(q["x"]) { frame.origin.x = value }
            if let value = queryDouble(q["y"]) { frame.origin.y = value }
            if let value = queryDouble(q["w"]) { frame.size.width = max(120, value) }
            if let value = queryDouble(q["h"]) {
                frame.size.height = note.isCollapsed ? NoteWindowController.barHeight : max(120, value)
            }
            window.setFrame(frame, display: true, animate: true)
            note.frame = frame
            if !note.isCollapsed { note.expandedFrame = frame }
            NoteStore.shared.scheduleSave()

        case "show-all":
            showAll()

        case "show-history":
            showHistory()

        default:
            break
        }
    }

    /// 标记参数格式: "起点,长度;起点,长度" (UTF-16 下标), 空串表示清空。
    /// 越界的段直接丢掉, 免得外部工具算错位置把文字画花。
    private func parseMarks(_ value: String?, in text: String) -> [TextHighlight] {
        guard let value, !value.isEmpty else { return [] }
        let limit = (text as NSString).length
        return value.split(separator: ";").compactMap { pair in
            let parts = pair.split(separator: ",")
            guard parts.count == 2, let loc = Int(parts[0]), let len = Int(parts[1]),
                  loc >= 0, len > 0, loc + len <= limit else { return nil }
            return TextHighlight(NSRange(location: loc, length: len))
        }
    }

    private func queryBool(_ value: String?) -> Bool? {
        switch value?.lowercased() {
        case "1", "true", "yes":  return true
        case "0", "false", "no": return false
        default:                    return nil
        }
    }

    private func queryDouble(_ value: String?) -> CGFloat? {
        guard let value, let number = Double(value), number.isFinite else { return nil }
        return CGFloat(number)
    }

    /// 解析 dateMarks 参数: "YYYY-MM-DD:文字;YYYY-MM-DD:文字"。
    /// 冒号分隔日期与文字, 分号分隔多条。日期格式错的整条丢弃。
    /// 空参数返回空字典 (清除全部)。
    private func parseDateMarks(_ value: String?) -> [String: String] {
        guard let value, !value.isEmpty else { return [:] }
        let dateRe = try! NSRegularExpression(
            pattern: "^\\d{4}-\\d{2}-\\d{2}:", options: [])
        var out: [String: String] = [:]
        for part in value.components(separatedBy: ";") {
            let p = part.trimmingCharacters(in: .whitespaces)
            guard !p.isEmpty,
                  dateRe.firstMatch(in: p, range: NSRange(p.startIndex..., in: p)) != nil
            else { continue }
            let sep = p.index(p.startIndex, offsetBy: 10)  // 指向 "YYYY-MM-DD" 后的冒号
            let key = String(p[..<sep])                       // 日期 key (10 字符)
            let textStart = p.index(sep, offsetBy: 1)         // 冒号后第一个字
            let text = String(p[textStart...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { out[key] = text }
        }
        return out
    }

    /// 解析 due 参数: "YYYY-MM-DD" 应用到所有行; "YYYY-MM-DD;YYYY-MM-DD;..." 按行对齐。
    /// 解析失败的日期返回 nil (未排期)。
    private func parseDueDates(_ value: String?, lineCount: Int) -> [Date?] {
        guard let value, !value.isEmpty else { return [] }
        let cal = Calendar(identifier: .gregorian)
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "en_US_POSIX")
        let parts = value.split(separator: ";").map(String.init)
        if parts.count == 1 {
            // 单值广播给所有行
            let d = parts[0].isEmpty ? nil : parser.date(from: parts[0]).map { cal.startOfDay(for: $0) }
            return Array(repeating: d, count: lineCount)
        }
        // 多值按行对齐
        var out: [Date?] = []
        for i in 0..<lineCount {
            let p = i < parts.count ? parts[i] : ""
            out.append(p.isEmpty ? nil : parser.date(from: p).map { cal.startOfDay(for: $0) })
        }
        return out
    }

    @objc private func showAll() {
        NSApp.activate(ignoringOtherApps: true)
        for controller in controllers.values {
            controller.window?.orderFront(nil)
            // 贴在桌面的便签临时浮上来露个脸, 3 秒后沉回桌面
            if controller.note.mode == .desktop {
                controller.window?.level = .floating
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak controller] in
                    controller?.applyMode()
                }
            }
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                sender.state = .off
            } else {
                try SMAppService.mainApp.register()
                sender.state = .on
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "设置开机启动失败"
            alert.informativeText = "\(error.localizedDescription)\n\n提示: 应用需要放在“应用程序”文件夹中才能注册开机启动。"
            alert.runModal()
        }
    }

    /// 改加粗快捷键: 弹窗期间直接按下新组合键即可
    @objc private func setBoldShortcut(_ sender: NSMenuItem) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "设置加粗快捷键"
        alert.informativeText = "现在按下新的组合键 (至少含 ⌘/⌃/⌥ 之一)。当前: \(BoldShortcut.display)"
        alert.addButton(withTitle: "恢复默认 ⌘B")
        alert.addButton(withTitle: "取消")
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
            guard !mods.intersection([.command, .control, .option]).isEmpty,
                  let ch = event.charactersIgnoringModifiers?.lowercased(),
                  ch.count == 1, ch != " " else { return event }
            BoldShortcut.save(key: ch, modifiers: mods)
            NSApp.abortModal()
            return nil
        }
        let response = alert.runModal()
        if let monitor { NSEvent.removeMonitor(monitor) }
        if response == .alertFirstButtonReturn {
            BoldShortcut.save(key: "b", modifiers: [.command])
        }
        sender.title = "加粗快捷键: \(BoldShortcut.display)"
    }

    @objc private func quit() {
        NoteStore.shared.saveNow()
        NSApp.terminate(nil)
    }

    private func showWindow(_ note: Note) {
        if note.frame.width < 50 {
            note.frame = CGRect(x: 200, y: 200, width: 280, height: 280)
        }
        let controller = NoteWindowController(
            note: note,
            onDelete: { [weak self] n in self?.delete(n) },
            onNewNote: { [weak self] kind in self?.createNote(kind: kind) }
        )
        controller.window?.setFrame(note.frame, display: true)
        controllers[note.id] = controller
        // 淡入出现
        controller.window?.alphaValue = 0
        controller.window?.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            controller.window?.animator().alphaValue = 1
        }
        if note.mode != .desktop {
            controller.window?.makeKey()
        }
    }

    private func delete(_ note: Note) {
        controllers[note.id]?.window?.orderOut(nil)
        controllers[note.id] = nil
        NoteStore.shared.archive(note)   // 有内容的便签先归档进历史
        NoteStore.shared.remove(note)
    }

    // MARK: 历史便签

    @objc private func showHistory() {
        NSApp.activate(ignoringOtherApps: true)
        if historyWindow == nil {
            let view = HistoryView(store: NoteStore.shared) { [weak self] item in
                self?.restore(item)
            }
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            win.title = "历史便签"
            win.contentView = NSHostingView(rootView: view)
            win.isReleasedWhenClosed = false
            win.center()
            historyWindow = win
        }
        historyWindow?.makeKeyAndOrderFront(nil)
    }

    /// 把历史记录恢复成一张新便签
    private func restore(_ item: ArchivedNote) {
        guard let archived = NoteStore.shared.unarchive(item.id) else { return }
        let cascade = CGFloat(controllers.count % 8) * 28
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let note = Note(
            text: archived.text, kind: archived.kind, theme: archived.theme,
            highlights: archived.highlights,
            bolds: archived.bolds,
            frame: CGRect(x: screen.midX - 140 + cascade, y: screen.midY - 20 - cascade,
                          width: 280, height: 280))
        NoteStore.shared.add(note)
        showWindow(note)
    }

    private func createWelcomeNote() {
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let note = Note(
            text: """
            # 欢迎使用便签 👋

            这是一张支持 **Markdown** 的便签:

            - 点右上角 👁 预览渲染效果
            - 点 ✏️ 回到编辑模式
            - 鼠标悬停顶栏可换颜色、切换窗口模式
            - [ ] 待办事项写法
            - [x] 已完成事项

            > 内容自动保存, 拖动边缘可调整大小

            菜单栏的 📝 图标可以新建便签、设置开机启动。
            """,
            theme: .lemon,
            frame: CGRect(x: screen.midX - 160, y: screen.midY - 40, width: 320, height: 360))
        NoteStore.shared.add(note)
        showWindow(note)
    }
}
