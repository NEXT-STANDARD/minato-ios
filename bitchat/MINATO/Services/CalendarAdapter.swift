import EventKit
import Foundation

// MARK: - CalendarAdapter Protocol

protocol CalendarAdapterProtocol {
    /// Request calendar access. Returns true if granted.
    func requestAccess() async -> Bool

    /// Check if the given time range has no conflicting events.
    /// NOTE: Returns true (no conflict) if access not yet granted — use checkAvailabilityAsync for accurate results.
    func checkAvailability(start: Date, end: Date) -> Bool

    /// Async variant that ensures access is requested before checking.
    /// Returns (hasAccess: Bool, isAvailable: Bool).
    func checkAvailabilityAsync(start: Date, end: Date) async -> (hasAccess: Bool, isAvailable: Bool)

    /// Create a calendar event from a ProposedEvent. Returns the EKEvent identifier.
    func createEvent(from event: ProposedEvent) throws -> String

    /// Delete a previously created event by identifier.
    func deleteEvent(identifier: String) throws

    /// Get busy time slots for the next N days (for AI schedule proposals).
    func busySlots(forNextDays days: Int) -> [(start: Date, end: Date)]
}

// MARK: - CalendarAdapter Errors

enum CalendarAdapterError: Error {
    case accessDenied
    case invalidDateFormat
    case saveFailed(String)
    case deleteFailed(String)
    case eventNotFound
}

// MARK: - CalendarAdapter

final class CalendarAdapter: CalendarAdapterProtocol {
    private let store = EKEventStore()
    private var accessGranted: Bool?

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Access

    func requestAccess() async -> Bool {
        if let granted = accessGranted { return granted }

        let granted: Bool
        if #available(iOS 17.0, macOS 14.0, *) {
            granted = (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            granted = await withCheckedContinuation { continuation in
                store.requestAccess(to: .event) { result, _ in
                    continuation.resume(returning: result)
                }
            }
        }
        accessGranted = granted
        return granted
    }

    // MARK: - Availability

    func checkAvailability(start: Date, end: Date) -> Bool {
        guard accessGranted == true else { return true }  // Assume available if no access
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
        return events.isEmpty
    }

    func checkAvailabilityAsync(start: Date, end: Date) async -> (hasAccess: Bool, isAvailable: Bool) {
        let granted = await requestAccess()
        guard granted else { return (false, true) }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
        return (true, events.isEmpty)
    }

    // MARK: - Create Event

    func createEvent(from proposedEvent: ProposedEvent) throws -> String {
        guard accessGranted == true else { throw CalendarAdapterError.accessDenied }

        guard let startDate = Self.isoFormatter.date(from: proposedEvent.start),
              let endDate = Self.isoFormatter.date(from: proposedEvent.end) else {
            throw CalendarAdapterError.invalidDateFormat
        }

        let ekEvent = EKEvent(eventStore: store)
        ekEvent.title = proposedEvent.title
        ekEvent.startDate = startDate
        ekEvent.endDate = endDate
        ekEvent.location = proposedEvent.location
        ekEvent.calendar = store.defaultCalendarForNewEvents

        do {
            try store.save(ekEvent, span: .thisEvent)
            return ekEvent.eventIdentifier
        } catch {
            throw CalendarAdapterError.saveFailed(error.localizedDescription)
        }
    }

    // MARK: - Delete Event

    func deleteEvent(identifier: String) throws {
        guard accessGranted == true else { throw CalendarAdapterError.accessDenied }

        guard let event = store.event(withIdentifier: identifier) else {
            throw CalendarAdapterError.eventNotFound
        }

        do {
            try store.remove(event, span: .thisEvent)
        } catch {
            throw CalendarAdapterError.deleteFailed(error.localizedDescription)
        }
    }

    // MARK: - Busy Slots

    func busySlots(forNextDays days: Int) -> [(start: Date, end: Date)] {
        guard accessGranted == true else { return [] }

        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: predicate)

        return events.map { ($0.startDate, $0.endDate) }
    }
}
