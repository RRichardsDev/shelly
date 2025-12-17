//
//  SHA1.swift
//  shellyd
//
//  SHA1 implementation for WebSocket accept key calculation
//

import Foundation
import CommonCrypto

enum SHA1 {
    static func hash(_ string: String) -> Data {
        let data = string.data(using: .utf8)!
        return hash(data)
    }

    static func hash(_ data: Data) -> Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_SHA1(ptr.baseAddress, CC_LONG(data.count), &digest)
        }
        return Data(digest)
    }
}

// WebSocket accept key calculation
func calculateWebSocketAcceptKey(_ key: String) -> String {
    let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    let combined = key + magic
    let hash = SHA1.hash(combined)
    return hash.base64EncodedString()
}
