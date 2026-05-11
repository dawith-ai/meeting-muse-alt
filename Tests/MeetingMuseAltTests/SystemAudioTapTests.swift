import Testing
import Foundation
import AVFoundation
@testable import MeetingMuseAlt

/// Tests for the M2.3 Core Audio Process Tap scaffold.
///
/// 현재 구현 범위:
///  - PID 유효성 검사 → `TapError.invalidPID`
///  - macOS 14.4 미만 → `TapError.unsupportedOS`
///  - PID 가 0 인 경우 AsyncThrowingStream 가 에러로 finish
///
/// 실제 탭 생성/해제는 권한과 사용자 동의가 필요해서 단위 테스트에서는
/// 다루지 않습니다. 후속 PR (IO proc + 권한 흐름) 에서 통합 테스트로 보강.

@Test func captureProcessRejectsNegativePID() async {
    let stream = SystemAudioTap.shared.captureProcess(pid: -1)
    var iterator = stream.makeAsyncIterator()
    do {
        _ = try await iterator.next()
        Issue.record("Expected captureProcess(-1) to throw, but it produced a buffer")
    } catch let error as SystemAudioTap.TapError {
        if case .invalidPID(let pid) = error {
            #expect(pid == -1)
        } else {
            Issue.record("Expected .invalidPID, got \(error)")
        }
    } catch {
        Issue.record("Expected TapError.invalidPID, got \(type(of: error)): \(error)")
    }
}

@Test func captureProcessRejectsZeroPID() async {
    let stream = SystemAudioTap.shared.captureProcess(pid: 0)
    var iterator = stream.makeAsyncIterator()
    do {
        _ = try await iterator.next()
        Issue.record("Expected captureProcess(0) to throw")
    } catch let error as SystemAudioTap.TapError {
        guard case .invalidPID = error else {
            Issue.record("Expected .invalidPID for pid 0, got \(error)")
            return
        }
    } catch {
        Issue.record("Expected TapError.invalidPID, got \(error)")
    }
}

@Test func attachRejectsInvalidPID() async {
    let engine = AVAudioEngineStub.make()
    do {
        try SystemAudioTap.shared.attach(to: engine, pid: -42)
        Issue.record("Expected attach(pid: -42) to throw")
    } catch let error as SystemAudioTap.TapError {
        // On unsupported OS we get .unsupportedOS first; on macOS 14.4+
        // we get .invalidPID. Either is correct for this test.
        switch error {
        case .invalidPID(let pid):
            #expect(pid == -42)
        case .unsupportedOS:
            break // running on older macOS — also acceptable
        default:
            Issue.record("Expected .invalidPID or .unsupportedOS, got \(error)")
        }
    } catch {
        Issue.record("Expected TapError, got \(type(of: error)): \(error)")
    }
}

@Test func processObjectIDRejectsInvalidPID() throws {
    if #available(macOS 14.4, *) {
        do {
            _ = try SystemAudioTap.processObjectID(for: 0)
            Issue.record("Expected processObjectID(0) to throw")
        } catch let error as SystemAudioTap.TapError {
            guard case .invalidPID = error else {
                Issue.record("Expected .invalidPID, got \(error)")
                return
            }
        }
    }
    // On older macOS the API is gated; this test is a no-op there.
}

// MARK: - Helpers

/// AVAudioEngine 인스턴스만 필요한 곳에서 사용할 더미 빌더.
/// `attach(to:)` 는 OS 체크/PID 검증이 먼저라서 엔진을 실제로 시작하지 않음.
private enum AVAudioEngineStub {
    static func make() -> AVAudioEngine {
        return AVAudioEngine()
    }
}
