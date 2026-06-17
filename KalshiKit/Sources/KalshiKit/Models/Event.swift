import Foundation

/// A Kalshi event: a single occurrence within a series, grouping one or more
/// markets (e.g. one day's temperature event grouping each strike's market).
public struct Event: Codable, Sendable, Hashable, Identifiable {
    public var eventTicker: String
    public var seriesTicker: String?
    public var title: String
    public var subTitle: String?
    public var mutuallyExclusive: Bool?
    /// Present only when the request asks for nested markets.
    public var markets: [Market]?

    /// Natural identity is the event ticker.
    public var id: String { eventTicker }

    public init(
        eventTicker: String,
        seriesTicker: String? = nil,
        title: String,
        subTitle: String? = nil,
        mutuallyExclusive: Bool? = nil,
        markets: [Market]? = nil
    ) {
        self.eventTicker = eventTicker
        self.seriesTicker = seriesTicker
        self.title = title
        self.subTitle = subTitle
        self.mutuallyExclusive = mutuallyExclusive
        self.markets = markets
    }
}

/// Paged list of events (`GET /events`).
public struct EventListResponse: Codable, Sendable, Hashable, CursorPaged {
    public var events: [Event]
    public var cursor: String?

    /// `CursorPaged` items projection.
    public var items: [Event] { events }

    public init(events: [Event], cursor: String? = nil) {
        self.events = events
        self.cursor = cursor
    }
}

/// Single-event endpoint envelope (`GET /events/{event_ticker}`).
public struct EventResponse: Codable, Sendable, Hashable {
    public var event: Event
    /// Sometimes returned alongside the event when markets are requested.
    public var markets: [Market]?

    public init(event: Event, markets: [Market]? = nil) {
        self.event = event
        self.markets = markets
    }
}
