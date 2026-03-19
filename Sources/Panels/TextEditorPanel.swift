import Foundation
import Combine
import AppKit

/// A panel that displays and edits a text file with live file-watching.
@MainActor
final class TextEditorPanel: Panel, ObservableObject {
    let id: UUID
    let panelType: PanelType = .textEditor

    /// Absolute path to the file being edited.
    let filePath: String

    /// The workspace this panel belongs to.
    private(set) var workspaceId: UUID

    /// Current text content (read-write).
    @Published var content: String = ""

    /// Title shown in the tab bar (filename).
    @Published private(set) var displayTitle: String = ""

    /// SF Symbol icon for the tab bar.
    var displayIcon: String? { "doc.text" }

    /// Whether the content has unsaved changes.
    @Published private(set) var isDirty: Bool = false

    /// Whether the file has been modified on disk while there are unsaved edits.
    @Published private(set) var hasExternalChange: Bool = false

    /// Whether the file has been deleted or is unreadable.
    @Published private(set) var isFileUnavailable: Bool = false

    /// Token incremented to trigger focus flash animation.
    @Published private(set) var focusFlashToken: Int = 0

    /// Callback to make the NSTextView first responder.
    var focusTextView: (() -> Void)?

    // MARK: - File watching

    private nonisolated(unsafe) var fileWatchSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var isClosed: Bool = false
    private let watchQueue = DispatchQueue(label: "com.cmux.text-editor-file-watch", qos: .utility)

    private static let maxReattachAttempts = 6
    private static let reattachDelay: TimeInterval = 0.5

    // MARK: - Init

    init(workspaceId: UUID, filePath: String) {
        self.id = UUID()
        self.workspaceId = workspaceId
        self.filePath = filePath
        self.displayTitle = (filePath as NSString).lastPathComponent

        loadFileContent()
        startFileWatcher()
        if isFileUnavailable && fileWatchSource == nil {
            scheduleReattach(attempt: 1)
        }
    }

    // MARK: - Panel protocol

    func focus() {
        focusTextView?()
    }

    func unfocus() {
        // No-op; NSTextView resignFirstResponder is handled by AppKit.
    }

    func close() {
        isClosed = true
        stopFileWatcher()
    }

    func triggerFlash() {
        guard NotificationPaneFlashSettings.isEnabled() else { return }
        focusFlashToken += 1
    }

    // MARK: - Public API

    /// Update content from the view layer (NSTextView delegate).
    func setContentFromEditor(_ newContent: String) {
        guard content != newContent else { return }
        content = newContent
        isDirty = true
    }

    /// Save content to disk atomically. UTF-8 only.
    func save() throws {
        guard let data = content.data(using: .utf8) else {
            throw TextEditorSaveError.encodingFailed
        }
        try data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
        isDirty = false
        hasExternalChange = false
    }

    /// Reload content from disk, discarding any unsaved edits.
    func reloadFromDisk() {
        loadFileContent()
        isDirty = false
        hasExternalChange = false
    }

    // MARK: - File I/O

    private func loadFileContent() {
        do {
            let newContent = try String(contentsOfFile: filePath, encoding: .utf8)
            content = newContent
            isFileUnavailable = false
        } catch {
            if let data = FileManager.default.contents(atPath: filePath),
               let decoded = String(data: data, encoding: .isoLatin1) {
                content = decoded
                isFileUnavailable = false
            } else {
                isFileUnavailable = true
            }
        }
    }

    // MARK: - File watcher via DispatchSource

    private func startFileWatcher() {
        stopFileWatcher()
        let fd = open(filePath, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: watchQueue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                DispatchQueue.main.async {
                    self.stopFileWatcher()
                    if self.isDirty {
                        self.hasExternalChange = true
                        // Try to reattach watcher for future events.
                        if FileManager.default.fileExists(atPath: self.filePath) {
                            self.startFileWatcher()
                        } else {
                            self.isFileUnavailable = true
                            self.scheduleReattach(attempt: 1)
                        }
                    } else {
                        self.loadFileContent()
                        if self.isFileUnavailable {
                            self.scheduleReattach(attempt: 1)
                        } else {
                            self.startFileWatcher()
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    if self.isDirty {
                        self.hasExternalChange = true
                    } else {
                        self.loadFileContent()
                    }
                }
            }
        }

        source.setCancelHandler {
            Darwin.close(fd)
        }

        source.resume()
        fileWatchSource = source
    }

    private func scheduleReattach(attempt: Int) {
        guard attempt <= Self.maxReattachAttempts else { return }
        watchQueue.asyncAfter(deadline: .now() + Self.reattachDelay) { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                guard !self.isClosed else { return }
                if FileManager.default.fileExists(atPath: self.filePath) {
                    self.isFileUnavailable = false
                    if !self.isDirty {
                        self.loadFileContent()
                    }
                    self.startFileWatcher()
                } else {
                    self.scheduleReattach(attempt: attempt + 1)
                }
            }
        }
    }

    private func stopFileWatcher() {
        if let source = fileWatchSource {
            source.cancel()
            fileWatchSource = nil
        }
        fileDescriptor = -1
    }

    deinit {
        fileWatchSource?.cancel()
    }
}

enum TextEditorSaveError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return String(localized: "textEditor.save.error", defaultValue: "Failed to save file")
        }
    }
}
