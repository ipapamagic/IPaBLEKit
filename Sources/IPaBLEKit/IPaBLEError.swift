//
//  IPaBLEError.swift
//  Pods
//
//  Created by IPa Chen on 2025/1/18.
//


public enum IPaBLEError: Error, LocalizedError {
    case timeout
    case encodingFailed
    case characteristicNotDiscovered
    case characteristicNotifyUpdateFailed
    case error(error: Error)

    public var errorDescription: String? {
        switch self {
        case .timeout:
            return "Operation timed out"
        case .encodingFailed:
            return "Encoding failed"
        case .characteristicNotDiscovered:
            return "Characteristic not discovered"
        case .characteristicNotifyUpdateFailed:
            return "Characteristic notify update failed"
        case .error(let error):
            return error.localizedDescription
        }
    }
}
