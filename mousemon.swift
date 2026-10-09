import Foundation
import IOKit.hid

var timebase = mach_timebase_info_data_t()
mach_timebase_info(&timebase)

func machToSeconds(_ t: UInt64) -> Double {
    Double(t) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
}

final class DevStats {
    var name = "?"
    var lastMach: UInt64 = 0
    var lastT: Double = 0
    var firstT: Double = -1
    var count = 0
    var gaps: [Double] = []
    var dropouts = 0
}

let dropoutThresholdMs = 100.0
var devices: [UnsafeMutableRawPointer: DevStats] = [:]

let runSeconds: Double = CommandLine.arguments.count > 1 ? (Double(CommandLine.arguments[1]) ?? 30) : 30
let vendorID: Int = CommandLine.arguments.count > 2 ? (Int(CommandLine.arguments[2], radix: 16) ?? 0x1532) : 0x1532

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

let matching: [String: Any] = [
    kIOHIDDeviceUsagePageKey: 0x01,
    kIOHIDDeviceUsageKey: 0x02,
    kIOHIDVendorIDKey: vendorID,
]
IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

let valueCallback: IOHIDValueCallback = { _, _, sender, value in
    guard let sender = sender else { return }
    let element = IOHIDValueGetElement(value)
    guard IOHIDElementGetUsagePage(element) == 0x01 else { return }
    let usage = IOHIDElementGetUsage(element)
    guard usage == 0x30 || usage == 0x31 else { return }

    let d: DevStats
    if let existing = devices[sender] {
        d = existing
    } else {
        d = DevStats()
        let device = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
        d.name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "?"
        devices[sender] = d
    }

    let machTS = IOHIDValueGetTimeStamp(value)
    if machTS == d.lastMach { return }
    let t = machToSeconds(machTS)
    if d.firstT < 0 { d.firstT = t }
    if d.lastMach != 0 {
        let gapMs = (t - d.lastT) * 1000
        if gapMs > 0 {
            d.gaps.append(gapMs)
            if gapMs > dropoutThresholdMs {
                d.dropouts += 1
                print(String(format: "DROPOUT  t=%6.2fs  gap=%7.1f ms", t - d.firstT, gapMs))
            }
        }
    }
    d.lastMach = machTS
    d.lastT = t
    d.count += 1
}
IOHIDManagerRegisterInputValueCallback(manager, valueCallback, nil)

IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
guard openResult == kIOReturnSuccess else {
    let msg = "cannot open HID manager (0x\(String(UInt32(bitPattern: openResult), radix: 16))).\n"
        + "Grant Input Monitoring to your terminal: System Settings > Privacy & Security > Input Monitoring, then rerun.\n"
    FileHandle.standardError.write(Data(msg.utf8))
    exit(1)
}

print(String(format: "Move the mouse CONTINUOUSLY for %.0fs (circles are fine). Flagging gaps > %.0f ms...", runSeconds, dropoutThresholdMs))

func summarize() {
    let active = devices.values.filter { $0.gaps.count > 50 }
    guard let d = active.max(by: { $0.count < $1.count }) else {
        print("no movement reports received — was the Razer mouse moving on this Mac?")
        exit(0)
    }
    let g = d.gaps.sorted()
    let duration = d.lastT - d.firstT
    func pct(_ p: Double) -> Double { g[min(g.count - 1, Int(Double(g.count) * p))] }
    print("\n=== summary (\(d.name)) ===")
    print(String(format: "movement reports: %d over %.1fs (avg %.0f Hz while active)", d.count, duration, Double(d.count) / max(duration, 0.001)))
    print(String(format: "gap ms — median: %.2f  p95: %.2f  p99: %.2f  max: %.1f", pct(0.5), pct(0.95), pct(0.99), g.last!))
    let buckets: [(String, Double, Double)] = [
        ("    <2 ms", 0, 2), ("   2-4 ms", 2, 4), ("   4-8 ms", 4, 8),
        ("  8-16 ms", 8, 16), (" 16-50 ms", 16, 50), (" 50-100ms", 50, 100),
        ("100-500ms", 100, 500), ("   >500ms", 500, .infinity),
    ]
    for (label, lo, hi) in buckets {
        let n = g.filter { $0 >= lo && $0 < hi }.count
        if n > 0 { print("\(label): \(n)") }
    }
    print("dropouts (>\(Int(dropoutThresholdMs)) ms): \(d.dropouts)")
    exit(d.dropouts == 0 ? 0 : 2)
}

signal(SIGINT, SIG_IGN)
let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigint.setEventHandler { summarize() }
sigint.resume()

let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + runSeconds, 0, 0, 0) { _ in
    summarize()
}
CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .defaultMode)

CFRunLoopRun()
