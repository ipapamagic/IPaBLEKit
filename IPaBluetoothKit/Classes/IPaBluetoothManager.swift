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
    func createPeripheral(from manager: IPaBluetoothManager, with peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) -> IPaPeripheral?
    func manager(_ manager: IPaBluetoothManager, didDiscover peripheral:IPaPeripheral)
    func manager(_ manager: IPaBluetoothManager, didConnect peripheral:IPaPeripheral)
    func manager(_ manager: IPaBluetoothManager, didFailToConnect peripheral:IPaPeripheral, error: Error?)
    func manager(_ manager: IPaBluetoothManager, didDisconnectPeripheral peripheral:IPaPeripheral, error: Error?)
}
public class IPaBluetoothManager: NSObject {
    lazy var centralManager = CBCentralManager(delegate: self, queue: .main)
    public var cbStateSubject = PassthroughSubject<CBManagerState,Never>()
    var scanTimer:Timer?
    var scanOptions:[String : Any]?
    public var rescanTime:TimeInterval = 10 {
        didSet {
            guard let _ = scanTimer else {
                return
            }
            self.startScan(self.scanOptions)
        }
    }
    public var peripheralTimeoutInterval:TimeInterval = 10
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
        self.scanTimer?.invalidate()
        self.scanOptions = options
        self.centralManager.scanForPeripherals(withServices: self.services, options:self.scanOptions)
        self.scanTimer = Timer.scheduledTimer(withTimeInterval: self.rescanTime, repeats: true, block: {
            timer in
            self.centralManager.stopScan()
            //remove timeout peripherals
            let now = Date().timeIntervalSince1970
            self.peripherals = self.peripherals.filter { peripheral in
                guard  peripheral.state == .disconnected else {
                    peripheral.lastDiscoverTime = now
                    return true
                }
                let isTimeout = (now - peripheral.lastDiscoverTime)  >   self.peripheralTimeoutInterval
                if isTimeout {
                    peripheral._peripheral = nil
                }
                return !isTimeout
            }
            
            self.centralManager.scanForPeripherals(withServices: self.services, options:self.scanOptions)
        })
        
        
    }
    public func remove(_ peripheral:IPaPeripheral) {
        if let index = self.peripherals.firstIndex(of: peripheral) {
            if peripheral.state == .connected {
                peripheral.disconnect()
            }
            self.peripherals.remove(at: index)
            peripheral._peripheral = nil
        }
    }
    public func stopScan() {
        self.scanTimer?.invalidate()
        self.scanTimer = nil
        self.centralManager.stopScan()
    }
    @inlinable func getPeripheral(_ cbPeripheral:CBPeripheral) -> IPaPeripheral? {
        return self.peripherals.first(where: { _peripheral in
            _peripheral.peripheral?.identifier == cbPeripheral.identifier
        })
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
        if let ipaPeripheral = self.getPeripheral(peripheral) {
            IPaLog("Peripheral discovered updated:\(peripheral.name ?? peripheral.description)")
            ipaPeripheral._rssi = RSSI
            ipaPeripheral._peripheral = peripheral
            ipaPeripheral.lastDiscoverTime = Date().timeIntervalSince1970
        }
        else if let ipaPeripheral = self.delegate.createPeripheral(from: self, with: peripheral, advertisementData: advertisementData, rssi: RSSI) {
            ipaPeripheral._peripheral = peripheral
            ipaPeripheral.manager = self
            ipaPeripheral._rssi = RSSI
            self.peripherals.append(ipaPeripheral)
            IPaLog("Peripheral Discovered:\(peripheral.name ?? peripheral.description)")
            ipaPeripheral.lastDiscoverTime = Date().timeIntervalSince1970
            self.delegate.manager(self, didDiscover: ipaPeripheral)
        }
    }
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        IPaLog("Peripheral connected:\(peripheral.name ?? peripheral.description)")
        if let ipaPeripheral = self.getPeripheral(peripheral) {
            self.delegate.manager(self, didConnect: ipaPeripheral)
            ipaPeripheral.scanService()
        }
    }
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        IPaLog("Peripheral fail to connect:\(peripheral.name ?? peripheral.description),error:\(error?.localizedDescription ?? "nil")")
        if let ipaPeripheral = self.getPeripheral(peripheral) {
            self.delegate.manager(self, didFailToConnect: ipaPeripheral,error:error)
            
        }
    }
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        IPaLog("Peripheral disconnect:\(peripheral.name ?? peripheral.description),error:\(error?.localizedDescription ?? "nil")")
        if let ipaPeripheral = self.getPeripheral(peripheral) {
            self.delegate.manager(self, didDisconnectPeripheral: ipaPeripheral,error:error)
        }
    }
}
