#if os(macOS)
import CMCore
import CMCoreBridge
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

/// Hardware H.264/H.265 decoding (spec 4.3): `VTDecompressionSession` with real-time settings, output in
/// IOSurface-backed, Metal-compatible pixel buffers (zero CPU copies into the renderer). Frames are decoded
/// synchronously into a reused buffer, so no per-frame copy of the bitstream is kept.
public final class VideoDecoder: VideoSink, @unchecked Sendable {
    /// Newest decoded frame, delivered on the decode thread.
    public var onFrame: (@Sendable (CVPixelBuffer) -> Void)?
    /// Last decode duration in milliseconds (debug HUD).
    public private(set) var lastDecodeMs: Double = 0

    private let lock = NSLock()
    private var codec: VideoCodecID = .h264
    private var format: CMVideoFormatDescription?
    private var session: VTDecompressionSession?
    private var scratch = [UInt8](repeating: 0, count: 1 << 20)
    /// While true (window hidden for > 5 s) packets are dropped; resuming waits for a key frame.
    private var suspended = false
    private var awaitingKeyFrame = true

    public init() {}

    deinit {
        if let session { VTDecompressionSessionInvalidate(session) }
    }

    /// Stops decoding to save power (spec 8.2.1); `resume` waits for the next key frame.
    public func suspend() {
        lock.withLock { suspended = true }
    }

    public func resume() {
        lock.withLock {
            suspended = false
            awaitingKeyFrame = true
        }
    }

    public func videoStarted(codec: VideoCodecID) {
        lock.withLock {
            self.codec = codec
            invalidate()
            awaitingKeyFrame = true
        }
    }

    public func videoSession(width: Int, height: Int) {
        lock.withLock { awaitingKeyFrame = true }
    }

    public func videoPacket(_ data: UnsafeRawBufferPointer, config: Bool, keyFrame: Bool, pts: UInt64) {
        lock.withLock {
            guard let length = convert(data) else { return }
            if config {
                configure(length: length)
                return
            }
            guard !suspended, session != nil else { return }
            if awaitingKeyFrame {
                guard keyFrame else { return }
                awaitingKeyFrame = false
            }
            decode(length: length, pts: pts)
        }
    }

    /// Annex B → length-prefixed into `scratch` (Rust core); grows the buffer when needed.
    private func convert(_ data: UnsafeRawBufferPointer) -> Int? {
        let needed = data.count + data.count / 2 + 64
        if scratch.count < needed { scratch = [UInt8](repeating: 0, count: needed) }
        return scratch.withUnsafeMutableBytes { try? ScrcpyProtocol.lengthPrefixed(data, into: $0) }
    }

    /// Extracts parameter sets from the converted config packet and (re)creates the session.
    private func configure(length: Int) {
        var sets: [[UInt8]] = []
        var i = 0
        while i + 4 <= length {
            let n = Int(scratch[i]) << 24 | Int(scratch[i + 1]) << 16 | Int(scratch[i + 2]) << 8 | Int(scratch[i + 3])
            guard n > 0, i + 4 + n <= length else { return }
            let nal = Array(scratch[(i + 4)..<(i + 4 + n)])
            let type = codec == .h264 ? nal[0] & 0x1F : (nal[0] >> 1) & 0x3F
            let wanted: Set<UInt8> = codec == .h264 ? [7, 8] : [32, 33, 34]
            if wanted.contains(type) { sets.append(nal) }
            i += 4 + n
        }
        guard !sets.isEmpty, let description = makeFormat(sets) else { return }
        if let format, CMFormatDescriptionEqual(format, otherFormatDescription: description), session != nil { return }
        invalidate()
        format = description
        makeSession(description)
    }

    private func makeFormat(_ sets: [[UInt8]]) -> CMVideoFormatDescription? {
        var description: CMVideoFormatDescription?
        let pointers = sets.map { set -> UnsafeMutablePointer<UInt8> in
            let p = UnsafeMutablePointer<UInt8>.allocate(capacity: set.count)
            p.initialize(from: set, count: set.count)
            return p
        }
        defer { pointers.forEach { $0.deallocate() } }
        let sizes = sets.map(\.count)
        let status: OSStatus = pointers.map { UnsafePointer($0) }.withUnsafeBufferPointer { ptrs in
            sizes.withUnsafeBufferPointer { lens in
                if codec == .h264 {
                    return CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: nil, parameterSetCount: sets.count,
                                                                               parameterSetPointers: ptrs.baseAddress!, parameterSetSizes: lens.baseAddress!,
                                                                               nalUnitHeaderLength: 4, formatDescriptionOut: &description)
                }
                return CMVideoFormatDescriptionCreateFromHEVCParameterSets(allocator: nil, parameterSetCount: sets.count,
                                                                           parameterSetPointers: ptrs.baseAddress!, parameterSetSizes: lens.baseAddress!,
                                                                           nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &description)
            }
        }
        if status != noErr { Log.error(.media, "parameter sets rejected", ["status": "\(status)"]) }
        return status == noErr ? description : nil
    }

    private func makeSession(_ description: CMVideoFormatDescription) {
        let decoderSpec: [CFString: Any] = [kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder: true]
        let imageAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [CFString: Any],
        ]
        var created: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(allocator: nil, formatDescription: description, decoderSpecification: decoderSpec as CFDictionary,
                                                  imageBufferAttributes: imageAttributes as CFDictionary, outputCallback: nil,
                                                  decompressionSessionOut: &created)
        guard status == noErr, let created else {
            Log.error(.media, "decoder session failed", ["status": "\(status)"])
            return
        }
        VTSessionSetProperty(created, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        session = created
        awaitingKeyFrame = true
    }

    private func decode(length: Int, pts: UInt64) {
        guard let session, let format else { return }
        let start = DispatchTime.now().uptimeNanoseconds
        scratch.withUnsafeMutableBytes { raw in
            var block: CMBlockBuffer?
            guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: raw.baseAddress, blockLength: length,
                                                     blockAllocator: kCFAllocatorNull, customBlockSource: nil, offsetToData: 0,
                                                     dataLength: length, flags: 0, blockBufferOut: &block) == kCMBlockBufferNoErr, let block else { return }
            var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(value: CMTimeValue(pts), timescale: 1_000_000),
                                            decodeTimeStamp: .invalid)
            var sizes = [length]
            var sample: CMSampleBuffer?
            guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: 1,
                                            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1,
                                            sampleSizeArray: &sizes, sampleBufferOut: &sample) == noErr, let sample else { return }
            let handler = onFrame
            let status = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample, flags: [._1xRealTimePlayback], infoFlagsOut: nil) { status, _, image, _, _ in
                if status == noErr, let image { handler?(image) }
            }
            if status != noErr {
                Log.error(.media, "decode failed", ["status": "\(status)"])
                awaitingKeyFrame = true
            }
        }
        lastDecodeMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
    }

    private func invalidate() {
        if let session { VTDecompressionSessionInvalidate(session) }
        session = nil
        format = nil
    }
}
#endif
