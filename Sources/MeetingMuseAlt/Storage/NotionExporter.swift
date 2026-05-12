import Foundation

/// Notion 페이지 익스포트 인터페이스.
///
/// `meeting-muse` 웹앱의 `IntegrationPanel` / `/api/notion` 과 동등한 동작을
/// 목표로 한다. Notion API 키 + database/page ID 가 필요하다.
public protocol NotionExporter: Sendable {
    /// 회의록을 Notion 페이지로 export.
    /// 부모 `databaseID` 또는 `parentPageID` 중 하나는 필수.
    func exportMeeting(
        title: String,
        body: MeetingExportData,
        databaseID: String?,
        parentPageID: String?
    ) async throws -> URL
}

public enum NotionExportError: LocalizedError {
    case missingCredentials
    case missingParent
    case network(String)
    case http(status: Int, body: String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Notion Integration 토큰이 필요합니다 (notion.so/my-integrations)."
        case .missingParent:
            return "databaseID 또는 parentPageID 중 하나는 반드시 제공해야 합니다."
        case .network(let m): return "네트워크 오류: \(m)"
        case .http(let s, let b): return "HTTP \(s): \(b.prefix(200))"
        case .decoding(let m): return "응답 디코딩 실패: \(m)"
        }
    }
}

/// 공식 Notion API 사용.
///
/// API 문서: https://developers.notion.com/reference/post-page
public struct NotionAPIExporter: NotionExporter {
    public let integrationToken: String
    public let apiVersion: String
    public let endpoint: URL
    public let session: URLSession

    public init(
        integrationToken: String,
        apiVersion: String = "2022-06-28",
        endpoint: URL = URL(string: "https://api.notion.com/v1/pages")!,
        session: URLSession = .shared
    ) {
        self.integrationToken = integrationToken
        self.apiVersion = apiVersion
        self.endpoint = endpoint
        self.session = session
    }

    public func exportMeeting(
        title: String,
        body: MeetingExportData,
        databaseID: String?,
        parentPageID: String?
    ) async throws -> URL {
        if integrationToken.isEmpty { throw NotionExportError.missingCredentials }
        if databaseID == nil && parentPageID == nil { throw NotionExportError.missingParent }

        let payload = Self.buildPayload(
            title: title,
            body: body,
            databaseID: databaseID,
            parentPageID: parentPageID
        )
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(integrationToken)", forHTTPHeaderField: "Authorization")
        req.setValue(apiVersion, forHTTPHeaderField: "Notion-Version")
        req.httpBody = data

        let (respData, response): (Data, URLResponse)
        do {
            (respData, response) = try await session.data(for: req)
        } catch {
            throw NotionExportError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw NotionExportError.network("응답이 HTTPURLResponse가 아닙니다.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let s = String(data: respData, encoding: .utf8) ?? ""
            throw NotionExportError.http(status: http.statusCode, body: s)
        }

        guard let json = try? JSONSerialization.jsonObject(with: respData) as? [String: Any],
              let urlStr = json["url"] as? String,
              let url = URL(string: urlStr)
        else {
            throw NotionExportError.decoding("응답에서 page url을 찾을 수 없습니다.")
        }
        return url
    }

    // MARK: - Internal helpers (test 가능)

    static func buildPayload(
        title: String,
        body: MeetingExportData,
        databaseID: String?,
        parentPageID: String?
    ) -> [String: Any] {
        var parent: [String: Any] = [:]
        if let db = databaseID {
            parent["database_id"] = db
        } else if let p = parentPageID {
            parent["page_id"] = p
        }

        let titleProp: [String: Any] = [
            "title": [
                ["type": "text", "text": ["content": title]]
            ]
        ]
        var properties: [String: Any] = ["Name": titleProp, "title": titleProp]
        if databaseID == nil {
            // page 부모일 때는 properties 가 title 단일이어야 함
            properties = ["title": titleProp]
        }

        var children: [[String: Any]] = []

        // 메타 헤더
        let dateString: String = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f.string(from: body.createdAt)
        }()
        children.append(makeParagraph(
            "회의록 · \(dateString) · ⏱ \(Int(body.durationSeconds))초 · \(body.language.uppercased())"
        ))

        if let summary = body.summary, !summary.isEmpty {
            children.append(makeHeading("요약", level: 2))
            for line in summary.split(separator: "\n") {
                children.append(makeParagraph(String(line)))
            }
        }

        if !body.utterances.isEmpty {
            children.append(makeHeading("전사", level: 2))
            for u in body.utterances.prefix(100) { // Notion API 한 페이지 children 100 제한
                let text = "[\(u.timestampLabel)] \(u.speaker.label): \(u.text)"
                children.append(makeParagraph(text))
            }
            if body.utterances.count > 100 {
                children.append(makeParagraph("… 총 \(body.utterances.count) 발화 중 100건만 표시 (Notion API children 제한)."))
            }
        }

        return [
            "parent": parent,
            "properties": properties,
            "children": children
        ]
    }

    private static func makeParagraph(_ text: String) -> [String: Any] {
        [
            "object": "block",
            "type": "paragraph",
            "paragraph": [
                "rich_text": [
                    ["type": "text", "text": ["content": text]]
                ]
            ]
        ]
    }

    private static func makeHeading(_ text: String, level: Int) -> [String: Any] {
        let key = level == 1 ? "heading_1" : (level == 2 ? "heading_2" : "heading_3")
        return [
            "object": "block",
            "type": key,
            key: [
                "rich_text": [
                    ["type": "text", "text": ["content": text]]
                ]
            ]
        ]
    }
}
