// FoundationModelsClient.swift
// On-device Apple Intelligence wrapper with a rule-based fallback.

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum FoundationModelsClient {
    static var isDefaultModelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.availability != .unavailable
        }
        #endif
        return false
    }
    
    static func parseQuery(_ text: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard isDefaultModelAvailable else { return nil }
            do {
                let session = LanguageModelSession(model: SystemLanguageModel.default)
                let response = try await session.respond(to: text)
                return String(describing: response)
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }
    
    static func recapNarrative(monthName: String, stats: String) async -> String? {
        let prompt = "Escribí en español rioplatense (vos) un recap breve y cálido de \(monthName). Datos: \(stats)"
        return await parseQuery(prompt)
    }
}
