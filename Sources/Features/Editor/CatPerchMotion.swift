import CoreGraphics
import Foundation

/// Motion lives in reveal space, independently of card height and footer layout.
/// Retargeting keeps both position and velocity; a resting cat needs no frame timer.
struct CatPerchMotion {
    enum Arrival {
        case peek
        case hop
    }

    struct Pose {
        var reveal: CGFloat
        var velocity: CGFloat

        /// One head stays visible while the grounded body unfolds beneath it.
        var bodyOpacity: CGFloat { 1 - blend(reveal, from: 0.2, to: 0.92) }
        var headRise: CGFloat { blend(reveal, from: 0, to: 1) }
        var restingFold: CGFloat { pow(sin(headRise * .pi), 2) }

        private func blend(_ value: CGFloat, from start: CGFloat, to end: CGFloat) -> CGFloat {
            let t = min(1, max(0, (value - start) / (end - start)))
            return t * t * (3 - 2 * t)
        }
    }

    private var placed = false
    private var source: CGFloat = 0
    private var velocity: CGFloat = 0
    private var destination: CGFloat = 0
    private var startedAt: TimeInterval = 0
    private var response: CGFloat = 7.6

    mutating func setPerched(_ perched: Bool, arrival: Arrival,
                            at time: TimeInterval, animated: Bool) {
        let target: CGFloat = perched ? 1 : 0
        guard placed, animated else {
            placed = true
            destination = target
            settle()
            return
        }
        guard target != destination else { return }
        let current = sample(at: time)
        source = current.position
        velocity = current.velocity
        destination = target
        startedAt = time
        // A quieter return lets the body unfold as the same head settles.
        response = perched ? (arrival == .peek ? 7.6 : 10) : 6.8
    }

    func pose(at time: TimeInterval) -> Pose {
        let current = sample(at: time)
        return Pose(reveal: min(1, max(0, current.position)), velocity: current.velocity)
    }

    func isMoving(at time: TimeInterval) -> Bool {
        let current = sample(at: time)
        return current.position != destination || current.velocity != 0
    }

    mutating func settle() {
        source = destination
        velocity = 0
    }

    private func sample(at time: TimeInterval) -> (position: CGFloat, velocity: CGFloat) {
        // Analytic critically damped spring: no frame-rate-dependent integration,
        // and no velocity reset when typing reverses an unfinished return.
        let elapsed = CGFloat(max(0, time - startedAt))
        let displacement = source - destination
        let coefficient = velocity + response * displacement
        let decay = exp(-response * elapsed)
        let position = destination + (displacement + coefficient * elapsed) * decay
        let speed = (velocity - response * coefficient * elapsed) * decay
        if abs(position - destination) < 0.001, abs(speed) < 0.012 {
            return (destination, 0)
        }
        return (position, speed)
    }
}
