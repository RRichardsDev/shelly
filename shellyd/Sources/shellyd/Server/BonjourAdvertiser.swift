//
//  BonjourAdvertiser.swift
//  shellyd
//
//  Advertises the shellyd service via Bonjour for auto-discovery
//

import Foundation
import Network

final class BonjourAdvertiser {
    private var listener: NWListener?
    private let port: UInt16
    private let serviceName: String

    // Service type for Shelly daemon
    static let serviceType = "_shelly._tcp"

    init(port: Int, serviceName: String? = nil) {
        self.port = UInt16(port)
        self.serviceName = serviceName ?? Host.current().localizedName ?? "Mac"
    }

    func startAdvertising() throws {
        // Create a listener just for Bonjour advertisement
        // We use a different approach - NetService for advertisement only
        let service = NetService(
            domain: "local.",
            type: BonjourAdvertiser.serviceType,
            name: serviceName,
            port: Int32(port)
        )

        // Set TXT record with additional info
        let txtData: [String: Data] = [
            "version": "1.0.0".data(using: .utf8)!,
            "platform": "macOS".data(using: .utf8)!
        ]
        service.setTXTRecord(NetService.data(fromTXTRecord: txtData))

        service.delegate = BonjourDelegate.shared
        service.publish()

        BonjourDelegate.shared.service = service

        print("  📡 Bonjour: Advertising as '\(serviceName)'")
    }

    func stopAdvertising() {
        BonjourDelegate.shared.service?.stop()
        BonjourDelegate.shared.service = nil
    }
}

// MARK: - NetService Delegate

private class BonjourDelegate: NSObject, NetServiceDelegate {
    static let shared = BonjourDelegate()
    var service: NetService?

    func netServiceDidPublish(_ sender: NetService) {
        // Service published successfully
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        print("  ⚠️  Bonjour: Failed to publish service")
    }
}
