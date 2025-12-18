//
//  ShellyPairingUI.swift
//  ShellyPairingUI
//
//  Displays pairing code in Apple-style UI
//  Usage: ShellyPairingUI "Device Name" "123456"
//

import SwiftUI
import AppKit

@main
struct ShellyPairingUIApp: App {
    @State private var deviceName: String
    @State private var code: String
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        let args = CommandLine.arguments
        if args.count >= 3 {
            _deviceName = State(initialValue: args[1])
            _code = State(initialValue: args[2])
        } else {
            _deviceName = State(initialValue: "iPhone")
            _code = State(initialValue: "000000")
        }
    }

    var body: some Scene {
        WindowGroup {
            PairingView(deviceName: deviceName, code: code)
                .onAppear {
                    // Bring window to front when it appears - above ALL other windows
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    if let window = NSApplication.shared.windows.first {
                        window.level = .statusBar  // Above almost everything
                        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                        window.makeKeyAndOrderFront(nil)
                        window.orderFrontRegardless()
                        window.center()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Force app to be a regular foreground app
        NSApp.setActivationPolicy(.regular)

        // Activate forcefully
        NSApplication.shared.activate(ignoringOtherApps: true)

        // Delay and activate again to ensure it comes to front
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            if let window = NSApplication.shared.windows.first {
                window.level = .screenSaver
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

struct PairingView: View {
    let deviceName: String
    let code: String
    @Environment(\.dismiss) private var dismiss

    var codeDigits: [String] {
        Array(code).map { String($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with icon
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)

                    Image(systemName: "iphone")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(.white)
                }
                .shadow(color: .blue.opacity(0.3), radius: 10, y: 5)

                VStack(spacing: 6) {
                    Text("Pairing Request")
                        .font(.system(size: 24, weight: .semibold))

                    Text(deviceName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 40)
            .padding(.bottom, 24)

            // Instruction
            Text("Enter this code on your iPhone")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)

            // Code display - big digits in boxes
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    DigitBox(digit: codeDigits.indices.contains(index) ? codeDigits[index] : "0")
                }

                // Separator
                Text("—")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.quaternary)
                    .padding(.horizontal, 4)

                ForEach(3..<6, id: \.self) { index in
                    DigitBox(digit: codeDigits.indices.contains(index) ? codeDigits[index] : "0")
                }
            }
            .padding(.bottom, 32)

            // Info text
            Text("Make sure this is your device before entering the code.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)

            Divider()

            // Dismiss button
            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Text("Done")
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.vertical, 20)
        }
        .frame(width: 420)
        .padding(.horizontal, 8)
        .background(Color(.windowBackgroundColor))
    }
}

struct DigitBox: View {
    let digit: String

    var body: some View {
        Text(digit)
            .font(.system(size: 44, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .frame(width: 52, height: 68)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.textBackgroundColor))
                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
    }
}

#Preview {
    PairingView(deviceName: "Rhodri's iPhone", code: "482951")
}
