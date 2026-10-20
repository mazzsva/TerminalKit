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

    mutating func setCurrentDirectory(_ location: Substring) {
        guard let url = URL(string: String(location)), url.isFileURL else {
            return
        }
        let path = url.path(percentEncoded: false)
        let host = url.host(percentEncoded: false)?.lowercased() ?? ""
        guard ["", "localhost", Self.launchHostName, Self.currentHostName].contains(host), path.hasPrefix("/") else {
            currentDirectory = nil
            return
        }
        currentDirectory = URL(filePath: path)
    }
}
