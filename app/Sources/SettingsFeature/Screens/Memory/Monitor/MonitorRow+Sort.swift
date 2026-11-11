import AnalyzersKit

/// The sortable values a table column needs: a column sorts by a key path
/// to something comparable, and a row with no reading sorts last.
extension MonitorRow {
    var cpuSort: Double { cpu ?? -1 }
    var pidSort: Int { pid ?? Int.max }
}
