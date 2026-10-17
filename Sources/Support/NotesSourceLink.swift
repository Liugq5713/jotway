import Foundation

/// App-owned links carry the opaque ID returned by Notes; opening uses its public show command.
enum NotesSourceLink {
    private static let maximumIDBytes = 4_096

    static func url(noteID: String) -> URL? {
        guard valid(noteID) else { return nil }
        var components = URLComponents()
        components.scheme = "jotway"
        components.host = "notes"
        components.path = "/open"
        components.queryItems = [URLQueryItem(name: "id", value: noteID)]
        return components.url
    }

    static func noteID(from url: URL) -> String? {
        guard url.absoluteString.utf8.count <= maximumIDBytes * 3 + 128,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "jotway",
              components.host?.lowercased() == "notes",
              components.user == nil, components.password == nil, components.port == nil,
              components.percentEncodedPath == "/open", components.fragment == nil,
              let query = components.queryItems, query.count == 1,
              query[0].name == "id", let noteID = query[0].value, valid(noteID) else { return nil }
        return noteID
    }

    private static func valid(_ noteID: String) -> Bool {
        !noteID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && noteID.utf8.count <= maximumIDBytes
            && noteID.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0)
            }
    }
}
