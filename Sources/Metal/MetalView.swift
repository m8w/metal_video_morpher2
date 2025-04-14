// Add @preconcurrency to handle Metal framework Sendable warnings
@preconcurrency import AppKit
@preconcurrency import MetalKit
@preconcurrency import Metal
import Domain
import AVFoundation

// Struct to match the shader MorphingUniforms
public struct MorphingUniforms {
    var morphAmount: Float = 0.0
    var morphType: Float = 0.0
    var time: Float = 0.0
    var touchPosition: SIMD2<Float> = SIMD2<Float>(0, 0)
    var extraParams: SIMD4<Float> = SIMD4<Float>(6, 0, 0, 0) // Default with 6 segments for kaleidoscope
}

/// Custom Metal view that handles rendering
@MainActor
public class MetalView: MTKView, MTKViewDelegate, VideoFrameDelegate, MorphingControlProtocol {
    // MARK: - Properties
    
    // Keep track of view size for proper rendering
    private var viewportSize: CGSize = .zero
    
    // Reuse the command queue for better performance
    private var commandQueue: MTLCommandQueue?
    
    // Render pipeline state for triangle rendering
    private var trianglePipelineState: MTLRenderPipelineState?
    
    // Render pipeline state for video processing
    private var videoPipelineState: MTLRenderPipelineState?
    
    // Video texture from camera
    private var currentVideoTexture: MTLTexture?
    private var videoTimestamp: CMTime = .zero
    
    // Uniform buffer for morphing effects
    private var morphingUniforms = MorphingUniforms()
    private var uniformBuffer: MTLBuffer?
    
    // Sampler state for texture sampling
    private var samplerState: MTLSamplerState?
    
    // Video quad vertices and buffer
    private var videoQuadVertices: [Float]?
    private var videoQuadBuffer: MTLBuffer?
    
    // Animation timing
    private var startTime = Date()
    
    // Queue for Metal completion handlers
    private static let metalCallbackQueue = DispatchQueue(label: "com.metalvideoprocessor.callback", qos: .utility)
    
    // Queue for texture updates
    private let textureQueue = DispatchQueue(label: "com.metalvideoprocessor.texture", qos: .userInteractive)
    // MARK: - Initialization
    
    // Standard initialization (required by MTKView)
    public override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        self.commonInit()
    }
    
    // Required initializer for loading from a nib or storyboard
    required init(coder: NSCoder) {
        super.init(coder: coder)
        // Get the default Metal device
        self.device = MTLCreateSystemDefaultDevice()
        self.commonInit()
    }
    
    private func commonInit() {
        // Set up view properties
        self.framebufferOnly = true
        self.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        self.colorPixelFormat = .bgra8Unorm
        self.depthStencilPixelFormat = .depth32Float
        
        // Create and store the command queue for reuse
        self.commandQueue = device?.makeCommandQueue()
        // Set up the rendering pipeline
        setupPipeline()
        
        // Initialize video rendering resources
        setupVideoRendering()
        // Set up delegate
        self.delegate = self
        
        // Enable auto-resizing
        self.autoresizingMask = [.width, .height]
        
        // Enable high DPI if available
        self.wantsLayer = true
        if let metalLayer = self.layer as? CAMetalLayer {
            metalLayer.pixelFormat = .bgra8Unorm
            metalLayer.framebufferOnly = true
            metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 1.0
        }
    }
    // Setup for video rendering
    private func setupVideoRendering() {
        guard let device = self.device else { return }
        
        // Create a quad mesh for rendering the video
        videoQuadVertices = [
            // Positions                        // Texture Coordinates
            -1.0,  1.0, 0.0, 1.0,               0.0, 0.0, // Top left
             1.0,  1.0, 0.0, 1.0,               1.0, 0.0, // Top right
            -1.0, -1.0, 0.0, 1.0,               0.0, 1.0, // Bottom left
             1.0, -1.0, 0.0, 1.0,               1.0, 1.0  // Bottom right
        ]
        
        // Create vertex buffer
        if let vertices = videoQuadVertices {
            videoQuadBuffer = device.makeBuffer(bytes: vertices,
                                              length: vertices.count * MemoryLayout<Float>.size,
                                              options: [])
        }
        
        // Create uniform buffer for morphing parameters
        let uniformSize = MemoryLayout<MorphingUniforms>.size
        uniformBuffer = device.makeBuffer(length: uniformSize, options: [])
        updateUniformBuffer()
        
        // Create a sampler for texture sampling
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
        
        // Create the video processing pipeline
        setupVideoPipeline()
    }
    
    // Setup video processing pipeline
    private func setupVideoPipeline() {
        guard let device = self.device, let library = device.makeDefaultLibrary() else {
            return
        }
        
        // Try to load from the file system
        var shader = try? String(contentsOfFile: "Sources/Metal/Shaders/VideoShaders.metal", encoding: .utf8)
        if shader == nil {
            shader = try? String(contentsOfFile: FileManager.default.currentDirectoryPath + "/Sources/Metal/Shaders/VideoShaders.metal", encoding: .utf8)
        }
        
        var videoLibrary: MTLLibrary?
        
        // Try to compile the shader from source if available
        if let shader = shader {
            do {
                videoLibrary = try device.makeLibrary(source: shader, options: nil)
                print("Successfully compiled video shaders from source")
            } catch {
                print("Failed to compile video shaders: \(error)")
            }
        }
        
        // If we couldn't load the shader, try to use the default library
        if videoLibrary == nil {
            videoLibrary = library
            print("Using default library for video shaders")
        }
        
        // Create the video processing pipeline
        if let videoLibrary = videoLibrary,
           let vertexFunction = videoLibrary.makeFunction(name: "videoVertexShader"),
           let fragmentFunction = videoLibrary.makeFunction(name: "morphingFragmentShader") {
            
            // Create the pipeline descriptor
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.label = "Video Processing Pipeline"
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat
            
            // Define vertex descriptor for video quad
            let vertexDescriptor = MTLVertexDescriptor()
            
            // Position attribute
            vertexDescriptor.attributes[0].format = .float4
            vertexDescriptor.attributes[0].offset = 0
            vertexDescriptor.attributes[0].bufferIndex = 0
            
            // Texture coordinate attribute
            vertexDescriptor.attributes[1].format = .float2
            vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 4
            vertexDescriptor.attributes[1].bufferIndex = 0
            
            // Define the layout
            vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.size * 6 // position (4) + texCoord (2)
            vertexDescriptor.layouts[0].stepRate = 1
            vertexDescriptor.layouts[0].stepFunction = .perVertex
            
            pipelineDescriptor.vertexDescriptor = vertexDescriptor
            
            // Create the pipeline state
            do {
                videoPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
                print("Successfully created video processing pipeline")
            } catch {
                print("Failed to create video processing pipeline: \(error)")
            }
        }
    }
    
    // MARK: - Public Methods for Morphing Control
    
    // Set the morphing amount (0.0 - 1.0)
    public nonisolated func setMorphAmount(_ amount: Double) {
        // Copy the value before sending to MainActor to avoid data races
        let floatAmount = Float(amount)
        Task { @MainActor in
            morphingUniforms.morphAmount = floatAmount
            updateUniformBuffer()
        }
    }
    // Set the morphing effect type
    public nonisolated func setMorphEffect(_ effect: MorphEffect) {
        // Copy the raw value before sending to MainActor to avoid data races
        let rawValue = effect.rawValue
        Task { @MainActor in
            morphingUniforms.morphType = rawValue
            updateUniformBuffer()
        }
    }
    
    // Set the touch position for effects
    public nonisolated func setTouchPosition(_ position: CGPoint) {
        // Copy values to avoid data races
        let posX = position.x
        let posY = position.y
        
        Task { @MainActor in
            // Convert from view coordinates to normalized coordinates
            let normalizedX = Float(posX / bounds.width)
            let normalizedY = Float(posY / bounds.height)
            morphingUniforms.touchPosition = SIMD2<Float>(normalizedX, normalizedY)
            updateUniformBuffer()
        }
    }
    
    // Set extra parameters
    public nonisolated func setExtraParams(_ params: SIMD4<Float>) {
        Task { @MainActor in
            morphingUniforms.extraParams = params
            updateUniformBuffer()
        }
    }
    // Update the uniform buffer with current values
    // Update the uniform buffer with current values
    private func updateUniformBuffer() {
        // Update the time parameter
        let currentTime = Date()
        let elapsedTime = currentTime.timeIntervalSince(startTime)
        morphingUniforms.time = Float(elapsedTime)
        
        // Copy the uniforms to the buffer
        if let buffer = uniformBuffer {
            let contents = buffer.contents()
            memcpy(contents, &morphingUniforms, MemoryLayout<MorphingUniforms>.size)
        }
    }
    
    // Video texture handling with dispatch queue synchronization
    
    // This method is called when a new video frame is available
    public nonisolated func didReceiveVideoFrame(texture: MTLTexture, timestamp: CMTime) {
        // Capture necessary texture properties (like dimensions and pixel format)
        // to pass to the main thread safely without sending the texture directly
        let textureWidth = texture.width
        let textureHeight = texture.height
        
        // Create an autorelease pool to ensure proper management of resources
        autoreleasepool {
            // Use the texture queue to handle the texture update
            // This approach avoids Sendable issues by using GCD instead of Swift concurrency
            textureQueue.async { [weak self] in
                guard let self = self else { return }
                
                // Log texture info - helpful for debugging
                print("Received texture: \(textureWidth)x\(textureHeight)")
                
                // Now dispatch to the main thread for UI updates
                DispatchQueue.main.async {
                    // Update the texture on the main thread
                    // This is safe because we're on the main thread where MainActor code runs
                    self.updateTextureOnMainThread(texture, timestamp: timestamp)
                }
            }
        }
    }
    
    // Called on the main thread to update the video texture
    private func updateTextureOnMainThread(_ texture: MTLTexture, timestamp: CMTime) {
        // This runs on the main thread so it's safe to update MainActor-isolated properties
        currentVideoTexture = texture
        videoTimestamp = timestamp
        
        // Request a redraw
        setNeedsDisplay(bounds)
    }
    // MARK: - MTKViewDelegate
    
    // Called whenever the view needs to render a frame
    public func draw(in view: MTKView) {
        // Get the current drawable and render pass descriptor
        guard let renderPassDescriptor = createRenderPassDescriptor(),
              let currentDrawable = currentDrawable,
              let commandQueue = self.commandQueue ?? device?.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("Failed to create essential Metal objects for rendering")
            return
        }
        
        // Store the command queue if we just created it
        if self.commandQueue == nil {
            self.commandQueue = commandQueue
        }
        
        // Create the render encoder
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            print("Failed to create render encoder")
            return
        }
        
        // Update viewport size
        viewportSize = drawableSize
        
        // Set the viewport
        renderEncoder.setViewport(MTLViewport(
            originX: 0, originY: 0,
            width: Double(viewportSize.width),
            height: Double(viewportSize.height),
            znear: 0.0, zfar: 1.0))
        
        // Update the uniform buffer before rendering
        updateUniformBuffer()
        
        // If we have a video texture, render it with effects
        if let videoTexture = currentVideoTexture, let videoPipelineState = self.videoPipelineState {
            drawVideoWithEffects(renderEncoder: renderEncoder, texture: videoTexture, pipelineState: videoPipelineState)
        } 
        // Otherwise fall back to rendering a triangle
        else if let device = self.device, let pipelineState = self.trianglePipelineState {
            drawSimpleTriangle(renderEncoder: renderEncoder, device: device, pipelineState: pipelineState)
        }
        // Define a completion handler without capturing self or accessing MainActor properties
        // This avoids the actor isolation issue that's causing the crash
        let completionHandler = { [weak self] (buffer: MTLCommandBuffer) in
            // This handler runs on Metal's internal thread - don't access any MainActor state
            if let error = buffer.error {
                // Just log the error to the console
                print("Metal rendering error: \(error.localizedDescription)")
                
                // If critical error, dispatch to main queue to update UI
                if buffer.error?.localizedDescription.contains("critical") == true {
                    DispatchQueue.main.async {
                        if let _ = self {
                            print("Critical Metal error occurred - notifying main thread")
                        }
                    }
                }
            }
        }
        // Add the completion handler to the command buffer
        commandBuffer.addCompletedHandler(completionHandler)
        // End encoding and present
        renderEncoder.endEncoding()
        commandBuffer.present(currentDrawable)
        commandBuffer.commit()
    }
    
    // Called whenever the view size changes
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = size
        
        // Update any size-dependent resources here
        print("Metal view size changed to: \(size.width) x \(size.height)")
        
        // Force a redraw to update with the new size
        self.setNeedsDisplay(NSRect(origin: .zero, size: size))
    }
    
    // MARK: - Helper Methods
    // Setup the Metal rendering pipeline
    private func setupPipeline() {
        guard let device = self.device else {
            print("Cannot setup pipeline - no Metal device")
            return
        }
        
        // Load our shader files
        var library: MTLLibrary?
        
        // Try multiple paths to load the shader
        do {
            // Try to load from the file system first
            let possibleShaderPaths = [
                FileManager.default.currentDirectoryPath + "/Sources/Metal/Shaders/Shaders.metal",
                "Sources/Metal/Shaders/Shaders.metal",
                "../Sources/Metal/Shaders/Shaders.metal"
            ]
            
            var foundShader = false
            for path in possibleShaderPaths where !foundShader {
                do {
                    if FileManager.default.fileExists(atPath: path) {
                        let source = try String(contentsOfFile: path, encoding: .utf8)
                        library = try device.makeLibrary(source: source, options: nil)
                        print("Loaded shader from path: \(path)")
                        foundShader = true
                    }
                } catch {
                    print("Failed to load shader from \(path): \(error)")
                }
            }
            
            // If we couldn't load from a file, try the default library
            if !foundShader {
                // Try to load the default library without a try block since this shouldn't throw
                library = device.makeDefaultLibrary()
                if library != nil {
                    print("Using default Metal library")
                } else {
                    print("Failed to load default Metal library")
                    print("Rendering will be limited")
                }
            }
        }
        
        // Create the pipeline state
        if let library = library {
            do {
                // Define the vertex descriptor to match our vertex data format
                let vertexDescriptor = MTLVertexDescriptor()
                
                // Position attribute
                vertexDescriptor.attributes[0].format = .float4
                vertexDescriptor.attributes[0].offset = 0
                vertexDescriptor.attributes[0].bufferIndex = 0
                
                // Color attribute
                vertexDescriptor.attributes[1].format = .float4
                vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.stride * 4 // After position
                vertexDescriptor.attributes[1].bufferIndex = 0
                
                // Define the layout
                vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.stride * 8 // 4 for position + 4 for color
                vertexDescriptor.layouts[0].stepRate = 1
                vertexDescriptor.layouts[0].stepFunction = .perVertex
                
                // Create the render pipeline descriptor
                let pipelineDescriptor = MTLRenderPipelineDescriptor()
                pipelineDescriptor.vertexDescriptor = vertexDescriptor
                pipelineDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat
                pipelineDescriptor.depthAttachmentPixelFormat = self.depthStencilPixelFormat
                
                // Try to get vertex and fragment functions
                if let vertexFunction = library.makeFunction(name: "vertexShader"),
                   let fragmentFunction = library.makeFunction(name: "fragmentShader") {
                    
                    pipelineDescriptor.vertexFunction = vertexFunction
                    pipelineDescriptor.fragmentFunction = fragmentFunction
                    
                    // Create the pipeline state
                    trianglePipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
                    print("Successfully created triangle rendering pipeline state")
                } else {
                    print("Failed to find required shader functions")
                }
            } catch {
                print("Failed to create render pipeline state: \(error)")
            }
        }
    }
    
    // Method to draw video frame with effects
    @MainActor private func drawVideoWithEffects(renderEncoder: MTLRenderCommandEncoder, texture: MTLTexture, pipelineState: MTLRenderPipelineState) {
        // Set the render pipeline state
        renderEncoder.setRenderPipelineState(pipelineState)
        
        // Set vertex buffer
        if let videoQuadBuffer = videoQuadBuffer {
            renderEncoder.setVertexBuffer(videoQuadBuffer, offset: 0, index: 0)
        }
        
        // Set the video texture
        renderEncoder.setFragmentTexture(texture, index: 0)
        
        // Set the sampler state
        if let samplerState = samplerState {
            renderEncoder.setFragmentSamplerState(samplerState, index: 0)
        }
        
        // Set the uniform buffer for morphing parameters
        if let uniformBuffer = uniformBuffer {
            renderEncoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        }
        
        // Draw the quad as two triangles (using a triangle strip)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
    
    // Helper method to draw a simple colored triangle
    @MainActor private func drawSimpleTriangle(renderEncoder: MTLRenderCommandEncoder, device: MTLDevice, pipelineState: MTLRenderPipelineState) {
        // Define a simple triangle (position + color for each vertex)
        let vertices: [Float] = [
             0.0,  0.5, 0.0, 1.0,    1.0, 0.0, 0.0, 1.0, // Top vertex (red)
            -0.5, -0.5, 0.0, 1.0,    0.0, 1.0, 0.0, 1.0, // Bottom left (green)
             0.5, -0.5, 0.0, 1.0,    0.0, 0.0, 1.0, 1.0  // Bottom right (blue)
        ]
        
        // Create a buffer for the vertices
        guard let vertexBuffer = device.makeBuffer(bytes: vertices, 
                                                 length: vertices.count * MemoryLayout<Float>.size, 
                                                 options: []) else {
            return
        }
        
        // Identity matrix for MVP transform
        let identityMatrix: [Float] = [
            1.0, 0.0, 0.0, 0.0,
            0.0, 1.0, 0.0, 0.0,
            0.0, 0.0, 1.0, 0.0,
            0.0, 0.0, 0.0, 1.0
        ]
        
        // Create a buffer for the transformation matrix
        guard let transformBuffer = device.makeBuffer(bytes: identityMatrix,
                                                    length: identityMatrix.count * MemoryLayout<Float>.size,
                                                    options: []) else {
            return
        }
        
        // Set the pipeline state - we know it exists because it was passed as a parameter
        renderEncoder.setRenderPipelineState(pipelineState)
        
        // Set vertex buffers and draw
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(transformBuffer, offset: 0, index: 1)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
    
    // Helper method to create a render pass descriptor
    @MainActor private func createRenderPassDescriptor() -> MTLRenderPassDescriptor? {
        guard let texture = currentDrawable?.texture else { return nil }
        
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = clearColor
        
        return descriptor
    }
}
