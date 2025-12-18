//
//  BonjourBrowser.swift
//  Shelly
//
//  Discovers shellyd services on the local network via Bonjour
//

import Foundation
import Network
import Combine

/// Represents a discovered Shelly daemon on the network
struct DiscoveredHost: Identifiable, Hashable {
    let id: String
    let name: String
    let endpoint: NWEndpoint
    var host: String  // Resolved IP or hostname
    var port: Int
    var isResolved: Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DiscoveredHost, rhs: DiscoveredHost) -> Bool {
        lhs.id == rhs.id
    }
}

/// Browses for Shelly daemons via Bonjour
final class BonjourBrowser: NSObject, ObservableObject {
    static let shared = BonjourBrowser()

    private static let serviceType = "_shelly._tcp"

    @Published private(set) var discoveredHosts: [DiscoveredHost] = []
    @Published private(set) var isScanning = false

    private var browser: NWBrowser?
    private var netServices: [String: NetService] = [:]

    private override init() {
        super.init()
    }

    func startScanning() {
        guard !isScanning else { return }

        DispatchQueue.main.async {
            self.isScanning = true
            self.discoveredHosts = []
        }

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(
            for: .bonjour(type: BonjourBrowser.serviceType, domain: "local."),
            using: parameters
        )

        browser?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .failed(let error):
                    print("Browser failed: \(error)")
                    self?.isScanning = false
                case .cancelled:
                    self?.isScanning = false
                default:
                    break
                }
            }
        }

        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            self?.handleChanges(changes)
        }

        browser?.start(queue: .main)
    }

    func stopScanning() {
        browser?.cancel()
        browser = nil

        for service in netServices.values {
            service.stop()
        }
        netServices.removeAll()

        DispatchQueue.main.async {
            self.isScanning = false
        }
    }

    func refresh() {
        stopScanning()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.startScanning()
        }
    }

    private func handleChanges(_ changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case .added(let result):
                if case .service(let name, let type, let domain, _) = result.endpoint {
                    // Add host immediately
                    let host = DiscoveredHost(
                        id: name,
                        name: name,
                        endpoint: result.endpoint,
                        host: "\(name).local",  // Use mDNS name as fallback
                        port: 8765,
                        isResolved: false
                    )

                    DispatchQueue.main.async {
                        if !self.discoveredHosts.contains(where: { $0.id == name }) {
                            self.discoveredHosts.append(host)
                        }
                    }

                    // Resolve using NetService
                    let service = NetService(domain: domain, type: type, name: name)
                    service.delegate = self
                    netServices[name] = service
                    service.resolve(withTimeout: 5.0)
                }

            case .removed(let result):
                if case .service(let name, _, _, _) = result.endpoint {
                    netServices[name]?.stop()
                    netServices.removeValue(forKey: name)
                    DispatchQueue.main.async {
                        self.discoveredHosts.removeAll { $0.id == name }
                    }
                }

            default:
                break
            }
        }
    }
}

extension BonjourBrowser: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        let name = sender.name
        let port = sender.port

        // Get IP from addresses
        var ipAddress: String?
        if let addresses = sender.addresses {
            for data in addresses {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                data.withUnsafeBytes { ptr in
                    let sockaddr = ptr.baseAddress!.assumingMemoryBound(to: sockaddr.self)
                    getnameinfo(sockaddr, socklen_t(data.count),
                               &hostname, socklen_t(hostname.count),
                               nil, 0, NI_NUMERICHOST)
                }
                let ip = String(cString: hostname)
                // Prefer IPv4
                if !ip.contains(":") {
                    ipAddress = ip
                    break
                } else if ipAddress == nil {
                    ipAddress = ip
                }
            }
        }

        DispatchQueue.main.async {
            if let index = self.discoveredHosts.firstIndex(where: { $0.id == name }) {
                if let ip = ipAddress {
                    // Remove %interface suffix if present
                    let cleanIP = ip.split(separator: "%").first.map(String.init) ?? ip
                    self.discoveredHosts[index].host = cleanIP
                }
                self.discoveredHosts[index].port = port
                self.discoveredHosts[index].isResolved = true
            }
        }

        netServices.removeValue(forKey: name)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        // Still mark as resolved with mDNS name - it might still work
        DispatchQueue.main.async {
            if let index = self.discoveredHosts.firstIndex(where: { $0.id == sender.name }) {
                self.discoveredHosts[index].isResolved = true
            }
        }
        netServices.removeValue(forKey: sender.name)
    }
}
