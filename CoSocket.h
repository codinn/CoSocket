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
#include <sys/socket.h> // AF_INET, AF_INET6


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
 @param timeout The maximum amount of time to wait for a connection to succeed.
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
 Shutdown the connection to the remote host.
 
 Close vs shutdown socket:
 
 shutdown is a flexible way to block communication in one or both directions. When the second parameter is SHUT_RDWR, it will block both sending and receiving (like close). However, close is the way to actually destroy a socket.
 
 With shutdown, you will still be able to receive pending data the peer already sent (thanks to Joey Adams for noting this).
 
 Big difference between shutdown and close on a socket is the behavior when the socket is shared by other processes. A shutdown() affects all copies of the socket while close() affects only the file descriptor in one process.
 
 Someone also had success under linux using shutdown() from one pthread to force another pthread currently blocked in connect() to abort early.
 
 Under other OSes (OSX at least), I found calling close() was enough to get connect() fail.
 
 @return YES if the close succeeded, NO otherwise.
 */
- (BOOL)shutdown;

/**
 Sends the specified number bytes from the given data.
 
 @param data   The data containing the bytes to send.
 @return The actual number of bytes sent.
 */
- (BOOL)writeData:(NSData *)data;

/**
 Receives the exact number of bytes specified unless a timeout or other error occurs.
 Stores the bytes in the given buffer and returns whether the correct number of bytes
 was received.
 
 @param buf   The buffer in which to store the bytes received.
 @param count The exact number of bytes to receive, typically the size of the buffer.
 @return YES if the correct number of bytes was received, NO otherwise.
 */
- (NSData *)readDataToLength:(NSUInteger)length;

/**
 * Reads bytes until (and including) the passed "data" parameter, which acts as a separator.
 *
 * If you pass nil or zero-length data as the "data" parameter,
 * the method will do nothing (except maybe print a warning), and the delegate will not be called.
 *
 * To read a line from the socket, use the line separator (e.g. CRLF for HTTP, see below) as the "data" parameter.
 * If you're developing your own custom protocol, be sure your separator can not occur naturally as
 * part of the data between separators.
 * For example, imagine you want to send several small documents over a socket.
 * Using CRLF as a separator is likely unwise, as a CRLF could easily exist within the documents.
 * In this particular example, it would be better to use a protocol similar to HTTP with
 * a header that includes the length of the document.
 * Also be careful that your separator cannot occur naturally as part of the encoding for a character.
 *
 * The given data (separator) parameter should be immutable.
 * For performance reasons, the socket will retain it, not copy it.
 * So if it is immutable, don't modify it while the socket is using it.
 **/
- (NSData *)readDataToData:(NSData *)data;

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

#pragma mark Utilities

/**
 * The address lookup utility used by the class.
 * This method is synchronous, so it's recommended you use it on a background thread/queue.
 *
 * The special strings "localhost" and "loopback" return the loopback address for IPv4 and IPv6.
 *
 * @returns
 *   A mutable array with all IPv4 and IPv6 addresses returned by getaddrinfo.
 *   The addresses are specifically for TCP connections.
 *   You can filter the addresses, if needed, using the other utility methods provided by the class.
 **/
+ (NSMutableArray *)lookupHost:(NSString *)host port:(uint16_t)port error:(NSError **)errPtr;

/**
 * Extracting host and port information from raw address data.
 **/

+ (NSString *)hostFromAddress:(NSData *)address;
+ (uint16_t)portFromAddress:(NSData *)address;

+ (BOOL)isIPv4Address:(NSData *)address;
+ (BOOL)isIPv6Address:(NSData *)address;

+ (BOOL)getHost:(NSString **)hostPtr port:(uint16_t *)portPtr fromAddress:(NSData *)address;

+ (BOOL)getHost:(NSString **)hostPtr port:(uint16_t *)portPtr family:(sa_family_t *)afPtr fromAddress:(NSData *)address;

/**
 * A few common line separators, for use with the readDataToData:... methods.
 **/
+ (NSData *)CRLFData;   // 0x0D0A
+ (NSData *)CRData;     // 0x0D
+ (NSData *)LFData;     // 0x0A
+ (NSData *)ZeroData;   // 0x00

@end
