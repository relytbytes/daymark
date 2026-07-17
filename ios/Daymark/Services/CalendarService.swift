//
//  CalendarService.swift
//  Daymark
//
//  Native calendar via EventKit (sees Google/iCloud/Exchange accounts already
//  on the phone — no OAuth needed), plus MapKit travel estimates.
//

import Foundation
import EventKit
import MapKit
import CoreLocation

@MainActor
final class CalendarService {
    private let store = EKEventStore()
    private(set) var accessGranted: Bool?

    /// The store, for the system event editor.
    var eventStore: EKEventStore { store }

    private static let meetingHosts = [
        "zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "whereby.com", "meet.jit.si",
    ]

    func ensureAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .fullAccess:
            accessGranted = true
        case .notDetermined:
            accessGranted = (try? await store.requestFullAccessToEvents()) ?? false
        default:
            accessGranted = false
        }
        return accessGranted ?? false
    }

    func events(from: Date, to: Date) -> [CalendarEventLite] {
        guard accessGranted == true else { return [] }
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
        let events = store.events(matching: predicate)
        return events
            .filter { !$0.isAllDay || Calendar.current.isDate($0.startDate, inSameDayAs: from) }
            .sorted { $0.startDate < $1.startDate }
            .map { Self.lite(from: $0) }
    }

    private static func lite(from event: EKEvent) -> CalendarEventLite {
        let attendees = (event.attendees ?? [])
            .filter { !$0.isCurrentUser && $0.participantType == .person }
            .compactMap { $0.name?.nilIfEmpty }

        let haystack = [
            event.url?.absoluteString,
            event.location,
            event.notes,
        ].compactMap { $0 }.joined(separator: "\n")

        let links = haystack.extractURLs()
        let join = links.first { url in
            guard let host = url.host?.lowercased() else { return false }
            return meetingHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
        }
        let extra = links.filter { $0 != join }.prefix(3)

        return CalendarEventLite(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title?.nilIfEmpty ?? "Untitled",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            location: event.location?.nilIfEmpty,
            notes: event.notes?.nilIfEmpty,
            attendees: Array(attendees.prefix(8)),
            joinURL: join,
            links: Array(extra)
        )
    }
}

// MARK: - Travel time to next meeting

@MainActor
final class TravelService {
    private let locationManager = CLLocationManager()
    private var cache: [String: Int] = [:]

    var authorized: Bool {
        let status = locationManager.authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    func requestPermission() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    /// Driving minutes to the event's location, or nil when unknowable.
    func minutes(to event: CalendarEventLite) async -> Int? {
        guard authorized,
              let address = event.location,
              !address.lowercased().contains("http"),
              address.count > 5
        else { return nil }
        if let cached = cache[event.id] { return cached }

        do {
            let placemarks = try await CLGeocoder().geocodeAddressString(address)
            guard let location = placemarks.first?.location else { return nil }
            let request = MKDirections.Request()
            request.source = MKMapItem.forCurrentLocation()
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
            request.transportType = .automobile
            let response = try await MKDirections(request: request).calculateETA()
            let mins = Int((response.expectedTravelTime / 60).rounded())
            cache[event.id] = mins
            return mins
        } catch {
            return nil
        }
    }
}
