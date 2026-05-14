import Foundation
import AssistantLLM

public struct GCalCalendar: Codable, Equatable {
    public let id: String
    public let summary: String
}

public final class GCalClient: Sendable {

    private let http: HTTPClient
    private let accessTokenProvider: @Sendable () -> String?
    private let baseURL: URL

    public init(http: HTTPClient,
                accessTokenProvider: @escaping @Sendable () -> String?,
                baseURL: URL = URL(string: "https://www.googleapis.com")!) {
        self.http = http
        self.accessTokenProvider = accessTokenProvider
        self.baseURL = baseURL
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func makeRequest(_ method: String, path: String,
                             query: [URLQueryItem] = [], body: Data? = nil) throws -> URLRequest {
        guard let token = accessTokenProvider() else { throw GCalError.unauthorized }
        var comps = URLComponents(url: baseURL.appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw GCalError.network("bad URL") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        return req
    }

    private func send(_ req: URLRequest) async throws -> Data {
        let resp: HTTPResponse
        do { resp = try await http.send(req) } catch { throw GCalError.network("\(error)") }
        switch resp.statusCode {
        case 200..<300: return resp.data
        case 401: throw GCalError.unauthorized
        case 403: throw GCalError.forbidden
        case 404: throw GCalError.notFound
        case 410:
            if let body = String(data: resp.data, encoding: .utf8),
               body.contains("fullSyncRequired") {
                throw GCalError.syncTokenInvalid
            }
            throw GCalError.notFound
        case 429: throw GCalError.rateLimited
        case 500..<600: throw GCalError.server(resp.statusCode)
        default: throw GCalError.network("HTTP \(resp.statusCode)")
        }
    }

    // MARK: - Calendars

    public func listCalendars() async throws -> GCalCalendarList {
        let req = try makeRequest("GET", path: "/calendar/v3/users/me/calendarList")
        let data = try await send(req)
        do { return try Self.decoder.decode(GCalCalendarList.self, from: data) }
        catch { throw GCalError.decoding("\(error)") }
    }

    public func createCalendar(summary: String) async throws -> GCalCalendar {
        let body = try JSONEncoder().encode(GCalCalendarCreateBody(summary: summary))
        let req = try makeRequest("POST", path: "/calendar/v3/calendars", body: body)
        let data = try await send(req)
        do { return try Self.decoder.decode(GCalCalendar.self, from: data) }
        catch { throw GCalError.decoding("\(error)") }
    }

    // MARK: - Events

    public func listEvents(calendarId: String,
                           syncToken: String? = nil,
                           timeMin: Date? = nil,
                           timeMax: Date? = nil,
                           pageToken: String? = nil) async throws -> GCalEventList {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "maxResults", value: "250")
        ]
        if let t = syncToken {
            query.append(URLQueryItem(name: "syncToken", value: t))
        } else {
            if let lo = timeMin {
                query.append(URLQueryItem(name: "timeMin",
                                          value: ISO8601DateFormatter().string(from: lo)))
            }
            if let hi = timeMax {
                query.append(URLQueryItem(name: "timeMax",
                                          value: ISO8601DateFormatter().string(from: hi)))
            }
        }
        if let pt = pageToken {
            query.append(URLQueryItem(name: "pageToken", value: pt))
        }
        let req = try makeRequest("GET",
                                  path: "/calendar/v3/calendars/\(calendarId)/events",
                                  query: query)
        let data = try await send(req)
        do { return try Self.decoder.decode(GCalEventList.self, from: data) }
        catch { throw GCalError.decoding("\(error)") }
    }

    public func insertEvent(calendarId: String,
                            summary: String,
                            start: Date, end: Date,
                            location: String?,
                            description: String?) async throws -> GCalEvent {
        let iso = ISO8601DateFormatter()
        var body: [String: Any] = [
            "summary": summary,
            "start": ["dateTime": iso.string(from: start)],
            "end":   ["dateTime": iso.string(from: end)]
        ]
        if let l = location { body["location"] = l }
        if let d = description { body["description"] = d }
        let data = try JSONSerialization.data(withJSONObject: body)
        let req = try makeRequest("POST",
                                  path: "/calendar/v3/calendars/\(calendarId)/events",
                                  body: data)
        let responseData = try await send(req)
        do { return try Self.decoder.decode(GCalEvent.self, from: responseData) }
        catch { throw GCalError.decoding("\(error)") }
    }

    public func updateEvent(calendarId: String, eventId: String,
                            summary: String?,
                            start: Date?, end: Date?,
                            location: String?,
                            description: String?) async throws -> GCalEvent {
        let iso = ISO8601DateFormatter()
        var body: [String: Any] = [:]
        if let s = summary { body["summary"] = s }
        if let l = location { body["location"] = l }
        if let d = description { body["description"] = d }
        if let st = start { body["start"] = ["dateTime": iso.string(from: st)] }
        if let en = end { body["end"] = ["dateTime": iso.string(from: en)] }
        let data = try JSONSerialization.data(withJSONObject: body)
        let req = try makeRequest("PATCH",
                                  path: "/calendar/v3/calendars/\(calendarId)/events/\(eventId)",
                                  body: data)
        let responseData = try await send(req)
        do { return try Self.decoder.decode(GCalEvent.self, from: responseData) }
        catch { throw GCalError.decoding("\(error)") }
    }

    public func deleteEvent(calendarId: String, eventId: String) async throws {
        let req = try makeRequest("DELETE",
                                  path: "/calendar/v3/calendars/\(calendarId)/events/\(eventId)")
        _ = try await send(req)
    }
}
