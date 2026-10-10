//
//  NotesWidgetView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import SwiftUI
import AppKit

struct NotesWidgetView: View {
    @ObservedObject private var notesManager = NotesManager.shared

    var body: some View {
        NotchMiniListWidget(
            title: "Notes",
            systemImage: "note.text",
            tint: .yellow,
            gradient: [Color.yellow.opacity(0.35), Color.orange.opacity(0.18)],
            count: notesManager.notes.count,
            items: Array(notesManager.notes.sorted { $0.updatedAt > $1.updatedAt }.prefix(3)),
            emptyText: "No notes yet"
        ) { note in
            Capsule()
                .fill(Color.yellow.opacity(0.75))
                .frame(width: 3, height: 14)
            Text(Self.suggestionLabel(for: note))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.9))
                .lineLimit(1)
        }
    }

    private static func suggestionLabel(for note: QuickNote) -> String {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? (body.isEmpty ? NSLocalizedString("Untitled", comment: "Note without a title") : body) : title
    }
}

struct NotesPlayerView: View {
    @Binding var navigationStack: [NotchWidgetMode]
    @EnvironmentObject var settings: SettingsModel
    @ObservedObject private var notesManager = NotesManager.shared
    @StateObject private var editorGate = NoteEditorGate()
    @State private var searchText = ""
    @State private var showSearch = false

    private var filteredNotes: [QuickNote] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return notesManager.notes }
        return notesManager.notes.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.body.localizedCaseInsensitiveContains(query)
        }
    }

    private var editingNote: QuickNote? {
        guard let id = editorGate.editingNoteID else { return nil }
        return notesManager.notes.first { $0.id == id }
    }

    var body: some View {
        Group {
            if let note = editingNote {
                InNotchNoteEditor(
                    note: note,
                    onBack: { editorGate.editingNoteID = nil },
                    onSave: { updated in
                        notesManager.updateNote(updated)
                    },
                    onDelete: {
                        notesManager.deleteNote(id: note.id)
                        editorGate.editingNoteID = nil
                    }
                )
            } else {
                listView
            }
        }
        .onAppear {
            NotchBackRouter.shared.intercept = { [weak editorGate] in
                editorGate?.dismissIfEditing() ?? false
            }
        }
        .onDisappear {
            NotchBackRouter.shared.intercept = nil
        }
    }

    private var listView: some View {
        NotchSwipeListPanel(
            title: "Notes",
            subtitle: String(format: NSLocalizedString("%d saved", comment: "Saved note count"), notesManager.notes.count),
            accent: .yellow,
            searchPlaceholder: "Search notes",
            searchText: $searchText,
            showSearch: $showSearch,
            width: 460,
            items: filteredNotes,
            leadingAction: { action(settings.settings.swipeActionSettings.notesLeading, for: $0) },
            trailingAction: { action(settings.settings.swipeActionSettings.notesTrailing, for: $0) }
        ) {
            NotchCapsuleIconButton(systemName: "square.and.pencil", activeTint: .yellow) {
                let note = notesManager.addNote()
                editorGate.editingNoteID = note.id
            }
        } row: { note in
            noteRow(note)
        } emptyState: {
            NotchListEmptyState(
                systemImage: "note.text",
                tint: .yellow,
                title: searchText.isEmpty ? "No notes yet" : "No matching notes",
                message: searchText.isEmpty ? "Tap the pencil to create your first note." : "Try a different search."
            )
        }
    }

    private func noteRow(_ note: QuickNote) -> some View {
        Button {
            editorGate.editingNoteID = note.id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: note.isDone
                                ? [Color.green.opacity(0.75), Color.mint.opacity(0.45)]
                                : [Color.yellow.opacity(0.9), Color.orange.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(note.title.isEmpty ? NSLocalizedString("Untitled", comment: "Note without a title") : note.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(note.isDone ? .secondary : .primary)
                            .strikethrough(note.isDone, color: .secondary)
                            .lineLimit(1)
                        if note.isDone {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.green.opacity(0.9))
                        }
                    }
                    Text(note.body.isEmpty ? NSLocalizedString("Empty note", comment: "Note without content") : note.body)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .opacity(note.isDone ? 0.65 : 1)
                }
                Spacer(minLength: 0)
                RelativeMinuteText(date: note.updatedAt)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .notchTintedCard(note.isDone ? .green : .yellow)
            .opacity(note.isDone ? 0.82 : 1)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(note.isDone ? NSLocalizedString("Mark Undone", comment: "Note action") : NSLocalizedString("Mark Done", comment: "Note action")) {
                notesManager.toggleNoteDone(id: note.id)
            }
            Button("Edit") { editorGate.editingNoteID = note.id }
            Button("Copy") {
                NSPasteboard.general.copyString("\(note.title)\n\(note.body)")
            }
            Divider()
            Button("Delete", role: .destructive) {
                notesManager.deleteNote(id: note.id)
            }
        }
    }

    private func action(_ configuredAction: NotesSwipeAction, for note: QuickNote) -> NotchSwipeAction? {
        switch configuredAction {
        case .none:
            return nil
        case .toggleDone:
            return NotchSwipeAction(
                systemImage: note.isDone ? "arrow.uturn.backward" : "checkmark",
                tint: note.isDone ? .orange : .green
            ) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    notesManager.toggleNoteDone(id: note.id)
                }
            }
        case .copy:
            return NotchSwipeAction(systemImage: "doc.on.doc", tint: .yellow) {
                copyNote(note)
            }
        case .delete:
            return NotchSwipeAction(systemImage: "trash.fill", tint: .red) {
                deleteNote(note)
            }
        }
    }

    private func deleteNote(_ note: QuickNote) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            if editorGate.editingNoteID == note.id { editorGate.editingNoteID = nil }
            notesManager.deleteNote(id: note.id)
        }
    }

    private func copyNote(_ note: QuickNote) {
        NSPasteboard.general.copyString("\(note.title)\n\(note.body)")
    }
}

@MainActor
private final class NoteEditorGate: ObservableObject {
    @Published var editingNoteID: UUID?

    func dismissIfEditing() -> Bool {
        guard editingNoteID != nil else { return false }
        editingNoteID = nil
        return true
    }
}

private struct InNotchNoteEditor: View {
    @State private var draft: QuickNote
    @State private var attributedBody: NSAttributedString
    @StateObject private var textViewBox = RichTextViewBox()

    let onBack: () -> Void
    let onSave: (QuickNote) -> Void
    let onDelete: () -> Void

    init(
        note: QuickNote,
        onBack: @escaping () -> Void,
        onSave: @escaping (QuickNote) -> Void,
        onDelete: @escaping () -> Void
    ) {
        _draft = State(initialValue: note)
        _attributedBody = State(initialValue: note.attributedBody())
        self.onBack = onBack
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                NotchSearchField(placeholder: "Title", text: $draft.title, autofocus: draft.title == "New Note" || draft.title.isEmpty)
                    .font(.system(size: 15, weight: .bold, design: .rounded))

                Spacer(minLength: 8)

                NotchCapsuleIconButton(
                    systemName: "trash",
                    isActive: true,
                    activeTint: .red,
                    help: "Delete note",
                    action: onDelete
                )

                Button(action: saveAndBack) {
                    Text("Done")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.yellow.opacity(0.22), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)

            RichTextToolbar(textViewBox: textViewBox, attributedText: $attributedBody)
                .padding(.horizontal, 12)
                .background(MaterialChartPalette.surfaceVariant, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            RichTextEditor(attributedText: $attributedBody, textViewBox: textViewBox)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MaterialChartPalette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MaterialChartPalette.outline, lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .frame(width: 520, height: 310)
        .clipped()
        .onDisappear {
            persistDraft()
        }
    }

    private func persistDraft() {
        draft.applyAttributedBody(attributedBody)
        onSave(draft)
    }

    private func saveAndBack() {
        persistDraft()
        onBack()
    }
}
