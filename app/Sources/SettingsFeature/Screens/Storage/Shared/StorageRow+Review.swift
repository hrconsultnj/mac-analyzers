import AnalyzersKit

extension StorageRow {
    /// The review table's own row for this one.
    var reviewRow: ReviewRow {
        ReviewRow(id: id, name: title, detail: detail, group: group, bytes: bytes, iconPath: iconPath,
                  keptReason: keptReason, valueText: valueText)
    }
}

extension ReviewConfirmation {
    /// The confirmation for a cleanup's words (`CleanWords`), so its title and second question can
    /// only come from the setting the words were made for.
    init(words: CleanWords) {
        self.init(verb: words.verb, destination: words.destination, message: words.message,
                  permanent: words.permanentWarning)
    }
}
