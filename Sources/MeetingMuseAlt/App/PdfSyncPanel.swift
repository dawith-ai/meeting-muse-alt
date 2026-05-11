import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import AppKit

/// SwiftUI 패널 — PDF 업로드, 페이지 미리보기, 페이지별 타임스탬프 마크.
///
/// `RecordingViewModel.elapsedSeconds` 와 `PdfSyncStore` 를 환경에서 받아
/// "현재 페이지에 지금 타임스탬프를 마크" 기능을 제공한다.
/// 영속화는 `MeetingRecord.pdfFilePath` / `pdfPageMarks` 로 흘려보낸다.
public struct PdfSyncPanel: View {
    @ObservedObject var store: PdfSyncStore
    /// 콜백: 호출자가 현재 녹음 타임스탬프를 알려준다 (초 단위).
    public var currentRecordingTime: () -> Double

    public init(store: PdfSyncStore, currentRecordingTime: @escaping () -> Double) {
        self.store = store
        self.currentRecordingTime = currentRecordingTime
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let url = store.pdfURL {
                PdfDocumentView(url: url, pageIndex: $store.currentPage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                marksList
            } else {
                emptyState
            }
        }
    }

    // MARK: - Subviews

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                openPdf()
            } label: {
                Label("PDF 열기", systemImage: "doc.fill")
            }
            if store.pdfURL != nil {
                Button {
                    store.upsertMark(
                        pageNumber: store.currentPage,
                        timestampSeconds: currentRecordingTime()
                    )
                } label: {
                    Label("현재 페이지에 타임스탬프 마크", systemImage: "bookmark.fill")
                }
                .keyboardShortcut("m", modifiers: [.command])

                Spacer()
                Text("페이지 \(store.currentPage) / \(store.totalPages)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Button("PDF 닫기") { store.clearPdf() }
                    .controlSize(.small)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("발표 자료 PDF를 업로드하세요")
                .font(.title3)
            Text("페이지를 넘기면서 ⌘M 으로 현재 녹음 시각에 마크하면, 재생 시 자동으로 따라갑니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var marksList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(store.marks) { mark in
                    HStack {
                        Text(mark.timestampLabel)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .leading)
                        Text("페이지 \(mark.pageNumber)")
                            .font(.callout)
                        Spacer()
                        Button {
                            store.currentPage = mark.pageNumber
                        } label: {
                            Image(systemName: "arrow.right.circle")
                        }
                        .buttonStyle(.borderless)
                        Button(role: .destructive) {
                            store.removeMark(forPage: mark.pageNumber)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    Divider()
                }
                if store.marks.isEmpty {
                    Text("마크 없음")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
        }
        .frame(maxHeight: 180)
    }

    // MARK: - PDF open

    private func openPdf() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            if let doc = PDFDocument(url: url) {
                store.loadPdf(url: url, totalPages: doc.pageCount)
            } else {
                store.loadPdf(url: url, totalPages: 0)
            }
        }
    }
}

/// `PDFView` 를 SwiftUI 로 래핑.
private struct PdfDocumentView: NSViewRepresentable {
    let url: URL
    @Binding var pageIndex: Int

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.displaysPageBreaks = false
        if let doc = PDFDocument(url: url) {
            view.document = doc
            if let page = doc.page(at: max(0, pageIndex - 1)) {
                view.go(to: page)
            }
        }
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        // 외부 상태 변화에 PDFView 동기화 (URL 변경 / 페이지 변경)
        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
        }
        if let doc = nsView.document {
            let safeIndex = max(0, min(pageIndex - 1, doc.pageCount - 1))
            if let target = doc.page(at: safeIndex),
               nsView.currentPage != target {
                nsView.go(to: target)
            }
        }
    }
}
