//
//  TerminalInputBar.swift
//  Shelly
//
//  Terminal input field with custom keyboard toolbar
//

import SwiftUI

struct TerminalInputBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    @State private var showSpecialKeys = false

    var body: some View {
        VStack(spacing: 0) {
            // Special keys toolbar (shown when keyboard is active)
            if isFocused.wrappedValue {
                SpecialKeysToolbar(
                    onKeyTap: { key in insertSpecialKey(key) },
                    onDismiss: { isFocused.wrappedValue = false }
                )
            }

            // Input field
            HStack(spacing: 12) {
                // Toggle special keys / show keyboard
                Button {
                    if isFocused.wrappedValue {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSpecialKeys.toggle()
                        }
                    } else {
                        isFocused.wrappedValue = true
                    }
                } label: {
                    Image(systemName: isFocused.wrappedValue ? "keyboard.chevron.compact.down" : "keyboard")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                // Text field
                TextField("Enter command...", text: $text)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused(isFocused)
                    .onSubmit(onSubmit)

                // Send button
                Button(action: onSubmit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(text.isEmpty ? .secondary : .accentColor)
                }
                .disabled(text.isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func insertSpecialKey(_ key: SpecialKey) {
        switch key {
        case .tab:
            text += "\t"
        case .escape:
            // Send escape sequence
            text += "\u{1B}"
        case .ctrl:
            // Toggle ctrl mode - would need state management
            break
        case .up, .down, .left, .right:
            // Arrow keys - would send escape sequences
            break
        case .home, .end:
            // Home/End - would send escape sequences
            break
        }
    }
}

// MARK: - Special Keys Toolbar

struct SpecialKeysToolbar: View {
    let onKeyTap: (SpecialKey) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SpecialKey.allCases, id: \.self) { key in
                        Button {
                            onKeyTap(key)
                        } label: {
                            Text(key.displayName)
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.medium)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }

            // Done button to dismiss keyboard
            Button("Done") {
                onDismiss()
            }
            .fontWeight(.semibold)
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .background(.bar)
    }
}

enum SpecialKey: CaseIterable {
    case tab
    case escape
    case ctrl
    case up
    case down
    case left
    case right
    case home
    case end

    var displayName: String {
        switch self {
        case .tab: return "Tab"
        case .escape: return "Esc"
        case .ctrl: return "Ctrl"
        case .up: return "↑"
        case .down: return "↓"
        case .left: return "←"
        case .right: return "→"
        case .home: return "Home"
        case .end: return "End"
        }
    }
}

#Preview {
    struct Preview: View {
        @State var text = ""
        @FocusState var focused: Bool

        var body: some View {
            VStack {
                Spacer()
                TerminalInputBar(text: $text, isFocused: $focused) {
                    print("Submit: \(text)")
                }
            }
        }
    }

    return Preview()
}
