import AppKit
import ApplicationServices

struct SelectionSource: Hashable, Sendable {
    let pid: pid_t
    let launchedAt: Date?
    @MainActor static var frontmost: Self? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return .init(pid: app.processIdentifier, launchedAt: app.launchDate)
    }
}

struct SelectedText: Hashable, Sendable {
    let source: SelectionSource
    let text: String
    let control: UUID?
    let range: NSRange?

    static func isValid(_ text: String) -> Bool {
        text.utf8.count <= 1_048_576 && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var quotation: String {
        text.trimmingCharacters(in: .newlines).split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { "> \($0)" }.joined(separator: "\n") + "\n\n"
    }
    func duplicates(_ other: Self) -> Bool {
        guard source == other.source, text == other.text else { return false }
        guard let control, let range, let otherControl = other.control, let otherRange = other.range else { return true }
        return control == otherControl && range == otherRange
    }
}

enum SelectionReadResult: Sendable {
    case selected(SelectedText), unauthorized, none, unsupported, failed, timedOut, busy
}

/// Owns all AX objects on one worker. The deadline resumes the caller independently
/// of a stalled synchronous AX call; the busy flag stays set until that call exits.
final class SelectedTextReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.liuguangqi.jotway.selected-text", qos: .userInitiated)
    private let lock = NSLock()
    private var busy = false
    private var controls: [(source: SelectionSource, element: AXUIElement, id: UUID)] = []
    private let trusted: @Sendable () -> Bool
    private let controlledRead: (@Sendable (SelectionSource, ContinuousClock.Instant) -> SelectionReadResult)?

    init(trusted: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
         read: (@Sendable (SelectionSource, ContinuousClock.Instant) -> SelectionReadResult)? = nil) {
        self.trusted = trusted; controlledRead = read
    }

    func read(source: SelectionSource, until deadline: ContinuousClock.Instant) async -> SelectionReadResult {
        guard trusted() else { return .unauthorized }
        guard ContinuousClock.now < deadline else { return .timedOut }
        let admitted = lock.withLock { if busy { return false }; busy = true; return true }
        guard admitted else { return .busy }
        return await withCheckedContinuation { continuation in
            let receipt = Receipt(continuation)
            let remaining = ContinuousClock.now.duration(to: deadline)
            let seconds = max(0, Double(remaining.components.seconds) + Double(remaining.components.attoseconds) / 1e18)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + seconds) { receipt.finish(.timedOut) }
            queue.async { [self] in
                defer { lock.withLock { busy = false } }
                guard ContinuousClock.now < deadline else { receipt.finish(.timedOut); return }
                let result = controlledRead?(source, deadline) ?? readAX(source: source, deadline: deadline)
                receipt.finish(ContinuousClock.now < deadline ? result : .timedOut)
            }
        }
    }

    private final class Receipt: @unchecked Sendable {
        let lock = NSLock()
        var continuation: CheckedContinuation<SelectionReadResult, Never>?
        init(_ continuation: CheckedContinuation<SelectionReadResult, Never>) { self.continuation = continuation }
        func finish(_ value: SelectionReadResult) {
            let current = lock.withLock { let value = continuation; continuation = nil; return value }
            current?.resume(returning: value)
        }
    }

    private func readAX(source: SelectionSource, deadline: ContinuousClock.Instant) -> SelectionReadResult {
        let application = AXUIElementCreateApplication(source.pid)
        func copy(_ element: AXUIElement, _ attribute: CFString) -> (AXError, CFTypeRef?) {
            let remaining = ContinuousClock.now.duration(to: deadline)
            let seconds = Double(remaining.components.seconds) + Double(remaining.components.attoseconds) / 1e18
            guard seconds > 0 else { return (.cannotComplete, nil) }
            AXUIElementSetMessagingTimeout(element, Float(min(seconds, 0.04)))
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, attribute, &value)
            return (error, value)
        }
        let (focusError, focusValue) = copy(application, kAXFocusedUIElementAttribute as CFString)
        guard focusError == .success, let focusValue, CFGetTypeID(focusValue) == AXUIElementGetTypeID() else {
            return focusError == .attributeUnsupported ? .unsupported : .failed
        }
        let element = unsafeBitCast(focusValue, to: AXUIElement.self)
        let (error, value) = copy(element, kAXSelectedTextAttribute as CFString)
        guard error == .success else {
            if error == .noValue { return .none }
            return error == .attributeUnsupported ? .unsupported : .failed
        }
        guard let text = value as? String, SelectedText.isValid(text) else { return .none }
        func range() -> NSRange? {
            let (error, value) = copy(element, kAXSelectedTextRangeAttribute as CFString)
            guard error == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
            let axValue = unsafeBitCast(value, to: AXValue.self)
            var result = CFRange()
            guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &result),
                  result.location >= 0, result.length >= 0 else { return nil }
            return NSRange(location: result.location, length: result.length)
        }
        let selectedRange = range()
        // Recheck only the observable selection and focused element, never AXValue or a tree.
        let (currentError, current) = copy(application, kAXFocusedUIElementAttribute as CFString)
        let (textError, currentText) = copy(element, kAXSelectedTextAttribute as CFString)
        guard currentError == .success, let current, CFEqual(element, current),
              textError == .success, currentText as? String == text,
              selectedRange == range(), ContinuousClock.now < deadline else { return .failed }
        let controlID: UUID
        if let known = controls.first(where: { $0.source == source && CFEqual($0.element, element) }) {
            controlID = known.id
        } else {
            controlID = UUID()
            controls.append((source, element, controlID))
        }
        return .selected(.init(source: source, text: text, control: controlID, range: selectedRange))
    }
}

@MainActor
struct SelectionAdoptions {
    private var draft: UUID?
    private var values: [SelectedText] = []
    mutating func contains(_ value: SelectedText, draftID: UUID) -> Bool {
        if draft != draftID { draft = draftID; values.removeAll() }
        return values.contains { $0.duplicates(value) }
    }
    mutating func record(_ value: SelectedText, draftID: UUID) {
        if !contains(value, draftID: draftID) { values.append(value) }
    }
}
