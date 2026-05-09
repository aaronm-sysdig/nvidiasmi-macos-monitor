import AppKit
import Foundation
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {

    static let serverHost = "your-server-host"  // Change to your server's address (e.g. "gpu-server.local")
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var popover: NSPopover?
    private var trustDelegate: TrustIgnoringDelegate?
    private var session: URLSession?

    // Circular buffer of readings (max 10), all access on main queue
    private var readings: [Reading] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up URLSession with trust-ignoring delegate
        trustDelegate = TrustIgnoringDelegate()
        let config = URLSessionConfiguration.default
        config.urlCredentialStorage = nil
        session = URLSession(configuration: config, delegate: trustDelegate, delegateQueue: nil)

        // Set up status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = "? W"
            button.target = self
            button.action = #selector(statusBarClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Start polling
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.fetchMetrics()
        }
        fetchMetrics()
    }

    deinit {
        timer?.invalidate()
        session?.invalidateAndCancel()
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
    }

    @objc private func statusBarClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        // Right-click or Control-click → quit menu
        if event.type == .rightMouseUp || NSEvent.modifierFlags.contains(.control) {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            return
        }

        // Left-click → toggle popover
        if popover?.isShown == true {
            popover?.close()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        if popover == nil {
            popover = NSPopover()
            popover?.contentSize = CGSize(width: 280, height: 320)
            popover?.behavior = .transient
            popover?.animates = true
        }

        let latestReading = readings.last
        let history = readings

        let hostingController = NSHostingController(rootView: PopoverContent(reading: latestReading, history: history))
        popover?.contentViewController = hostingController

        if let button = statusItem?.button {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        }
    }

    private func fetchMetrics() {
        guard let button = statusItem?.button else { return }
        let url = URL(string: "https://\(Self.serverHost):9090/v1/metrics")!

        session?.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                if let error = error {
                    print("[GPUWatts] error: \(error.localizedDescription)")
                    button.title = "ERR"
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    print("[GPUWatts] non-200 response")
                    button.title = "ERR"
                    return
                }

                guard let data = data else {
                    print("[GPUWatts] no data")
                    button.title = "ERR"
                    return
                }

                do {
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    guard let gpusArray = json?["gpus"] as? [[String: Any]],
                          let totalWatts = json?["total_watts"] as? Int else {
                        print("[GPUWatts] JSON parse failed")
                        button.title = "ERR"
                        return
                    }

                    // Decode GPU metrics manually (avoid full Codable for flexibility)
                    var metrics: [GPUMetric] = []
                    for gpuJson in gpusArray {
                        metrics.append(GPUMetric(
                            id: gpuJson["id"] as? Int ?? 0,
                            name: gpuJson["name"] as? String ?? "GPU",
                            powerWatts: gpuJson["power_watts"] as? Int ?? 0,
                            powerLimitWatts: gpuJson["power_limit_watts"] as? Int ?? 0,
                            temperatureC: gpuJson["temperature_c"] as? Int ?? 0,
                            fanPct: gpuJson["fan_pct"] as? Int ?? 0,
                            utilizationGpu: gpuJson["utilization_gpu"] as? Int ?? 0,
                            utilizationMem: gpuJson["utilization_mem"] as? Int ?? 0
                        ))
                    }

                    let reading = Reading(date: Date(), gpus: metrics, totalWatts: totalWatts)
                    self.readings.append(reading)
                    if self.readings.count > 10 {
                        self.readings.removeFirst()
                    }

                    button.title = "\(totalWatts) W"
                    print("[GPUWatts] updated: \(totalWatts) W (\(metrics.count) GPUs)")
                } catch {
                    print("[GPUWatts] decode error: \(error)")
                    button.title = "ERR"
                }
            }
        }.resume()
    }
}
