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

public typealias BKSendDataCompletionHandler = ((_ data: Data, _ remotePeer: BKRemotePeer, _ error: BKError?) -> Void)

public class BKPeer {

    /// The configuration the BKCentral object was started with.
    public var configuration: BKConfiguration? {
        return nil
    }

    internal var connectedRemotePeers: [BKRemotePeer] {
        get {
            return _connectedRemotePeers
        }
        set {
            _connectedRemotePeers = newValue
        }
    }

    internal var sendDataTasks: [BKSendDataTask] = []

    private var _connectedRemotePeers: [BKRemotePeer] = []

    /**
     Sends data to a connected remote central.
     - parameter data: The data to send.
     - parameter remotePeer: The destination of the data payload.
     - parameter completionHandler: A completion handler allowing you to react in case the data failed to send or once it was sent succesfully.
     */
    public func sendData(_ data: Data,
                         inCharacteristic characteristicCBUUID: CBUUID,
                         underService serviceCBUUID: CBUUID,
                         toRemotePeer remotePeer: BKRemotePeer,
                         completionHandler: BKSendDataCompletionHandler?) {
        guard connectedRemotePeers.contains(remotePeer) else {
            completionHandler?(data, remotePeer, BKError.remotePeerNotConnected)
            return
        }
        guard let remotePeripheral = remotePeer as? BKRemotePeripheral else {
          let genericError = BKError.genericError(reason: "Not able to send data")
          completionHandler?(data, remotePeer, genericError)
          return
        }

        remotePeripheral.sendDelegate = self //TODO: check where this delegate should go

        let sendDataTask = BKSendDataTask(data: data,
                                          inCharacteristic: characteristicCBUUID,
                                          underService: serviceCBUUID,
                                          destination: remotePeer,
                                          completionHandler: completionHandler)
        sendDataTasks.append(sendDataTask)
        if sendDataTasks.count == 1 {
            if #available(iOS 11, *) {
                processSendDataTasks(inCharacteristic: characteristicCBUUID,
                                     underService: serviceCBUUID)
            } else {
//                processSendDataTasksWithDelay(inCharacteristic: characteristicCBUUID,
//                                              underService: serviceCBUUID)
              //TODO: check this
            }
        }
    }

  internal func processSendDataTasks(inCharacteristic characteristicCBUUID: CBUUID,
                                     underService serviceCBUUID: CBUUID) {
        guard sendDataTasks.count > 0,
          let nextTask = sendDataTasks.first else { return }

        let genericError = BKError.internalError(underlyingError: NSError(domain: "Not able to send data",
                                                                          code: 0,
                                                                          userInfo: nil))
        guard let nextPayload = nextTask.nextPayload else {
            sendDataTasks.remove(at: sendDataTasks.index(of: nextTask)!)
            nextTask.completionHandler?(nextTask.data,
                                        nextTask.destination,
                                        genericError)
            return
        }

        //Adds a delay of sendDelay if specified every betweenBytes sent
    //TODO: Add delay
//        if nextTask.offset != 0 && nextTask.offset % betweenBytes == 0 {
//            let msDelay = UInt32(sendDelay * 1000)
//            usleep(msDelay)
//        }

          let dataSent = sendData(nextPayload,
                                  inCharacteristic: characteristicCBUUID,
                                  underService: serviceCBUUID,
                                  toRemotePeer: nextTask.destination)
          if dataSent {
              nextTask.offset += nextPayload.count
          } else {
              if let taskIndex = sendDataTasks.index(of: nextTask) {
                  sendDataTasks.remove(at: taskIndex)
              }
              nextTask.completionHandler?(nextTask.data,
                                          nextTask.destination,
                                          genericError)
              return
          }

          if nextTask.sentAllData {
              sendDataTasks.remove(at: sendDataTasks.index(of: nextTask)!)
              nextTask.completionHandler?(nextTask.data, nextTask.destination, nil)
          }
    }

    internal func failSendDataTasksForRemotePeer(_ remotePeer: BKRemotePeer) {
        for sendDataTask in sendDataTasks.filter({ $0.destination == remotePeer }) {
            sendDataTasks.remove(at: sendDataTasks.index(of: sendDataTask)!)
            sendDataTask.completionHandler?(sendDataTask.data, sendDataTask.destination, .remotePeerNotConnected)
        }
    }

    internal func sendData(_ data: Data,
                           inCharacteristic characteristicCBUUID: CBUUID,
                           underService serviceCBUUID: CBUUID,
                           toRemotePeer remotePeer: BKRemotePeer) -> Bool {
        fatalError("Function must be overridden by subclass")
    }
}

extension BKPeer: BKPeripheralSendDelegate {
    public func remotePeripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        if sendDataTasks.count == 1,
          let service = sendDataTasks.first?.service,
          let characteristic = sendDataTasks.first?.characteristic {
              processSendDataTasks(inCharacteristic: characteristic,
                                   underService: service)
        }
    }
}
