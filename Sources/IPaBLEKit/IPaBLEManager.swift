//
//  IPaBLEManager.swift
//  IPaBLEKit
//
//  Created by IPa Chen on 2022/6/8.
//

import UIKit
import CoreBluetooth
import IPaLog
import Combine
public protocol IPaBLEManagerDelegate {
    func createPeripheral(from manager: IPaBLEManager, with peripheral: CBPeripheral, advertisementData: [String : Any]?, rssi RSSI: NSNumber?) -> IPaPeripheral?
    func peripheral(_ ipaPeripheral:IPaPeripheral,isEqualTo peripheral:CBPeripheral,with advertisementData: [String : Any]) -> Bool
    func restorePeripheral(from manager: IPaBLEManager, with peripheral: CBPeripheral) -> IPaPeripheral?
    
    func manager(_ manager: IPaBLEManager, didDiscover peripheral:IPaPeripheral)
    func manager(_ manager: IPaBLEManager, willRestore peripheral:IPaPeripheral)
    func manager(_ manager: IPaBLEManager, didConnect peripheral:IPaPeripheral)
    func manager(_ manager: IPaBLEManager, didFailToConnect peripheral:IPaPeripheral, error: Error?)
    func manager(_ manager: IPaBLEManager, didDisconnectPeripheral peripheral:IPaPeripheral, error: Error?)
}
public class IPaBLEManager: NSObject {
    var centralManager:CBCentralManager!
    
    public var cbStateSubject = PassthroughSubject<CBManagerState,Never>()
    var scanTimer:Timer?
    var scanOptions:[String : Any]?
    public var isScanning:Bool {
        return scanTimer != nil
    }
    public var rescanTime:TimeInterval = 5 {
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
    public var delegate:IPaBLEManagerDelegate
    public init(_ services:[String]? = nil,queue:dispatch_queue_t = .main ,options:[String:Any]? = nil,delegate:IPaBLEManagerDelegate) {
        
        self.services = services?.map({ uuid in
            return CBUUID(string: uuid)
        })
        self.delegate = delegate
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: queue,options:options)
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
    @inlinable func getPeripheral(_ cbPeripheral:CBPeripheral,advertisementData:[String:Any]? = nil) -> IPaPeripheral? {
        return self.peripherals.first(where: { _peripheral in
            if _peripheral.peripheral?.identifier == cbPeripheral.identifier {
                return true
            }
            if let advertisementData = advertisementData {
                return self.delegate.peripheral(_peripheral, isEqualTo: cbPeripheral, with: advertisementData)
            }
            return false
        })
    }
}
extension IPaBLEManager:CBCentralManagerDelegate {
    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for peripheral in peripherals {
                IPaLog("Peripheral willRestoreState:\(peripheral.name ?? peripheral.description)")
                
                if let ipaPeripheral = self.getPeripheral(peripheral) {
                    ipaPeripheral._peripheral = peripheral
                    ipaPeripheral.lastDiscoverTime = Date().timeIntervalSince1970
                    self.delegate.manager(self, willRestore: ipaPeripheral)
                }
                else if let ipaPeripheral = self.delegate.restorePeripheral(from: self, with: peripheral) {
                    ipaPeripheral._peripheral = peripheral
                    ipaPeripheral.manager = self
                    
                    self.peripherals.append(ipaPeripheral)
                    self.delegate.manager(self, willRestore: ipaPeripheral)
                }
                
                
            }
        }
    }
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        self.cbStateSubject.send(central.state)
        
    }
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name,name.count > 0 else {
            return
        }
        IPaLog("Peripheral discovered updated:\(peripheral.name ?? peripheral.description)")
        if let ipaPeripheral = self.getPeripheral(peripheral,advertisementData: advertisementData) {
            ipaPeripheral._rssi = RSSI
            if ipaPeripheral.peripheral != peripheral {
                ipaPeripheral._peripheral = peripheral
            }
            ipaPeripheral.lastDiscoverTime = Date().timeIntervalSince1970
            self.delegate.manager(self, didDiscover: ipaPeripheral)
        }
        else if let ipaPeripheral = self.delegate.createPeripheral(from: self, with: peripheral, advertisementData: advertisementData, rssi: RSSI) {
            ipaPeripheral._peripheral = peripheral
            ipaPeripheral.manager = self
            ipaPeripheral._rssi = RSSI
            self.peripherals.append(ipaPeripheral)
            ipaPeripheral.lastDiscoverTime = Date().timeIntervalSince1970
            self.delegate.manager(self, didDiscover: ipaPeripheral)
        }
    }
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        IPaLog("Peripheral connected:\(peripheral.name ?? peripheral.description)")
        if let ipaPeripheral = self.getPeripheral(peripheral) {
            ipaPeripheral.onBLEConnected()
            self.delegate.manager(self, didConnect: ipaPeripheral)
            
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
            ipaPeripheral.onDisconnected(error)
        }
    }
}
