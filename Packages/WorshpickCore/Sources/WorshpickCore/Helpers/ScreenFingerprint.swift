import CoreGraphics
import Foundation

/// A 64×36 grayscale thumbnail. Lyric screens share their background and differ only in text,
/// so tiny hashes (like a 9×8 dHash) see them as the same screen; this size keeps the text visible.
public struct ScreenFingerprint: Sendable, Equatable {
    static let width = 64
    static let height = 36

    let grayscalePixels: [UInt8]

    public init(of image: CGImage) {
        var pixels = [UInt8](repeating: 0, count: Self.width * Self.height)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: Self.width, height: Self.height, bitsPerComponent: 8,
                bytesPerRow: Self.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: Self.width, height: Self.height))
        }
        grayscalePixels = pixels
    }

    /// Mean absolute pixel difference, from 0 (identical) to 255.
    public func difference(from other: ScreenFingerprint) -> Double {
        let totalDifference = zip(grayscalePixels, other.grayscalePixels).reduce(0) { total, pair in
            total + abs(Int(pair.0) - Int(pair.1))
        }
        return Double(totalDifference) / Double(grayscalePixels.count)
    }
}
