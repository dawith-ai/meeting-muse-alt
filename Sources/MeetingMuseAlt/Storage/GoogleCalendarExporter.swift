import Foundation

/// Google Calendar 이벤트 생성 인터페이스.
///
/// `meeting-muse` 웹앱의 `IntegrationPanel` (Google Calendar 부분) 과 동등한
/// 동작을 목표로 한다. OAuth 2.0 access token 이 필요하며, 토큰 발급은 호출자가
/// 한다 (이 모듈은 토큰 + calendarID 받아서 이벤트 POST 만).
public protocol GoogleCalendarExporter: Sendable {
    /// 회의록을 Google Calendar 이벤트로 생성.
    /// - Parameters:
    ///   - summary: 이벤트 제목
    ///   - description: 이벤트 본문 (보통 회의 요약 마크다운)
    ///   - startDate: 이벤트 시작 시각
    ///   - durationSeconds: 이벤트 길이
    ///   - calendarID: Calendar ID (기본 "primary")
    ///   - accessToken: OAuth 2.0 access token
    /// - Returns: 생성된 이벤트의 htmlLink URL
    func createEvent(
        summary: String,
        description: String,
        startDate: Date,
        durationSeconds: Double,
        calendarID: String,
        accessToken: String
    ) async throws -> URL
}

public enum GoogleCalendarError: LocalizedError {
    case missingToken
    case invalidCalendarID
    case network(String)
    case http(status: Int, body: String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Google OAuth access token이 필요합니다."
        case .invalidCalendarID:
            return "Calendar ID가 비어 있습니다."
        case .network(let m): return "네트워크 오류: \(m)"
        case .http(let s, let b): return "HTTP \(s): \(b.prefix(200))"
        case .decoding(let m): return "응답 디코딩 실패: \(m)"
        }
    }
}

/// Google Calendar API v3 (https://www.googleapis.com/calendar/v3) 기반 구현.
public struct GoogleCalendarAPIExporter: GoogleCalendarExporter {
    public let endpointBase: URL
    public let session: URLSession

    public init(
        endpointBase: URL = URL(string: "https://www.googleapis.com/calendar/v3")!,
        session: URLSession = .shared
    ) {
        self.endpointBase = endpointBase
        self.session = session
    }

    public func createEvent(
        summary: String,
        description: String,
        startDate: Date,
        durationSeconds: Double,
        calendarID: String = "primary",
        accessToken: String
    ) async throws -> URL {
        if accessToken.isEmpty { throw GoogleCalendarError.missingToken }
        if calendarID.isEmpty { throw GoogleCalendarError.invalidCalendarID }

        let path = "/calendars/\(calendarID)/events"
        let url = endpointBase.appendingPathComponent(path)

        let endDate = startDate.addingTimeInterval(durationSeconds)
        let payload = Self.buildPayload(
            summary: summary,
            description: description,
            startDate: startDate,
            endDate: endDate
        )
        let body = try JSONSerialization.data(withJSONObject: payload, options: [])

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = body

        let (respData, response): (Data, URLResponse)
        do {
            (respData, response) = try await session.data(for: req)
        } catch {
            throw GoogleCalendarError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw GoogleCalendarError.network("응답이 HTTPURLResponse가 아닙니다.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let s = String(data: respData, encoding: .utf8) ?? ""
            throw GoogleCalendarError.http(status: http.statusCode, body: s)
        }
        guard let json = try? JSONSerialization.jsonObject(with: respData) as? [String: Any],
              let link = (json["htmlLink"] as? String) ?? (json["id"] as? String).map({ "https://calendar.google.com/event?eid=\($0)" }),
              let linkURL = URL(string: link)
        else {
            throw GoogleCalendarError.decoding("응답에서 htmlLink를 찾을 수 없습니다.")
        }
        return linkURL
    }

    // MARK: - Internal helpers

    static func buildPayload(
        summary: String,
        description: String,
        startDate: Date,
        endDate: Date
    ) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let tz = TimeZone.current.identifier
        return [
            "summary": summary,
            "description": description,
            "start": [
                "dateTime": iso.string(from: startDate),
                "timeZone": tz,
            ],
            "end": [
                "dateTime": iso.string(from: endDate),
                "timeZone": tz,
            ],
        ]
    }
}
