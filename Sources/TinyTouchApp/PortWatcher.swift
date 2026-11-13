import Foundation
import IOKit
import IOKit.serial

/// Calls `onChange` when a serial device appears or disappears, using IOKit
/// notifications for the same IOSerialBSDClient class the CLI scans.
@MainActor
final class PortWatcher {
    private let onChange: @MainActor () -> Void
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []

    init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
    }

    /// The notifications hold an unretained pointer to this object.
    isolated deinit {
        for iterator in iterators { IOObjectRelease(iterator) }
        if let port { IONotificationPortDestroy(port) }
    }

    func start() {
        guard port == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.port = port
        IONotificationPortSetDispatchQueue(port, .main)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(
                port, type, IOServiceMatching(kIOSerialBSDServiceValue),
                { context, iterator in
                    PortWatcher.drain(iterator)
                    guard let context else { return }
                    let watcher = Unmanaged<PortWatcher>.fromOpaque(context).takeUnretainedValue()
                    MainActor.assumeIsolated { watcher.onChange() }
                },
                context, &iterator
            )
            guard result == KERN_SUCCESS else { continue }
            // Draining arms the notification; existing devices are read by the initial refresh.
            PortWatcher.drain(iterator)
            iterators.append(iterator)
        }
    }

    private nonisolated static func drain(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            IOObjectRelease(service)
        }
    }
}
