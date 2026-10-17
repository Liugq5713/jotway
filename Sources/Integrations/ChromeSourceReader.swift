import AppKit
import Carbon

struct BrowserSource: Equatable, Sendable {
    let title: String
    let url: String

    static func validated(title: String, url: String) -> BrowserSource? {
        guard url.utf8.count <= 8192, !url.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !url.contains(where: \.isWhitespace),
              let parts = URLComponents(string: url),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              URL(string: url, encodingInvalidCharacters: false) != nil else { return nil }
        let name = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return .init(title: name.isEmpty ? host : String(name.prefix(512)), url: url)
    }
}

/// Reads only one already-running Chrome process. No URL is fetched or executed.
struct ChromeSourceReader: Sendable {
    static let bundleIdentifier = "com.google.Chrome"

    static func permission(request: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, request)
    }

    func read(processID: pid_t) async -> BrowserSource? {
        await Task.detached(priority: .utility) { Self.capture(processID: processID) }.value
    }

    private static func capture(processID: pid_t) -> BrowserSource? {
        do {
            guard permission(request: false) == noErr else { return nil }
            let target = NSAppleEventDescriptor(processIdentifier: processID)
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .milliseconds(500))
            func code(_ value: String) -> OSType { value.utf8.reduce(0) { ($0 << 8) | OSType($1) } }
            func object(_ kind: OSType, container: NSAppleEventDescriptor = .null(),
                        form: OSType, key: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
                let record = NSAppleEventDescriptor.record()
                record.setDescriptor(.init(typeCode: kind), forKeyword: AEKeyword(keyAEDesiredClass))
                record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
                record.setDescriptor(.init(enumCode: form), forKeyword: AEKeyword(keyAEKeyForm))
                record.setDescriptor(key, forKeyword: AEKeyword(keyAEKeyData))
                guard let value = record.coerce(toDescriptorType: DescType(typeObjectSpecifier)) else { throw CocoaError(.coderInvalidValue) }
                return value
            }
            func property(_ name: String, of container: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
                let remaining = clock.now.duration(to: deadline).components
                let timeout = Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18
                guard timeout > 0 else { throw CocoaError(.userCancelled) }
                let reference = try object(OSType(cProperty), container: container,
                    form: OSType(formPropertyID), key: .init(typeCode: code(name)))
                let event = NSAppleEventDescriptor(eventClass: AEEventClass(kAECoreSuite), eventID: AEEventID(kAEGetData),
                    targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
                event.setParam(reference, forKeyword: AEKeyword(keyDirectObject))
                let reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: timeout)
                if let error = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber))?.int32Value, error != 0 {
                    throw NSError(domain: NSOSStatusErrorDomain, code: Int(error))
                }
                guard let result = reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)), clock.now < deadline else {
                    throw CocoaError(.coderInvalidValue)
                }
                return result
            }
            // Public codes from Chrome's scripting.sdef. Re-resolve the front window and
            // active tab after reading; never trust list position as a stable identity.
            let window = try object(code("cwin"), form: OSType(formAbsolutePosition), key: .init(int32: 1))
            let windowID = try property("ID  ", of: window).stringValue
            let tab = try property("acTa", of: window)
            let tabID = try property("ID  ", of: tab).stringValue
            let url = try property("URL ", of: tab).stringValue
            let title = try property("pnam", of: tab).stringValue ?? ""
            let currentTab = try property("acTa", of: window)
            guard let windowID, let tabID, let url,
                  try property("ID  ", of: window).stringValue == windowID,
                  try property("ID  ", of: currentTab).stringValue == tabID,
                  try property("URL ", of: currentTab).stringValue == url else { return nil }
            return BrowserSource.validated(title: title, url: url)
        } catch { return nil }
    }
}

@MainActor @Observable
final class BrowserSourceSettings {
    private let preferences: UserDefaults
    private let checkPermission: @Sendable (Bool) -> OSStatus
    private(set) var enabled: Bool
    private(set) var permissionGranted = false
    private(set) var requesting = false
    private var revision = 0

    init(preferences: UserDefaults, checkPermission: @escaping @Sendable (Bool) -> OSStatus = { ChromeSourceReader.permission(request: $0) }) {
        self.preferences = preferences
        self.checkPermission = checkPermission
        enabled = preferences.bool(forKey: "browserSource.enabled")
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        preferences.set(value, forKey: "browserSource.enabled")
        revision += 1
        if value { refreshPermission(request: true) }
        else { permissionGranted = false }
    }

    func refreshPermission(request: Bool = false) {
        guard enabled, !requesting else { return }
        let generation = revision
        requesting = true
        let check = checkPermission
        Task { [weak self] in
            let status = await Task.detached(priority: .utility) { check(request) }.value
            guard let self else { return }
            self.requesting = false
            guard self.enabled, self.revision == generation else { return }
            self.permissionGranted = status == noErr
        }
    }
}
