import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DocumentWindow: View {
    @Binding var document: HangyeolDocument
    var fileURL: URL?
    /// Preview / tests. Live windows use `document.hasUnsavedEdits`.
    var isEditedOverride: Bool? = nil

    @Environment(\.openDocument) private var openDocument
    @ObservedObject private var recents = RecentDocuments.shared
    @StateObject private var exportFailure = RetryableFailure()
    @StateObject private var printFailure = RetryableFailure()
    @StateObject private var reopenFailure = RetryableFailure()
    @State private var showFindReplace = false
    @State private var findQuery = ""
    @State private var replaceQuery = ""
    @State private var lastReplacementCount: Int?
    @State private var replaceStatusFocusToken = 0
    @State private var presentedError: HangyeolError?
    @State private var dismissedOpenErrorID: String?
    @State private var cellEditError: HangyeolError?
    @State private var lastCellEdit: (table: UInt32, row: Int, col: Int, text: String)?
    @State private var paragraphEditError: HangyeolError?
    @State private var lastParagraphEdit: (section: UInt32, paragraph: UInt32, oldText: String, newText: String)?
    @State private var engineTables: [TableInfo] = []
    @State private var showHelp = false
    @State private var isDropTargeted = false
    @State private var dismissedSaveErrorID: String?
    @State private var exportProgress: ExportProgressPresentation?

    /// Phase0 스케치 플래그. `true`면 본문 대신 `RenderHostView.placeholder`.
    /// 합의·개발자2 주입 전까지 기본 `false`(`StructuredTextView` 유지).
    private let showsRenderHostSketch = false

    private var chrome: DocumentChromeState {
        DocumentChromeState.make(
            title: document.model.displayTitle,
            isEditedOverride: isEditedOverride,
            hasUnsavedEdits: document.hasUnsavedEdits
        )
    }

    private var sessionSaveError: HangyeolError? {
        SessionSaveFailurePresentation.presentedError(
            lastSaveError: document.session.lastSaveError,
            dismissedID: dismissedSaveErrorID
        )
    }

    /// Open freeze failures (`encrypted` / `corrupt` / `unsupported` / …) on ErrorSheet.
    private var sessionOpenError: HangyeolError? {
        SessionOpenFailurePresentation.presentedError(
            lastOpenError: document.session.lastOpenError,
            dismissedID: dismissedOpenErrorID
        )
    }

    private var findReplacePresentation: FindReplacePresentation {
        FindReplacePresentation.make(
            canReplace: document.session.canReplace,
            query: findQuery,
            lastReplacementCount: lastReplacementCount,
            statusFocusToken: replaceStatusFocusToken
        )
    }

    private var exportPresentation: ExportPresentation {
        ExportPresentation.make(isEmpty: document.model.isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showFindReplace {
                FindReplaceBar(
                    query: $findQuery,
                    replacement: $replaceQuery,
                    presentation: findReplacePresentation,
                    onFind: {},
                    onReplace: replaceInDocument,
                    onClose: { showFindReplace = false }
                )
                Divider()
            }

            if document.model.isEmpty {
                EmptyStateView(
                    recents: recents.items,
                    onOpenSample: loadSample,
                    onOpenDocument: presentOpenPanel,
                    onOpenRecent: openRecent
                )
            } else if showsRenderHostSketch {
                RenderHostView.placeholder
            } else {
                StructuredTextView(
                    model: document.model,
                    canEditCells: document.session.canEditCells,
                    canEditParagraphs: document.session.canEditParagraphs,
                    engineTables: engineTables,
                    onTableCellCommit: commitTableCell,
                    onParagraphCommit: commitParagraph
                )
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .padding(12)
                    .overlay {
                        Text(L10n.dropToOpen)
                            .font(.title2.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            FileOpening.handleDrop(providers: providers)
        }
        .navigationTitle(chrome.title)
        .hangyeolEditedSubtitle(chrome.navigationSubtitle)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if chrome.isEdited {
                    Text(L10n.edited)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                        .accessibilityLabel(L10n.edited)
                        .accessibilityIdentifier("document-edited-badge")
                }

                Button {
                    showFindReplace.toggle()
                } label: {
                    Label(L10n.find, systemImage: "magnifyingglass")
                }
                .help(L10n.find)

                Button(action: exportPDF) {
                    Label(L10n.exportPDF, systemImage: "arrow.up.doc")
                }
                .help(exportPresentation.exportHelp)
                .accessibilityHint(exportPresentation.exportHelp)
                .disabled(!exportPresentation.canExport)

                Button(action: printDocument) {
                    Label(L10n.printDocument, systemImage: "printer")
                }
                .help(exportPresentation.printHelp)
                .accessibilityHint(exportPresentation.printHelp)
                .disabled(!exportPresentation.canPrint)
            }
        }
        .sheet(item: openErrorSheetBinding) { error in
            ErrorSheet(error: error, context: .generic) {
                dismissOpenError(error)
            }
        }
        .sheet(item: $cellEditError) { error in
            ErrorSheet(
                error: error,
                context: .tableCell,
                retryTitle: L10n.retry,
                retryHint: L10n.tableCellEditRetryHint,
                onRetry: retryLastCellEdit,
                onDismiss: { cellEditError = nil }
            )
        }
        .sheet(item: $paragraphEditError) { error in
            ErrorSheet(
                error: error,
                context: .paragraph,
                retryTitle: L10n.retry,
                retryHint: L10n.paragraphEditRetryHint,
                onRetry: retryLastParagraphEdit,
                onDismiss: { paragraphEditError = nil }
            )
        }
        .sheet(item: sessionSaveErrorBinding) { error in
            SaveFailureSheet(
                error: error,
                context: .save,
                retryTitle: L10n.retrySave,
                retryHint: L10n.saveFailureRetryHint,
                onRetry: retryDocumentSave,
                onDismiss: { dismissedSaveErrorID = error.id }
            )
        }
        .sheet(item: exportFailure.sheetBinding) { error in
            SaveFailureSheet(
                error: error,
                context: .export,
                retryTitle: ExportPresentation.retryTitle(for: error),
                retryHint: ExportPresentation.retryHint(for: error),
                onRetry: { exportFailure.retry() },
                onDismiss: { exportFailure.dismiss() }
            )
        }
        .sheet(item: printFailure.sheetBinding) { error in
            SaveFailureSheet(
                error: error,
                context: .print,
                retryTitle: L10n.openDocument,
                retryHint: L10n.printEmptyRetryHint,
                onRetry: { printFailure.retry() },
                onDismiss: { printFailure.dismiss() }
            )
        }
        .sheet(item: $exportProgress) { presentation in
            ExportProgressSheet(presentation: presentation)
        }
        .sheet(item: reopenFailure.sheetBinding) { error in
            ErrorSheet(
                error: error,
                context: .reopen,
                retryTitle: L10n.retryOpen,
                retryHint: L10n.reopenRetryHint,
                onRetry: { reopenFailure.retry() },
                onDismiss: { reopenFailure.dismiss() }
            )
        }
        .sheet(isPresented: $showHelp) {
            HelpSheet(onDismiss: { showHelp = false })
        }
        .focusedSceneValue(\.hangyeolActions, HangyeolWindowActions(
            openSample: loadSample,
            openDocument: presentOpenPanel,
            openRecent: openRecent,
            clearRecents: { recents.clear() },
            toggleFindReplace: { showFindReplace.toggle() },
            exportPDF: exportPDF,
            printDocument: printDocument,
            showHelp: { showHelp = true },
            canExportPDF: exportPresentation.canExport,
            canPrint: exportPresentation.canPrint,
            exportHelp: exportPresentation.exportHelp,
            printHelp: exportPresentation.printHelp
        ))
        .focusedSceneValue(\.hangyeolRecents, recents.items)
        .onAppear {
            FileOpening.install(openDocument: openDocument)
            if let fileURL {
                recents.noteOpened(fileURL)
            }
            reloadEngineTables()
        }
        .hangyeolSessionUndo(document: $document)
        .onChange(of: fileURL) { _, url in
            if let url {
                recents.noteOpened(url)
            }
            reloadEngineTables()
        }
        .onChange(of: document.hasUnsavedEdits) { _, _ in
            reloadEngineTables()
        }
        .onChange(of: document.session.canEditCells) { _, _ in
            reloadEngineTables()
        }
        .onChange(of: document.session.canEditParagraphs) { _, _ in
            reloadEngineTables()
        }
        .onChange(of: findQuery) { _, _ in
            lastReplacementCount = nil
        }
        .onReceive(document.session.$lastSaveError) { error in
            if error == nil {
                dismissedSaveErrorID = nil
            }
        }
        .onReceive(document.session.$lastOpenError) { error in
            if error == nil {
                dismissedOpenErrorID = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: HangyeolError.presentNotification)) { note in
            if let error = note.object as? HangyeolError {
                presentedError = error
            }
        }
    }

    private var sessionSaveErrorBinding: Binding<HangyeolError?> {
        Binding(
            get: { sessionSaveError },
            set: { newValue in
                if newValue == nil, let id = document.session.lastSaveError?.id {
                    dismissedSaveErrorID = id
                }
            }
        )
    }

    /// `presentedError` (Finder / open panel / sample) or session `lastOpenError`.
    private var openErrorSheetBinding: Binding<HangyeolError?> {
        Binding(
            get: { presentedError ?? sessionOpenError },
            set: { newValue in
                if newValue == nil {
                    if let presentedError {
                        dismissOpenError(presentedError)
                    } else if let sessionOpenError {
                        dismissOpenError(sessionOpenError)
                    }
                } else {
                    presentedError = newValue
                }
            }
        )
    }

    private func dismissOpenError(_ error: HangyeolError) {
        if presentedError?.id == error.id {
            presentedError = nil
        }
        if document.session.lastOpenError?.id == error.id {
            dismissedOpenErrorID = error.id
        }
    }

    private func retryDocumentSave() {
        NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil)
    }

    private func reloadEngineTables() {
        guard document.session.canEditCells || document.session.canEditParagraphs else {
            engineTables = []
            return
        }
        do {
            engineTables = try document.listTables()
        } catch {
            engineTables = []
        }
    }

    private func commitTableCell(engineIndex: UInt32, row: Int, col: Int, text: String) {
        lastCellEdit = (engineIndex, row, col, text)
        switch TableCellEditFlow.commit(
            canEditCells: document.session.canEditCells,
            engineTableIndex: engineIndex,
            row: row,
            col: col,
            text: text,
            perform: { table, cellRow, cellCol, value in
                var updated = document
                try updated.setCellText(table: table, row: cellRow, col: cellCol, text: value)
                document = updated
            }
        ) {
        case .skippedUnavailable, .skippedUnmapped:
            return
        case .updated:
            reloadEngineTables()
        case .failed(let error):
            cellEditError = error
        }
    }

    private func retryLastCellEdit() {
        guard let last = lastCellEdit else {
            cellEditError = nil
            return
        }
        cellEditError = nil
        commitTableCell(engineIndex: last.table, row: last.row, col: last.col, text: last.text)
    }

    private func commitParagraph(section: UInt32, paragraph: UInt32, oldText: String, newText: String) {
        lastParagraphEdit = (section, paragraph, oldText, newText)
        switch ParagraphEditFlow.commit(
            canEditParagraphs: document.session.canEditParagraphs,
            section: section,
            paragraph: paragraph,
            oldText: oldText,
            newText: newText,
            insert: { sec, para, offset, text in
                var updated = document
                try updated.insertText(section: sec, paragraph: para, charOffset: offset, text: text)
                document = updated
            },
            delete: { sec, para, offset, count in
                var updated = document
                try updated.deleteRange(section: sec, paragraph: para, charOffset: offset, count: count)
                document = updated
            }
        ) {
        case .skippedUnavailable, .skippedUnmapped, .skippedUnchanged:
            return
        case .updated:
            reloadEngineTables()
        case .failed(let error):
            paragraphEditError = error
        }
    }

    private func retryLastParagraphEdit() {
        guard let last = lastParagraphEdit else {
            paragraphEditError = nil
            return
        }
        paragraphEditError = nil
        commitParagraph(
            section: last.section,
            paragraph: last.paragraph,
            oldText: last.oldText,
            newText: last.newText
        )
    }

    private func replaceInDocument() {
        switch FindReplaceFlow.replace(
            canReplace: document.session.canReplace,
            find: findQuery,
            replace: replaceQuery,
            perform: { find, replacement in
                var updated = document
                let count = try updated.replaceText(find: find, replace: replacement)
                document = updated
                return count
            }
        ) {
        case .skippedUnavailable, .skippedEmptyQuery:
            return
        case .replaced(let count):
            lastReplacementCount = count
            replaceStatusFocusToken += 1
        case .failed(let error):
            presentedError = error
        }
    }

    private func loadSample() {
        do {
            document.model = try MockEngine.loadBundledSample()
            reloadEngineTables()
        } catch let error as HangyeolError {
            presentedError = error
        } catch {
            presentedError = .sampleNotFound
        }
    }

    private func presentOpenPanel() {
        FileOpening.install(openDocument: openDocument)
        FileOpening.presentOpenPanel()
    }

    private func openRecent(_ item: RecentDocuments.Item) {
        do {
            try recents.open(item)
        } catch let error as HangyeolError {
            reopenFailure.present(error) { openRecent(item) }
        } catch {
            reopenFailure.present(.bookmarkFailed(error.localizedDescription)) {
                openRecent(item)
            }
        }
    }

    private func exportPDF() {
        guard exportPresentation.canExport else {
            exportFailure.present(.exportEmptyDocument, retry: presentOpenPanel)
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.title = L10n.exportPDF
        panel.prompt = L10n.exportPDFConfirm
        panel.message = L10n.exportPDFMessage
        panel.nameFieldStringValue = "\(document.model.displayTitle).pdf"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let filename = url.lastPathComponent
            exportProgress = .make(filename: filename)
            DispatchQueue.main.async {
                switch ExportFlow.export(isEmpty: document.model.isEmpty, perform: {
                    try PDFExporter.export(document.model, to: url)
                }) {
                case .skippedEmpty:
                    exportProgress = nil
                    exportFailure.present(.exportEmptyDocument, retry: presentOpenPanel)
                case .exported:
                    exportProgress = nil
                case .failed(let error):
                    exportProgress = nil
                    exportFailure.present(error, retry: exportPDF)
                }
            }
        }
    }

    private func printDocument() {
        switch PrintFlow.prepare(
            isEmpty: document.model.isEmpty,
            plainText: document.model.plainText
        ) {
        case .skippedEmpty:
            printFailure.present(.printEmptyDocument, retry: presentOpenPanel)
        case .ready(let text):
            PrintCoordinator.print(text: text, jobTitle: document.model.displayTitle)
        }
    }
}

#Preview("문서") {
    DocumentWindow(
        document: .constant(HangyeolDocument(model: MockEngine.sampleDocument())),
        fileURL: nil
    )
}

#Preview("빈 화면") {
    DocumentWindow(document: .constant(HangyeolDocument()), fileURL: nil)
}

#Preview("편집됨") {
    DocumentWindow(
        document: .constant(HangyeolDocument(model: MockEngine.sampleDocument())),
        fileURL: nil,
        isEditedOverride: true
    )
}
