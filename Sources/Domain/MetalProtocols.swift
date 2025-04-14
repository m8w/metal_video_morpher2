import Foundation
import AppKit

/// Represents errors that can occur in Metal operations
public enum MetalError: Error {
    case deviceCreationFailed
    case libraryCreationFailed
    case pipelineCreationFailed
    case commandQueueCreationFailed
    case textureCreationFailed
    case bufferCreationFailed
    case renderingFailed(String)
    case unsupportedPixelFormat
    
    public var localizedDescription: String {
        switch self {
        case .deviceCreationFailed:
            return "Failed to create Metal device"
        case .libraryCreationFailed:
            return "Failed to create Metal shader library"
        case .pipelineCreationFailed:
            return "Failed to create Metal rendering pipeline"
        case .commandQueueCreationFailed:
            return "Failed to create Metal command queue"
        case .textureCreationFailed:
            return "Failed to create Metal texture"
        case .bufferCreationFailed:
            return "Failed to create Metal buffer"
        case .renderingFailed(let reason):
            return "Rendering failed: \(reason)"
        case .unsupportedPixelFormat:
            return "Unsupported pixel format for Metal processing"
        }
    }
}
/// Protocol defining the requirements for a Metal renderer
@preconcurrency
public protocol MetalRendererProtocol {
    /// Initialize the Metal renderer
    /// - Throws: MetalError if initialization fails
    func initialize() async throws
    
    /// Create a view for rendering
    /// - Returns: NSView that can be added to the view hierarchy
    @MainActor
    func createRenderView() -> NSView
    
    /// Set the clear color for the renderer
    /// - Parameter color: The color to clear the view with
    @MainActor
    func setClearColor(_ color: (red: Double, green: Double, blue: Double, alpha: Double))
    
    /// Resize the renderer to handle a new size
    /// - Parameter size: The new size for rendering
    func resize(to size: CGSize) async
    
    /// Begin a new rendering frame
    /// - Returns: A token representing the current frame
    @MainActor
    func beginFrame() throws -> Any
    
    /// End the current rendering frame and present it
    /// - Parameter frameToken: The token from beginFrame()
    @MainActor
    func endFrame(frameToken: Any) throws
    
    /// Check if Metal is supported on this device
    /// - Returns: Boolean indicating if Metal is supported
    static func isSupported() -> Bool
}
