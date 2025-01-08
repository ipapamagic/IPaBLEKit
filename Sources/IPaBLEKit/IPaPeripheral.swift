//
//  IPaPeripheral.swift
//  IPaBLEKit
//
//  Created by IPa Chen on 2022/6/8.
//

import UIKit
import CoreBluetooth
import IPaLog
import Combine
open class IPaPeripheral: NSObject {
    @objc class open func keyPathsForValuesAffectingRssi() -> Set<String> {
        return ["_rssi"]
    }
    @objc class open func keyPathsForValuesAffectingState() -> Set<String> {
        return ["_peripheral","_peripheral.state"]
    }
    @objc class open func keyPathsForValuesAffectingPeripheral() -> Set<String> {
        return ["_peripheral"]
    }
    var characteristicsAnyCancellable = [AnyCancellable]()
    @objc dynamic var _peripheral:CBPeripheral? {
        didSet {
            guard let _peripheral = _peripheral else {
                return
            }
            _peripheral.delegate = self
            self.didSet(peripheral: _peripheral)
        }
    }
    lazy var lastDiscoverTime = Date().timeIntervalSince1970
    var _rssi:NSNumber = NSNumber(value: 0)
    @objc dynamic  public var peripheral:CBPeripheral? {
        return _peripheral
    }
    @objc dynamic public var rssi:NSNumber {
        return _rssi
    }
    @objc dynamic public var state:CBPeripheralState {
        get {
            return self.peripheral?.state ?? .disconnected
        }
    }
    lazy var _services:[CBUUID:IPaCBService] = [:]
    public var services:[IPaCBService] {
        get {
            return Array(self._services.values)
        }
    }
    weak var manager:IPaBLEManager!

    @inlinable public var peripheralName:String {
        return self.peripheral?.name ?? ""
    }
    @inlinable public var peripheralUUID:UUID? {
        return self.peripheral?.identifier
    }
    @inlinable public var peripheralUUIDString:String {
        return self.peripheral?.identifier.uuidString ?? ""
    }
    public override init() {
        
        super.init()
        self._services = self.generateServices().reduce([CBUUID:IPaCBService](), { partialResult, service in
            var partialResult = partialResult
            partialResult[service.uuid] = service
            return partialResult
        })
    }
    open func generateServices() -> [IPaCBService] {
        return []
    }
    func scanService() {
        let servicesUUIDs = Array(self._services.keys)
        
        self.peripheral?.discoverServices(servicesUUIDs.count > 0 ? servicesUUIDs : nil)
    }
    public func connect() {
        guard let peripheral = peripheral else {
            return
        }
        self.manager.centralManager.connect(peripheral)
    }
    public func disconnect() {
        guard let peripheral = peripheral else {
            return
        }
        for service in self.services {
            service.disconnect()
        }
        self.manager.centralManager.cancelPeripheralConnection(peripheral)
    }
    open func didSet(peripheral:CBPeripheral) {
        
    }
    @inlinable open func didDiscover(characteristic:IPaCBCharacteristic) {
        
    }

    @inlinable public func writeValue(_ data:Data,for characteristic:CBCharacteristic,type:CBCharacteristicWriteType = .withResponse) {
        self.peripheral?.writeValue(data, for: characteristic, type: type)
    }
    @inlinable public func writeValue(_ data:Data,for descriptor:CBDescriptor) {
        self.peripheral?.writeValue(data, for: descriptor)
    }
    public func bind(with characteristic:IPaCBCharacteristic,onDataUpdate callback:@escaping (Data?)->()) {
        let anyCancellable = characteristic.valueSubject.sink(receiveValue: callback)
        self.characteristicsAnyCancellable.append(anyCancellable)
    }
    public func bind<Root>(_ keyPath:ReferenceWritableKeyPath<Root,String?>,to characteristic:IPaCBCharacteristic)  {
        let anyCancellable = characteristic.valueSubject.map { data -> String? in
            guard let data = data else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        }.assign(to: keyPath, on: self as! Root)
        self.characteristicsAnyCancellable.append(anyCancellable)
    }
    public func bind<PropertyType,T,Root>(_ keyPath:ReferenceWritableKeyPath<Root,PropertyType?>,to characteristic:IPaCBCharacteristic,transform:@escaping ((T) -> PropertyType))  {
        let anyCancellable = characteristic.valueSubject.map { data -> PropertyType? in
            guard let data = data else {
                return nil
            }
            let chunkSize = MemoryLayout<T>.size
            // Get the bytes that contain next value
            let nextDataChunk = Data(data[0..<chunkSize])
            // Read the actual value from the data chunk
            let value:T = nextDataChunk.withUnsafeBytes { bufferPointer in
                bufferPointer.load(fromByteOffset: 0, as: T.self)
            }
            return transform(value)
        }.assign(to: keyPath, on: self as! Root)
        self.characteristicsAnyCancellable.append(anyCancellable)
        
    }
    public func bind<T,Root>(_ keyPath:ReferenceWritableKeyPath<Root,T?>,to characteristic:IPaCBCharacteristic)  {
        self.bind(keyPath, to: characteristic, transform: {return $0 })
    }
    fileprivate func updateCharacteristicValue(_ characteristic:CBCharacteristic) {
        guard let cbService = characteristic.service,let ipaService = self._services[cbService.uuid],let ipaCharacteristic = ipaService.characteristics[characteristic.uuid] else {
            return
        }
        ipaCharacteristic.valueSubject.send(characteristic.value)
    }
    open func onDisconnected(_ error:Error?) {
        
    }
}

extension IPaPeripheral:CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if error != nil {
            return
        }
        guard let services = peripheral.services else {
            return
        }
        for service in services {
            if let ipaService = self._services[service.uuid] {
                ipaService._cbService = service
                let uuids = Array(ipaService.characteristics.keys)
                peripheral.discoverCharacteristics(uuids.count > 0 ? uuids : nil , for: service)
            }
            else {
                self._services[service.uuid] = IPaCBService(service)
                peripheral.discoverCharacteristics(nil, for: service)
            }
            
            
        }
    }
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            IPaLog ("\(error.debugDescription)")
            return
        }
        if let descriptors = characteristic.descriptors {
            for descript in descriptors {
                IPaLog("IPaPeripheral - did discover descript\(descript.description)")
            }
        }
                
    }
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
//        IPaLog("IPaPeripheral - did write value for characteristic: \(characteristic.description)")
        
        guard let cbService = characteristic.service,let service = self._services[cbService.uuid],let ipaCharacteristic = service.characteristics[characteristic.uuid] else {
            return
        }
        ipaCharacteristic.didWriteValueSubject.send(error)
        
    }
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?) {
        IPaLog("IPaPeripheral - did write value for descriptor: \(descriptor.description)")
    }
    open func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        self.updateCharacteristicValue(characteristic)
    }
    open func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        self.updateCharacteristicValue(characteristic)
    }
    open func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        
    }
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if  error != nil {
            IPaLog("IPaPeripheral - Error discovering characteristics \(error!.localizedDescription)")
        }
        guard let characteristics = service.characteristics, let ipaService = self._services[service.uuid] else {
            IPaLog("IPaPeripheral - service:\(service.uuid) not exist  or  characteristics not exist")
            return
        }
        IPaLog("IPaPeripheral - Discovered characteristic: \(characteristics)")
        for characteristic in characteristics {
            var ipaCharacteristic:IPaCBCharacteristic
            if let _ipaCharacteristic = ipaService.characteristics[characteristic.uuid]  {
                _ipaCharacteristic._cbCharacteristic = characteristic
                ipaCharacteristic = _ipaCharacteristic
            }
            else {
                ipaCharacteristic = IPaCBCharacteristic(characteristic)
                ipaService.characteristics[characteristic.uuid] = ipaCharacteristic
            }
            ipaCharacteristic._peripheral = self
            self.didDiscover(characteristic: ipaCharacteristic)
            peripheral.discoverDescriptors(for: characteristic)
        }
    }
}
