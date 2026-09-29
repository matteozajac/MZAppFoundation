#if os(iOS)
@preconcurrency import AVFoundation

actor VideoExporter {
    func combine(_ segments: [VideoSegment], to url: URL) async throws -> Double {
        guard let last = segments.last else { throw CaptureError.noVideo }
        let cutoff = last.end - VideoRetention.duration
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CaptureError.encoding
        }
        var cursor = CMTime.zero
        for segment in segments where segment.end > cutoff {
            try Task.checkCancellation()
            let asset = AVURLAsset(url: segment.url)
            guard let source = try await asset.loadTracks(withMediaType: .video).first else { continue }
            let range = try await source.load(.timeRange)
            let skip = CMTime(seconds: max(0, cutoff - segment.start), preferredTimescale: 600)
            let remaining = range.duration - skip
            guard remaining > .zero else { continue }
            let duration = min(remaining, CMTime(seconds: 60, preferredTimescale: 600) - cursor)
            guard duration > .zero else { break }
            try track.insertTimeRange(CMTimeRange(start: range.start + skip, duration: duration), of: source, at: cursor)
            cursor = cursor + duration
        }
        guard cursor > .zero else { throw CaptureError.noVideo }
        try await export(composition, range: CMTimeRange(start: .zero, duration: cursor), to: url)
        return cursor.seconds
    }

    func trim(_ source: URL, range: ClosedRange<Double>, to url: URL) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        let selection = VideoRetention.trim(start: range.lowerBound, end: range.upperBound, available: duration)
        guard selection.upperBound > selection.lowerBound else { throw CaptureError.noVideo }
        try await export(asset, range: CMTimeRange(
            start: CMTime(seconds: selection.lowerBound, preferredTimescale: 600),
            duration: CMTime(seconds: selection.upperBound - selection.lowerBound, preferredTimescale: 600)
        ), to: url)
    }

    private func export(_ asset: AVAsset, range: CMTimeRange, to url: URL) async throws {
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            throw CaptureError.encoding
        }
        export.timeRange = range
        export.shouldOptimizeForNetworkUse = true
        try await export.export(to: url, as: .mp4)
    }
}

#endif
