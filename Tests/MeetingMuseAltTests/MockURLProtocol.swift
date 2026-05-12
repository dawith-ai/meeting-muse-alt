import Foundation

/// 테스트용 `URLProtocol` — 등록된 핸들러로 모든 URLRequest 응답을 합성.
///
/// 사용법:
///     let config = URLSessionConfiguration.ephemeral
///     config.protocolClasses = [MockURLProtocol.self]
///     let session = URLSession(configuration: config)
///     MockURLProtocol.requestHandler = { request in
///         let resp = HTTPURLResponse(url: request.url!, statusCode: 200, ...)
///         return (resp, body)
///     }
final class MockURLProtocol: URLProtocol {
    /// 테스트가 매 호출마다 응답을 합성. nil 반환 시 noResponse 에러.
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// 일반 JSON 200 응답 헬퍼.
    static func jsonResponse(_ json: String, status: Int = 200, url: URL) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, json.data(using: .utf8) ?? Data())
    }
}
