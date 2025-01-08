//
//  IPaCBService.swift
//  IPaBLEKit
//
//  Created by IPa Chen on 2022/7/22.
//

import UIKit
import CoreBluetooth
public class IPaCBService:NSObject {
    @objc class public func keyPathsForValuesAffectingConnected() -> Set<String> {
        return ["_cbService"]
    }
    public private(set) var uuid:CBUUID
    @objc dynamic public var connected:Bool {
        return _cbService != nil
    }
    @objc dynamic weak var _cbService:CBService?
    public private(set) weak var cbService:CBService? {
        get {
            return _cbService
        }
        set {
            self._cbService = newValue
        }
    }
    lazy var characteristics = [CBUUID:IPaCBCharacteristic]()
    public convenience init(_ uuidString:String,characteristics:[IPaCBCharacteristic]? = nil) {
        self.init(CBUUID(string: uuidString),characteristics:characteristics)
    }
    public init(_ uuid:CBUUID,characteristics:[IPaCBCharacteristic]? = nil) {
        self.uuid = uuid
        super.init()
        self.characteristics = characteristics?.reduce([CBUUID:IPaCBCharacteristic](), { partialResult, characteristics in
            var partialResult = partialResult
            partialResult[characteristics.uuid] = characteristics
            return partialResult
        }) ?? [:]
    }
    public init(_ cbService:CBService) {
        self.uuid = cbService.uuid
        self._cbService = cbService
        super.init()
    }
    func disconnect() {
        for characteristic in self.characteristics.values {
            characteristic.disconnect()
        }
        self._cbService = nil
    }
}
