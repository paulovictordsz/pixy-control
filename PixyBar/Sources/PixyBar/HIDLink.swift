import Foundation
import IOKit.hid

/// Conexão HID crua com a EMEET PIXY via IOHIDManager (sem dependências externas).
/// Reports de 32 bytes, report ID 0x09, sempre no run loop principal.
final class HIDLink {
    static let vendorID = 0x328F
    static let productID = 0x00C0
    static let usagePage = 0x83
    static let reportSize = 32

    private var manager: IOHIDManager
    private var device: IOHIDDevice?
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)

    var onReport: (([UInt8]) -> Void)?
    var onConnection: ((Bool) -> Void)?
    private(set) var isConnected = false
    private(set) var serialNumber: String = ""

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: HIDLink.vendorID,
            kIOHIDProductIDKey as String: HIDLink.productID,
            kIOHIDPrimaryUsagePageKey as String: HIDLink.usagePage,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            guard let ctx else { return }
            Unmanaged<HIDLink>.fromOpaque(ctx).takeUnretainedValue().attach(device)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, device in
            guard let ctx else { return }
            Unmanaged<HIDLink>.fromOpaque(ctx).takeUnretainedValue().detach(device)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func attach(_ dev: IOHIDDevice) {
        guard device == nil else { return }
        device = dev
        if let sn = IOHIDDeviceGetProperty(dev, kIOHIDSerialNumberKey as CFString) as? String { serialNumber = sn }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(dev, inputBuffer, 64, { ctx, _, _, _, _, report, length in
            guard let ctx else { return }
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            Unmanaged<HIDLink>.fromOpaque(ctx).takeUnretainedValue().onReport?(bytes)
        }, ctx)
        isConnected = true
        onConnection?(true)
    }

    private func detach(_ dev: IOHIDDevice) {
        guard device == dev else { return }
        device = nil
        isConnected = false
        onConnection?(false)
    }

    /// Envia um report completo de 32 bytes (byte 0 = report ID 0x09), igual ao hid_write do hidapi.
    func write(_ report: [UInt8]) -> Bool {
        guard let device, report.count == HIDLink.reportSize else { return false }
        return report.withUnsafeBufferPointer { buf in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(report[0]), buf.baseAddress!, CFIndex(report.count)) == kIOReturnSuccess
        }
    }
}
