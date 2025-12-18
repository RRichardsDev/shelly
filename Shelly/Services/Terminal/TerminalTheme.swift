//
//  TerminalTheme.swift
//  Shelly
//
//  Terminal color themes
//

import SwiftUI
import UIKit

struct TerminalTheme: Identifiable, Codable, Equatable {
    let id: String
    let name: String

    // Basic colors
    let background: CodableColor
    let foreground: CodableColor
    let cursor: CodableColor

    // ANSI 16 colors
    let black: CodableColor
    let red: CodableColor
    let green: CodableColor
    let yellow: CodableColor
    let blue: CodableColor
    let magenta: CodableColor
    let cyan: CodableColor
    let white: CodableColor

    let brightBlack: CodableColor
    let brightRed: CodableColor
    let brightGreen: CodableColor
    let brightYellow: CodableColor
    let brightBlue: CodableColor
    let brightMagenta: CodableColor
    let brightCyan: CodableColor
    let brightWhite: CodableColor

    var uiColors: [UIColor] {
        [
            black.uiColor, red.uiColor, green.uiColor, yellow.uiColor,
            blue.uiColor, magenta.uiColor, cyan.uiColor, white.uiColor,
            brightBlack.uiColor, brightRed.uiColor, brightGreen.uiColor, brightYellow.uiColor,
            brightBlue.uiColor, brightMagenta.uiColor, brightCyan.uiColor, brightWhite.uiColor
        ]
    }
}

// MARK: - Codable Color

struct CodableColor: Codable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") {
            hexString.removeFirst()
        }

        var rgb: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgb)

        self.red = Double((rgb >> 16) & 0xFF) / 255.0
        self.green = Double((rgb >> 8) & 0xFF) / 255.0
        self.blue = Double(rgb & 0xFF) / 255.0
        self.alpha = 1.0
    }

    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}

// MARK: - Preset Themes

extension TerminalTheme {
    static let system = TerminalTheme(
        id: "system",
        name: "System",
        background: CodableColor(0.1, 0.1, 0.1),
        foreground: CodableColor(0.9, 0.9, 0.9),
        cursor: CodableColor(1.0, 1.0, 1.0),
        black: CodableColor(0.0, 0.0, 0.0),
        red: CodableColor(0.8, 0.0, 0.0),
        green: CodableColor(0.0, 0.8, 0.0),
        yellow: CodableColor(0.8, 0.8, 0.0),
        blue: CodableColor(0.0, 0.0, 0.8),
        magenta: CodableColor(0.8, 0.0, 0.8),
        cyan: CodableColor(0.0, 0.8, 0.8),
        white: CodableColor(0.8, 0.8, 0.8),
        brightBlack: CodableColor(0.5, 0.5, 0.5),
        brightRed: CodableColor(1.0, 0.0, 0.0),
        brightGreen: CodableColor(0.0, 1.0, 0.0),
        brightYellow: CodableColor(1.0, 1.0, 0.0),
        brightBlue: CodableColor(0.0, 0.0, 1.0),
        brightMagenta: CodableColor(1.0, 0.0, 1.0),
        brightCyan: CodableColor(0.0, 1.0, 1.0),
        brightWhite: CodableColor(1.0, 1.0, 1.0)
    )

    static let solarizedDark = TerminalTheme(
        id: "solarized-dark",
        name: "Solarized Dark",
        background: CodableColor(hex: "#002b36"),
        foreground: CodableColor(hex: "#839496"),
        cursor: CodableColor(hex: "#93a1a1"),
        black: CodableColor(hex: "#073642"),
        red: CodableColor(hex: "#dc322f"),
        green: CodableColor(hex: "#859900"),
        yellow: CodableColor(hex: "#b58900"),
        blue: CodableColor(hex: "#268bd2"),
        magenta: CodableColor(hex: "#d33682"),
        cyan: CodableColor(hex: "#2aa198"),
        white: CodableColor(hex: "#eee8d5"),
        brightBlack: CodableColor(hex: "#002b36"),
        brightRed: CodableColor(hex: "#cb4b16"),
        brightGreen: CodableColor(hex: "#586e75"),
        brightYellow: CodableColor(hex: "#657b83"),
        brightBlue: CodableColor(hex: "#839496"),
        brightMagenta: CodableColor(hex: "#6c71c4"),
        brightCyan: CodableColor(hex: "#93a1a1"),
        brightWhite: CodableColor(hex: "#fdf6e3")
    )

    static let dracula = TerminalTheme(
        id: "dracula",
        name: "Dracula",
        background: CodableColor(hex: "#282a36"),
        foreground: CodableColor(hex: "#f8f8f2"),
        cursor: CodableColor(hex: "#f8f8f2"),
        black: CodableColor(hex: "#21222c"),
        red: CodableColor(hex: "#ff5555"),
        green: CodableColor(hex: "#50fa7b"),
        yellow: CodableColor(hex: "#f1fa8c"),
        blue: CodableColor(hex: "#bd93f9"),
        magenta: CodableColor(hex: "#ff79c6"),
        cyan: CodableColor(hex: "#8be9fd"),
        white: CodableColor(hex: "#f8f8f2"),
        brightBlack: CodableColor(hex: "#6272a4"),
        brightRed: CodableColor(hex: "#ff6e6e"),
        brightGreen: CodableColor(hex: "#69ff94"),
        brightYellow: CodableColor(hex: "#ffffa5"),
        brightBlue: CodableColor(hex: "#d6acff"),
        brightMagenta: CodableColor(hex: "#ff92df"),
        brightCyan: CodableColor(hex: "#a4ffff"),
        brightWhite: CodableColor(hex: "#ffffff")
    )

    static let monokai = TerminalTheme(
        id: "monokai",
        name: "Monokai",
        background: CodableColor(hex: "#272822"),
        foreground: CodableColor(hex: "#f8f8f2"),
        cursor: CodableColor(hex: "#f8f8f0"),
        black: CodableColor(hex: "#272822"),
        red: CodableColor(hex: "#f92672"),
        green: CodableColor(hex: "#a6e22e"),
        yellow: CodableColor(hex: "#f4bf75"),
        blue: CodableColor(hex: "#66d9ef"),
        magenta: CodableColor(hex: "#ae81ff"),
        cyan: CodableColor(hex: "#a1efe4"),
        white: CodableColor(hex: "#f8f8f2"),
        brightBlack: CodableColor(hex: "#75715e"),
        brightRed: CodableColor(hex: "#f92672"),
        brightGreen: CodableColor(hex: "#a6e22e"),
        brightYellow: CodableColor(hex: "#f4bf75"),
        brightBlue: CodableColor(hex: "#66d9ef"),
        brightMagenta: CodableColor(hex: "#ae81ff"),
        brightCyan: CodableColor(hex: "#a1efe4"),
        brightWhite: CodableColor(hex: "#f9f8f5")
    )

    static let nord = TerminalTheme(
        id: "nord",
        name: "Nord",
        background: CodableColor(hex: "#2e3440"),
        foreground: CodableColor(hex: "#d8dee9"),
        cursor: CodableColor(hex: "#d8dee9"),
        black: CodableColor(hex: "#3b4252"),
        red: CodableColor(hex: "#bf616a"),
        green: CodableColor(hex: "#a3be8c"),
        yellow: CodableColor(hex: "#ebcb8b"),
        blue: CodableColor(hex: "#81a1c1"),
        magenta: CodableColor(hex: "#b48ead"),
        cyan: CodableColor(hex: "#88c0d0"),
        white: CodableColor(hex: "#e5e9f0"),
        brightBlack: CodableColor(hex: "#4c566a"),
        brightRed: CodableColor(hex: "#bf616a"),
        brightGreen: CodableColor(hex: "#a3be8c"),
        brightYellow: CodableColor(hex: "#ebcb8b"),
        brightBlue: CodableColor(hex: "#81a1c1"),
        brightMagenta: CodableColor(hex: "#b48ead"),
        brightCyan: CodableColor(hex: "#8fbcbb"),
        brightWhite: CodableColor(hex: "#eceff4")
    )

    static let allThemes: [TerminalTheme] = [
        .system, .solarizedDark, .dracula, .monokai, .nord
    ]
}

// MARK: - Theme Manager

@Observable
class TerminalThemeManager {
    static let shared = TerminalThemeManager()

    var currentTheme: TerminalTheme {
        didSet {
            saveTheme()
        }
    }

    private let defaultsKey = "selectedTerminalTheme"

    private init() {
        if let themeId = UserDefaults.standard.string(forKey: defaultsKey),
           let theme = TerminalTheme.allThemes.first(where: { $0.id == themeId }) {
            currentTheme = theme
        } else {
            currentTheme = .system
        }
    }

    private func saveTheme() {
        UserDefaults.standard.set(currentTheme.id, forKey: defaultsKey)
    }
}
