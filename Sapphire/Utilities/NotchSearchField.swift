//
//  NotchSearchField.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-10

import SwiftUI
import AppKit

struct NotchSearchField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil
    var autofocus: Bool = false

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(NSLocalizedString(placeholder, comment: "Notch search placeholder"), text: $text)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .onSubmit { onSubmit?() }
            .onChange(of: isFocused) { _, focused in
                guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
                if focused {
                    appDelegate.makeNotchWindowFocusable()
                } else {
                    appDelegate.revertNotchWindowFocus()
                }
            }
            .onAppear {
                if autofocus {
                    DispatchQueue.main.async {
                        isFocused = true
                    }
                }
            }
            .onDisappear {
                if isFocused {
                    isFocused = false
                    (NSApp.delegate as? AppDelegate)?.revertNotchWindowFocus()
                }
            }
    }
}

struct NotchSearchBar: View {
    let placeholder: String
    @Binding var text: String
    let accent: Color
    var autofocus = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            NotchSearchField(
                placeholder: placeholder,
                text: $text,
                autofocus: autofocus
            )
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MaterialChartPalette.surfaceContainer)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MaterialChartPalette.cardGradient(for: accent))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accent.opacity(0.22), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
}

struct NotchKeyboardFocusModifier: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in
                guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
                if focused {
                    appDelegate.makeNotchWindowFocusable()
                } else {
                    appDelegate.revertNotchWindowFocus()
                }
            }
            .onDisappear {
                if isFocused {
                    isFocused = false
                    (NSApp.delegate as? AppDelegate)?.revertNotchWindowFocus()
                }
            }
    }
}

extension View {
    func notchKeyboardFocus() -> some View {
        modifier(NotchKeyboardFocusModifier())
    }
}
