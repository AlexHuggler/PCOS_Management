import Foundation
import CryptoKit

enum DemoDataScenario: String, CaseIterable, Identifiable, Sendable {
    case newlyDiagnosed
    case symptomManagement
    case ttcFertility

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newlyDiagnosed:
            L10n.string("Newly Diagnosed", defaultValue: "Newly Diagnosed")
        case .symptomManagement:
            L10n.string("Symptom Management", defaultValue: "Symptom Management")
        case .ttcFertility:
            L10n.string("TTC / Fertility", defaultValue: "TTC / Fertility")
        }
    }

    var subtitle: String {
        switch self {
        case .newlyDiagnosed:
            L10n.string("Long irregular cycles with early tracking habits", defaultValue: "Long irregular cycles with early tracking habits")
        case .symptomManagement:
            L10n.string("Established routine with symptom and metabolic patterns", defaultValue: "Established routine with symptom and metabolic patterns")
        case .ttcFertility:
            L10n.string("Trying-to-conceive tracking with variable cycle lengths", defaultValue: "Trying-to-conceive tracking with variable cycle lengths")
        }
    }

    var backupSource: SettingsDataBackupSource {
        SettingsDataBackupSource(kind: .demoScenario, scenarioID: rawValue)
    }

    @MainActor
    func applyOnboardingDefaults(to profile: OnboardingProfile) {
        let defaults = onboardingDefaults
        profile.primaryGoal = defaults.primaryGoal
        profile.pcosExperience = defaults.experience
        profile.symptomFocusAreas = defaults.focusAreas
        profile.hasCompletedWelcome = true
        profile.hasCompletedQuestionnaire = true
        profile.hasCompletedGuidedAction = true
    }
}

struct DemoDataBuilder {
    private struct ScenarioTemplate {
        var completedCycleLengths: [Int]
        var completedPeriodLengths: [Int]
        var ongoingCycleDays: Int
        var ongoingPeriodDays: Int
        var fastingBaseline: Double
        var postMealBaseline: Double
        var symptomRotation: [SymptomType]
        var supplements: [(name: String, dosage: Double, brand: String)]
        var mealPatterns: [(MealType, GlycemicImpact, String)]
        var onboardingDefaults: DemoOnboardingDefaults
    }

    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func makeBackup(
        for scenario: DemoDataScenario,
        referenceDate: Date = Date()
    ) -> SettingsDataBackupFile {
        let template = template(for: scenario)
        let exportedAt = atNoon(referenceDate)
        let stableReferenceDate = atNoon(min(referenceDate, Date()))
        let idGenerator = StableIDGenerator(
            namespace: "\(scenario.rawValue)|\(stableTimestamp(stableReferenceDate))"
        )
        let records = buildRecords(
            for: scenario,
            template: template,
            referenceDate: referenceDate,
            idGenerator: idGenerator
        )

        return SettingsDataBackupFile(
            exportedAt: exportedAt,
            appVersion: "demo-\(scenario.rawValue)",
            source: scenario.backupSource,
            records: records
        )
    }
}

private extension DemoDataBuilder {
    private func template(for scenario: DemoDataScenario) -> ScenarioTemplate {
        switch scenario {
        case .newlyDiagnosed:
            return ScenarioTemplate(
                completedCycleLengths: [52, 37, 63, 41],
                completedPeriodLengths: [7, 5, 8, 6],
                ongoingCycleDays: 19,
                ongoingPeriodDays: 6,
                fastingBaseline: 102,
                postMealBaseline: 138,
                symptomRotation: [.fatigue, .bloating, .cramps, .moodSwings, .acne],
                supplements: [
                    ("Inositol", 2000, "Wholesome Story"),
                    ("Vitamin D3", 2000, "Nature Made"),
                ],
                mealPatterns: [
                    (.breakfast, .medium, "Greek yogurt, berries, chia"),
                    (.lunch, .high, "Rice bowl with teriyaki chicken"),
                    (.dinner, .low, "Salmon, quinoa, roasted vegetables"),
                ],
                onboardingDefaults: DemoOnboardingDefaults(
                    primaryGoal: .trackCycles,
                    experience: .newlyDiagnosed,
                    focusAreas: [.painCramps, .moodEnergy]
                )
            )

        case .symptomManagement:
            return ScenarioTemplate(
                completedCycleLengths: [34, 31, 46, 36, 40],
                completedPeriodLengths: [5, 4, 6, 5, 5],
                ongoingCycleDays: 14,
                ongoingPeriodDays: 5,
                fastingBaseline: 95,
                postMealBaseline: 126,
                symptomRotation: [.energyCrash, .cravings, .bloating, .anxious, .breakouts, .fatigue],
                supplements: [
                    ("Inositol", 4000, "Ovasitol"),
                    ("Magnesium", 300, "Pure Encapsulations"),
                    ("Omega-3", 1000, "Nordic Naturals"),
                ],
                mealPatterns: [
                    (.breakfast, .low, "Egg scramble, avocado, greens"),
                    (.lunch, .medium, "Lentil bowl with tahini dressing"),
                    (.dinner, .low, "Turkey chili with vegetables"),
                ],
                onboardingDefaults: DemoOnboardingDefaults(
                    primaryGoal: .understandSymptoms,
                    experience: .experienced,
                    focusAreas: [.moodEnergy, .digestionWeight, .skinHair]
                )
            )

        case .ttcFertility:
            return ScenarioTemplate(
                completedCycleLengths: [58, 72, 45, 66],
                completedPeriodLengths: [6, 7, 5, 6],
                ongoingCycleDays: 23,
                ongoingPeriodDays: 5,
                fastingBaseline: 98,
                postMealBaseline: 132,
                symptomRotation: [.cramps, .pelvicPain, .breastTenderness, .fatigue, .anxious],
                supplements: [
                    ("Prenatal", 1, "Ritual"),
                    ("Inositol", 2000, "Theralogix"),
                    ("CoQ10", 200, "Jarrow"),
                ],
                mealPatterns: [
                    (.breakfast, .low, "Overnight oats with flaxseed"),
                    (.lunch, .medium, "Chicken wrap with hummus"),
                    (.dinner, .low, "Tofu stir-fry with brown rice"),
                ],
                onboardingDefaults: DemoOnboardingDefaults(
                    primaryGoal: .trackCycles,
                    experience: .experienced,
                    focusAreas: [.painCramps, .digestionWeight]
                )
            )
        }
    }

    private func buildRecords(
        for scenario: DemoDataScenario,
        template: ScenarioTemplate,
        referenceDate: Date,
        idGenerator: StableIDGenerator
    ) -> SettingsDataBackupRecords {
        let now = atNoon(min(referenceDate, Date()))
        let completedDays = template.completedCycleLengths.reduce(0, +)
        let ongoingStart = addingDays(-template.ongoingCycleDays, to: now)
        var cycleCursor = addingDays(-completedDays, to: ongoingStart)

        var cycles: [CycleRecord] = []
        var cycleEntries: [CycleEntryRecord] = []
        var symptoms: [SymptomEntryRecord] = []
        var bloodSugar: [BloodSugarReadingRecord] = []
        var supplements: [SupplementLogRecord] = []
        var meals: [MealEntryRecord] = []
        var hairPhotos: [HairPhotoEntryRecord] = []
        var dailyLogs: [DailyLogRecord] = []
        var insights: [InsightRecord] = []

        for (index, length) in template.completedCycleLengths.enumerated() {
            let cycleID = idGenerator.uuid("cycle/completed/\(index)")
            let startDate = cycleCursor
            let endDate = addingDays(length - 1, to: startDate)
            cycles.append(
                CycleRecord(
                    id: cycleID,
                    startDate: startDate,
                    endDate: endDate,
                    lengthDays: length,
                    isPredicted: false,
                    manualCycleLengthOverrideDays: nil,
                    ovulationStatus: ovulationStatus(for: scenario, completedCycleIndex: index)
                )
            )

            let periodDays = template.completedPeriodLengths[safe: index] ?? 5
            let generatedEntries = makePeriodEntries(
                cycleID: cycleID,
                startDate: startDate,
                periodDays: periodDays,
                notePrefix: "Cycle \(index + 1)",
                idGenerator: idGenerator,
                idNamespace: "completed/\(index)"
            )
            cycleEntries.append(contentsOf: generatedEntries)
            symptoms.append(
                contentsOf: makePeriodSymptoms(
                    from: generatedEntries,
                    scenario: scenario,
                    idGenerator: idGenerator,
                    idNamespace: "completed/\(index)"
                )
            )
            cycleCursor = addingDays(1, to: endDate)
        }

        let ongoingCycleID = idGenerator.uuid("cycle/ongoing")
        cycles.append(
            CycleRecord(
                id: ongoingCycleID,
                startDate: cycleCursor,
                endDate: nil,
                lengthDays: nil,
                isPredicted: false,
                manualCycleLengthOverrideDays: manualCycleLengthOverrideDays(for: scenario),
                ovulationStatus: .unknown
            )
        )

        let ongoingEntries = makePeriodEntries(
            cycleID: ongoingCycleID,
            startDate: cycleCursor,
            periodDays: template.ongoingPeriodDays,
            notePrefix: "Current cycle",
            idGenerator: idGenerator,
            idNamespace: "ongoing"
        )
        cycleEntries.append(contentsOf: ongoingEntries)
        symptoms.append(
            contentsOf: makePeriodSymptoms(
                from: ongoingEntries,
                scenario: scenario,
                idGenerator: idGenerator,
                idNamespace: "ongoing"
            )
        )

        for offset in stride(from: 2, through: 34, by: 4) {
            let date = addingDays(-offset, to: now)
            guard date >= cycles.first?.startDate ?? date else { continue }
            let symptomType = template.symptomRotation[(offset / 2) % template.symptomRotation.count]
            let severity = min(5, 2 + (offset % 3))
            symptoms.append(
                SymptomEntryRecord(
                    id: idGenerator.uuid("symptom/routine/\(offset)"),
                    date: date,
                    category: symptomType.category,
                    symptomType: symptomType,
                    severity: severity,
                    notes: "\(demoSymptomDisplayName(symptomType)) noted during routine tracking",
                    cycleEntryID: nil
                )
            )
        }

        for dayOffset in 0..<18 {
            let dayAnchor = addingDays(-(dayOffset * 2), to: now)
            let context = bloodSugarMealContext(for: dayOffset)

            let fastingValue = template.fastingBaseline + Double((dayOffset % 5) * 3 - 5)
            bloodSugar.append(
                BloodSugarReadingRecord(
                    id: idGenerator.uuid("bloodSugar/day\(dayOffset)/fasting"),
                    timestamp: addingHours(-5, to: dayAnchor),
                    glucoseValue: max(76, fastingValue),
                    readingType: .fasting,
                    mealContext: "Morning baseline",
                    fromHealthKit: false,
                    notes: "Home finger-stick meter"
                )
            )

            let beforeMealValue = template.fastingBaseline + Double((dayOffset % 4) * 2 + 2)
            bloodSugar.append(
                BloodSugarReadingRecord(
                    id: idGenerator.uuid("bloodSugar/day\(dayOffset)/before"),
                    timestamp: dayAnchor,
                    glucoseValue: max(80, beforeMealValue),
                    readingType: .beforeMeal,
                    mealContext: context,
                    fromHealthKit: false,
                    notes: "Pre-meal check"
                )
            )

            let spike = Double((dayOffset % 6) * 6 + 16)
            let afterMealValue = beforeMealValue + spike
            bloodSugar.append(
                BloodSugarReadingRecord(
                    id: idGenerator.uuid("bloodSugar/day\(dayOffset)/after"),
                    timestamp: addingHours(2, to: dayAnchor),
                    glucoseValue: max(98, afterMealValue),
                    readingType: .afterMeal,
                    mealContext: context,
                    fromHealthKit: false,
                    notes: "2h post meal"
                )
            )
        }

        for dayOffset in 0..<72 {
            let date = addingDays(-dayOffset, to: now)
            let primarySupplement = template.supplements[dayOffset % template.supplements.count]
            let dosage = adjustedSupplementDosage(
                baseDosage: primarySupplement.dosage,
                supplementName: primarySupplement.name,
                dayOffset: dayOffset
            )
            supplements.append(
                SupplementLogRecord(
                    id: idGenerator.uuid("supplement/\(dayOffset)"),
                    date: date,
                    supplementName: primarySupplement.name,
                    dosageMg: dosage,
                    dosageUnit: Self.demoDosageUnit(for: primarySupplement.name).rawValue,
                    timeTaken: addingHours(-(dayOffset % 3), to: date),
                    taken: dayOffset % 6 != 0,
                    brand: primarySupplement.brand
                )
            )
        }

        for index in 0..<12 {
            let pattern = template.mealPatterns[index % template.mealPatterns.count]
            let timestamp = addingHours(-(index * 16), to: now)
            let feedbackSeverity = index % 3 == 0 ? nil : min(5, 2 + (index % 4))
            let feedbackNote = feedbackSeverity.map { _ in
                postMealFeedbackNote(for: scenario, index: index)
            }
            meals.append(
                MealEntryRecord(
                    id: idGenerator.uuid("meal/\(index)"),
                    timestamp: timestamp,
                    mealType: pattern.0,
                    mealDescription: pattern.2,
                    glycemicImpact: pattern.1,
                    photoData: nil,
                    carbsGrams: 24 + Double((index % 4) * 8),
                    proteinGrams: 18 + Double((index % 3) * 6),
                    fatGrams: 10 + Double((index % 2) * 5),
                    notes: "Demo meal entry",
                    selectedTemplateID: mealTemplateID(for: pattern.0, index: index),
                    postMealSymptomSeverity: feedbackSeverity,
                    postMealSymptomNote: feedbackNote,
                    postMealFeedbackTimestamp: feedbackSeverity == nil ? nil : addingHours(2, to: timestamp),
                    createdAt: timestamp,
                    updatedAt: timestamp
                )
            )
        }

        for dayOffset in 0..<45 {
            let date = addingDays(-dayOffset, to: now)
            dailyLogs.append(
                DailyLogRecord(
                    id: idGenerator.uuid("dailyLog/\(dayOffset)"),
                    date: date,
                    weight: 70.8 - Double(dayOffset) * 0.03,
                    sleepHours: 6.3 + Double(dayOffset % 5) * 0.35,
                    activeMinutes: 22 + (dayOffset % 6) * 7,
                    restingHeartRateBPM: 63 + Double((dayOffset % 7) - 3),
                    stressLevel: min(5, 2 + (dayOffset % 4)),
                    energyLevel: max(1, 4 - (dayOffset % 3)),
                    waterOz: 56 + (dayOffset % 5) * 6
                )
            )
        }

        let hairPhotoSeeds: [(offsetDays: Int, type: HairPhotoType, score: Int, source: String)] = [
            (84, .scalpPart, 62, "heuristic"),
            (56, .hairline, 59, "Core ML"),
            (42, .faceChin, 57, "heuristic"),
            (28, .scalpPart, 68, "Core ML"),
            (21, .faceChin, 61, "Core ML"),
            (14, .hairline, 66, "heuristic"),
            (7, .scalpPart, 71, "Core ML"),
        ]

        for (index, seed) in hairPhotoSeeds.enumerated() {
            let date = addingDays(-seed.offsetDays, to: now)
            hairPhotos.append(
                HairPhotoEntryRecord(
                    id: idGenerator.uuid("hairPhoto/\(index)"),
                    date: date,
                    photoType: seed.type,
                    photoData: demoPhotoData(),
                    notes: "Consistent lighting and angle",
                    analysisResult: "Estimated density score: \(seed.score)/100 (\(demoPhotoTypeName(seed.type)), \(seed.source))."
                )
            )
        }

        insights.append(contentsOf: makeInsights(for: scenario, referenceDate: now, idGenerator: idGenerator))

        return SettingsDataBackupRecords(
            cycles: cycles,
            cycleEntries: cycleEntries,
            symptoms: symptoms,
            bloodSugarReadings: bloodSugar,
            supplements: supplements,
            meals: meals,
            hairPhotos: hairPhotos,
            dailyLogs: dailyLogs,
            insights: insights
        )
    }

    func makePeriodEntries(
        cycleID: UUID,
        startDate: Date,
        periodDays: Int,
        notePrefix: String,
        idGenerator: StableIDGenerator,
        idNamespace: String
    ) -> [CycleEntryRecord] {
        let flowPattern: [FlowIntensity] = [.heavy, .medium, .medium, .light, .spotting, .light, .spotting]
        var entries: [CycleEntryRecord] = []

        for day in 0..<periodDays {
            let entryID = idGenerator.uuid("cycleEntry/\(idNamespace)/\(day)")
            let date = addingDays(day, to: startDate)
            let flow = flowPattern[safe: day] ?? .light
            entries.append(
                CycleEntryRecord(
                    id: entryID,
                    date: date,
                    flowIntensity: flow,
                    isPeriodDay: true,
                    cyclePhase: .menstrual,
                    notes: day == 0
                        ? "\(notePrefix): period started"
                        : nil,
                    createdAt: date,
                    cycleID: cycleID
                )
            )
        }

        return entries
    }

    func makePeriodSymptoms(
        from periodEntries: [CycleEntryRecord],
        scenario: DemoDataScenario,
        idGenerator: StableIDGenerator,
        idNamespace: String
    ) -> [SymptomEntryRecord] {
        var results: [SymptomEntryRecord] = []

        for (index, entry) in periodEntries.enumerated() {
            let crampsSeverity = min(5, 3 + (index % 3))
            results.append(
                SymptomEntryRecord(
                    id: idGenerator.uuid("symptom/period/\(idNamespace)/\(index)/primary"),
                    date: entry.date,
                    category: SymptomType.cramps.category,
                    symptomType: .cramps,
                    severity: crampsSeverity,
                    notes: "Period day \(index + 1) discomfort",
                    cycleEntryID: entry.id
                )
            )

            let secondaryType: SymptomType
            switch scenario {
            case .newlyDiagnosed:
                secondaryType = index % 2 == 0 ? .bloating : .fatigue
            case .symptomManagement:
                secondaryType = index % 2 == 0 ? .energyCrash : .cravings
            case .ttcFertility:
                secondaryType = index % 2 == 0 ? .pelvicPain : .breastTenderness
            }

            results.append(
                SymptomEntryRecord(
                    id: idGenerator.uuid("symptom/period/\(idNamespace)/\(index)/secondary"),
                    date: entry.date,
                    category: secondaryType.category,
                    symptomType: secondaryType,
                    severity: min(5, 2 + (index % 4)),
                    notes: "Associated symptom during menstrual phase",
                    cycleEntryID: entry.id
                )
            )
        }

        return results
    }

    func makeInsights(
        for scenario: DemoDataScenario,
        referenceDate: Date,
        idGenerator: StableIDGenerator
    ) -> [InsightRecord] {
        switch scenario {
        case .newlyDiagnosed:
            return [
                InsightRecord(
                    id: idGenerator.uuid("insight/\(scenario.rawValue)/0"),
                    generatedDate: addingDays(-2, to: referenceDate),
                    insightType: .cyclePattern,
                    title: "Your cycles vary widely",
                    content: "Recent cycles ranged from 37 to 63 days. This is common with PCOS and improves with consistent tracking.",
                    confidence: 0.58,
                    dataPointsUsed: 4,
                    actionable: true,
                    relatedSymptoms: ["cramps", "fatigue"]
                ),
                InsightRecord(
                    id: idGenerator.uuid("insight/\(scenario.rawValue)/1"),
                    generatedDate: addingDays(-1, to: referenceDate),
                    insightType: .symptomCorrelation,
                    title: "Fatigue often clusters around period start",
                    content: "Fatigue scores were higher in the first two days of menstrual bleeding.",
                    confidence: 0.63,
                    dataPointsUsed: 16,
                    actionable: true,
                    relatedSymptoms: ["fatigue", "cramps"]
                ),
            ]

        case .symptomManagement:
            return [
                InsightRecord(
                    id: idGenerator.uuid("insight/\(scenario.rawValue)/0"),
                    generatedDate: addingDays(-5, to: referenceDate),
                    insightType: .dietImpact,
                    title: "Acne breakouts correlate with high-GI meals 2-3 days prior",
                    content: "Breakout severity 2 days after high-GI days averaged 3.8/5 versus 2.6/5 after low-GI days (Δ 1.2/5, n=12, 74% confidence).",
                    confidence: 0.74,
                    dataPointsUsed: 12,
                    actionable: true,
                    relatedSymptoms: ["acne", "breakouts"]
                ),
                InsightRecord(
                    id: idGenerator.uuid("insight/\(scenario.rawValue)/1"),
                    generatedDate: addingDays(-4, to: referenceDate),
                    insightType: .supplementEfficacy,
                    title: "Cycle length shift with Inositol adherence",
                    content: "Your cycles were 8.0 days shorter in months with >80% Inositol adherence (34.0 vs 42.0 days; n=3+2; 78% confidence).",
                    confidence: 0.78,
                    dataPointsUsed: 5,
                    actionable: true,
                    relatedSymptoms: ["cravings"]
                ),
                InsightRecord(
                    id: idGenerator.uuid("insight/\(scenario.rawValue)/2"),
                    generatedDate: addingDays(-3, to: referenceDate),
                    insightType: .seasonalPattern,
                    title: "Symptoms vary by season",
                    content: "Your average symptom severity was highest in January (3.6/5) and lowest in June (2.4/5), a 1.2-point difference.",
                    confidence: 0.67,
                    dataPointsUsed: 54,
                    actionable: true,
                    relatedSymptoms: ["energy_crash", "breakouts"]
                ),
                InsightRecord(
                    id: idGenerator.uuid("insight/\(scenario.rawValue)/3"),
                    generatedDate: addingDays(-2, to: referenceDate),
                    insightType: .symptomCorrelation,
                    title: "7-day symptom severity forecast",
                    content: "Predicted symptom severity for the next 7 days averages 2.7/5 (range 2.2-3.3/5). Top weighted drivers: Sleep 28%, Stress 24%, Meal GI 20%. Forecast confidence: 71%.",
                    confidence: 0.71,
                    dataPointsUsed: 126,
                    actionable: true,
                    relatedSymptoms: ["energy_crash", "cravings", "breakouts"]
                ),
                InsightRecord(
                    id: idGenerator.uuid("insight/\(scenario.rawValue)/4"),
                    generatedDate: addingDays(-1, to: referenceDate),
                    insightType: .cyclePattern,
                    title: "Cycle length forecast range",
                    content: "Predicted next cycle length is 35 days (range 31-40 days, 69% confidence).",
                    confidence: 0.69,
                    dataPointsUsed: 37,
                    actionable: true,
                    relatedSymptoms: ["cravings"]
                ),
            ]

        case .ttcFertility:
            return [
                InsightRecord(
                    id: idGenerator.uuid("insight/\(scenario.rawValue)/0"),
                    generatedDate: addingDays(-4, to: referenceDate),
                    insightType: .cyclePattern,
                    title: "Fertility windows are broad across irregular cycles",
                    content: "Recent cycle lengths between 45 and 72 days suggest wider ovulation uncertainty windows.",
                    confidence: 0.61,
                    dataPointsUsed: 4,
                    actionable: true,
                    relatedSymptoms: ["pelvic_pain"]
                ),
                InsightRecord(
                    id: idGenerator.uuid("insight/\(scenario.rawValue)/1"),
                    generatedDate: addingDays(-1, to: referenceDate),
                    insightType: .sleepActivity,
                    title: "Higher stress days correlate with lower energy",
                    content: "When stress level is 4+, energy logs trend lower the next day.",
                    confidence: 0.66,
                    dataPointsUsed: 15,
                    actionable: true,
                    relatedSymptoms: ["anxious", "fatigue"]
                ),
            ]
        }
    }

    func addingDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    func addingHours(_ hours: Int, to date: Date) -> Date {
        calendar.date(byAdding: .hour, value: hours, to: date) ?? date
    }

    func atNoon(_ date: Date) -> Date {
        calendar.date(
            bySettingHour: 12,
            minute: 0,
            second: 0,
            of: date
        ) ?? date
    }

    func stableTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    func ovulationStatus(for scenario: DemoDataScenario, completedCycleIndex index: Int) -> OvulationStatus {
        switch scenario {
        case .newlyDiagnosed:
            let statuses: [OvulationStatus] = [.unknown, .anovulatory, .ovulatory, .unknown]
            return statuses[safe: index] ?? .unknown
        case .symptomManagement:
            let statuses: [OvulationStatus] = [.ovulatory, .anovulatory, .ovulatory, .unknown, .ovulatory]
            return statuses[safe: index] ?? .unknown
        case .ttcFertility:
            let statuses: [OvulationStatus] = [.anovulatory, .unknown, .ovulatory, .anovulatory]
            return statuses[safe: index] ?? .unknown
        }
    }

    func manualCycleLengthOverrideDays(for scenario: DemoDataScenario) -> Int {
        switch scenario {
        case .newlyDiagnosed:
            44
        case .symptomManagement:
            35
        case .ttcFertility:
            52
        }
    }

    func mealTemplateID(for mealType: MealType, index: Int) -> String {
        switch mealType {
        case .breakfast:
            let ids = ["breakfast.greek-yogurt-berries", "breakfast.veggie-omelet", "breakfast.protein-oats"]
            return ids[index % ids.count]
        case .lunch:
            let ids = ["lunch.chicken-quinoa-bowl", "lunch.salmon-salad", "lunch.lentil-bowl"]
            return ids[index % ids.count]
        case .dinner:
            let ids = ["dinner.salmon-veggies", "dinner.turkey-chili", "dinner.tofu-stirfry"]
            return ids[index % ids.count]
        case .snack:
            let ids = ["snack.apple-nut-butter", "snack.greek-yogurt", "snack.nuts-seeds"]
            return ids[index % ids.count]
        }
    }

    func postMealFeedbackNote(for scenario: DemoDataScenario, index: Int) -> String {
        switch scenario {
        case .newlyDiagnosed:
            let notes = [
                "Mild bloating after lunch.",
                "Energy dipped about 90 minutes later.",
                "Felt stable after this meal."
            ]
            return notes[index % notes.count]
        case .symptomManagement:
            let notes = [
                "Steady energy for 3 hours.",
                "Cravings increased later in the evening.",
                "Light bloating but no crash.",
                "Felt good after swapping refined carbs."
            ]
            return notes[index % notes.count]
        case .ttcFertility:
            let notes = [
                "Mild nausea resolved quickly.",
                "No significant symptoms after meal.",
                "Felt a small energy drop mid-afternoon."
            ]
            return notes[index % notes.count]
        }
    }

    func bloodSugarMealContext(for dayOffset: Int) -> String {
        let contexts = [
            "lunch bowl",
            "dinner stir-fry",
            "rice bowl",
            "high-fiber breakfast"
        ]
        return contexts[dayOffset % contexts.count]
    }

    static func demoDosageUnit(for supplementName: String) -> DosageUnit {
        let normalized = supplementName.lowercased()
        if normalized.contains("vitamin d") { return .internationalUnit }
        if normalized.contains("folate") || normalized.contains("chromium") { return .microgram }
        return .milligram
    }

    func adjustedSupplementDosage(
        baseDosage: Double,
        supplementName: String,
        dayOffset: Int
    ) -> Double {
        let periodIndex = max(0, 2 - min(dayOffset / 24, 2))
        let normalizedName = supplementName.lowercased()

        let stepSize: Double
        if normalizedName.contains("inositol") {
            stepSize = 500
        } else if normalizedName.contains("magnesium") {
            stepSize = 50
        } else if normalizedName.contains("omega") {
            stepSize = 200
        } else if normalizedName.contains("coq10") {
            stepSize = 50
        } else {
            stepSize = 0
        }

        return max(1, baseDosage + Double(periodIndex) * stepSize)
    }

    func demoPhotoData() -> Data {
        let onePixelPNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7+qXQAAAAASUVORK5CYII="
        if let decoded = Data(base64Encoded: onePixelPNG) {
            return decoded
        }
        return Data([0x89, 0x50, 0x4E, 0x47])
    }

    func demoPhotoTypeName(_ type: HairPhotoType) -> String {
        switch type {
        case .scalpPart: "Scalp Part"
        case .hairline: "Hairline"
        case .faceChin: "Chin"
        case .faceUpperLip: "Upper Lip"
        case .body: "Body"
        }
    }

    func demoSymptomDisplayName(_ symptomType: SymptomType) -> String {
        switch symptomType {
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
}

private struct StableIDGenerator {
    let namespace: String

    func uuid(_ path: String) -> UUID {
        let digest = SHA256.hash(data: Data("\(namespace)|\(path)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

struct DemoOnboardingDefaults: Sendable {
    var primaryGoal: PrimaryGoal
    var experience: PCOSExperience
    var focusAreas: [SymptomFocusArea]
}

extension DemoDataScenario {
    var onboardingDefaults: DemoOnboardingDefaults {
        switch self {
        case .newlyDiagnosed:
            return DemoOnboardingDefaults(
                primaryGoal: .trackCycles,
                experience: .newlyDiagnosed,
                focusAreas: [.painCramps, .moodEnergy]
            )
        case .symptomManagement:
            return DemoOnboardingDefaults(
                primaryGoal: .understandSymptoms,
                experience: .experienced,
                focusAreas: [.moodEnergy, .digestionWeight, .skinHair]
            )
        case .ttcFertility:
            return DemoOnboardingDefaults(
                primaryGoal: .trackCycles,
                experience: .experienced,
                focusAreas: [.painCramps, .digestionWeight]
            )
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
