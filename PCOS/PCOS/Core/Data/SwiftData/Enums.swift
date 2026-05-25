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
        case .none:
            L10n.string("None", defaultValue: "None")
        case .spotting:
            L10n.string("Spotting", defaultValue: "Spotting")
        case .light:
            L10n.string("Light", defaultValue: "Light")
        case .medium:
            L10n.string("Medium", defaultValue: "Medium")
        case .heavy:
            L10n.string("Heavy", defaultValue: "Heavy")
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

    /// Single-character label for calendar cells (colorblind accessibility).
    var shortLabel: String {
        switch self {
        case .none:
            ""
        case .spotting:
            L10n.string("S", defaultValue: "S")
        case .light:
            L10n.string("L", defaultValue: "L")
        case .medium:
            L10n.string("M", defaultValue: "M")
        case .heavy:
            L10n.string("H", defaultValue: "H")
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
        case .menstrual:
            L10n.string("Menstrual", defaultValue: "Menstrual")
        case .follicular:
            L10n.string("Follicular", defaultValue: "Follicular")
        case .ovulatory:
            L10n.string("Ovulatory", defaultValue: "Ovulatory")
        case .luteal:
            L10n.string("Luteal", defaultValue: "Luteal")
        }
    }
}

enum OvulationStatus: String, Codable, CaseIterable, Identifiable {
    case unknown
    case ovulatory
    case anovulatory

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unknown:
            L10n.string("Unknown", defaultValue: "Unknown")
        case .ovulatory:
            L10n.string("Ovulatory", defaultValue: "Ovulatory")
        case .anovulatory:
            L10n.string("Anovulatory", defaultValue: "Anovulatory")
        }
    }
}

enum CervicalMucusType: String, Codable, CaseIterable, Identifiable {
    case notObserved
    case dry
    case sticky
    case creamy
    case watery
    case eggWhite

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notObserved:
            L10n.string("Not observed", defaultValue: "Not observed")
        case .dry:
            L10n.string("Dry", defaultValue: "Dry")
        case .sticky:
            L10n.string("Sticky", defaultValue: "Sticky")
        case .creamy:
            L10n.string("Creamy", defaultValue: "Creamy")
        case .watery:
            L10n.string("Watery", defaultValue: "Watery")
        case .eggWhite:
            L10n.string("Egg white", defaultValue: "Egg white")
        }
    }
}

enum LHTestResult: String, Codable, CaseIterable, Identifiable {
    case notTested
    case negative
    case high
    case peak

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notTested:
            L10n.string("Not tested", defaultValue: "Not tested")
        case .negative:
            L10n.string("Negative", defaultValue: "Negative")
        case .high:
            L10n.string("High", defaultValue: "High")
        case .peak:
            L10n.string("Peak", defaultValue: "Peak")
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
        case .physical:
            L10n.string("Physical", defaultValue: "Physical")
        case .mood:
            L10n.string("Mood", defaultValue: "Mood")
        case .pain:
            L10n.string("Pain", defaultValue: "Pain")
        case .digestive:
            L10n.string("Digestive", defaultValue: "Digestive")
        case .metabolic:
            L10n.string("Metabolic", defaultValue: "Metabolic")
        case .hair:
            L10n.string("Hair", defaultValue: "Hair")
        case .skin:
            L10n.string("Skin", defaultValue: "Skin")
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
        case .fatigue:
            L10n.string("Fatigue", defaultValue: "Fatigue")
        case .bloating:
            L10n.string("Bloating", defaultValue: "Bloating")
        case .headache:
            L10n.string("Headache", defaultValue: "Headache")
        case .acne:
            L10n.string("Acne", defaultValue: "Acne")
        case .breastTenderness:
            L10n.string("Breast Tenderness", defaultValue: "Breast Tenderness")
        case .irritable:
            L10n.string("Irritability", defaultValue: "Irritability")
        case .anxious:
            L10n.string("Anxiety", defaultValue: "Anxiety")
        case .depressed:
            L10n.string("Low Mood", defaultValue: "Low Mood")
        case .moodSwings:
            L10n.string("Mood Swings", defaultValue: "Mood Swings")
        case .cramps:
            L10n.string("Cramps", defaultValue: "Cramps")
        case .pelvicPain:
            L10n.string("Pelvic Pain", defaultValue: "Pelvic Pain")
        case .backPain:
            L10n.string("Back Pain", defaultValue: "Back Pain")
        case .nausea:
            L10n.string("Nausea", defaultValue: "Nausea")
        case .constipation:
            L10n.string("Constipation", defaultValue: "Constipation")
        case .diarrhea:
            L10n.string("Diarrhea", defaultValue: "Diarrhea")
        case .cravings:
            L10n.string("Cravings", defaultValue: "Cravings")
        case .hunger:
            L10n.string("Hunger", defaultValue: "Hunger")
        case .energyCrash:
            L10n.string("Energy Crash", defaultValue: "Energy Crash")
        case .shedding:
            L10n.string("Hair Shedding", defaultValue: "Hair Shedding")
        case .growthFace:
            L10n.string("Facial Hair", defaultValue: "Facial Hair")
        case .growthBody:
            L10n.string("Body Hair", defaultValue: "Body Hair")
        case .oily:
            L10n.string("Oily Skin", defaultValue: "Oily Skin")
        case .dry:
            L10n.string("Dry Skin", defaultValue: "Dry Skin")
        case .breakouts:
            L10n.string("Breakouts", defaultValue: "Breakouts")
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
        case .nausea: "allergens"
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
        case .fasting:
            L10n.string("Fasting", defaultValue: "Fasting")
        case .beforeMeal:
            L10n.string("Before Meal", defaultValue: "Before Meal")
        case .afterMeal:
            L10n.string("After Meal", defaultValue: "After Meal")
        case .random:
            L10n.string("Random", defaultValue: "Random")
        }
    }
}

// MARK: - Daily Log Enums

enum PositiveActionType: String, Codable, CaseIterable, Identifiable {
    case pcosFriendlyMeal = "pcos_friendly_meal"
    case highProteinMeal = "high_protein_meal"
    case lowerCarbMeal = "lower_carb_meal"
    case walkMovement = "walk_movement"
    case stressReduction = "stress_reduction"
    case goodSleep = "good_sleep"
    case supplementsTaken = "supplements_taken"
    case cycleSupportiveSigns = "cycle_supportive_signs"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pcosFriendlyMeal:
            L10n.string("PCOS-friendly meal", defaultValue: "PCOS-friendly meal")
        case .highProteinMeal:
            L10n.string("High-protein meal", defaultValue: "High-protein meal")
        case .lowerCarbMeal:
            L10n.string("Lower-carb meal", defaultValue: "Lower-carb meal")
        case .walkMovement:
            L10n.string("Walk / movement", defaultValue: "Walk / movement")
        case .stressReduction:
            L10n.string("Stress reduction", defaultValue: "Stress reduction")
        case .goodSleep:
            L10n.string("Good sleep", defaultValue: "Good sleep")
        case .supplementsTaken:
            L10n.string("Supplements taken", defaultValue: "Supplements taken")
        case .cycleSupportiveSigns:
            L10n.string("Cycle-supportive signs", defaultValue: "Cycle-supportive signs")
        }
    }

    var encouragement: String {
        switch self {
        case .pcosFriendlyMeal:
            L10n.string(
                "Nice work - logging meals helps connect food, energy, and symptoms over time.",
                defaultValue: "Nice work - logging meals helps connect food, energy, and symptoms over time."
            )
        case .highProteinMeal:
            L10n.string(
                "Great consistency - protein context can make meal patterns easier to compare.",
                defaultValue: "Great consistency - protein context can make meal patterns easier to compare."
            )
        case .lowerCarbMeal:
            L10n.string(
                "Logged - this gives your glucose and energy patterns more useful context.",
                defaultValue: "Logged - this gives your glucose and energy patterns more useful context."
            )
        case .walkMovement:
            L10n.string(
                "Nice work - that walk supports insulin sensitivity.",
                defaultValue: "Nice work - that walk supports insulin sensitivity."
            )
        case .stressReduction:
            L10n.string(
                "Good check-in - stress reduction can help show what supports steadier days.",
                defaultValue: "Good check-in - stress reduction can help show what supports steadier days."
            )
        case .goodSleep:
            L10n.string(
                "Helpful data point - sleep context can clarify energy and craving patterns.",
                defaultValue: "Helpful data point - sleep context can clarify energy and craving patterns."
            )
        case .supplementsTaken:
            L10n.string(
                "Great consistency - this helps build a clearer PCOS pattern over time.",
                defaultValue: "Great consistency - this helps build a clearer PCOS pattern over time."
            )
        case .cycleSupportiveSigns:
            L10n.string(
                "Saved - cycle-supportive signs can add context without assuming every cycle ovulates.",
                defaultValue: "Saved - cycle-supportive signs can add context without assuming every cycle ovulates."
            )
        }
    }

    var systemImage: String {
        switch self {
        case .pcosFriendlyMeal: "leaf.fill"
        case .highProteinMeal: "fork.knife"
        case .lowerCarbMeal: "chart.bar.fill"
        case .walkMovement: "figure.walk"
        case .stressReduction: "wind"
        case .goodSleep: "bed.double.fill"
        case .supplementsTaken: "pills.fill"
        case .cycleSupportiveSigns: "sparkles"
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
        case .breakfast:
            L10n.string("Breakfast", defaultValue: "Breakfast")
        case .lunch:
            L10n.string("Lunch", defaultValue: "Lunch")
        case .dinner:
            L10n.string("Dinner", defaultValue: "Dinner")
        case .snack:
            L10n.string("Snack", defaultValue: "Snack")
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
        case .low:
            L10n.string("Low GI", defaultValue: "Low GI")
        case .medium:
            L10n.string("Medium GI", defaultValue: "Medium GI")
        case .high:
            L10n.string("High GI", defaultValue: "High GI")
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
        case .scalpPart:
            L10n.string("Scalp (Part Line)", defaultValue: "Scalp (Part Line)")
        case .hairline:
            L10n.string("Hairline", defaultValue: "Hairline")
        case .faceChin:
            L10n.string("Chin", defaultValue: "Chin")
        case .faceUpperLip:
            L10n.string("Upper Lip", defaultValue: "Upper Lip")
        case .body:
            L10n.string("Body", defaultValue: "Body")
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
        case .cyclePattern:
            L10n.string("Cycle Pattern", defaultValue: "Cycle Pattern")
        case .symptomCorrelation:
            L10n.string("Symptom Correlation", defaultValue: "Symptom Correlation")
        case .supplementEfficacy:
            L10n.string("Supplement Efficacy", defaultValue: "Supplement Efficacy")
        case .dietImpact:
            L10n.string("Diet Impact", defaultValue: "Diet Impact")
        case .sleepActivity:
            L10n.string("Sleep & Activity", defaultValue: "Sleep & Activity")
        case .seasonalPattern:
            L10n.string("Seasonal Pattern", defaultValue: "Seasonal Pattern")
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
