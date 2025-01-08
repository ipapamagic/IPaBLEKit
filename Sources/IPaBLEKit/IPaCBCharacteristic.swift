//
//  IPaCBCharacteristic.swift
//  IPaBLEKit
//
//  Created by IPa Chen on 2022/7/22.
//

import UIKit
import CoreBluetooth
import Combine
import IPaLog
import IPaSecurity
public class IPaCBCharacteristic:NSObject {
    
    public private(set) var uuid:CBUUID
    public weak var peripheral:IPaPeripheral? {
        get {
            return _peripheral
        }
    }
    weak var _peripheral:IPaPeripheral?
    weak var _cbCharacteristic:CBCharacteristic?
    var valueSubject = PassthroughSubject<Data?,Never>()
    var didWriteValueSubject = PassthroughSubject<Result<Data?,IPaBLEError>,Never>()
    var writeValueCancellable:AnyCancellable?
    var didUpdateNotifySubject = PassthroughSubject<Result<Void,IPaBLEError>,Never>()
    var updateNoifyCancellable:AnyCancellable?
    public private(set) weak var cbCharacteristic:CBCharacteristic? {
        get {
            return _cbCharacteristic
        }
        set {
            self._cbCharacteristic = newValue
        }
    }
    public convenience init(_ uuidString:String) {
        self.init(CBUUID(string: uuidString))
    }
    public init(_ uuid:CBUUID,cbCharacteristic:CBCharacteristic? = nil) {
        self.uuid = uuid
        self._cbCharacteristic = cbCharacteristic
        super.init()
    }
    public init(_ cbCharacteristic:CBCharacteristic) {
        self.uuid = cbCharacteristic.uuid
        self._cbCharacteristic = cbCharacteristic
        super.init()
    }
    public func setNotify(_ enable:Bool,timeout:TimeInterval? = nil) async -> Bool {
        guard let peripheral = peripheral?.peripheral,let cbCharacteristic = cbCharacteristic  else {
            return false
        }
        peripheral.setNotifyValue(enable, for: cbCharacteristic)
        do {
            let publisher = timeout ?? 0 > 0 ?
            self.didUpdateNotifySubject.setFailureType(to: IPaBLEError.self).timeout(.seconds(timeout!), scheduler: DispatchQueue.main,customError: {
                IPaBLEError.timeout
            }).catch { error in
                Just(.failure(error))
            }.eraseToAnyPublisher() : self.didUpdateNotifySubject.eraseToAnyPublisher()
            
            try await withCheckedThrowingContinuation {
                continuation in
                self.updateNoifyCancellable = publisher.sink { result in
                    switch result {
                    case .success( _):
                        if cbCharacteristic.isNotifying == enable {
                            continuation.resume()
                        }
                        else {
                            continuation.resume(throwing: IPaBLEError.characteristicNotifyUpdateFailed)
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                    self.updateNoifyCancellable?.cancel()
                    self.updateNoifyCancellable = nil
                }
            }
            
            return true
        }
        catch (let error) {
            IPaLog(error.localizedDescription)
            return false
        }
    }
    @inlinable public func readValue() {
        guard let peripheral = peripheral?.peripheral,let cbCharacteristic = cbCharacteristic  else {
            return
        }
        peripheral.readValue(for: cbCharacteristic)
    }
    
    //    func withTimeout(
    //        timeout: TimeInterval?,
    //        task: @escaping () async throws -> ()
    //    ) async throws {
    //        guard let timeout = timeout, timeout > 0 else {
    //            // no time out, just run task
    //            try await task()
    //            return
    //        }
    //        // use TaskGroup for both tasks
    //        try await withThrowingTaskGroup(of: Void.self) { group in
    //            // add Main task
    //            group.addTask {
    //                return try await task()
    //            }
    //            // add timeout task
    //            group.addTask {
    //                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
    //                throw IPaBLEError.timeout
    //            }
    //            // return the first finished task
    //            guard let result = try await group.next() else {
    //                fatalError("Task group completed without returning any result.")
    //            }
    //            // cancel other task
    //            group.cancelAll()
    //            return result
    //        }
    //    }
    @discardableResult @inlinable public func writeValueWithNoResponse(_ dataString:String, encoding:String.Encoding = .ascii) async -> Bool {
        guard let peripheral = peripheral?.peripheral,let cbCharacteristic = cbCharacteristic,let data = dataString.data(using: encoding)   else {
            return false
        }
        peripheral.writeValue(data, for: cbCharacteristic, type: .withoutResponse)
        return true
    }
    @discardableResult @inlinable public func writeValueWithNoResponse(_ data:Data) async -> Bool {
        guard let peripheral = peripheral?.peripheral,let cbCharacteristic = cbCharacteristic  else {
            return false
        }
        peripheral.writeValue(data, for: cbCharacteristic, type: .withoutResponse)
        return true
    }
    @inlinable public func writeValue(_ dataString:String, encoding:String.Encoding = .ascii,timeout:TimeInterval? = nil) async throws {
        guard let data = dataString.data(using: encoding) else {
            throw IPaBLEError.encodingFailed
        }
        return try await self.writeValue(data,timeout: timeout)
        
    }
    public func writeValue(_ data:Data,timeout:TimeInterval? = nil) async throws {
        guard let peripheral = peripheral?.peripheral,let cbCharacteristic = cbCharacteristic  else {
            throw IPaBLEError.characteristicNotDiscovered
        }
        
        peripheral.writeValue(data, for: cbCharacteristic, type: .withResponse)
        
        try await withCheckedThrowingContinuation {
            continuation in
            let publisher = timeout ?? 0 > 0 ?
            self.didWriteValueSubject.setFailureType(to: IPaBLEError.self).timeout(.seconds(timeout!), scheduler: DispatchQueue.main,customError: {
                IPaBLEError.timeout
            }).catch { error in
                Just(.failure(error))
            }.eraseToAnyPublisher() : self.didWriteValueSubject.eraseToAnyPublisher()
            
            self.writeValueCancellable = publisher.sink { result in
                switch result {
                case .success( _):
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
                self.writeValueCancellable?.cancel()
                self.writeValueCancellable = nil
            }
        }
        
        
        
    }
    
    func disconnect() {
        self._cbCharacteristic = nil
    }
}
