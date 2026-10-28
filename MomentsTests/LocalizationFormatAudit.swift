// LocalizationFormatAudit.swift
// Parses .strings / .xcstrings format specifiers so a reordered
// "cataloging_from_app %@ %lld" = "Tenés %lld fotos de %@" cannot ship.

import Foundation

enum LocalizationFormatAudit {
    struct Specifier: Equatable {
        let position: Int
        let type: String
    }
    
    struct Finding: Equatable {
        let language: String
        let file: String
        let key: String
        let value: String
        let reason: String
    }
    
    struct CheckResult: Equatable {
        let isValid: Bool
        let reason: String
        
        static let ok = CheckResult(isValid: true, reason: "")
    }
    
    /// Sequential value specifiers must match the key's types in order.
    /// Positional value specifiers (`%2$lld`, `%1$@`) must map onto the same types.
    static func check(key: String, value: String) -> CheckResult {
        let keySpecs = extractSpecifiers(from: key)
        guard !keySpecs.isEmpty else { return .ok }
        
        let valueSpecs = extractSpecifiers(from: value)
        if valueSpecs.isEmpty {
            return CheckResult(
                isValid: false,
                reason: "key has \(keySpecs.map(\.type).joined(separator: ",")) but value has no specifiers"
            )
        }
        
        let keyByPosition = Dictionary(uniqueKeysWithValues: keySpecs.map { ($0.position, $0.type) })
        let usesPositional = value.contains("$")
        
        if usesPositional {
            for spec in valueSpecs {
                guard let keyType = keyByPosition[spec.position] else {
                    return CheckResult(
                        isValid: false,
                        reason: "positional %\(spec.position)$\(spec.type) has no matching key specifier"
                    )
                }
                if keyType != spec.type {
                    return CheckResult(
                        isValid: false,
                        reason: "position \(spec.position) is %\(keyType) in key but %\(spec.type) in value"
                    )
                }
            }
            return .ok
        }
        
        if valueSpecs.count != keySpecs.count {
            return CheckResult(
                isValid: false,
                reason: "key has \(keySpecs.count) specifiers, value has \(valueSpecs.count)"
            )
        }
        for (keySpec, valueSpec) in zip(keySpecs, valueSpecs) {
            if keySpec.type != valueSpec.type {
                return CheckResult(
                    isValid: false,
                    reason: "order/type mismatch: key \(describe(keySpecs)) vs value \(describe(valueSpecs))"
                )
            }
        }
        return .ok
    }
    
    static func extractSpecifiers(from format: String) -> [Specifier] {
        var specs: [Specifier] = []
        var sequential = 0
        let chars = Array(format)
        var i = 0
        while i < chars.count {
            if chars[i] != "%" {
                i += 1
                continue
            }
            if i + 1 < chars.count && chars[i + 1] == "%" {
                i += 2
                continue
            }
            var j = i + 1
            var position: Int?
            let startDigits = j
            while j < chars.count && chars[j].isNumber {
                j += 1
            }
            if startDigits < j && j < chars.count && chars[j] == "$" {
                position = Int(String(chars[startDigits..<j]))
                j += 1
            } else {
                j = i + 1
            }
            while j < chars.count && "+-# 0*.'".contains(chars[j]) {
                j += 1
            }
            while j < chars.count && (chars[j].isNumber || chars[j] == ".") {
                j += 1
            }
            var length = ""
            if j + 1 < chars.count && chars[j] == "h" && chars[j + 1] == "h" {
                length = "hh"; j += 2
            } else if j + 1 < chars.count && chars[j] == "l" && chars[j + 1] == "l" {
                length = "ll"; j += 2
            } else if j < chars.count && "hlLztj".contains(chars[j]) {
                length = String(chars[j]); j += 1
            }
            guard j < chars.count, "@diouxXfFeEgGcsapn".contains(chars[j]) else {
                i += 1
                continue
            }
            let type = length + String(chars[j])
            if position == nil {
                sequential += 1
                position = sequential
            }
            specs.append(Specifier(position: position!, type: type))
            i = j + 1
        }
        return specs
    }
    
    static func auditFiles(in resourcesDirectory: URL) throws -> [Finding] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: resourcesDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        
        var findings: [Finding] = []
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            if ext == "strings" {
                findings.append(contentsOf: auditStringsFile(fileURL))
            } else if ext == "xcstrings" {
                findings.append(contentsOf: try auditXCStringsFile(fileURL))
            }
        }
        return findings
    }
    
    static func resourcesDirectoryFromTestFile(_ filePath: String = #filePath) -> URL {
        URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Moments/Resources", isDirectory: true)
    }
    
    private static func auditStringsFile(_ fileURL: URL) -> [Finding] {
        let language = fileURL.deletingLastPathComponent().deletingPathExtension().lastPathComponent
        guard let dict = NSDictionary(contentsOf: fileURL) as? [String: String] else {
            return [Finding(
                language: language,
                file: fileURL.lastPathComponent,
                key: "",
                value: "",
                reason: "could not parse \(fileURL.path)"
            )]
        }
        return dict.compactMap { key, value in
            let result = check(key: key, value: value)
            guard !result.isValid else { return nil }
            return Finding(
                language: language,
                file: fileURL.lastPathComponent,
                key: key,
                value: value,
                reason: result.reason
            )
        }
    }
    
    private static func auditXCStringsFile(_ fileURL: URL) throws -> [Finding] {
        let data = try Data(contentsOf: fileURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = root["strings"] as? [String: Any] else { return [] }
        
        var findings: [Finding] = []
        for (key, entry) in strings {
            guard let entryDict = entry as? [String: Any],
                  let localizations = entryDict["localizations"] as? [String: Any] else { continue }
            for (language, localization) in localizations {
                guard let loc = localization as? [String: Any],
                      let unit = loc["stringUnit"] as? [String: Any],
                      let value = unit["value"] as? String else { continue }
                let result = check(key: key, value: value)
                if !result.isValid {
                    findings.append(Finding(
                        language: language,
                        file: fileURL.lastPathComponent,
                        key: key,
                        value: value,
                        reason: result.reason
                    ))
                }
            }
        }
        return findings
    }
    
    private static func describe(_ specs: [Specifier]) -> String {
        specs.map { "%\($0.position)$\($0.type)" }.joined(separator: " ")
    }
}
