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

/// Draws decoded frames with Metal (spec 4.4): IOSurface-backed pixel buffers become textures through
/// `CVMetalTextureCache` (no CPU copies), a shader converts BT.709/BT.2020 video-range YCbCr to RGB, and the
/// display link (ProMotion-paced) always presents the newest frame — older ones are simply replaced.
/// Privacy blur renders a heavy Gaussian blur of a downscaled frame with a dark tint (spec 8.2.4).
public final class MetalScreenView: NSView, CALayerDelegate {
    private let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var blitPipeline: MTLRenderPipelineState?
    private var textureCache: CVMetalTextureCache?
    private let metalLayer = CAMetalLayer()
    private let latest = NSLock()
    private var pending: CVPixelBuffer?
    private var shown: CVPixelBuffer?
    private var link: CADisplayLink?

    /// Stop drawing while the window is fully hidden (spec 8.2.1).
    public var renderingPaused = false
    /// Privacy blur: real content is no longer presented.
    public var blurred = false {
        didSet { if blurred != oldValue { drawBlurredOrClear() } }
    }
    /// Called once per presented frame (fps counter for the HUD).
    public var onPresent: (() -> Void)?

    public override init(frame: NSRect) {
        device = MTLCreateSystemDefaultDevice()
        queue = device?.makeCommandQueue()
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        if let device {
            CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
            pipeline = Self.makePipeline(device, fragment: "fmain")
            blitPipeline = Self.makePipeline(device, fragment: "fblit")
        }
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

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate()
        guard window != nil else { return }
        let l = displayLink(target: self, selector: #selector(step(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    public override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? 2
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }

    /// Hands over a decoded frame (any thread). Only the newest is kept.
    public func enqueue(_ buffer: CVPixelBuffer) {
        latest.withLock { pending = buffer }
    }

    /// The frame on screen, for screenshots.
    public var currentFrame: CVPixelBuffer? {
        latest.withLock { pending ?? shown }
    }

    @objc private func step(_ link: CADisplayLink) {
        guard !renderingPaused, !blurred else { return }
        guard let frame = latest.withLock({ () -> CVPixelBuffer? in
            defer { pending = nil }
            return pending
        }) else { return }
        shown = frame
        draw(frame, blur: false)
        onPresent?()
    }

    private func drawBlurredOrClear() {
        if blurred, let frame = currentFrame { draw(frame, blur: true) } else if let frame = currentFrame { draw(frame, blur: false) }
    }

    // MARK: Rendering

    private func textures(_ buffer: CVPixelBuffer) -> (MTLTexture, MTLTexture)? {
        guard let cache = textureCache, CVPixelBufferGetPlaneCount(buffer) == 2 else { return nil }
        func plane(_ index: Int, _ format: MTLPixelFormat) -> MTLTexture? {
            var texture: CVMetalTexture?
            let w = CVPixelBufferGetWidthOfPlane(buffer, index), h = CVPixelBufferGetHeightOfPlane(buffer, index)
            guard CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil, format, w, h, index, &texture) == kCVReturnSuccess,
                  let texture else { return nil }
            return CVMetalTextureGetTexture(texture)
        }
        guard let y = plane(0, .r8Unorm), let uv = plane(1, .rg8Unorm) else { return nil }
        return (y, uv)
    }

    /// BT.2020 when the decoder tags the frame so, BT.709 otherwise.
    private func matrixIndex(_ buffer: CVPixelBuffer) -> UInt32 {
        let tag = CVBufferCopyAttachment(buffer, kCVImageBufferYCbCrMatrixKey, nil) as? String
        return tag == (kCVImageBufferYCbCrMatrix_ITU_R_2020 as String) ? 1 : 0
    }

    /// Fraction of brightness kept under the blur (dark tint so the lock glyph reads clearly).
    static let blurTint: Float = 0.45
    static let blurDownscale = 8
    static let blurSigma: Float = 4

    private func draw(_ buffer: CVPixelBuffer, blur: Bool) {
        guard let device, let queue, let (y, uv) = textures(buffer), let drawable = metalLayer.nextDrawable(),
              let commands = queue.makeCommandBuffer() else { return }
        let matrix = matrixIndex(buffer)
        if blur {
            let w = max(1, drawable.texture.width / Self.blurDownscale), h = max(1, drawable.texture.height / Self.blurDownscale)
            guard let small = Self.texture(device, w, h), let soft = Self.texture(device, w, h) else { return }
            encodeConvert(commands, y, uv, matrix, into: small)
            MPSImageGaussianBlur(device: device, sigma: Self.blurSigma).encode(commandBuffer: commands, sourceTexture: small, destinationTexture: soft)
            encodeBlit(commands, soft, tint: Self.blurTint, into: drawable.texture)
        } else {
            encodeConvert(commands, y, uv, matrix, into: drawable.texture)
        }
        commands.present(drawable)
        commands.commit()
    }

    private static func texture(_ device: MTLDevice, _ w: Int, _ h: Int) -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead, .shaderWrite]
        return device.makeTexture(descriptor: d)
    }

    private func pass(_ target: MTLTexture) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        return pass
    }

    private func encodeConvert(_ commands: MTLCommandBuffer, _ y: MTLTexture, _ uv: MTLTexture, _ matrix: UInt32, into target: MTLTexture) {
        guard let pipeline, let encoder = commands.makeRenderCommandEncoder(descriptor: pass(target)) else { return }
        var m = matrix
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(y, index: 0)
        encoder.setFragmentTexture(uv, index: 1)
        encoder.setFragmentBytes(&m, length: MemoryLayout<UInt32>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func encodeBlit(_ commands: MTLCommandBuffer, _ source: MTLTexture, tint: Float, into target: MTLTexture) {
        guard let blitPipeline, let encoder = commands.makeRenderCommandEncoder(descriptor: pass(target)) else { return }
        var t = tint
        encoder.setRenderPipelineState(blitPipeline)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentBytes(&t, length: MemoryLayout<Float>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct V { float4 position [[position]]; float2 uv; };
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    vertex V vmain(uint id [[vertex_id]]) {
        float2 p = float2((id << 1) & 2, id & 2);
        V v; v.position = float4(p * 2.0 - 1.0, 0, 1); v.uv = float2(p.x, 1.0 - p.y); return v;
    }
    fragment float4 fmain(V in [[stage_in]], texture2d<float> y [[texture(0)]], texture2d<float> uv [[texture(1)]],
                          constant uint &matrix [[buffer(0)]]) {
        float luma = (y.sample(s, in.uv).r - 16.0 / 255.0) * (255.0 / 219.0);
        float2 c = (uv.sample(s, in.uv).rg - 128.0 / 255.0) * (255.0 / 224.0);
        float3 rgb = matrix == 1
            ? float3(luma + 1.4746 * c.y, luma - 0.16455 * c.x - 0.57135 * c.y, luma + 1.8814 * c.x)
            : float3(luma + 1.5748 * c.y, luma - 0.18732 * c.x - 0.46812 * c.y, luma + 1.8556 * c.x);
        return float4(saturate(rgb), 1.0);
    }
    fragment float4 fblit(V in [[stage_in]], texture2d<float> t [[texture(0)]], constant float &tint [[buffer(0)]]) {
        return float4(t.sample(s, in.uv).rgb * tint, 1.0);
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

    /// Saves the current frame at full native resolution as PNG into `~/Pictures/CarbonMirror/`.
    public func saveScreenshot(date: Date = Date()) -> URL? {
        guard let frame = currentFrame, let folder = ScreenshotLocation.folder() else { return nil }
        let image = CIImage(cvPixelBuffer: frame)
        guard let cg = CIContext(options: [.useSoftwareRenderer: false]).createCGImage(image, from: image.extent) else { return nil }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let url = folder.appendingPathComponent(ScreenshotLocation.fileName(for: date))
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cg, nil)
        return CGImageDestinationFinalize(destination) ? url : nil
    }
}
#endif
