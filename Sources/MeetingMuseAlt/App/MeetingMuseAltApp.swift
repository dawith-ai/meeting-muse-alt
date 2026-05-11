import SwiftUI

@main
struct MeetingMuseAltApp: App {
    @StateObject private var recordingVM = RecordingViewModel()
    @StateObject private var detector = MeetingAppDetector()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(recordingVM)
                .environmentObject(detector)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    detector.start()
                }
                .onDisappear {
                    detector.stop()
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        MenuBarExtra("Meeting Muse Alt", systemImage: MenuBarStatus.iconName(isRecording: recordingVM.isRecording)) {
            MenuBarScene()
                .environmentObject(recordingVM)
                .environmentObject(detector)
        }
        .menuBarExtraStyle(.menu)
    }
}
