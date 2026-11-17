import AppKit
import QuickLookThumbnailing
import SwiftUI
import WorshpickCore

struct SetlistFileRow: Equatable, Identifiable {
    var itemId: Int64
    var songId: UUID
    var fileURL: URL
    var title: String
    var slotLabel: String?
    var fileExists: Bool

    var id: Int64 { itemId }
    var fileName: String { fileURL.lastPathComponent }
}

extension NSPasteboard.PasteboardType {
    static let setlistRowIndex = NSPasteboard.PasteboardType("com.dfeliz.worshpick.setlist-row")
    static let worshpickSong = NSPasteboard.PasteboardType(UTType.worshpickSong.identifier)
}

/// AppKit table so several selected files can be dragged out to Proclaim at once, in setlist order.
struct SetlistFileTable: NSViewRepresentable {
    var rows: [SetlistFileRow]
    var onReorder: ([Int64]) -> Void
    var onDropSongs: ([UUID], Int) -> Void
    var onRemove: ([Int64]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = 52
        tableView.allowsMultipleSelection = true
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = false
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.registerForDraggedTypes([.setlistRowIndex, .worshpickSong])
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.draggingDestinationFeedbackStyle = .gap

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quitar del setlist", action: #selector(Coordinator.removeClickedRows(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Mostrar en Finder", action: #selector(Coordinator.revealClickedRows(_:)), keyEquivalent: ""))
        menu.items.forEach { $0.target = context.coordinator }
        tableView.menu = menu

        context.coordinator.tableView = tableView
        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onReorder = onReorder
        coordinator.onDropSongs = onDropSongs
        coordinator.onRemove = onRemove
        guard coordinator.rows != rows else { return }
        let selectedItemIds = coordinator.selectedItemIds
        coordinator.rows = rows
        coordinator.tableView?.reloadData()
        let rowIndexesToSelect = IndexSet(rows.indices.filter { selectedItemIds.contains(rows[$0].itemId) })
        coordinator.tableView?.selectRowIndexes(rowIndexesToSelect, byExtendingSelection: false)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var rows: [SetlistFileRow] = []
        var onReorder: ([Int64]) -> Void = { _ in }
        var onDropSongs: ([UUID], Int) -> Void = { _, _ in }
        var onRemove: ([Int64]) -> Void = { _ in }
        weak var tableView: NSTableView?
        private var thumbnailsByFileURL: [URL: NSImage] = [:]
        private var thumbnailRequestsInFlight: Set<URL> = []

        var selectedItemIds: Set<Int64> {
            Set(tableView?.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].itemId : nil } ?? [])
        }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let cell = (tableView.makeView(withIdentifier: SetlistFileCellView.identifier, owner: nil) as? SetlistFileCellView) ?? SetlistFileCellView()
            let fileRow = rows[row]
            cell.configure(with: fileRow, position: row + 1, thumbnail: thumbnail(for: fileRow, row: row))
            return cell
        }

        // MARK: Dragging out and reordering

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            let fileRow = rows[row]
            guard fileRow.fileExists else { return nil }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(fileRow.fileURL.absoluteString, forType: .fileURL)
            pasteboardItem.setString(String(row), forType: .setlistRowIndex)
            return pasteboardItem
        }

        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
            tableView.setDropRow(row, dropOperation: .above)
            let isReorderInsideTable = (info.draggingSource as? NSTableView) === tableView
            if isReorderInsideTable { return .move }
            return info.draggingPasteboard.types?.contains(.worshpickSong) == true ? .copy : []
        }

        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            let pasteboardItems = info.draggingPasteboard.pasteboardItems ?? []
            let isReorderInsideTable = (info.draggingSource as? NSTableView) === tableView
            if isReorderInsideTable {
                let draggedRowIndexes = pasteboardItems.compactMap { $0.string(forType: .setlistRowIndex).flatMap(Int.init) }
                onReorder(Self.itemIdsAfterMoving(rowIndexes: draggedRowIndexes, to: row, in: rows.map(\.itemId)))
                return true
            }
            let droppedSongIds = pasteboardItems
                .compactMap { $0.data(forType: .worshpickSong) }
                .compactMap { try? JSONDecoder().decode(SongDragItem.self, from: $0) }
                .flatMap(\.songIds)
            guard !droppedSongIds.isEmpty else { return false }
            onDropSongs(droppedSongIds, row)
            return true
        }

        static func itemIdsAfterMoving(rowIndexes: [Int], to destinationRow: Int, in itemIds: [Int64]) -> [Int64] {
            let movedRowIndexes = Set(rowIndexes)
            let movedItemIds = rowIndexes.sorted().map { itemIds[$0] }
            var remainingItemIds = itemIds.enumerated().filter { !movedRowIndexes.contains($0.offset) }.map(\.element)
            let movedRowsAboveDestination = rowIndexes.filter { $0 < destinationRow }.count
            let insertionIndex = min(destinationRow - movedRowsAboveDestination, remainingItemIds.count)
            remainingItemIds.insert(contentsOf: movedItemIds, at: max(0, insertionIndex))
            return remainingItemIds
        }

        // MARK: Context menu

        private var clickedOrSelectedRows: [SetlistFileRow] {
            guard let tableView else { return [] }
            let clickedRow = tableView.clickedRow
            let rowIndexes = clickedRow >= 0 && !tableView.selectedRowIndexes.contains(clickedRow) ? IndexSet(integer: clickedRow) : tableView.selectedRowIndexes
            return rowIndexes.filter(rows.indices.contains).map { rows[$0] }
        }

        @objc func removeClickedRows(_ sender: Any?) {
            onRemove(clickedOrSelectedRows.map(\.itemId))
        }

        @objc func revealClickedRows(_ sender: Any?) {
            NSWorkspace.shared.activateFileViewerSelecting(clickedOrSelectedRows.filter(\.fileExists).map(\.fileURL))
        }

        // MARK: Thumbnails

        private func thumbnail(for fileRow: SetlistFileRow, row: Int) -> NSImage {
            if let cachedThumbnail = thumbnailsByFileURL[fileRow.fileURL] { return cachedThumbnail }
            let placeholder = NSWorkspace.shared.icon(for: .mpeg4Movie)
            guard fileRow.fileExists, !thumbnailRequestsInFlight.contains(fileRow.fileURL) else { return placeholder }
            thumbnailRequestsInFlight.insert(fileRow.fileURL)
            let request = QLThumbnailGenerator.Request(fileAt: fileRow.fileURL, size: CGSize(width: 72, height: 44), scale: 2, representationTypes: .thumbnail)
            let fileURL = fileRow.fileURL
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                let image = representation?.nsImage
                Task { @MainActor [weak self] in
                    guard let self, let image else { return }
                    self.thumbnailsByFileURL[fileURL] = image
                    if let rowIndex = self.rows.firstIndex(where: { $0.fileURL == fileURL }) {
                        self.tableView?.reloadData(forRowIndexes: IndexSet(integer: rowIndex), columnIndexes: IndexSet(integer: 0))
                    }
                }
            }
            return placeholder
        }
    }
}

final class SetlistFileCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("SetlistFileCell")

    private let positionLabel = NSTextField(labelWithString: "")
    private let thumbnailView = NSImageView()
    private let fileNameLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        positionLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        positionLabel.textColor = .tertiaryLabelColor
        positionLabel.alignment = .right
        thumbnailView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = 4
        thumbnailView.layer?.masksToBounds = true
        fileNameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        fileNameLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [fileNameLabel, detailLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        let rowStack = NSStackView(views: [positionLabel, thumbnailView, textStack])
        rowStack.orientation = .horizontal
        rowStack.spacing = 8
        rowStack.alignment = .centerY
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowStack)
        NSLayoutConstraint.activate([
            positionLabel.widthAnchor.constraint(equalToConstant: 18),
            thumbnailView.widthAnchor.constraint(equalToConstant: 64),
            thumbnailView.heightAnchor.constraint(equalToConstant: 40),
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            rowStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            rowStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        imageView = thumbnailView
        textField = fileNameLabel
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(with row: SetlistFileRow, position: Int, thumbnail: NSImage) {
        positionLabel.stringValue = "\(position)"
        thumbnailView.image = thumbnail
        fileNameLabel.stringValue = row.fileName
        fileNameLabel.textColor = row.fileExists ? .labelColor : .disabledControlTextColor
        let details = [row.slotLabel, row.fileExists ? nil : "Archivo no encontrado"].compactMap { $0 }
        detailLabel.stringValue = details.isEmpty ? row.title : details.joined(separator: " · ")
    }
}
