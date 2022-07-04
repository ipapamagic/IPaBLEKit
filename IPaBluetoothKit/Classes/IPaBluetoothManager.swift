//
//  IPaBluetoothManager.swift
//  IPaBluetoothKit
//
//  Created by IPa Chen on 2022/6/8.
//

import UIKit
import CoreBluetooth
import IPaLog
import Combine
public protocol IPaBluetoothManagerDelegate {
    func createPeripheral(from manager: IPaBluetoothManager, with peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) -> IPaPeripheral
    func manager(_ manager: IPaBluetoothManager, didDiscover peripheral:IPaPeripheral)
    func manager(_ manager: IPaBluetoothManager, didConnect peripheral:IPaPeripheral)
}
public class IPaBluetoothManager: NSObject {
    lazy var centralManager = CBCentralManager(delegate: self, queue: .main)
    public var cbStateSubject = PassthroughSubject<CBManagerState,Never>()
    @objc dynamic public private(set) var peripherals = [IPaPeripheral]()
    var services:[CBUUID]?
    public var cbState:CBManagerState {
        get {
            return self.centralManager.state
        }
    }
    public var delegate:IPaBluetoothManagerDelegate
    public init(_ services:[String]? = nil,delegate:IPaBluetoothManagerDelegate) {
        self.services = services?.map({ uuid in
            return CBUUID(string: uuid)
        })
        self.delegate = delegate
        super.init()
    }
    public func startScan(_ options:[String:Any]? = nil) {
        peripherals.removeAll()
        self.centralManager.scanForPeripherals(withServices: self.services, options:options)
    }
    public func stopScan() {
        self.centralManager.stopScan()
    }
    
}
extension IPaBluetoothManager:CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        self.cbStateSubject.send(central.state)
        
    }
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name,name.count > 0 else {
            return
        }
        
        
        if let ipaPeripheral = self.peripherals.first(where: { _peripheral in
            _peripheral.peripheral == peripheral
        }) {
            ipaPeripheral._rssi = RSSI
            IPaLog("Peripheral discovered updated:\(peripheral.name ?? peripheral.description)")
        }
        else {
            let ipaPeripheral = self.delegate.createPeripheral(from: self, with: peripheral, advertisementData: advertisementData, rssi: RSSI)
            ipaPeripheral._peripheral = peripheral
            ipaPeripheral.manager = self
            ipaPeripheral._rssi = RSSI
            self.peripherals.append(ipaPeripheral)
            IPaLog("Peripheral Discovered:\(peripheral.name ?? peripheral.description)")
            
            self.delegate.manager(self, didDiscover: ipaPeripheral)
        }
        
        
        
        
        
    }
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        IPaLog("Peripheral connected:\(peripheral.name ?? peripheral.description)")
        if let ipaPeripheral = self.peripherals.first(where: { ipaPeripheral in
            return ipaPeripheral.peripheral == peripheral
        }) {
            self.delegate.manager(self, didConnect: ipaPeripheral)
            ipaPeripheral.scanService()
        }
    }
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        IPaLog("Peripheral fail to connect:\(peripheral.name ?? peripheral.description)")
    }
    
}
