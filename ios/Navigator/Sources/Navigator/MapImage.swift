import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Grey of the streets, darker than the blue route and the white text on the band.
private let streetGrey = 0x4a

/// `streets` around `anchor` as a PNG `width`×`height` band px, north up at `Tuning.metresPerPx`, `anchor` in the
/// middle: the grey layer as one picture holding every street, for the band to move instead of hundreds of divs
/// (#15). Grey 4 px lines on black. `bits` per pixel (1, 2 or 4) sets the shades between black and the
/// grey: an indexed PNG of 1 bit is about a fifth of an 8-bit grey one (8.5 KB against 47 KB for 312×450 of Hà Nội),
/// more bits keep the antialiased edges.
public func mapImage(_ streets: [[Point]], around anchor: Point, width: Int, height: Int, bits: Int = 1) -> Data? {
    precondition([1, 2, 4].contains(bits))
    var gray = [UInt8](repeating: 0, count: width * height)
    let drawn = gray.withUnsafeMutableBytes { buf -> Bool in
        guard let ctx = CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
        ctx.setLineWidth(4)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(gray: CGFloat(streetGrey) / 255, alpha: 1)
        // CoreGraphics has y up and its first row in memory is the top: north is +y.
        let w = Double(width), h = Double(height)
        for street in streets where street.count > 1 {
            ctx.addLines(between: street.map { p in
                let (e, n) = local(anchor, p)
                return CGPoint(x: w / 2 + e / Tuning.metresPerPx, y: h / 2 + n / Tuning.metresPerPx)
            })
        }
        ctx.strokePath()
        return true
    }
    guard drawn else { return nil }

    let perByte = 8 / bits, row = (width + perByte - 1) / perByte, top = (1 << bits) - 1
    var packed = [UInt8](repeating: 0, count: row * height)
    for y in 0..<height {
        for x in 0..<width {
            let level = min((Int(gray[y * width + x]) * top + streetGrey / 2) / streetGrey, top)
            packed[y * row + x / perByte] |= UInt8(level) << ((perByte - 1 - x % perByte) * bits)
        }
    }
    let table = (0...top).flatMap { [UInt8](repeating: UInt8(streetGrey * $0 / top), count: 3) }
    guard let space = CGColorSpace(indexedBaseSpace: CGColorSpaceCreateDeviceRGB(), last: top, colorTable: table),
          let provider = CGDataProvider(data: Data(packed) as CFData),
          let image = CGImage(width: width, height: height, bitsPerComponent: bits, bitsPerPixel: bits,
                              bytesPerRow: row, space: space, bitmapInfo: [], provider: provider, decode: nil,
                              shouldInterpolate: false, intent: .defaultIntent)
    else { return nil }
    let png = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest) ? png as Data : nil
}
