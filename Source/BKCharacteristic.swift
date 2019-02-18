//
//  BKCharacteristic.swift
//  UAPISampleApp
//
//
//  Copyright © 2017 UEI. All rights reserved.
//

import Foundation
import CoreBluetooth

public class BKCharacteristic {
  /// The UUID for the service used to send data. This should be unique to your applications.
  public let serviceUUID: CBUUID

  /// The UUID for the characteristics used to send data.
  public var characteristic: CBCharacteristic

  public var isReadable: Bool

  // MARK: Initialization

  public init(serviceUUID: CBUUID, characteristic: CBCharacteristic, isReadable: Bool) {
    self.serviceUUID = serviceUUID
    self.characteristic = characteristic
    self.isReadable = isReadable
  }
}
