import CoreGraphics
import Foundation
import ImageIO

/// A game's picture, decoded once by the host: the 16:9 key art (the eShop banner) or the square NACP icon.
/// The views only draw it. A tiny copy and the mean colour are made here, so the blurred backgrounds stay cheap.
public struct Artwork: Equatable, @unchecked Sendable {
    public let id: String
    let image: CGImage
    /// About 48 px across. Scaled up and blurred, it gives the same backdrop as the full picture for a fraction of the work.
    let thumbnail: CGImage
    /// The picture's mean colour in sRGB, 0 to 1.
    let tone: (red: Double, green: Double, blue: Double)

    public init(id: String, image: CGImage) {
        self.id = id
        self.image = image
        thumbnail = Self.redraw(image, width: 48, height: max(1, Int(48 / max(0.25, CGFloat(image.width) / CGFloat(max(1, image.height)))))) ?? image
        tone = Self.meanColour(of: thumbnail)
    }

    /// PNG, JPEG or HEIC bytes, as the NACP icon comes. Nil when ImageIO cannot read them.
    public init?(id: String, data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        self.init(id: id, image: image)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && lhs.image === rhs.image }

    var aspectRatio: CGFloat { CGFloat(image.width) / CGFloat(max(1, image.height)) }

    private static func redraw(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func meanColour(of image: CGImage) -> (red: Double, green: Double, blue: Double) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn: Bool = pixel.withUnsafeMutableBytes { buffer in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return (0.2, 0.2, 0.22) }
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }
}

/// A stable number from a string. `hashValue` changes with every launch, and a placeholder should not.
func stableHash(_ text: String) -> UInt64 {
    text.utf8.reduce(UInt64(5381)) { ($0 &* 33) ^ UInt64($1) }
}
