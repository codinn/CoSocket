//
//  SocketTests.swift
//  CoSocket
//
//  Created by Yang Yubo on 4/12/16.
//  Copyright © 2016 Codinn. All rights reserved.
//

import XCTest
import Darwin

class SocketTests: XCTestCase {
    var expectation: XCTestExpectation?

    let echoPort : UInt16 = 5007
    let echoTask = NSTask()
    
    // for artificially create a connection timeout error
    let nonRoutableIP = "10.255.255.1"
    
    let ipv4Address = "127.0.0.1"
    let ipv6Address = "::1"
    let targetHost = "localhost"
    
    func startEchoServer() {
        let echoServer = NSBundle(forClass: self.dynamicType).pathForResource("echo_server.py", ofType: "");
        echoTask.launchPath = echoServer
        echoTask.arguments = ["-p", "\(echoPort)"]
        
        let pipe = NSPipe()
        echoTask.standardOutput = pipe
        echoTask.standardError = pipe
        echoTask.standardInput = NSFileHandle.fileHandleWithNullDevice()
        pipe.fileHandleForReading.readabilityHandler = { (handler: NSFileHandle?) in
            if let data = handler?.availableData {
                if let output = String(data: data, encoding: NSUTF8StringEncoding) {
                    print(output)
                }
            }
            
            self.expectation?.fulfill()
            // stop catch output
            pipe.fileHandleForReading.readabilityHandler = nil;
        }
        
        echoTask.terminationHandler = { (task: NSTask) in
            // set readabilityHandler block to nil; otherwise, you'll encounter high CPU usage
            pipe.fileHandleForReading.readabilityHandler = nil;
        }
        
        echoTask.launch()
    }
    
    func stopEchoServer() {
        echoTask.terminate()
    }
    
    func waitEchoServerStart() {
        expectation = expectationWithDescription("Wait echo server start")
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                XCTFail(error.localizedDescription)
                self.stopEchoServer()
            }
        }
    }

    override func setUp() {
        super.setUp()
        startEchoServer()
        waitEchoServerStart()
    }
    
    override func tearDown() {
        stopEchoServer()
        super.tearDown()
    }
    
    func readWriteVerifyOnSocket(socket: CoSocket) throws {
        let echoData = "Hello world!".dataUsingEncoding(NSUTF8StringEncoding)
        try socket.writeData(echoData)
        let echoBackData = try socket.readDataToData(echoData)
        XCTAssertEqual(echoData, echoBackData)
    }
    
    // MARK: - Connect
    
    func testConnectWithoutTimeout() {
        let socket = CoSocket()
        
        do {
            try socket.connectToHost(targetHost, onPort: self.echoPort, withTimeout: 0)
            XCTAssertTrue(socket.isConnected)
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }

    func testConnectWithTimeout() {
        let socket = CoSocket()
        
        do {
            try socket.connectToHost(targetHost, onPort: self.echoPort, withTimeout: 10)
            XCTAssertTrue(socket.isConnected)
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testConnectTimedOut() {
        let socket = CoSocket()
        
        do {
            try socket.connectToHost(nonRoutableIP, onPort: self.echoPort, withTimeout: 1)
        } catch let error as NSError {
            XCTAssertEqual(error.code, Int(ETIMEDOUT), error.description)
            return
        }
        
        XCTFail("Connect should timed out")
    }
    
    func testConnectViaLoopbackInterface() {
        let socket = CoSocket()
        
        do {
            try socket.connectToHost(ipv4Address, onPort: self.echoPort, viaInterface: "lo0", withTimeout: 1)
            XCTAssertTrue(socket.isConnected)
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testConnectViaUnknownInterface() {
        let socket = CoSocket()
        
        do {
            try socket.connectToHost(nonRoutableIP, onPort: self.echoPort, viaInterface: "unknown", withTimeout: 1)
        } catch let error as NSError {
            XCTAssertEqual(error.code, Int(ENOEXEC), error.description)
            return
        }
        
        XCTFail("Connection should fail")
    }
    
    // MARK: - Disconnect
    
    func testDisconnect() {
        let socket = CoSocket()
        let echoData = "Hello world!".dataUsingEncoding(NSUTF8StringEncoding)
        
        do {
            try socket.connectToHost(ipv6Address, onPort: self.echoPort, withTimeout: 0)
            try socket.writeData(echoData)
            XCTAssertTrue(socket.isConnected)
            socket.disconnect()
            XCTAssertFalse(socket.isConnected)
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    // MARK: - Write
    
    func testWriteData() {
        let socket = CoSocket()
        let echoData = "Hello world!".dataUsingEncoding(NSUTF8StringEncoding)
        
        do {
            try socket.connectToHost(targetHost, onPort: self.echoPort, withTimeout: 0)
            try socket.writeData(echoData)
        } catch let error as NSError {
            XCTFail(error.description)
        }
        
        XCTAssertTrue(socket.isConnected)
    }
    
    func testWriteEmptyData() {
        let socket = CoSocket()
        let echoData = NSData()
        
        do {
            try socket.connectToHost(targetHost, onPort: self.echoPort, withTimeout: 0)
            try socket.writeData(echoData)
        } catch _ as NSError {
            XCTAssertTrue(socket.isConnected)
            return
        }
        
        XCTFail("Write operation should fail")
    }
    
    func testWriteAfterDisconnect() {
        let socket = CoSocket()
        let echoData = "Hello world!".dataUsingEncoding(NSUTF8StringEncoding)
        
        do {
            try socket.connectToHost(ipv6Address, onPort: self.echoPort, withTimeout: 0)
            XCTAssertTrue(socket.isConnected)
            socket.disconnect()
            XCTAssertFalse(socket.isConnected)
            try socket.writeData(echoData)
        } catch let error as NSError {
            XCTAssertEqual(error.code, Int(EBADF), error.description)
            return
        }
        
        XCTFail("Write operation should fail")
    }
    
    // MARK: - Read
    
    func testReadToData() {
        let socket = CoSocket()
        let echoData = "Hello world!".dataUsingEncoding(NSUTF8StringEncoding)
        
        do {
            try socket.connectToHost(targetHost, onPort: self.echoPort, withTimeout: 0)
            try socket.writeData(echoData)
            
            let echoBackData = try socket.readDataToData(echoData)
            XCTAssertEqual(echoData, echoBackData)
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testReadToLength() {
        let socket = CoSocket()
        let echoData = "Hello world!".dataUsingEncoding(NSUTF8StringEncoding)
        
        do {
            try socket.connectToHost(targetHost, onPort: self.echoPort, withTimeout: 0)
            try socket.writeData(echoData)
            
            let echoBackData = try socket.readDataToLength(UInt((echoData?.length)!))
            XCTAssertEqual(echoData, echoBackData)
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testReadAfterDisconnect() {
        let socket = CoSocket()
        let echoData = "Hello world!".dataUsingEncoding(NSUTF8StringEncoding)
        
        do {
            try socket.connectToHost("::1", onPort: self.echoPort, withTimeout: 0)
            XCTAssertTrue(socket.isConnected)
            try socket.writeData(echoData)
            socket.disconnect()
            XCTAssertFalse(socket.isConnected)
            try socket.readDataToLength(UInt((echoData?.length)!))
        } catch let error as NSError {
            XCTAssertEqual(error.code, Int(EBADF), error.description)
            return
        }
        
        XCTFail("Read operation should fail")
    }
    
    // MARK: - IPv4 / IPv6
    
    func testConnectToIPv4WithIPv4Enabled() {
        let socket = CoSocket()
        socket.IPv4Enabled = true;
        socket.IPv6Enabled = false;
        
        do {
            try socket.connectToHost(ipv4Address, onPort: self.echoPort, withTimeout: 0)
            try readWriteVerifyOnSocket(socket)
        } catch let error as NSError {
            XCTFail(error.description)
        }
    }
    
    func testConnectToIPv4WithIPv4AndIPv6Disabled() {
        let socket = CoSocket()
        socket.IPv4Enabled = false;
        socket.IPv6Enabled = false;
        
        do {
            try socket.connectToHost(ipv4Address, onPort: self.echoPort, withTimeout: 0)
            try readWriteVerifyOnSocket(socket)
        } catch let error as NSError {
            XCTAssertEqual(error.code, Int(ENOEXEC), error.description)
            return
        }
        
        XCTFail("Connect should fail")
    }
    
    func testConnectToIPv6WithIPv4AndIPv6Disabled() {
        let socket = CoSocket()
        socket.IPv4Enabled = false;
        socket.IPv6Enabled = false;
        
        do {
            try socket.connectToHost(ipv6Address, onPort: self.echoPort, withTimeout: 0)
            try readWriteVerifyOnSocket(socket)
        } catch let error as NSError {
            XCTAssertEqual(error.code, Int(ENOEXEC), error.description)
            return
        }
        
        XCTFail("Connect should fail")
    }
    
    func testConnectToIPv4WithIPv4Disabled() {
        let socket = CoSocket()
        socket.IPv4Enabled = false;
        socket.IPv6Enabled = true;
        
        do {
            try socket.connectToHost(ipv4Address, onPort: self.echoPort, withTimeout: 0)
            try readWriteVerifyOnSocket(socket)
        } catch let error as NSError {
            XCTAssertEqual(error.code, Int(ENOEXEC), error.description)
            return
        }
        
        XCTFail("Connect should fail")
    }
    
    func testConnectToIPv6WithIPv6Disabled() {
        let socket = CoSocket()
        socket.IPv4Enabled = true;
        socket.IPv6Enabled = false;
        
        do {
            try socket.connectToHost(ipv6Address, onPort: self.echoPort, withTimeout: 0)
            try readWriteVerifyOnSocket(socket)
        } catch let error as NSError {
            XCTAssertEqual(error.code, Int(ENOEXEC), error.description)
            return
        }
        
        XCTFail("Connect should fail")
    }
    
    // MARK: - Connected Host / Port
    
    func testConnectedHostPort() {
        let socket = CoSocket()
        
        XCTAssertNil(socket.connectedHost)
        XCTAssertEqual(socket.connectedPort, 0)
        
        do {
            try socket.connectToHost(ipv4Address, onPort: self.echoPort, withTimeout: 0)
            try readWriteVerifyOnSocket(socket)
        } catch let error as NSError {
            XCTFail(error.description)
        }
        
        XCTAssertEqual(socket.connectedHost, ipv4Address)
        XCTAssertEqual(socket.connectedPort, self.echoPort)
    }
    
    func testConnectedHostPortWithIPv6Prefered() {
        let socket = CoSocket()
        socket.IPv4PreferredOverIPv6 = false
        
        XCTAssertNil(socket.connectedHost)
        XCTAssertEqual(socket.connectedPort, 0)
        
        do {
            try socket.connectToHost(targetHost, onPort: self.echoPort, withTimeout: 0)
            try readWriteVerifyOnSocket(socket)
        } catch let error as NSError {
            XCTFail(error.description)
        }
        
        XCTAssertEqual(socket.connectedHost, ipv6Address)
        XCTAssertEqual(socket.connectedPort, self.echoPort)
    }
}
