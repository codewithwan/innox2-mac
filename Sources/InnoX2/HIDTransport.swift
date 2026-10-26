import Foundation
import IOKit.hid

/// Finds the mouse's vendor config interface (usage page 0xFFFF, usage 2) and exchanges
/// 64-byte feature reports with it. Report ID 0 = no report ID on this interface.
final class HIDTransport {
    static let vendorID = 0x3151

    private let manager: IOHIDManager
    private(set) var device: IOHIDDevice?
    var onChange: (() -> Void)?

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDPrimaryUsagePageKey: 0xFFFF,
            kIOHIDPrimaryUsageKey: 2,
        ] as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, dev in
            let me = Unmanaged<HIDTransport>.fromOpaque(ctx!).takeUnretainedValue()
            IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
            me.device = dev
            me.onChange?()
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, dev in
            let me = Unmanaged<HIDTransport>.fromOpaque(ctx!).takeUnretainedValue()
            if me.device == dev { me.device = nil }
            me.onChange?()
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    var productID: Int? {
        device.flatMap { IOHIDDeviceGetProperty($0, kIOHIDProductIDKey as CFString) as? Int }
    }

    var productName: String? {
        device.flatMap { IOHIDDeviceGetProperty($0, kIOHIDProductKey as CFString) as? String }
    }

    enum Err: Error { case noDevice, io(IOReturn) }

    func setFeature(_ bytes: [UInt8]) throws {
        guard let d = device else { throw Err.noDevice }
        var buf = bytes + [UInt8](repeating: 0, count: max(0, 64 - bytes.count))
        let r = IOHIDDeviceSetReport(d, kIOHIDReportTypeFeature, 0, &buf, 64)
        if r != kIOReturnSuccess { throw Err.io(r) }
    }

    func getFeature() throws -> [UInt8] {
        guard let d = device else { throw Err.noDevice }
        var buf = [UInt8](repeating: 0, count: 64)
        var len = CFIndex(64)
        let r = IOHIDDeviceGetReport(d, kIOHIDReportTypeFeature, 0, &buf, &len)
        if r != kIOReturnSuccess { throw Err.io(r) }
        return buf
    }
}
