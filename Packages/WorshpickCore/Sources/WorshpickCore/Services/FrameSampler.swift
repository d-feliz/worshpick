import AVFoundation
import CoreGraphics
import Foundation

/// CGImage is immutable, so sharing frames across tasks is safe.
public struct SampledFrame: @unchecked Sendable {
    public let timestamp: TimeInterval
    public let image: CGImage

    public init(timestamp: TimeInterval, image: CGImage) {
        self.timestamp = timestamp
        self.image = image
    }
}

public enum FrameSamplerError: Error, Equatable, LocalizedError {
    case unreadableVideo

    public var errorDescription: String? { "No se puede leer el video" }
}

public protocol FrameSampling: Sendable {
    func sampleFrames(from videoURL: URL, interval: TimeInterval) async throws -> [SampledFrame]
}

public struct FrameSampler: FrameSampling {
    public static let defaultInterval: TimeInterval = 1.5
    public static let defaultMaximumFrameCount = 120
    static let maximumDifferenceForSameScreen = 1.0
    static let maximumFrameWidth: CGFloat = 1280

    public var maximumFrameCount: Int

    public init(maximumFrameCount: Int = defaultMaximumFrameCount) {
        self.maximumFrameCount = maximumFrameCount
    }

    public func sampleFrames(from videoURL: URL, interval: TimeInterval = defaultInterval) async throws -> [SampledFrame] {
        let asset = AVURLAsset(url: videoURL)
        let duration: Double
        do {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard !videoTracks.isEmpty else { throw FrameSamplerError.unreadableVideo }
            duration = try await asset.load(.duration).seconds
        } catch {
            throw FrameSamplerError.unreadableVideo
        }
        guard duration.isFinite, duration > 0 else { throw FrameSamplerError.unreadableVideo }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: Self.maximumFrameWidth, height: Self.maximumFrameWidth)
        let tolerance = CMTime(seconds: min(0.25, interval / 4), preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        // Sample the middle of each interval so fades between screens are less likely.
        let sampleTimes = stride(from: interval / 2, to: duration, by: interval).map { CMTime(seconds: $0, preferredTimescale: 600) }

        var distinctFrames: [SampledFrame] = []
        var lastKeptFingerprint: ScreenFingerprint?
        for await result in generator.images(for: sampleTimes) {
            guard let image = try? result.image else { continue }
            let fingerprint = ScreenFingerprint(of: image)
            let isSameScreenAsLastKept = lastKeptFingerprint.map { $0.difference(from: fingerprint) <= Self.maximumDifferenceForSameScreen } ?? false
            if isSameScreenAsLastKept { continue }
            lastKeptFingerprint = fingerprint
            distinctFrames.append(SampledFrame(timestamp: result.requestedTime.seconds, image: image))
        }
        return distinctFrames.evenlySpaced(count: maximumFrameCount)
    }
}
