//
//  Actions.swift
//  DataPushPerformance
//
//  Created by Fernando Barbat on 6/6/23.
//

import Combine
import Foundation

/// Use 60FPS as a reference. This way tests might apply for both remote control and screen share video stream handling.
/// If we don't throttle it, we might hit contention cases depending on the strategy. We would be testing a
/// pretty different workload than the actual in app workload.
/// But we want to set up an environment which is similar to how we would use it.
private let nanosecondDelayBetweenTests: UInt64 = 1_000_000_000 / 60

protocol DataPushTest {
    func run(count: Int) async -> Measurements
}

enum Strategy: String, CaseIterable {
    case methodInvocation
    case methodInvocationWithLock
    case actor
    case actorWithAsyncStreamUnfolding
    case actorWithAsyncStreamWithContinuation
    case combine
    case combineReceiveOn
    case dispatchQueue
}

extension Strategy: Identifiable {
    var id: Self {
        return self
    }
}

extension Strategy: DataPushTest {
    func run(count: Int) async -> Measurements {
        switch self {
        case .methodInvocation:
            return await MethodInvocation().run(count: count)
        case .methodInvocationWithLock:
            return await MethodInvocationWithLock().run(count: count)
        case .actor:
            return await Actor().run(count: count)
        case .actorWithAsyncStreamUnfolding:
            return await ActorWithAsyncStreamUnfolding().run(count: count)
        case .actorWithAsyncStreamWithContinuation:
            return await ActorWithAsyncStreamWithContinuation().run(count: count)
        case .combine:
            return await Combine().run(count: count)
        case .combineReceiveOn:
            return await CombineReceiveOn().run(count: count)
        case .dispatchQueue:
            return await DispatchQueueStrategy().run(count: count)
        }
    }
}

private final class MethodInvocation: DataPushTest {
    private final class Receiver {
        let measurements: Measurements
        
        init(measurements: Measurements) {
            self.measurements = measurements
        }
        
        func test(start: DispatchTime) {
            let end = DispatchTime.now()
            measurements.add(start: start, end: end)
        }
    }

    func run(count: Int) async -> Measurements {
        let measurements = Measurements(count: count)
        
        let receiver = Receiver(measurements: measurements)
        
        for _ in 0 ..< count {
            let start = DispatchTime.now()
            receiver.test(start: start)
            try? await Task.sleep(nanoseconds: nanosecondDelayBetweenTests)
        }
        
        return measurements
    }
}

private final class MethodInvocationWithLock: DataPushTest {
    private final class Receiver {
        private let measurements: Measurements
        private let lock = NSLock()
        
        init(measurements: Measurements) {
            self.measurements = measurements
        }
        
        func test(start: DispatchTime) {
            lock.lock()
            // We would do something useful here
            lock.unlock()
            
            let end = DispatchTime.now()
            measurements.add(start: start, end: end)
        }
    }
    
    func run(count: Int) async -> Measurements {
        let measurements = Measurements(count: count)
        
        let receiver = Receiver(measurements: measurements)
     
        for _ in 0 ..< count {
            let start = DispatchTime.now()
            receiver.test(start: start)
            try? await Task.sleep(nanoseconds: nanosecondDelayBetweenTests)
        }
        
        return measurements
    }
}

private final class Actor: DataPushTest {
    private final actor Receiver {
        private let measurements: Measurements
        
        init(measurements: Measurements) {
            self.measurements = measurements
        }
        
        func test(start: DispatchTime) {
            let end = DispatchTime.now()
            measurements.add(start: start, end: end)
        }
    }
    
    func run(count: Int) async -> Measurements {
        let measurements = Measurements(count: count)
        
        let receiver = Receiver(measurements: measurements)
     
        for _ in 0 ..< count {
            let start = DispatchTime.now()
            await receiver.test(start: start)
            try? await Task.sleep(nanoseconds: nanosecondDelayBetweenTests)
        }
        
        return measurements
    }
}

private final class ActorWithAsyncStreamUnfolding: DataPushTest {
    final actor Receiver {
        private let measurements: Measurements
        
        private var task: Task<Void, Never>?
        
        init(measurements: Measurements, asyncStream: AsyncStream<DispatchTime>) async {
            self.measurements = measurements
            
            task = Task {
                for await start in asyncStream {
                    let end = DispatchTime.now()
                    self.measurements.add(start: start, end: end)
                }
            }
        }
    }
    
    func run(count: Int) async -> Measurements {
        let measurements = Measurements(count: count)
        
        var i = count
        
        let receiver = await Receiver(measurements: measurements, asyncStream: AsyncStream<DispatchTime>(unfolding: {
            try? await Task.sleep(nanoseconds: nanosecondDelayBetweenTests)
            
            if i > 0 {
                i -= 1
                let start = DispatchTime.now()
                return start
            } else {
                return nil
            }
        }))
     
        await measurements.valuesCollected()
        
        _ = receiver
        
        return measurements
    }
}

private final class ActorWithAsyncStreamWithContinuation: DataPushTest {
    func run(count: Int) async -> Measurements {
        let measurements = Measurements(count: count)
        
        // Same receiver implementation than ActorWithAsyncStreamUnfolding
        let receiver = await ActorWithAsyncStreamUnfolding.Receiver(measurements: measurements, asyncStream: AsyncStream<DispatchTime> { continuation in
            Task {
                for _ in 0 ..< count {
                    let start = DispatchTime.now()
                    continuation.yield(start)
                    try? await Task.sleep(nanoseconds: nanosecondDelayBetweenTests)
                }
                
                continuation.finish()
            }
        })
     
        await measurements.valuesCollected()
        
        _ = receiver
        
        return measurements
    }
}

private final class Combine: DataPushTest {
    private class Receiver {
        private let measurements: Measurements
        
        private var cancellable: AnyCancellable?
        
        init(measurements: Measurements, publisher: some Publisher<DispatchTime, Never>) {
            self.measurements = measurements
            cancellable = publisher.sink { [measurements] start in
                let end = DispatchTime.now()
                measurements.add(start: start, end: end)
            }
        }
    }
    
    func run(count: Int) async -> Measurements {
        let measurements = Measurements(count: count)
        
        let passthroughSubject = PassthroughSubject<DispatchTime, Never>()
        
        let receiver = Receiver(measurements: measurements, publisher: passthroughSubject)
        
        for _ in 0 ..< count {
            let start = DispatchTime.now()
            passthroughSubject.send(start)
            try? await Task.sleep(nanoseconds: nanosecondDelayBetweenTests)
        }
        
        _ = receiver
        
        return measurements
    }
}

private final class CombineReceiveOn: DataPushTest {
    private class Receiver {
        private let dispatchQueue = DispatchQueue(label: "CombineReceiveOn", target: DispatchQueue.global(qos: .userInteractive))
        
        private var cancellable: AnyCancellable?
        
        init(measurements: Measurements, publisher: some Publisher<DispatchTime, Never>) {
            cancellable = publisher
                .receive(on: dispatchQueue)
                .sink { start in
                    let end = DispatchTime.now()
                    measurements.add(start: start, end: end)
                }
        }
    }
    
    func run(count: Int) async -> Measurements {
        let measurements = Measurements(count: count)
        
        let passthroughSubject = PassthroughSubject<DispatchTime, Never>()
        
        let receiver = Receiver(measurements: measurements, publisher: passthroughSubject)
        
        for _ in 0 ..< count {
            let start = DispatchTime.now()
            passthroughSubject.send(start)
            try? await Task.sleep(nanoseconds: nanosecondDelayBetweenTests)
        }
        
        await measurements.valuesCollected()
        
        _ = receiver
        
        return measurements
    }
}

private final class DispatchQueueStrategy: DataPushTest {
    private class Receiver {
        private let measurements: Measurements
        private let dispatchQueue = DispatchQueue(label: "DispatchQueueStrategy", target: DispatchQueue.global(qos: .userInteractive))
        
        init(measurements: Measurements) {
            self.measurements = measurements
        }
        
        func test(start: DispatchTime) {
            dispatchQueue.async { [measurements] in
                let end = DispatchTime.now()
                measurements.add(start: start, end: end)
            }
        }
    }
    
    func run(count: Int) async -> Measurements {
        let measurements = Measurements(count: count)
        
        let receiver = Receiver(measurements: measurements)
        
        for _ in 0 ..< count {
            let start = DispatchTime.now()
            receiver.test(start: start)
            try? await Task.sleep(nanoseconds: nanosecondDelayBetweenTests)
        }
        
        await measurements.valuesCollected()
        
        return measurements
    }
}
