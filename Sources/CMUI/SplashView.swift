#if os(macOS)
import AppKit
import AVFoundation

/// Startup animation: the bundled 1024 px clip on OLED black, centred in the phone window. It is shown at
/// most 512 pt wide (1024 device pixels on a Retina display, so it is never upscaled) and fitted inside
/// narrower windows. Fades out and removes itself when the clip is over.
@MainActor
final class SplashView: NSView {
    static let maxSide: CGFloat = 512
    static let clipDuration: Duration = .seconds(3)

    private let player: AVPlayer
    private let playerLayer: AVPlayerLayer

    /// nil when the clip is not bundled (a bare `swift run` binary).
    init?(frame: NSRect, clip: URL? = Bundle.main.url(forResource: "CarbonMirror-startup", withExtension: "mp4")) {
        guard let clip else { return nil }
        player = AVPlayer(url: clip)
        playerLayer = AVPlayerLayer(player: player)
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
        player.play()
        // Timed, not notification-driven: a clip that fails to play can never leave the splash on screen.
        Task { [weak self] in
            try? await Task.sleep(for: Self.clipDuration)
            self?.finish()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// Centred square, snapped to device pixels so the clip is not resampled off-grid.
    override func layout() {
        super.layout()
        let side = min(Self.maxSide, bounds.width, bounds.height)
        let square = NSRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = backingAlignedRect(square, options: .alignAllEdgesNearest)
        CATransaction.commit()
    }

    private func finish() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.player.pause()
                self?.removeFromSuperview()
            }
        })
    }
}
#endif
