import AppKit
import SwiftUI

private func wrap(_ a: Int, _ n: Int) -> Int { ((a % n) + n) % n }

private let rowHeight: CGFloat = 68

/// Continuous wheel position. `pos` is unbounded so the column loops (SPEC §6.2).
@MainActor
final class WheelModel: ObservableObject {
    @Published private(set) var pos: Double
    private(set) var target: Int
    var onCommit: ((Int) -> Void)?

    private var timer: Timer?
    private var dragStartPos = 0.0
    private var scrollAccumulator = 0.0

    init(value: Int) {
        pos = Double(value)
        target = value
    }

    func setTarget(_ t: Int) {
        target = t
        onCommit?(t)
        startSettling()
    }

    /// External value change: roll the shortest way round.
    func follow(_ value: Int, count: Int) {
        let current = wrap(target, count)
        guard current != value else { return }
        var delta = value - current
        if delta > count / 2 { delta -= count } else if delta < -count / 2 { delta += count }
        target += delta
        startSettling()
    }

    func dragBegan() {
        stopSettling()
        dragStartPos = pos
    }

    /// Follows the cursor 1:1 (68 pt = 1 step).
    func dragChanged(_ dy: CGFloat) {
        pos = dragStartPos - Double(dy / rowHeight)
    }

    func dragEnded() {
        setTarget(Int(pos.rounded()))
    }

    func click(rowOffset: Int) {
        setTarget(target + rowOffset)
    }

    /// Wheel/trackpad: deltas accumulate, every 30 units = one step.
    func scroll(_ event: NSEvent) {
        if event.hasPreciseScrollingDeltas {
            scrollAccumulator += -event.scrollingDeltaY
            var steps = 0
            while scrollAccumulator >= 30 { steps += 1; scrollAccumulator -= 30 }
            while scrollAccumulator <= -30 { steps -= 1; scrollAccumulator += 30 }
            if steps != 0 { setTarget(target + steps) }
        } else if event.scrollingDeltaY != 0 {
            setTarget(target + (event.scrollingDeltaY > 0 ? -1 : 1))
        }
    }

    // pos += (target − pos)·0.2 per frame until |Δ| < 0.002.
    private func startSettling() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.settleStep() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func settleStep() {
        let d = Double(target) - pos
        if abs(d) < 0.002 {
            pos = Double(target)
            stopSettling()
        } else {
            pos += d * 0.2
        }
    }

    private func stopSettling() {
        timer?.invalidate()
        timer = nil
    }
}

struct WheelPicker: View {
    @Binding var value: Int
    let count: Int
    @StateObject private var model: WheelModel

    init(value: Binding<Int>, count: Int) {
        _value = value
        self.count = count
        _model = StateObject(wrappedValue: WheelModel(value: value.wrappedValue))
    }

    var body: some View {
        let base = Int(model.pos.rounded(.down))
        ZStack {
            ForEach((base - 3)...(base + 3), id: \.self) { k in
                let d = Double(k) - model.pos
                Text(String(format: "%02d", wrap(k, count)))
                    .font(AppFont.make(68, .light))
                    .tracking(-68 * 0.02)
                    .foregroundColor(Theme.textPrimary)
                    .scaleEffect(1 - abs(d) * 0.08)
                    .rotation3DEffect(.degrees(-d * 24), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                    .opacity(max(0, 1 - abs(d) * 0.5))
                    .offset(y: d * rowHeight)
            }
        }
        .frame(width: 128, height: 204)
        .clipped()
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.28),
                    .init(color: .black, location: 0.72),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
        .overlay(WheelInput(model: model))
        .onAppear {
            let binding = $value
            let count = count
            model.onCommit = { binding.wrappedValue = wrap($0, count) }
        }
        .onChange(of: value) { _, v in model.follow(v, count: count) }
    }
}

/// Mouse & scroll input for the wheel. SwiftUI has no scroll-wheel hook on macOS, so this is an NSView.
private struct WheelInput: NSViewRepresentable {
    let model: WheelModel

    func makeNSView(context: Context) -> WheelInputView {
        let v = WheelInputView()
        v.model = model
        return v
    }

    func updateNSView(_ view: WheelInputView, context: Context) {
        view.model = model
    }
}

private final class WheelInputView: NSView {
    weak var model: WheelModel?
    private var start: CGPoint = .zero
    private var moved = false

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func scrollWheel(with event: NSEvent) {
        model?.scroll(event)
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        moved = false
        model?.dragBegan()
    }

    override func mouseDragged(with event: NSEvent) {
        let dy = convert(event.locationInWindow, from: nil).y - start.y
        // Under 3 pt it's still a click.
        if abs(dy) >= 3 { moved = true }
        if moved { model?.dragChanged(dy) }
    }

    override func mouseUp(with event: NSEvent) {
        if moved {
            model?.dragEnded()
        } else {
            let offset = Int(((start.y - bounds.midY) / rowHeight).rounded())
            model?.click(rowOffset: offset)
        }
    }
}

/// Hours : minutes with the shared highlight bar.
struct TimeWheel: View {
    @Binding var hour: Int
    @Binding var minute: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .frame(height: rowHeight)
            HStack(spacing: 0) {
                WheelPicker(value: $hour, count: 24)
                Text(":")
                    .font(AppFont.make(60, .light))
                    .foregroundColor(Theme.textSecondary)
                    .offset(y: -4)
                    .frame(width: 28)
                WheelPicker(value: $minute, count: 60)
            }
        }
        .frame(height: 204)
    }
}
