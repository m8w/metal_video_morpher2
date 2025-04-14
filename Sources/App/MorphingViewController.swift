import AppKit
@preconcurrency import Metal
import AVFoundation
import Domain  // Import Domain module for MorphEffect
import MetalRenderer  // Import Metal module for MetalView

@MainActor
class MorphingViewController: NSViewController {
    // MARK: - Properties
    
    // Video Source
    private enum VideoSource {
        case camera
        case file
    }
    private var currentSource: VideoSource = .camera
    
    // UI Controls
    private var sourceSegmentedControl: NSSegmentedControl!
    private var effectSegmentedControl: NSSegmentedControl!
    private var intensitySlider: NSSlider!
    private var segmentCountSlider: NSSlider!
    private var extraParamSlider: NSSlider!
    private var startStopButton: NSButton!
    private var openFileButton: NSButton!
    private var playPauseButton: NSButton!
    private var seekSlider: NSSlider!
    private var statusLabel: NSTextField!
    
    // Metal view for rendering
    private var metalView: MetalView?
    
    // Video sources
    private var videoCaptureController: VideoCaptureController?
    private var videoFileController: VideoFileController?
    
    // Video file info
    private var currentVideoURL: URL?
    
    // Current effect parameters
    private var currentEffect: Domain.MorphEffect = .none
    private var effectIntensity: Double = 0.5
    private var segmentCount: Double = 6.0
    private var extraParam: Double = 0.0
    private var touchPosition: CGPoint = .zero
    
    // Video state
    private var isCapturing = false
    private var isVideoPlaying = false
    
    // MARK: - View Lifecycle
    
    override func loadView() {
        // Create the main view container
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.black.cgColor
        
        // Set up the Metal view
        setupMetalView(in: containerView)
        
        // Set up the UI controls
        setupUIControls(in: containerView)
        
        // Set as the view controller's view
        self.view = containerView
        
        // Set up event handling for mouse input
        setupMouseTracking()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Initialize with wave effect
        selectEffect(Domain.MorphEffect.wave)
        updateEffectParameters()
        
        // Initialize video file controller
        videoFileController = VideoFileController()
    }
    // MARK: - UI Setup
    
    private func setupMetalView(in containerView: NSView) {
        // Create a Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            showAlert(title: "Error", message: "Metal is not supported on this device")
            return
        }
        
        // Create the Metal view
        let metalView = MetalView(frame: containerView.bounds, device: device)
        metalView.autoresizingMask = [.width, .height]
        metalView.translatesAutoresizingMaskIntoConstraints = false
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        
        // Add to the container
        containerView.addSubview(metalView)
        
        // Add constraints to fill the container (minus space for controls)
        NSLayoutConstraint.activate([
            metalView.topAnchor.constraint(equalTo: containerView.topAnchor),
            metalView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            metalView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -120)
        ])
        
        // Store a reference
        self.metalView = metalView
    }
    
    private func setupUIControls(in containerView: NSView) {
        // Create a control panel at the bottom
        let controlPanel = NSView(frame: NSRect(x: 0, y: 0, width: containerView.bounds.width, height: 80))
        controlPanel.wantsLayer = true
        controlPanel.layer?.backgroundColor = NSColor(white: 0.2, alpha: 1.0).cgColor
        controlPanel.translatesAutoresizingMaskIntoConstraints = false
        
        containerView.addSubview(controlPanel)
        
        // Position the control panel at the bottom (make it taller to accommodate more controls)
        NSLayoutConstraint.activate([
            controlPanel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            controlPanel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            controlPanel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            controlPanel.heightAnchor.constraint(equalToConstant: 120)
        ])
        
        // Create source selection control
        sourceSegmentedControl = NSSegmentedControl(labels: ["Camera", "Video File"], trackingMode: .selectOne, target: self, action: #selector(sourceChanged))
        sourceSegmentedControl.selectedSegment = 0
        sourceSegmentedControl.translatesAutoresizingMaskIntoConstraints = false
        
        controlPanel.addSubview(sourceSegmentedControl)
        
        // Create camera control button
        startStopButton = NSButton(title: "Start Camera", target: self, action: #selector(toggleCapture))
        startStopButton.bezelStyle = .rounded
        startStopButton.translatesAutoresizingMaskIntoConstraints = false
        
        controlPanel.addSubview(startStopButton)
        
        // Create open file button
        openFileButton = NSButton(title: "Open Video...", target: self, action: #selector(openVideo))
        openFileButton.bezelStyle = .rounded
        openFileButton.translatesAutoresizingMaskIntoConstraints = false
        openFileButton.isHidden = true  // Initially hidden because we start with camera mode
        
        controlPanel.addSubview(openFileButton)
        
        // Create play/pause button for video
        playPauseButton = NSButton(title: "Play", target: self, action: #selector(togglePlayback))
        playPauseButton.bezelStyle = .rounded
        playPauseButton.translatesAutoresizingMaskIntoConstraints = false
        playPauseButton.isHidden = true  // Initially hidden
        
        controlPanel.addSubview(playPauseButton)
        
        // Create seek slider for video
        seekSlider = NSSlider(value: 0, minValue: 0, maxValue: 1.0, target: self, action: #selector(seekVideo))
        seekSlider.translatesAutoresizingMaskIntoConstraints = false
        seekSlider.isHidden = true  // Initially hidden
        
        controlPanel.addSubview(seekSlider)
        
        // Create a segmented control for effect selection
        effectSegmentedControl = NSSegmentedControl(labels: ["None", "Wave", "Pixelate", "Swirl", "Bulge", "Kaleidoscope"], trackingMode: .selectOne, target: self, action: #selector(effectChanged))
        effectSegmentedControl.selectedSegment = 0
        effectSegmentedControl.translatesAutoresizingMaskIntoConstraints = false
        
        controlPanel.addSubview(effectSegmentedControl)
        
        // Create an intensity slider
        let intensityLabel = createLabel("Intensity:")
        intensitySlider = NSSlider(value: effectIntensity, minValue: 0, maxValue: 1, target: self, action: #selector(intensityChanged))
        // Target and action now set in initializer
        intensitySlider.translatesAutoresizingMaskIntoConstraints = false
        
        controlPanel.addSubview(intensityLabel)
        controlPanel.addSubview(intensitySlider)
        
        // Create a segments slider for kaleidoscope
        let segmentsLabel = createLabel("Segments:")
        segmentCountSlider = NSSlider(value: segmentCount, minValue: 3, maxValue: 20, target: self, action: #selector(segmentsChanged))
        // Target and action now set in initializer
        segmentCountSlider.translatesAutoresizingMaskIntoConstraints = false
        
        controlPanel.addSubview(segmentsLabel)
        controlPanel.addSubview(segmentCountSlider)
        
        // Create an extra parameter slider
        let extraParamLabel = createLabel("Extra:")
        extraParamSlider = NSSlider(value: extraParam, minValue: 0, maxValue: 1, target: self, action: #selector(extraParamChanged))
        // Target and action now set in initializer
        extraParamSlider.translatesAutoresizingMaskIntoConstraints = false
        
        controlPanel.addSubview(extraParamLabel)
        controlPanel.addSubview(extraParamSlider)
        
        // Create a status label at the top
        statusLabel = createLabel("Ready")
        statusLabel.alignment = .center
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        
        containerView.addSubview(statusLabel)
        
        // Position the status label at the top
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
            statusLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            statusLabel.widthAnchor.constraint(equalToConstant: 300),
            statusLabel.heightAnchor.constraint(equalToConstant: 20)
        ])
        
        // Position all the controls
        NSLayoutConstraint.activate([
            // Source selector (top row)
            sourceSegmentedControl.topAnchor.constraint(equalTo: controlPanel.topAnchor, constant: 10),
            sourceSegmentedControl.leadingAnchor.constraint(equalTo: controlPanel.leadingAnchor, constant: 10),
            sourceSegmentedControl.widthAnchor.constraint(equalToConstant: 200),
            
            // Camera button (next to source selector)
            startStopButton.centerYAnchor.constraint(equalTo: sourceSegmentedControl.centerYAnchor),
            startStopButton.leadingAnchor.constraint(equalTo: sourceSegmentedControl.trailingAnchor, constant: 10),
            
            // Open file button (same position as camera button, but shown only in file mode)
            openFileButton.centerYAnchor.constraint(equalTo: sourceSegmentedControl.centerYAnchor),
            openFileButton.leadingAnchor.constraint(equalTo: sourceSegmentedControl.trailingAnchor, constant: 10),
            
            // Play/pause button
            playPauseButton.topAnchor.constraint(equalTo: sourceSegmentedControl.bottomAnchor, constant: 10),
            playPauseButton.leadingAnchor.constraint(equalTo: controlPanel.leadingAnchor, constant: 10),
            
            // Seek slider
            seekSlider.centerYAnchor.constraint(equalTo: playPauseButton.centerYAnchor),
            seekSlider.leadingAnchor.constraint(equalTo: playPauseButton.trailingAnchor, constant: 10),
            seekSlider.widthAnchor.constraint(equalToConstant: 200),
            
            // Effect selector (middle row)
            effectSegmentedControl.topAnchor.constraint(equalTo: playPauseButton.bottomAnchor, constant: 15),
            effectSegmentedControl.leadingAnchor.constraint(equalTo: controlPanel.leadingAnchor, constant: 10),
            effectSegmentedControl.widthAnchor.constraint(equalToConstant: 400),
            
            // Intensity slider
            intensityLabel.leadingAnchor.constraint(equalTo: effectSegmentedControl.trailingAnchor, constant: 15),
            intensityLabel.centerYAnchor.constraint(equalTo: effectSegmentedControl.centerYAnchor),
            
            intensitySlider.leadingAnchor.constraint(equalTo: intensityLabel.trailingAnchor, constant: 5),
            intensitySlider.centerYAnchor.constraint(equalTo: intensityLabel.centerYAnchor),
            intensitySlider.widthAnchor.constraint(equalToConstant: 150),
            
            // Segments slider
            segmentsLabel.leadingAnchor.constraint(equalTo: intensitySlider.trailingAnchor, constant: 15),
            segmentsLabel.centerYAnchor.constraint(equalTo: intensityLabel.centerYAnchor),
            
            segmentCountSlider.leadingAnchor.constraint(equalTo: segmentsLabel.trailingAnchor, constant: 5),
            segmentCountSlider.centerYAnchor.constraint(equalTo: segmentsLabel.centerYAnchor),
            segmentCountSlider.widthAnchor.constraint(equalToConstant: 100),
            
            // Extra parameter slider
            extraParamLabel.leadingAnchor.constraint(equalTo: effectSegmentedControl.leadingAnchor),
            extraParamLabel.topAnchor.constraint(equalTo: effectSegmentedControl.bottomAnchor, constant: 10),
            
            extraParamSlider.leadingAnchor.constraint(equalTo: extraParamLabel.trailingAnchor, constant: 5),
            extraParamSlider.centerYAnchor.constraint(equalTo: extraParamLabel.centerYAnchor),
            extraParamSlider.widthAnchor.constraint(equalToConstant: 150)
        ])
    }
    
    private func createLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = .white
        label.backgroundColor = .clear
        label.isBezeled = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
    
    private func setupMouseTracking() {
        // Add a tracking area to detect mouse movement for position-based effects
        let trackingArea = NSTrackingArea(
            rect: view.bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(trackingArea)
    }
    
    // MARK: - Event Handlers
    
    override func mouseMoved(with event: NSEvent) {
        // Convert event location to view coordinates
        let viewLocation = view.convert(event.locationInWindow, from: nil)
        
        // Only update if the point is within the Metal view area
        if let metalView = metalView, metalView.frame.contains(viewLocation) {
            // Convert to Metal view coordinates
            let metalViewLocation = metalView.convert(viewLocation, from: view)
            
            // Store the position
            touchPosition = metalViewLocation
            
            // Update the effect
            updateTouchPosition()
            
            // Update status
            statusLabel.stringValue = "Touch: \(Int(metalViewLocation.x)), \(Int(metalViewLocation.y))"
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        // Update status
        statusLabel.stringValue = "Mouse entered view"
    }
    
    override func mouseExited(with event: NSEvent) {
        // Reset touch position when mouse exits
        touchPosition = CGPoint(x: metalView?.bounds.midX ?? 0, y: metalView?.bounds.midY ?? 0)
        updateTouchPosition()
        
        // Update status
        statusLabel.stringValue = "Mouse exited view"
    }
    
    @objc private func toggleCapture() {
        // Ensure we're in camera mode
        if currentSource != .camera {
            sourceSegmentedControl.selectedSegment = 0
            sourceChanged()
            return
        }
        
        Task {
            if isCapturing {
                // Stop capture
                await stopVideoCapture()
                startStopButton.title = "Start Camera"
                isCapturing = false
                statusLabel.stringValue = "Camera stopped"
            } else {
                // Start capture
                await startVideoCapture()
                startStopButton.title = "Stop Camera"
                isCapturing = true
                statusLabel.stringValue = "Camera started"
            }
        }
    }
    
    @objc private func effectChanged() {
        let selectedSegment = effectSegmentedControl.selectedSegment
        
        // Convert segment index to effect type
        switch selectedSegment {
        case 0:
            selectEffect(Domain.MorphEffect.none)
        case 1:
            selectEffect(Domain.MorphEffect.wave)
        case 2:
            selectEffect(Domain.MorphEffect.pixelate)
        case 3:
            selectEffect(Domain.MorphEffect.swirl)
        case 4:
            selectEffect(Domain.MorphEffect.bulge)
        case 5:
            selectEffect(Domain.MorphEffect.kaleidoscope)
        default:
            selectEffect(Domain.MorphEffect.none)
        }
        
        // Update parameters based on the selected effect
        updateEffectParameters()
        
        // Update status
        statusLabel.stringValue = "Effect: \(effectSegmentedControl.label(forSegment: selectedSegment) ?? "Unknown")"
    }
    
    @objc private func intensityChanged() {
        effectIntensity = intensitySlider.doubleValue
        updateEffectParameters()
        
        // Update status
        statusLabel.stringValue = "Intensity: \(String(format: "%.2f", effectIntensity))"
    }
    
    @objc private func segmentsChanged() {
        segmentCount = segmentCountSlider.doubleValue
        updateEffectParameters()
        
        // Update status
        statusLabel.stringValue = "Segments: \(Int(segmentCount))"
    }
    
    @objc private func extraParamChanged() {
        extraParam = extraParamSlider.doubleValue
        updateEffectParameters()
        
        // Update status
        statusLabel.stringValue = "Extra: \(String(format: "%.2f", extraParam))"
    }
    
    // MARK: - Video Capture Methods
    
    private func startVideoCapture() async {
        // Create video capture controller if needed
        if videoCaptureController == nil {
            videoCaptureController = VideoCaptureController()
        }
        
        // Connect to Metal view
        if let metalView = metalView {
            videoCaptureController?.delegate = metalView
        }
        
        // Request camera access and start capture
        do {
            try await videoCaptureController?.requestCameraAccess()
            try await videoCaptureController?.startCapture()
            statusLabel.stringValue = "Video capture started"
        } catch {
            print("Failed to start video capture: \(error)")
            showAlert(title: "Camera Error", 
                     message: "Failed to access the camera: \(error.localizedDescription)")
        }
    }
    
    private func stopVideoCapture() async {
        await videoCaptureController?.stopCapture()
        statusLabel.stringValue = "Video capture stopped"
    }
    
    // MARK: - Effect Methods
    
    // MARK: - Video File Methods
    
    /// Switch between camera and video file sources
    @objc private func sourceChanged() {
        let selectedSegment = sourceSegmentedControl.selectedSegment
        
        Task {
            // First, stop any active source
            await stopCurrentVideoSource()
            
            // Switch source based on selection
            switch selectedSegment {
            case 0: // Camera
                currentSource = .camera
                
                // Show camera controls, hide video controls
                startStopButton.isHidden = false
                openFileButton.isHidden = true
                playPauseButton.isHidden = true
                seekSlider.isHidden = true
                
                // Update status
                statusLabel.stringValue = "Camera mode selected"
                
            case 1: // Video file
                currentSource = .file
                
                // Hide camera controls, show video controls
                startStopButton.isHidden = true
                openFileButton.isHidden = false
                playPauseButton.isHidden = false
                seekSlider.isHidden = false
                
                // Initialize video controller if needed
                if videoFileController == nil {
                    videoFileController = VideoFileController()
                    if let metalView = metalView {
                        videoFileController?.delegate = metalView
                    }
                }
                
                // Update status
                statusLabel.stringValue = "Video file mode selected"
                
                // If no video is loaded yet, prompt to open one
                if currentVideoURL == nil {
                    openVideo()
                }
            default:
                break
            }
        }
    }
    
    /// Open a video file using NSOpenPanel
    @objc private func openVideo() {
        // Create and configure an open panel
        let openPanel = NSOpenPanel()
        openPanel.title = "Select Video File"
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        openPanel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, .mpeg2Video, .avi]
        
        // Show the panel
        openPanel.beginSheetModal(for: self.view.window!) { [weak self] response in
            guard let self = self, response == .OK, let url = openPanel.url else { return }
            
            // Load the selected video
            Task {
                await self.loadVideoFile(from: url)
            }
        }
    }
    
    /// Load a video file from the specified URL
    private func loadVideoFile(from url: URL) async {
        guard let videoFileController = videoFileController else { return }
        
        do {
            // Load the video file
            try await videoFileController.loadVideo(from: url)
            
            // Store the URL
            currentVideoURL = url
            
            // Update UI
            playPauseButton.title = "Play"
            isVideoPlaying = false
            
            // Reset seek slider
            seekSlider.doubleValue = 0.0
            
            // Start a timer to update the seek slider position
            startSeekSliderUpdateTimer()
            
            // Update status
            statusLabel.stringValue = "Video loaded: \(url.lastPathComponent)"
        } catch {
            showAlert(title: "Video Load Error", 
                     message: "Failed to load video: \(error.localizedDescription)")
            
            statusLabel.stringValue = "Error loading video"
        }
    }
    
    /// Toggle video playback
    @objc private func togglePlayback() {
        guard let videoFileController = videoFileController else { return }
        
        if isVideoPlaying {
            // Pause the video
            videoFileController.pause()
            playPauseButton.title = "Play"
            isVideoPlaying = false
            statusLabel.stringValue = "Video paused"
        } else {
            // Play the video
            videoFileController.play()
            playPauseButton.title = "Pause"
            isVideoPlaying = true
            statusLabel.stringValue = "Video playing"
        }
    }
    
    /// Seek to a position in the video
    @objc private func seekVideo() {
        guard let videoFileController = videoFileController else { return }
        
        // Get the position from the slider (0.0 to 1.0)
        let position = seekSlider.doubleValue
        
        // Seek to the position
        videoFileController.seek(to: position)
        
        // Update status
        let formattedPosition = String(format: "%.1f%%", position * 100)
        statusLabel.stringValue = "Seeking to \(formattedPosition)"
    }
    
    /// Start a timer to update the seek slider position during playback
    private func startSeekSliderUpdateTimer() {
        // Use a MainActor Task instead of Timer to ensure proper actor isolation
        Task { @MainActor in
            do {
                while !Task.isCancelled {
                    // Only update if we're in file mode and playing
                    if currentSource == .file, 
                       let videoFileController = self.videoFileController,
                       isVideoPlaying {
                        // Get the current position safely from main actor context
                        let position = videoFileController.currentPosition()
                        
                        // Update the slider (already on the main actor)
                        seekSlider.doubleValue = position
                    }
                    
                    // Wait before next update (50 frames per second)
                    try await Task.sleep(for: .milliseconds(500))
                }
            } catch {
                // Task cancelled or other error
                print("Seek slider update task ended: \(error.localizedDescription)")
            }
        }
    }
    
    /// Stop the current video source (camera or file)
    private func stopCurrentVideoSource() async {
        switch currentSource {
        case .camera:
            if isCapturing {
                await stopVideoCapture()
                isCapturing = false
                startStopButton.title = "Start Camera"
            }
        case .file:
            if isVideoPlaying, let videoFileController = videoFileController {
                videoFileController.pause()
                isVideoPlaying = false
                playPauseButton.title = "Play"
            }
        }
    }
    
    // MARK: - Effect Methods
    
    // Select the current effect
    private func selectEffect(_ effect: Domain.MorphEffect) {
        currentEffect = effect
        
        // Update the UI
        effectSegmentedControl.selectedSegment = Int(effect.rawValue)
        
        // Enable/disable parameters based on the selected effect
        updateControlsForCurrentEffect()
    }
    
    // Update the morphing parameters
    private func updateEffectParameters() {
        // Update Metal view with current parameters
        metalView?.setMorphAmount(effectIntensity)
        metalView?.setMorphEffect(currentEffect)
        
        // Set extra parameters based on effect type
        var extraParams = SIMD4<Float>(Float(segmentCount), 0, 0, 0)
        
        // For kaleidoscope effect, first param is segment count
        if currentEffect == Domain.MorphEffect.kaleidoscope {
            extraParams.x = Float(segmentCount)
        }
        
        // For grayscale control in some effects
        if extraParam > 0 {
            extraParams.y = 1.0 // Enable grayscale
            extraParams.z = Float(extraParam) // Grayscale amount
        }
        
        metalView?.setExtraParams(extraParams)
    }
    
    // Update the touch position
    private func updateTouchPosition() {
        if let metalView = metalView {
            // Normalize touch position to [0,1] range for the shader
            let normalizedX = touchPosition.x / metalView.bounds.width
            let normalizedY = touchPosition.y / metalView.bounds.height
            
            // Send to MetalView
            metalView.setTouchPosition(CGPoint(x: normalizedX, y: normalizedY))
        }
    }
    
    // Update controls based on the current effect
    private func updateControlsForCurrentEffect() {
        // Enable/disable specific controls based on the effect
        switch currentEffect {
        case .none:
            // Disable all control sliders
            intensitySlider.isEnabled = false
            segmentCountSlider.isEnabled = false
            extraParamSlider.isEnabled = false
            
        case .kaleidoscope:
            // Enable segment count for kaleidoscope
            intensitySlider.isEnabled = true
            segmentCountSlider.isEnabled = true
            extraParamSlider.isEnabled = true
            
        case .wave, .pixelate, .swirl, .bulge:
            // Most effects only need intensity and extra
            intensitySlider.isEnabled = true
            segmentCountSlider.isEnabled = false
            extraParamSlider.isEnabled = true
        }
    }
    
    // MARK: - Utility Methods
    
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
    
    // MARK: - Cleanup
    
    override func viewWillDisappear() {
        super.viewWillDisappear()
        
        // Clean up resources
        Task {
            await stopCurrentVideoSource()
        }
    }
}
