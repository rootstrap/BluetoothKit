//
//  BluetoothKit
//
//  Copyright (c) 2015 Rasmus Taulborg Hummelmose - https://github.com/rasmusth
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation
import CoreBluetooth

/**
    The delegate of a remote peripheral receives callbacks when asynchronous events occur.
*/
public protocol BKRemotePeripheralDelegate: class {

    /**
        Called when the remote peripheral updated its name.
        - parameter remotePeripheral: The remote peripheral that updated its name.
        - parameter name: The new name.
    */
    func remotePeripheral(_ remotePeripheral: BKRemotePeripheral, didUpdateName name: String)

    /**
        Called when services and charateristic are discovered and the device is ready for send/receive
        - parameter remotePeripheral: The remote peripheral that is ready.
     */
    func remotePeripheralIsReady(_ remotePeripheral: BKRemotePeripheral)

    /**
        Called when insufficient authorization error received when trying to read a charateristic.
    */
    func remotePeripheralInsufficientAuthorization(_ remotePeripheral: BKRemotePeripheral, characteristic: CBCharacteristic)
}

public protocol BKSendDelegate: class {
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral)
}

/**
    Class to represent a remote peripheral that can be connected to by BKCentral objects.
*/
public class BKRemotePeripheral: BKRemotePeer, BKCBPeripheralDelegate {

    // MARK: Enums

    /**
        Possible states for BKRemotePeripheral objects.
        - Shallow: The peripheral was initialized only with an identifier (used when one wants to connect to a peripheral for which the identifier is known in advance).
        - Disconnected: The peripheral is disconnected.
        - Connecting: The peripheral is currently connecting.
        - Connected: The peripheral is already connected.
        - Disconnecting: The peripheral is currently disconnecting.
    */
    public enum State {
        case shallow, disconnected, connecting, connected, disconnecting
    }

    // MARK: Properties

    /// The current state of the remote peripheral, either shallow or derived from an underlying CBPeripheral object.
    public var state: State {
        if peripheral == nil {
            return .shallow
        }
        #if os(iOS) || os(tvOS)
        switch peripheral!.state {
            case .disconnected: return .disconnected
            case .connecting: return .connecting
            case .connected: return .connected
            case .disconnecting: return .disconnecting
        }
        #else
        switch peripheral!.state {
            case .disconnected: return .disconnected
            case .connecting: return .connecting
            case .connected: return .connected
        }
        #endif
    }

    /// The name of the remote peripheral, derived from an underlying CBPeripheral object.
    public var name: String? {
        return peripheral?.name
    }

    /// The amount of tries to pair with remote peripheral object.
    public var intentTimes = 0

    /// The version info of the remote peripheral, derived from Software Revision String 0x2A28 in advertised packet.
    public var swVersion = ""

    /// The remote peripheral's delegate.
    public weak var peripheralDelegate: BKRemotePeripheralDelegate?

    public weak var sendDelegate: BKSendDelegate?

    override internal var maximumUpdateValueLength: Int {
        guard #available(iOS 9, *), let peripheral = peripheral else {
            return super.maximumUpdateValueLength
        }
        #if os(OSX)
            return super.maximumUpdateValueLength
        #else
            return peripheral.maximumWriteValueLength(for: .withoutResponse)
        #endif
    }

    internal var characteristicsData: [BKCharacteristic] = []

    internal var peripheral: CBPeripheral?

    private var peripheralDelegateProxy: BKCBPeripheralDelegateProxy!

    // MARK: Initialization

    public init(identifier: UUID, peripheral: CBPeripheral?) {
        super.init(identifier: identifier)
        self.peripheralDelegateProxy = BKCBPeripheralDelegateProxy(delegate: self)
        self.peripheral = peripheral
    }

    // MARK: Public Functions
    public func readCharacteristic(from service: CBUUID) {
      if service == BKConfiguration.deviceInfoService,
        let devInfoService = peripheral?.services?.filter({ $0.uuid == service }).first,
        let swVersionCharacteristic = devInfoService.characteristics?.filter({ $0.uuid == BKConfiguration.softwareRevisionInfo }).first {
        read(characteristic: swVersionCharacteristic)
      } else if let characteristicData = characteristicsData.filter({ $0.serviceUUID == service && $0.isReadable}).first {
        read(characteristic: characteristicData.characteristic)
      }
    }

    // MARK: Internal Functions
    private func read(characteristic: CBCharacteristic) {
      peripheral?.readValue(for: characteristic)
    }

    internal func prepareForConnection() {
        peripheral?.delegate = peripheralDelegateProxy
    }

    internal func discoverServices() {
        if peripheral?.services != nil {
            peripheral(peripheral!, didDiscoverServices: nil)
            return
        }

        peripheral?.discoverServices(configuration!.serviceUUIDs)
    }

    internal func unsubscribe() {
        guard peripheral?.services != nil else {
            return
        }
        for service in peripheral!.services! {
            guard service.characteristics != nil else {
                continue
            }
            for characteristic in service.characteristics! {
                peripheral?.setNotifyValue(false, for: characteristic)
            }
        }
    }

    // MARK: BKCBPeripheralDelegate

    internal func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        peripheralDelegate?.remotePeripheral(self, didUpdateName: name!)
    }

    internal func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else {
            return
        }
        for service in services {
            if service.characteristics != nil {
                self.peripheral(peripheral, didDiscoverCharacteristicsFor: service, error: nil)
            } else {
                peripheral.discoverCharacteristics(configuration!.characteristicUUIDsForServiceUUID(service.uuid), for: service)
            }
        }
    }

    internal func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if service.uuid == BKConfiguration.deviceInfoService, let versionInfo = service.characteristics?.filter({ $0.uuid == BKConfiguration.softwareRevisionInfo }).last {
            read(characteristic: versionInfo)
            return
        }

        guard let bkService = configuration!.services.filter({ $0.dataServiceUUID == service.uuid }).first else { return }

        if let dataCharacteristic = service.characteristics?.filter({ $0.uuid == bkService.writeDataServiceCharacteristicUUID }).last {
          characteristicsData.append(BKCharacteristic(serviceUUID: bkService.dataServiceUUID, characteristic: dataCharacteristic, isReadable: false))
        }

        if let dataCharacteristic = service.characteristics?.filter({ $0.uuid == bkService.readDataServiceCharacteristicUUID }).last {
          characteristicsData.append(BKCharacteristic(serviceUUID: bkService.dataServiceUUID, characteristic: dataCharacteristic, isReadable: true))
          peripheral.setNotifyValue(true, for: dataCharacteristic) //TODO
        }

        peripheralDelegate?.remotePeripheralIsReady(self)
    }

    internal func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let value = characteristic.value else {
          if let error = error as NSError?,
            error.code == CBATTError.insufficientAuthorization.rawValue {
            peripheralDelegate?.remotePeripheralInsufficientAuthorization(self, characteristic: characteristic)
          }
          return
        }

        if characteristic.uuid == BKConfiguration.softwareRevisionInfo {
          swVersion = String(data: characteristic.value!, encoding: .utf8) ?? ""
        } else {
          handleReceivedData(value, from: characteristic.uuid)
        }
    }

    internal func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let bkCharacteristic = characteristicsData.filter({ $0.characteristic.uuid == characteristic.uuid }).first {
          bkCharacteristic.characteristic = characteristic
        }

        peripheralDelegate?.remotePeripheralIsReady(self)
    }

    internal func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
      sendDelegate?.peripheralIsReady(toSendWriteWithoutResponse: peripheral)
    }
}
