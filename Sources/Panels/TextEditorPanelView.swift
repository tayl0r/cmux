import AppKit
import SwiftUI
import CodeEditor

// MARK: - Text Editor Theme Settings

enum TextEditorThemeSettings {
    static let darkThemeKey = "editorThemeDark"
    static let lightThemeKey = "editorThemeLight"
    static let defaultDarkTheme = "monokai-sublime"
    static let defaultLightTheme = "github"

    /// Dark themes (background luminance < 0.5), sorted alphabetically.
    /// Derived from the bundled Highlightr v3 theme CSS files.
    static let darkThemes: [String] = [
        "a11y-dark", "agate", "an-old-hope", "androidstudio", "arta",
        "atelier-cave-dark", "atelier-dune-dark", "atelier-estuary-dark",
        "atelier-forest-dark", "atelier-heath-dark", "atelier-lakeside-dark",
        "atelier-plateau-dark", "atelier-savanna-dark", "atelier-seaside-dark",
        "atelier-sulphurpool-dark", "atom-one-dark", "atom-one-dark-reasonable",
        "codepen-embed", "darcula", "dark", "dracula", "far", "gml", "gruvbox-dark",
        "hopscotch", "hybrid", "ir-black", "isbl-editor-dark", "kimbie.dark",
        "monokai", "monokai-sublime", "nord", "obsidian", "ocean", "paraiso-dark",
        "qtcreator_dark", "railscasts", "rainbow", "shades-of-purple",
        "solarized-dark", "sunburst", "tomorrow-night", "tomorrow-night-blue",
        "tomorrow-night-eighties", "vs2015", "xcode-dark", "xt256", "zenburn"
    ]

    /// Light themes (background luminance >= 0.5), sorted alphabetically.
    /// Derived from the bundled Highlightr v3 theme CSS files.
    static let lightThemes: [String] = [
        "a11y-light", "arduino-light", "atelier-cave-light", "atelier-dune-light",
        "atelier-estuary-light", "atelier-forest-light", "atelier-heath-light",
        "atelier-lakeside-light", "atelier-plateau-light", "atelier-savanna-light",
        "atelier-seaside-light", "atelier-sulphurpool-light", "atom-one-light",
        "brown-paper", "color-brewer", "default", "docco", "foundation", "github",
        "grayscale", "gruvbox-light", "idea", "kimbie.light", "magula", "mono-blue",
        "paraiso-light", "purebasic", "qtcreator_light", "routeros",
        "solarized-light", "xcode"
    ]

    /// Display-friendly name: "monokai-sublime" → "Monokai Sublime"
    static func displayName(for theme: String) -> String {
        theme.replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

/// SwiftUI view that renders a TextEditorPanel's content with syntax highlighting.
struct TextEditorPanelView: View {
    @ObservedObject var panel: TextEditorPanel
    let isFocused: Bool
    let isVisibleInUI: Bool
    let portalPriority: Int
    let onRequestPanelFocus: () -> Void

    @State private var focusFlashOpacity: Double = 0.0
    @State private var focusFlashAnimationGeneration: Int = 0
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(TextEditorThemeSettings.darkThemeKey) private var darkTheme = TextEditorThemeSettings.defaultDarkTheme
    @AppStorage(TextEditorThemeSettings.lightThemeKey) private var lightTheme = TextEditorThemeSettings.defaultLightTheme

    var body: some View {
        Group {
            if panel.isFileUnavailable {
                fileUnavailableView
            } else {
                editorContentView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundColor)
        .overlay {
            RoundedRectangle(cornerRadius: FocusFlashPattern.ringCornerRadius)
                .stroke(cmuxAccentColor().opacity(focusFlashOpacity), lineWidth: 3)
                .shadow(color: cmuxAccentColor().opacity(focusFlashOpacity * 0.35), radius: 10)
                .padding(FocusFlashPattern.ringInset)
                .allowsHitTesting(false)
        }
        .overlay {
            if isVisibleInUI {
                TextEditorPointerObserver(onPointerDown: onRequestPanelFocus)
            }
        }
        .onChange(of: panel.focusFlashToken) { _ in
            triggerFocusFlashAnimation()
        }
    }

    // MARK: - Content

    private var editorContentView: some View {
        VStack(spacing: 0) {
            filePathHeader
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 6)

            if panel.hasExternalChange {
                externalChangeBanner
            }

            Divider()
                .padding(.horizontal, 12)

            CodeEditor(
                source: Binding(
                    get: { panel.content },
                    set: { panel.setContentFromEditor($0) }
                ),
                language: codeLanguage,
                theme: codeTheme,
                fontSize: .constant(13),
                flags: [.selectable, .editable, .smartIndent],
                autoscroll: false
            )
        }
    }

    // MARK: - Language detection

    private var codeLanguage: CodeEditor.Language {
        let ext = (panel.filePath as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .swift
        case "py": return .python
        case "js", "mjs", "cjs", "jsx": return .javascript
        case "ts", "mts", "cts", "tsx": return .typescript
        case "rb": return .ruby
        case "go": return .go
        case "rs": return .rust
        case "c", "h": return .c
        case "cpp", "cc", "cxx", "hpp": return .cpp
        case "m": return .objectivec
        case "java": return .java
        case "kt", "kts": return .init(rawValue: "kotlin")
        case "json": return .json
        case "yaml", "yml": return .yaml
        case "xml", "plist": return .xml
        case "html", "htm": return .init(rawValue: "html")
        case "css": return .css
        case "scss": return .init(rawValue: "scss")
        case "less": return .init(rawValue: "less")
        case "sh", "bash", "zsh": return .bash
        case "sql": return .sql
        case "md", "markdown": return .markdown
        case "lua": return .lua
        case "pl", "pm": return .init(rawValue: "perl")
        case "php": return .php
        case "cs": return .cs
        case "dockerfile": return .dockerfile
        default: return .init(rawValue: "plaintext")
        }
    }

    private var codeTheme: CodeEditor.ThemeName {
        CodeEditor.ThemeName(rawValue: colorScheme == .dark ? darkTheme : lightTheme)
    }

    // MARK: - Subviews

    private var filePathHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            Text(panel.filePath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if panel.isDirty {
                Circle()
                    .fill(Color.primary.opacity(0.4))
                    .frame(width: 6, height: 6)
            }
            Spacer()
        }
    }

    private var externalChangeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 12))
            Text(String(localized: "textEditor.externalChange.banner", defaultValue: "File changed on disk"))
                .font(.system(size: 12))
                .foregroundColor(.primary)
            Spacer()
            Button(String(localized: "textEditor.externalChange.reload", defaultValue: "Reload")) {
                panel.reloadFromDisk()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.1))
    }

    private var fileUnavailableView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(String(localized: "textEditor.fileUnavailable.title", defaultValue: "File unavailable"))
                .font(.headline)
                .foregroundColor(.primary)
            Text(panel.filePath)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
            Text(String(localized: "textEditor.fileUnavailable.message", defaultValue: "The file may have been moved or deleted."))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Styling

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color(nsColor: NSColor(white: 0.12, alpha: 1.0))
            : Color(nsColor: NSColor(white: 0.98, alpha: 1.0))
    }

    // MARK: - Focus Flash

    private func triggerFocusFlashAnimation() {
        focusFlashAnimationGeneration &+= 1
        let generation = focusFlashAnimationGeneration
        focusFlashOpacity = FocusFlashPattern.values.first ?? 0

        for segment in FocusFlashPattern.segments {
            DispatchQueue.main.asyncAfter(deadline: .now() + segment.delay) {
                guard focusFlashAnimationGeneration == generation else { return }
                withAnimation(focusFlashAnimation(for: segment.curve, duration: segment.duration)) {
                    focusFlashOpacity = segment.targetOpacity
                }
            }
        }
    }

    private func focusFlashAnimation(for curve: FocusFlashCurve, duration: TimeInterval) -> Animation {
        switch curve {
        case .easeIn:
            return .easeIn(duration: duration)
        case .easeOut:
            return .easeOut(duration: duration)
        }
    }
}

// MARK: - Click observer (AppKit-level, doesn't consume events)

private struct TextEditorPointerObserver: NSViewRepresentable {
    let onPointerDown: () -> Void

    func makeNSView(context: Context) -> TextEditorPointerObserverView {
        let view = TextEditorPointerObserverView()
        view.onPointerDown = onPointerDown
        return view
    }

    func updateNSView(_ nsView: TextEditorPointerObserverView, context: Context) {
        nsView.onPointerDown = onPointerDown
    }
}

final class TextEditorPointerObserverView: NSView {
    var onPointerDown: (() -> Void)?
    private var eventMonitor: Any?

    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installEventMonitor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func installEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self,
                  event.type == .leftMouseDown,
                  let window = self.window,
                  event.window === window,
                  !self.isHiddenOrHasHiddenAncestor else { return event }
            let point = self.convert(event.locationInWindow, from: nil)
            if self.bounds.contains(point) {
                DispatchQueue.main.async { [weak self] in
                    self?.onPointerDown?()
                }
            }
            return event
        }
    }
}
