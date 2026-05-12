import Testing
import Foundation
@testable import MeetingMuseAlt

@Test func extractsFromActionItemsSection() {
    let md = """
    # 회의록

    ## 핵심 요약
    - 분기 매출 검토

    ## 액션 아이템
    - PRD 작성 (담당: 홍길동, 기한: 2026-05-20, 우선순위: 높음)
    - 마케팅 보고서 갱신 (담당: 김유나, 기한: 다음 주 금요일)
    - 디자인 리뷰 일정 잡기

    ## 결정 사항
    - 리눅스 사용 보류
    """
    let items = ActionItemExtractor.extract(from: md)
    #expect(items.count == 3)
    #expect(items[0].task == "PRD 작성")
    #expect(items[0].assignee == "홍길동")
    #expect(items[0].dueText == "2026-05-20")
    #expect(items[0].priority == .high)
    #expect(items[1].assignee == "김유나")
    #expect(items[1].dueText == "다음 주 금요일")
    #expect(items[2].assignee == nil)
    #expect(items[2].priority == nil)
}

@Test func extractsEnglishActionItemsSection() {
    let md = """
    ## Action Items
    - Ship feature flag rollout (owner: Alice, due: 2026-06-01, priority: high)
    - Investigate flaky test (assignee: Bob)
    """
    let items = ActionItemExtractor.extract(from: md)
    #expect(items.count == 2)
    #expect(items[0].priority == .high)
    #expect(items[0].assignee == "Alice")
    #expect(items[1].assignee == "Bob")
}

@Test func fallsBackToAnyBulletWhenNoActionSection() {
    let md = """
    - 첫째 작업
    - 둘째 작업 (담당: A)
    """
    let items = ActionItemExtractor.extract(from: md)
    #expect(items.count == 2)
    #expect(items[1].assignee == "A")
}

@Test func priorityKeywordsMapToEnumValues() {
    let md = """
    ## 액션 아이템
    - 고우선 (priority: 높음)
    - 중간 (priority: 보통)
    - 낮음건 (priority: low)
    """
    let items = ActionItemExtractor.extract(from: md)
    #expect(items.count == 3)
    #expect(items[0].priority == .high)
    #expect(items[1].priority == .medium)
    #expect(items[2].priority == .low)
}

@Test func bulletMarkersSupported() {
    let md = """
    ## 액션 아이템
    - dash
    * asterisk
    • bullet
    1. numbered
    """
    let items = ActionItemExtractor.extract(from: md)
    #expect(items.count == 4)
    #expect(items.map(\.task) == ["dash", "asterisk", "bullet", "numbered"])
}

@Test func emptyMarkdownReturnsEmpty() {
    #expect(ActionItemExtractor.extract(from: "").isEmpty)
    #expect(ActionItemExtractor.extract(from: "## 핵심 요약\n- 그냥 요약").isEmpty == false) // 핵심 요약은 fallback bullet 캡처
}
