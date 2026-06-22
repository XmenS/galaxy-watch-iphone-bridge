import Foundation
import HealthKit

/// Server-side canonical health types. Must match the FastAPI `CANONICAL_TYPES` set.
enum CanonicalSampleType: String, CaseIterable, Codable {
    case steps
    case distance
    case activeEnergy           = "active_energy"
    case basalEnergy            = "basal_energy"
    case heartRate              = "heart_rate"
    case restingHeartRate       = "resting_heart_rate"
    case hrv
    case spo2
    case respiratoryRate        = "respiratory_rate"
    case bodyTemperature        = "body_temperature"
    case bloodPressureSystolic  = "blood_pressure_systolic"
    case bloodPressureDiastolic = "blood_pressure_diastolic"
    case bodyMass               = "body_mass"
    case bodyFatPercentage      = "body_fat_percentage"
    case leanBodyMass           = "lean_body_mass"
    case sleepInBed             = "sleep_in_bed"
    case sleepAwake             = "sleep_awake"
    case sleepLight             = "sleep_light"
    case sleepDeep              = "sleep_deep"
    case sleepRem               = "sleep_rem"
    case workout
    case mindfulMinutes         = "mindful_minutes"
    case standHours             = "stand_hours"
    case vo2Max                 = "vo2_max"
    case stressScore            = "stress_score"

    var healthKitWriteType: HKSampleType? {
        if let q = healthKitQuantityType { return q }
        if let c = healthKitCategoryType { return c }
        return nil
    }

    var healthKitReadType: HKObjectType? { healthKitWriteType }

    var healthKitQuantityType: HKQuantityType? {
        let id: HKQuantityTypeIdentifier?
        switch self {
        case .steps:                    id = .stepCount
        case .distance:                 id = .distanceWalkingRunning
        case .activeEnergy:             id = .activeEnergyBurned
        case .basalEnergy:              id = .basalEnergyBurned
        case .heartRate:                id = .heartRate
        case .restingHeartRate:         id = .restingHeartRate
        case .hrv:                      id = .heartRateVariabilitySDNN
        case .spo2:                     id = .oxygenSaturation
        case .respiratoryRate:          id = .respiratoryRate
        case .bodyTemperature:          id = .bodyTemperature
        case .bloodPressureSystolic:    id = .bloodPressureSystolic
        case .bloodPressureDiastolic:   id = .bloodPressureDiastolic
        case .bodyMass:                 id = .bodyMass
        case .bodyFatPercentage:        id = .bodyFatPercentage
        case .leanBodyMass:             id = .leanBodyMass
        case .vo2Max:                   id = .vo2Max
        default:                        id = nil
        }
        return id.flatMap { HKQuantityType.quantityType(forIdentifier: $0) }
    }

    var healthKitCategoryType: HKCategoryType? {
        let id: HKCategoryTypeIdentifier?
        switch self {
        case .sleepInBed, .sleepAwake, .sleepLight, .sleepDeep, .sleepRem:
            id = .sleepAnalysis
        case .mindfulMinutes:
            id = .mindfulSession
        default:
            id = nil
        }
        return id.flatMap { HKCategoryType.categoryType(forIdentifier: $0) }
    }

    var healthKitUnit: HKUnit? {
        switch self {
        case .steps:                  return .count()
        case .distance:               return .meter()
        case .activeEnergy, .basalEnergy: return .kilocalorie()
        case .heartRate, .restingHeartRate: return HKUnit(from: "count/min")
        case .hrv:                    return .secondUnit(with: .milli)
        case .spo2:                   return .percent()
        case .respiratoryRate:        return HKUnit(from: "count/min")
        case .bodyTemperature:        return .degreeCelsius()
        case .bloodPressureSystolic,
             .bloodPressureDiastolic: return .millimeterOfMercury()
        case .bodyMass, .leanBodyMass: return .gramUnit(with: .kilo)
        case .bodyFatPercentage:      return .percent()
        case .vo2Max:                 return HKUnit(from: "ml/(kg*min)")
        default:                      return nil
        }
    }

    var sleepCategoryValue: HKCategoryValueSleepAnalysis? {
        switch self {
        case .sleepInBed: return .inBed
        case .sleepAwake: return .awake
        case .sleepLight: return .asleepCore
        case .sleepDeep:  return .asleepDeep
        case .sleepRem:   return .asleepREM
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .steps:                  return "Steps"
        case .distance:               return "Distance"
        case .activeEnergy:           return "Active calories"
        case .basalEnergy:            return "Resting calories"
        case .heartRate:              return "Heart rate"
        case .restingHeartRate:       return "Resting heart rate"
        case .hrv:                    return "Heart rate variability"
        case .spo2:                   return "Blood oxygen"
        case .respiratoryRate:        return "Respiratory rate"
        case .bodyTemperature:        return "Body temperature"
        case .bloodPressureSystolic:  return "Systolic BP"
        case .bloodPressureDiastolic: return "Diastolic BP"
        case .bodyMass:               return "Weight"
        case .bodyFatPercentage:      return "Body fat"
        case .leanBodyMass:           return "Lean body mass"
        case .sleepInBed:             return "In bed"
        case .sleepAwake:             return "Awake"
        case .sleepLight:             return "Light sleep"
        case .sleepDeep:              return "Deep sleep"
        case .sleepRem:               return "REM sleep"
        case .workout:                return "Workout"
        case .mindfulMinutes:         return "Mindful minutes"
        case .standHours:             return "Stand hours"
        case .vo2Max:                 return "VO₂ max"
        case .stressScore:            return "Stress score"
        }
    }
}

struct CanonicalSample: Codable, Identifiable {
    var id: String { clientUid }
    let clientUid: String
    let source: String
    let type: CanonicalSampleType
    let unit: String?
    let value: Double?
    let startedAt: Date
    let endedAt: Date
    let metadata: [String: AnyCodable]
    let nonceB64: String?
    let ciphertextB64: String?

    enum CodingKeys: String, CodingKey {
        case clientUid = "client_uid"
        case source, type, unit, value
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case metadata
        case nonceB64 = "nonce_b64"
        case ciphertextB64 = "ciphertext_b64"
    }

    func toHKSample() -> HKSample? {
        if let q = type.healthKitQuantityType, let unit = type.healthKitUnit, let v = value {
            let quantity = HKQuantity(unit: unit, doubleValue: v)
            return HKQuantitySample(
                type: q, quantity: quantity, start: startedAt, end: endedAt,
                metadata: ["GHBSource": source, "GHBClientUid": clientUid]
            )
        }
        if let c = type.healthKitCategoryType, let val = type.sleepCategoryValue {
            return HKCategorySample(
                type: c, value: val.rawValue, start: startedAt, end: endedAt,
                metadata: ["GHBSource": source, "GHBClientUid": clientUid]
            )
        }
        return nil
    }
}

/// Tiny type-erased JSON value so metadata can survive encoding/decoding.
struct AnyCodable: Codable, Equatable {
    let value: Any
    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Bool.self)   { value = v; return }
        if let v = try? c.decode(Int.self)    { value = v; return }
        if let v = try? c.decode(Double.self) { value = v; return }
        if let v = try? c.decode(String.self) { value = v; return }
        if let v = try? c.decode([String: AnyCodable].self) { value = v; return }
        if let v = try? c.decode([AnyCodable].self) { value = v; return }
        value = NSNull()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let v as Bool: try c.encode(v)
        case let v as Int: try c.encode(v)
        case let v as Double: try c.encode(v)
        case let v as String: try c.encode(v)
        case let v as [String: AnyCodable]: try c.encode(v)
        case let v as [AnyCodable]: try c.encode(v)
        default: try c.encodeNil()
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }
}
