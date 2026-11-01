import AppKit

/// Drives a CGPoint toward a target with a damped spring, for window frames that SwiftUI cannot animate.
/// Same feel as `Design.Motion.open`; DESIGN.md allows springs only, so `NSWindow.setFrame(animate:)` is out.
@MainActor
final class SpringAnimator {
    private var timer: Timer?
    private var position = CGPoint.zero
    private var velocity = CGPoint.zero
    private var target = CGPoint.zero
    private var last: CFTimeInterval = 0
    private var apply: ((CGPoint) -> Void)?
    private var done: (() -> Void)?
    var isRunning: Bool { timer != nil }

    func run(from: CGPoint, to: CGPoint, response: Double, damping: Double,
             apply: @escaping (CGPoint) -> Void, done: (() -> Void)? = nil) {
        stop()
        position = from; target = to; velocity = .zero
        self.apply = apply; self.done = done
        last = CACurrentMediaTime()
        let omega = 2 * Double.pi / response
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step(omega: omega, zeta: damping) }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func step(omega: Double, zeta: Double) {
        let now = CACurrentMediaTime()
        var remaining = min(now - last, 0.05)
        last = now
        // Fixed sub-steps keep the integration stable when a frame is late.
        let h = 1.0 / 240.0
        while remaining > 0 {
            let dt = min(h, remaining)
            let ax = -omega * omega * Double(position.x - target.x) - 2 * zeta * omega * Double(velocity.x)
            let ay = -omega * omega * Double(position.y - target.y) - 2 * zeta * omega * Double(velocity.y)
            velocity.x += CGFloat(ax * dt); velocity.y += CGFloat(ay * dt)
            position.x += velocity.x * CGFloat(dt); position.y += velocity.y * CGFloat(dt)
            remaining -= dt
        }
        let settled = abs(position.x - target.x) < 0.25 && abs(position.y - target.y) < 0.25
            && abs(velocity.x) < 4 && abs(velocity.y) < 4
        if settled {
            apply?(target)
            stop()
            done?()
        } else {
            apply?(position)
        }
    }
}
