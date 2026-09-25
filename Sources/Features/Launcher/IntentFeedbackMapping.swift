import Foundation

extension IntentRecognition.Suggestion {
    /// 功能层将识别快照转换为持久化值；Data 不认识识别器或编辑器。
    @MainActor
    func feedback(confirmationSource: IntentFeedback.ConfirmationSource = .commandEnter,
                  at date: Date = Date()) -> IntentFeedback {
        let targetID = self.targetID
        let application = snapshot.applications.first { $0.id == targetID }
        return IntentFeedback(id: id, acceptedAt: date, draftID: snapshot.draftID,
            draftRevision: snapshot.revision, text: snapshot.text, action: action.diagnosticAction,
            targetID: targetID, applicationBundleID: application?.bundleIdentifier,
            applicationName: application?.name, recognition: recognition,
            confirmationSource: confirmationSource, label: .userAccepted)
    }
}
