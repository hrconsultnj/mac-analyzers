import AnalyzersKit

extension StorageRow {
    /// The review table's own row for this one.
    var reviewRow: ReviewRow {
        ReviewRow(id: id, name: title, detail: detail, group: group, bytes: bytes, iconPath: iconPath,
                  keptReason: keptReason, valueText: valueText)
    }
}
