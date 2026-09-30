// Turns the classic icon (824×824 rounded square at 100,100 on a 1024 canvas, radius ≈184)
// into full-bleed square artwork for macOS 26, where the system applies the shape itself.
// Transparent corners are filled by projecting each pixel back onto the rounded edge.
//   swift scripts/icon-fullbleed.swift <classic.png> <out.png>
import AppKit

let args = CommandLine.arguments
let src = NSImage(contentsOf: URL(fileURLWithPath: args[1]))!
var r = CGRect(x: 0, y: 0, width: 1024, height: 1024)
let cg = src.cgImage(forProposedRect: &r, context: nil, hints: nil)!
let n = 1024
var px = [UInt8](repeating: 0, count: n * n * 4)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let info = CGImageAlphaInfo.premultipliedLast.rawValue
CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: space, bitmapInfo: info)!
    .draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))

// Shape, inset a few px to skip the anti-aliased rim.
let inset = 6.0
let lo = 100.0 + inset, hi = 923.0 - inset, radius = 184.0 - inset

func sample(_ x: Double, _ y: Double) -> [UInt8] {
    let xi = min(max(Int(x.rounded()), 0), n - 1), yi = min(max(Int(y.rounded()), 0), n - 1)
    let i = (yi * n + xi) * 4
    return [px[i], px[i + 1], px[i + 2], 255]
}

let side = Int(hi - lo)
var out = [UInt8](repeating: 0, count: side * side * 4)
for oy in 0..<side {
    for ox in 0..<side {
        var x = lo + Double(ox) + 0.5, y = lo + Double(oy) + 0.5
        // Corner zone: pull the point onto the arc, slightly inside it.
        let cx = x < lo + radius ? lo + radius : (x > hi - radius ? hi - radius : x)
        let cy = y < lo + radius ? lo + radius : (y > hi - radius ? hi - radius : y)
        let dx = x - cx, dy = y - cy, d = (dx * dx + dy * dy).squareRoot()
        if d > radius - 2 {
            let k = (radius - 2) / d
            x = cx + dx * k; y = cy + dy * k
        }
        let c = sample(x, y)
        let o = (oy * side + ox) * 4
        out[o] = c[0]; out[o + 1] = c[1]; out[o + 2] = c[2]; out[o + 3] = 255
    }
}

let outCtx = CGContext(data: &out, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: space, bitmapInfo: info)!
let square = outCtx.makeImage()!
// Scale to 1024.
let final = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
final.interpolationQuality = .high
final.draw(square, in: CGRect(x: 0, y: 0, width: n, height: n))
let rep = NSBitmapImageRep(cgImage: final.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2])")
