//
//  CoSocket.h
//  Copyright (c) 2011-2013 Daniel Reese <dan@danandcheryl.com>
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

#import <Foundation/Foundation.h>


#define NEW_ERROR(num, str) [[NSError alloc] initWithDomain:@"CoSocketErrorDomain" code:(num) userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"%s", (str)] forKey:NSLocalizedDescriptionKey]]

@interface CoSocket : NSObject

#pragma mark - Properties

/**
 The file descriptor used to communicate to the remote machine.
 */
@property (nonatomic, readonly) int sockfd;

/**
 The host name of the remote machine.
 */
@property (nonatomic, readonly) NSString *host;

/**
 The port number of the remote machine.
 */
@property (nonatomic, readonly) uint16_t port;

/**
 The last error that occured. This value is not set to nil after a successful call, so it is not
 appropriate to test this value to check for error conditions. Check for a NO or nil return value.
 */
@property (nonatomic, readonly) NSError *lastError;

#pragma mark - Initializers

/**
 Returns an initialized CoSocket object configured to connect to the given host name and port number.
 
 @param host The host name of the remote host.
 @param port The port number on which to connect.
 @return An initialized CoSocket object configured to connect to the given host name and port number.
 */
- (instancetype)initWithHost:(NSString *)host onPort:(uint16_t)port timeout:(NSTimeInterval)timeout;
- (instancetype)initWithHost:(NSString *)host onPort:(uint16_t)port;

/**
 Returns an initialized CoSocket object configured to communicate throught the given file descriptor.
 This method is primary used by a server socket to receive an incoming connection.
 
 @param fd The file descriptor to use for communication.
 @return An initialized CoSocket object configured to communicate throught the given file descriptor.
 */
- (instancetype)initWithFileDescriptor:(int)fd timeout:(NSTimeInterval)timeout;
- (instancetype)initWithFileDescriptor:(int)fd;

/**
 Retrieves the internal buffer and its size for use outside the class. This buffer is good
 to use for sending and receiving bytes because it is a multiple of the segment size and
 allocated so that it is aligned on a memory page boundary.
 */
- (void)buffer:(void **)buf size:(long *)size __attribute__((nonnull));

#pragma mark - Actions

/**
 Connect the socket to the remote host.
 
 @return YES if the connection succeeded, NO otherwise.
 */
- (BOOL)connect;

/**
 Connect the socket to the remote host with the given timeout value.
 
 @param timeout The maximum amount of time to wait for a connection to succeed.
 @return YES if the connection succeeded, NO otherwise.
 */
- (BOOL)connectWithTimeout:(NSTimeInterval)timeout;

/**
 Returns whether the socket is currently connected.
 
 @return YES if the socket is connected, NO otherwise.
 */
- (BOOL)isConnected;

/**
 Closes the connection to the remote host.
 
 @return YES if the close succeeded, NO otherwise.
 */
- (BOOL)close;

/**
 Sends the specified number bytes from the given data.
 
 @param data   The data containing the bytes to send.
 @return The actual number of bytes sent.
 */
- (BOOL)writeData:(NSData *)data;

/**
 Receives an unpredictable number bytes up to the specified limit. Stores the bytes
 in the given buffer and returns the actual number received.
 
 @param buf   The buffer in which to store the bytes received.
 @param limit The maximum number of bytes to receive, typically the size of the buffer.
 @return The actual number of bytes received.
 */
- (NSData *)readDataWithMaxLength:(NSUInteger)maxLength;

/**
 Receives the exact number of bytes specified unless a timeout or other error occurs.
 Stores the bytes in the given buffer and returns whether the correct number of bytes
 was received.
 
 @param buf   The buffer in which to store the bytes received.
 @param count The exact number of bytes to receive, typically the size of the buffer.
 @return YES if the correct number of bytes was received, NO otherwise.
 */
- (NSData *)readDataToLength:(NSUInteger)length;

#pragma mark - Settings

/**
 Returns the number of seconds to wait without any network activity before giving up and
 returning an error. The default is zero seconds, in which case it will never time out.
 
 @return The current timeout value in seconds.
 */
- (NSTimeInterval)timeout;

/**
 Sets the number of seconds to wait without any network activity before giving up and
 returning an error. The default is zero seconds, in which case it will never time out.
 
 @param seconds The number of seconds to wait before timing out.
 @return YES if the timeout value was set successfully, NO otherwise.
 */
- (BOOL)setTimeout:(NSTimeInterval)seconds;

/**
 Returns the maximum segment size. The segment size is the largest amount of
 data that can be transmitted within a single packet. Too large of a value may result in packets
 being broken apart and reassembled during transmission, which is normal but can slow things
 down. Too small of a value may result in lots of overhead, which can also slow things down.
 
 A default value is automatically negotiated when a connection is established. However, the
 negotiation process may incorporate assumptions that are incorrect. If you understand the
 network condidtions, setting this value correctly may increase performance.
 
 @return The current maximum segment value, measured in bytes.
 */
- (int)segmentSize;

/**
 Sets the maximum segment size. The segment size is the largest amount of
 data that can be transmitted within a single packet, excluding headers. Too large of a value
 may result in packets being broken apart and reassembled during transmission, which is normal
 but can slow things down. Too small of a value may result in lots of overhead, which can
 also slow things down.
 
 A default value is automatically negotiated when a connection is established. However, the
 negotiation process may incorporate assumptions that are incorrect. If you understand the
 network condidtions, setting this value correctly may increase performance.
 
 @param bytes The maximum segment size, measured in bytes.
 @return YES if the segment size value was set successfully, NO otherwise.
 */
- (BOOL)setSegmentSize:(int)bytes;

@end
