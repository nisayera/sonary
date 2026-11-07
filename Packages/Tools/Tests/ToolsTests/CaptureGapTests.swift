import CoreGraphics
import Foundation
import Testing
@testable import Tools

struct CaptureSelectorModeTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func theDigitsPickTheModes() {
        #expect(CaptureMode(keyCode: 18) == .screenshot)
        #expect(CaptureMode(keyCode: 21) == .recording)
        #expect(CaptureMode(keyCode: 0) == nil)
    }

    @Test func aClickTakesTheWholeScreen() {
        let rect = captureRegion(start: CGPoint(x: 100, y: 100), end: CGPoint(x: 101, y: 102), screen: screen,
                                 mode: .screenshot)
        #expect(rect == screen)
    }

    @Test func aDragTakesItsRectangleAndTinyOnesNothing() {
        #expect(captureRegion(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 110, y: 60), screen: screen, mode: .text)
            == CGRect(x: 10, y: 10, width: 100, height: 50))
        #expect(captureRegion(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 14, y: 10.5), screen: screen,
                              mode: .screenshot) == nil)
    }

    @Test func theColourModePicksThePoint() {
        let rect = captureRegion(start: CGPoint(x: 5, y: 5), end: CGPoint(x: 40.7, y: 80.2), screen: screen, mode: .color)
        #expect(rect == CGRect(x: 40, y: 80, width: 1, height: 1))
    }
}

struct EditorExportTests {
    private let size = CGSize(width: 800, height: 600)

    @Test func noCropOrATinyOneKeepsTheWholeShot() {
        #expect(exportCropArea(nil, imageSize: size) == CGRect(origin: .zero, size: size))
        #expect(exportCropArea(CGRect(x: 10, y: 10, width: 4, height: 4), imageSize: size)
            == CGRect(origin: .zero, size: size))
    }

    @Test func aCropStaysInsideThePictureOnWholePoints() {
        let area = exportCropArea(CGRect(x: 700.4, y: -20, width: 200, height: 100.2), imageSize: size)
        #expect(area == CGRect(x: 700, y: 0, width: 100, height: 81))
    }

    @Test func theWatermarkSitsBottomRight() {
        let origin = watermarkOrigin(textSize: CGSize(width: 100, height: 20),
                                     in: CGRect(x: 48, y: 48, width: 800, height: 600), padding: 10)
        #expect(origin == CGPoint(x: 48 + 800 - 100 - 10, y: 58))
    }
}

struct RecordingRegionTests {
    @Test func regionsAreMeasuredFromTheTopOfTheirDisplay() {
        // A second display to the right of a 1440 × 900 one, 1920 × 1080 tall.
        let frame = CGRect(x: 1440, y: -180, width: 1920, height: 1080)
        let rect = recordingSourceRect(CGRect(x: 1540, y: 700, width: 400, height: 100), screenFrame: frame)
        #expect(rect == CGRect(x: 100, y: 100, width: 400, height: 100))
    }

    @Test func theVideoSizeIsInEvenPixels() {
        let region = RecordingRegion(displayID: 1, rect: CGRect(x: 0, y: 0, width: 333, height: 201), scale: 2)
        #expect(region.pixelSize.width == 666)
        #expect(region.pixelSize.height == 402)
        let odd = RecordingRegion(displayID: 1, rect: CGRect(x: 0, y: 0, width: 333, height: 201), scale: 1)
        #expect(odd.pixelSize.width % 2 == 0)
        #expect(odd.pixelSize.height % 2 == 0)
    }
}

struct TrimTests {
    @Test func theRangeStaysInsideTheClip() {
        #expect(trimRange(start: -3, end: 0, duration: 20) == 0...20)
        #expect(trimRange(start: 5, end: 30, duration: 20) == 5...20)
    }

    @Test func nothingLeftMeansNoRange() {
        #expect(trimRange(start: 10, end: 10, duration: 20) == nil)
        #expect(trimRange(start: 25, end: 0, duration: 20) == nil)
    }
}
