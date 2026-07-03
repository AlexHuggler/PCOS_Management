import Foundation
import HealthKit

struct HealthKitDataTypeDescriptor: Identifiable {
    enum Category: String {
        case body
        case activity
        case heart
        case sleep
        case glucose
        case nutrition
        case cycle
        case symptoms
        case reproductiveContext
    }

    enum ObjectKind {
        case quantity(HKQuantityTypeIdentifier)
        case category(HKCategoryTypeIdentifier)
        case characteristic(HKCharacteristicTypeIdentifier)
        case workout
        case disclosureOnly
    }

    var id: String
    var title: String
    var healthKitTypeDescription: String
    var usageDescription: String
    var systemImage: String
    var category: Category
    var objectKind: ObjectKind

    var objectType: HKObjectType? {
        switch objectKind {
        case .quantity(let identifier):
            HKObjectType.quantityType(forIdentifier: identifier)
        case .category(let identifier):
            HKObjectType.categoryType(forIdentifier: identifier)
        case .characteristic(let identifier):
            HKObjectType.characteristicType(forIdentifier: identifier)
        case .workout:
            HKObjectType.workoutType()
        case .disclosureOnly:
            nil
        }
    }

    static var defaultReadTypes: Set<HKObjectType> {
        Set(readDescriptors.compactMap(\.objectType))
    }

    static let readDescriptors: [HealthKitDataTypeDescriptor] = [
        quantity("body_mass", .bodyMass, "Body Mass", "Used for daily weight and weight trends.", "scalemass", .body),
        quantity("height", .height, "Height", "Used as optional body context for trend interpretation.", "ruler", .body),
        characteristic("date_of_birth", .dateOfBirth, "Date of Birth", "Used only as optional age context when Apple Health shares it.", "person.crop.circle", .body),

        category("sleep_analysis", .sleepAnalysis, "Sleep Analysis", "Used for sleep hours and sleep/recovery insights.", "bed.double.fill", .sleep),
        quantity("active_energy", .activeEnergyBurned, "Active Energy Burned", "Used as activity context for daily logs and activity insights.", "flame.fill", .activity),
        quantity("apple_exercise_time", .appleExerciseTime, "Exercise Time", "Used for movement context when Apple Health shares exercise minutes.", "figure.run", .activity),
        quantity("step_count", .stepCount, "Step Count", "Used for activity context and source summaries.", "figure.walk", .activity),
        quantity("walking_running_distance", .distanceWalkingRunning, "Walking + Running Distance", "Used for movement context and source summaries.", "figure.walk.motion", .activity),
        workout("workouts", "Workouts", "Used for workout source summaries and activity context.", "figure.strengthtraining.traditional", .activity),

        quantity("heart_rate", .heartRate, "Heart Rate", "Used as optional recovery and symptom context.", "heart.fill", .heart),
        quantity("resting_heart_rate", .restingHeartRate, "Resting Heart Rate", "Used for daily resting BPM and recovery context.", "heart.circle", .heart),
        quantity("heart_rate_variability", .heartRateVariabilitySDNN, "Heart Rate Variability", "Used as optional recovery context when Apple Health shares it.", "waveform.path.ecg", .heart),
        quantity("electrodermal_activity", .electrodermalActivity, "Electrodermal Activity", "Used as optional stress/recovery context when Apple Health shares it.", "figure.mind.and.body", .heart),

        quantity("blood_glucose", .bloodGlucose, "Blood Glucose", "Used for blood sugar history and metabolic insight context.", "drop.fill", .glucose),

        quantity("dietary_energy", .dietaryEnergyConsumed, "Dietary Energy", "Imported nutrition is reviewed before it becomes a saved meal.", "fork.knife.circle", .nutrition),
        quantity("dietary_carbohydrates", .dietaryCarbohydrates, "Dietary Carbohydrates", "Used for nutrition source summaries and meal/glucose context.", "fork.knife.circle", .nutrition),
        quantity("dietary_protein", .dietaryProtein, "Dietary Protein", "Used for nutrition source summaries and meal/glucose context.", "fork.knife.circle", .nutrition),
        quantity("dietary_fat_total", .dietaryFatTotal, "Dietary Fat", "Used for nutrition source summaries and meal/glucose context.", "fork.knife.circle", .nutrition),
        quantity("dietary_fat_saturated", .dietaryFatSaturated, "Saturated Fat", "Used for nutrition source summaries when available.", "fork.knife.circle", .nutrition),
        quantity("dietary_fiber", .dietaryFiber, "Dietary Fiber", "Used for nutrition source summaries and glucose-impact context.", "fork.knife.circle", .nutrition),
        quantity("dietary_sugar", .dietarySugar, "Dietary Sugar", "Used for nutrition source summaries and glucose-impact context.", "fork.knife.circle", .nutrition),
        quantity("dietary_sodium", .dietarySodium, "Sodium", "Used for nutrition source summaries when available.", "fork.knife.circle", .nutrition),
        quantity("dietary_cholesterol", .dietaryCholesterol, "Cholesterol", "Used for nutrition source summaries when available.", "fork.knife.circle", .nutrition),
        quantity("dietary_potassium", .dietaryPotassium, "Potassium", "Used for nutrition source summaries when available.", "fork.knife.circle", .nutrition),
        quantity("dietary_calcium", .dietaryCalcium, "Calcium", "Used for nutrition source summaries when available.", "fork.knife.circle", .nutrition),
        quantity("dietary_iron", .dietaryIron, "Iron", "Used for nutrition source summaries when available.", "fork.knife.circle", .nutrition),
        quantity("dietary_water", .dietaryWater, "Water", "Used for hydration context when Apple Health shares it.", "drop.circle", .nutrition),

        quantity("body_temperature", .bodyTemperature, "Body Temperature", "Used as optional body context when Apple Health shares it.", "thermometer.medium", .cycle),
        quantity("basal_body_temperature", .basalBodyTemperature, "Basal Body Temperature", "Used for optional ovulation context.", "thermometer.sun", .cycle),
        category("menstrual_flow", .menstrualFlow, "Menstruation", "Used to prefill period context after Apple Health shares it.", "drop.fill", .cycle),
        category("cervical_mucus", .cervicalMucusQuality, "Cervical Mucus", "Used for optional ovulation context.", "sparkles", .cycle),
        category("ovulation_test_result", .ovulationTestResult, "Ovulation Test Result", "Used for optional ovulation context.", "checkmark.seal", .cycle),
        category("progesterone_test_result", .progesteroneTestResult, "Progesterone Test Result", "Stored as reviewable reproductive context.", "checkmark.seal", .cycle),

        category("pregnancy", .pregnancy, "Pregnancy", "Stored as sensitive context for review; it does not change app mode automatically.", "heart.text.square", .reproductiveContext),
        category("pregnancy_test_result", .pregnancyTestResult, "Pregnancy Test Result", "Stored as sensitive context for review; it does not change app mode automatically.", "checkmark.seal", .reproductiveContext),
        category("lactation", .lactation, "Lactation", "Stored as sensitive reproductive context for review.", "heart.text.square", .reproductiveContext),
        category("sexual_activity", .sexualActivity, "Sexual Activity", "Stored as sensitive reproductive context for review.", "lock.shield", .reproductiveContext),

        category("abdominal_cramps", .abdominalCramps, "Abdominal Cramps", "Used to prefill symptom context from Apple Health.", "bolt.heart", .symptoms),
        category("pelvic_pain", .pelvicPain, "Pelvic Pain", "Used to prefill symptom context from Apple Health.", "bolt.heart", .symptoms),
        category("fatigue", .fatigue, "Fatigue", "Used to prefill symptom context from Apple Health.", "battery.25", .symptoms),
        category("bloating", .bloating, "Bloating", "Used to prefill symptom context from Apple Health.", "circle.fill", .symptoms),
        category("acne", .acne, "Acne", "Used to prefill symptom context from Apple Health.", "circle.dotted", .symptoms),
        category("hair_loss", .hairLoss, "Hair Loss", "Used to prefill symptom context from Apple Health.", "comb", .symptoms),
        category("headache", .headache, "Headache", "Used to prefill symptom context from Apple Health.", "head.profile.arrow.forward.and.visionpro", .symptoms),
        category("mood_changes", .moodChanges, "Mood Changes", "Used to prefill symptom context from Apple Health.", "brain.head.profile", .symptoms),
        category("appetite_changes", .appetiteChanges, "Appetite Changes", "Used to prefill craving/hunger context from Apple Health.", "fork.knife", .symptoms),
        category("sleep_changes", .sleepChanges, "Sleep Changes", "Used as optional sleep context from Apple Health.", "bed.double", .symptoms),
    ]

    static let disclosureItems: [HealthKitDataTypeDescriptor] = [
        disclosure("body_context", "Body context", "HealthKit types: Body Mass, Height, Date of Birth", "Used for daily weight, body context, and source summaries.", "scalemass", .body),
        disclosure("sleep", "Sleep", "HealthKit type: Sleep Analysis", "Used for sleep hours and sleep/recovery insights.", "bed.double.fill", .sleep),
        disclosure("activity", "Activity", "HealthKit types: Active Energy, Exercise Time, Steps, Walking + Running Distance, Workouts", "Used as movement context for daily logs and activity insights.", "figure.walk", .activity),
        disclosure("heart_recovery", "Heart & recovery", "HealthKit types: Heart Rate, Resting Heart Rate, Heart Rate Variability, Electrodermal Activity", "Used for recovery context and source summaries when Apple Health shares it.", "heart.circle", .heart),
        disclosure("blood_glucose", "Blood Glucose", "HealthKit type: Blood Glucose", "Used for blood sugar history and metabolic insight context. Imported readings appear in Blood Sugar History with an Apple Health label.", "drop.fill", .glucose),
        disclosure("nutrition", "Nutrition", "HealthKit types: Dietary Energy, Carbohydrates, Protein, Total Fat, Saturated Fat, Fiber, Sugar, Sodium, Cholesterol, Potassium, Calcium, Iron, Water", "Used for nutrition source summaries and meal/glucose insight context. Imported nutrition is reviewed before it becomes a saved meal.", "fork.knife.circle", .nutrition),
        disclosure("cycle_ovulation", "Cycle & ovulation", "HealthKit types: Body Temperature, Basal Body Temperature, Menstruation, Cervical Mucus, Ovulation Test Result, Progesterone Test Result", "Used to prefill cycle and ovulation context after Apple Health shares it.", "sparkles", .cycle),
        disclosure("reproductive_context", "Reproductive context", "HealthKit types: Pregnancy, Pregnancy Test Result, Lactation, Sexual Activity", "Stored as sensitive reviewable context. CycleBalance does not change app mode automatically from these samples.", "lock.shield", .reproductiveContext),
        disclosure("symptoms", "Symptoms", "HealthKit types: Abdominal Cramps, Pelvic Pain, Fatigue, Bloating, Acne, Hair Loss, Headache, Mood Changes, Appetite Changes, Sleep Changes", "Used to prefill symptom context from compatible period and wellness apps.", "heart.text.square.fill", .symptoms),
    ]

    private static func quantity(
        _ id: String,
        _ identifier: HKQuantityTypeIdentifier,
        _ title: String,
        _ usage: String,
        _ systemImage: String,
        _ category: Category
    ) -> HealthKitDataTypeDescriptor {
        HealthKitDataTypeDescriptor(
            id: id,
            title: title,
            healthKitTypeDescription: "HealthKit type: \(title)",
            usageDescription: usage,
            systemImage: systemImage,
            category: category,
            objectKind: .quantity(identifier)
        )
    }

    private static func category(
        _ id: String,
        _ identifier: HKCategoryTypeIdentifier,
        _ title: String,
        _ usage: String,
        _ systemImage: String,
        _ category: Category
    ) -> HealthKitDataTypeDescriptor {
        HealthKitDataTypeDescriptor(
            id: id,
            title: title,
            healthKitTypeDescription: "HealthKit type: \(title)",
            usageDescription: usage,
            systemImage: systemImage,
            category: category,
            objectKind: .category(identifier)
        )
    }

    private static func characteristic(
        _ id: String,
        _ identifier: HKCharacteristicTypeIdentifier,
        _ title: String,
        _ usage: String,
        _ systemImage: String,
        _ category: Category
    ) -> HealthKitDataTypeDescriptor {
        HealthKitDataTypeDescriptor(
            id: id,
            title: title,
            healthKitTypeDescription: "HealthKit type: \(title)",
            usageDescription: usage,
            systemImage: systemImage,
            category: category,
            objectKind: .characteristic(identifier)
        )
    }

    private static func workout(
        _ id: String,
        _ title: String,
        _ usage: String,
        _ systemImage: String,
        _ category: Category
    ) -> HealthKitDataTypeDescriptor {
        HealthKitDataTypeDescriptor(
            id: id,
            title: title,
            healthKitTypeDescription: "HealthKit type: Workouts",
            usageDescription: usage,
            systemImage: systemImage,
            category: category,
            objectKind: .workout
        )
    }

    private static func disclosure(
        _ id: String,
        _ title: String,
        _ healthKitType: String,
        _ usage: String,
        _ systemImage: String,
        _ category: Category
    ) -> HealthKitDataTypeDescriptor {
        HealthKitDataTypeDescriptor(
            id: id,
            title: title,
            healthKitTypeDescription: healthKitType,
            usageDescription: usage,
            systemImage: systemImage,
            category: category,
            objectKind: .disclosureOnly
        )
    }
}
