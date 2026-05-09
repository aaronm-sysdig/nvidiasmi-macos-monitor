import SwiftUI

struct PopoverContent: View {
    let reading: Reading?
    let history: [Reading]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            Text("GPU Watts")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            if let reading {
                // Total watts — prominent
                HStack {
                    Text("Total:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(reading.totalWatts) W")
                        .font(.title2)
                        .fontWeight(.bold)
                }

                Divider()

                // Per-GPU rows
                ForEach(reading.gpus, id: \.id) { gpu in
                    VStack(alignment: .leading, spacing: 2) {
                        // GPU name row
                        HStack {
                            Text("GPU \(gpu.id)")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text(gpu.name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        // Primary metrics
                        HStack {
                            Text("⚡ \(gpu.powerWatts) W")
                                .font(.caption)
                            Spacer()
                            Text("🌡 \(gpu.temperatureC)°C")
                                .font(.caption)
                        }
                        // Secondary metrics
                        HStack {
                            Text("🌀 \(gpu.fanPct)%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("📊 \(gpu.utilizationGpu)%")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }

                Divider()

                // Sparkline + history
                VStack(alignment: .leading, spacing: 4) {
                    SparklineView(values: history.map { $0.totalWatts })
                    ForEach(Array(history.reversed().prefix(10))) { r in
                        let time = DateFormatter.timeFormatter.string(from: r.date)
                        let gpuStr = r.gpus.map { "\($0.powerWatts)" }.joined(separator: ",")
                        Text("\(time)  \(gpuStr)=\(r.totalWatts) W")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                // Loading state
                Text("Loading...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}

// MARK: - Helpers
private extension DateFormatter {
    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
