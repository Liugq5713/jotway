import SwiftUI

struct TemplateSettingsView: View {
    let configuration: TemplateConfiguration
    @State private var editing = false
    @State private var editingID: String?
    @State private var name = ""
    @State private var templateBody = ""
    @State private var issue: String?
    @FocusState private var isNameFocused: Bool

    private var isEditingBuiltIn: Bool {
        editing && configuration.builtIns.contains { $0.id == editingID }
    }

    var body: some View {
        Form {
            if let error = configuration.error, !editing || configuration.isReadOnly {
                Section { Text(error).foregroundStyle(.red) }
            }
            Section(L10n.text("templates.built_in")) {
                ForEach(configuration.builtIns) { template in
                    templateRow(template)
                }
            }
            Section(L10n.text("templates.custom")) {
                ForEach(configuration.custom) { template in
                    templateRow(template)
                }
                Button(L10n.text("templates.add")) { begin(nil) }
                    .disabled(configuration.isReadOnly || editing)
            }
            if editing && !isEditingBuiltIn {
                Section(L10n.text("templates.editing")) {
                    editingForm
                }
            }
            if !editing, let issue { Section { Text(issue).foregroundStyle(.red) } }
            Section(L10n.text("templates.syntax_title")) {
                Text(L10n.text("templates.syntax_help")).font(.caption).textSelection(.enabled)
            }
        }.formStyle(.grouped)
    }

    private var editingForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("templates.name"))
                TextField("", text: $name)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(L10n.text("templates.name"))
                    .focused($isNameFocused)
            }
            .disabled(configuration.isReadOnly)
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("templates.body"))
                TextEditor(text: $templateBody)
                    .font(.body.monospaced())
                    .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
                    .accessibilityLabel(L10n.text("templates.body"))
            }
            .disabled(configuration.isReadOnly)
            if let issue { Text(issue).foregroundStyle(.red) }
            HStack {
                Button(L10n.text("templates.save")) { save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(configuration.isReadOnly)
                Button(L10n.text("templates.cancel")) { endEditing() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if isEditingBuiltIn { isNameFocused = true }
        }
    }

    private func templateRow(_ template: InputTemplate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if template.isBuiltIn && editing && editingID == template.id {
                editingForm
            } else {
                templateContent(template)
                HStack {
                    Spacer()
                    Button(L10n.text("templates.edit")) { begin(template) }
                    if !template.isBuiltIn {
                        Button(L10n.text("templates.delete"), role: .destructive) {
                            guard !editing, !configuration.isReadOnly else { return }
                            do { try configuration.delete(template.id); issue = nil }
                            catch { issue = error.localizedDescription }
                        }
                    }
                }
                .disabled(configuration.isReadOnly || editing)
            }
        }
    }

    private func templateContent(_ template: InputTemplate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(template.name).font(.headline)
            Text(template.body)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func begin(_ template: InputTemplate?) {
        guard !editing, !configuration.isReadOnly else { return }
        editingID = template?.id; name = template?.name ?? ""; templateBody = template?.body ?? ""
        issue = nil; editing = true
    }

    private func save() {
        guard editing, !configuration.isReadOnly else { return }
        do {
            try configuration.save(id: editingID, name: name, body: templateBody)
            endEditing()
        } catch { issue = error.localizedDescription }
    }

    private func endEditing() {
        isNameFocused = false
        editing = false; editingID = nil; name = ""; templateBody = ""; issue = nil
    }
}
