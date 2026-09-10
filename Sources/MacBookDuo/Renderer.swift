import AppKit
import MetalKit

final class FoldRenderer: NSObject, MTKViewDelegate {
    let view: MTKView
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var texture: MTLTexture?
    private var filteredTexture: MTLTexture?
    private var textureDirty = true
    private var cache: CVMetalTextureCache?
    private var retainedFrame: CVMetalTexture?
    var fold: Float = 0
    var strength: Float = 1
    var blur: Float = 0.65
    var shade: Float = 0.4

    init(size: NSSize) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw NSError(domain: "Metal unavailable", code: 1)
        }
        self.queue = queue
        view = MTKView(frame: NSRect(origin: .zero, size: size), device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        struct V { float4 position [[position]]; float2 uv; };
        vertex V vertexMain(uint i [[vertex_id]]) {
            float2 p[4] = {float2(-1,-1),float2(1,-1),float2(-1,1),float2(1,1)};
            V o; o.position=float4(p[i],0,1); o.uv=float2((p[i].x+1)*.5,(1-p[i].y)*.5); return o;
        }
        fragment float4 fragmentMain(V in [[stage_in]], texture2d<float> tex [[texture(0)]], constant float4 &u [[buffer(0)]]) {
            constexpr sampler s(filter::linear, mip_filter::linear, address::clamp_to_edge);
            float p=clamp(u.x*u.y,0.0f,1.0f);
            // Two separate layers: the glass/screen is moving, while the UI
            // remains a rigid, flat plane behind it. We project rays through
            // the moving screen onto that plane, which creates real parallax.
            constexpr float PI=3.14159265;
            float theta=p*1.42;
            float v=1.0-in.uv.y;             // distance from the hinge
            float aspect=float(tex.get_width())/float(tex.get_height());
            float eye=2.15;
            float depth=v*sin(theta);
            float perspective=eye/(eye-depth);
            float2 projected=float2((in.uv.x-.5)*perspective+.5,
                .5+(v*cos(theta)-.5)*perspective);
            float2 uv=float2(projected.x,1.0-projected.y);
            float2 pixel=1.0/float2(tex.get_width(),tex.get_height());
            float vertical=clamp(v,0.0f,1.0f);
            float feather=smoothstep(0.05,0.95,vertical);
            // The projected boundary is feathered more as it rises away from
            // the Dock, so the lower edge stays anchored and the upper edge
            // dissolves into a soft optical halo.
            float2 boundary=max(pixel*3.0,pixel*(8.0+26.0*feather));
            float2 coverage=smoothstep(-boundary,boundary,uv)*
                (1.0-smoothstep(1.0-boundary,1.0+boundary,uv));
            float inside=coverage.x*coverage.y;

            // Smooth mipmapped blur; its radius follows the physical gap.
            float separation=pow(clamp(depth,0.0f,1.0f),1.22);
            float radius=u.z*separation*(0.35+0.65*feather)*float(tex.get_height())*0.020;
            float lod=max(0.0,log2(max(1.0,radius*0.9)));
            float2 sigma=max(pixel,float2(radius/float(tex.get_width()),radius/float(tex.get_height()))*0.72);
            float3 color=float3(0);
            float total=0;
            for(int j=-3;j<=3;j++) for(int i=-3;i<=3;i++) {
                float2 o=float2(i,j)*0.7;
                float w=exp(-0.5*dot(o,o));
                float2 q=uv+o*sigma;
                float2 c=smoothstep(-pixel,pixel,q)*(1.0-smoothstep(1.0-pixel,1.0+pixel,q));
                color+=tex.sample(s,q,level(lod)).rgb*c.x*c.y*w;
                total+=w;
            }
            color/=max(total,0.001);

            // At the start of opening, the inner plane is already lit. A
            // shallow second projection gives the translucent-window glimpse
            // before the screen has fully separated from the UI.
            float reveal=smoothstep(0.015,0.10,p)*(1.0-smoothstep(0.10,0.26,p));
            float2 innerUV=uv+float2(0.0, -0.010*reveal);
            float3 inner=tex.sample(s,innerUV,level(max(0.0,lod-1.2))).rgb;
            float innerLum=dot(inner,float3(.2126,.7152,.0722));
            float windowAlpha=0.055*reveal*smoothstep(.08,.82,innerLum);
            color=mix(color,inner,color.x*0.0 + windowAlpha);

            // Black domain outside the projected plane, plus a soft physical
            // edge so the plane reads as a panel in space instead of a crop.
            float edgeFade=min(min(coverage.x,coverage.y),min(coverage.x,coverage.y));
            color*=1.0-u.w*0.52*separation;
            float normalLight=0.08*(1.0-cos(theta))*smoothstep(0.0,0.8,v);
            color+=normalLight;

            // Color scattering at the projected boundary; sample the same
            // continuous mip level so there are no repeated ghost outlines.
            float edgeDist=min(min(uv.x,1.0-uv.x),min(uv.y,1.0-uv.y));
            // radius is in source pixels; convert it to UV space before
            // evaluating the outside falloff, otherwise the glow gets clipped.
            float glowRadius=max(radius*2.8/float(tex.get_height()),0.0012);
            float outsideDistance=max(0.0,-edgeDist);
            float edgeBand=(1.0-smoothstep(0.0,glowRadius*3.8,outsideDistance))
                *smoothstep(0.06,0.92,vertical);
            float3 glow=tex.sample(s,clamp(uv,float2(0),float2(1)),level(max(0.0,lod+1.0))).rgb;
            float glowAmount=u.z*separation*0.34*edgeBand*smoothstep(.12,.78,dot(glow,float3(.2126,.7152,.0722)));
            color=1.0-(1.0-color)*(1.0-glow*glowAmount);
            // The panel itself remains clipped to the projected plane, but
            // the scattered light is allowed to live in the surrounding black
            // domain and fade smoothly with distance from the edge.
            float3 outsideGlow=glow*glowAmount*edgeBand;
            color=color*inside + outsideGlow*(1.0-inside);

            // Preserve the black domain while anti-aliasing its boundary.
            // Keep the Dock side crisp; let the top dissolve gradually.
            return float4(color,1);

        }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "vertexMain")
        desc.fragmentFunction = library.makeFunction(name: "fragmentMain")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: desc)
        super.init()
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        view.delegate = self
    }
    func setImage(_ image: CGImage) throws {
        guard let device = view.device else { return }
        let width = image.width, height = image.height
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: descriptor) else { throw NSError(domain: "Texture allocation failed", code: 2) }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw NSError(domain: "Image conversion failed", code: 3) }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            tex.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes.baseAddress!, bytesPerRow: width * 4)
        }
        texture = tex
        textureDirty = true
        render()
    }
    func setFrame(_ buffer: CVPixelBuffer) {
        guard let cache else { return }
        var frame: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil, .bgra8Unorm,
            CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &frame)
        guard result == kCVReturnSuccess, let frame, let tex = CVMetalTextureGetTexture(frame) else { return }
        retainedFrame = frame
        texture = tex
        textureDirty = true
        render()
    }
    func render() { view.draw() }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let texture, let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor, let command = queue.makeCommandBuffer(),
              let device = view.device else { return }
        if filteredTexture?.width != texture.width || filteredTexture?.height != texture.height || filteredTexture?.pixelFormat != texture.pixelFormat {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture.pixelFormat, width: texture.width, height: texture.height, mipmapped: true)
            descriptor.usage = [.shaderRead]
            descriptor.storageMode = .private
            filteredTexture = device.makeTexture(descriptor: descriptor)
            textureDirty = true
        }
        guard let filteredTexture else { return }
        if textureDirty {
            guard let blit = command.makeBlitCommandEncoder() else { return }
            blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: filteredTexture, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.generateMipmaps(for: filteredTexture)
            blit.endEncoding()
            textureDirty = false
        }
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        var uniforms = SIMD4<Float>(fold, strength, blur, shade)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(filteredTexture, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
    }
}
