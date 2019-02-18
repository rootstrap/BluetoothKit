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

    //Latency delay - Value specified would be used te set a delay on data sent every betweenBytes
    public var sendDelay = 0
    public var betweenBytes = 20

    /**
     Sends data to a connected remote central.
     - parameter data: The data to send.
     - parameter remotePeer: The destination of the data payload.
     - parameter completionHandler: A completion handler allowing you to react in case the data failed to send or once it was sent succesfully.
     */
    public func sendData(_ data: Data, toRemotePeer remotePeer: BKRemotePeer, under serviceId: CBUUID, completionHandler: BKSendDataCompletionHandler?) {
        guard connectedRemotePeers.contains(remotePeer) else {
            completionHandler?(data, remotePeer, BKError.remotePeerNotConnected)
            return
        }
        guard let remotePeripheral = remotePeer as? BKRemotePeripheral else { return }
        remotePeripheral.sendDelegate = self

        let sendDataTask = BKSendDataTask(data: data, destination: remotePeer, completionHandler: completionHandler, underService: serviceId)
        sendDataTasks.append(sendDataTask)
        if sendDataTasks.count == 1 {
          if #available(iOS 11, *) {
              processSendDataTasks(under: serviceId)
          } else {
            processSendDataTasksWithDelay(under: serviceId)
          }
        }
    }

    internal func processSendDataTasks(under serviceId: CBUUID) {
        guard sendDataTasks.count > 0 else {
            return
        }

        let nextTask = sendDataTasks.first!
        let genericError = BKError.internalError(underlyingError: NSError(domain: "Not able to send data", code: 0, userInfo: nil))
        guard let nextPayload = nextTask.nextPayload else {
            sendDataTasks.remove(at: sendDataTasks.index(of: nextTask)!)
            nextTask.completionHandler?(nextTask.data, nextTask.destination, genericError)
            return
        }

        //Adds a delay of sendDelay if specified every betweenBytes sent
        if nextTask.offset != 0 && nextTask.offset % betweenBytes == 0 {
            let msDelay = UInt32(sendDelay * 1000)
            usleep(msDelay)
        }

        let dataSent = sendData(nextPayload, toRemotePeer: nextTask.destination, under: serviceId)
        if dataSent {
            nextTask.offset += nextPayload.count
        } else {
            sendDataTasks.remove(at: sendDataTasks.index(of: nextTask)!)
            nextTask.completionHandler?(nextTask.data, nextTask.destination, genericError)
            return
        }

        if nextTask.sentAllData {
            sendDataTasks.remove(at: sendDataTasks.index(of: nextTask)!)
            nextTask.completionHandler?(nextTask.data, nextTask.destination, nil)
        }
    }

    internal func processSendDataTasksWithDelay(under serviceId: CBUUID) {
        guard sendDataTasks.count > 0 else {
            return
        }

        let nextTask = sendDataTasks.first!
        let genericError = BKError.internalError(underlyingError: NSError(domain: "Not able to send data", code: 0, userInfo: nil))
        while !nextTask.sentAllData {
            guard let nextPayload = nextTask.nextPayload else {
                sendDataTasks.remove(at: sendDataTasks.index(of: nextTask)!)
                nextTask.completionHandler?(nextTask.data, nextTask.destination, genericError)
                return
            }

            //Adds a delay of sendDelay if specified every betweenBytes sent
            if nextTask.offset != 0 && nextTask.offset % betweenBytes == 0 {
                let msDelay = UInt32(sendDelay * 1000)
                usleep(msDelay)
            }

            let dataSent = sendData(nextPayload, toRemotePeer: nextTask.destination, under: serviceId)
            if dataSent {
                nextTask.offset += nextPayload.count
            } else {
                sendDataTasks.remove(at: sendDataTasks.index(of: nextTask)!)
                nextTask.completionHandler?(nextTask.data, nextTask.destination, genericError)
                return
            }
        }

        sendDataTasks.remove(at: sendDataTasks.index(of: nextTask)!)
        nextTask.completionHandler?(nextTask.data, nextTask.destination, nil)
    }

    internal func failSendDataTasksForRemotePeer(_ remotePeer: BKRemotePeer) {
        for sendDataTask in sendDataTasks.filter({ $0.destination == remotePeer }) {
            sendDataTasks.remove(at: sendDataTasks.index(of: sendDataTask)!)
            sendDataTask.completionHandler?(sendDataTask.data, sendDataTask.destination, .remotePeerNotConnected)
        }
    }

    internal func sendData(_ data: Data, toRemotePeer remotePeer: BKRemotePeer, under service: CBUUID) -> Bool {
        fatalError("Function must be overridden by subclass")
    }

}

extension BKPeer: BKSendDelegate {
  public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
    if sendDataTasks.count == 1, let serviceId = sendDataTasks.first?.underService {
      processSendDataTasks(under: serviceId)
    }
  }
}
