import Foundation

/// Opt-in, content-free timing for isolated release profiling. No logging on the typing path.
@MainActor
enum InputPerformance {
    static var report: ((_ phase: String, _ milliseconds: Double) -> Void)?

    static func begin() -> UInt64? {
        report == nil ? nil : DispatchTime.now().uptimeNanoseconds
    }

    static func end(_ phase: String, _ start: UInt64?) {
        guard let start else { return }
        report?(phase, Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }
}
