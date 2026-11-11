#if os(macOS)
import AppKit
import CMCore
import CMCoreBridge

/// `--demo`: cycles every status state, reveals and hides the hover chrome, and resizes between the size
/// limits with the aspect ratio locked (Checkpoint 2), looping until quit.
@MainActor
final class DemoDriver {
    private let controller: PhoneWindowController
    private var task: Task<Void, Never>?

    init(controller: PhoneWindowController) {
        self.controller = controller
    }

    func start() {
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.runOnce()
            }
        }
    }

    func stop() {
        task?.cancel()
    }

    private func runOnce() async {
        for state in UIStateCode.allCases where state != .retryingSilently {
            controller.show(state: state)
            await pause(1.6)
        }
        controller.show(state: .notPaired)
        controller.setChrome(shown: true)
        await pause(1.5)
        for scale in [SizeMath.minScale, 1, SizeMath.maxScale, 1] {
            controller.setScale(scale)
            await pause(1.5)
        }
        controller.setChrome(shown: false)
        controller.setLandscape(true)
        await pause(1.5)
        controller.setLandscape(false)
        await pause(1.5)
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}
#endif
