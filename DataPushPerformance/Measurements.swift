//
//  Measurements.swift
//  DataPushPerformance
//
//  Created by Fernando Barbat on 6/6/23.
//

import Charts
import Foundation
import SigmaSwiftStatistics

final class Measurements {
    private let count: Int
    private(set) var values: [UInt64] = []
    
    private var valuesCollectedContinuation: AsyncStream<Void>.Continuation?
    
    private lazy var valuesCollectedAsyncStream = AsyncStream<Void> { continuation in
        self.valuesCollectedContinuation = continuation
    }
    
    init(count: Int) {
        self.count = count
        values.reserveCapacity(count)
        
        _ = valuesCollectedAsyncStream
    }
    
    func add(start: DispatchTime, end: DispatchTime) {
        let elapsedTime: UInt64 = end.uptimeNanoseconds - start.uptimeNanoseconds
        values.append(elapsedTime)
        
        if values.count == count {
            valuesCollectedContinuation?.finish()
            
            // Eagerly load derived data while we have a progress view
            _ = bins
            _ = stats
        }
    }
    
    struct Bin {
        let index: Int
        let range: ChartBinRange<UInt64>
        let count: Int
    }
    
    private(set) lazy var bins: [Bin] = {
        let numberBins = NumberBins<UInt64>(data: values)
        
        let groups: [Int: [UInt64]] = Dictionary(
            grouping: values,
            by: numberBins.index
        )
        
        return groups.map { key, values in Bin(
            index: key,
            range: numberBins[key],
            count: values.count
        ) }
    }()
    
    struct Stats {
        let count: UInt64
        let minimum: UInt64
        let average: UInt64
        let maximum: UInt64
        let p1: UInt64
        let p10: UInt64
        let p50: UInt64
        let p90: UInt64
        let p99: UInt64
        let p999: UInt64
    }
    
    private(set) lazy var stats: Stats = {
        let sorted = values
            .map { value in Double(value) }
            .sorted()
        
        return Stats(
            count: UInt64(sorted.count),
            minimum: UInt64(sorted.first ?? 0),
            average: UInt64(Sigma.average(sorted) ?? 0),
            maximum: UInt64(sorted.last ?? 0),
            p1: UInt64(percentile(sorted, probability: 0.01) ?? 0),
            p10: UInt64(percentile(sorted, probability: 0.1) ?? 0),
            p50: UInt64(percentile(sorted, probability: 0.5) ?? 0),
            p90: UInt64(percentile(sorted, probability: 0.9) ?? 0),
            p99: UInt64(percentile(sorted, probability: 0.99) ?? 0),
            p999: UInt64(percentile(sorted, probability: 0.999) ?? 0)
        )
    }()
    
    // Extracted these methods from SigmaSwiftStatistics so we order the elements a single time and then reuse that.
    private func percentile(_ orderedData: [Double], probability: Double) -> Double? {
        if probability < 0 || probability > 1 { return nil }
        let count = Double(orderedData.count)
        let m = 1.0 - probability
        let k = Int((probability * count) + m)
        let probability = (probability * count) + m - Double(k)
        return qDef(orderedData, k: k, probability: probability)
    }
    
    private func qDef(_ data: [Double], k: Int, probability: Double) -> Double? {
        if data.isEmpty { return nil }
        if k < 1 { return data[0] }
        if k >= data.count { return data.last }
        return ((1.0 - probability) * data[k - 1]) + (probability * data[k])
    }
    
    func valuesCollected() async {
        // Wait for the async stream to finish
        for await _ in valuesCollectedAsyncStream {}
    }
}
