//
//  NotchListWidgetChrome.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-13

import SwiftUI

struct NotchMiniListWidget<Item: Identifiable, Row: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let gradient: [Color]
    let count: Int
    let items: [Item]
    let emptyText: String
    var onTap: (@MainActor (Item) -> Void)? = nil
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if items.isEmpty {
                Text(NSLocalizedString(emptyText, comment: "Empty notch widget message"))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(MaterialChartPalette.onSurfaceVariant)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(items) { item in
                        suggestion(item)
                    }
                }
            }
        }
        .frame(width: 176, height: 96, alignment: .topLeading)
        .clipped()
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 26, height: 26)
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(NSLocalizedString(title, comment: "Notch widget title"))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Text("\(count)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(MaterialChartPalette.onSurfaceVariant)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(MaterialChartPalette.surfaceVariant)
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private func suggestion(_ item: Item) -> some View {
        let chrome = HStack(spacing: 6) {
            row(item)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(MaterialChartPalette.surfaceContainer)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

        if let onTap {
            chrome
                .contentShape(Rectangle())
                .onTapGesture { onTap(item) }
        } else {
            chrome
        }
    }
}

struct NotchSwipeListPanel<Item: Identifiable, Toolbar: View, Row: View, EmptyState: View>: View {
    let title: String
    let subtitle: String
    let accent: Color
    let searchPlaceholder: String
    @Binding var searchText: String
    @Binding var showSearch: Bool
    let width: CGFloat
    let items: [Item]
    let leadingAction: @MainActor (Item) -> NotchSwipeAction?
    let trailingAction: @MainActor (Item) -> NotchSwipeAction?
    @ViewBuilder let toolbar: Toolbar
    @ViewBuilder let row: (Item) -> Row
    @ViewBuilder let emptyState: EmptyState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(NSLocalizedString(title, comment: "Notch panel title"))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                NotchCapsuleIconButton(systemName: "magnifyingglass", isActive: showSearch, activeTint: accent) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showSearch.toggle()
                        if !showSearch { searchText = "" }
                    }
                }
                toolbar
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            if showSearch {
                NotchSearchBar(
                    placeholder: searchPlaceholder,
                    text: $searchText,
                    accent: accent,
                    autofocus: true
                )
            }

            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(items) { item in
                            NotchSwipeRow(
                                leading: leadingAction(item),
                                trailing: trailingAction(item)
                            ) {
                                row(item)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
        }
        .padding(.top, 10)
        .frame(width: width, height: 270)
        .clipped()
    }
}

struct NotchListEmptyState: View {
    let systemImage: String
    let tint: Color
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(tint.opacity(0.8))
            Text(NSLocalizedString(title, comment: "Empty notch panel title"))
                .font(.headline)
            Text(NSLocalizedString(message, comment: "Empty notch panel message"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 20)
    }
}

extension View {
    func notchTintedCard(_ tint: Color) -> some View {
        background(
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MaterialChartPalette.surface)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MaterialChartPalette.cardGradient(for: tint))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MaterialChartPalette.outline, lineWidth: 1)
        )
    }
}
