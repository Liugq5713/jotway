import SwiftUI

struct NotesReviewScopeView: View {
    let library: NotesReviewLibrary

    var body: some View {
        Text(L10n.text("notes.review.privacy")).font(.caption).foregroundStyle(.secondary)
        if !library.hasPermission {
            Button(L10n.text("notes.review.authorize")) { Task { await library.loadFolders() } }
                .disabled(library.authorizing)
        }
        Toggle(L10n.text("notes.review.all_folders"), isOn: Binding(
            get: { library.allFolders }, set: { library.setAllFolders($0) }))
        if !library.allFolders {
            Button(L10n.text("notes.review.load_folders")) { Task { await library.loadFolders() } }
                .disabled(library.authorizing)
            Text(L10n.text("notes.review.scope_count", library.selectedFolders.count)).font(.caption)
            ForEach(library.availableFolders) { folder in
                Toggle(folder.name, isOn: Binding(get: { library.selectedFolders.contains(folder.id) },
                    set: { library.selectFolder(folder.id, selected: $0) }))
            }
            ForEach(library.selectedFolders.subtracting(Set(library.availableFolders.map(\.id))).sorted(), id: \.self) { id in
                HStack {
                    Text(L10n.text("notes.review.saved_folder", id)).font(.caption)
                    Button(L10n.text("notes.review.remove_scope")) { library.selectFolder(id, selected: false) }
                }
            }
        }
        if library.authorizing { ProgressView().controlSize(.small) }
        if let message = library.message { Text(message).font(.caption).foregroundStyle(.secondary) }
    }
}
