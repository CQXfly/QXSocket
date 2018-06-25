//
//  QXSocketManager.swift
//  QXSocket
//
//  Created by fox on 2018/6/11.
//

import Foundation
import Socket

public class QXTCPSocketManager: NSObject {
    
    static let quitCommand: String = "QUIT"
    static let shutdownCommand: String = "SHUTDOWN"
    static let bufferSize = 4096
    
    public typealias QXTCPSocketParseDataBlock = (_ data:Any)->()
    
    public var status = QXSocketStatus.disconnected
    public weak var delegate: QXSocketManagerProtocol?
    public var reqid: Int64 = 0
    public var needAutoReconnect: Bool = true
    public var timeout: TimeInterval  = 15
    public var reconnectTime: TimeInterval = 7
    public var reconnectRetryTimes: Int = 100
    
    let socketLockQueue = DispatchQueue(label: "com.ibm.serverSwift.socketLockQueue")
    var continueRunning = true
    
    //粘包 断包服务
    public var needUnpack: Bool = false
    public var headLen:Int?
    
    /**< 获取包长的BLOCK，给你包头Data，返回包头长度 */
    public var contentLenHandler: QXTCPSocketParseDataBlock?
    
    /**< 解包代码，实现这个block后会收到ytx_socketDidRecieveParsedData这个Delegate返回，否则需要自行在ytx_socketDidReceiveData中自行粘包 */
    public var parseReceivedDataBlock: QXTCPSocketParseDataBlock?
    
    /**< 封包代码，实现这个block后可已使用sendUnpackedData，内部会统一添加表头 */
    public var parseSentDataBlock: QXTCPSocketParseDataBlock?
    
    
    public var needSSL: Bool = false
    
    
    fileprivate let host: String!
    
    fileprivate let port: Int32!
    
    private var retryTimes: Int32 = 0
    
    fileprivate var socket: Socket?
    
    private var tmpData:Array<Any> = []
    
    fileprivate var socketQueue = DispatchQueue(label: "fox.socket.com")
    
    private var stashedMessages:Array<Any> = []
    
//    private let socket: BlueSocket!
    
    init(host:String,on port:Int32) {
        self.host = host
        self.port = port
        try? self.socket = Socket.create(family: .inet, type: .stream, proto: .tcp)
        
        
        super.init()
//        socket?.delegate = self
        
    }
    
    deinit {
        
    }
}

extension QXTCPSocketManager {
    
    public static func manager(host: String,on port: Int32)->QXTCPSocketManager {
        
        return QXTCPSocketManager(host: host, on: port)
    }
    
    public func connect(){
        try? self.socket?.connect(to: self.host, port: self.port)
        self.run()
        
        if !(socket?.isConnected)! {
            
            fatalError("Failed to connect to the server...")
        }
    }
    
    public func connectToHost(_ host:String,on port:Int32) {
        
        do {
            try self.socket?.connect(to: host, port: port)
            
//            self.run()
            
        } catch {
            print("connect error")
        }
    }
    
    public func disconnect(){
        socket?.close()
        socket = nil
    }
    
    func readAndPrint(socket: Socket, data: inout Data) throws -> String? {
        
        data.count = 0
        let    bytesRead = try socket.read(into: &data)
        if bytesRead > 0 {
            
            print("Read \(bytesRead) from socket...")
            
            guard let response = NSString(data: data as Data, encoding: String.Encoding.utf8.rawValue) else {
                
                print("Error accessing received data...")
            
                return nil
            }
            
            print("Response:\n\(response)")
            return String(describing: response)
        }
        
        return nil
    }
    
    public func send(data: Data)  {
        
        var datas = Data()
//        _ = try? readAndPrint(socket: socket, data: &datas)
        
        
        do {
            try socket?.write(from: String(data: data, encoding: .utf8)!)
            
            
        } catch let err   {
            print(err)
        }
    }
    
    
    public func run() {
        
        socketQueue.async { [unowned self, socket] in
            
            var shouldKeepRunning = true
            
            var readData = Data(capacity:QXTCPSocketManager.bufferSize)
            
            do {
                // Write the welcome string...
                try socket?.write(from: "Hello, type 'QUIT' to end session\nor 'SHUTDOWN' to stop server.\n")
                
                repeat {
                    let bytesRead = try socket?.read(into: &readData)
                    
                    if bytesRead! > 0 {
                        guard let response = String(data: readData, encoding: .utf8) else {
                            
                            print("Error decoding response...")
                            readData.count = 0
                            break
                        }
                        if response.hasPrefix(QXTCPSocketManager.shutdownCommand) {
                            
                            print("Shutdown requested by connection at \(socket?.remoteHostname):\(socket?.remotePort)")
                            
                            // Shut things down...
//                            self.shutdownServer()
                            
                            return
                        }
                        print("Server received from connection at \(socket?.remoteHostname):\(socket?.remotePort): \(response) ")
                        let reply = "Server response: \n\(response)\n"
                        
                        self.delegate?.qx_socketDidReceiveData(readData)
                        
//                        try socket?.write(from: reply)
                        
                        if (response.uppercased().hasPrefix(QXTCPSocketManager.quitCommand) || response.uppercased().hasPrefix(QXTCPSocketManager.shutdownCommand)) &&
                            (!response.hasPrefix(QXTCPSocketManager.quitCommand) && !response.hasPrefix(QXTCPSocketManager.shutdownCommand)) {
                            
//                            try socket?.write(from: "If you want to QUIT or SHUTDOWN, please type the name in all caps. 😃\n")
                        }
                        
                        if response.hasPrefix(QXTCPSocketManager.quitCommand) || response.hasSuffix(QXTCPSocketManager.quitCommand) {
                            
                            shouldKeepRunning = false
                        }
                    }
                    
                    if bytesRead == 0 {
                        
                        shouldKeepRunning = false
                        break
                    }
                    
                    readData.count = 0
                    
                } while shouldKeepRunning
                
                print("Socket: \(socket?.remoteHostname):\(socket?.remotePort) closed...")
                socket?.close()
              
                
            }
            catch let error {
                guard let socketError = error as? Socket.Error else {
                    print("Unexpected error by connection at \(socket?.remoteHostname):\(socket?.remotePort)...")
                    return
                }
                if self.continueRunning {
                    print("Error reported by connection at \(socket?.remoteHostname):\(socket?.remotePort):\n \(socketError.description)")
                }
            }
        }
    }
    
    /// 发送未经过处理的数据
    ///
    /// - Parameter data: 任何数据结构
    public func sendUnpacked(data: Any) {
        
    }
}


//extension QXTCPSocketManager:SSLServiceDelegate {
//    public func send(buffer: UnsafeRawPointer!, bufSize: Int) throws -> Int {
//        <#code#>
//    }
//
//    public func initialize(asServer: Bool) throws {
//
//    }
//
//    public func deinitialize() {
//
//    }
//
//    public func onAccept(socket: Socket) throws {
//
//    }
//
//    public func onConnect(socket: Socket) throws {
//
//    }
//
//    public func send(buffer: UnsafeRawPointer, bufSize: Int) throws -> Int {
//        return bufSize
//    }
//
//    public func recv(buffer: UnsafeMutableRawPointer, bufSize: Int) throws -> Int {
//        return bufSize
//    }
//
//
//}

//extension QXTCPSocketManager : QXSocketManagerProtocol {
//    func qx_socketDidConnect() {
//
//    }
//
//    func qx_socketDidDisconnect(_ err: Error) {
//
//    }
//
//    func qx_socketDidReceiveData(_ data: Data) {
//
//
//    }
//
//    func qx_socketDidReceiveParseData(_ data: Data) {
//
//    }
//
//    /// 加密c成功后的回调
//    func qx_socketDidSecure() {
//
//    }
//
//    func qx_SocketSecurityConfig()-> Dictionary<String, Any> {
//
//    }
//}



