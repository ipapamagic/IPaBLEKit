//
//  IPaCBCharacteristic.swift
//  IPaBluetoothKit
//
//  Created by IPa Chen on 2022/7/22.
//

import UIKit
import CoreBluetooth
import Combine
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
    public var didWriteValueSubject = PassthroughSubject<Error?,Never>()
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
    @inlinable public func setNotify(_ enable:Bool) {
        guard let peripheral = peripheral?.peripheral,let cbCharacteristic = cbCharacteristic  else {
            return
        }
        peripheral.setNotifyValue(enable, for: cbCharacteristic)
    }
    @inlinable public func readValue() {
        guard let peripheral = peripheral?.peripheral,let cbCharacteristic = cbCharacteristic  else {
            return
        }
        peripheral.readValue(for: cbCharacteristic)
    }
    @inlinable public func writeValuesWithChecksum(_ values:[UInt8],type:CBCharacteristicWriteType) throws -> Bool {
        var checksum:UInt8 = 0
        var data = Data()
        for value in values {
            data.append(value)
            checksum += value
        }
        data.append(checksum)
        return self.writeValue(data, type: type)
    }
    
    @discardableResult @inlinable public func writeValue(_ data:Data,type:CBCharacteristicWriteType) -> Bool {
        guard let peripheral = peripheral?.peripheral,let cbCharacteristic = cbCharacteristic  else {
            return false
        }
        peripheral.writeValue(data, for: cbCharacteristic, type: type)
        return true
    }
    
    func disconnect() {
        self._cbCharacteristic = nil
    }
}
