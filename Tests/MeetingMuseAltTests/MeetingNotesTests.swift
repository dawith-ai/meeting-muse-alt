import Testing
import Foundation
@testable import MeetingMuseAlt

@MainActor
@Test func addNoteInsertsAtTop() {
    let store = MeetingNotesStore(inMemory: true)
    store.add("첫 메모")
    store.add("두 번째")
    #expect(store.notes.count == 2)
    #expect(store.notes[0].text == "두 번째")
    #expect(store.notes[1].text == "첫 메모")
}

@MainActor
@Test func updateNoteChangesTextAndTimestamp() async throws {
    let store = MeetingNotesStore(inMemory: true)
    store.add("original")
    let id = store.notes[0].id
    let originalUpdatedAt = store.notes[0].updatedAt
    try await Task.sleep(nanoseconds: 10_000_000) // 10ms
    store.update(id: id, text: "modified")
    #expect(store.notes[0].text == "modified")
    #expect(store.notes[0].updatedAt > originalUpdatedAt)
}

@MainActor
@Test func removeNoteDeletesMatch() {
    let store = MeetingNotesStore(inMemory: true)
    store.add("a")
    store.add("b")
    let id = store.notes[0].id
    store.remove(id: id)
    #expect(store.notes.count == 1)
    #expect(store.notes[0].text == "a")
}

@MainActor
@Test func notesForMeetingFiltersByID() {
    let store = MeetingNotesStore(inMemory: true)
    let meetingID = UUID()
    store.add("free")
    store.add("tied", meetingID: meetingID)
    store.add("free 2")

    let tied = store.notes(forMeeting: meetingID)
    let free = store.notes(forMeeting: nil)
    #expect(tied.count == 1)
    #expect(tied[0].text == "tied")
    #expect(free.count == 2)
}

@MainActor
@Test func clearEmptiesStore() {
    let store = MeetingNotesStore(inMemory: true)
    store.add("a"); store.add("b")
    store.clear()
    #expect(store.notes.isEmpty)
}
