#!/bin/bash
# Build and Test Script for ScreenCapture
# This script allows Conductor agents to build, validate, and optionally run the app

set -e

# Configuration
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="$PROJECT_DIR/ScreenCapture.xcodeproj"
SCHEME="ScreenCapture"
CONFIGURATION="Debug"
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_status() {
    echo -e "${BLUE}[BUILD]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --build         Build the application (default action)"
    echo "  --run           Build and run the application"
    echo "  --open-xcode    Open the project in Xcode"
    echo "  --clean         Clean build artifacts before building"
    echo "  --release       Build in Release configuration"
    echo "  --verbose       Show full build output"
    echo "  --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Just build"
    echo "  $0 --run              # Build and run the app"
    echo "  $0 --clean --build    # Clean build"
    echo "  $0 --open-xcode       # Open in Xcode"
}

# Parse arguments
ACTION="build"
CLEAN=false
VERBOSE=false
OPEN_XCODE=false
RUN_APP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --build)
            ACTION="build"
            shift
            ;;
        --run)
            RUN_APP=true
            shift
            ;;
        --open-xcode)
            OPEN_XCODE=true
            shift
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        --release)
            CONFIGURATION="Release"
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Change to project directory
cd "$PROJECT_DIR"

# Open Xcode if requested
if [ "$OPEN_XCODE" = true ]; then
    print_status "Opening project in Xcode..."
    open "$PROJECT_FILE"
    print_success "Xcode opened"
    if [ "$RUN_APP" = false ] && [ "$CLEAN" = false ]; then
        exit 0
    fi
fi

# Clean if requested
if [ "$CLEAN" = true ]; then
    print_status "Cleaning build artifacts..."
    xcodebuild -project "$PROJECT_FILE" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        clean 2>&1 | tail -5
    print_success "Clean complete"
fi

# Build
print_status "Building $SCHEME ($CONFIGURATION)..."
BUILD_START=$(date +%s)

if [ "$VERBOSE" = true ]; then
    xcodebuild -project "$PROJECT_FILE" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        build 2>&1
    BUILD_EXIT=$?
else
    # Capture build output, show only errors/warnings and summary
    BUILD_OUTPUT=$(xcodebuild -project "$PROJECT_FILE" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        build 2>&1)
    BUILD_EXIT=$?

    # Extract and display errors and warnings
    ERRORS=$(echo "$BUILD_OUTPUT" | grep -E "error:|warning:" || true)
    if [ -n "$ERRORS" ]; then
        echo "$ERRORS"
    fi

    # Show build result
    if echo "$BUILD_OUTPUT" | grep -q "BUILD SUCCEEDED"; then
        echo "** BUILD SUCCEEDED **"
    elif echo "$BUILD_OUTPUT" | grep -q "BUILD FAILED"; then
        echo "** BUILD FAILED **"
        # Show more context on failure
        echo ""
        echo "Build output (last 50 lines):"
        echo "$BUILD_OUTPUT" | tail -50
    fi
fi

BUILD_END=$(date +%s)
BUILD_TIME=$((BUILD_END - BUILD_START))

if [ $BUILD_EXIT -ne 0 ]; then
    print_error "Build failed after ${BUILD_TIME}s"
    exit 1
fi

print_success "Build succeeded in ${BUILD_TIME}s"

# Find the built app
APP_PATH=$(find "$DERIVED_DATA" -name "ScreenCapture.app" -path "*/$CONFIGURATION/*" -type d 2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
    print_warning "Could not find built app path"
else
    print_status "Built app: $APP_PATH"
fi

# Run the app if requested
if [ "$RUN_APP" = true ]; then
    if [ -z "$APP_PATH" ]; then
        print_error "Cannot run: app not found"
        exit 1
    fi

    # Kill any existing instance
    pkill -x "ScreenCapture" 2>/dev/null || true
    sleep 0.5

    print_status "Launching ScreenCapture..."
    open "$APP_PATH"
    print_success "App launched"
fi

# Summary
echo ""
echo "=========================================="
echo -e "${GREEN}BUILD VALIDATION COMPLETE${NC}"
echo "=========================================="
echo "Configuration: $CONFIGURATION"
echo "Build time: ${BUILD_TIME}s"
if [ -n "$APP_PATH" ]; then
    echo "App location: $APP_PATH"
fi
echo "=========================================="

exit 0
