# Metal Video Morpher

A macOS application that applies real-time morphing effects to video input using Apple's Metal framework. The app supports both live camera input and video file playback with a variety of visual effects.

## Features

- **Dual Input Support:**
  - Live camera capture with permissions handling
  - Video file playback with seeking controls

- **Multiple Visual Effects:**
  - None (passthrough)
  - Wave effect
  - Pixelate
  - Swirl
  - Bulge
  - Kaleidoscope (adjustable segments)

- **Interactive Controls:**
  - Effect selection
  - Effect intensity adjustment
  - Position-based effects using mouse tracking
  - Additional parameters for each effect

- **Efficient Implementation:**
  - Metal-accelerated graphics processing
  - Thread-safe architecture with proper actor isolation
  - Optimized frame extraction and rendering

## Building the Application

### Quick Build (Release)

To build a release version of the app:

```bash
# From the project root directory
./build.sh --release
```

This will:
1. Compile the Swift package in release mode
2. Create an app bundle in `dist/MetalVideoMorpher.app`
3. Create a distributable zip file in `dist/MetalVideoMorpher.zip`
4. Code sign the app if certificates are available

### Development Build

For development builds:

```bash
# From the project root directory
./build.sh
```

This creates a debug build with additional debugging information.

### Running the App

After building, run the app with:

```bash
open dist/MetalVideoMorpher.app
```

## Development Setup

### Requirements

- macOS 13.0 or later
- Xcode Command Line Tools
- Swift 5.9 or later

### Development Environment

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd metal_video_morpher2
   ```

2. Build the Swift package:
   ```bash
   swift build
   ```

3. For testing individual components:
   ```bash
   swift test
   ```

### Project Structure

The project follows a modular architecture with:

- **App Layer** (`Sources/App/`): Main application code and UI
- **Domain Layer** (`Sources/Domain/`): Business logic and protocols
- **Data Layer** (`Sources/Data/`): Data handling
- **Metal Renderer** (`Sources/Metal/`): Graphics rendering code

## Key Files

- `Package.swift`: Swift package configuration
- `Sources/App/AppDelegate.swift`: Main application entry point
- `Sources/App/MorphingViewController.swift`: Main UI controller
- `Sources/App/VideoCaptureController.swift`: Camera input handling
- `Sources/App/VideoFileController.swift`: Video file input handling
- `Sources/Metal/MetalView.swift`: Metal rendering view
- `Sources/Metal/Shaders/`: Metal shader files
- `build.sh`: Script to build and package the app

## Continuing Development

### Getting Back to Work

When returning to development:

1. Navigate to the project directory:
   ```bash
   cd /Users/wvn/Documents/GitHub/wvn/metal_video_morpher2
   ```

2. Update dependencies if needed:
   ```bash
   swift package update
   ```

3. Build the app:
   ```bash
   ./build.sh
   ```

### Adding New Effects

To add a new visual effect:

1. Add a new case to the `MorphEffect` enum in `Sources/Domain/VideoProcessingProtocols.swift`
2. Implement the shader in `Sources/Metal/Shaders/`
3. Add UI controls in `MorphingViewController.swift`
4. Update the shader selector in `MetalView.swift`

### Modifying UI

The UI is implemented using AppKit. Main UI components are in:
- `MorphingViewController.swift`: Main UI layout and control handling
- `MetalView.swift`: Rendering canvas

## Troubleshooting

### Common Issues

- **Camera Access Denied**: Ensure camera permissions are granted in System Preferences → Security & Privacy → Camera
- **Build Failures**: Ensure Xcode Command Line Tools are installed (`xcode-select --install`)
- **Shader Compilation Errors**: Check Metal shader syntax in `Sources/Metal/Shaders/`

### Debug Builds

For more detailed debugging:

```bash
swift build -c debug
```

This creates a debug build with additional debugging symbols.

## License

[Insert your license information here]

## Acknowledgments

- Apple Metal framework documentation
- [Any other acknowledgments]

