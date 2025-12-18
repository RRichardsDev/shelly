//
//  ShellyInstallerApp.swift
//  ShellyInstaller
//
//  macOS installer for shellyd daemon
//

import SwiftUI

@main
struct ShellyInstallerApp: App {
    var body: some Scene {
        WindowGroup {
            InstallerView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

struct InstallerView: View {
    @State private var installState: InstallState = .checking
    @State private var logs: [String] = []
    @State private var isWorking = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)
                
                Text("Shelly")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Remote terminal access for your Mac")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)
            .padding(.bottom, 30)
            
            Divider()
            
            // Status
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 12, height: 12)
                    
                    Text(statusText)
                        .font(.headline)
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 20)
                
                // Info cards
                if installState == .installed || installState == .running {
                    VStack(alignment: .leading, spacing: 8) {
                        InfoRow(label: "Binary", value: "/usr/local/bin/shellyd")
                        InfoRow(label: "Config", value: "~/.shellyd/config.json")
                        InfoRow(label: "Port", value: "8765")
                        InfoRow(label: "Logs", value: "~/Library/Logs/shellyd.log")
                    }
                    .padding()
                    .background(Color(.windowBackgroundColor))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
                
                // Log output
                if !logs.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(logs, id: \.self) { log in
                                Text(log)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 100)
                    .padding(8)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(6)
                    .padding(.horizontal)
                }
            }
            
            Spacer()
            
            Divider()
            
            // Buttons
            HStack(spacing: 12) {
                if installState == .installed || installState == .running {
                    Button("Uninstall") {
                        uninstall()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isWorking)
                }
                
                Spacer()
                
                if installState == .running {
                    Button("Stop Daemon") {
                        stopDaemon()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isWorking)
                } else if installState == .installed {
                    Button("Start Daemon") {
                        startDaemon()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking)
                } else if installState == .notInstalled {
                    Button("Install") {
                        install()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking)
                } else if installState == .checking {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding()
        }
        .frame(width: 450, height: 500)
        .onAppear {
            checkStatus()
        }
    }
    
    private var statusColor: Color {
        switch installState {
        case .checking: return .gray
        case .notInstalled: return .orange
        case .installed: return .yellow
        case .running: return .green
        case .error: return .red
        }
    }
    
    private var statusText: String {
        switch installState {
        case .checking: return "Checking status..."
        case .notInstalled: return "Not installed"
        case .installed: return "Installed (not running)"
        case .running: return "Running"
        case .error(let msg): return "Error: \(msg)"
        }
    }
    
    private func checkStatus() {
        installState = .checking
        
        Task {
            // Check if binary exists
            let binaryExists = FileManager.default.fileExists(atPath: "/usr/local/bin/shellyd")
            
            if !binaryExists {
                await MainActor.run { installState = .notInstalled }
                return
            }
            
            // Check if running
            let isRunning = await shell("pgrep -x shellyd").exitCode == 0
            
            await MainActor.run {
                installState = isRunning ? .running : .installed
            }
        }
    }
    
    private func install() {
        isWorking = true
        logs = []

        Task {
            await log("Starting installation...")

            // Find binaries bundled inside the app
            guard let resources = findBundledResources() else {
                await log("❌ Could not find bundled binaries.")
                await log("   The app bundle may be corrupted.")
                await MainActor.run {
                    installState = .error("Binaries not found")
                    isWorking = false
                }
                return
            }

            let shellydPath = resources.shellyd
            let pairingUIAppPath = resources.pairingUI

            // Remove quarantine attributes first (doesn't need admin)
            await log("🔓 Removing quarantine flags...")
            _ = await shell("xattr -cr \"\(shellydPath)\" 2>/dev/null")
            _ = await shell("xattr -cr \"\(pairingUIAppPath)\" 2>/dev/null")

            await log("📁 Installing daemon (requires password)...")

            // Copy to a temp location first, then move with admin
            let tempDir = NSTemporaryDirectory()
            let tempShellyd = tempDir + "shellyd"

            // Copy to temp (no admin needed)
            try? FileManager.default.removeItem(atPath: tempShellyd)
            try? FileManager.default.copyItem(atPath: shellydPath, toPath: tempShellyd)

            let installCmd = "mv \"\(tempShellyd)\" /usr/local/bin/shellyd && chmod +x /usr/local/bin/shellyd"

            let installResult = await shellWithAdmin(installCmd)

            // Install pairing UI app bundle to ~/.shellyd/ (no admin needed)
            let shellyDir = NSHomeDirectory() + "/.shellyd"
            try? FileManager.default.createDirectory(atPath: shellyDir, withIntermediateDirectories: true)
            let pairingUIDestPath = shellyDir + "/ShellyPairingUI.app"
            if FileManager.default.fileExists(atPath: pairingUIAppPath) {
                try? FileManager.default.removeItem(atPath: pairingUIDestPath)
                try? FileManager.default.copyItem(atPath: pairingUIAppPath, toPath: pairingUIDestPath)
                await log("✅ Pairing UI installed")
            }
            if installResult.exitCode != 0 {
                await log("❌ Install failed: \(installResult.output)")
                await MainActor.run {
                    installState = .error("Install failed")
                    isWorking = false
                }
                return
            }
            await log("✅ Binaries installed")
            
            // Create config directory
            let configDir = NSHomeDirectory() + "/.shellyd"
            try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
            
            // Create default config
            let configPath = configDir + "/config.json"
            if !FileManager.default.fileExists(atPath: configPath) {
                let config = """
                {
                    "port": 8765,
                    "shell": "/bin/zsh",
                    "verbose": false
                }
                """
                try? config.write(toFile: configPath, atomically: true, encoding: .utf8)
                await log("⚙️ Created config file")
            }
            
            // Create authorized_keys
            let keysPath = configDir + "/authorized_keys"
            if !FileManager.default.fileExists(atPath: keysPath) {
                FileManager.default.createFile(atPath: keysPath, contents: nil)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keysPath)
                await log("🔑 Created authorized_keys")
            }
            
            // Setup launchd
            await log("🚀 Setting up auto-start...")
            await setupLaunchd()
            
            await log("✅ Installation complete!")

            // Clear logs after a short delay
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            await MainActor.run {
                logs = []
                isWorking = false
                checkStatus()
            }
        }
    }
    
    private func uninstall() {
        isWorking = true
        logs = []
        
        Task {
            await log("Stopping daemon...")
            let launchdPath = NSHomeDirectory() + "/Library/LaunchAgents/com.shelly.daemon.plist"
            _ = await shell("launchctl unload '\(launchdPath)' 2>/dev/null")
            _ = await shell("pkill -x shellyd 2>/dev/null")
            
            await log("Removing launchd plist...")
            try? FileManager.default.removeItem(atPath: launchdPath)
            
            await log("Removing daemon (requires password)...")
            _ = await shellWithAdmin("rm -f /usr/local/bin/shellyd")

            // Remove pairing UI app bundle (no admin needed)
            let pairingUIPath = NSHomeDirectory() + "/.shellyd/ShellyPairingUI.app"
            try? FileManager.default.removeItem(atPath: pairingUIPath)
            
            await log("")
            await log("✅ Uninstalled! Config at ~/.shellyd/ was kept.")
            
            await MainActor.run {
                isWorking = false
                checkStatus()
            }
        }
    }
    
    private func startDaemon() {
        Task {
            let launchdPath = NSHomeDirectory() + "/Library/LaunchAgents/com.shelly.daemon.plist"
            _ = await shell("launchctl load '\(launchdPath)'")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            checkStatus()
        }
    }
    
    private func stopDaemon() {
        Task {
            let launchdPath = NSHomeDirectory() + "/Library/LaunchAgents/com.shelly.daemon.plist"
            _ = await shell("launchctl unload '\(launchdPath)' 2>/dev/null")
            _ = await shell("pkill -x shellyd 2>/dev/null")
            try? await Task.sleep(nanoseconds: 500_000_000)
            checkStatus()
        }
    }
    
    private func setupLaunchd() async {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.shelly.daemon</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/local/bin/shellyd</string>
                <string>start</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardOutPath</key>
            <string>\(NSHomeDirectory())/Library/Logs/shellyd.log</string>
            <key>StandardErrorPath</key>
            <string>\(NSHomeDirectory())/Library/Logs/shellyd.error.log</string>
        </dict>
        </plist>
        """
        
        let launchAgentsDir = NSHomeDirectory() + "/Library/LaunchAgents"
        try? FileManager.default.createDirectory(atPath: launchAgentsDir, withIntermediateDirectories: true)
        
        let plistPath = launchAgentsDir + "/com.shelly.daemon.plist"
        
        // Unload existing
        _ = await shell("launchctl unload '\(plistPath)' 2>/dev/null")
        
        // Write new plist
        try? plist.write(toFile: plistPath, atomically: true, encoding: .utf8)
        
        // Load
        _ = await shell("launchctl load '\(plistPath)'")
    }
    
    private func findBundledResources() -> (shellyd: String, pairingUI: String)? {
        // Look for binaries bundled inside the app's Resources folder
        guard let resourcePath = Bundle.main.resourcePath else { return nil }

        let shellydPath = (resourcePath as NSString).appendingPathComponent("shellyd")
        let pairingUIPath = (resourcePath as NSString).appendingPathComponent("ShellyPairingUI.app")

        if FileManager.default.fileExists(atPath: shellydPath) {
            return (shellydPath, pairingUIPath)
        }

        return nil
    }
    
    private func log(_ message: String) async {
        await MainActor.run {
            logs.append(message)
        }
    }
    
    private func shell(_ command: String) async -> (output: String, exitCode: Int32) {
        let task = Process()
        let pipe = Pipe()
        
        task.standardOutput = pipe
        task.standardError = pipe
        task.launchPath = "/bin/zsh"
        task.arguments = ["-c", command]
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            return (output, task.terminationStatus)
        } catch {
            return (error.localizedDescription, 1)
        }
    }
    
    private func shellWithAdmin(_ command: String) async -> (output: String, exitCode: Int32) {
        // Escape for AppleScript: escape backslashes first, then double quotes
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "'", with: "'\\''")

        let script = "do shell script \"\(escaped)\" with administrator privileges"

        let task = Process()
        let pipe = Pipe()

        task.standardOutput = pipe
        task.standardError = pipe
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            return (output, task.terminationStatus)
        } catch {
            return (error.localizedDescription, 1)
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}

enum InstallState: Equatable {
    case checking
    case notInstalled
    case installed
    case running
    case error(String)
}
