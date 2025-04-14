import Foundation
import Metal
import CoreMedia

/// Protocol for receiving video frames for processing
@MainActor
public protocol VideoFrameDelegate: AnyObject {
    /// Called when a new video frame is available
    /// - Parameters:
    ///   - texture: The Metal texture containing the video frame
    ///   - timestamp: The timestamp of the video frame
    func didReceiveVideoFrame(texture: MTLTexture, timestamp: CMTime)
}

/// Constants for effect types
public enum MorphEffect: Float {
    case none = 0.0
    case wave = 1.0
    case pixelate = 2.0
    case swirl = 3.0
    case bulge = 4.0
    case kaleidoscope = 5.0
}

/// Protocol for morphing parameter control
@MainActor
public protocol MorphingControlProtocol {
    /// Set the morphing amount
    /// - Parameter amount: Value between 0.0 and 1.0
    func setMorphAmount(_ amount: Double)
    
    /// Set the morphing effect type
    /// - Parameter effect: The effect to apply
    func setMorphEffect(_ effect: MorphEffect)
    
    /// Set the touch position for position-based effects
    /// - Parameter position: Point in view coordinates
    func setTouchPosition(_ position: CGPoint)
    
    /// Set extra parameters for effects
    /// - Parameter params: Vector of 4 parameters
    func setExtraParams(_ params: SIMD4<Float>)
}

