
import Foundation
import AppKit
import Domain

/// Implementation of the DataManager for handling video data
public class DataManager: DataManagerProtocol {
    // MARK: - Properties
    
    /// Loaded video frames
    private var frames: [VideoFrame] = []
    
    /// Original video URL
    private var currentVideoURL: URL?
    
    // MARK: - Initialization
    
    public init() {
        // Initialize with empty state
    }
    
    // MARK: - DataManagerProtocol Implementation
    
    public func loadVideo(from url: URL) throws -> Int {
        // Clear any existing data
        clearData()
        
        // Store the current URL
        currentVideoURL = url
        
        // Check if the file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DataError.fileNotFound
        }
        
        // For now, we'll implement a placeholder that creates a few test frames
        // In a real implementation, this would use AVFoundation to extract frames
        
        // Create some test frames with colored squares
        for i in 0..<10 {
            // Create a colored image
            let size = NSSize(width: 640, height: 480)
            let image = NSImage(size: size)
            
            image.lockFocus()
            
            // Calculate a color based on the frame index
            let red = CGFloat(i) / 10.0
            let green = 0.5
            let blue = 1.0 - (CGFloat(i) / 10.0)
            NSColor(red: red, green: green, blue: blue, alpha: 1.0).setFill()
            
            // Fill the entire image
            NSRect(origin: .zero, size: size).fill()
            
            // Add frame number text
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 48),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraphStyle
            ]
            
            let text = "Frame \(i + 1)"
            let textRect = NSRect(x: 0, y: size.height / 2 - 24, width: size.width, height: 48)
            text.draw(in: textRect, withAttributes: attributes)
            
            image.unlockFocus()
            
            // Create the video frame
            let frame = VideoFrame(
                timestamp: TimeInterval(i) / 30.0, // Assuming 30fps
                image: image,
                index: i
            )
            
            frames.append(frame)
        }
        
        print("Loaded \(frames.count) test frames")
        return frames.count
    }
    
    public func getFrame(at index: Int) -> VideoFrame? {
        guard index >= 0, index < frames.count else {
            return nil
        }
        
        return frames[index]
    }
    
    public func getFrameCount() -> Int {
        return frames.count
    }
    
    public func saveVideo(frames: [VideoFrame], to url: URL) throws {
        // This would normally use AVFoundation to create a video file
        // For now, we'll just log the operation
        print("Would save \(frames.count) frames to \(url.path)")
        
        // In a real implementation, we would:
        // 1. Create an AVAssetWriter
        // 2. Configure video settings
        // 3. Write each frame
        // 4. Finalize the video file
        
        // For this example, we'll throw an error if frames is empty
        if frames.isEmpty {
            throw DataError.saveFailed("No frames to save")
        }
    }
    
    public func clearData() {
        frames.removeAll()
        currentVideoURL = nil
    }
    
    // MARK: - Helper Methods
    
    /// For debugging: Saves a single frame as a PNG file
    /// - Parameters:
    ///   - frame: The frame to save
    ///   - url: Destination URL for the PNG file
    /// - Throws: DataError if saving fails
    public func saveFrameAsPNG(_ frame: VideoFrame, to url: URL) throws {
        guard let tiffData = frame.image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw DataError.saveFailed("Failed to convert image to PNG")
        }
        
        do {
            try pngData.write(to: url)
            print("Saved frame to \(url.path)")
        } catch {
            throw DataError.saveFailed(error.localizedDescription)
        }
    }
}

