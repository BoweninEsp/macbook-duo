import AppKit
import ScreenCaptureKit

final class DesktopCapture: NSObject, @preconcurrency SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    var onFrame: ((CVPixelBuffer) -> Void)?
    var onFailure: ((String) -> Void)?
    func start(displayID: CGDirectDisplayID, excluding windowID: Int) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw AppFailure.missingDisplay
        }
        let excluded = content.windows.filter { $0.windowID == CGWindowID(windowID) }
        guard !excluded.isEmpty else {
            throw AppFailure.exclusionFailed
        }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let config = SCStreamConfiguration()
        config.width = display.width * 2
        config.height = display.height * 2
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 3
        config.showsCursor = false
        config.capturesAudio = false
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        self.stream = stream
        try await stream.startCapture()
    }
    func stop() async {
        let old = stream
        stream = nil
        try? await old?.stopCapture()
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
              let buffer = sampleBuffer.imageBuffer else { return }
        onFrame?(buffer)
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.onFailure?(message) }
    }
}
