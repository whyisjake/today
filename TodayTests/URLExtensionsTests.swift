//
//  URLExtensionsTests.swift
//  TodayTests
//
//  Tests for URL UTM parameter extension
//

import XCTest
@testable import Today

final class URLExtensionsTests: XCTestCase {
    
    func testAddingUTMParametersToSimpleURL() {
        let originalURL = URL(string: "https://example.com/article")!
        let modifiedURL = originalURL.addingUTMParameters()
        
        XCTAssertNotNil(modifiedURL)
        XCTAssertTrue(modifiedURL.absoluteString.contains("utm_source=today_app"))
        XCTAssertTrue(modifiedURL.absoluteString.contains("utm_medium=ios_share"))
    }
    
    func testAddingUTMParametersToURLWithExistingQuery() {
        let originalURL = URL(string: "https://example.com/article?id=123")!
        let modifiedURL = originalURL.addingUTMParameters()
        
        XCTAssertNotNil(modifiedURL)
        // Should preserve existing query parameter
        XCTAssertTrue(modifiedURL.absoluteString.contains("id=123"))
        // Should add UTM parameters
        XCTAssertTrue(modifiedURL.absoluteString.contains("utm_source=today_app"))
        XCTAssertTrue(modifiedURL.absoluteString.contains("utm_medium=ios_share"))
    }
    
    func testAddingUTMParametersWithCampaign() {
        let originalURL = URL(string: "https://example.com/article")!
        let modifiedURL = originalURL.addingUTMParameters(campaign: "winter_2024")
        
        XCTAssertNotNil(modifiedURL)
        XCTAssertTrue(modifiedURL.absoluteString.contains("utm_source=today_app"))
        XCTAssertTrue(modifiedURL.absoluteString.contains("utm_medium=ios_share"))
        XCTAssertTrue(modifiedURL.absoluteString.contains("utm_campaign=winter_2024"))
    }
    
    func testAddingUTMParametersWithCustomSourceAndMedium() {
        let originalURL = URL(string: "https://example.com/article")!
        let modifiedURL = originalURL.addingUTMParameters(source: "custom_source", medium: "custom_medium")
        
        XCTAssertNotNil(modifiedURL)
        XCTAssertTrue(modifiedURL.absoluteString.contains("utm_source=custom_source"))
        XCTAssertTrue(modifiedURL.absoluteString.contains("utm_medium=custom_medium"))
    }
    
    func testPreservesFragment() {
        let originalURL = URL(string: "https://example.com/article#section1")!
        let modifiedURL = originalURL.addingUTMParameters()
        
        XCTAssertNotNil(modifiedURL)
        XCTAssertTrue(modifiedURL.absoluteString.contains("#section1"))
        XCTAssertTrue(modifiedURL.absoluteString.contains("utm_source=today_app"))
    }
    
    func testHandlesComplexURL() {
        let originalURL = URL(string: "https://example.com/article?id=123&category=tech#overview")!
        let modifiedURL = originalURL.addingUTMParameters()
        
        XCTAssertNotNil(modifiedURL)
        // Preserve original parameters and fragment
        XCTAssertTrue(modifiedURL.absoluteString.contains("id=123"))
        XCTAssertTrue(modifiedURL.absoluteString.contains("category=tech"))
        XCTAssertTrue(modifiedURL.absoluteString.contains("#overview"))
        // Add UTM parameters
        XCTAssertTrue(modifiedURL.absoluteString.contains("utm_source=today_app"))
        XCTAssertTrue(modifiedURL.absoluteString.contains("utm_medium=ios_share"))
    }
    
    func testURLComponentsAreValidQueryItems() {
        let originalURL = URL(string: "https://example.com/article")!
        let modifiedURL = originalURL.addingUTMParameters()
        
        guard let components = URLComponents(url: modifiedURL, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems else {
            XCTFail("Failed to parse URL components")
            return
        }
        
        // Verify query items are properly structured
        XCTAssertTrue(queryItems.contains(where: { $0.name == "utm_source" && $0.value == "today_app" }))
        XCTAssertTrue(queryItems.contains(where: { $0.name == "utm_medium" && $0.value == "ios_share" }))
    }
}
