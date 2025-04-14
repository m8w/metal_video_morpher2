import Foundation
import AppKit

/// Errors related to data operations
public enum DataError: Error {
    case fileNotFound
    case invalidFileFormat
    case loadFailed(String)
    case saveFailed(String)
    case processingFailed(String)
    case outOfMemory
    
    public var localizedDescription: String {
        switch self {
        case .fileNotFound:
            return "The specified file could not be found"
        case .invalidFileFormat:
            return "The file format is not supported or is corrupted"
        case .loadFailed(let reason):
            return "Failed to load data: \(reason)"
        case .saveFailed(let reason):
            return "Failed to save data: \(reason)"
        case .processingFailed(let reason):
            return "Data processing failed: \(reason)"
        case .outOfMemory:
            return "Not enough memory to process the data"
        }
    }
}

/// Represents a video frame for processing
public struct VideoFrame {
    public let timestamp: TimeInterval
    public let image: NSImage
    public let index: Int
    
    public init(timestamp: TimeInterval, image: NSImage, index: Int) {
        self.timestamp = timestamp
        self.image = image
        self.index = index
    }
}

/// Protocol defining the data management operations
public protocol DataManagerProtocol {
    /// Load a video file from the specified URL
    /// - Parameter url: The URL of the video file
    /// - Returns: Number of frames loaded
    /// - Throws: DataError if loading fails
    func loadVideo(from url: URL) throws -> Int
    
    /// Get a specific frame from the loaded video
    /// - Parameter index: Index of the frame to retrieve
    /// - Returns: The video frame, or nil if not available
    func getFrame(at index: Int) -> VideoFrame?
    
    /// Get the total number of frames in the current video
    /// - Returns: Frame count or 0 if no video is loaded
    func getFrameCount() -> Int
    
    /// Save processed frames to a new video file
    /// - Parameters:
    ///   - frames: The frames to save
    ///   - url: The destination URL
    /// - Throws: DataError if saving fails
    func saveVideo(frames: [VideoFrame], to url: URL) throws
    
    /// Clear all loaded data to free up memory
    func clearData()
}

