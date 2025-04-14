import Foundation
@preconcurrency import AVFoundation
@preconcurrency import CoreVideo
@preconcurrency import Metal
import AppKit
import Domain

/// Class for handling video file playback and frame extraction
@MainActor
class VideoFileController: NSObject {
    // MARK: - Properties
    // MARK: - Properties
    
    // AVPlayer for video playback
    // Using nonisolated(unsafe) because AVPlayer is thread-safe for basic operations
    // like play/pause as documented in Apple's AVFoundation documentation
    nonisolated(unsafe) private var player: AVPlayer?
    
    // Using nonisolated(unsafe) for playerItem so we can handle notifications in a thread-safe manner
    nonisolated(unsafe) private var playerItem: AVPlayerItem?
    
    // Output for extracting frames from the video
    private var playerItemOutput: AVPlayerItemVideoOutput?
    
    // Display link for synchronized frame extraction
    // Using nonisolated(unsafe) because CVDisplayLink operations are thread-safe
    // and we only need start/stop operations in cleanup context
    nonisolated(unsafe) private var displayLink: CVDisplayLink?
    // Reference to the Metal device
    private let device: MTLDevice?
    
    // Texture manager for handling texture operations
    nonisolated private let textureManager: TextureManager
    
    // Delegate to receive video frames
    weak var delegate: VideoFrameDelegate?
    
    // Current playback info
    private var isPlaying: Bool = false
    private var videoURL: URL?
    private var duration: CMTime = .zero
    
    // Last frame timestamp to avoid duplicates
    private var lastFrameTime: CMTime = .zero
    
    // MARK: - Initialization
    // MARK: - Initialization
    
    override init() {
        // Get the default Metal device
        let metalDevice = MTLCreateSystemDefaultDevice()
        self.device = metalDevice
        
        // Create the texture manager
        self.textureManager = TextureManager(device: metalDevice)
        
        super.init()
    }
    
    deinit {
        // Ensure cleanup on deallocation
        // Use the nonisolated versions for deinit
        nonisolatedCleanupDisplayLink()
        nonisolatedCleanupPlayer()
    }
    // MARK: - Public Methods
    
    /// Load a video file from the specified URL
    /// - Parameter url: URL to the video file
    func loadVideo(from url: URL) async throws {
        // Clean up any existing resources
        cleanupPlayer()
        
        // Store the URL
        videoURL = url
        
        // Create an asset from the URL
        let asset = AVAsset(url: url)
        
        // Ensure the asset is playable
        let tracks = try await asset.load(.tracks)
        guard !tracks.isEmpty else {
            throw NSError(domain: "com.metalvideoprocessor", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "No tracks found in video file"])
        }
        
        // Check if any video tracks exist
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard !videoTracks.isEmpty else {
            throw NSError(domain: "com.metalvideoprocessor", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "No video tracks found in file"])
        }
        
        // Create a player item with the asset
        let playerItem = AVPlayerItem(asset: asset)
        self.playerItem = playerItem
        
        // Configure output for Metal texture extraction
        let pixelBufferAttributes = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: pixelBufferAttributes)
        playerItem.add(output)
        self.playerItemOutput = output
        
        // Create and configure the player
        let player = AVPlayer(playerItem: playerItem)
        self.player = player
        
        // Get video duration
        self.duration = try await asset.load(.duration)
        
        // Set up display link for frame extraction
        try setupDisplayLink()
        
        // Add notification for when playback ends
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
    }
    
    /// Start playing the video
    func play() {
        guard let player = player, !isPlaying else { return }
        
        player.play()
        isPlaying = true
    }
    
    /// Pause the video
    func pause() {
        guard let player = player, isPlaying else { return }
        
        player.pause()
        isPlaying = false
    }
    
    /// Seek to a specific time in the video
    /// - Parameter time: The time to seek to
    func seek(to time: CMTime) {
        guard let player = player else { return }
        
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    /// Seek to a specific position in the video (0.0 to 1.0)
    /// - Parameter position: A value between 0.0 and 1.0 representing the position in the video
    func seek(to position: Double) {
        guard let player = player, duration.seconds > 0 else { return }
        
        // Calculate the target time
        let seconds = position * duration.seconds
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    /// Get current playback position (0.0 to 1.0)
    func currentPosition() -> Double {
        guard let player = player, duration.seconds > 0 else { return 0.0 }
        
        let currentTime = player.currentTime()
        return currentTime.seconds / duration.seconds
    }
    
    /// Get the current video dimensions
    func videoDimensions() async -> CGSize {
        guard let playerItem = playerItem else { return CGSize(width: 640, height: 480) }
        
        do {
            let tracks = try await playerItem.asset.loadTracks(withMediaType: .video)
            if let videoTrack = tracks.first {
                let dimensions = try await videoTrack.load(.naturalSize)
                return dimensions
            }
        } catch {
            print("Failed to get video dimensions: \(error)")
        }
        
        return CGSize(width: 640, height: 480)
    }
    
    // MARK: - Display Link and Frame Extraction
    
    /// Set up the display link for synchronized frame extraction
    private func setupDisplayLink() throws {
        // Clean up any existing display link
        cleanupDisplayLink()
        
        // Create CVDisplayLink
        var displayLink: CVDisplayLink?
        var status = CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard status == kCVReturnSuccess, let displayLink = displayLink else {
            throw NSError(domain: "com.metalvideoprocessor", code: 3,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to create display link"])
        }
        
        // Set output callback
        let callback: CVDisplayLinkOutputCallback = { displayLink, _, _, _, _, userInfo in
            let controller = unsafeBitCast(userInfo, to: VideoFileController.self)
            
            // Dispatch to the main thread for UI updates
            DispatchQueue.main.async {
                controller.displayLinkFired()
            }
            
            return kCVReturnSuccess
        }
        
        status = CVDisplayLinkSetOutputCallback(displayLink, callback, Unmanaged.passUnretained(self).toOpaque())
        guard status == kCVReturnSuccess else {
            throw NSError(domain: "com.metalvideoprocessor", code: 4,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to set display link callback"])
        }
        
        // Store the display link
        self.displayLink = displayLink
        
        // Start the display link
        CVDisplayLinkStart(displayLink)
    }
    
    /// Clean up the display link (for use within MainActor context)
    private func cleanupDisplayLink() {
        if let displayLink = displayLink {
            CVDisplayLinkStop(displayLink)
            self.displayLink = nil
        }
    }
    
    /// Non-isolated version of display link cleanup for use in deinit
    /// Safe to use because CVDisplayLink is thread-safe for stop/release operations
    nonisolated private func nonisolatedCleanupDisplayLink() {
        if let displayLink = self.displayLink {
            CVDisplayLinkStop(displayLink)
            self.displayLink = nil
        }
    }
    
    /// Called when the display link fires
    @MainActor private func displayLinkFired() {
        // Only process frames if we're playing
        guard isPlaying else { return }
        
        // Extract the current frame and send it to the delegate
        if let (texture, timestamp) = extractCurrentFrame() {
            // Only send new frames (avoid duplicates)
            if timestamp != lastFrameTime {
                delegate?.didReceiveVideoFrame(texture: texture, timestamp: timestamp)
                lastFrameTime = timestamp
            }
        }
    }
    
    /// Extract the current frame from the video as a Metal texture
    /// - Returns: A tuple containing the Metal texture and its timestamp, or nil if no frame is available
    private func extractCurrentFrame() -> (MTLTexture, CMTime)? {
        // Ensure we have a valid player and output
        guard let player = player, let output = playerItemOutput else {
            print("Missing player or output")
            return nil
        }
        
        // Get the current time
        let itemTime = player.currentTime()
        
        // Only proceed if the time is valid
        if itemTime.value == 0 && itemTime.timescale == 0 {
            print("Invalid player time")
            return nil
        }
        
        // Check if a new frame is available at the current time
        if !output.hasNewPixelBuffer(forItemTime: itemTime) {
            // This is normal during playback, not an error
            return nil
        }
        
        // Get the pixel buffer for the current time
        guard let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) else {
            print("Failed to copy pixel buffer for time: \(itemTime)")
            return nil
        }
        
        // Convert the pixel buffer to a Metal texture
        guard let texture = textureManager.createTexture(from: pixelBuffer) else {
            print("Failed to create texture from pixel buffer")
            return nil
        }
        
        return (texture, itemTime)
    }
    
    // MARK: - Cleanup
    
    /// Clean up the player and related resources (for use within MainActor context)
    private func cleanupPlayer() {
        // Stop playback
        player?.pause()
        
        // Remove notification observers
        if let playerItem = playerItem {
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        }
        
        // Clear references
        self.player = nil
        self.playerItem = nil
        self.playerItemOutput = nil
        self.isPlaying = false
    }
    
    /// Non-isolated version of player cleanup for use in deinit
    /// Non-isolated version of player cleanup for use in deinit
    /// Safe to use because:
    /// 1. AVPlayer is thread-safe for basic operations like pause
    /// 2. NotificationCenter is thread-safe for observer operations
    /// 3. This is only used during object deallocation
    nonisolated private func nonisolatedCleanupPlayer() {
        // Stop playback - AVPlayer is thread-safe for pause
        player?.pause()
        
        // Remove notification observers - NotificationCenter is thread-safe
        if let playerItem = self.playerItem {
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        }
        
        // Now safe to nil out properties since they're nonisolated(unsafe)
        self.player = nil
        self.playerItem = nil
    }
    // MARK: - Notification Handlers
    
    @objc private func playerItemDidReachEnd(notification: Notification) {
        // Loop playback if needed
        player?.seek(to: .zero)
        
        // If we were playing, restart playback
        if isPlaying {
            player?.play()
        }
    }
}

