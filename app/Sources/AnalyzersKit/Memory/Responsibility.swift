import Darwin
import Foundation

/// macOS's own record of which app a helper process is working for — what
/// Activity Monitor uses to file a web-content process under its browser.
/// Not in the public headers, so it is looked up at runtime and its absence
/// simply leaves helpers grouped by parent.
enum Responsibility {
    private typealias Lookup = @convention(c) (pid_t) -> pid_t

    private static let lookup: Lookup? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2),   // RTLD_DEFAULT
                                 "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        return unsafeBitCast(symbol, to: Lookup.self)
    }()

    static func pid(for pid: Int32) -> Int32? {
        guard let lookup else { return nil }
        let responsible = lookup(pid)
        return responsible > 0 ? responsible : nil
    }
}
