// GeocodingService.swift
// Servicio para reverse geocoding con cache

import Foundation
import CoreLocation

actor GeocodingService {
    static let shared = GeocodingService()
    
    private let geocoder = CLGeocoder()
    private var cache: [String: CachedLocation] = [:]
    private let cacheExpiration: TimeInterval = 60 * 60 * 24 * 30 // 30 días
    
    struct CachedLocation: Codable {
        let name: String
        let city: String?
        let country: String?
        let timestamp: Date
    }
    
    private init() {
        loadCache()
    }
    
    // MARK: - Public Methods
    
    func getLocationName(latitude: Double, longitude: Double) async -> (name: String, city: String?, country: String?)? {
        let cacheKey = "\(latitude.rounded(to: 4)),\(longitude.rounded(to: 4))"
        
        // Verificar cache
        if let cached = cache[cacheKey], !isCacheExpired(cached) {
            return (cached.name, cached.city, cached.country)
        }
        
        // Reverse geocoding
        let location = CLLocation(latitude: latitude, longitude: longitude)
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            
            guard let placemark = placemarks.first else { return nil }
            
            let name = placemark.name ?? placemark.locality ?? placemark.administrativeArea ?? "Ubicación"
            let city = placemark.locality
            let country = placemark.country
            
            // Guardar en cache
            let cached = CachedLocation(name: name, city: city, country: country, timestamp: Date())
            cache[cacheKey] = cached
            saveCache()
            
            return (name, city, country)
            
        } catch {
            print("Geocoding error: \(error)")
            return nil
        }
    }
    
    func getPlaceName(latitude: Double, longitude: Double) async -> String {
        guard let result = await getLocationName(latitude: latitude, longitude: longitude) else {
            return "Ubicación desconocida"
        }
        return result.name
    }
    
    // MARK: - Cache Management
    
    private var cacheFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("geocoding_cache.json")
    }
    
    private func loadCache() {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: cacheFileURL)
            cache = try JSONDecoder().decode([String: CachedLocation].self, from: data)
            
            // Limpiar entradas expiradas
            let now = Date()
            cache = cache.filter { !isCacheExpired($0.value, now: now) }
            
        } catch {
            print("Error loading geocoding cache: \(error)")
        }
    }
    
    private func saveCache() {
        do {
            let data = try JSONEncoder().encode(cache)
            try data.write(to: cacheFileURL)
        } catch {
            print("Error saving geocoding cache: \(error)")
        }
    }
    
    private func isCacheExpired(_ cached: CachedLocation, now: Date = Date()) -> Bool {
        now.timeIntervalSince(cached.timestamp) > cacheExpiration
    }
    
    func clearCache() {
        cache.removeAll()
        try? FileManager.default.removeItem(at: cacheFileURL)
    }
}

// MARK: - Double Extension

fileprivate extension Double {
    func rounded(to places: Int) -> Double {
        let multiplier = pow(10, Double(places))
        return (self * multiplier).rounded() / multiplier
    }
}
