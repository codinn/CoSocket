//
//  CoSocket.h
//  Copyright (c) 2011-2013 Daniel Reese <dan@danandcheryl.com>
//  Copyright (c) 2014 Yang Yubo <yang@codinn.com>
//
//  Some part of code is copied from GCDAsyncSocket project,
//  which created by Robbie Hanson in Q4 2010.
//  Updated and maintained by Deusty LLC and the Apple development community.
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

@interface CoSocket : NSObject

#pragma mark Configuration

/**
 * By default, both IPv4 and IPv6 are enabled.
 *
 * For accepting incoming connections, this means CoSocket automatically supports both protocols,
 * and can simulataneously accept incoming connections on either protocol.
 *
 * For outgoing connections, this means CoSocket can connect to remote hosts running either protocol.
 * If a DNS lookup returns only IPv4 results, CoSocket will automatically use IPv4.
 * If a DNS lookup returns only IPv6 results, CoSocket will automatically use IPv6.
 * If a DNS lookup returns both IPv4 and IPv6 results, the preferred protocol will be chosen.
 * By default, the preferred protocol is IPv4, but may be configured as desired.
 **/

@property (atomic, assign, readwrite, getter=isIPv4Enabled) BOOL IPv4Enabled;
@property (atomic, assign, readwrite, getter=isIPv6Enabled) BOOL IPv6Enabled;

@property (atomic, assign, readwrite, getter=isIPv4PreferredOverIPv6) BOOL IPv4PreferredOverIPv6;

#pragma mark Connecting

/**
 * Connects to the given host and port.
 *
 * This method invokes connectToHost:onPort:viaInterface:withTimeout:error:
 * and uses the default interface, and no timeout.
 **/
- (BOOL)connectToHost:(NSString *)host onPort:(uint16_t)port error:(NSError **)errPtr;

/**
 * Connects to the given host and port with an optional timeout.
 *
 * This method invokes connectToHost:onPort:viaInterface:withTimeout:error: and uses the default interface.
 **/
- (BOOL)connectToHost:(NSString *)host
               onPort:(uint16_t)port
          withTimeout:(NSTimeInterval)timeout
                error:(NSError **)errPtr;

/**
 * Connects to the given host & port, via the optional interface, with an optional timeout.
 *
 * The host may be a domain name (e.g. "deusty.com") or an IP address string (e.g. "192.168.0.2").
 * The host may also be the special strings "localhost" or "loopback" to specify connecting
 * to a service on the local machine.
 *
 * The interface may be a name (e.g. "en1" or "lo0") or the corresponding IP address (e.g. "192.168.4.35").
 * The interface may also be used to specify the local port (see below).
 *
 * To not time out use a negative time interval.
 *
 * This method will return NO if an error is detected, and set the error pointer (if one was given).
 * Possible errors would be a nil host, invalid interface, or socket is already connected.
 *
 * The interface may optionally contain a port number at the end of the string, separated by a colon.
 * This allows you to specify the local port that should be used for the outgoing connection. (read paragraph to end)
 * To specify both interface and local port: "en1:8082" or "192.168.4.35:2424".
 * To specify only local port: ":8082".
 * Please note this is an advanced feature, and is somewhat hidden on purpose.
 * You should understand that 99.999% of the time you should NOT specify the local port for an outgoing connection.
 * If you think you need to, there is a very good chance you have a fundamental misunderstanding somewhere.
 * Local ports do NOT need to match remote ports. In fact, they almost never do.
 * This feature is here for networking professionals using very advanced techniques.
 **/
- (BOOL)connectToHost:(NSString *)host
               onPort:(uint16_t)port
         viaInterface:(NSString *)interface
          withTimeout:(NSTimeInterval)timeout
                error:(NSError **)errPtr;

/**
 * Connects to the given address, specified as a sockaddr structure wrapped in a NSData object.
 * For example, a NSData object returned from NSNetService's addresses method.
 *
 * If you have an existing struct sockaddr you can convert it to a NSData object like so:
 * struct sockaddr sa  -> NSData *dsa = [NSData dataWithBytes:&remoteAddr length:remoteAddr.sa_len];
 * struct sockaddr *sa -> NSData *dsa = [NSData dataWithBytes:remoteAddr length:remoteAddr->sa_len];
 *
 * This method invokes connectToAdd
 **/
- (BOOL)connectToAddress:(NSData *)remoteAddr error:(NSError **)errPtr;

/**
 * This method is the same as connectToAddress:error: with an additional timeout option.
 * To not time out use a negative time interval, or simply use the connectToAddress:error: method.
 **/
- (BOOL)connectToAddress:(NSData *)remoteAddr withTimeout:(NSTimeInterval)timeout error:(NSError **)errPtr;

/**
 * Connects to the given address, using the specified interface and timeout.
 *
 * The address is specified as a sockaddr structure wrapped in a NSData object.
 * For example, a NSData object returned from NSNetService's addresses method.
 *
 * If you have an existing struct sockaddr you can convert it to a NSData object like so:
 * struct sockaddr sa  -> NSData *dsa = [NSData dataWithBytes:&remoteAddr length:remoteAddr.sa_len];
 * struct sockaddr *sa -> NSData *dsa = [NSData dataWithBytes:remoteAddr length:remoteAddr->sa_len];
 *
 * The interface may be a name (e.g. "en1" or "lo0") or the corresponding IP address (e.g. "192.168.4.35").
 * The interface may also be used to specify the local port (see below).
 *
 * The timeout is optional. To not time out use a negative time interval.
 *
 * This method will return NO if an error is detected, and set the error pointer (if one was given).
 * Possible errors would be a nil host, invalid interface, or socket is already connected.
 *
 * The interface may optionally contain a port number at the end of the string, separated by a colon.
 * This allows you to specify the local port that should be used for the outgoing connection. (read paragraph to end)
 * To specify both interface and local port: "en1:8082" or "192.168.4.35:2424".
 * To specify only local port: ":8082".
 * Please note this is an advanced feature, and is somewhat hidden on purpose.
 * You should understand that 99.999% of the time you should NOT specify the local port for an outgoing connection.
 * If you think you need to, there is a very good chance you have a fundamental misunderstanding somewhere.
 * Local ports do NOT need to match remote ports. In fact, they almost never do.
 * This feature is here for networking professionals using very advanced techniques.
 **/
- (BOOL)connectToAddress:(NSData *)remoteAddr
            viaInterface:(NSString *)interface
             withTimeout:(NSTimeInterval)timeout
                   error:(NSError **)errPtr;


#pragma mark Disconnecting

/**
 * Disconnects immediately (synchronously). Any pending reads or writes are dropped.
 *
 **/
- (void)disconnect;

#pragma mark Diagnostics

/**
 * Returns whether the socket is  connected.
 **/
@property (atomic, readonly) BOOL isConnected;

/**
 * Returns the local or remote host and port to which this socket is connected, or nil and 0 if not connected.
 * The host will be an IP address.
 **/
@property (atomic, readonly) NSString *connectedHost;
@property (atomic, readonly) uint16_t  connectedPort;

@property (atomic, readonly) NSString *localHost;
@property (atomic, readonly) uint16_t  localPort;

/**
 * Returns the local or remote address to which this socket is connected,
 * specified as a sockaddr structure wrapped in a NSData object.
 *
 * @seealso connectedHost
 * @seealso connectedPort
 * @seealso localHost
 * @seealso localPort
 **/
@property (atomic, readonly) NSData *connectedAddress;
@property (atomic, readonly) NSData *localAddress;

/**
 * Returns whether the socket is IPv4 or IPv6.
 * An accepting socket may be both.
 **/
@property (atomic, readonly) BOOL isIPv4;
@property (atomic, readonly) BOOL isIPv6;

#pragma mark Writing

/**
 Sends the specified number bytes from the given data.
 
 @param data   The data containing the bytes to send.
 @return The actual number of bytes sent.
 */
- (BOOL)writeData:(NSData *)data error:(NSError **)errPtr;


#pragma mark Reading

/**
 Receives the exact number of bytes specified unless a timeout or other error occurs.
 Stores the bytes in the given buffer and returns whether the correct number of bytes
 was received.
 
 @param buf   The buffer in which to store the bytes received.
 @param count The exact number of bytes to receive, typically the size of the buffer.
 @return YES if the correct number of bytes was received, NO otherwise.
 */
- (NSData *)readDataToLength:(NSUInteger)length error:(NSError **)errPtr;

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
- (NSData *)readDataToData:(NSData *)data error:(NSError **)errPtr;

#pragma mark Advanced

/**
* Provides access to the socket's file descriptor(s).
* If the socket is a server socket (is accepting incoming connections),
* it might actually have multiple internal socket file descriptors - one for IPv4 and one for IPv6.
**/
@property (nonatomic, readonly) int socketFD;
@property (nonatomic, readonly) int socket4FD;
@property (nonatomic, readonly) int socket6FD;

#pragma mark Utilities

/**
 * The address lookup utility used by the class.
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
