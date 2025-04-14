
import Foundation
@preconcurrency import AVFoundation
@preconcurrency import Metal
@preconcurrency import CoreVideo
import AppKit
import Domain  // Import Domain module for VideoFrameDelegate

// A class to handle thread-safe texture creation
// This separates texture operations from the MainActor
// 
// Using @unchecked Sendable because:
// 1. CVMetalTextureCache is thread-safe per Apple's documentation
// 2. We only initialize it once during init() and never modify it
// 3. All access to it is properly synchronized
// 4. Metal textures are designed to be shared across threads safely
final class TextureManager: @unchecked Sendable {
    // Store the texture cache for reuse
    // This is effectively immutable after initialization and CVMetalTextureCache
    // is documented to be thread-safe for concurrent access
    private let textureCache: CVMetalTextureCache?
    
    init(device: MTLDevice?) {
        // Initialize texture cache if we have a Metal device
        var textureCacheTemp: CVMetalTextureCache?
        if let device = device {
            CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCacheTemp)
        }
        self.textureCache = textureCacheTemp
    }
    
    // Create a Metal texture from a pixel buffer
    // This method is thread-safe and can be called from any thread
    func createTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // Lock the buffer
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        // Create a Metal texture from the pixel buffer
        var cvMetalTexture: CVMetalTexture?
        
        guard let textureCache = self.textureCache else {
            print("Missing texture cache")
            return nil
        }

        // Create a Metal texture from the pixel buffer
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvMetalTexture
        )
        
        // Check for success
        guard status == kCVReturnSuccess, let cvMetalTexture = cvMetalTexture else {
            print("Failed to create Metal texture from pixel buffer, status: \(status)")
            return nil
        }
        
        // Get the Metal texture
        let texture = CVMetalTextureGetTexture(cvMetalTexture)
        return texture
    }
}

// Use the VideoFrameDelegate protocol from Domain module instead of redefining it
// Class for handling video capture
@MainActor
class VideoCaptureController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    // MARK: - Properties
    
    // Capture session and related objects
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var captureDevice: AVCaptureDevice?
    
    // Reference to the Metal device
    private let device: MTLDevice?
    
    // Texture manager for handling texture operations outside of the MainActor
    // This is marked nonisolated since TextureManager is designed to be thread-safe
    // and we need to access it from the nonisolated captureOutput method
    nonisolated private let textureManager: TextureManager
    
    // Delegate to receive video frames
    weak var delegate: VideoFrameDelegate?
    
    // Status tracking
    var isRunning: Bool = false
    
    // Queue for processing video frames
    private let processingQueue = DispatchQueue(label: "com.metalvideoprocessor.capture", qos: .userInteractive)
    
    // Initialization
    override init() {
        // Get the default Metal device
        let metalDevice = MTLCreateSystemDefaultDevice()
        self.device = metalDevice
        
        // Create the texture manager
        self.textureManager = TextureManager(device: metalDevice)
        
        super.init()
    }
    
    // Request camera permission
    func requestCameraAccess() async throws {
        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch authorizationStatus {
        case .authorized:
            return // Already authorized
        case .notDetermined:
            // Request permission
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
            
            if !granted {
                throw NSError(domain: "com.metalvideoprocessor", code: 1, 
                             userInfo: [NSLocalizedDescriptionKey: "Camera access denied"])
            }
        case .denied, .restricted:
            throw NSError(domain: "com.metalvideoprocessor", code: 2, 
                         userInfo: [NSLocalizedDescriptionKey: "Camera access restricted"])
        @unknown default:
            throw NSError(domain: "com.metalvideoprocessor", code: 3, 
                         userInfo: [NSLocalizedDescriptionKey: "Unknown camera authorization status"])
        }
    }
    
    // Setup and start capture
    func startCapture() async throws {
        // Create and configure the capture session
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .high
        
        // Find the camera
        guard let camera = AVCaptureDevice.default(for: .video) else {
            throw NSError(domain: "com.metalvideoprocessor", code: 4, 
                         userInfo: [NSLocalizedDescriptionKey: "No camera available"])
        }
        
        // Create device input
        let deviceInput = try AVCaptureDeviceInput(device: camera)
        
        // Add input to session
        if session.canAddInput(deviceInput) {
            session.addInput(deviceInput)
        } else {
            throw NSError(domain: "com.metalvideoprocessor", code: 5, 
                         userInfo: [NSLocalizedDescriptionKey: "Could not add camera input to session"])
        }
        
        // Create video output
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        
        // Add output to session
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        } else {
            throw NSError(domain: "com.metalvideoprocessor", code: 6, 
                         userInfo: [NSLocalizedDescriptionKey: "Could not add video output to session"])
        }
        
        // Finalize configuration
        session.commitConfiguration()
        
        // Store objects
        self.captureSession = session
        self.videoOutput = videoOutput
        self.captureDevice = camera
        
        // Start the session
        session.startRunning()
        isRunning = true
    }
    
    // Stop capture
    func stopCapture() async {
        guard let session = captureSession, session.isRunning else { return }
        
        session.stopRunning()
        isRunning = false
    }
    
    // AVCaptureVideoDataOutputSampleBufferDelegate method
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Ensure we have a pixel buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Could not get pixel buffer from sample buffer")
            return
        }
        
        // Get the timestamp
        // Get the timestamp
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        // Use the texture manager to create the texture
        guard let metalTexture = textureManager.createTexture(from: pixelBuffer) else {
            print("Failed to create Metal texture from pixel buffer")
            return
        }
        // Send the texture to the delegate on the main thread
        Task { @MainActor in
            delegate?.didReceiveVideoFrame(texture: metalTexture, timestamp: timestamp)
        }
    }
    
    // Note: Texture creation is now handled by TextureManager
}
