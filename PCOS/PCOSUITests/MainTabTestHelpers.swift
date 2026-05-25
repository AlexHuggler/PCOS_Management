import XCTest

func insightDisclosureButtonPredicate() -> NSPredicate {
    NSPredicate(format: "identifier ENDSWITH %@", ".learn_more_button")
}

enum MainTab: Int, CaseIterable {
    case today = 0
    case calendar
    case track
    case insights
    case settings

    var identifier: String {
        switch self {
        case .today:
            "tab.today"
        case .calendar:
            "tab.calendar"
        case .track:
            "tab.track"
        case .insights:
            "tab.insights"
        case .settings:
            "tab.settings"
        }
    }
}

@MainActor
func tapMainTab(
    _ tab: MainTab,
    in app: XCUIApplication,
    timeout: TimeInterval = 10,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    mainTabElement(tab, in: app, timeout: timeout, file: file, line: line).tap()
}

@MainActor
func mainTabElement(
    _ tab: MainTab,
    in app: XCUIApplication,
    timeout: TimeInterval = 10,
    file: StaticString = #filePath,
    line: UInt = #line
) -> XCUIElement {
    let customButton = app.buttons[tab.identifier]
    if customButton.exists {
        return customButton
    }

    let tabBar = app.tabBars.firstMatch
    if tabBar.exists {
        XCTAssertGreaterThanOrEqual(tabBar.buttons.count, MainTab.allCases.count, file: file, line: line)
        return tabBar.buttons.element(boundBy: tab.rawValue)
    }

    if customButton.waitForExistence(timeout: 2) {
        return customButton
    }

    XCTAssertTrue(tabBar.waitForExistence(timeout: timeout), "Missing main tab shell", file: file, line: line)
    XCTAssertGreaterThanOrEqual(tabBar.buttons.count, MainTab.allCases.count, file: file, line: line)
    return tabBar.buttons.element(boundBy: tab.rawValue)
}

@MainActor
func assertMainTabShellPresent(
    in app: XCUIApplication,
    timeout: TimeInterval = 10,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let customBar = app.otherElements["botanical.tab_bar"]
    let firstCustomTab = app.buttons[MainTab.today.identifier]
    if customBar.exists || firstCustomTab.exists {
        for tab in MainTab.allCases {
            XCTAssertTrue(app.buttons[tab.identifier].exists, "Missing custom tab \(tab.identifier)", file: file, line: line)
        }
        return
    }

    let tabBar = app.tabBars.firstMatch
    if tabBar.exists {
        XCTAssertGreaterThanOrEqual(tabBar.buttons.count, MainTab.allCases.count, file: file, line: line)
        return
    }

    if customBar.waitForExistence(timeout: 1) || firstCustomTab.waitForExistence(timeout: 1) {
        for tab in MainTab.allCases {
            XCTAssertTrue(app.buttons[tab.identifier].exists, "Missing custom tab \(tab.identifier)", file: file, line: line)
        }
        return
    }

    XCTAssertTrue(tabBar.waitForExistence(timeout: timeout), "Missing main tab shell", file: file, line: line)
    XCTAssertGreaterThanOrEqual(tabBar.buttons.count, MainTab.allCases.count, file: file, line: line)
}

@MainActor
func assertMainTabLabel(
    _ tab: MainTab,
    equals expectedLabel: String,
    in app: XCUIApplication,
    timeout: TimeInterval = 5,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let customButton = app.buttons[tab.identifier]
    if customButton.exists {
        XCTAssertEqual(customButton.label, expectedLabel, file: file, line: line)
        return
    }

    let tabBar = app.tabBars.firstMatch
    if tabBar.exists {
        XCTAssertTrue(
            tabBar.buttons[expectedLabel].exists || tabBar.staticTexts[expectedLabel].exists,
            "Missing tab label '\(expectedLabel)'. Visible labels: \(visibleMainTabLabels(in: app))",
            file: file,
            line: line
        )
        return
    }

    if customButton.waitForExistence(timeout: 1) {
        XCTAssertEqual(customButton.label, expectedLabel, file: file, line: line)
        return
    }

    XCTAssertTrue(tabBar.waitForExistence(timeout: timeout), "Missing main tab shell", file: file, line: line)
    XCTAssertTrue(
        tabBar.buttons[expectedLabel].exists || tabBar.staticTexts[expectedLabel].exists,
        "Missing tab label '\(expectedLabel)'. Visible labels: \(visibleMainTabLabels(in: app))",
        file: file,
        line: line
    )
}

@MainActor
func mainTabShellContainsLabel(_ label: String, in app: XCUIApplication) -> Bool {
    for tab in MainTab.allCases {
        let customButton = app.buttons[tab.identifier]
        if customButton.exists && customButton.label == label {
            return true
        }
    }

    let tabBar = app.tabBars.firstMatch
    guard tabBar.exists else { return false }
    return tabBar.buttons[label].exists || tabBar.staticTexts[label].exists
}

@MainActor
func visibleMainTabLabels(in app: XCUIApplication) -> [String] {
    let customLabels = MainTab.allCases
        .map { app.buttons[$0.identifier] }
        .filter(\.exists)
        .map(\.label)
    if !customLabels.isEmpty {
        return Array(Set(customLabels)).sorted()
    }

    let tabBar = app.tabBars.firstMatch
    guard tabBar.exists else { return [] }
    let buttonLabels = tabBar.buttons.allElementsBoundByIndex.map(\.label)
    let textLabels = tabBar.staticTexts.allElementsBoundByIndex.map(\.label)
    return Array(Set(buttonLabels + textLabels)).sorted()
}

@MainActor
func firstVisibleInsightDisclosureButton(
    in app: XCUIApplication,
    timeout: TimeInterval = 1,
    maxSwipes: Int = 5
) -> XCUIElement {
    let button = app.buttons.matching(insightDisclosureButtonPredicate()).firstMatch
    if button.waitForExistence(timeout: timeout) {
        return button
    }

    for _ in 0..<maxSwipes {
        app.swipeUp()
        if button.waitForExistence(timeout: 1) {
            return button
        }
    }

    for _ in 0..<maxSwipes {
        app.swipeDown()
        if button.waitForExistence(timeout: 1) {
            return button
        }
    }

    return button
}
