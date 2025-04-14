
import Foundation
import AppKit
import Metal
import MetalKit
import Domain
/// Implementation of the Metal renderer
@MainActor
public class MetalRenderer: MetalRendererProtocol {
    // MARK: - Properties
    
    // Metal objects
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var metalView: MetalView?
    
    // Rendering properties
    private var clearColor: MTLClearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
    
    // MARK: - Initialization
    
    public init() {
        // Initialization will be deferred to the initialize() method
    }
    
    // MARK: - MetalRendererProtocol Implementation
    
    public func initialize() async throws {
        // Create a Metal device (this operation is thread-safe)
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetalError.deviceCreationFailed
        }
        
        // Switch to main actor for UI-related operations
        await MainActor.run {
            self.device = device
            
            // Create command queue
            guard let commandQueue = device.makeCommandQueue() else {
                print("Failed to create command queue")
                return
            }
            
            self.commandQueue = commandQueue
        }
        
        // Setup will be completed when createRenderView is called
        print("Metal initialized successfully with device: \(device.name)")
    }
    public func createRenderView() -> NSView {
        guard let device = device else {
            fatalError("Metal device not initialized. Call initialize() first.")
        }
        
        // Create the Metal view
        let metalView = MetalView(frame: .zero, device: device)
        metalView.clearColor = clearColor
        metalView.delegate = metalView // Will act as its own delegate for now
        metalView.enableSetNeedsDisplay = true
        metalView.framebufferOnly = false
        
        // Create a simple render pipeline
        createRenderPipeline(metalView: metalView)
        
        // Store a reference to the view
        self.metalView = metalView
        
        return metalView
    }
    
    public func setClearColor(_ color: (red: Double, green: Double, blue: Double, alpha: Double)) {
        clearColor = MTLClearColor(
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha
        )
        
        metalView?.clearColor = clearColor
    }
    
    public func resize(to size: CGSize) async {
        // The MTKView will automatically handle resizing, but we can add custom logic here if needed
        print("Renderer resized to: \(size.width) x \(size.height)")
    }
    public func beginFrame() throws -> Any {
        guard let metalView = metalView, let commandQueue = commandQueue else {
            throw MetalError.renderingFailed("Metal view or command queue not initialized")
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw MetalError.renderingFailed("Failed to create command buffer")
        }
        
        // Create a render pass descriptor
        guard let renderPassDescriptor = metalView.currentRenderPassDescriptor else {
            throw MetalError.renderingFailed("Failed to create render pass descriptor")
        }
        
        // Create a render command encoder
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            throw MetalError.renderingFailed("Failed to create render command encoder")
        }
        
        // Return the command buffer and encoder as a tuple
        return (commandBuffer, renderEncoder)
    }
    
    public func endFrame(frameToken: Any) throws {
        guard let (commandBuffer, renderEncoder) = frameToken as? (MTLCommandBuffer, MTLRenderCommandEncoder) else {
            throw MetalError.renderingFailed("Invalid frame token")
        }
        
        // End encoding
        renderEncoder.endEncoding()
        
        // Get the drawable and present it
        if let drawable = metalView?.currentDrawable {
            commandBuffer.present(drawable)
        }
        
        // Commit the command buffer
        commandBuffer.commit()
    }
    
    // This method doesn't interact with the UI, so it's safe to mark as nonisolated
    public static nonisolated func isSupported() -> Bool {
        return MTLCreateSystemDefaultDevice() != nil
    }
    
    // Public method to access the pipeline state
    public func getPipelineState() -> MTLRenderPipelineState? {
        return pipelineState
    }
    
    private func createRenderPipeline(metalView: MetalView) {
        guard let device = device else { return }
        
        // Try multiple approaches to load the Metal shader library
        var defaultLibrary: MTLLibrary? = nil
        
        // First, try to create an embedded shader with a hardcoded simple shader if all else fails
        let fallbackShaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        
        // Vertex input structure
        struct VertexInput {
            float4 position [[attribute(0)]];
            float4 color [[attribute(1)]];
        };
        
        // Vertex output structure
        struct VertexOutput {
            float4 position [[position]];
            float4 color;
        };
        
        // Simple vertex shader
        vertex VertexOutput basicVertexShader(uint vertexID [[vertex_id]],
                             constant float4 *positions [[buffer(0)]],
                             constant float4 *colors [[buffer(1)]]) {
            VertexOutput out;
            out.position = positions[vertexID];
            out.color = colors[vertexID];
            return out;
        }
        
        // Simple fragment shader
        fragment float4 basicFragmentShader(VertexOutput in [[stage_in]]) {
            return in.color;
        }
        """
        
        // Try loading strategies in order of preference
        
        // 1. First try: Use the bundle's default library
        do {
            defaultLibrary = try device.makeDefaultLibrary(bundle: Bundle.module)
            print("Successfully loaded Metal library from Bundle.module")
        } catch {
            print("Could not load Metal library from bundle: \(error)")
            
            // 2. Second try: Try to load from the file system
            let possiblePaths = [
                FileManager.default.currentDirectoryPath + "/Sources/Metal/Shaders/Shaders.metal",
                "Sources/Metal/Shaders/Shaders.metal",
                "../Sources/Metal/Shaders/Shaders.metal"
            ]
            
            var foundShader = false
            for shaderPath in possiblePaths {
                if !foundShader {
                    do {
                        let shaderSource = try String(contentsOfFile: shaderPath, encoding: .utf8)
                        defaultLibrary = try device.makeLibrary(source: shaderSource, options: nil)
                        print("Successfully loaded Metal library from file: \(shaderPath)")
                        foundShader = true
                    } catch {
                        print("Could not load Metal library from \(shaderPath): \(error)")
                    }
                }
            }
            
            // 3. Third try: System default library
            if !foundShader {
                do {
                    if let library = device.makeDefaultLibrary() {
                        defaultLibrary = library
                        print("Using system default Metal library")
                    } else {
                        // 4. Final fallback: Use the hardcoded shader
                        defaultLibrary = try device.makeLibrary(source: fallbackShaderSource, options: nil)
                        print("Using hardcoded fallback shader")
                    }
                } catch {
                    print("All attempts to load Metal library failed: \(error)")
                }
            }
        }
        // Create the render pipeline descriptor
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "Basic Render Pipeline"
        
        // Set the pixel format to match the Metal view
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = metalView.depthStencilPixelFormat
        // A simple placeholder vertex descriptor for when we have no actual shader
        if defaultLibrary == nil {
            print("Creating fallback empty pipeline - rendering will be limited")
            
            // Create a very basic render pipeline state with minimal requirements
            // This will at least clear the screen but won't render anything
            do {
                self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
                print("Created fallback Metal render pipeline")
            } catch {
                print("Failed to create even a fallback pipeline: \(error)")
            }
            return
        }
        
        // If we successfully loaded the library, set up the shader functions
        guard let library = defaultLibrary else { return }
        
        // Get the vertex and fragment functions from the library
        do {
            // Try to get the shader functions - try multiple function names in case we're using a fallback
            let vertexFunctionNames = ["vertexShader", "basicVertexShader", "textureVertexShader"]
            let fragmentFunctionNames = ["fragmentShader", "basicFragmentShader", "textureFragmentShader"]
            
            var vertexFunction: MTLFunction? = nil
            var fragmentFunction: MTLFunction? = nil
            
            // Try each vertex function name until we find one that works
            for name in vertexFunctionNames {
                if vertexFunction == nil {
                    vertexFunction = library.makeFunction(name: name)
                    if vertexFunction != nil {
                        print("Using vertex function: \(name)")
                    }
                }
            }
            
            // Try each fragment function name until we find one that works
            for name in fragmentFunctionNames {
                if fragmentFunction == nil {
                    fragmentFunction = library.makeFunction(name: name)
                    if fragmentFunction != nil {
                        print("Using fragment function: \(name)")
                    }
                }
            }
            
            guard let vertexFunction = vertexFunction, let fragmentFunction = fragmentFunction else {
                print("Could not find shader functions in library")
                throw MetalError.libraryCreationFailed
            }
            // Set up the functions in the pipeline descriptor
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            
            // Set up a basic vertex descriptor for our shaders
            let vertexDescriptor = MTLVertexDescriptor()
            
            // Position
            vertexDescriptor.attributes[0].format = .float4
            vertexDescriptor.attributes[0].offset = 0
            vertexDescriptor.attributes[0].bufferIndex = 0
            
            // Color
            vertexDescriptor.attributes[1].format = .float4
            vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD4<Float>>.stride
            vertexDescriptor.attributes[1].bufferIndex = 0
            
            // Layout
            vertexDescriptor.layouts[0].stride = MemoryLayout<SIMD4<Float>>.stride * 2
            vertexDescriptor.layouts[0].stepRate = 1
            vertexDescriptor.layouts[0].stepFunction = .perVertex
            
            pipelineDescriptor.vertexDescriptor = vertexDescriptor
            
            print("Successfully set up shader functions for pipeline")
            
            // Create the actual pipeline state
            self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            print("Created Metal render pipeline state successfully")
        } catch {
            print("Failed to create render pipeline state: \(error)")
        }
    }
}

