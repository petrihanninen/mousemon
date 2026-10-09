# mousemon

Measures wireless mouse radio-link health on macOS by timestamping HID movement reports (kernel-level, via IOHIDManager) and flagging inter-report gaps. Built to diagnose 2.4 GHz dongle dropouts caused by USB 3.x RF interference.

## Usage

```sh
./mousemon [seconds] [vendorID-hex]
```

Defaults: 30 seconds, vendor `1532` (Razer). Move the mouse continuously during the run — gaps over 100 ms print live as `DROPOUT`, and a summary with a gap histogram prints at the end. Exit code 0 = no dropouts, 2 = dropouts detected.

Requires Input Monitoring permission for your terminal (System Settings → Privacy & Security → Input Monitoring).

## Build

```sh
swiftc -O -swift-version 5 mousemon.swift -o mousemon
```

## Reference results (Viper V2 Pro, 2026-08-26)

- Dongle in ATEN US234 under desk: 7 dropouts >100 ms per 20 s, worst 717 ms
- Dongle on extension cable on desk: 0 dropouts, max gap 13 ms, clean 1000 Hz
