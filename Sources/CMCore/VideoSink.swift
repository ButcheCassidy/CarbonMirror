// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
import CMCoreBridge

/// Receives the parsed video stream. Buffers are only valid during the call (zero-copy from the session's
/// read buffer); a decoder must copy or decode synchronously.
public protocol VideoSink: AnyObject, Sendable {
    func videoStarted(codec: VideoCodecID)
    /// Frame size changed (rotation, first frame).
    func videoSession(width: Int, height: Int)
    /// Codec configuration (`config`) or one encoded frame.
    func videoPacket(_ data: UnsafeRawBufferPointer, config: Bool, keyFrame: Bool, pts: UInt64)
}
