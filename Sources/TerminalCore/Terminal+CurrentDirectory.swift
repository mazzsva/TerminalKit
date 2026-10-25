import Foundation

extension Terminal {
    private static let launchHostName = currentHostName

    private static var currentHostName: String {
        var name = [CChar](repeating: 0, count: Int(MAXHOSTNAMELEN) + 1)
        guard gethostname(&name, Int(MAXHOSTNAMELEN)) == 0 else {
            return ""
        }
        return String(decoding: name.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self).lowercased()
    }

    package static func isLocal(_ url: URL) -> Bool {
        let host = url.host()?.lowercased() ?? ""
        return ["", "localhost", launchHostName, currentHostName].contains(host)
    }

    mutating func setCurrentDirectory(_ location: Substring) {
        guard let url = URL(string: String(location)), url.isFileURL else {
            return
        }
        let path = url.path(percentEncoded: false)
        guard Self.isLocal(url), path.hasPrefix("/") else {
            currentDirectory = nil
            return
        }
        currentDirectory = URL(filePath: path)
    }
}
