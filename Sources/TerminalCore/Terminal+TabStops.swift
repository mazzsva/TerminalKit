extension Terminal {
    struct TabStops {
        private static let width = 8
        private var stops: [Bool] = []
        private var hasDefaultStopsBeyond = true

        func contains(_ column: Int) -> Bool {
            column < stops.count ? stops[column] : hasDefaultStopsBeyond && column % Self.width == 0
        }

        mutating func set(_ isStop: Bool, at column: Int) {
            while stops.count <= column {
                stops.append(contains(stops.count))
            }
            stops[column] = isStop
        }

        mutating func removeAll() {
            stops = []
            hasDefaultStopsBeyond = false
        }
    }
}
