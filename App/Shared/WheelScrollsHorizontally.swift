import AppKit
import SwiftUI

extension View {
    func wheelScrollsHorizontally() -> some View {
        modifier(WheelScrollsHorizontally())
    }
}

private struct WheelScrollsHorizontally: ViewModifier {
    @State private var redirector = WheelRedirector()

    func body(content: Content) -> some View {
        content
            .onHover { redirector.isActive = $0 }
            .onAppear { redirector.start() }
            .onDisappear { redirector.stop() }
    }
}

private final class WheelRedirector {
    var isActive = false
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.redirect(event) ?? event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isActive = false
    }

    private func redirect(_ event: NSEvent) -> NSEvent {
        // Trackpads already scroll sideways; only plain mouse wheels need the vertical axis turned.
        guard isActive, !event.hasPreciseScrollingDeltas, event.scrollingDeltaX == 0,
              let swapped = event.cgEvent?.copy() else { return event }
        for (vertical, horizontal) in [(CGEventField.scrollWheelEventDeltaAxis1, CGEventField.scrollWheelEventDeltaAxis2),
                                       (.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2)] {
            swapped.setIntegerValueField(horizontal, value: swapped.getIntegerValueField(vertical))
            swapped.setIntegerValueField(vertical, value: 0)
        }
        swapped.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: swapped.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1))
        swapped.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
        return NSEvent(cgEvent: swapped) ?? event
    }
}
