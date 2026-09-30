import Foundation

public enum SunriseCurve {
    /// 1 − (1 − e)², clamped.
    public static func easeOut(_ e: Double) -> Double {
        let x = min(max(e, 0), 1)
        return 1 - (1 - x) * (1 - x)
    }

    /// SPEC §8/§9: b = from + (1 − from)·easeOut(e), e = (elapsed − delay) / duration.
    public static func brightness(elapsed: Double, duration: Double, from: Double, delay: Double = 0) -> Double {
        let e = duration > 0 ? (elapsed - delay) / duration : 1
        return from + (1 - from) * easeOut(e)
    }
}

/// CSS-style cubic-bezier(x1, y1, x2, y2) timing function.
public struct CubicBezier: Sendable {
    let cx, bx, ax, cy, by, ay: Double

    public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        cx = 3 * x1; bx = 3 * (x2 - x1) - cx; ax = 1 - cx - bx
        cy = 3 * y1; by = 3 * (y2 - y1) - cy; ay = 1 - cy - by
    }

    public func callAsFunction(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        return sampleY(solveT(x))
    }

    private func sampleX(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
    private func sampleY(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
    private func slopeX(_ t: Double) -> Double { (3 * ax * t + 2 * bx) * t + cx }

    private func solveT(_ x: Double) -> Double {
        var t = x
        for _ in 0..<8 {
            let err = sampleX(t) - x
            if abs(err) < 1e-6 { return t }
            let d = slopeX(t)
            if abs(d) < 1e-6 { break }
            t -= err / d
        }
        // Newton stalled — fall back to bisection.
        var lo = 0.0, hi = 1.0
        t = x
        while hi - lo > 1e-6 {
            if sampleX(t) < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return t
    }
}
