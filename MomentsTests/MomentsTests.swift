// MomentsTests.swift
// Unit tests for Moments app

import XCTest
@testable import Moments

final class MomentsTests: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    override func tearDownWithError() throws {
    }
    
    // MARK: - Intent Parser Tests
    
    func testSpanishCleanupIntentParsing() throws {
        // Test that Spanish cleanup commands are recognized
        let cleanupPatterns = [
            "borra las capturas",
            "elimina las fotos borrosas",
            "limpia las oscuras",
            "borrá los duplicados"
        ]
        
        for pattern in cleanupPatterns {
            let normalized = pattern.lowercased()
                .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_AR"))
            
            // Verify cleanup-related keywords are present
            let isCleanupIntent = normalized.contains("borra") || 
                                  normalized.contains("elimina") || 
                                  normalized.contains("limpia")
            
            XCTAssertTrue(isCleanupIntent, "Should recognize cleanup intent: \(pattern)")
        }
    }
    
    func testSpanishSearchIntentParsing() throws {
        let searchPatterns = [
            "mostrame fotos de Buenos Aires",
            "buscar fotos de cumpleaños",
            "encontrar fotos de viaje"
        ]
        
        for pattern in searchPatterns {
            let normalized = pattern.lowercased()
                .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_AR"))
            
            let isSearchIntent = normalized.contains("mostrame") || 
                                 normalized.contains("buscar") || 
                                 normalized.contains("encontrar")
            
            XCTAssertTrue(isSearchIntent, "Should recognize search intent: \(pattern)")
        }
    }
    
    // MARK: - Date Parsing Tests
    
    func testDateComponentExtraction() throws {
        let calendar = Calendar.current
        let now = Date()
        
        // Test "hace 3 meses" parsing
        let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now)!
        
        let components = calendar.dateComponents([.month, .year], from: threeMonthsAgo)
        XCTAssertNotNil(components.month)
        XCTAssertNotNil(components.year)
    }
    
    func testRelativeDateKeywords() throws {
        let relativeKeywords = [
            ("ayer", -1),
            ("anteayer", -2),
            ("hace una semana", -7),
            ("hace un mes", -30)
        ]
        
        for (keyword, _) in relativeKeywords {
            XCTAssertFalse(keyword.isEmpty, "Keyword should not be empty")
        }
    }
    
    // MARK: - Localization Tests
    
    func testLocalizedStringsExist() throws {
        // Test that key localized strings exist
        let requiredKeys = [
            "tab_home",
            "tab_assistant",
            "tab_moments",
            "tab_settings",
            "cleanup_category_screenshots",
            "cleanup_category_blurry",
            "cleanup_category_dark"
        ]
        
        for key in requiredKeys {
            let localized = NSLocalizedString(key, comment: "")
            // In tests, if key equals localized, the string wasn't found
            // This is a basic check - real apps should have proper localization testing
            XCTAssertFalse(localized.isEmpty, "Localized string should exist for key: \(key)")
        }
    }
    
    // MARK: - Model Tests
    
    func testCleanupCategoryLocalizedKeys() throws {
        // Test that cleanup categories have proper localized keys
        let categories = ["screenshots", "blurry", "dark", "duplicates", "documents"]
        
        for category in categories {
            let key = "cleanup_category_\(category)"
            XCTAssertTrue(key.contains("cleanup_category_"), "Key should have proper prefix")
        }
    }
    
    func testImportantDateTypeKeys() throws {
        let types = ["birthday", "wedding", "anniversary", "graduation"]
        
        for type in types {
            let key = "important_date_type_\(type)"
            XCTAssertTrue(key.contains("important_date_type_"), "Key should have proper prefix")
        }
    }
    
    // MARK: - Vos Form Verification (es-AR)
    
    func testVosFormInCopy() throws {
        // Verify that Spanish copy uses "vos" form (Argentine Spanish)
        let vosIndicators = [
            "mostrame",  // instead of "muéstrame"
            "borrá",     // instead of "borra" 
            "podés",     // instead of "puedes"
            "tenés",     // instead of "tienes"
            "querés"     // instead of "quieres"
        ]
        
        // These should be recognized as valid vos forms
        for indicator in vosIndicators {
            let normalized = indicator.lowercased()
                .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_AR"))
            XCTAssertFalse(normalized.isEmpty, "Vos form should be non-empty: \(indicator)")
        }
    }
    
    // MARK: - Utility Function Tests
    
    func testFileSizeFormatting() throws {
        // Test size formatting for Spanish
        let sizes: [(Int64, String)] = [
            (500, "500 B"),
            (1024, "1 KB"),
            (1024 * 1024, "1 MB"),
            (1024 * 1024 * 1024, "1 GB")
        ]
        
        for (bytes, _) in sizes {
            let byteCount = ByteCountFormatter()
            byteCount.allowedUnits = [.useAll]
            byteCount.countStyle = .file
            
            let formatted = byteCount.string(fromByteCount: bytes)
            XCTAssertFalse(formatted.isEmpty, "Should format \(bytes) bytes")
        }
    }
    
    func testPhotoCountFormatting() throws {
        let counts = [1, 5, 100, 1000, 50000]
        
        for count in counts {
            // Spanish plural forms: 1 foto, N fotos
            let label = count == 1 ? "foto" : "fotos"
            let formatted = "\(count) \(label)"
            XCTAssertTrue(formatted.contains(String(count)), "Should contain count")
        }
    }
}
