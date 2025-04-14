#!/bin/bash
# Build script for Metal Video Morpher

# Exit on error
set -e

# Define colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# App configuration
APP_NAME="MetalVideoMorpher"
APP_DIR="$(pwd)/dist"
APP_BUNDLE_PATH="$APP_DIR/$APP_NAME.app"
APP_IDENTIFIER="com.yourcompany.metalvideomorpher"
SWIFT_PACKAGE_DIR="$(pwd)"  # Current directory contains the Swift package
RELEASE_BUILD=false

# Parse command line args
for arg in "$@"; do
  case $arg in
    --release)
      RELEASE_BUILD=true
      shift
      ;;
    *)
      # Unknown option
      ;;
  esac
done

# Function to handle errors
handle_error() {
    echo -e "${RED}Error: $1${NC}"
    exit 1
}

# Print current directory and Swift package location
echo -e "${BLUE}Current directory: $(pwd)${NC}"
echo -e "${BLUE}Swift package directory: $SWIFT_PACKAGE_DIR${NC}"

# Verify Swift package directory exists
if [ ! -f "$SWIFT_PACKAGE_DIR/Package.swift" ]; then
    handle_error "Swift package not found at $SWIFT_PACKAGE_DIR"
fi

echo -e "${BLUE}Building ${APP_NAME}...${NC}"

# Build the Swift package
if [ "$RELEASE_BUILD" = true ]; then
    echo -e "${BLUE}Building release configuration...${NC}"
    swift build -c release || handle_error "Swift build failed"
    BUILD_PATH="$SWIFT_PACKAGE_DIR/.build/release"
else
    echo -e "${BLUE}Building debug configuration...${NC}"
    swift build || handle_error "Swift build failed"
    BUILD_PATH="$SWIFT_PACKAGE_DIR/.build/debug"
fi

echo -e "${GREEN}Swift build completed successfully.${NC}"

# Create app bundle directory structure
echo -e "${BLUE}Creating app bundle structure...${NC}"
mkdir -p "$APP_BUNDLE_PATH/Contents/MacOS" || handle_error "Failed to create MacOS directory"
mkdir -p "$APP_BUNDLE_PATH/Contents/Resources" || handle_error "Failed to create Resources directory"
mkdir -p "$APP_BUNDLE_PATH/Contents/Frameworks" || handle_error "Failed to create Frameworks directory"

# Verify executable exists
if [ ! -f "$BUILD_PATH/App" ]; then
    handle_error "Executable not found at $BUILD_PATH/App"
fi

# Copy the built executable
echo -e "${BLUE}Copying executable to app bundle...${NC}"
cp "$BUILD_PATH/App" "$APP_BUNDLE_PATH/Contents/MacOS/$APP_NAME" || handle_error "Failed to copy executable"

# Create Info.plist
echo -e "${BLUE}Creating Info.plist...${NC}"
cat > "$APP_BUNDLE_PATH/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${APP_IDENTIFIER}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSCameraUsageDescription</key>
    <string>This app needs access to your camera to capture and process video frames for applying visual effects.</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>mp4</string>
                <string>mov</string>
                <string>m4v</string>
            </array>
            <key>CFBundleTypeName</key>
            <string>Movie</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
        </dict>
    </array>
</dict>
</plist>
EOF

# Copy Metal shader files to Resources
echo -e "${BLUE}Copying Metal shader resources...${NC}"
SHADER_DIR="$SWIFT_PACKAGE_DIR/Sources/Metal/Shaders"
if [ -d "$SHADER_DIR" ]; then
    mkdir -p "$APP_BUNDLE_PATH/Contents/Resources/Shaders" || handle_error "Failed to create Shaders directory"
    cp -R "$SHADER_DIR/"* "$APP_BUNDLE_PATH/Contents/Resources/Shaders/" || handle_error "Failed to copy shader resources"
    echo -e "${GREEN}Copied shader resources.${NC}"
else
    echo -e "${RED}Warning: Shader directory not found at $SHADER_DIR${NC}"
fi

# Set executable permissions
echo -e "${BLUE}Setting executable permissions...${NC}"
chmod +x "$APP_BUNDLE_PATH/Contents/MacOS/$APP_NAME" || handle_error "Failed to set executable permissions"

# Code signing
if command -v codesign &> /dev/null; then
    echo -e "${BLUE}Checking for available signing identities...${NC}"
    IDENTITY=$(security find-identity -v -p codesigning | grep -o '"[^"]*"' | head -1 | tr -d '"')
    
    if [ -n "$IDENTITY" ]; then
        echo -e "${BLUE}Signing app with identity: ${IDENTITY}${NC}"
        codesign --force --options runtime --sign "$IDENTITY" "$APP_BUNDLE_PATH" || echo -e "${RED}Signing failed, but continuing...${NC}"
        echo -e "${GREEN}App signed successfully.${NC}"
    else
        echo -e "${RED}No code signing identity found. App will not be signed.${NC}"
    fi
else
    echo -e "${RED}codesign command not found. App will not be signed.${NC}"
fi

echo -e "${GREEN}App bundle created at: ${APP_BUNDLE_PATH}${NC}"
echo -e "${BLUE}To run the app: open ${APP_BUNDLE_PATH}${NC}"

# Create a zip archive for distribution
if [ "$RELEASE_BUILD" = true ]; then
    echo -e "${BLUE}Creating zip archive for distribution...${NC}"
    ZIP_NAME="${APP_NAME}.zip"
    (cd "$APP_DIR" && zip -r "$ZIP_NAME" "$(basename "$APP_BUNDLE_PATH")") || handle_error "Failed to create zip archive"
    echo -e "${GREEN}Zip archive created: $APP_DIR/$ZIP_NAME${NC}"
fi

echo -e "${GREEN}Build completed successfully!${NC}"

