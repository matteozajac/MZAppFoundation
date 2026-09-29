#if os(iOS)
import AVKit
import SwiftUI

struct VideoTrimView: View {
    let url: URL
    let duration: Double
    @Binding var start: Double
    @Binding var end: Double
    @State private var player = AVPlayer()
    @State private var thumbnails: [UIImage] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VideoPlayer(player: player).frame(height: 240)
            HStack(spacing: 2) {
                ForEach(thumbnails.indices, id: \.self) { index in
                    Image(uiImage: thumbnails[index]).resizable().scaledToFit()
                }
            }.frame(height: 56).accessibilityHidden(true)
            LabeledContent(BugReportStrings.text("bug_trim_start"), value: String(format: "%.1f s", start))
            Slider(value: $start, in: 0...max(0.001, end - min(0.1, duration)))
                .disabled(duration <= 0.1)
                .accessibilityLabel(BugReportStrings.text("bug_trim_start"))
                .onChange(of: start) { _, value in
                    player.seek(to: CMTime(seconds: value, preferredTimescale: 600))
                }
            LabeledContent(BugReportStrings.text("bug_trim_end"), value: String(format: "%.1f s", end))
            Slider(value: $end, in: min(start + min(0.1, duration), duration)...max(0.001, duration))
                .disabled(duration <= 0.1)
                .accessibilityLabel(BugReportStrings.text("bug_trim_end"))
                .onChange(of: end) { _, value in
                    player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: value, preferredTimescale: 600)
                }
            Text(String(format: BugReportStrings.text("bug_trim_duration"), max(0, end - start)))
                .font(.caption).foregroundStyle(.secondary)
        }
        .task(id: url) {
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600)
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 120, height: 120)
            var images: [UIImage] = []
            for index in 0..<6 {
                guard !Task.isCancelled else { return }
                let time = CMTime(seconds: duration * Double(index) / 6, preferredTimescale: 600)
                if let image = try? await generator.image(at: time).image { images.append(UIImage(cgImage: image)) }
            }
            thumbnails = images
        }
        .onDisappear { player.pause() }
    }
}

#endif
