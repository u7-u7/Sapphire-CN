//
//  ClipboardWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import SwiftUI
import AppKit

@MainActor
private func performCopy(_ item: ClipboardItem, via manager: ClipboardManager) {
    if !manager.copyItem(item) { NSSound.beep() }
}

@MainActor
private func performShare(_ item: ClipboardItem, via manager: ClipboardManager) {
    if !manager.shareItem(item) { NSSound.beep() }
}

extension ClipboardItemKind {
    var spec: (systemImage: String, color: Color) {
        switch self {
        case .text:
            return ("doc.text", .blue)
        case .image:
            return ("photo", .purple)
        case .file:
            return ("doc", .teal)
        case .folder:
            return ("folder.fill", .orange)
        }
    }

    var displayName: String {
        switch self {
        case .text:
            return "Text"
        case .image:
            return "Image"
        case .file:
            return "File"
        case .folder:
            return "Folder"
        }
    }
}

struct ClipboardWidgetView: View {
    @ObservedObject private var clipboardManager = ClipboardManager.shared

    var body: some View {
        NotchMiniListWidget(
            title: "Clipboard",
            systemImage: "list.clipboard",
            tint: .blue,
            gradient: [Color.blue.opacity(0.35), Color.cyan.opacity(0.16)],
            count: clipboardManager.recentItems.count,
            items: Array(clipboardManager.recentItems.prefix(3)),
            emptyText: "Nothing copied yet"
        ) { item in
            let spec = item.kind.spec
            if item.isImage {
                ClipboardItemThumbnailView(
                    item: item,
                    size: 14,
                    cornerRadius: 3,
                    fallbackSystemImage: spec.systemImage,
                    fallbackTint: spec.color
                )
            } else {
                Image(systemName: spec.systemImage)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(spec.color)
                    .frame(width: 14)
            }
            Text(item.preview)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.9))
                .lineLimit(1)
        }
        .onAppear {
            clipboardManager.startMonitoring()
        }
        .contentShape(Rectangle())
    }
}

struct ClipboardPlayerView: View {
    @Binding var navigationStack: [NotchWidgetMode]
    @EnvironmentObject var settings: SettingsModel
    @ObservedObject private var clipboardManager = ClipboardManager.shared
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var filterImagesOnly = false

    private var filteredItems: [ClipboardItem] {
        var items = clipboardManager.recentItems
        if filterImagesOnly {
            items = items.filter(\.isImage)
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.preview.localizedCaseInsensitiveContains(query)
                || ($0.textContent?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        NotchSwipeListPanel(
            title: "Clipboard",
            subtitle: String(format: NSLocalizedString("%d items", comment: "Clipboard item count"), clipboardManager.recentItems.count),
            accent: .blue,
            searchPlaceholder: "Search clipboard",
            searchText: $searchText,
            showSearch: $showSearch,
            width: 480,
            items: Array(filteredItems.prefix(40)),
            leadingAction: { action(settings.settings.swipeActionSettings.clipboardLeading, for: $0) },
            trailingAction: { action(settings.settings.swipeActionSettings.clipboardTrailing, for: $0) }
        ) {
            NotchCapsuleIconButton(systemName: "photo", isActive: filterImagesOnly, activeTint: .blue) {
                filterImagesOnly.toggle()
            }
            NotchCapsuleIconButton(systemName: "trash", activeTint: .blue) {
                clipboardManager.clearHistory()
            }
        } row: { item in
            clipboardRow(item)
        } emptyState: {
            NotchListEmptyState(
                systemImage: "list.clipboard",
                tint: .blue,
                title: filterImagesOnly ? "No images" : (searchText.isEmpty ? "Clipboard is empty" : "No matches"),
                message: searchText.isEmpty ? "Copy text or images to build history." : "Try a different search."
            )
        }
        .onAppear {
            clipboardManager.startMonitoring()
            clipboardManager.beginHighPriorityMonitoring()
        }
        .onDisappear {
            clipboardManager.endHighPriorityMonitoring()
        }
    }

    private func clipboardRow(_ item: ClipboardItem) -> some View {
        let tint = item.kind.spec.color
        return HStack(alignment: .center, spacing: 12) {
            thumbnail(for: item)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.preview)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(item.kind.displayName)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint.opacity(0.9))
                    Text("·")
                        .foregroundStyle(.tertiary)
                    RelativeMinuteText(date: item.copiedAt)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            CopyAgainButton(
                tint: tint,
                onTap: { performCopy(item, via: clipboardManager) }
            )
            .help("Copy again")
        }
        .padding(12)
        .notchTintedCard(tint)
        .contentShape(Rectangle())
        .onTapGesture {
            performCopy(item, via: clipboardManager)
        }
        .contextMenu {
            Button("Copy") { performCopy(item, via: clipboardManager) }
            Button("Share…") { performShare(item, via: clipboardManager) }
            Button("Delete", role: .destructive) { clipboardManager.removeItem(id: item.id) }
        }
    }

    private struct CopyAgainButton: View {
        let tint: Color
        let onTap: () -> Void

        @State private var copied = false

        var body: some View {
            Button {
                onTap()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeInOut(duration: 0.25)) { copied = false }
                }
            } label: {
                ZStack {
                    NotchCapsuleIconLabel(
                        systemName: copied ? "checkmark" : "doc.on.doc",
                        isActive: copied,
                        activeTint: tint
                    )
                    .scaleEffect(copied ? 1.12 : 1.0)
                    .rotationEffect(.degrees(copied ? -6 : 0))
                    .animation(.spring(response: 0.35, dampingFraction: 0.55), value: copied)
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func thumbnail(for item: ClipboardItem) -> some View {
        let spec = item.kind.spec
        if item.isImage {
            ClipboardItemThumbnailView(
                item: item,
                size: 44,
                cornerRadius: 10,
                fallbackSystemImage: spec.systemImage,
                fallbackTint: spec.color,
                strokeColor: MaterialChartPalette.outline
            )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(spec.color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: spec.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(spec.color)
            }
        }
    }

    private func action(_ configuredAction: ClipboardSwipeAction, for item: ClipboardItem) -> NotchSwipeAction? {
        switch configuredAction {
        case .none:
            return nil
        case .share:
            return NotchSwipeAction(systemImage: "square.and.arrow.up", tint: .blue) {
                performShare(item, via: clipboardManager)
            }
        case .copy:
            return NotchSwipeAction(systemImage: "doc.on.doc", tint: .cyan) {
                performCopy(item, via: clipboardManager)
            }
        case .delete:
            return NotchSwipeAction(systemImage: "trash.fill", tint: .red) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    clipboardManager.removeItem(id: item.id)
                }
            }
        }
    }
}
