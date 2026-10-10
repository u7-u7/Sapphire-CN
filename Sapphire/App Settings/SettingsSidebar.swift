//
//  SettingsSidebar.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-10.
//

import SwiftUI

struct SettingsSidebarGroup: Identifiable {
    let title: String
    let sections: [SettingsSection]
    var id: String { title }
}

extension SettingsSection {
    static let sidebarGroups: [SettingsSidebarGroup] = [
        .init(title: "General", sections: [.general, .keyboardShortcuts, .bluetoothUnlock, .intelligence, .neardrop, .continuity]),
        .init(title: "Notch", sections: [.appearance, .widgets, .liveActivities, .lockScreen, .notifications, .hud]),
        .init(title: "Widgets & Content", sections: [.music, .weather, .calendar, .sports, .finance, .battery, .audio, .bluetooth, .shortcuts, .fileShelf, .notes, .clipboard, .mirror, .caffeine]),
        .init(title: "System & Utilities", sections: [.systemEnhance, .snapZones, .dockLayouts, .mediaOptimizer, .mouse, .monitoring, .devActivity, .emoji, .archives, .apps, .storage]),
        .init(title: "Focus & Security", sections: [.eyeBreak, .focusSession, .appLock]),
        .init(title: "", sections: [.about])
    ]
}

struct SettingsSidebarView: View {
    @Binding var selectedSection: SettingsSection?
    @Binding var showAccountPane: Bool
    let onQuit: () -> Void
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var searchText = ""

    private var filteredGroups: [SettingsSidebarGroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return SettingsSection.sidebarGroups }

        return SettingsSection.sidebarGroups.compactMap { group in
            let matches = group.sections.filter { section in
                // 切换中文显示后仍允许按英文名称和说明搜索。
                let haystacks = [section.label, section.shortDescription, section.englishLabel, section.englishShortDescription] + section.searchTokens
                return haystacks.contains { $0.localizedCaseInsensitiveContains(query) }
            }
            return matches.isEmpty ? nil : SettingsSidebarGroup(title: group.title, sections: matches)
        }
    }

    private var lockedSections: Set<SettingsSection> {
        Set(SettingsSection.sidebarGroups
            .flatMap(\.sections)
            .filter { section in
                section.requiredPremiumFeature
                    .map { !subscriptionManager.hasAccess(to: $0) } ?? false
            })
    }

    var body: some View {
        let lockedSections = lockedSections
        let filteredGroups = filteredGroups

        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 45)

            // MARK: 1. Search Settings (Top of Sidebar)
            ClearableSearchField(placeholder: "Search settings", text: $searchText)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            // MARK: 2. Apple ID Style Account Sidebar Card (Below Search Bar)
            SidebarAccountCardView(
                subscriptionManager: subscriptionManager,
                isSelected: showAccountPane
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showAccountPane = true
                    selectedSection = nil
                }
            }

            // MARK: 3. Settings Sections list
            List(selection: Binding(
                get: { selectedSection },
                set: { value in
                    selectedSection = value
                    if value != nil {
                        showAccountPane = false
                    }
                }
            )) {
                ForEach(filteredGroups) { group in
                    Section {
                        ForEach(group.sections) { section in
                            SidebarRowView(
                                section: section,
                                isPremiumLocked: lockedSections.contains(section)
                            )
                            .tag(section)
                        }
                    } header: {
                        Text(NSLocalizedString(group.title, comment: "Settings sidebar group"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.sidebar).scrollContentBackground(.hidden)
            .frame(maxHeight: .infinity, alignment: .top)
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SapphireSelectSection"))) { notification in
                if let sectionName = notification.object as? String,
                   let section = SettingsSection(rawValue: sectionName) {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        self.selectedSection = section
                        self.showAccountPane = false
                    }
                }
            }

            if !searchText.isEmpty && filteredGroups.isEmpty {
                Text(String(format: NSLocalizedString("No settings matched \"%@\".", comment: "Settings search empty state"), searchText))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            Spacer(minLength: 0)

            Button(action: onQuit) {
                HStack {
                    Image(systemName: "power.circle.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.red)
                        .frame(width: 30, height: 30)
                        .background(Color.red.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Text("Quit")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                }
                .padding(.vertical, 3)
                .padding(.leading, 12)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 15)
        }
    }
}

// MARK: - Sidebar Profile Card
struct SidebarAccountCardView: View {
    @ObservedObject var subscriptionManager: SubscriptionManager
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Group {
                    if subscriptionManager.isSignedIn {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: subscriptionManager.tierGradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                            Text(subscriptionManager.userInitials)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    } else {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 30, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(subscriptionManager.userDisplayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(subscriptionManager.tierLabel)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.white.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
}

struct TrafficLightButtonStyle: ButtonStyle {
    let color: Color; let isHovering: Bool
    func makeBody(configuration: Configuration) -> some View {
        ZStack { Circle().fill(color); configuration.label.foregroundStyle(.black.opacity(0.6)).opacity(isHovering ? 1 : 0) }.frame(width: 12, height: 12)
    }
}

fileprivate struct SidebarRowView: View {
    let section: SettingsSection
    let isPremiumLocked: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: section.systemImage).font(.system(size: 11, weight: .bold)).foregroundStyle(.white).frame(width: 22, height: 22).background(LinearGradient(colors: section.iconGradientColors, startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.8)).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(section.label).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
            Spacer()
            if isPremiumLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }.padding(.vertical, 5)
    }
}
