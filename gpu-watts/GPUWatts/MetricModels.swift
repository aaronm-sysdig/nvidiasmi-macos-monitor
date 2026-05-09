import Foundation

struct GPUMetric: Codable {
    let id: Int
    let name: String
    let powerWatts: Int
    let powerLimitWatts: Int
    let temperatureC: Int
    let fanPct: Int
    let utilizationGpu: Int
    let utilizationMem: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case powerWatts = "power_watts"
        case powerLimitWatts = "power_limit_watts"
        case temperatureC = "temperature_c"
        case fanPct = "fan_pct"
        case utilizationGpu = "utilization_gpu"
        case utilizationMem = "utilization_mem"
    }
}

struct Reading: Codable, Identifiable {
    let id = UUID()
    let date: Date
    let gpus: [GPUMetric]
    let totalWatts: Int

    enum CodingKeys: String, CodingKey {
        case gpus
        case totalWatts = "total_watts"
    }

    init(date: Date, gpus: [GPUMetric], totalWatts: Int) {
        self.date = date
        self.gpus = gpus
        self.totalWatts = totalWatts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gpus = try container.decode([GPUMetric].self, forKey: .gpus)
        totalWatts = try container.decode(Int.self, forKey: .totalWatts)
        // No timestamp in the server response — we use local fetch time
        self.date = Date()
    }
}
