//
//  HealthService.swift
//  Daymark
//
//  HealthKit reads for the scorecard: fitness fills itself from real
//  activity. A "fitness day" this week = a logged workout, 30+ exercise
//  minutes, or 8,000+ steps. Read-only; nothing leaves the device.
//

import Foundation
import HealthKit

@MainActor
final class HealthService {
    private let store = HKHealthStore()
    private(set) var authorized = false

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async -> Bool {
        guard Self.isAvailable else { return false }
        let types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.appleExerciseTime),
            HKQuantityType(.stepCount),
        ]
        do {
            try await store.requestAuthorization(toShare: [], read: types)
            authorized = true
            return true
        } catch {
            return false
        }
    }

    /// Days since Monday that count as a fitness day.
    func fitnessDaysThisWeek() async -> Int {
        guard Self.isAvailable else { return 0 }
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now) // 1 = Sunday
        let sinceMonday = (weekday + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -sinceMonday, to: calendar.startOfDay(for: now))
        else { return 0 }

        var qualifying = Set<String>()
        let dayKeyFormatter = DateFormatter()
        dayKeyFormatter.dateFormat = "yyyy-MM-dd"

        // Workouts
        if let workouts = try? await samples(
            of: HKObjectType.workoutType(),
            from: monday, to: now
        ) {
            for workout in workouts {
                qualifying.insert(dayKeyFormatter.string(from: workout.startDate))
            }
        }

        // Exercise minutes + steps, per day
        for offset in 0...sinceMonday {
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: monday) else { continue }
            let dayEnd = min(now, calendar.date(byAdding: .day, value: 1, to: dayStart) ?? now)
            let key = dayKeyFormatter.string(from: dayStart)
            if qualifying.contains(key) { continue }

            let exercise = await quantitySum(.appleExerciseTime, unit: .minute(), from: dayStart, to: dayEnd)
            if exercise >= 30 {
                qualifying.insert(key)
                continue
            }
            let steps = await quantitySum(.stepCount, unit: .count(), from: dayStart, to: dayEnd)
            if steps >= 8000 {
                qualifying.insert(key)
            }
        }
        return qualifying.count
    }

    // MARK: HK plumbing

    private func samples(of type: HKSampleType, from start: Date, to end: Date) async throws -> [HKSample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: results ?? []) }
            }
            store.execute(query)
        }
    }

    private func quantitySum(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> Double {
        let type = HKQuantityType(identifier)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                          options: .cumulativeSum) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(query)
        }
    }
}
