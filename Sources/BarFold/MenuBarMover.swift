import AppKit
import BarFoldCore

enum MenuBarMoveError: Error {
    case busy, unavailable, interrupted, rejected
}

private let dragEventTag: Int64 = 0x4246_4F4C_44

private final class DragActivity: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true

    var uninterrupted: Bool { lock.withLock { active } }
    func interrupt() { lock.withLock { active = false } }
}

@MainActor
final class MenuBarMover {
    private var cancelDrag: (() -> Void)?

    func cancel() {
        cancelDrag?()
        cancelDrag = nil
    }

    func waitForIdle(isCurrent: () -> Bool) async throws {
        for _ in 0..<20 {
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
            let flags = CGEventSource.flagsState(.combinedSessionState)
            let modifiers: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
            let mouseUp = !CGEventSource.buttonState(.combinedSessionState, button: .left)
                && !CGEventSource.buttonState(.combinedSessionState, button: .right)
            let quiet = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved) > 0.2
            if mouseUp && flags.intersection(modifiers).isEmpty && quiet { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw MenuBarMoveError.busy
    }

    func move(_ move: MenuBarMove, isCurrent: () -> Bool) async throws {
        try await performInput(from: CGPoint(x: move.item.frame.midX, y: move.item.frame.midY),
                               to: move.destination, commandDrag: true, isCurrent: isCurrent)
    }

    func click(at point: CGPoint, isCurrent: () -> Bool) async throws {
        try await performInput(from: point, to: point, commandDrag: false, isCurrent: isCurrent)
    }

    private func performInput(from start: CGPoint, to destination: CGPoint, commandDrag: Bool, isCurrent: () -> Bool) async throws {
        guard let source = CGEventSource(stateID: .privateState), let original = CGEvent(source: nil)?.location else {
            throw MenuBarMoveError.unavailable
        }
        source.userData = dragEventTag
        let activity = DragActivity()
        let eventTypes: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                        .rightMouseDown, .scrollWheel, .keyDown, .flagsChanged]
        let mask = eventTypes.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                         eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
                || event.getIntegerValueField(.eventSourceUserData) != dragEventTag {
                Unmanaged<DragActivity>.fromOpaque(context).takeUnretainedValue().interrupt()
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(activity).toOpaque()),
              let runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        else { throw MenuBarMoveError.unavailable }
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        var pressed = false
        var point = start
        func post(_ type: CGEventType, at point: CGPoint) throws {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
                throw MenuBarMoveError.unavailable
            }
            event.flags = commandDrag && type != .leftMouseUp ? .maskCommand : []
            event.post(tap: .cghidEventTap)
        }
        var finished = false
        func finish() {
            guard !finished else { return }
            finished = true
            if pressed { try? post(.leftMouseUp, at: CGEvent(source: nil)?.location ?? point) }
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            // Preserve actual user input if it interrupted the operation.
            if activity.uninterrupted { CGWarpMouseCursorPosition(original) }
        }
        cancelDrag = { finish() }
        defer { finish(); cancelDrag = nil }
        guard isCurrent() else { throw CancellationError() }
        try post(.leftMouseDown, at: point)
        pressed = true
        if commandDrag {
            try await Task.sleep(for: .milliseconds(100))
            for step in 1...8 {
                guard activity.uninterrupted else { throw MenuBarMoveError.interrupted }
                guard isCurrent() else { throw CancellationError() }
                let progress = CGFloat(step) / 8
                point = CGPoint(x: start.x + (destination.x - start.x) * progress, y: start.y)
                try post(.leftMouseDragged, at: point)
                try await Task.sleep(for: .milliseconds(20))
            }
        } else {
            try await Task.sleep(for: .milliseconds(40))
        }
        guard isCurrent(), activity.uninterrupted else { throw CancellationError() }
        try post(.leftMouseUp, at: point)
        pressed = false
        try await Task.sleep(for: .milliseconds(80))
        guard activity.uninterrupted else { throw MenuBarMoveError.interrupted }
    }
}
