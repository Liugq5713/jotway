import Foundation

/// A continuous oval drift with a damped response to typing. Switching goals keeps
/// position and velocity, including when a return is interrupted halfway through.
struct SharkSwimMotion {
    private(set) var position: CGPoint?
    private var velocity = CGVector.zero
    private var phase: CGFloat = 0.7
    private var time: CGFloat = 0

    mutating func resume() {
        velocity = .zero
    }

    mutating func advance(delta: TimeInterval, lane: CGRect, edge: CGPoint, retreating: Bool) -> CGPoint {
        let dt = CGFloat(delta)
        time += dt
        let radiusX = min(110, lane.width / 2)
        let radiusY = min(90, lane.height / 2)
        let tangent = hypot(radiusX * sin(phase), radiusY * cos(phase))
        // Coast through the tight ends instead of stopping and reversing on a line.
        phase += dt * min(0.85, (29 + 5 * sin(time * 0.42)) / max(1, tangent))
        let patrol = CGPoint(x: lane.midX + radiusX * cos(phase),
                             y: lane.midY + radiusY * sin(phase))
        let resting = CGPoint(x: edge.x + 5 * sin(time * 0.6),
                              y: edge.y + 7 * sin(time * 0.43))
        let goal = retreating ? resting : patrol
        guard let current = position else { position = goal; return goal }
        // Capped acceleration and speed keep a distant edge from causing a dash.
        // A new goal retains momentum; even an interrupted return turns gradually.
        let response: CGFloat = retreating ? 1.3 : 2.4
        let acceleration = limited(
            CGVector(dx: (goal.x - current.x) * response * response - 2 * response * velocity.dx,
                     dy: (goal.y - current.y) * response * response - 2 * response * velocity.dy),
            to: 48)
        velocity = limited(CGVector(dx: velocity.dx + acceleration.dx * dt,
                                    dy: velocity.dy + acceleration.dy * dt),
                           to: retreating ? 36 : 42)
        let next = CGPoint(x: current.x + velocity.dx * dt, y: current.y + velocity.dy * dt)
        position = next
        return next
    }

    private func limited(_ vector: CGVector, to maximum: CGFloat) -> CGVector {
        let length = hypot(vector.dx, vector.dy)
        let scale = length > maximum ? maximum / length : 1
        return CGVector(dx: vector.dx * scale, dy: vector.dy * scale)
    }
}
