//
//  ContentView.swift
//  DataPushPerformance
//
//  Created by Fernando Barbat on 6/6/23.
//

import Charts
import SwiftUI

struct ContentView: View {
    @State private var loadedMeasurements: LoadedMeasurements?

    var body: some View {
        if let loadedMeasurements {
            MainView(loadedMeasurements: loadedMeasurements)
        } else {
            Loading()
                .task {
                    let start = DispatchTime.now()
                    var measurements: [Strategy: Measurements] = [:]

                    for strategy in Strategy.allCases {
                        measurements[strategy] = await strategy.run(count: 2000)
                    }

                    let end = DispatchTime.now()

                    let loadingTimeSeconds = Int((end.uptimeNanoseconds - start.uptimeNanoseconds) / UInt64(1_000_000_000))
                    
                    self.loadedMeasurements = LoadedMeasurements(
                        loadingTimeSeconds: loadingTimeSeconds,
                        measurements: measurements
                    )
                }
        }
    }
}

private struct Loading: View {
    let startTime = Date()
    let timer = Timer.TimerPublisher(interval: 1, runLoop: .main, mode: .default)
        .autoconnect()
    
    @State private var elapsedTimeSeconds = 0
    
    var body: some View {
        VStack {
            ProgressView()
            Text("Running latency tests…")
            Text("Elapsed time: \(elapsedTimeSeconds)s")
        }
        .onReceive(timer) { date in
            elapsedTimeSeconds = Int(date.timeIntervalSince(startTime))
        }
    }
}

private struct LoadedMeasurements {
    let loadingTimeSeconds: Int
    let measurements: [Strategy: Measurements]
}

private struct MainView: View {
    let loadedMeasurements: LoadedMeasurements

    @State private var strategy: Strategy?

    var body: some View {
        NavigationSplitView {
            List(
                orderedStrategies,
                selection: $strategy
            ) { strategy in
                Text(strategy.rawValue)
            }
            .navigationSplitViewColumnWidth(min: nil, ideal: 280, max: nil)
        } detail: {
            if let strategy, let measurements = loadedMeasurements.measurements[strategy] {
                MeasurementsView(measurements: measurements)
                    .toolbar {
                        ToolbarItem {
                            Text("Loading time: \(loadedMeasurements.loadingTimeSeconds)s")
                        }
                    }
            } else {
                Text("Select a strategy")
            }
            
        }
    }

    private var orderedStrategies: [Strategy] {
        loadedMeasurements.measurements
            .sorted(by: { lhs, rhs in lhs.value.stats.p99 < rhs.value.stats.p99 })
            .map { strategy, _ in strategy }
    }
}

private struct MeasurementsView: View {
    let measurements: Measurements

    var body: some View {
        VStack {
            MeasurementsChart(bins: measurements.bins)
            StatsView(stats: measurements.stats)
        }
        .padding()
    }
}

private struct MeasurementsChart: View {
    let bins: [Measurements.Bin]

    var body: some View {
        Chart(
            bins, id: \.index
        ) { element in
            BarMark(
                x: .value(
                    "Elapsed Time (ms)",
                    element.range
                ),
                y: .value(
                    "Count",
                    element.count
                )
            )
        }
    }
}

private struct StatsView: View {
    let stats: Measurements.Stats

    var body: some View {
        Grid(alignment: .leading) {
            GridRow {
                Text("Min: \(stats.minimum)ns")
                Text("Avg: \(stats.average)ns")
                Text("Max: \(stats.maximum)ns")
                Text("Count: \(stats.count)")
            }
            GridRow {
                Text("P1: \(stats.p1)ns")
                Text("P10: \(stats.p10)ns")
                Text("P50: \(stats.p50)ns")
            }
            GridRow {
                Text("P90: \(stats.p90)ns")
                Text("P99: \(stats.p99)ns")
                Text("P999: \(stats.p999)ns")
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
