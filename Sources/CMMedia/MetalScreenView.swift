// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
#if os(macOS)
import AppKit
import CMCore
import CoreImage
import CoreVideo
import ImageIO
import Metal
import MetalPerformanceShaders
import QuartzCore
import UniformTypeIdentifiers

/// Newest-frame slot shared by the decode thread (writer) and the main-thread renderer (reader).
/// Only one pending frame exists at a time: a newer frame simply replaces an older, undrawn one.
public final class FrameSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: CVPixelBuffer?
    private var shown: CVPixelBuffer?

    public init() {}

    public func put(_ buffer: CVPixelBuffer) {
        lock.withLock { pending = buffer }
    }

    /// Takes the pending frame (if any) and remembers it as the one on screen.
    func take() -> CVPixelBuffer? {
        lock.withLock {
            guard let frame = pending else { return nil }
            pending = nil
            shown = frame
            return frame
        }
    }

    /// The newest frame, drawn or not (screenshots, redraws).
    public var current: CVPixelBuffer? {
        lock.withLock { pending ?? shown }
    }

    /// Drops every frame reference (session end: no frame caches, spec 7.6).
    public func clear() {
        lock.withLock {
            pending = nil
            shown = nil
        }
    }
}

/// Keeps Core Video textures alive until the GPU has finished reading them.
private final class GPURetain: @unchecked Sendable {
    let objects: [AnyObject]
    init(_ objects: [AnyObject]) { self.objects = objects }
}

/// Draws decoded frames with Metal (spec 4.4): IOSurface-backed pixel buffers become textures through
/// `CVMetalTextureCache` (no CPU copies), a shader converts video-range YCbCr (BT.709 / BT.2020 / BT.601,
/// from the frame's own tag) to RGB, and the view's display link (ProMotion-paced) presents only the newest
/// frame. Content is aspect-fitted (letterboxed) so a landscape frame inside a portrait window is never
/// stretched. Privacy blur draws a heavy Gaussian blur of a downscaled frame with a dark tint (spec 8.2.4).
@MainActor
public final class MetalScreenView: NSView {
    private let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private var convertPipeline: MTLRenderPipelineState?
    private var blitPipeline: MTLRenderPipelineState?
    private var textureCache: CVMetalTextureCache?
    private let metalLayer = CAMetalLayer()
    private var link: CADisplayLink?

    /// Written by the decoder from any thread.
    public nonisolated let frames = FrameSlot()

    /// Stop drawing while the window is fully hidden (spec 8.2.1).
    public var renderingPaused = false
    /// Privacy blur: real content is no longer presented.
    public var blurred = false {
        didSet { if blurred != oldValue { redraw() } }
    }
    /// Reconnecting: the last frame stays visible, dimmed (spec 8.2.2).
    public var dimmed = false {
        didSet { if dimmed != oldValue { redraw() } }
    }
    /// Called once per presented frame (fps counter for the HUD).
    public var onPresent: (() -> Void)?

    /// Brightness kept under the blur (dark tint so the lock glyph reads clearly).
    static let blurTint: Float = 0.45
    /// Brightness of the last frame while reconnecting.
    static let dimGain: Float = 0.5
    static let blurDownscale = 8
    static let blurSigma: Float = 4

    public override init(frame: NSRect) {
        device = MTLCreateSystemDefaultDevice()
        queue = device?.makeCommandQueue()
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        if let device {
            CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
            convertPipeline = Self.makePipeline(device, fragment: "fconvert")
            blitPipeline = Self.makePipeline(device, fragment: "fblit")
        }
        if convertPipeline == nil { Log.error(.media, "metal pipeline unavailable") }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    public override func makeBackingLayer() -> CALayer {
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.isOpaque = true
        metalLayer.backgroundColor = NSColor.black.cgColor
        metalLayer.displaySyncEnabled = true
        metalLayer.maximumDrawableCount = 3
        return metalLayer
    }

    public override var isOpaque: Bool { true }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil else { return }
        let l = displayLink(target: self, selector: #selector(step(_:)))
        // Both ends are adaptive (phone 1–120 Hz, ProMotion): run up to 120 Hz so each frame shows when it arrives.
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 1, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    public override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
        if blurred || dimmed || renderingPaused { redraw() }
    }

    /// Hands over a decoded frame (any thread). Only the newest is kept.
    public nonisolated func enqueue(_ buffer: CVPixelBuffer) {
        frames.put(buffer)
    }

    @objc private func step(_ link: CADisplayLink) {
        guard !renderingPaused, !blurred, !dimmed, let frame = frames.take() else { return }
        draw(frame, blur: false, gain: 1)
        onPresent?()
    }

    /// Re-presents the newest frame in the current mode (blur/dim change, resize while not live).
    private func redraw() {
        guard let frame = frames.current else {
            clearToBlack()
            return
        }
        draw(frame, blur: blurred, gain: dimmed ? Self.dimGain : 1)
    }

    /// Black screen, dropping every frame reference (session ended).
    public func reset() {
        frames.clear()
        clearToBlack()
    }

    // MARK: Rendering

    private struct Planes {
        let y: MTLTexture
        let uv: MTLTexture
        let retain: GPURetain
    }

    private func planes(_ buffer: CVPixelBuffer) -> Planes? {
        guard let cache = textureCache, CVPixelBufferGetPlaneCount(buffer) == 2 else { return nil }
        var refs: [AnyObject] = [buffer]
        func plane(_ index: Int, _ format: MTLPixelFormat) -> MTLTexture? {
            var texture: CVMetalTexture?
            let w = CVPixelBufferGetWidthOfPlane(buffer, index), h = CVPixelBufferGetHeightOfPlane(buffer, index)
            guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil, format, w, h, index, &texture) == kCVReturnSuccess,
                  let texture, let metal = CVMetalTextureGetTexture(texture) else { return nil }
            refs.append(texture)
            return metal
        }
        guard let y = plane(0, .r8Unorm), let uv = plane(1, .rg8Unorm) else { return nil }
        return Planes(y: y, uv: uv, retain: GPURetain(refs))
    }

    /// 0 = BT.709, 1 = BT.2020, 2 = BT.601, from the decoder's colour tag (BT.709 when untagged).
    private func matrixIndex(_ buffer: CVPixelBuffer) -> UInt32 {
        guard let tag = CVBufferCopyAttachment(buffer, kCVImageBufferYCbCrMatrixKey, nil) as? String else { return 0 }
        if tag == (kCVImageBufferYCbCrMatrix_ITU_R_2020 as String) { return 1 }
        if tag == (kCVImageBufferYCbCrMatrix_ITU_R_601_4 as String) { return 2 }
        return 0
    }

    /// Aspect-fit rectangle of a `frameW × frameH` image inside a `targetW × targetH` texture.
    static func fitViewport(frameW: Int, frameH: Int, targetW: Int, targetH: Int) -> MTLViewport {
        guard frameW > 0, frameH > 0, targetW > 0, targetH > 0 else {
            return MTLViewport(originX: 0, originY: 0, width: Double(targetW), height: Double(targetH), znear: 0, zfar: 1)
        }
        let scale = min(Double(targetW) / Double(frameW), Double(targetH) / Double(frameH))
        let w = (Double(frameW) * scale).rounded(), h = (Double(frameH) * scale).rounded()
        return MTLViewport(originX: ((Double(targetW) - w) / 2).rounded(), originY: ((Double(targetH) - h) / 2).rounded(),
                           width: w, height: h, znear: 0, zfar: 1)
    }

    private func draw(_ buffer: CVPixelBuffer, blur: Bool, gain: Float) {
        guard let device, let queue, let planes = planes(buffer), let drawable = metalLayer.nextDrawable(),
              let commands = queue.makeCommandBuffer() else { return }
        let matrix = matrixIndex(buffer)
        let frameW = CVPixelBufferGetWidth(buffer), frameH = CVPixelBufferGetHeight(buffer)
        let target = drawable.texture
        if blur {
            let w = max(1, target.width / Self.blurDownscale), h = max(1, target.height / Self.blurDownscale)
            guard let small = Self.texture(device, w, h), let soft = Self.texture(device, w, h) else { return }
            encodeConvert(commands, planes, matrix, gain: 1, into: small,
                          viewport: Self.fitViewport(frameW: frameW, frameH: frameH, targetW: w, targetH: h))
            MPSImageGaussianBlur(device: device, sigma: Self.blurSigma)
                .encode(commandBuffer: commands, sourceTexture: small, destinationTexture: soft)
            encodeBlit(commands, soft, gain: Self.blurTint, into: target)
        } else {
            encodeConvert(commands, planes, matrix, gain: gain, into: target,
                          viewport: Self.fitViewport(frameW: frameW, frameH: frameH, targetW: target.width, targetH: target.height))
        }
        let retain = planes.retain
        commands.addCompletedHandler { _ in withExtendedLifetime(retain) {} }
        commands.present(drawable)
        commands.commit()
    }

    private func clearToBlack() {
        guard let queue, let drawable = metalLayer.nextDrawable(), let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: Self.pass(drawable.texture)) else { return }
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }

    private static func texture(_ device: MTLDevice, _ w: Int, _ h: Int) -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead, .shaderWrite]
        d.storageMode = .private
        return device.makeTexture(descriptor: d)
    }

    private static func pass(_ target: MTLTexture) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        return pass
    }

    /// Shader parameters (layout matches `Params` in the shader).
    private struct Params {
        var matrix: UInt32
        var gain: Float
    }

    private func encodeConvert(_ commands: MTLCommandBuffer, _ planes: Planes, _ matrix: UInt32, gain: Float, into target: MTLTexture,
                               viewport: MTLViewport) {
        guard let convertPipeline, let encoder = commands.makeRenderCommandEncoder(descriptor: Self.pass(target)) else { return }
        var params = Params(matrix: matrix, gain: gain)
        encoder.setRenderPipelineState(convertPipeline)
        encoder.setViewport(viewport)
        encoder.setFragmentTexture(planes.y, index: 0)
        encoder.setFragmentTexture(planes.uv, index: 1)
        encoder.setFragmentBytes(&params, length: MemoryLayout<Params>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func encodeBlit(_ commands: MTLCommandBuffer, _ source: MTLTexture, gain: Float, into target: MTLTexture) {
        guard let blitPipeline, let encoder = commands.makeRenderCommandEncoder(descriptor: Self.pass(target)) else { return }
        var params = Params(matrix: 0, gain: gain)
        encoder.setRenderPipelineState(blitPipeline)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentBytes(&params, length: MemoryLayout<Params>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// Full-screen triangle; video-range YCbCr → RGB with the frame's own matrix.
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct V { float4 position [[position]]; float2 uv; };
    struct Params { uint matrix; float gain; };
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    vertex V vmain(uint id [[vertex_id]]) {
        float2 p = float2((id << 1) & 2, id & 2);
        V v; v.position = float4(p * 2.0 - 1.0, 0, 1); v.uv = float2(p.x, 1.0 - p.y); return v;
    }
    fragment float4 fconvert(V in [[stage_in]], texture2d<float> y [[texture(0)]], texture2d<float> uv [[texture(1)]],
                             constant Params &k [[buffer(0)]]) {
        float l = (y.sample(s, in.uv).r - 16.0 / 255.0) * (255.0 / 219.0);
        float2 c = (uv.sample(s, in.uv).rg - 128.0 / 255.0) * (255.0 / 224.0);
        float3 rgb;
        if (k.matrix == 1) {
            rgb = float3(l + 1.4746 * c.y, l - 0.16455 * c.x - 0.57135 * c.y, l + 1.8814 * c.x);
        } else if (k.matrix == 2) {
            rgb = float3(l + 1.402 * c.y, l - 0.344136 * c.x - 0.714136 * c.y, l + 1.772 * c.x);
        } else {
            rgb = float3(l + 1.5748 * c.y, l - 0.18732 * c.x - 0.46812 * c.y, l + 1.8556 * c.x);
        }
        return float4(saturate(rgb) * k.gain, 1.0);
    }
    fragment float4 fblit(V in [[stage_in]], texture2d<float> t [[texture(0)]], constant Params &k [[buffer(0)]]) {
        return float4(t.sample(s, in.uv).rgb * k.gain, 1.0);
    }
    """

    private static func makePipeline(_ device: MTLDevice, fragment: String) -> MTLRenderPipelineState? {
        guard let library = try? device.makeLibrary(source: shaderSource, options: nil) else { return nil }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: "vmain")
        d.fragmentFunction = library.makeFunction(name: fragment)
        d.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try? device.makeRenderPipelineState(descriptor: d)
    }

    // MARK: Screenshot (spec A7 / 5.4)

    /// Saves the newest frame at full native resolution as PNG into `~/Pictures/CarbonMirror/`.
    /// Built from the decoded frame on the Mac; nothing is read from phone storage.
    public func saveScreenshot(date: Date = Date()) -> URL? {
        guard let frame = frames.current, let folder = ScreenshotLocation.folder() else { return nil }
        let image = CIImage(cvPixelBuffer: frame)
        guard let cg = CIContext(options: [.useSoftwareRenderer: false]).createCGImage(image, from: image.extent) else { return nil }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            Log.error(.media, "screenshot folder unavailable")
            return nil
        }
        let url = folder.appendingPathComponent(ScreenshotLocation.fileName(for: date))
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cg, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        Log.info(.media, "screenshot saved")
        return url
    }
}
#endif
