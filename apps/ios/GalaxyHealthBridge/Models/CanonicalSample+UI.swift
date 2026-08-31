import SwiftUI

extension CanonicalSampleType {

    var iconName: String {
        switch self {
        case .steps:                  return "figure.walk"
        case .distance:               return "location.fill"
        case .flightsClimbed:         return "stairs"
        case .activeEnergy:           return "flame.fill"
        case .basalEnergy:            return "bolt.fill"
        case .heartRate:              return "heart.fill"
        case .restingHeartRate:       return "heart"
        case .hrv:                    return "waveform.path.ecg"
        case .spo2:                   return "drop.fill"
        case .respiratoryRate:        return "lungs.fill"
        case .bodyTemperature:        return "thermometer"
        case .bloodPressureSystolic:  return "arrow.up.heart.fill"
        case .bloodPressureDiastolic: return "arrow.down.heart.fill"
        case .bodyMass:               return "scalemass.fill"
        case .bodyFatPercentage:      return "percent"
        case .leanBodyMass:           return "figure.arms.open"
        case .sleepInBed:             return "bed.double.fill"
        case .sleepAwake:             return "sun.max.fill"
        case .sleepLight:             return "moon.fill"
        case .sleepDeep:              return "moon.zzz.fill"
        case .sleepRem:               return "moon.stars.fill"
        case .workout:                return "figure.run"
        case .mindfulMinutes:         return "leaf.fill"
        case .standHours:             return "figure.stand"
        case .vo2Max:                 return "lungs"
        case .stressScore:            return "gauge"
        }
    }

    var tintColor: Color {
        switch self {
        case .activeEnergy, .basalEnergy, .bodyTemperature:
            return .orange
        case .steps, .distance, .flightsClimbed, .standHours:
            return .green
        case .heartRate, .restingHeartRate, .hrv:
            return .red
        case .bloodPressureSystolic, .bloodPressureDiastolic:
            return .pink
        case .spo2:
            return .blue
        case .respiratoryRate, .vo2Max:
            return .teal
        case .bodyMass, .bodyFatPercentage, .leanBodyMass:
            return .brown
        case .sleepInBed, .sleepDeep, .sleepLight, .sleepRem:
            return .indigo
        case .sleepAwake:
            return .yellow
        case .workout:
            return .green
        case .mindfulMinutes:
            return .mint
        case .stressScore:
            return .purple
        }
    }
}
