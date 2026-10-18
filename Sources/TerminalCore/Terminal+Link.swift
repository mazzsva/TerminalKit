extension Terminal {
    package struct Links: Sendable {
        let capacity: Int
        let byteCapacity: Int
        private var keys: [String] = [""]
        private var uris: [String] = [""]
        private var indices: [String: UInt16] = [:]
        private var byteCount = 0
        private var additionsSinceCompaction = 0

        init(capacity: Int = Int(UInt16.max), byteCapacity: Int = 4 << 20) {
            self.capacity = capacity
            self.byteCapacity = byteCapacity
        }

        var count: Int {
            uris.count
        }

        package func uri(of link: UInt16) -> String? {
            link > 0 && Int(link) < uris.count ? uris[Int(link)] : nil
        }

        func needsCompaction(forKey key: String, uri: String) -> Bool {
            isFull(adding: uri) && additionsSinceCompaction >= 64 && indices[key] == nil
        }

        mutating func link(forKey key: String, uri: String) -> UInt16 {
            if let index = indices[key] {
                return index
            }
            additionsSinceCompaction += 1
            guard !isFull(adding: uri) else {
                return 0
            }
            let index = UInt16(uris.count)
            keys.append(key)
            uris.append(uri)
            indices[key] = index
            byteCount += uri.utf8.count
            return index
        }

        static func markLinks(in lines: [Line], into used: inout [Bool]) {
            for line in lines {
                for cell in line where cell.style.link > 0 {
                    used[Int(cell.style.link)] = true
                }
            }
        }

        mutating func compact(keeping used: [Bool]) -> [UInt16] {
            var newIndices = Array(repeating: UInt16(0), count: uris.count)
            var keptKeys = [""]
            var keptURIs = [""]
            for index in uris.indices.dropFirst() where used[index] {
                newIndices[index] = UInt16(keptURIs.count)
                keptKeys.append(keys[index])
                keptURIs.append(uris[index])
            }
            keys = keptKeys
            uris = keptURIs
            indices = Dictionary(uniqueKeysWithValues: keptKeys.enumerated().dropFirst().map { ($1, UInt16($0)) })
            byteCount = keptURIs.reduce(0) { $0 + $1.utf8.count }
            additionsSinceCompaction = 0
            return newIndices
        }

        static func remapLinks(in lines: inout [Line], with newIndices: [UInt16]) {
            for row in lines.indices where lines[row].contains(where: { $0.style.link > 0 }) {
                for column in lines[row].indices where lines[row][column].style.link > 0 {
                    lines[row][column].style.link = newIndices[Int(lines[row][column].style.link)]
                }
            }
        }

        static func key(from value: Substring) -> (key: String, uri: String)? {
            guard let separator = value.firstIndex(of: ";") else {
                return nil
            }
            let uri = String(value[value.index(after: separator)...])
            let id = value[..<separator].split(separator: ":").first { $0.hasPrefix("id=") }?.dropFirst(3) ?? ""
            return (id.isEmpty ? uri : "\(id)\u{0}\(uri)", uri)
        }

        private func isFull(adding uri: String) -> Bool {
            uris.count >= capacity || byteCount + uri.utf8.count > byteCapacity
        }
    }
}
