/// Where the user is: a sidebar section and what is pushed on top of it.
/// Both the history and the saved restoration state are made of these.
struct Location: Hashable, Codable {
    var section: SectionID
    var path: [Route]

    init(_ section: SectionID, path: [Route] = []) {
        self.section = section
        self.path = path
    }
}
