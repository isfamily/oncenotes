import SwiftUI

// MARK: - 磨砂玻璃背景 (NSVisualEffectView 桥接)

struct FrostedGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// macOS 27 起 isMovableByWindowBackground 不再把 SwiftUI 顶栏空白处当窗口背景, 显式接管拖动
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}

struct NoteView: View {
    @ObservedObject var note: Note
    var onClose: () -> Void
    var onModeChange: (NoteMode) -> Void
    var onNewNote: (NoteKind) -> Void
    var onToggleCollapse: () -> Void
    var onOpacity: ((Double) -> Void)? = nil

    @State private var hovering = false
    @State private var eraseAllToken = 0

    private var highlighterMode: Bool { note.highlighterMode }

    /// 透明度滑杆用的 Binding: 改完立刻回调窗口层, 让整张窗口变透明
    private var opacityBinding: Binding<Double> {
        Binding(
            get: { note.opacity },
            set: { newValue in
                note.opacity = clampOpacity(newValue)
                onOpacity?(note.opacity)
            }
        )
    }

    private var accent: Color { Color(nsColor: note.theme.accent) }
    private var ink: Color { Color(nsColor: note.theme.text) }

    /// 吸附屏幕边缘时, 贴边的一侧变直角 (被屏幕"切平"的效果)
    private var cornerRadii: RectangleCornerRadii {
        let r: CGFloat = 14
        guard note.isCollapsed else {
            return .init(topLeading: r, bottomLeading: r, bottomTrailing: r, topTrailing: r)
        }
        switch note.snappedEdge {
        case .left:
            return .init(topLeading: 0, bottomLeading: 0, bottomTrailing: r, topTrailing: r)
        case .right:
            return .init(topLeading: r, bottomLeading: r, bottomTrailing: 0, topTrailing: 0)
        case nil:
            return .init(topLeading: r, bottomLeading: r, bottomTrailing: r, topTrailing: r)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if !note.isCollapsed {
                content
            }
        }
        .background {
            // 玻璃拟态: 磨砂玻璃透出桌面 + 半透明色彩罩保证文字可读
            ZStack {
                FrostedGlass()
                Color(nsColor: note.theme.background).opacity(0.82)
            }
        }
        .clipShape(UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous))
        .overlay {
            // 玻璃边缘: 上亮下暗的渐变细线
            UnevenRoundedRectangle(cornerRadii: cornerRadii, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.55), .white.opacity(0.08),
                                 .black.opacity(0.06)],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
        }
        .animation(.spring(duration: 0.25), value: note.snappedEdge)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.18)) { hovering = h }
        }
    }

    // MARK: 顶栏

    private var topBar: some View {
        HStack(spacing: 8) {
            if !note.isCollapsed {
            // 关闭(删除)按钮
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(ink.opacity(hovering ? 0.55 : 0.22))
                    .frame(width: 17, height: 17)
                    .background(Circle().fill(ink.opacity(hovering ? 0.08 : 0.04)))
            }
            .buttonStyle(.plain)
            .help("删除这张便签")

            // 新建按钮 (弹出类型选择)
            Menu {
                Button("📝 文字便签") { onNewNote(.text) }
                Button("✅ 待办便签") { onNewNote(.todo) }
                Button("📅 日历便签") { onNewNote(.calendar) }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(ink.opacity(hovering ? 0.55 : 0.22))
                    .frame(width: 17, height: 17)
                    .background(Circle().fill(ink.opacity(hovering ? 0.08 : 0.04)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 19)
            .help("新建便签")
            }

            if note.isCollapsed {
                // 折叠态: 只显示标题 (删除/新建按钮隐藏, 展开后恢复)
                Text(note.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.75))
                    .lineLimit(1)
                    .fixedSize()   // 强制完整显示, 永不省略成 "..."
                    .padding(.leading, 2)
            }

            Spacer()

            if !note.isCollapsed && hovering {
                // 颜色切换
                ForEach(NoteTheme.allCases, id: \.self) { theme in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { note.theme = theme }
                    } label: {
                        Circle()
                            .fill(Color(nsColor: theme.bar))
                            .frame(width: 11, height: 11)
                            .overlay {
                                Circle().strokeBorder(
                                    Color(nsColor: theme.accent)
                                        .opacity(note.theme == theme ? 0.9 : 0.25),
                                    lineWidth: note.theme == theme ? 1.5 : 1)
                            }
                            .scaleEffect(note.theme == theme ? 1.15 : 1)
                    }
                    .buttonStyle(.plain)
                    .help(theme.displayName)
                }

                Divider().frame(height: 11).opacity(0.4)

                // 窗口模式切换
                Menu {
                    ForEach(NoteMode.allCases, id: \.self) { mode in
                        Button {
                            onModeChange(mode)
                        } label: {
                            if note.mode == mode {
                                Label(mode.displayName, systemImage: "checkmark")
                            } else {
                                Text(mode.displayName)
                            }
                        }
                    }
                } label: {
                    Image(systemName: note.mode.symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ink.opacity(0.5))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 22)
                .help("窗口模式: \(note.mode.displayName)")
            }

            // 荧光笔 (文字和待办都有; 日历没有正文, 不涂)
            if !note.isCollapsed && note.kind != .calendar && !note.isPreview {
                // 清空全部: 模式开着且真有高亮时才浮出来
                if highlighterMode && !note.highlights.isEmpty {
                    Button {
                        // 文字便签整篇由一个 NSTextView 接管, 走它才能进撤销栈;
                        // 待办是每条一个视图, 顶栏这里直接清整张。
                        if note.kind == .text {
                            eraseAllToken += 1
                        } else {
                            withAnimation(.easeOut(duration: 0.15)) { note.highlights = [] }
                        }
                    } label: {
                        Image(systemName: "eraser")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ink.opacity(0.5))
                            .frame(width: 17, height: 17)
                    }
                    .buttonStyle(.plain)
                    .help("清空这张便签的全部高亮")
                    .transition(.opacity.combined(with: .scale))
                }

                Button {
                    withAnimation(.easeOut(duration: 0.18)) { note.highlighterMode.toggle() }
                } label: {
                    Image(systemName: "highlighter")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(highlighterMode ? accent : ink.opacity(hovering ? 0.55 : 0.22))
                        .frame(width: 17, height: 17)
                        .background(Circle().fill(accent.opacity(highlighterMode ? 0.16 : 0)))
                }
                .buttonStyle(.plain)
                .help(highlighterMode ? "退出荧光笔 (Esc)" : "荧光笔 (⌘⇧H): 拖动涂抹, 退格擦除")
            }

            // 所有便签 (文字/待办/日历): 透明度滑杆
            if !note.isCollapsed {
                // 透明度滑杆 (0.3...1)
                Slider(value: opacityBinding, in: 0.3...1, step: 0.05)
                    .frame(width: 56)
                    .controlSize(.small)
                    .help("窗口透明度: 调低更像一张通透的卡片")
                Text("\(Int(note.opacity * 100))%")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(ink.opacity(0.4))
                    .frame(width: 26, alignment: .leading)
            }

            // 编辑/预览切换 (折叠时隐藏; 日历没有编辑态, 直接当预览看)
            if !note.isCollapsed && note.kind != .calendar {
                Button {
                    note.highlighterMode = false
                    withAnimation(.easeInOut(duration: 0.2)) { note.isPreview.toggle() }
                } label: {
                    Image(systemName: note.isPreview ? "pencil" : "eye")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ink.opacity(hovering ? 0.55 : 0.22))
                        .frame(width: 17, height: 17)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .help(note.isPreview ? "回到编辑" : "预览 (只读干净视图)")
            }

            // 折叠/展开
            Button {
                note.highlighterMode = false
                onToggleCollapse()
            } label: {
                Image(systemName: note.isCollapsed
                    ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ink.opacity(hovering ? 0.55 : 0.22))
                    .frame(width: 17, height: 17)
            }
            .buttonStyle(.plain)
            .help(note.isCollapsed ? "展开便签" : "折叠成一行标题")
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background {
            ZStack {
                Color(nsColor: note.theme.bar).opacity(0.5)
                WindowDragArea()
            }
        }
        .overlay(alignment: .bottom) {
            // 顶栏与正文之间的发丝线
            Rectangle().fill(ink.opacity(0.06)).frame(height: 0.5)
        }
    }

    // MARK: 内容区

    @ViewBuilder
    private var content: some View {
        if note.kind == .calendar {
            CalendarNoteView(note: note)
        } else if note.kind == .todo {
            TodoListView(note: note, readOnly: note.isPreview, highlighterMode: highlighterMode)
        } else if note.isPreview {
            ScrollView {
                MarkdownText(source: note.text, highlights: note.highlights,
                             bolds: note.bolds, theme: note.theme,
                             onToggleTask: { note.toggleTaskLine($0) })
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        } else {
            HighlightedTextEditor(
                text: $note.text,
                highlights: $note.highlights,
                bolds: $note.bolds,
                theme: note.theme,
                highlighterMode: $note.highlighterMode,
                eraseAllToken: eraseAllToken)
        }
    }
}

/// 荧光笔笔头光标, 热点落在左下角的笔尖上
func highlighterCursor(_ color: NSColor) -> NSCursor {
    guard let symbol = NSImage(systemSymbolName: "highlighter", accessibilityDescription: "荧光笔"),
          let image = symbol.withSymbolConfiguration(
            .init(pointSize: 17, weight: .regular)
            .applying(.init(paletteColors: [color.withAlphaComponent(1)])))
    else { return .crosshair }
    image.isTemplate = false
    return NSCursor(image: image, hotSpot: NSPoint(x: 2, y: image.size.height - 2))
}

// MARK: - 带荧光笔的原生文字编辑器

/// TextEditor 无法定制原生右键菜单，也不能持久显示局部背景色，
/// 因此这里用 NSTextView 保留纯文本数据，并通过 temporary attributes 绘制高亮。
struct HighlightedTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var highlights: [TextHighlight]
    @Binding var bolds: [TextHighlight]
    let theme: NoteTheme
    @Binding var highlighterMode: Bool
    let eraseAllToken: Int   // 顶栏「清空全部」按钮的信号, 值变了就执行一次

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = HighlighterTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 9, height: 8)
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = theme.text
        textView.insertionPointColor = theme.accent
        textView.string = text

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4.5
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: theme.text,
            .paragraphStyle: paragraph
        ]

        // 文字一变就要平移高亮, 所以立刻挂上; 等到 textDidBeginEditing 再挂会漏掉
        // MCP、历史恢复这类用户从没敲过字的便签。
        textView.textStorage?.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.lastSyncedText = text

        let c = context.coordinator
        textView.onPaint = { [weak c] in c?.paint($0) }
        textView.onErase = { [weak c] in c?.erase($0) }
        textView.onEraseSelection = { [weak c] in c?.eraseSelection($0) }
        textView.onEraseAll = { [weak c] in c?.eraseAll() }
        textView.onModeChange = { [weak c] in c?.setMode($0) }
        textView.hasHighlight = { [weak c] in c?.hasHighlight(in: $0) ?? false }
        textView.onToggleBold = { [weak c] in c?.toggleBold($0) }
        textView.isBold = { [weak c] in c?.parent.bolds.coversFully($0) ?? false }

        scrollView.documentView = textView
        context.coordinator.applyState(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? HighlighterTextView else { return }

        // 只有内容确实来自外部(MCP/历史恢复)才回灌。
        // 用户打字时 textStorage 回调会先改 highlights 触发一次刷新, 那一刻
        // note.text 还没跟上, 若在这里回灌就等于在 TextKit 处理编辑的过程中
        // 重入改写 text storage —— 编辑器会就此失去响应。
        if textView.string != text, text != context.coordinator.lastSyncedText {
            let caret = textView.selectedRange().location
            context.coordinator.syncingFromModel = true
            textView.string = text
            context.coordinator.syncingFromModel = false
            context.coordinator.lastSyncedText = text
            textView.setSelectedRange(
                NSRange(location: min(caret, (text as NSString).length), length: 0))
            context.coordinator.invalidateDrawing()
        }
        if context.coordinator.eraseToken != eraseAllToken {
            context.coordinator.eraseToken = eraseAllToken
            // 不能在 SwiftUI 的更新周期里改 @Binding, 挪到下一轮
            DispatchQueue.main.async { [weak c = context.coordinator] in c?.eraseAll() }
        }
        context.coordinator.applyState(to: textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: HighlightedTextEditor
        weak var textView: HighlighterTextView?
        var syncingFromModel = false
        var eraseToken: Int
        /// 最后一次由本视图同步出去的内容, 用来分辨「model 只是还没跟上」
        /// 和「内容真的被外部改了」
        var lastSyncedText: String?

        private var drawn: [TextHighlight] = []
        private var drawnBolds: [TextHighlight] = []
        private var drawnColor: NSColor?
        private var needsRedraw = true

        init(_ parent: HighlightedTextEditor) {
            self.parent = parent
            self.eraseToken = parent.eraseAllToken
        }

        func applyState(to textView: HighlighterTextView) {
            textView.highlightMode = parent.highlighterMode
            textView.textColor = parent.theme.text
            textView.insertionPointColor = parent.theme.accent
            textView.highlighterColor = parent.theme.highlighter
            textView.typingAttributes[.foregroundColor] = parent.theme.text
            redraw(in: textView)
        }

        func invalidateDrawing() { needsRedraw = true }

        // MARK: 文字同步

        /// 荧光笔是一个模式: 模式内只涂不改字, 这里是挡住所有文字改动的总闸门
        /// (打字、粘贴、拖放、输入法、撤销文字编辑都会经过它)。
        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange,
                      replacementString: String?) -> Bool {
            !parent.highlighterMode
        }

        func textDidChange(_ notification: Notification) {
            guard !syncingFromModel, let textView else { return }
            lastSyncedText = textView.string
            parent.text = textView.string
            redraw(in: textView)
        }

        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                         range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters), !syncingFromModel else { return }
            let replaced = NSRange(location: editedRange.location,
                                   length: max(0, editedRange.length - delta))
            // 跟随文字变化的平移不进撤销栈: 撤销文字编辑时这里会被反向调用一次, 自然还原。
            let shifted = parent.highlights.shifting(replacing: replaced, newLength: editedRange.length)
            if shifted != parent.highlights { parent.highlights = shifted }
            let shiftedBolds = parent.bolds.shifting(replacing: replaced, newLength: editedRange.length)
            if shiftedBolds != parent.bolds { parent.bolds = shiftedBolds }
            // 此刻 layout manager 还没收到这次编辑, 在这里动 temporary attributes
            // 会打断输入处理, 编辑器从此不再响应按键。只标脏, 等 textDidChange
            // (编辑收尾后) 再重绘。
            needsRedraw = true
        }

        // MARK: 高亮增删

        func paint(_ range: NSRange) {
            guard range.length > 0, let textView else { return }
            let s = textView.string as NSString
            guard NSMaxRange(range) <= s.length else { return }
            let pieces = lineSegments(range, in: s)
            guard !pieces.isEmpty else { return }
            apply(pieces.reduce(parent.highlights) { $0.adding($1) }, "涂色")
        }

        func erase(_ target: NSRange) {
            guard target.length > 0 else { return }
            apply(parent.highlights.removing(target), "擦除高亮")
        }

        /// 跨行拖选时选区里夹着换行符, 给换行符上底色会让上一行的色块
        /// 一直铺到窗口右边缘。按换行切开, 再削掉每段两端的空白。
        private func lineSegments(_ range: NSRange, in s: NSString) -> [NSRange] {
            var out: [NSRange] = []
            var start = range.location
            for i in range.location..<NSMaxRange(range) {
                let c = s.character(at: i)
                guard c == 0x0A || c == 0x0D else { continue }
                if i > start { out.append(NSRange(location: start, length: i - start)) }
                start = i + 1
            }
            if NSMaxRange(range) > start {
                out.append(NSRange(location: start, length: NSMaxRange(range) - start))
            }
            return out.compactMap { trimmedBlanks($0, in: s) }
        }

        private func trimmedBlanks(_ r: NSRange, in s: NSString) -> NSRange? {
            var lo = r.location, hi = NSMaxRange(r)
            func blank(_ i: Int) -> Bool {
                guard let u = Unicode.Scalar(s.character(at: i)) else { return false }
                return CharacterSet.whitespaces.contains(u)
            }
            while lo < hi, blank(lo) { lo += 1 }
            while hi > lo, blank(hi - 1) { hi -= 1 }
            return hi > lo ? NSRange(location: lo, length: hi - lo) : nil
        }

        /// 右键「擦除所选高亮」: 没有选区时擦掉光标所在的那一整段
        func eraseSelection(_ selection: NSRange) {
            if selection.length > 0 { erase(selection); return }
            if let h = parent.highlights.first(where: { NSLocationInRange(selection.location, $0.range) }) {
                erase(h.range)
            }
        }

        func eraseAll() { apply([], "清空高亮") }

        func hasHighlight(in selection: NSRange) -> Bool {
            if selection.length == 0 {
                return parent.highlights.contains { NSLocationInRange(selection.location, $0.range) }
            }
            return parent.highlights.contains { NSIntersectionRange($0.range, selection).length > 0 }
        }

        // MARK: 加粗

        func toggleBold(_ range: NSRange) {
            guard range.length > 0 else { return }
            if parent.bolds.coversFully(range) {
                applyBolds(parent.bolds.removing(range), "取消加粗")
            } else {
                applyBolds(parent.bolds.adding(range), "加粗")
            }
        }

        private func applyBolds(_ new: [TextHighlight], _ actionName: String) {
            let old = parent.bolds
            guard old != new else { return }
            parent.bolds = new
            textView?.undoManager?.registerUndo(withTarget: self) { $0.applyBolds(old, actionName) }
            textView?.undoManager?.setActionName(actionName)
            if let textView { redraw(in: textView) }
        }

        func setMode(_ enabled: Bool) {
            parent.highlighterMode = enabled
            textView?.highlightMode = enabled
        }

        /// 高亮改动的唯一出口: 写模型 + 注册撤销 + 重绘
        private func apply(_ new: [TextHighlight], _ actionName: String) {
            let old = parent.highlights
            guard old != new else { return }
            parent.highlights = new
            textView?.undoManager?.registerUndo(withTarget: self) { $0.apply(old, actionName) }
            textView?.undoManager?.setActionName(actionName)
            if let textView { redraw(in: textView) }
        }

        // MARK: 绘制与平移

        private func redraw(in textView: HighlighterTextView) {
            let color = parent.theme.highlighter
            guard needsRedraw || drawn != parent.highlights || drawnBolds != parent.bolds
                    || drawnColor != color,
                  let lm = textView.layoutManager else { return }
            // 输入法组字期间不动属性, 上屏后的 textDidChange 会再来一次
            if textView.hasMarkedText() { needsRedraw = true; return }
            let full = NSRange(location: 0, length: (textView.string as NSString).length)
            lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
            for h in parent.highlights where h.length > 0 && NSMaxRange(h.range) <= full.length {
                lm.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: h.range)
            }
            if let ts = textView.textStorage {
                ts.beginEditing()
                ts.addAttribute(.font, value: NSFont.systemFont(ofSize: 14), range: full)
                for b in parent.bolds where b.length > 0 && NSMaxRange(b.range) <= full.length {
                    ts.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 14), range: b.range)
                }
                ts.endEditing()
            }
            drawn = parent.highlights
            drawnBolds = parent.bolds
            drawnColor = color
            needsRedraw = false
        }

    }
}

// MARK: - 加粗快捷键 (菜单栏可改, 默认 ⌘B)

enum BoldShortcut {
    private static let keyKey = "boldShortcut.key"
    private static let modsKey = "boldShortcut.modifiers"

    static var key: String { UserDefaults.standard.string(forKey: keyKey) ?? "b" }

    static var modifiers: NSEvent.ModifierFlags {
        guard let raw = UserDefaults.standard.object(forKey: modsKey) as? UInt else {
            return [.command]
        }
        return NSEvent.ModifierFlags(rawValue: raw)
    }

    static func save(key: String, modifiers: NSEvent.ModifierFlags) {
        UserDefaults.standard.set(key, forKey: keyKey)
        UserDefaults.standard.set(modifiers.rawValue, forKey: modsKey)
    }

    static func matches(_ event: NSEvent) -> Bool {
        event.charactersIgnoringModifiers?.lowercased() == key
            && event.modifierFlags
                .intersection([.command, .control, .option, .shift]) == modifiers
    }

    static var display: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option)  { s += "⌥" }
        if modifiers.contains(.shift)   { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + key.uppercased()
    }
}

final class HighlighterTextView: NSTextView, NSMenuDelegate {
    var highlightMode = false {
        didSet {
            guard oldValue != highlightMode else { return }
            window?.invalidateCursorRects(for: self)
            if !highlightMode { NSCursor.iBeam.set() }
        }
    }
    var highlighterColor: NSColor = .systemYellow
    var onPaint: ((NSRange) -> Void)?
    var onErase: ((NSRange) -> Void)?
    var onEraseSelection: ((NSRange) -> Void)?
    var onEraseAll: (() -> Void)?
    var onModeChange: ((Bool) -> Void)?
    var hasHighlight: ((NSRange) -> Bool)?
    var onToggleBold: ((NSRange) -> Void)?
    var isBold: ((NSRange) -> Bool)?
    var onMeasured: ((CGFloat) -> Void)?

    private var fullRange: NSRange { NSRange(location: 0, length: (string as NSString).length) }

    /// 按当前实际宽度排一遍版, 算出真实需要的行高 (宽度没定下来之前不报,
    /// 报出去的高度按错宽度算的, 反而害了上层)
    func measureAndReport() {
        guard let lm = layoutManager, let c = textContainer else { return }
        let w = bounds.width
        guard w > 1 else { return }
        c.containerSize = NSSize(width: w, height: .greatestFiniteMagnitude)
        lm.ensureLayout(for: c)
        onMeasured?(max(22, ceil(lm.usedRect(for: c).height)))
    }

    /// 宿主宽度变了 (窗口拉宽、行内布局落位) → 换行点全变, 重新报一次高
    /// (NSTextView 没有 didResize, 宿主套新 frame 会走 setFrameSize)
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        DispatchQueue.main.async { [weak self] in self?.measureAndReport() }
    }

    /// 内容变了 → 可能换出新行 / 消掉一行, 重新报一次高
    override func didChangeText() {
        super.didChangeText()
        DispatchQueue.main.async { [weak self] in self?.measureAndReport() }
    }

    /// 既不能编辑也不能选中时让点击穿过去, 交给上层的 SwiftUI 手势
    /// (待办里已完成的那条, 点文字要能取消勾选)
    override func hitTest(_ point: NSPoint) -> NSView? {
        (!isEditable && !isSelectable) ? nil : super.hitTest(point)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if highlightMode { addCursorRect(visibleRect, cursor: highlighterCursor(highlighterColor)) }
    }

    // MARK: 模式内的鼠标与键盘

    /// NSTextView 的 mouseDown 内部会一直跟踪到松手才返回, 所以拖选的结果
    /// 在 super 返回后直接读: 有选区 = 拖过一段(涂色), 没选区 = 单击(只放光标)。
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard highlightMode else { return }
        let range = selectedRange()
        guard range.length > 0 else { return }
        onPaint?(range)
        setSelectedRange(NSRange(location: NSMaxRange(range), length: 0))
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift],
           event.charactersIgnoringModifiers?.lowercased() == "h" {
            setMode(!highlightMode)
            return true
        }
        // 加粗只在正常编辑态生效, 荧光笔模式不受影响
        if BoldShortcut.matches(event), !highlightMode, isEditable {
            let selection = selectedRange()
            if selection.length > 0 { onToggleBold?(selection) }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if highlightMode, event.keyCode == 53 {   // Esc
            setMode(false)
            return
        }
        super.keyDown(with: event)
    }

    /// 模式内退格键不删字, 改成擦掉光标前一个字的高亮并左移一格
    override func deleteBackward(_ sender: Any?) {
        guard highlightMode else { super.deleteBackward(sender); return }
        let sel = selectedRange()
        if sel.length > 0 {
            onErase?(sel)
            return
        }
        guard sel.location > 0 else { return }
        // 按「一个字」擦, emoji 和组合字符算一个整体
        let prev = (string as NSString).rangeOfComposedCharacterSequence(at: sel.location - 1)
        onErase?(prev)
        setSelectedRange(NSRange(location: prev.location, length: 0))
    }

    private func setMode(_ on: Bool) {
        highlightMode = on
        onModeChange?(on)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.allowsContextMenuPlugIns = false
        if #available(macOS 15.2, *) {
            menu.automaticallyInsertsWritingToolsItems = false
        }
        menu.delegate = self

        let selection = selectedRange()
        addItem("撤销", action: #selector(performUndo), to: menu,
                enabled: undoManager?.canUndo == true)
        addItem("重做", action: #selector(performRedo), to: menu,
                enabled: undoManager?.canRedo == true)
        menu.addItem(.separator())
        // 荧光笔模式是只读的, 改文字的项一律灰掉
        addItem("剪切", action: #selector(cut(_:)), to: menu,
                enabled: !highlightMode && selection.length > 0)
        addItem("拷贝", action: #selector(copy(_:)), to: menu, enabled: selection.length > 0)
        addItem("粘贴", action: #selector(paste(_:)), to: menu,
                enabled: !highlightMode
                    && NSPasteboard.general.canReadObject(forClasses: [NSString.self], options: nil))
        addItem("全选", action: #selector(selectAll(_:)), to: menu, enabled: !string.isEmpty)

        let bold = addItem(
            isBold?(selection) == true ? "取消加粗" : "加粗",
            action: #selector(toggleBoldFromMenu), to: menu,
            enabled: !highlightMode && isEditable && selection.length > 0)
        bold.image = NSImage(systemSymbolName: "bold", accessibilityDescription: nil)
        bold.keyEquivalent = BoldShortcut.key
        bold.keyEquivalentModifierMask = BoldShortcut.modifiers
        menu.addItem(.separator())

        let highlighter = addItem(
            highlightMode ? "退出荧光笔 (Esc)" : "荧光笔 (⌘⇧H)",
            action: #selector(toggleHighlighter), to: menu, enabled: true)
        highlighter.state = highlightMode ? .on : .off
        highlighter.image = NSImage(systemSymbolName: "highlighter", accessibilityDescription: nil)

        let erase = addItem("擦除所选高亮", action: #selector(eraseSelected), to: menu,
                            enabled: hasHighlight?(selection) == true)
        erase.image = NSImage(systemSymbolName: "eraser", accessibilityDescription: nil)

        let eraseEverything = addItem("清空全部高亮", action: #selector(eraseAll), to: menu,
                                      enabled: hasHighlight?(fullRange) == true)
        eraseEverything.image = NSImage(systemSymbolName: "eraser.fill", accessibilityDescription: nil)
        return menu
    }

    /// AppKit 会在文字菜单末尾自动追加“自动填充”和“服务”等项目；
    /// 这里仅保留便签真正需要的编辑与荧光笔操作。
    func menuNeedsUpdate(_ menu: NSMenu) {
        let allowedActions = Set([
            "performUndo", "performRedo", "cut:", "copy:", "paste:", "selectAll:",
            "toggleBoldFromMenu", "toggleHighlighter", "eraseSelected", "eraseAll"
        ])
        for item in menu.items.reversed() where !item.isSeparatorItem {
            guard let action = item.action,
                  allowedActions.contains(NSStringFromSelector(action)) else {
                menu.removeItem(item)
                continue
            }
        }

        while menu.items.first?.isSeparatorItem == true { menu.removeItem(at: 0) }
        while menu.items.last?.isSeparatorItem == true { menu.removeItem(at: menu.items.count - 1) }
        for index in menu.items.indices.reversed() where index > 0 {
            if menu.items[index].isSeparatorItem && menu.items[index - 1].isSeparatorItem {
                menu.removeItem(at: index)
            }
        }
    }

    @discardableResult
    private func addItem(_ title: String, action: Selector, to menu: NSMenu,
                         enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        menu.addItem(item)
        return item
    }

    @objc private func performUndo() { undoManager?.undo() }
    @objc private func performRedo() { undoManager?.redo() }
    @objc private func toggleHighlighter() { setMode(!highlightMode) }
    @objc private func toggleBoldFromMenu() { onToggleBold?(selectedRange()) }
    @objc private func eraseSelected() { onEraseSelection?(selectedRange()) }
    @objc private func eraseAll() { onEraseAll?() }
}

// MARK: - 待办里的一条文字 (荧光笔模式专用)

/// 复用文字便签那套 TextKit 视图来渲染单条待办, 荧光笔因此在待办上
/// 也是逐字拖抹 + 退格擦除, 而不是整条涂。范围要在「本条局部」和
/// 「note.text 全局」之间来回换算, baseOffset 就是这条正文的起点。
///
/// 平时可编辑、荧光笔模式只读可涂、预览模式纯只读 —— 三种状态都走这里,
/// 高亮才能一直看得见 (换回 SwiftUI 的 Text/TextField 就画不出局部底色了)。
struct HighlightableLine: NSViewRepresentable {
    /// 待办正文 18pt (和选框同号), 加粗和高亮都跟这个走
    static let fontSize: CGFloat = 18

    let text: String
    let baseOffset: Int
    @Binding var highlights: [TextHighlight]
    @Binding var bolds: [TextHighlight]
    let theme: NoteTheme
    let done: Bool
    let painting: Bool    // 荧光笔模式: 只读 + 可涂
    let editable: Bool    // 平时: 可以直接改字
    /// 这一条是否该抢焦点 (回车新建下一条后把光标挪过来)
    var shouldFocus: Bool = false
    /// 焦点已经抢到手, 通知上层把标记清掉
    var onFocusHandled: () -> Void = {}
    /// 在条内按回车: 上层负责在该条后面插一条新的
    var onNewLine: () -> Void = {}
    /// 这一条开始/结束编辑 —— 空条目失焦后要靠它变淡
    var onEditingChanged: (Bool) -> Void = { _ in }
    var onEdit: (String) -> Void
    var onExitMode: () -> Void
    /// 编辑真正结束 (失焦) —— 上层据此判断: 只有"已有内容被改过"才把日期归到今天;
    /// 空条目 (回车插出来的行) 第一次写入不算改动, 保留继承来的日期
    var onEditingEnded: ((_ modified: Bool, _ beganEmpty: Bool) -> Void)? = nil
    /// 本条实际量出来的行高 (换行后比 22 大) —— 上层拿它给这一行定高,
    /// 长条目才会撑开自己, 不会压到下一条
    var onMeasured: (CGFloat) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> HighlighterTextView {
        let tv = HighlighterTextView()
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.importsGraphics = false
        tv.drawsBackground = false
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.allowsUndo = true
        tv.textStorage?.delegate = context.coordinator

        let c = context.coordinator
        tv.onPaint = { [weak c] in c?.paint($0) }
        tv.onErase = { [weak c] in c?.erase($0) }
        tv.onEraseSelection = { [weak c] in c?.eraseSelection($0) }
        tv.onEraseAll = { [weak c] in c?.eraseAll() }
        tv.onModeChange = { [weak c] enabled in if !enabled { c?.parent.onExitMode() } }
        tv.hasHighlight = { [weak c] in c?.hasHighlight(in: $0) ?? false }
        tv.onToggleBold = { [weak c] in c?.toggleBold($0) }
        tv.isBold = { [weak c] in c?.isBoldSelection($0) ?? false }
        // 量高结果报给上层: 宿主每次把新的 frame 套上时, 用最新的回调
        tv.onMeasured = { h in c.parent.onMeasured(h) }

        context.coordinator.textView = tv
        context.coordinator.render(tv)
        return tv
    }

    func updateNSView(_ tv: HighlighterTextView, context: Context) {
        context.coordinator.parent = self
        tv.highlighterColor = theme.highlighter
        context.coordinator.render(tv)
        // 回调要跟着 parent 走 (parent 每次 body 重算都是新实例)
        tv.onMeasured = { [weak coordinator = context.coordinator] h in coordinator?.parent.onMeasured(h) }
        // 回车新建下一条后, 把光标请到那一条上
        if shouldFocus, tv.window?.firstResponder !== tv {
            DispatchQueue.main.async {
                guard let tv = context.coordinator.textView, let win = tv.window else { return }
                win.makeFirstResponder(tv)
                let end = (tv.string as NSString).length
                tv.setSelectedRange(NSRange(location: end, length: 0))
                context.coordinator.parent.onFocusHandled()
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HighlighterTextView,
                      context: Context) -> CGSize? {
        guard let container = nsView.textContainer, let lm = nsView.layoutManager else { return nil }
        // 优先信任提案宽度 —— 宿主(窗口)拉宽时, 提案带着新的可用宽度来,
        // 跟着它算高度并返回这个宽度, 宿主才会把文本视图放大、折行点才跟着移动。
        // (上一版反过来优先用 bounds: 窗口拉宽时 bounds 还是旧值, 宿主把视图钉死在
        //  旧宽度, 文字就不跟随变宽了 —— 用户实测发现的 bug)
        // 提案没给 (nil/非有限) 时才退回实际 bounds; bounds 也还没落位就用 200 兜底。
        var width: CGFloat? = proposal.width
        if let pw = width, !(pw.isFinite && pw > 1) { width = nil }
        if width == nil, nsView.bounds.width > 1 { width = nsView.bounds.width }
        let w = width ?? 200
        container.containerSize = NSSize(width: w, height: .greatestFiniteMagnitude)
        lm.ensureLayout(for: container)
        // 只算, 不触发任何 AppKit 的固有尺寸失效 —— 在量尺寸的回调里再量尺寸
        // (invalidateIntrinsicContentSize) 会让 AppKit 和 SwiftUI 互相追着量, 死循环,
        // 整个 App 卡死。宽度变化/内容变化后的补报由 setFrameSize/didChangeText 的
        // measureAndReport 负责, 那俩都在下一个 runloop 跑, 不在布局路径里。
        return CGSize(width: w, height: max(22, ceil(lm.usedRect(for: container).height)))
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: HighlightableLine
        weak var textView: HighlighterTextView?
        private var syncing = false
        private var lastSyncedText: String?
        /// 本次编辑会话开始时的文本 —— 结束时拿它判断"到底改没改"
        private var editingBeginText: String?

        init(_ parent: HighlightableLine) { self.parent = parent }

        /// 荧光笔模式和预览下不许改字; 回车不在条内换行, 而是让上层新建下一条
        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange,
                      replacementString: String?) -> Bool {
            guard parent.editable, !parent.painting else { return false }
            guard let s = replacementString else { return true }
            if s == "\n" || s == "\r" {
                // 不能在 TextKit 的回调里同步改 SwiftUI 状态, 挪到下一个 runloop
                DispatchQueue.main.async { self.parent.onNewLine() }
                return false
            }
            // 粘贴进来的多行文本仍然拒掉, 免得一条待办被撑成好几行
            return !s.contains("\n")
        }

        func textDidChange(_ notification: Notification) {
            guard !syncing, let tv = textView else { return }
            lastSyncedText = tv.string
            parent.onEdit(tv.string)
        }

        /// 开始编辑: 告诉上层"这一条在编辑中" (空条目这时不该变淡),
        /// 同时记下起点文本, 结束时判断这次到底改没改
        func textDidBeginEditing(_ notification: Notification) {
            editingBeginText = textView?.string
            let cb = parent.onEditingChanged
            DispatchQueue.main.async { cb(true) }
        }

        /// 结束编辑: 空条目会因此变淡;
        /// 汇报"改没改、起点是不是空条目" —— 只有"已有内容被改动"才触发上层的归日期
        func textDidEndEditing(_ notification: Notification) {
            let cb = parent.onEditingChanged
            let endText = textView?.string ?? ""
            let begin = editingBeginText ?? ""
            editingBeginText = nil
            let modified = !(endText.trimmingCharacters(in: .whitespaces)
                            == begin.trimmingCharacters(in: .whitespaces))
            let beganEmpty = begin.trimmingCharacters(in: .whitespaces).isEmpty
            DispatchQueue.main.async {
                cb(false)
                self.parent.onEditingEnded?(modified, beganEmpty)
            }
        }

        /// 条内打字要把本条的高亮跟着挪, 换算成全局范围后交给共用的平移逻辑
        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                         range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters), !syncing, parent.editable else { return }
            let replaced = NSRange(location: editedRange.location + parent.baseOffset,
                                   length: max(0, editedRange.length - delta))
            let shifted = parent.highlights.shifting(replacing: replaced, newLength: editedRange.length)
            if shifted != parent.highlights { parent.highlights = shifted }
            let shiftedBolds = parent.bolds.shifting(replacing: replaced, newLength: editedRange.length)
            if shiftedBolds != parent.bolds { parent.bolds = shiftedBolds }
        }

        func render(_ tv: HighlighterTextView) {
            tv.highlightMode = parent.painting
            // 已完成的那条不给编辑, 也不给选中, 好让点击穿透去取消勾选
            tv.isEditable = parent.editable && !parent.done
            tv.isSelectable = parent.painting || (parent.editable && !parent.done)
            // 同主编辑器: 只有内容真的来自外部才回灌, 否则会在 TextKit
            // 处理编辑的过程中重入改写, 把这一条的输入卡死。
            if tv.string != parent.text, parent.text != lastSyncedText {
                syncing = true
                let caret = tv.selectedRange().location
                tv.string = parent.text
                syncing = false
                lastSyncedText = parent.text
                tv.setSelectedRange(
                    NSRange(location: min(caret, (parent.text as NSString).length), length: 0))
            }
            let full = NSRange(location: 0, length: (parent.text as NSString).length)
            let size = HighlightableLine.fontSize
            tv.textStorage?.setAttributes([
                .font: NSFont.systemFont(ofSize: size),
                .foregroundColor: parent.theme.text.withAlphaComponent(parent.done ? 0.4 : 1),
                .strikethroughStyle: parent.done ? NSUnderlineStyle.single.rawValue : 0,
                .strikethroughColor: parent.theme.text.withAlphaComponent(0.45)
            ], range: full)
            tv.typingAttributes = [
                .font: NSFont.systemFont(ofSize: size),
                .foregroundColor: parent.theme.text.withAlphaComponent(parent.done ? 0.4 : 1)
            ]
            tv.insertionPointColor = parent.theme.accent

            for local in localRanges(of: parent.bolds, in: full.length) {
                tv.textStorage?.addAttribute(
                    .font, value: NSFont.boldSystemFont(ofSize: size), range: local)
            }
            guard let lm = tv.layoutManager else { return }
            lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
            for local in localRanges(of: parent.highlights, in: full.length) {
                lm.addTemporaryAttribute(.backgroundColor,
                                         value: parent.theme.highlighter, forCharacterRange: local)
            }
        }

        func paint(_ local: NSRange) { apply(parent.highlights.adding(global(local)), "涂色") }
        func erase(_ local: NSRange) { apply(parent.highlights.removing(global(local)), "擦除高亮") }

        func eraseSelection(_ selection: NSRange) {
            if selection.length > 0 { erase(selection); return }
            let point = selection.location + parent.baseOffset
            if let h = parent.highlights.first(where: { NSLocationInRange(point, $0.range) }) {
                apply(parent.highlights.removing(h.range), "擦除高亮")
            }
        }

        /// 待办的「清空全部」清的是整张便签, 跟文字便签一致
        func eraseAll() { apply([], "清空高亮") }

        func isBoldSelection(_ local: NSRange) -> Bool { parent.bolds.coversFully(global(local)) }

        func toggleBold(_ local: NSRange) {
            guard local.length > 0 else { return }
            let g = global(local)
            if parent.bolds.coversFully(g) {
                applyBolds(parent.bolds.removing(g), "取消加粗")
            } else {
                applyBolds(parent.bolds.adding(g), "加粗")
            }
        }

        private func applyBolds(_ new: [TextHighlight], _ actionName: String) {
            let old = parent.bolds
            guard old != new else { return }
            parent.bolds = new
            textView?.undoManager?.registerUndo(withTarget: self) { $0.applyBolds(old, actionName) }
            textView?.undoManager?.setActionName(actionName)
            if let textView { render(textView) }
        }

        func hasHighlight(in selection: NSRange) -> Bool {
            let g = global(selection)
            if g.length == 0 {
                return parent.highlights.contains { NSLocationInRange(g.location, $0.range) }
            }
            return parent.highlights.covers(g)
        }

        private func apply(_ new: [TextHighlight], _ actionName: String) {
            let old = parent.highlights
            guard old != new else { return }
            parent.highlights = new
            textView?.undoManager?.registerUndo(withTarget: self) { $0.apply(old, actionName) }
            textView?.undoManager?.setActionName(actionName)
            if let textView { render(textView) }
        }

        private func global(_ r: NSRange) -> NSRange {
            NSRange(location: r.location + parent.baseOffset, length: r.length)
        }

        /// 整张便签的标记里, 落在这一条上的部分, 换算成本条的局部范围
        private func localRanges(of marks: [TextHighlight], in length: Int) -> [NSRange] {
            let line = NSRange(location: parent.baseOffset, length: length)
            return marks.compactMap {
                let overlap = NSIntersectionRange($0.range, line)
                guard overlap.length > 0 else { return nil }
                return NSRange(location: overlap.location - parent.baseOffset, length: overlap.length)
            }
        }
    }
}

// MARK: - 待办清单视图 (带周历筛选器)
//
// 上半部: 本周 7 天 (周一~周日), 点某天切换到它;
//         有未完成任务的日子格子上多一个小圆点。
// 下半部: 选中日期的待办条目 + 「未排期」区 (没有归属日期的条目)。
// 新添加的待办默认归属当前选中的日期。
// 选中日期是纯 UI 状态 (@State), 不持久化 —— 每次打开便签都回到今天。

struct TodoListView: View {
    @ObservedObject var note: Note
    var readOnly: Bool = false   // 预览模式: 隐藏添加/删除, 文字不可编辑
    var highlighterMode: Bool = false
    @State private var newItemText = ""
    @FocusState private var addFieldFocused: Bool
    @State private var selectedDay: Date = .now
    /// 回车新建下一条之后, 光标要落到哪一条上 (用完即清)
    @State private var focusTodoIndex: Int?
    /// 正在编辑哪一条 (空条目在失焦后会变淡, 编辑中保持正常)
    @State private var editingTodoIndex: Int?
    /// 点「M月」字样切换: 只看未排期; 再点一次(或点任意日期格/⟲)回到按日期筛选
    @State private var showUnscheduledOnly: Bool = false

    /// 荧光笔模式下待办同样是只读的
    private var locked: Bool { readOnly || highlighterMode }

    private var accent: Color { Color(nsColor: note.theme.accent) }
    private var ink: Color { Color(nsColor: note.theme.text) }

    private var greg: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 1   // 周日起始
        c.locale = Locale(identifier: "zh_CN")
        return c
    }

    /// 选中日期所在周 (周一开始), 翻周 = 选中日期 ±7 天
    private var weekDays: [Date] {
        guard let interval = greg.dateInterval(of: .weekOfYear, for: selectedDay) else { return [] }
        var out: [Date] = []
        var cur = interval.start
        for _ in 0..<7 {
            out.append(cur)
            cur = greg.date(byAdding: .day, value: 1, to: cur) ?? cur
        }
        return out
    }

    private var pendingSet: Set<Date> { note.pendingDays(in: weekDays) }

    private var dayItems: [(index: Int, item: TodoItem)] {
        note.todos(on: selectedDay)
    }

    private var unassigned: [(index: Int, item: TodoItem)] {
        note.todoItems.enumerated()
            .filter { $0.element.due == nil }
            .map { (index: $0.offset, item: $0.element) }
    }

    /// 左侧只显示月份 (如 "9月"), 比 "9/13 – 9/19" 清爽
    private var monthLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月"
        return f.string(from: selectedDay)
    }

    var body: some View {
        VStack(spacing: 0) {
            weekPicker
            divider
            // 添加行固定在列表上方 (用户习惯: 新建/更新都在最上面, 不用滚到底部)
            // 预览/荧光笔模式下隐藏
            if !locked {
                HStack(spacing: 7) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(ink.opacity(0.3))
                    TextField("添加待办, 按回车确认 (默认归到选中这天, 排在最上面)",
                              text: $newItemText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .foregroundStyle(ink)
                        .focused($addFieldFocused)
                        .onSubmit {
                            // 新待办默认归到周历选中的那天 (不是"今天"), 置顶
                            withAnimation(.spring(duration: 0.3)) {
                                note.addTodo(newItemText,
                                             due: greg.startOfDay(for: selectedDay))
                            }
                            newItemText = ""
                            addFieldFocused = true   // 连续输入
                        }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                divider
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    if showUnscheduledOnly {
                        // 未排期视图: 点「M月」进来的, 只看没排日期的条目 (不压暗, 正常显示)
                        if unassigned.isEmpty {
                            Text("没有未排期的待办")
                                .font(.system(size: 12))
                                .foregroundStyle(ink.opacity(0.35))
                                .padding(.vertical, 10)
                        } else {
                            ForEach(unassigned, id: \.index) { entry in
                                todoRow(index: entry.index, item: entry.item)
                            }
                        }
                    } else {
                        if dayItems.isEmpty && unassigned.isEmpty {
                            // 空状态提示
                            Text(selectedDay == greg.startOfDay(for: .now)
                                 ? "今天没有待办, 加一条吧"
                                 : "这一天没有待办 (点「\u{ff08}M月\u{ff09}」看所有未排期)")
                                .font(.system(size: 12))
                                .foregroundStyle(ink.opacity(0.35))
                                .padding(.vertical, 10)
                        } else {
                            ForEach(dayItems, id: \.index) { entry in
                                todoRow(index: entry.index, item: entry.item)
                            }
                            // 未排期区 (仅当按日期筛选、且确实有未排期条目时才单独列出;
                            // 未排期视图里它们已是主体, 不再压暗)
                            if !unassigned.isEmpty {
                                Text("未排期")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(ink.opacity(0.4))
                                    .padding(.top, 6)
                                    .padding(.bottom, 2)
                                ForEach(unassigned, id: \.index) { entry in
                                    todoRow(index: entry.index, item: entry.item, dimmed: true)
                                }
                            }
                        }
                    }
                }
                .padding(13)
            }
        }
    }

    // MARK: 周历筛选器

    private var weekPicker: some View {
        HStack(spacing: 8) {
            // 左侧两颗小按钮: 上一周 / 下一周
            HStack(spacing: 3) {
                squareButton("chevron.left", help: "上一周", size: 17) { shiftWeek(-1) }
                squareButton("chevron.right", help: "下一周", size: 17) { shiftWeek(1) }
            }

            // 月份 (如 "9月"): 点一下 → 下方列表换成「所有未排期」; 再点一次 → 换回按日期筛选。
            // 字样始终不变 (周历行外观保持原样), 只在激活时下方加一道短下划线做提示
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showUnscheduledOnly.toggle()
                }
            } label: {
                Text(monthLabel)
                    .font(.system(size: 19, weight: .semibold, design: .serif))
                    .foregroundStyle(ink.opacity(0.75))
                    .fixedSize()
                    .padding(.bottom, 1)
                    .overlay(alignment: .bottom) {
                        if showUnscheduledOnly {
                            Capsule().fill(accent).frame(height: 2).offset(y: 2)
                        }
                    }
            }
            .buttonStyle(.plain)
            .help(showUnscheduledOnly ? "回到按日期筛选" : "看所有未排期的待办")

            // 7 个日期格: 点一下切换选中日 (未排期模式下变暗, 点它自动回到日期筛选)
            HStack(spacing: 3) {
                ForEach(Array(weekDays.enumerated()), id: \.offset) { i, day in
                    dayCell(day, weekdayIndex: i)
                }
            }
            .frame(maxWidth: .infinity)
            .opacity(showUnscheduledOnly ? 0.35 : 1)

            // 右侧一颗: 回到今天 (同时退出未排期模式)
            squareButton("arrow.counterclockwise",
                         help: "回到今天",
                         active: !showUnscheduledOnly && greg.isDate(selectedDay, inSameDayAs: .now)) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showUnscheduledOnly = false
                    selectedDay = .now
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    /// 周历两侧的小按钮: 圆角方块, 尺寸统一由 size 决定
    private func squareButton(_ icon: String, help: String,
                              active: Bool = false,
                              size: CGFloat = 22,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(active ? accent : ink.opacity(0.42))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                        .fill(active ? accent.opacity(0.14) : ink.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func dayCell(_ day: Date, weekdayIndex: Int) -> some View {
        let label = weekdayLabels[weekdayIndex]
        let isToday = greg.isDate(day, inSameDayAs: .now)
        let isSelected = greg.isDate(day, inSameDayAs: selectedDay)
        let hasPending = pendingSet.contains(greg.startOfDay(for: day))
        let isWeekend = weekdayIndex == 0 || weekdayIndex == 6
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showUnscheduledOnly = false   // 点日期格 = 回到按日期筛选
                selectedDay = day
            }
        } label: {
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(isWeekend ? accent.opacity(0.7) : ink.opacity(0.45))
                Text("\(greg.component(.day, from: day))")
                    .font(.system(size: 12, weight: isToday ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? .white :
                                     (isToday ? accent : ink))
                // 小圆点: 该天有未完成任务
                Circle()
                    .fill(hasPending ? accent : .clear)
                    .frame(width: 3.5, height: 3.5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(accent.opacity(0.9))
                } else if isToday {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(accent.opacity(0.12))
                }
            }
        }
        .buttonStyle(.plain)
        .help("\(day) — \(hasPending ? "有未完成" : "无")")
    }

    private func shiftWeek(_ delta: Int) {
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedDay = greg.date(byAdding: .day, value: 7 * delta,
                                    to: selectedDay) ?? selectedDay
        }
    }

    private var divider: some View {
        Rectangle().fill(ink.opacity(0.08)).frame(height: 0.5)
    }

    @ViewBuilder
    private func todoRow(index: Int, item: TodoItem, dimmed: Bool = false) -> some View {
        // 空条目 (回车新建出来的那一行): 没在编辑时整行变淡, 免得空圆点太扎眼
        let fadedEmpty = item.text.isEmpty && editingTodoIndex != index && !item.done
        return HStack(alignment: .top, spacing: 8) {
            // 圆形勾选框 (18pt, 和正文同号)
            Button {
                withAnimation(.spring(duration: 0.3)) { note.toggleTodo(index) }
            } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(item.done ? accent.opacity(0.9) : ink.opacity(0.32))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .disabled(highlighterMode || dimmed && locked)

            // 三种状态都走同一个视图, 高亮才能一直看得见
            if let range = note.todoContentRange(index) {
                HighlightableLine(
                    text: item.text,
                    baseOffset: range.location,
                    highlights: $note.highlights,
                    bolds: $note.bolds,
                    theme: note.theme,
                    done: item.done,
                    painting: highlighterMode,
                    editable: !locked && !dimmed,
                    shouldFocus: focusTodoIndex == index,
                    onFocusHandled: {
                        if focusTodoIndex == index { focusTodoIndex = nil }
                    },
                    onNewLine: { insertTodoAfter(index) },
                    onEditingChanged: { editing in
                        if editing {
                            editingTodoIndex = index
                        } else if editingTodoIndex == index {
                            editingTodoIndex = nil
                        }
                    },
                    onEdit: { note.setTodoText(index, $0) },
                    onExitMode: { note.highlighterMode = false },
                    onEditingEnded: { modified, beganEmpty in
                        // 已有内容被改过 → 日期归到今天 (位置不动);
                        // 空条目第一次写入不算改动, 保留继承来的日期
                        if modified, !beganEmpty {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                note.touchTodo(at: index)
                            }
                        }
                    },
                    onMeasured: { h in
                        // 只有量出来的高真变了才写状态, 否则布局永远在转
                        if abs((measuredHeights[index] ?? 0) - h) > 0.5 {
                            measuredHeights[index] = h
                        }
                    })
                    .onTapGesture {
                        // 已完成的那条是只读的, 点击会落到这里: 点文字取消勾选
                        guard !locked, !dimmed, item.done else { return }
                        withAnimation(.spring(duration: 0.3)) { note.toggleTodo(index) }
                    }
                    .opacity(dimmed ? 0.75 : 1)
                    // 占满剩余宽度 → 按便签宽窄自动折行
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // 用 TextKit 实测的行高给这一行定高: 长条目换几行就长几行,
                    // 不会多出来压住下一条 (默认 22 = 单行)
                    .frame(height: measuredHeights[index] ?? 22, alignment: .top)
            } else {
                Text(item.text).font(.system(size: 16))
                    .foregroundStyle(ink.opacity(dimmed ? 0.75 : 1))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)

            // 排期按钮放在最右: 未排期 = 灰色空心日历; 已排期 = 彩色实心日历
            if !locked {
                Button {
                    showScheduleMenu = (index, item.due)
                } label: {
                    Image(systemName: item.due == nil ? "calendar.badge.plus" : "calendar")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(item.due == nil ? ink.opacity(0.25) : accent.opacity(0.75))
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(item.due == nil ? Color.clear : accent.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .help(item.due == nil ? "排期: 点我选一天" : "改期: 点我换一天; 右键可删除")
            }
        }
        .padding(.vertical, 4)
        .opacity(fadedEmpty ? 0.3 : 1)
        .animation(.easeOut(duration: 0.18), value: fadedEmpty)
        // 排期菜单弹出
        .popover(
            isPresented: Binding(
                get: { showScheduleMenu?.0 == index },
                set: { if !$0 { showScheduleMenu = nil } }
            ),
            arrowEdge: .trailing
        ) {
            scheduleMenu(for: showScheduleMenu?.0 ?? -1, currentDue: showScheduleMenu?.1)
                .frame(minWidth: 180)
                .padding(8)
        }
        .contextMenu {
            if !locked {
                Menu("改到...") {
                    ForEach(Array(weekDays.enumerated()), id: \.offset) { _, day in
                        Button(dayTitle(day)) { moveDue(index, to: day) }
                    }
                    Divider()
                    Button("清除日期") { clearDue(index) }
                }
                // 原来的小叉叉删掉了, 删除收进右键菜单, 功能不丢
                Button("删除这一条") {
                    withAnimation(.spring(duration: 0.3)) { note.removeTodo(index) }
                }
            }
        }
    }

    /// 每条待办实测的行高 (按当前便签宽度排版后 TextKit 报上来的)
    @State private var measuredHeights: [Int: CGFloat] = [:]
    @State private var showScheduleMenu: (Int, Date?)?

    private func scheduleMenu(for index: Int, currentDue: Date?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("排期到…")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(ink.opacity(0.5))
            ForEach(Array(weekDays.enumerated()), id: \.offset) { _, day in
                let isSelected = currentDue != nil && greg.isDate(day, inSameDayAs: currentDue!)
                Button(action: { moveDue(index, to: day); showScheduleMenu = nil }) {
                    HStack {
                        Image(systemName: isSelected ? "checkmark" : "circle")
                            .font(.system(size: 11))
                            .foregroundStyle(isSelected ? accent : ink.opacity(0.3))
                        Text(dayTitle(day)).font(.system(size: 13))
                        if greg.isDate(day, inSameDayAs: .now) {
                            Text("今天").font(.system(size: 11)).foregroundStyle(accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Divider()
            HStack {
                Button("清除日期") {
                    clearDue(index); showScheduleMenu = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(ink.opacity(0.5))
            }
        }
    }

    private func dayTitle(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M/d (EEE)"
        return f.string(from: d)
    }

    /// 在条内按回车: 这一条后面插一条空白待办, 光标跟着过去 (连续录入用)
    private func insertTodoAfter(_ index: Int) {
        var items = note.todoItems
        guard items.indices.contains(index) else { return }
        // 新条目沿用本条日期; 本条没排期就归今天
        let due = items[index].due ?? greg.startOfDay(for: .now)
        let at = note.insertTodo(after: index, due: due)
        withAnimation(.spring(duration: 0.3)) { focusTodoIndex = at }
    }

    private func moveDue(_ index: Int, to day: Date) {
        var items = note.todoItems
        guard items.indices.contains(index) else { return }
        items[index].due = greg.startOfDay(for: day)
        // 重写 text + dueDates, 高亮跟着平移, 自动保存
        note.rebuildTextForEditing(items)
    }

    private func clearDue(_ index: Int) {
        var items = note.todoItems
        guard items.indices.contains(index) else { return }
        items[index].due = nil
        note.rebuildTextForEditing(items)
    }
}

// MARK: - 简易 Markdown 渲染

/// 按行渲染: 支持 #/##/### 标题、- 列表、> 引用,
/// 行内的 **粗体** `代码` *斜体* [链接](url) 交给系统 AttributedString 解析。
struct MarkdownText: View {
    let source: String
    var highlights: [TextHighlight] = []
    var bolds: [TextHighlight] = []
    let theme: NoteTheme
    var onToggleTask: ((Int) -> Void)? = nil   // 参数是行号

    private var ink: Color { Color(nsColor: theme.text) }
    private var accent: Color { Color(nsColor: theme.accent) }

    private struct SourceLine: Identifiable {
        let index: Int
        let text: String
        let utf16Offset: Int
        var id: Int { index }
    }

    private var lines: [SourceLine] {
        let parts = source.components(separatedBy: "\n")
        var offset = 0
        return parts.enumerated().map { index, line in
            defer { offset += (line as NSString).length + (index < parts.count - 1 ? 1 : 0) }
            return SourceLine(index: index, text: line, utf16Offset: offset)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines) { line in
                renderLine(line.text, at: line.index, sourceOffset: line.utf16Offset)
            }
        }
    }

    @ViewBuilder
    private func renderLine(_ line: String, at lineIndex: Int, sourceOffset: Int) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let leadingOffset = trimmed.isEmpty ? 0 : (line as NSString).range(of: trimmed).location
        if trimmed.isEmpty {
            Text(" ").font(.system(size: 6))
        } else if trimmed.hasPrefix("### ") {
            inline(String(trimmed.dropFirst(4)), sourceOffset: sourceOffset + leadingOffset + 4)
                .font(.system(size: 15, weight: .semibold, design: .serif))
        } else if trimmed.hasPrefix("## ") {
            inline(String(trimmed.dropFirst(3)), sourceOffset: sourceOffset + leadingOffset + 3)
                .font(.system(size: 17, weight: .bold, design: .serif))
                .padding(.top, 2)
        } else if trimmed.hasPrefix("# ") {
            inline(String(trimmed.dropFirst(2)), sourceOffset: sourceOffset + leadingOffset + 2)
                .font(.system(size: 21, weight: .bold, design: .serif))
                .padding(.bottom, 2)
        } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
            HStack(alignment: .top, spacing: 6) {
                Button {
                    withAnimation(.spring(duration: 0.3)) { onToggleTask?(lineIndex) }
                } label: {
                    Image(systemName: "checkmark.square.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(accent.opacity(0.85))
                        .padding(.top, 2)
                }
                .buttonStyle(.plain)
                .help("取消完成")
                inline(String(trimmed.dropFirst(6)), sourceOffset: sourceOffset + leadingOffset + 6)
                    .font(.system(size: 14))
                    .strikethrough(true, color: ink.opacity(0.45))
                    .opacity(0.5)
            }
        } else if trimmed.hasPrefix("- [ ] ") {
            HStack(alignment: .top, spacing: 6) {
                Button {
                    withAnimation(.spring(duration: 0.3)) { onToggleTask?(lineIndex) }
                } label: {
                    Image(systemName: "square")
                        .font(.system(size: 12))
                        .foregroundStyle(ink.opacity(0.35))
                        .padding(.top, 2)
                }
                .buttonStyle(.plain)
                .help("标记完成")
                inline(String(trimmed.dropFirst(6)), sourceOffset: sourceOffset + leadingOffset + 6)
                    .font(.system(size: 14))
            }
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 7) {
                Text("•").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accent.opacity(0.7))
                inline(String(trimmed.dropFirst(2)), sourceOffset: sourceOffset + leadingOffset + 2)
                    .font(.system(size: 14))
            }
        } else if trimmed.hasPrefix("> ") {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(accent.opacity(0.5))
                    .frame(width: 2.5)
                inline(String(trimmed.dropFirst(2)), sourceOffset: sourceOffset + leadingOffset + 2)
                    .font(.system(size: 14))
                    .italic()
                    .opacity(0.7)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else if trimmed == "---" || trimmed == "***" {
            Rectangle().fill(ink.opacity(0.12)).frame(height: 0.5)
                .padding(.vertical, 3)
        } else {
            inline(line, sourceOffset: sourceOffset).font(.system(size: 14)).lineSpacing(4.5)
        }
    }

    private func inline(_ s: String, sourceOffset: Int) -> Text {
        guard var attr = try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return Text(s).foregroundColor(ink)
        }
        paint(&attr, source: s, sourceOffset: sourceOffset)
        return Text(attr).foregroundColor(ink)
    }

    /// 渲染会吃掉 **、`、[]() 这些语法字符, 结果串是源码串的子序列。
    /// 逐字对齐求出「渲染结果下标 → 源码下标」的映射, 才能把高亮落在正确的字上;
    /// 按文字内容去搜索会在同一行出现重复词时涂错地方。
    private func paint(_ attr: inout AttributedString, source: String, sourceOffset: Int) {
        let line = NSRange(location: sourceOffset, length: (source as NSString).length)
        let hits = highlights.filter { NSIntersectionRange($0.range, line).length > 0 }
        let boldHits = bolds.filter { NSIntersectionRange($0.range, line).length > 0 }
        guard !hits.isEmpty || !boldHits.isEmpty else { return }

        let src = source as NSString
        let plain = String(attr.characters)
        let plainNS = plain as NSString
        var map: [Int] = []
        var cursor = 0
        for i in 0..<plainNS.length {
            let ch = plainNS.character(at: i)
            while cursor < src.length && src.character(at: cursor) != ch { cursor += 1 }
            guard cursor < src.length else { break }
            map.append(cursor)
            cursor += 1
        }

        let chars = attr.characters
        func resolved(_ hit: TextHighlight) -> Range<AttributedString.Index>? {
            let overlap = NSIntersectionRange(hit.range, line)
            let local = NSRange(location: overlap.location - sourceOffset, length: overlap.length)
            let inside = map.indices.filter {
                local.location <= map[$0] && map[$0] < NSMaxRange(local)
            }
            guard let first = inside.first, let last = inside.last,
                  let r = Range(NSRange(location: first, length: last - first + 1), in: plain)
            else { return nil }
            let lo = chars.index(chars.startIndex,
                                 offsetBy: plain.distance(from: plain.startIndex, to: r.lowerBound))
            let hi = chars.index(lo, offsetBy: plain.distance(from: r.lowerBound, to: r.upperBound))
            return lo..<hi
        }
        for hit in hits {
            guard let r = resolved(hit) else { continue }
            attr[r].backgroundColor = Color(nsColor: theme.highlighter)
        }
        for hit in boldHits {
            guard let r = resolved(hit) else { continue }
            attr[r].inlinePresentationIntent = .stronglyEmphasized
        }
    }
}
