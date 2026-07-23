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
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKCategoryType(.sleepAnalysis),
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

    // MARK: Readiness

    struct Readiness {
        let sleepHours: Double?
        let restingHR: Double?
        let restingHRBaseline: Double?
        let hrv: Double?
        let hrvBaseline: Double?
        let score: Int          // -3...3
        let verdict: String     // "Recovered" / "Steady" / "Run it easy"
        let line: String        // the composed sentence
    }

    /// Last night against your own 30-day baselines, distilled to a line.
    func readiness() async -> Readiness? {
        guard Self.isAvailable else { return nil }
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)

        // Sleep: samples from 20:00 yesterday to 11:00 today.
        var sleepHours: Double?
        if let windowStart = calendar.date(byAdding: .hour, value: -4, to: todayStart),
           let windowEnd = calendar.date(byAdding: .hour, value: 11, to: todayStart),
           let sleepSamples = try? await samples(of: HKCategoryType(.sleepAnalysis),
                                                 from: windowStart, to: windowEnd) {
            let asleep = sleepSamples.compactMap { $0 as? HKCategorySample }.filter {
                HKCategoryValueSleepAnalysis.allAsleepValues
                    .contains(HKCategoryValueSleepAnalysis(rawValue: $0.value) ?? .inBed)
            }
            let seconds = asleep.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            if seconds > 0 { sleepHours = seconds / 3600 }
        }

        // Resting HR + HRV: last day-and-a-half vs the 30-day baseline.
        let monthAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let dayAgo = calendar.date(byAdding: .hour, value: -36, to: now) ?? now
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let rhr = await quantityAverage(.restingHeartRate, unit: bpm, from: dayAgo, to: now)
        let rhrBase = await quantityAverage(.restingHeartRate, unit: bpm, from: monthAgo, to: now)
        let hrv = await quantityAverage(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli),
                                        from: dayAgo, to: now)
        let hrvBase = await quantityAverage(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli),
                                            from: monthAgo, to: now)

        guard sleepHours != nil || rhr != nil || hrv != nil else { return nil }

        var score = 0
        if let sleep = sleepHours {
            if sleep >= 7 { score += 1 } else if sleep < 6 { score -= 1 }
        }
        if let rhr, let base = rhrBase, base > 0 {
            if rhr <= base + 1 { score += 1 } else if rhr > base + 3 { score -= 1 }
        }
        if let hrv, let base = hrvBase, base > 0 {
            if hrv >= base * 0.9 { score += 1 } else if hrv < base * 0.75 { score -= 1 }
        }

        let verdict = score >= 2 ? "Recovered" : score >= 0 ? "Steady" : "Run it easy"
        var facts: [String] = []
        if let sleep = sleepHours {
            let hours = Int(sleep)
            let minutes = Int((sleep - Double(hours)) * 60)
            facts.append(String(format: "slept %d:%02d", hours, minutes))
        }
        if let rhr {
            facts.append("RHR \(Int(rhr.rounded()))" + (rhrBase.map { " (avg \(Int($0.rounded())))" } ?? ""))
        }
        if let hrv { facts.append("HRV \(Int(hrv.rounded()))ms") }
        let guidance = score >= 2 ? "good day to push"
            : score >= 0 ? "hold the plan"
            : "keep it gentle today"
        let line = facts.joined(separator: " · ") + " — " + guidance + "."

        return Readiness(sleepHours: sleepHours, restingHR: rhr, restingHRBaseline: rhrBase,
                         hrv: hrv, hrvBaseline: hrvBase, score: score, verdict: verdict, line: line)
    }

    private func quantityAverage(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit,
                                 from start: Date, to end: Date) async -> Double? {
        let type = HKQuantityType(identifier)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                          options: .discreteAverage) { _, stats, _ in
                continuation.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
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
