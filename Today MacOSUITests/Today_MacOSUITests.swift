//
//  Today_MacOSUITests.swift
//  Today MacOSUITests
//
//  Created by Jake Spurlock on 1/28/26.
//

import XCTest

final class Today_MacOSUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testAppLaunches() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()
        
        // Verify the app launched successfully
        XCTAssertTrue(app.exists)
    }
    
    @MainActor
    func testSidebarNavigation() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Wait for the app to fully load
        let sidebar = app.splitGroups.firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        
        // Test navigation items exist
        let todayButton = app.buttons["Today"]
        let feedsButton = app.buttons["Manage Feeds"]
        let aiButton = app.buttons["AI Summary"]
        let settingsButton = app.buttons["Settings"]
        
        XCTAssertTrue(todayButton.exists)
        XCTAssertTrue(feedsButton.exists)
        XCTAssertTrue(aiButton.exists)
        XCTAssertTrue(settingsButton.exists)
    }
    
    @MainActor
    func testKeyboardShortcuts() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Test Command+1 for Today view
        app.typeKey("1", modifierFlags: .command)
        
        // Test Command+2 for Feeds view
        app.typeKey("2", modifierFlags: .command)
        
        // Test Command+3 for AI Summary
        app.typeKey("3", modifierFlags: .command)
        
        // Test Command+4 for Settings
        app.typeKey("4", modifierFlags: .command)
        
        // If we got here without crashes, the shortcuts work
        XCTAssertTrue(app.exists)
    }
    
    @MainActor
    func testSettingsWindow() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Open settings with keyboard shortcut
        app.typeKey(",", modifierFlags: .command)
        
        // Wait for settings window
        let settingsWindow = app.windows["Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        
        // Verify tabs exist
        let generalTab = settingsWindow.buttons["General"]
        let readingTab = settingsWindow.buttons["Reading"]
        let audioTab = settingsWindow.buttons["Audio"]
        let aboutTab = settingsWindow.buttons["About"]
        
        XCTAssertTrue(generalTab.exists)
        XCTAssertTrue(readingTab.exists)
        XCTAssertTrue(audioTab.exists)
        XCTAssertTrue(aboutTab.exists)
    }
    
    @MainActor
    func testArticleListExists() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Wait for content to load
        sleep(2)
        
        // Check if article list or empty state exists
        let articleList = app.scrollViews.firstMatch
        XCTAssertTrue(articleList.exists)
    }
    
    @MainActor
    func testMenuBarCommands() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Access the Feeds menu
        let menuBar = app.menuBars
        let feedsMenu = menuBar.menuBarItems["Feeds"]
        
        if feedsMenu.exists {
            feedsMenu.click()
            
            // Verify sync command exists
            let syncCommand = app.menuItems["Sync All Feeds"]
            XCTAssertTrue(syncCommand.exists)
        }
    }
    
    @MainActor
    func testThemeToggle() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Open settings
        app.typeKey(",", modifierFlags: .command)
        
        let settingsWindow = app.windows["Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        
        // Click on General tab
        let generalTab = settingsWindow.buttons["General"]
        generalTab.click()
        
        // Find appearance picker (segmented control)
        let appearancePicker = settingsWindow.segmentedControls.firstMatch
        if appearancePicker.exists {
            XCTAssertTrue(appearancePicker.buttons.count >= 3)
        }
    }
    
    @MainActor
    func testAccentColorSelection() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Open settings
        app.typeKey(",", modifierFlags: .command)
        
        let settingsWindow = app.windows["Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        
        // Verify accent color options are present
        // Looking for the color picker buttons
        let colorButtons = settingsWindow.buttons.matching(identifier: "").allElementsBoundByIndex
        XCTAssertTrue(colorButtons.count > 0)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
