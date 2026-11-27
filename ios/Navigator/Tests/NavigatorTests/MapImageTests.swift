import CoreGraphics
import Foundation
import ImageIO
import Navigator
import XCTest

/// The PNG's pixels as 8-bit grey, first row at the top.
func pixels(_ png: Data) throws -> (w: Int, h: Int, grey: [UInt8]) {
    let image = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
    var grey = [UInt8](repeating: 0, count: image.width * image.height)
    grey.withUnsafeMutableBytes { buf in
        CGContext(data: buf.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                  bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
            .draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return (image.width, image.height, grey)
}

final class MapImageTests: XCTestCase {
    let o = Point(lat: 21, lon: 105.8)
    func at(east: Double, north: Double) -> Point {
        Point(lat: o.lat + north / 111_320, lon: o.lon + east / (111_320 * cos(o.lat * .pi / 180)))
    }

    func testAStreetNorthOfTheMiddleIsDrawnAboveItInGreyOnBlack() throws {
        // 100 m west to east, 100 m north of the middle: 50 px at 2 m/px, so row 150 - 50 = 100 of 300.
        let street = [at(east: -100, north: 100), at(east: 100, north: 100)]
        let png = try XCTUnwrap(mapImage([street], around: o, width: 200, height: 300))
        // Indexed PNG, 1 bit a pixel: IHDR bit depth then colour type 3.
        XCTAssertEqual(Array(png[24...25]), [1, 3])
        let (w, h, grey) = try pixels(png)
        XCTAssertEqual([w, h], [200, 300])
        XCTAssertEqual(grey[100 * w + 100], 0x4a)
        XCTAssertEqual(grey[200 * w + 100], 0, "south of the middle is empty")
        XCTAssertEqual(grey[100 * w + 10], 0, "past the street's west end")
    }

    func testMoreBitsKeepTheShadesAtTheEdges() throws {
        // A diagonal has antialiased edges: shades between black and the grey with 2 bits, none with 1.
        let street = [at(east: -100, north: -100), at(east: 100, north: 100)]
        let shades = { (bits: Int) in try Set(pixels(XCTUnwrap(mapImage([street], around: self.o, width: 200, height: 200, bits: bits))).grey) }
        XCTAssertEqual(try shades(1), [0, 0x4a])
        XCTAssertGreaterThan(try shades(2).count, 2)
    }

    func testEveryLayerAlongTheFixtureRouteFitsTheBandsMessage() throws {
        let map = try StreetMap(deflated: Data(contentsOf: URL(fileURLWithPath: #filePath)
            .appending(path: "../../../../Maps4MiBand/hanoi-streets.bin").standardized))
        let route = try Vietmap.parse(fixture, status: 200).points
        let streets = map.along(route)
        // A layer at every route point, 312×450 as Navigator sends them: base64 well under the 16 KB the band takes.
        for p in route {
            let png = try XCTUnwrap(mapImage(streets, around: p, width: 312, height: 450))
            XCTAssertLessThan(png.base64EncodedString().count, 13_000)
        }
    }
}
