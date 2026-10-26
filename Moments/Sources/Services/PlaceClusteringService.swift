// PlaceClusteringService.swift
// Servicio para agrupar fotos por ubicación y detectar home/work/trips

import Foundation
import SwiftData
import CoreLocation

@MainActor
class PlaceClusteringService: ObservableObject {
    private var modelContext: ModelContext?
    private let geocodingService = GeocodingService.shared
    
    // Clustering parameters
    private let clusterRadiusMeters: Double = 100
    private let minPhotosForCluster: Int = 5
    private let homeMinVisitDays: Int = 30
    private let workMinVisitDays: Int = 10
    
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // MARK: - Cluster Detection
    
    func buildPlaceClusters() async {
        guard let context = modelContext else { return }
        
        do {
            // Fetch all photos with location
            let descriptor = FetchDescriptor<PersistedPhoto>(
                predicate: #Predicate { $0.latitude != nil && $0.longitude != nil }
            )
            
            let photos = try context.fetch(descriptor)
            
            // Group photos by location
            var locationGroups: [[PersistedPhoto]] = []
            var processedIds: Set<String> = []
            
            for photo in photos {
                guard !processedIds.contains(photo.id),
                      let lat = photo.latitude,
                      let lon = photo.longitude else { continue }
                
                var cluster: [PersistedPhoto] = [photo]
                processedIds.insert(photo.id)
                
                let photoLocation = CLLocation(latitude: lat, longitude: lon)
                
                // Find all nearby photos
                for otherPhoto in photos {
                    guard !processedIds.contains(otherPhoto.id),
                          let otherLat = otherPhoto.latitude,
                          let otherLon = otherPhoto.longitude else { continue }
                    
                    let otherLocation = CLLocation(latitude: otherLat, longitude: otherLon)
                    let distance = photoLocation.distance(from: otherLocation)
                    
                    if distance <= clusterRadiusMeters {
                        cluster.append(otherPhoto)
                        processedIds.insert(otherPhoto.id)
                    }
                }
                
                if cluster.count >= minPhotosForCluster {
                    locationGroups.append(cluster)
                }
            }
            
            // Create or update place clusters
            for group in locationGroups {
                await createOrUpdateCluster(for: group)
            }
            
            // Detect home and work
            await detectHomeAndWork()
            
            try context.save()
            
        } catch {
            print("Error building place clusters: \(error)")
        }
    }
    
    private func createOrUpdateCluster(for photos: [PersistedPhoto]) async {
        guard let context = modelContext else { return }
        
        // Calculate centroid
        let validPhotos = photos.compactMap { photo -> (lat: Double, lon: Double, date: Date?)? in
            guard let lat = photo.latitude, let lon = photo.longitude else { return nil }
            return (lat, lon, photo.creationDate)
        }
        
        guard !validPhotos.isEmpty else { return }
        
        let avgLat = validPhotos.reduce(0.0) { $0 + $1.lat } / Double(validPhotos.count)
        let avgLon = validPhotos.reduce(0.0) { $0 + $1.lon } / Double(validPhotos.count)
        
        // Check if cluster already exists
        let existingDescriptor = FetchDescriptor<PersistedPlaceCluster>()
        let existingClusters = (try? context.fetch(existingDescriptor)) ?? []
        
        var matchingCluster: PersistedPlaceCluster?
        let centroid = CLLocation(latitude: avgLat, longitude: avgLon)
        
        for cluster in existingClusters {
            let clusterLocation = CLLocation(latitude: cluster.latitude, longitude: cluster.longitude)
            if centroid.distance(from: clusterLocation) <= clusterRadiusMeters * 2 {
                matchingCluster = cluster
                break
            }
        }
        
        // Calculate visit stats
        let dates = validPhotos.compactMap { $0.date }
        let sortedDates = dates.sorted()
        let firstVisit = sortedDates.first
        let lastVisit = sortedDates.last
        
        // Count unique days
        let calendar = Calendar.current
        let uniqueDays = Set(dates.map { calendar.startOfDay(for: $0) }).count
        
        // Reverse geocode
        var address: String?
        var city: String?
        var country: String?
        
        if let locationInfo = await geocodingService.getLocationName(latitude: avgLat, longitude: avgLon) {
            address = locationInfo.name
            city = locationInfo.city
            country = locationInfo.country
        }
        
        if let cluster = matchingCluster {
            // Update existing cluster
            cluster.photoCount = photos.count
            cluster.latitude = avgLat
            cluster.longitude = avgLon
            cluster.address = address
            cluster.city = city
            cluster.country = country
            cluster.firstVisit = firstVisit
            cluster.lastVisit = lastVisit
            cluster.visitCount = uniqueDays
            
            // Update photos with cluster ID
            for photo in photos {
                photo.placeClusterId = cluster.id
            }
        } else {
            // Create new cluster
            let cluster = PersistedPlaceCluster(
                latitude: avgLat,
                longitude: avgLon,
                address: address,
                city: city,
                country: country,
                photoCount: photos.count,
                firstVisit: firstVisit,
                lastVisit: lastVisit,
                visitCount: uniqueDays
            )
            context.insert(cluster)
            
            // Update photos with cluster ID
            for photo in photos {
                photo.placeClusterId = cluster.id
            }
        }
    }
    
    // MARK: - Home/Work Detection
    
    private func detectHomeAndWork() async {
        guard let context = modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<PersistedPlaceCluster>(
                sortBy: [SortDescriptor(\.visitCount, order: .reverse)]
            )
            
            var clusters = try context.fetch(descriptor)
            
            // Skip already user-labeled clusters
            clusters = clusters.filter { !$0.isUserLabeled }
            
            guard !clusters.isEmpty else { return }
            
            // The most visited place is likely home
            if let homeCandidate = clusters.first,
               homeCandidate.visitCount >= homeMinVisitDays,
               homeCandidate.placeType == .unknown {
                homeCandidate.placeType = .home
                
                // Update analysis state
                let stateDescriptor = FetchDescriptor<AnalysisState>()
                if let state = try context.fetch(stateDescriptor).first {
                    state.homeLatitude = homeCandidate.latitude
                    state.homeLongitude = homeCandidate.longitude
                    state.homeConfidence = Double(homeCandidate.visitCount) / 100.0
                }
            }
            
            // Second most visited could be work
            // But only if visits are on weekdays
            if clusters.count > 1 {
                let workCandidates = clusters.dropFirst().filter { $0.visitCount >= workMinVisitDays }
                
                for candidate in workCandidates {
                    // For now, mark as frequent place
                    // More sophisticated work detection would analyze time-of-day patterns
                    if candidate.placeType == .unknown {
                        candidate.placeType = .frequentPlace
                    }
                }
            }
            
            // Detect trips: places visited for a few days but far from home
            if let home = clusters.first(where: { $0.placeType == .home }) {
                let homeLocation = CLLocation(latitude: home.latitude, longitude: home.longitude)
                
                for cluster in clusters where cluster.placeType == .unknown {
                    let clusterLocation = CLLocation(latitude: cluster.latitude, longitude: cluster.longitude)
                    let distanceFromHome = homeLocation.distance(from: clusterLocation)
                    
                    // More than 50km from home = potential trip
                    if distanceFromHome > 50_000 {
                        cluster.placeType = .tripDestination
                    }
                }
            }
            
            try context.save()
            
        } catch {
            print("Error detecting home/work: \(error)")
        }
    }
    
    // MARK: - Manual Labeling
    
    func labelCluster(_ clusterId: String, as type: PlaceClusterType, customName: String? = nil) {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<PersistedPlaceCluster>(
            predicate: #Predicate { $0.id == clusterId }
        )
        
        guard let cluster = try? context.fetch(descriptor).first else { return }
        
        cluster.placeType = type
        cluster.isUserLabeled = true
        
        if let name = customName {
            cluster.name = name
        }
        
        // If labeled as home, update analysis state
        if type == .home {
            let stateDescriptor = FetchDescriptor<AnalysisState>()
            if let state = try? context.fetch(stateDescriptor).first {
                state.homeLatitude = cluster.latitude
                state.homeLongitude = cluster.longitude
                state.homeConfidence = 1.0
            }
        }
        
        // If labeled as work, update analysis state
        if type == .work {
            let stateDescriptor = FetchDescriptor<AnalysisState>()
            if let state = try? context.fetch(stateDescriptor).first {
                state.workLatitude = cluster.latitude
                state.workLongitude = cluster.longitude
                state.workConfidence = 1.0
            }
        }
        
        try? context.save()
    }
    
    // MARK: - Unknown Clusters
    
    func getUnlabeledClusters(limit: Int = 10) -> [PersistedPlaceCluster] {
        guard let context = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<PersistedPlaceCluster>(
            predicate: #Predicate { $0.placeTypeRaw == "unknown" && !$0.isUserLabeled },
            sortBy: [SortDescriptor(\.photoCount, order: .reverse)]
        )
        
        let clusters = (try? context.fetch(descriptor)) ?? []
        return Array(clusters.prefix(limit))
    }
}
