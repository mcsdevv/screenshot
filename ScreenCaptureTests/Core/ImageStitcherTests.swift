import XCTest
@testable import ScreenCapture

final class ImageStitcherTests: XCTestCase {

    var stitcher: ImageStitcher!

    override func setUp() {
        super.setUp()
        stitcher = ImageStitcher()
    }

    override func tearDown() {
        stitcher = nil
        super.tearDown()
    }

    // MARK: - Empty Array Tests

    func testStitchEmptyArrayReturnsNil() {
        let result = stitcher.stitch(images: [])
        XCTAssertNil(result)
    }

    // MARK: - Single Image Tests

    func testStitchSingleImageReturnsSameImage() {
        let testSize = CGSize(width: 200, height: 100)
        let image = TestImageGenerator.createSolidColorImage(size: testSize, color: .red)

        let result = stitcher.stitch(images: [image])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.size.width, testSize.width)
        XCTAssertEqual(result?.size.height, testSize.height)
    }

    func testStitchSingleImagePreservesContent() {
        let image = TestImageGenerator.createImageWithText("SINGLE", size: CGSize(width: 300, height: 150))

        let result = stitcher.stitch(images: [image])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.size, image.size)
    }

    // MARK: - Multiple Images Tests

    func testStitchTwoImagesReturnsStitchedImage() {
        let imageSize = CGSize(width: 200, height: 100)
        let image1 = TestImageGenerator.createSolidColorImage(size: imageSize, color: .red)
        let image2 = TestImageGenerator.createSolidColorImage(size: imageSize, color: .blue)

        let result = stitcher.stitch(images: [image1, image2])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.size.width, imageSize.width)
        // Height should be less than 2x due to 10% overlap
        XCTAssertLessThan(result!.size.height, imageSize.height * 2)
    }

    func testStitchCalculatesCorrectOverlap() {
        let imageSize = CGSize(width: 200, height: 100)
        let image1 = TestImageGenerator.createSolidColorImage(size: imageSize, color: .red)
        let image2 = TestImageGenerator.createSolidColorImage(size: imageSize, color: .blue)

        let result = stitcher.stitch(images: [image1, image2])

        XCTAssertNotNil(result)

        // Expected height calculation:
        // Total height = 200 (100 + 100)
        // Overlap = 10 (10% of 100)
        // Adjusted height = 200 - 10 = 190
        let expectedHeight: CGFloat = imageSize.height * 2 - (imageSize.height * 0.1)
        XCTAssertEqual(result!.size.height, expectedHeight, accuracy: 0.001)
    }

    func testStitchThreeImages() {
        let imageSize = CGSize(width: 200, height: 100)
        let image1 = TestImageGenerator.createSolidColorImage(size: imageSize, color: .red)
        let image2 = TestImageGenerator.createSolidColorImage(size: imageSize, color: .green)
        let image3 = TestImageGenerator.createSolidColorImage(size: imageSize, color: .blue)

        let result = stitcher.stitch(images: [image1, image2, image3])

        XCTAssertNotNil(result)

        // Expected height:
        // Total height = 300 (100 + 100 + 100)
        // Overlaps = 2 * 10 = 20 (two overlaps between three images)
        // Adjusted height = 300 - 20 = 280
        let expectedHeight: CGFloat = imageSize.height * 3 - (imageSize.height * 0.1 * 2)
        XCTAssertEqual(result!.size.height, expectedHeight, accuracy: 0.001)
    }

    func testStitchMultipleImagesPreservesWidth() {
        let imageSize = CGSize(width: 300, height: 100)
        let images = (0..<5).map { _ in
            TestImageGenerator.createSolidColorImage(size: imageSize, color: .gray)
        }

        let result = stitcher.stitch(images: images)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.size.width, imageSize.width)
    }

    func testStitchWithDifferentWidthsUsesMaxWidth() {
        let image1 = TestImageGenerator.createSolidColorImage(size: CGSize(width: 200, height: 100), color: .red)
        let image2 = TestImageGenerator.createSolidColorImage(size: CGSize(width: 300, height: 100), color: .blue)
        let image3 = TestImageGenerator.createSolidColorImage(size: CGSize(width: 250, height: 100), color: .green)

        let result = stitcher.stitch(images: [image1, image2, image3])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.size.width, 300) // Max width from image2
    }

    // MARK: - Large Image Tests

    func testStitchLargeImages() {
        // Test with larger images that are more representative of actual screenshots
        let imageSize = CGSize(width: 1920, height: 1080)
        let image1 = TestImageGenerator.createGradientImage(
            size: imageSize,
            startColor: .blue,
            endColor: .green
        )
        let image2 = TestImageGenerator.createGradientImage(
            size: imageSize,
            startColor: .green,
            endColor: .red
        )

        let result = stitcher.stitch(images: [image1, image2])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.size.width, imageSize.width)

        let expectedHeight = imageSize.height * 2 - (imageSize.height * 0.1)
        XCTAssertEqual(result!.size.height, expectedHeight, accuracy: 0.001)
    }

    // MARK: - Edge Cases

    func testStitchWithVerySmallImages() {
        let imageSize = CGSize(width: 10, height: 10)
        let image1 = TestImageGenerator.createSolidColorImage(size: imageSize, color: .red)
        let image2 = TestImageGenerator.createSolidColorImage(size: imageSize, color: .blue)

        let result = stitcher.stitch(images: [image1, image2])

        XCTAssertNotNil(result)
        let expectedHeight: CGFloat = 10 + 10 - 1 // 10% of 10 = 1
        XCTAssertEqual(result!.size.height, expectedHeight, accuracy: 0.001)
    }

    func testStitchWithTallNarrowImages() {
        let imageSize = CGSize(width: 50, height: 500)
        let image1 = TestImageGenerator.createSolidColorImage(size: imageSize, color: .red)
        let image2 = TestImageGenerator.createSolidColorImage(size: imageSize, color: .blue)

        let result = stitcher.stitch(images: [image1, image2])

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.size.width, 50)
        let expectedHeight: CGFloat = 500 + 500 - 50 // 10% of 500 = 50
        XCTAssertEqual(result!.size.height, expectedHeight, accuracy: 0.001)
    }

    func testStitchManyImages() {
        let imageSize = CGSize(width: 100, height: 50)
        let imageCount = 10
        let images = (0..<imageCount).map { index -> NSImage in
            let hue = CGFloat(index) / CGFloat(imageCount)
            let color = NSColor(hue: hue, saturation: 0.8, brightness: 0.9, alpha: 1.0)
            return TestImageGenerator.createSolidColorImage(size: imageSize, color: color)
        }

        let result = stitcher.stitch(images: images)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.size.width, imageSize.width)

        // Expected height: totalHeight - (overlap * (count - 1))
        // = (50 * 10) - (5 * 9) = 500 - 45 = 455
        let overlap = imageSize.height * 0.1
        let expectedHeight = (imageSize.height * CGFloat(imageCount)) - (overlap * CGFloat(imageCount - 1))
        XCTAssertEqual(result!.size.height, expectedHeight, accuracy: 0.001)
    }

    // MARK: - Image Content Preservation

    func testStitchedImageHasValidBitmapRepresentation() {
        let imageSize = CGSize(width: 100, height: 100)
        let image1 = TestImageGenerator.createSolidColorImage(size: imageSize, color: .red)
        let image2 = TestImageGenerator.createSolidColorImage(size: imageSize, color: .blue)

        let result = stitcher.stitch(images: [image1, image2])

        XCTAssertNotNil(result)

        // Verify we can get a CGImage from the result (proves valid bitmap)
        let cgImage = result?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        XCTAssertNotNil(cgImage)
    }
}
