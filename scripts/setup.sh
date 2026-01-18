#!/bin/bash
# Setup Script for ScreenCapture
# Verifies the development environment is ready

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[SETUP]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

ERRORS=0

echo "=========================================="
echo "ScreenCapture Development Environment Setup"
echo "=========================================="
echo ""

# Check Xcode
print_status "Checking Xcode installation..."
if xcode-select -p &>/dev/null; then
    XCODE_PATH=$(xcode-select -p)
    print_success "Xcode found at: $XCODE_PATH"
else
    print_error "Xcode command line tools not found"
    print_status "Install with: xcode-select --install"
    ERRORS=$((ERRORS + 1))
fi

# Check xcodebuild
print_status "Checking xcodebuild..."
if command -v xcodebuild &>/dev/null; then
    XCODE_VERSION=$(xcodebuild -version | head -1)
    print_success "$XCODE_VERSION"
else
    print_error "xcodebuild not found"
    ERRORS=$((ERRORS + 1))
fi

# Check project file exists
print_status "Checking project file..."
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$PROJECT_DIR/ScreenCapture.xcodeproj/project.pbxproj" ]; then
    print_success "Project file found"
else
    print_error "ScreenCapture.xcodeproj not found"
    ERRORS=$((ERRORS + 1))
fi

# Check build script is executable
print_status "Checking build script..."
if [ -x "$PROJECT_DIR/scripts/build-and-test.sh" ]; then
    print_success "Build script is executable"
else
    print_warning "Build script not executable, fixing..."
    chmod +x "$PROJECT_DIR/scripts/build-and-test.sh"
    print_success "Build script is now executable"
fi

# Verify build works
print_status "Verifying build..."
if "$PROJECT_DIR/scripts/build-and-test.sh" &>/dev/null; then
    print_success "Build verification passed"
else
    print_error "Build verification failed"
    print_status "Run './scripts/build-and-test.sh --verbose' for details"
    ERRORS=$((ERRORS + 1))
fi

# Summary
echo ""
echo "=========================================="
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}SETUP COMPLETE - Environment is ready${NC}"
    echo ""
    echo "Quick commands:"
    echo "  ./scripts/build-and-test.sh        # Build"
    echo "  ./scripts/build-and-test.sh --run  # Build and run"
    exit 0
else
    echo -e "${RED}SETUP FAILED - $ERRORS error(s) found${NC}"
    echo "Please fix the errors above before proceeding."
    exit 1
fi
