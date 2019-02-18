//
//  BKService.swift
//  UAPISampleApp
//
// 
//  Copyright © 2017 UEI. All rights reserved.
//

import Foundation
import CoreBluetooth

public class BKService {
  /// The UUID for the service used to send data. This should be unique to your applications.
  public let dataServiceUUID: CBUUID

  /// The UUID for the characteristics used to send data.
  public var writeDataServiceCharacteristicUUID: CBUUID

  /// The UUID for the characteristics used to recieve data.
  public var readDataServiceCharacteristicUUID: CBUUID

  // MARK: Initialization

  public init(dataServiceUUID: UUID, writeDataServiceCharacteristicUUID: CBUUID, readDataServiceCharacteristicUUID: CBUUID) {
    self.dataServiceUUID = CBUUID(nsuuid: dataServiceUUID)
    self.writeDataServiceCharacteristicUUID = writeDataServiceCharacteristicUUID
    self.readDataServiceCharacteristicUUID = readDataServiceCharacteristicUUID
  }
}
