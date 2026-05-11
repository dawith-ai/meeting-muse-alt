import Testing
import Foundation
@testable import MeetingMuseAlt

/// `WhisperKitEngine` 의 모델 다운로드/추론은 인터넷 + 디스크 + 모델 자산이
/// 필요하므로 단위 테스트에서는 변환 헬퍼만 검증한다. 통합 검증은
/// macOS 디바이스 + 모델 캐시가 준비된 환경에서 수동으로 수행.

@Test func convertEmptyResultsReturnsEmpty() {
    let utts = WhisperKitEngine.convertToUtterances([])
    #expect(utts.isEmpty)
}

@Test func engineInstantiableWithDefaultModel() {
    let engine = WhisperKitEngine()
    #expect(engine.modelName == "tiny")
}

@Test func engineInstantiableWithCustomModel() {
    let engine = WhisperKitEngine(modelName: "base.en")
    #expect(engine.modelName == "base.en")
}
