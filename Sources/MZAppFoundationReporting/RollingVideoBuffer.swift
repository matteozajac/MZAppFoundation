#if os(iOS)
@preconcurrency import AVFoundation
import CoreImage
import ImageIO
import ReplayKit
import Synchronization

/// ReplayKit calls ingest on its capture queue. The mutex owns every encoder value,
/// including finalization callbacks; no raw frames are queued or retained by us.
final class RollingVideoBuffer: Sendable {
    private struct Encoding {
        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
        let start: CMTime
        var last: CMTime
        let url: URL
    }

    private struct State {
        var accepting = true
        var encoding: Encoding?
        var segments: [VideoSegment] = []
        var finishing: [URL: AVAssetWriter] = [:]
        var discarded: Set<URL> = []
        var error: String?
        var didReportFailure = false
        var latest: Double = 0
        let context = CIContext(options: [.cacheIntermediates: false])
    }

    private let state = Mutex(State())
    private let pending = DispatchGroup()
    let directory: URL

    init(directory: URL) { self.directory = directory }

    func ingest(_ sample: CMSampleBuffer) {
        state.withLock { state in
            guard state.accepting, state.error == nil,
                  let source = CMSampleBufferGetImageBuffer(sample) else { return }
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
            guard timestamp.isValid, timestamp.seconds.isFinite else { return }
            if let current = state.encoding {
                guard timestamp > current.last else { return }
                guard (timestamp - current.last).seconds >= 1.0 / 15.0 else { return }
                if (timestamp - current.start).seconds >= 5 {
                    finish(&state, endingAt: timestamp)
                }
            }
            do {
                if state.encoding == nil {
                    // Bound the number of asynchronously finalizing files as well as frame memory.
                    guard state.finishing.count < 2 else { return }
                    state.encoding = try makeEncoding(at: timestamp)
                }
                guard var encoding = state.encoding, encoding.input.isReadyForMoreMediaData,
                      let pool = encoding.adaptor.pixelBufferPool else { return }
                var target: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &target) == kCVReturnSuccess, let target else {
                    throw CaptureError.encoding
                }
                var frame = CIImage(cvPixelBuffer: source)
                if let raw = CMGetAttachment(sample, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
                   let orientation = CGImagePropertyOrientation(rawValue: raw.uint32Value) {
                    frame = frame.oriented(orientation)
                }
                let extent = frame.extent
                let scale = min(720 / extent.width, 1280 / extent.height)
                frame = frame.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
                    .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                    .transformed(by: CGAffineTransform(translationX: (720 - extent.width * scale) / 2, y: (1280 - extent.height * scale) / 2))
                let canvas = CGRect(x: 0, y: 0, width: 720, height: 1280)
                frame = frame.composited(over: CIImage(color: .black).cropped(to: canvas))
                state.context.render(frame, to: target, bounds: canvas, colorSpace: CGColorSpaceCreateDeviceRGB())
                guard encoding.adaptor.append(target, withPresentationTime: timestamp) else {
                    throw encoding.writer.error ?? CaptureError.encoding
                }
                encoding.last = timestamp
                state.encoding = encoding
                state.latest = timestamp.seconds + 1.0 / 15.0
                prune(&state)
            } catch {
                state.error = error.localizedDescription
                state.accepting = false
                state.encoding?.writer.cancelWriting()
                state.encoding = nil
            }
        }
    }

    func takeFailure() -> String? {
        state.withLock { state in
            guard !state.didReportFailure, let error = state.error else { return nil }
            state.didReportFailure = true
            return error
        }
    }

    /// Synchronously closes the gate before the diagnostics UI is presented.
    func freeze() {
        state.withLock { state in
            state.accepting = false
            finish(&state)
        }
    }

    func snapshot() async throws -> [VideoSegment] {
        await withCheckedContinuation { continuation in
            pending.notify(queue: .global(qos: .utility)) { continuation.resume() }
        }
        return try state.withLock { state in
            if let error = state.error { throw CaptureError.failed(error) }
            prune(&state)
            return state.segments.sorted { $0.start < $1.start }
        }
    }

    private func makeEncoding(at timestamp: CMTime) throws -> Encoding {
        let free = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        guard free > 64 * 1024 * 1024 else { throw CaptureError.storage }
        let url = directory.appendingPathComponent(UUID().uuidString + ".mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 720, AVVideoHeightKey: 1280,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_000_000,
                                              AVVideoExpectedSourceFrameRateKey: 15,
                                              AVVideoMaxKeyFrameIntervalKey: 15]
        ])
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 720, kCVPixelBufferHeightKey as String: 1280,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        guard writer.canAdd(input) else { throw CaptureError.encoding }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CaptureError.encoding }
        writer.startSession(atSourceTime: timestamp)
        return Encoding(writer: writer, input: input, adaptor: adaptor, start: timestamp, last: timestamp, url: url)
    }

    private func finish(_ state: inout State, endingAt boundary: CMTime? = nil) {
        guard let encoding = state.encoding else { return }
        state.encoding = nil
        let end = boundary ?? (encoding.last + CMTime(value: 1, timescale: 15))
        encoding.writer.endSession(atSourceTime: end)
        encoding.input.markAsFinished()
        state.segments.append(VideoSegment(url: encoding.url, start: encoding.start.seconds, end: end.seconds, bytes: 0))
        state.finishing[encoding.url] = encoding.writer
        pending.enter()
        let url = encoding.url
        encoding.writer.finishWriting { [self] in
            self.state.withLock { state in
                guard let writer = state.finishing.removeValue(forKey: url) else { return }
                if state.discarded.remove(url) != nil {
                    try? FileManager.default.removeItem(at: url)
                } else if writer.status != .completed {
                    state.error = writer.error?.localizedDescription ?? BugReportStrings.text("bug_encoding_failed")
                } else if let index = state.segments.firstIndex(where: { $0.url == url }) {
                    state.segments[index].bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    prune(&state)
                }
            }
            pending.leave()
        }
    }

    private func prune(_ state: inout State) {
        // Reserve a segment's budget for the active writer, including pending finalizations.
        let candidates = state.segments.map { segment in
            var segment = segment
            if state.finishing[segment.url] != nil { segment.bytes = 2 * 1024 * 1024 }
            return segment
        }
        let retained = VideoRetention.retained(candidates, endingAt: state.latest, byteLimit: VideoRetention.byteLimit - (1 + state.discarded.count) * 2 * 1024 * 1024)
        let keep = Set(retained.map(\.url))
        for segment in state.segments where !keep.contains(segment.url) {
            if state.finishing[segment.url] != nil {
                state.discarded.insert(segment.url)
            } else {
                try? FileManager.default.removeItem(at: segment.url)
            }
        }
        state.segments.removeAll { !keep.contains($0.url) }
    }
}

enum CaptureError: LocalizedError {
    case encoding, storage, noVideo, failed(String)

    var errorDescription: String? {
        switch self {
        case .encoding: BugReportStrings.text("bug_encoding_failed")
        case .storage: BugReportStrings.text("bug_storage_low")
        case .noVideo: BugReportStrings.text("bug_video_unavailable")
        case .failed(let message): message
        }
    }
}

#endif
