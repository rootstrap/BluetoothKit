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
                         toRemotePeer remotePeer: BKRemotePeer,
                         delay: Int = 0,
                         bytesBetweenDelay: Int = 0,
                         completionHandler: BKSendDataCompletionHandler?) {
        guard connectedRemotePeers.contains(remotePeer) else {
            completionHandler?(data, remotePeer, BKError.remotePeerNotConnected)
            return
        }

        remotePeer.writeDelegate = self
        let sendDataTask = BKSendDataTask(data: data,
                                          inCharacteristic: characteristicCBUUID,
                                          delay: delay,
                                          bytesBetweenDelay: bytesBetweenDelay,
                                          destination: remotePeer,
                                          completionHandler: completionHandler)
        sendDataTasks.append(sendDataTask)
        processSendDataTasks()
    }
  
    internal func processDataForiOS11() -> Bool {
        if #available(iOS 12, *) { return false }
        if #available(iOS 11, *) { return true }
        return false
    }

    internal func processSendDataTasks() {
        guard sendDataTasks.count > 0,
          let dataTask = sendDataTasks.first else { return }

        if processDataForiOS11() {
            //In iOS 11, delegate method to send next packet in data task is being called every time a packet is sent
            _ = sendPacket(withDataTask: dataTask,
                           delay: dataTask.delay,
                           bytesBetweenDelay: dataTask.bytesBetweenDelay)
        } else {
            var sent = true
            while !dataTask.sentAllData && sent {
                //If iOS 10 or lower, canSendWriteWithoutResponse always true,
                //If iOS 12 or higher and canSendWriteWithoutResponse false delegate method to send data in data task will be called when perpheral is ready
                guard dataTask.destination.canSendWriteWithoutResponse else { return }
            
                sent = sendPacket(withDataTask: dataTask,
                                  delay: dataTask.delay,
                                  bytesBetweenDelay: dataTask.bytesBetweenDelay)
            }
        }
    }

    internal func sendPacket(withDataTask dataTask: BKSendDataTask,
                             delay: Int = 0,
                             bytesBetweenDelay: Int = 0) -> Bool {
        let sendingError = BKError.internalError(underlyingError: NSError(domain: "Not able to send data",
                                                                          code: 0,
                                                                          userInfo: nil))
        guard let nextPayload = dataTask.nextPayload else {
            onSendingCompleted(withDataTask: dataTask, error: sendingError)
            return false
        }

        //Adds a delay of delay (in ms) every bytesBetweenDelay sent
        if delay > 0 && dataTask.offset != 0 && dataTask.offset % bytesBetweenDelay == 0 {
            let msDelay = UInt32(delay * 1000)
            usleep(msDelay)
        }

        let dataSent = sendData(nextPayload,
                                inCharacteristic: dataTask.characteristic,
                                toRemotePeer: dataTask.destination)
        guard dataSent else {
            onSendingCompleted(withDataTask: dataTask, error: sendingError)
            return false
        }

        dataTask.offset += nextPayload.count
        if dataTask.sentAllData {
            onSendingCompleted(withDataTask: dataTask)
        }
        return true
    }

    internal func onSendingCompleted(withDataTask dataTask: BKSendDataTask,
                                     error: BKError? = nil) {
        if let taskIndex = sendDataTasks.index(of: dataTask) {
            sendDataTasks.remove(at: taskIndex)
        }
        dataTask.completionHandler?(dataTask.data,
                                    dataTask.destination,
                                    error)
    }

    internal func failSendDataTasksForRemotePeer(_ remotePeer: BKRemotePeer) {
        for sendDataTask in sendDataTasks.filter({ $0.destination == remotePeer }) {
            sendDataTasks.remove(at: sendDataTasks.index(of: sendDataTask)!)
            sendDataTask.completionHandler?(sendDataTask.data, sendDataTask.destination, .remotePeerNotConnected)
        }
    }

    internal func sendData(_ data: Data,
                           inCharacteristic characteristicCBUUID: CBUUID,
                           toRemotePeer remotePeer: BKRemotePeer) -> Bool {
        fatalError("Function must be overridden by subclass")
    }
}

extension BKPeer: BKPeripheralWriteDelegate {
    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        processSendDataTasks()
    }
}
