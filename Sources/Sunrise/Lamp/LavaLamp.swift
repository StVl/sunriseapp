import MetalKit
import SwiftUI

/// SPEC §11.3 palette structure. Colors are sRGB, straight alpha.
struct LavaPalette {
    enum Name: String, CaseIterable, Codable {
        case ember = "Ember", aurora = "Aurora", glacier = "Glacier"
    }

    let top, mid, bot: SIMD4<Float>
    let wax0, wax1: SIMD4<Float>
    let glow, glow2: SIMD4<Float>

    static func named(_ name: Name) -> LavaPalette {
        switch name {
        case .ember:
            return LavaPalette(
                top: rgb(0x6a2204), mid: rgb(0xc24a0c), bot: rgb(0xff7a1a),
                wax0: rgb(0xfff3a0), wax1: rgb(0xffc44d),
                glow: rgb(255, 150, 60, 0.6), glow2: rgb(230, 110, 30, 0.4)
            )
        case .aurora:
            return LavaPalette(
                top: rgb(0x0d1f7a), mid: rgb(0x1552c4), bot: rgb(0x1d8bff),
                wax0: rgb(0x7dffcf), wax1: rgb(0x2bd98f),
                glow: rgb(60, 170, 255, 0.55), glow2: rgb(40, 110, 230, 0.4)
            )
        case .glacier:
            return LavaPalette(
                top: rgb(0x4a0a3f), mid: rgb(0xa8246f), bot: rgb(0xff3fa4),
                wax0: rgb(0xffffff), wax1: rgb(0xffc2e6),
                glow: rgb(255, 110, 190, 0.55), glow2: rgb(220, 60, 150, 0.4)
            )
        }
    }

    private static func rgb(_ hex: UInt32) -> SIMD4<Float> {
        SIMD4(Float((hex >> 16) & 0xff) / 255, Float((hex >> 8) & 0xff) / 255, Float(hex & 0xff) / 255, 1)
    }

    private static func rgb(_ r: Float, _ g: Float, _ b: Float, _ a: Float) -> SIMD4<Float> {
        SIMD4(r / 255, g / 255, b / 255, a)
    }
}

/// Full-window lava lamp, drawn by a Metal shader (SPEC §11).
struct LavaLampView: View {
    @ObservedObject var state: AppState

    var body: some View {
        LampMetalView(state: state)
            .background(Theme.windowBackground)
    }
}

// MARK: - Geometry (port of LavaField from light.jsx with the SPEC §11 changes)

enum LavaGeometry {
    /// 48 s per loop, 2.67× slower than the 18 s prototype.
    static let period = 48.0

    static func phase(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        return t / period * 2 * .pi
    }

    private struct Blob { let x, r, f, ph, dx: Double }

    // Integer frequencies keep the loop seamless.
    private static let blobs: [Blob] = [
        Blob(x: 0.18, r: 110, f: 1, ph: 0.0, dx: 0.05),
        Blob(x: 0.34, r: 80, f: 2, ph: 2.1, dx: 0.04),
        Blob(x: 0.50, r: 140, f: 1, ph: 3.6, dx: 0.06),
        Blob(x: 0.64, r: 70, f: 2, ph: 5.2, dx: 0.05),
        Blob(x: 0.78, r: 120, f: 1, ph: 1.4, dx: 0.04),
        Blob(x: 0.90, r: 60, f: 3, ph: 4.4, dx: 0.03),
        Blob(x: 0.42, r: 55, f: 3, ph: 0.9, dx: 0.07),
        Blob(x: 0.08, r: 65, f: 2, ph: 3.0, dx: 0.03),
    ]

    /// Ellipses as (cx, cy, rx, ry) in points, y down: 10 pools + 8 blobs.
    static func shapes(w: Double, h: Double, p: Double) -> [SIMD4<Float>] {
        let sc = h / 700
        var out: [SIMD4<Float>] = []
        out.reserveCapacity(18)

        // Pools top and bottom that bulge as blobs pass.
        func pool(_ y: Double, _ ph: Double) {
            let rx = 200 * sc * (w / h) / 1.77
            for i in 0..<5 {
                let fi = Double(i)
                let cx = w * (fi + 0.5) / 5 + 30 * sc * sin(p + fi + ph)
                let ry = (70 + 25 * sin(p * 2 + fi * 1.7 + ph)) * sc
                out.append(SIMD4(Float(cx), Float(y), Float(rx), Float(ry)))
            }
        }
        pool(h + 30 * sc, 0)
        pool(-40 * sc, 2)

        for b in blobs {
            let r = b.r * sc
            let s = sin(p * b.f + b.ph)
            let cy = h / 2 - s * (h / 2 + r * 0.2)
            let cx = w * (b.x + b.dx * sin(p * (b.f + 1) + b.ph * 1.3))
            // Stretch while moving fast, squash near the pools.
            let v = abs(cos(p * b.f + b.ph))
            out.append(SIMD4(Float(cx), Float(cy), Float(r * (1 - 0.12 * v)), Float(r * (1 + 0.22 * v))))
        }
        return out
    }

    /// Centers of the two moving body glows (points).
    static func glowCenters(w: Double, h: Double, p: Double) -> SIMD4<Float> {
        SIMD4(
            Float(w * (0.50 + 0.18 * sin(p))), Float(h * (0.75 + 0.08 * cos(p))),
            Float(w * (0.20 + 0.10 * cos(p))), Float(h * 0.20)
        )
    }
}

// MARK: - Metal

/// Mirrors `U` in the shader; all fields are float4 so the layouts match without padding rules.
private struct LampUniforms {
    var size: SIMD4<Float>        // w, h (pt), sc, pixels per point
    var params: SIMD4<Float>      // intensity, overlay, merge radius, shape count
    var glowCenters: SIMD4<Float>
    var top, mid, bot, wax0, wax1, glow, glow2: SIMD4<Float>
    var output: SIMD4<Float>      // EDR boost (linear multiplier), lift 0…1, unused ×2
}

@MainActor
final class LampRenderer {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    /// Half-float so values above 1.0 reach the display as EDR.
    static let pixelFormat = MTLPixelFormat.rgba16Float

    init?() {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let queue = device.makeCommandQueue()
        else { return nil }
        do {
            // Compiled at launch so the SwiftPM build needs no Metal toolchain.
            let library = try device.makeLibrary(source: lampShaderSource, options: nil)
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: "lampVertex")
            desc.fragmentFunction = library.makeFunction(name: "lampFragment")
            desc.colorAttachments[0].pixelFormat = Self.pixelFormat
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            NSLog("Sunrise: lamp shader failed: \(error)")
            return nil
        }
        self.device = device
        self.queue = queue
    }

    func encode(
        pass: MTLRenderPassDescriptor, commandBuffer: MTLCommandBuffer,
        sizePt: CGSize, pixelsPerPoint: CGFloat, date: Date,
        palette: LavaPalette, intensity: Double, overlay: Double, boost: Double = 1, lift: Double = 0
    ) {
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let w = Double(sizePt.width), h = Double(sizePt.height)
        let p = LavaGeometry.phase(at: date)
        var shapes = LavaGeometry.shapes(w: w, h: h, p: p)
        let sc = Float(h / 700)
        var u = LampUniforms(
            size: SIMD4(Float(w), Float(h), sc, Float(pixelsPerPoint)),
            // Merge radius: how eagerly blobs bridge — stands in for the prototype's 28·sc goo blur.
            params: SIMD4(Float(intensity), Float(overlay), 20 * sc, Float(shapes.count)),
            glowCenters: LavaGeometry.glowCenters(w: w, h: h, p: p),
            top: palette.top, mid: palette.mid, bot: palette.bot,
            wax0: palette.wax0, wax1: palette.wax1, glow: palette.glow, glow2: palette.glow2,
            output: SIMD4(Float(boost), Float(lift), 0, 0)
        )
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<LampUniforms>.stride, index: 0)
        enc.setFragmentBytes(&shapes, length: MemoryLayout<SIMD4<Float>>.stride * shapes.count, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    var commandQueue: MTLCommandQueue { queue }
}

private struct LampMetalView: NSViewRepresentable {
    @ObservedObject var state: AppState

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.colorPixelFormat = LampRenderer.pixelFormat
        view.clearColor = MTLClearColor(red: 0.0103, green: 0.0037, blue: 0.0015, alpha: 1) // #1a0c05, linear
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 120
        if let layer = view.layer as? CAMetalLayer {
            // The shader blends in sRGB like CSS, then outputs linear light; values above 1.0 are EDR.
            layer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        }
        if let renderer = context.coordinator.renderer {
            view.device = renderer.device
            view.delegate = context.coordinator
        }
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.state = state
    }

    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        var state: AppState
        let renderer = LampRenderer()

        /// Smoothed "sunlight" lift, so it eases in and out instead of snapping.
        private var lift = 0.0
        private var lastFrame = Date()

        init(state: AppState) { self.state = state }

        nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        nonisolated func draw(in view: MTKView) {
            MainActor.assumeIsolated { render(view) }
        }

        private func render(_ view: MTKView) {
            guard
                let renderer,
                let pass = view.currentRenderPassDescriptor,
                let drawable = view.currentDrawable,
                let cb = renderer.commandQueue.makeCommandBuffer()
            else { return }
            let now = Date()
            // The lamp is barely visible while armed — no need for 120 fps all night.
            view.preferredFramesPerSecond = state.phase == .armed ? 30 : 120
            let size = view.bounds.size
            let ppp = size.width > 0 ? view.drawableSize.width / size.width : 2
            let overlay = state.overlayOpacity(at: now)
            let sunrise = state.hdrBoost && (state.phase == .ringing || state.previewStart != nil)
            renderer.encode(
                pass: pass, commandBuffer: cb, sizePt: size, pixelsPerPoint: ppp, date: now,
                palette: LavaPalette.named(state.palette), intensity: state.intensity,
                overlay: overlay, boost: edrBoost(view, brightness: 1 - overlay),
                lift: sunLift(sunrise: sunrise, brightness: 1 - overlay, now: now)
            )
            cb.present(drawable)
            cb.commit()
        }

        /// Near the peak of the sunrise the lamp's colors lighten: more light from the same backlight.
        private func sunLift(sunrise: Bool, brightness: Double, now: Date) -> Double {
            let dt = min(now.timeIntervalSince(lastFrame), 0.1)
            lastFrame = now
            let x = min(max((brightness - 0.55) / 0.45, 0), 1)
            let target = sunrise ? x * x * (3 - 2 * x) : 0
            lift += (target - lift) * min(1, dt * 2.5)
            return lift
        }

        /// Pushes the lamp past SDR white while the sunrise runs (requested only then).
        /// On XDR panels this reaches ~1000 nits full-screen. An SDR panel (MacBook Air) grants only
        /// ~1.25× for a full-screen layer — there the backlight (`Backlight`) does the heavy lifting.
        private func edrBoost(_ view: MTKView, brightness: Double) -> Double {
            let wanted = state.hdrBoost && (state.phase == .ringing || state.previewStart != nil)
            if let layer = view.layer as? CAMetalLayer, layer.wantsExtendedDynamicRangeContent != wanted {
                layer.wantsExtendedDynamicRangeContent = wanted
            }
            guard wanted, let screen = view.window?.screen else { return 1 }
            // Current headroom: macOS ramps it up over a second or two after EDR is requested,
            // and scaling to it (rather than the potential) avoids clipping and hue shifts.
            let headroom = Double(screen.maximumExtendedDynamicRangeColorComponentValue)
            let b = min(max(brightness, 0), 1)
            return 1 + (max(headroom, 1) - 1) * b * b
        }
    }
}

// MARK: - Shader

private let lampShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct U {
    float4 size;        // w, h (pt), sc, pixels per point
    float4 params;      // intensity, overlay, merge radius, count
    float4 glowCenters; // glow.xy, glow2.xy (pt)
    float4 top, mid, bot, wax0, wax1, glow, glow2;
    float4 output;      // EDR boost, lift, unused ×2
};

// Screen-style lighten: brighter, hue mostly kept.
static float3 lighten(float3 c, float k) {
    return 1.0 - (1.0 - c) * (1.0 - k);
}

static float3 srgbToLinear(float3 c) {
    return select(pow((c + 0.055) / 1.055, 2.4), c / 12.92, c <= 0.04045);
}

struct VOut { float4 pos [[position]]; };

// One triangle covering the screen.
vertex VOut lampVertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    VOut o;
    o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return o;
}

// Source-over with straight alpha, blended in sRGB space like CSS.
static float3 over(float3 base, float4 c, float a) {
    return mix(base, c.rgb, clamp(c.a * a, 0.0, 1.0));
}

// CSS radial-gradient(rx ry at c, color, transparent stop): linear falloff inside the ellipse.
static float radialFalloff(float2 p, float2 c, float2 r, float stop) {
    return 1.0 - clamp(length((p - c) / r) / stop, 0.0, 1.0);
}

fragment float4 lampFragment(VOut in [[stage_in]],
                             constant U& u [[buffer(0)]],
                             constant float4* shapes [[buffer(1)]]) {
    float W = u.size.x, H = u.size.y, sc = u.size.z;
    float2 p = in.pos.xy / u.size.w;          // points, y down
    float intensity = u.params.x;
    float k = u.params.z;
    int count = int(u.params.w);

    // 1. Lamp body: top → mid → bot, plus corner shade and two drifting glows.
    float ty = clamp(p.y / H, 0.0, 1.0);
    float lift = u.output.y;      // 0 normally, → 1 near the peak of the sunrise
    float3 col = ty < 0.5 ? mix(u.top.rgb, u.mid.rgb, ty * 2.0) : mix(u.mid.rgb, u.bot.rgb, ty * 2.0 - 1.0);
    // Orange body → light peach: pull toward a lightened bottom color so it stays saturated
    // (lightening toward white turns the dark top into dusty pink).
    col = mix(col, lighten(u.bot.rgb, 0.4), 0.7 * lift);
    // Shadows eat light: fade them out as the sun comes up.
    float shade = 1.0 - 0.7 * lift;
    col = over(col, float4(0, 0, 0, 0.35 * shade), radialFalloff(p, float2(W, 0), float2(0.8 * W, 0.9 * H), 0.6));
    col = over(col, u.glow2, radialFalloff(p, u.glowCenters.zw, float2(0.45 * W, 0.55 * H), 0.7));
    col = over(col, u.glow, radialFalloff(p, u.glowCenters.xy, float2(0.6 * W, 0.7 * H), 0.7));

    // 2. Wax: exponential smooth union of ellipse distances — blobs bridge as they approach.
    float sum = 0.0, waxT = 0.0;
    for (int i = 0; i < count; i++) {
        float4 s = shapes[i];
        float2 v = p - s.xy;
        float q = length(v / s.zw);
        float len = length(v);
        // Radial distance to the ellipse edge along the ray from its center.
        float rr = len > 1e-3 ? len / max(q, 1e-5) : min(s.z, s.w);
        float d = (q - 1.0) * rr;
        float w = exp(-d / k);
        sum += w;
        // Wax gradient: from each shape's bottom center, radius 110% of its box.
        waxT += w * length((p - float2(s.x, s.y + s.w)) / (2.2 * s.zw));
    }
    float d = -k * log(max(sum, 1e-30));
    float t = clamp(waxT / max(sum, 1e-30), 0.0, 1.0);

    // Soft glow under the wax (≈ the prototype's 60·sc blur).
    float glow = 0.5 * (1.0 - tanh(d / (72.0 * sc)));
    col = over(col, float4(lighten(u.wax1.rgb, 0.5 * lift), 1.0), 0.55 * intensity * glow);

    // Anti-aliased wax edge, one pixel wide whatever the field's slope (d isn't a true distance near bridges).
    float wax = clamp(0.5 - d / max(fwidth(d), 1e-4), 0.0, 1.0);
    // Yellow wax → pale cream.
    float3 waxCol = lighten(mix(u.wax0.rgb, u.wax1.rgb, t), 0.45 * lift);
    col = over(col, float4(waxCol, 1.0), min(1.0, 0.95 * intensity) * wax);

    // 3. Horizontal glass sheen, edges darkened to 0.3.
    float x = p.x / W;
    if (x < 0.18)      col = over(col, float4(0, 0, 0, 0.3 * shade), 1.0 - x / 0.18);
    else if (x < 0.30) col = over(col, float4(1, 1, 1, 0.06), (x - 0.18) / 0.12);
    else if (x < 0.42) col = over(col, float4(1, 1, 1, 0.06), 1.0 - (x - 0.30) / 0.12);
    else if (x > 0.80) col = over(col, float4(0, 0, 0, 0.3 * shade), (x - 0.80) / 0.20);

    // 4. Brightness layer: black at opacity max(1 − brightness, dim).
    col *= 1.0 - clamp(u.params.y, 0.0, 1.0);

    // 5. Linear light for the extended-range layer, scaled past 1.0 at the peak of the sunrise.
    return float4(srgbToLinear(col) * u.output.x, 1.0);
}
"""
