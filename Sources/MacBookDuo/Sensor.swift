import Foundation
import IOKit.hid

final class LidSensor {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
    private var device: IOHIDDevice?
    init() {
        // Apple's lid sensor HID identifier; protocol documented by Sam Gold's LidAngleSensor.
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x05ac, kIOHIDProductIDKey: 0x8104] as CFDictionary)
        guard IOHIDManagerOpen(manager, 0) == kIOReturnSuccess,
              let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return }
        for candidate in devices {
            guard IOHIDDeviceOpen(candidate, 0) == kIOReturnSuccess else { continue }
            device = candidate
            if read() != nil { break }
            IOHIDDeviceClose(candidate, 0)
            device = nil
        }
    }
    func read() -> Double? {
        guard let device else { return nil }
        var bytes = [UInt8](repeating: 0, count: 8)
        var size = bytes.count
        guard IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &bytes, &size) == kIOReturnSuccess,
              size >= 3 else { return nil }
        let angle = Double(UInt16(bytes[1]) | UInt16(bytes[2]) << 8)
        return (0...180).contains(angle) ? angle : nil
    }
    func close() {
        if let device { IOHIDDeviceClose(device, 0) }
        device = nil
        IOHIDManagerClose(manager, 0)
    }
}
