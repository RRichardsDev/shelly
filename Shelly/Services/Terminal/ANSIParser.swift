//
//  ANSIParser.swift
//  Shelly
//
//  Parses and strips ANSI escape codes from terminal output
//

import Foundation

struct ANSIParser {

    /// Strip all ANSI escape codes from text
    static func stripEscapeCodes(_ text: String) -> String {
        var result = ""
        var iterator = text.makeIterator()

        while let char = iterator.next() {
            if char == "\u{1B}" { // ESC character
                // Check next character
                guard let next = iterator.next() else { break }

                switch next {
                case "[":
                    // CSI sequence: ESC [ ... (ends with letter)
                    skipCSISequence(&iterator)

                case "]":
                    // OSC sequence: ESC ] ... (ends with BEL or ST)
                    skipOSCSequence(&iterator)

                case "(", ")":
                    // Character set designation - skip one more char
                    _ = iterator.next()

                case "=", ">":
                    // Keypad mode - just the two chars
                    break

                default:
                    // Unknown escape, skip
                    break
                }
            } else if char == "\r" {
                // Carriage return - skip if followed by content (overwrites line)
                // For now, just skip standalone \r
                continue
            } else if char == "\u{07}" {
                // BEL character - skip
                continue
            } else {
                result.append(char)
            }
        }

        return result
    }

    /// Skip CSI (Control Sequence Introducer) sequence
    /// Format: ESC [ <params> <intermediate> <final>
    private static func skipCSISequence(_ iterator: inout String.Iterator) {
        while let char = iterator.next() {
            // CSI sequences end with a letter (@ to ~, ASCII 64-126)
            if char >= "@" && char <= "~" {
                break
            }
        }
    }

    /// Skip OSC (Operating System Command) sequence
    /// Format: ESC ] <code> ; <text> BEL  or  ESC ] <code> ; <text> ESC \
    private static func skipOSCSequence(_ iterator: inout String.Iterator) {
        var prevChar: Character = "\0"
        while let char = iterator.next() {
            // OSC ends with BEL (\x07) or ST (ESC \)
            if char == "\u{07}" {
                break
            }
            if prevChar == "\u{1B}" && char == "\\" {
                break
            }
            prevChar = char
        }
    }

    /// Clean up terminal output for display
    static func cleanOutput(_ text: String) -> String {
        var cleaned = stripEscapeCodes(text)

        // Remove excessive blank lines
        while cleaned.contains("\n\n\n") {
            cleaned = cleaned.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        // Trim leading/trailing whitespace from each line but preserve structure
        let lines = cleaned.components(separatedBy: "\n")
        let trimmedLines = lines.map { line -> String in
            // Only trim trailing whitespace, keep leading for indentation
            var result = line
            while result.hasSuffix(" ") || result.hasSuffix("\t") {
                result.removeLast()
            }
            return result
        }

        return trimmedLines.joined(separator: "\n")
    }
}
