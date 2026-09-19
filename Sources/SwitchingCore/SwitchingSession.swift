/// A frozen ring for one Command hold. Zero-window applications remain selectable.
public struct SwitchingSession: Equatable {
    public let counts: [Int]
    public private(set) var app: Int
    public private(set) var window: Int
    public init?(windowCounts: [Int], currentApp: Int = 0) {
        guard !windowCounts.isEmpty, windowCounts.indices.contains(currentApp), windowCounts.allSatisfy({ $0 >= 0 }) else { return nil }
        counts = windowCounts
        // Discovery puts the focused window first. Finish its app before moving on.
        app = currentApp
        window = 0
        advance()
    }
    public mutating func advance() {
        if window + 1 < counts[app] { window += 1 }
        else { app = (app + 1) % counts.count; window = 0 }
    }
}
