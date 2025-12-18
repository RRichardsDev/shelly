//
//  ANSIRenderer.swift
//  Shelly
//
//  Renders ANSI escape codes as styled attributed strings
//

import Foundation
import UIKit

struct ANSIRenderer {

    // Get colors from current theme or use defaults
    static var colors: [UIColor] {
        TerminalThemeManager.shared.currentTheme.uiColors
    }

    // Default ANSI color palette (fallback)
    static let defaultColors: [UIColor] = [
        UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0),       // 0: Black
        UIColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0),       // 1: Red
        UIColor(red: 0.0, green: 0.8, blue: 0.0, alpha: 1.0),       // 2: Green
        UIColor(red: 0.8, green: 0.8, blue: 0.0, alpha: 1.0),       // 3: Yellow
        UIColor(red: 0.0, green: 0.0, blue: 0.8, alpha: 1.0),       // 4: Blue
        UIColor(red: 0.8, green: 0.0, blue: 0.8, alpha: 1.0),       // 5: Magenta
        UIColor(red: 0.0, green: 0.8, blue: 0.8, alpha: 1.0),       // 6: Cyan
        UIColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0),       // 7: White
        // Bright colors
        UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0),       // 8: Bright Black
        UIColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0),       // 9: Bright Red
        UIColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0),       // 10: Bright Green
        UIColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0),       // 11: Bright Yellow
        UIColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0),       // 12: Bright Blue
        UIColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0),       // 13: Bright Magenta
        UIColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 1.0),       // 14: Bright Cyan
        UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),       // 15: Bright White
    ]

    struct TextStyle {
        var foregroundColor: UIColor?
        var backgroundColor: UIColor?
        var bold: Bool = false
        var italic: Bool = false
        var underline: Bool = false
        var inverse: Bool = false

        static let `default` = TextStyle()
    }

    /// Render text with ANSI codes to attributed string
    static func render(_ text: String, defaultForeground: UIColor, defaultBackground: UIColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var currentStyle = TextStyle()
        var buffer = ""
        var i = 0
        let chars = Array(text)
        let count = chars.count

        func flushBuffer() {
            if !buffer.isEmpty {
                let attrs = attributesFor(style: currentStyle, defaultFg: defaultForeground, defaultBg: defaultBackground)
                result.append(NSAttributedString(string: buffer, attributes: attrs))
                buffer = ""
            }
        }

        while i < count {
            let char = chars[i]

            if char == "\u{1B}" && i + 1 < count {
                let next = chars[i + 1]

                if next == "[" {
                    flushBuffer()
                    i += 2 // Skip ESC [
                    // Parse CSI sequence
                    var params: [Int] = []
                    var currentParam = ""
                    var foundEnd = false

                    while i < count {
                        let c = chars[i]
                        if c >= "0" && c <= "9" {
                            currentParam.append(c)
                            i += 1
                        } else if c == ";" {
                            params.append(Int(currentParam) ?? 0)
                            currentParam = ""
                            i += 1
                        } else if c >= "@" && c <= "~" {
                            // End of sequence
                            if !currentParam.isEmpty {
                                params.append(Int(currentParam) ?? 0)
                            }
                            if c == "m" {
                                applyCSI(params: params, to: &currentStyle)
                            }
                            // Other CSI commands (J, K, H, etc.) - just skip
                            i += 1
                            foundEnd = true
                            break
                        } else {
                            // Invalid character in CSI sequence, bail
                            i += 1
                            foundEnd = true
                            break
                        }
                    }
                    if !foundEnd {
                        // Reached end of string without finding terminator
                        break
                    }
                } else if next == "]" {
                    // OSC sequence - skip until BEL or ST
                    i += 2
                    while i < count {
                        if chars[i] == "\u{07}" {
                            i += 1
                            break
                        } else if chars[i] == "\u{1B}" && i + 1 < count && chars[i + 1] == "\\" {
                            i += 2
                            break
                        }
                        i += 1
                    }
                } else if next == "(" || next == ")" {
                    // Charset designation - skip 3 chars total
                    i += 3
                } else if next == "=" || next == ">" {
                    // Keypad mode
                    i += 2
                } else {
                    // Unknown escape, skip ESC
                    i += 1
                }
            } else if char == "\u{07}" {
                // BEL - skip
                i += 1
            } else {
                buffer.append(char)
                i += 1
            }
        }

        flushBuffer()
        return result
    }

    private static func applyCSI(params: [Int], to style: inout TextStyle) {
        if params.isEmpty {
            style = .default
            return
        }

        var i = 0
        while i < params.count {
            let code = params[i]

            switch code {
            case 0:
                style = .default
            case 1:
                style.bold = true
            case 3:
                style.italic = true
            case 4:
                style.underline = true
            case 7:
                style.inverse = true
            case 22:
                style.bold = false
            case 23:
                style.italic = false
            case 24:
                style.underline = false
            case 27:
                style.inverse = false
            case 30...37:
                style.foregroundColor = colors[code - 30]
            case 38:
                // Extended foreground color
                if i + 2 < params.count && params[i + 1] == 5 {
                    let colorIndex = params[i + 2]
                    style.foregroundColor = color256(colorIndex)
                    i += 2
                }
            case 39:
                style.foregroundColor = nil
            case 40...47:
                style.backgroundColor = colors[code - 40]
            case 48:
                // Extended background color
                if i + 2 < params.count && params[i + 1] == 5 {
                    let colorIndex = params[i + 2]
                    style.backgroundColor = color256(colorIndex)
                    i += 2
                }
            case 49:
                style.backgroundColor = nil
            case 90...97:
                style.foregroundColor = colors[code - 90 + 8]
            case 100...107:
                style.backgroundColor = colors[code - 100 + 8]
            default:
                break
            }

            i += 1
        }
    }

    private static func color256(_ index: Int) -> UIColor {
        if index < 16 {
            return colors[index]
        } else if index < 232 {
            // 216 color cube
            let idx = index - 16
            let r = CGFloat((idx / 36) % 6) / 5.0
            let g = CGFloat((idx / 6) % 6) / 5.0
            let b = CGFloat(idx % 6) / 5.0
            return UIColor(red: r, green: g, blue: b, alpha: 1.0)
        } else {
            // Grayscale
            let gray = CGFloat(index - 232) / 23.0
            return UIColor(white: gray, alpha: 1.0)
        }
    }

    private static func attributesFor(style: TextStyle, defaultFg: UIColor, defaultBg: UIColor) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [:]

        let font: UIFont
        if style.bold {
            font = UIFont.monospacedSystemFont(ofSize: 14, weight: .bold)
        } else {
            font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        }
        attrs[.font] = font

        var fg = style.foregroundColor ?? defaultFg
        var bg = style.backgroundColor

        if style.inverse {
            let temp = fg
            fg = bg ?? defaultBg
            bg = temp
        }

        attrs[.foregroundColor] = fg
        if let bg = bg {
            attrs[.backgroundColor] = bg
        }

        if style.underline {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }

        return attrs
    }
}
