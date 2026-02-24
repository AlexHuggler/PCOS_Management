import Foundation

// MARK: - Cycle Enums

enum FlowIntensity: String, Codable, CaseIterable, Identifiable {
    case none
    case spotting
    case light
    case medium
    case heavy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "None"
        case .spotting: "Spotting"
        case .light: "Light"
        case .medium: "Medium"
        case .heavy: "Heavy"
        }
    }

    var systemImage: String {
        switch self {
        case .none: "drop"
        case .spotting: "drop.fill"
        case .light: "drop.fill"
        case .medium: "drop.fill"
        case .heavy: "drop.fill"
        }
    }
}

enum CyclePhase: String, Codable, CaseIterable, Identifiable {
    case menstrual
    case follicular
    case ovulatory
    case luteal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .menstrual: "Menstrual"
        case .follicular: "Follicular"
        case .ovulatory: "Ovulatory"
        case .luteal: "Luteal"
        }
    }
}

// MARK: - Symptom Enums

enum SymptomCategory: String, Codable, CaseIterable, Identifiable {
    case physical
    case mood
    case pain
    case digestive
    case metabolic
    case hair
    case skin

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .physical: "Physical"
        case .mood: "Mood"
        case .pain: "Pain"
        case .digestive: "Digestive"
        case .metabolic: "Metabolic"
        case .hair: "Hair"
        case .skin: "Skin"
        }
    }

    var systemImage: String {
        switch self {
        case .physical: "figure.walk"
        case .mood: "brain.head.profile"
        case .pain: "bolt.fill"
        case .digestive: "leaf.fill"
        case .metabolic: "flame.fill"
        case .hair: "comb.fill"
        case .skin: "hand.raised.fill"
        }
    }

    var symptomTypes: [SymptomType] {
        switch self {
        case .physical: [.fatigue, .bloating, .headache, .acne, .breastTenderness]
        case .mood: [.irritable, .anxious, .depressed, .moodSwings]
        case .pain: [.cramps, .pelvicPain, .backPain]
        case .digestive: [.nausea, .constipation, .diarrhea]
        case .metabolic: [.cravings, .hunger, .energyCrash]
        case .hair: [.shedding, .growthFace, .growthBody]
        case .skin: [.oily, .dry, .breakouts]
        }
    }
}

enum SymptomType: String, Codable, CaseIterable, Identifiable {
    // Physical
    case fatigue
    case bloating
    case headache
    case acne
    case breastTenderness = "breast_tenderness"

    // Mood
    case irritable
    case anxious
    case depressed
    case moodSwings = "mood_swings"

    // Pain
    case cramps
    case pelvicPain = "pelvic_pain"
    case backPain = "back_pain"

    // Digestive
    case nausea
    case constipation
    case diarrhea

    // Metabolic
    case cravings
    case hunger
    case energyCrash = "energy_crash"

    // Hair
    case shedding
    case growthFace = "growth_face"
    case growthBody = "growth_body"

    // Skin
    case oily
    case dry
    case breakouts

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fatigue: "Fatigue"
        case .bloating: "Bloating"
        case .headache: "Headache"
        case .acne: "Acne"
        case .breastTenderness: "Breast Tenderness"
        case .irritable: "Irritability"
        case .anxious: "Anxiety"
        case .depressed: "Low Mood"
        case .moodSwings: "Mood Swings"
        case .cramps: "Cramps"
        case .pelvicPain: "Pelvic Pain"
        case .backPain: "Back Pain"
        case .nausea: "Nausea"
        case .constipation: "Constipation"
        case .diarrhea: "Diarrhea"
        case .cravings: "Cravings"
        case .hunger: "Hunger"
        case .energyCrash: "Energy Crash"
        case .shedding: "Hair Shedding"
        case .growthFace: "Facial Hair"
        case .growthBody: "Body Hair"
        case .oily: "Oily Skin"
        case .dry: "Dry Skin"
        case .breakouts: "Breakouts"
        }
    }

    var systemImage: String {
        switch self {
        case .fatigue: "battery.25"
        case .bloating: "circle.fill"
        case .headache: "head.profile.arrow.forward.and.visionpro"
        case .acne: "circle.dotted"
        case .breastTenderness: "heart.fill"
        case .irritable: "exclamationmark.triangle"
        case .anxious: "wind"
        case .depressed: "cloud.rain"
        case .moodSwings: "arrow.up.arrow.down"
        case .cramps: "bolt.fill"
        case .pelvicPain: "bolt.heart"
        case .backPain: "figure.walk"
        case .nausea: "stomach"
        case .constipation: "minus.circle"
        case .diarrhea: "arrow.down.circle"
        case .cravings: "fork.knife"
        case .hunger: "flame"
        case .energyCrash: "battery.0"
        case .shedding: "comb"
        case .growthFace: "face.dashed"
        case .growthBody: "figure.arms.open"
        case .oily: "drop.halffull"
        case .dry: "sun.dust"
        case .breakouts: "circle.dotted.circle"
        }
    }

    var category: SymptomCategory {
        switch self {
        case .fatigue, .bloating, .headache, .acne, .breastTenderness: .physical
        case .irritable, .anxious, .depressed, .moodSwings: .mood
        case .cramps, .pelvicPain, .backPain: .pain
        case .nausea, .constipation, .diarrhea: .digestive
        case .cravings, .hunger, .energyCrash: .metabolic
        case .shedding, .growthFace, .growthBody: .hair
        case .oily, .dry, .breakouts: .skin
        }
    }
}

// MARK: - Blood Sugar Enums

enum GlucoseReadingType: String, Codable, CaseIterable, Identifiable {
    case fasting
    case beforeMeal = "before_meal"
    case afterMeal = "after_meal"
    case random

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fasting: "Fasting"
        case .beforeMeal: "Before Meal"
        case .afterMeal: "After Meal"
        case .random: "Random"
        }
    }
}

// MARK: - Meal Enums

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case snack

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snack"
        }
    }

    var systemImage: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon.stars"
        case .snack: "carrot"
        }
    }
}

enum GlycemicImpact: String, Codable, CaseIterable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low: "Low GI"
        case .medium: "Medium GI"
        case .high: "High GI"
        }
    }
}

// MARK: - Photo Journal Enums

enum HairPhotoType: String, Codable, CaseIterable, Identifiable {
    case scalpPart = "scalp_part"
    case hairline
    case faceChin = "face_chin"
    case faceUpperLip = "face_upper_lip"
    case body

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .scalpPart: "Scalp (Part Line)"
        case .hairline: "Hairline"
        case .faceChin: "Chin"
        case .faceUpperLip: "Upper Lip"
        case .body: "Body"
        }
    }
}

// MARK: - Insight Enums

enum InsightType: String, Codable, CaseIterable, Identifiable {
    case cyclePattern = "cycle_pattern"
    case symptomCorrelation = "symptom_correlation"
    case supplementEfficacy = "supplement_efficacy"
    case dietImpact = "diet_impact"
    case sleepActivity = "sleep_activity"
    case seasonalPattern = "seasonal_pattern"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cyclePattern: "Cycle Pattern"
        case .symptomCorrelation: "Symptom Correlation"
        case .supplementEfficacy: "Supplement Efficacy"
        case .dietImpact: "Diet Impact"
        case .sleepActivity: "Sleep & Activity"
        case .seasonalPattern: "Seasonal Pattern"
        }
    }

    var systemImage: String {
        switch self {
        case .cyclePattern: "calendar.circle"
        case .symptomCorrelation: "chart.xyaxis.line"
        case .supplementEfficacy: "pills.circle"
        case .dietImpact: "fork.knife.circle"
        case .sleepActivity: "bed.double"
        case .seasonalPattern: "leaf.circle"
        }
    }
}
