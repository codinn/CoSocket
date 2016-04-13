//
//  SocketTests.swift
//  CoSocket
//
//  Created by Yang Yubo on 4/12/16.
//  Copyright © 2016 Codinn. All rights reserved.
//

import XCTest

class SocketTests: XCTestCase {
    var expectation: XCTestExpectation?

    let echoPort : UInt16 = 5007
    let echoTask = NSTask()
    
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
        waitForExpectationsWithTimeout(5) { error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
            }
            self.stopEchoServer()
        }
    }

    override func setUp() {
        super.setUp()
        startEchoServer()
    }
    
    override func tearDown() {
        stopEchoServer()
        super.tearDown()
    }

    func testExample() {
        expectation = expectationWithDescription("Open Direct Channel")
        waitEchoServerStart()
        
        let socket = CoSocket()
        
        do {
            try socket.connectToHost("localhost", onPort: self.echoPort, withTimeout: 10)
        } catch let error as NSError {
            XCTFail(error.description)
        }
        
    }
}
