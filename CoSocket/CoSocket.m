//
//  CoSocket.m
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

//
//  See the following for source information for this code:
//  http://beej.us/guide/bgnet/
//  http://www.phildev.net/mss/blackhole_description.shtml
//  http://www.mikeash.com/pyblog/friday-qa-2011-02-18-compound-literals.html
//  http://cr.yp.to/docs/connect.html
//
//  Set optimal packet size: 1500 bytes (Ethernet) - 40 bytes (TCP) - 12 bytes (Optional TCP timestamp) = 1448 bytes.
//  http://www.faqs.org/docs/gazette/tcp.html
//  http://smallvoid.com/article/windows-tcpip-settings.html
//  http://developer.apple.com/mac/library/documentation/Darwin/Reference/ManPages/man4/tcp.4.html
//
//  Disk caching is not needed unless the file will be accessed again soon (avoids
//  a buffer copy). Increasing the size of the TCP receive window is better for
//  fast networks. Using page-aligned memory allows the kernel to skip a buffer
//  copy. Using a multiple of the max segment size avoids partially filled network
//  buffers. Ethernet and IPv4 headers are each 20 bytes. OS X uses the optional
//  12 byte TCP timestamp. Disabling TCP wait (Nagle's algorithm) is better for
//  sending files since all packets are large and the waiting slows things down.
//


#import "CoSocket.h"
#import <CommonCrypto/CommonDigest.h>
#import <netdb.h>
#import <net/if.h>
#import <netinet/tcp.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <fcntl.h>
#import <ifaddrs.h>
#import <sys/socket.h>
#import <sys/types.h>
#import <sys/ioctl.h>

#define CoSocketErrorDomain @"CoSocketErrorDomain"
#define CoTCPSocketBufferSize 65536 // 64K
#define SOCKET_NULL -1

static struct timeval get_timeval(NSTimeInterval interval);

#if 0
static NSTimeInterval get_interval(struct timeval tv);
#endif

static int connect_timeout(int sockfd, const struct sockaddr *address, socklen_t address_len, struct timeval * timeout, CoSocketLogHandler logDebug);


@interface CoSocket () {
@protected
	void *_buffer;
	long _size;
    NSTimeInterval _timeout;    // select() may update the timeout argument
    // to indicate how much time was left.
    
    NSData * _connectInterface;
}
@end


@implementation CoSocket

- (instancetype)init
{
	if ((self = [super init])) {
		_socketFD = SOCKET_NULL;
		_size = CoTCPSocketBufferSize;
		_buffer = malloc(_size);
        _timeout = 0;
        
        self.IPv4Enabled = YES;
        self.IPv6Enabled = YES;
        self.IPv4PreferredOverIPv6 = YES;
	}
	return self;
}

- (void)dealloc {
    [self disconnect];
    _socketFD = SOCKET_NULL;
	free(_buffer);
}
///////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Errors
///////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (NSError *)gaiError:(int)gai_error
{
    NSString *errMsg = [NSString stringWithCString:gai_strerror(gai_error) encoding:NSASCIIStringEncoding];
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:errMsg forKey:NSLocalizedDescriptionKey];
    
    return [NSError errorWithDomain:@"kCFStreamErrorDomainNetDB" code:gai_error userInfo:userInfo];
}

- (NSError *)errnoErrorWithReason:(NSString *)reason
{
    NSString *errMsg = [NSString stringWithUTF8String:strerror(errno)];
    NSDictionary *userInfo = @{
                               NSLocalizedDescriptionKey : errMsg,
                               NSLocalizedFailureReasonErrorKey : reason,
                               };
    
    return [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:userInfo];
}

- (NSError *)errnoError
{
    NSString *errMsg = [NSString stringWithUTF8String:strerror(errno)];
    NSDictionary *userInfo = @{
                               NSLocalizedDescriptionKey : errMsg,
                               };
    
    return [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:userInfo];
}

- (NSError *)otherError:(NSString *)errMsg
{
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:errMsg forKey:NSLocalizedDescriptionKey];
    
    return [NSError errorWithDomain:CoSocketErrorDomain code:8 userInfo:userInfo];
}

//////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Connecting
//////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)preConnectWithInterface:(NSString *)interface error:(NSError **)errPtr
{
    if ([self isConnected]) { // Must be disconnected
        if (errPtr) {
            *errPtr = [self otherError:@"Attempting to connect while connected or accepting connections. Disconnect first."];
        }
        
        return NO;
    }
    
    if (!self.isIPv4Enabled && !self.isIPv6Enabled) { // Must have IPv4 or IPv6 enabled
        if (errPtr) {
            *errPtr = [self otherError:@"Both IPv4 and IPv6 have been disabled. Must enable at least one protocol first."];
        }
        return NO;
    }
    
    if (interface) {
        NSMutableData *interface4 = nil;
        NSMutableData *interface6 = nil;
        
        [self getInterfaceAddress4:&interface4 address6:&interface6 fromDescription:interface port:0];
        
        if ((interface4 == nil) && (interface6 == nil)) {
            if (errPtr) {
                *errPtr = [self otherError:@"Unknown interface. Specify valid interface by name (e.g. \"en1\") or IP address."];
            }
            return NO;
        }
        
        if (!self.isIPv4Enabled && (interface6 == nil)) {
            if (errPtr) {
                *errPtr = [self otherError:@"IPv4 has been disabled and specified interface doesn't support IPv6."];
            }
            return NO;
        }
        
        if (!self.isIPv6Enabled && (interface4 == nil)) {
            if (errPtr) {
                *errPtr = [self otherError:@"IPv6 has been disabled and specified interface doesn't support IPv4."];
            }
            return NO;
        }
        
        // Determine socket type
        BOOL useIPv4 = (self.isIPv4Enabled && ( (self.isIPv4PreferredOverIPv6 && interface4) || (interface6 == nil) ) );
        
        if (useIPv4) {
            _connectInterface = interface4;
        } else {
            _connectInterface = interface6;
        }
    }
    
    return YES;
}


- (BOOL)connectWithAddress4:(NSData *)address4 address6:(NSData *)address6 error:(NSError **)errPtr
{
    // Determine socket type
    BOOL useIPv4 = (self.isIPv4Enabled && ( (self.isIPv4PreferredOverIPv6 && address4) || (address6 == nil) ) );
    
    // Create the socket
    
    NSData *address;
    
    if (useIPv4) {
        _socketFD = socket(AF_INET, SOCK_STREAM, 0);
        address = address4;
        if (_logDebug) _logDebug(@"Create socket with IPv4 address family");
    } else {
        _socketFD = socket(AF_INET6, SOCK_STREAM, 0);
        address = address6;
        if (_logDebug) _logDebug(@"Create socket with IPv6 address family");
    }
    
    if (_socketFD == SOCKET_NULL) {
        if (errPtr)
            *errPtr = [self errnoErrorWithReason:@"Error in socket() function"];
        
        return NO;
    }
    
    // Bind the socket to the desired interface (if needed)
    
    if (_connectInterface) {
        if ([self.class portFromAddress:_connectInterface] > 0) {
            // Since we're going to be binding to a specific port,
            // we should turn on reuseaddr to allow us to override sockets in time_wait.
            
            int reuseOn = 1;
            setsockopt(_socketFD, SOL_SOCKET, SO_REUSEADDR, &reuseOn, sizeof(reuseOn));
        }
        
        const struct sockaddr *interfaceAddr = (const struct sockaddr *) _connectInterface.bytes;
        
        if (bind(_socketFD, interfaceAddr, (socklen_t)_connectInterface.length) != 0) {
            if (errPtr)
                *errPtr = [self errnoErrorWithReason:@"Error in bind() function"];
            
            return NO;
        }
        
        if (_logDebug) _logDebug(@"Bound to specified interface");
    }
    
    // Numerous Small Packet Exchanges Result In Poor TCP Performance
    // Make interactive shell, rdp etc, more responsive by disable the Nagle algorithm
    // More info: xcdoc://?url=developer.apple.com/library/etc/redirect/xcode/mac/34580/qa/nw26/_index.html
    if (setsockopt(_socketFD, IPPROTO_TCP, TCP_NODELAY, &(int){1}, sizeof(int))==-1) {
        if (_logDebug) _logDebug(@"Failed to set TCP_NODELAY");
    }
    
    // Instead of receiving a SIGPIPE signal, have write() return an error.
    if (setsockopt(_socketFD, SOL_SOCKET, SO_NOSIGPIPE, &(int){1}, sizeof(int)) != 0) {
        if (errPtr) *errPtr = [self errnoError];
        [self disconnect];
        return NO;
    }
    
    // Set socket to non-blocking.
    fcntl(_socketFD, F_SETFL, O_NONBLOCK);
    
    struct timeval timeout = get_timeval(_timeout);
    struct timeval *timeoutPtr = NULL;
    if (_timeout>0) {
        timeoutPtr = &timeout;
    }
    
    // Connect the socket using the given timeout.
    if (connect_timeout(_socketFD, (const struct sockaddr *)address.bytes, (socklen_t)address.length, timeoutPtr, _logDebug) < 0) {
        if (errPtr) *errPtr = [self errnoError];
        [self disconnect];
        return NO;
    }
    
    return YES;
}

- (BOOL)connectToHost:(NSString*)host onPort:(uint16_t)port error:(NSError **)errPtr
{
    return [self connectToHost:host onPort:port withTimeout:-1 error:errPtr];
}

- (BOOL)connectToHost:(NSString *)host
               onPort:(uint16_t)port
          withTimeout:(NSTimeInterval)timeout
                error:(NSError **)errPtr
{
    return [self connectToHost:host onPort:port viaInterface:nil withTimeout:timeout error:errPtr];
}

- (BOOL)connectToHost:(NSString *)inHost
               onPort:(uint16_t)port
         viaInterface:(NSString *)inInterface
          withTimeout:(NSTimeInterval)timeout
                error:(NSError **)errPtr
{
    if (_logDebug) _logDebug(@"Connect to %@:%d, with timeout %f", inHost, port, timeout);
    
    _timeout = timeout;
    
    // Just in case immutable objects were passed
    NSString *host = [inHost copy];
    NSString *interface = [inInterface copy];
    
    // Check for problems with host parameter
    
    if (!host.length) {
        if (errPtr) *errPtr = [self otherError:@"Invalid host parameter (nil or \"\"). Should be a domain name or IP address string."];
        
        return NO;
    }
    
    // Run through standard pre-connect checks
    
    if (![self preConnectWithInterface:interface error:errPtr]) {
        return NO;
    }
    
    // We've made it past all the checks.
    // It's time to start the connection process.
    
    // It's possible that the given host parameter is actually a NSMutableString.
    // So we want to copy it now, within this block that will be executed synchronously.
    // This way the asynchronous lookup block below doesn't have to worry about it changing.
    
    NSString *hostCpy = [host copy];
    
    NSMutableArray *addresses = [self.class lookupHost:hostCpy port:port error:errPtr];
    
    if (errPtr && *errPtr) {
        [self disconnect];
        return NO;
    } else {
        NSData *address4 = nil;
        NSData *address6 = nil;
        
        for (NSData *address in addresses) {
            if (!address4 && [self.class isIPv4Address:address]) {
                address4 = address;
            } else if (!address6 && [self.class isIPv6Address:address]) {
                address6 = address;
            }
        }
        
        // Check for problems
        
        if (!self.isIPv4Enabled && (address6 == nil)) {
            NSString *msg = @"IPv4 has been disabled and DNS lookup found no IPv6 address.";
            if (errPtr) *errPtr = [self otherError:msg];
            [self disconnect];
            return NO;
        }
        
        if (!self.isIPv6Enabled && (address4 == nil)) {
            NSString *msg = @"IPv6 has been disabled and DNS lookup found no IPv4 address.";
            
            if (errPtr) *errPtr = [self otherError:msg];
            [self disconnect];
            return NO;
        }
        
        // Start the normal connection process
        
        if (![self connectWithAddress4:address4 address6:address6 error:errPtr]) {
            [self disconnect];
            return NO;
        };
    }
    
    return YES;
}

- (BOOL)connectToAddress:(NSData *)remoteAddr error:(NSError **)errPtr
{
    return [self connectToAddress:remoteAddr viaInterface:nil withTimeout:-1 error:errPtr];
}

- (BOOL)connectToAddress:(NSData *)remoteAddr withTimeout:(NSTimeInterval)timeout error:(NSError **)errPtr
{
    return [self connectToAddress:remoteAddr viaInterface:nil withTimeout:timeout error:errPtr];
}

- (BOOL)connectToAddress:(NSData *)inRemoteAddr
            viaInterface:(NSString *)inInterface
             withTimeout:(NSTimeInterval)timeout
                   error:(NSError **)errPtr
{
    _timeout = timeout;
    
    // Just in case immutable objects were passed
    NSData *remoteAddr = [inRemoteAddr copy];
    NSString *interface = [inInterface copy];
    
    // Check for problems with remoteAddr parameter
    
    NSData *address4 = nil;
    NSData *address6 = nil;
    
    if ([remoteAddr length] >= sizeof(struct sockaddr)) {
        const struct sockaddr *sockaddr = (const struct sockaddr *)[remoteAddr bytes];
        
        if (sockaddr->sa_family == AF_INET) {
            if ([remoteAddr length] == sizeof(struct sockaddr_in)) {
                address4 = remoteAddr;
            }
        } else if (sockaddr->sa_family == AF_INET6) {
            if ([remoteAddr length] == sizeof(struct sockaddr_in6)) {
                address6 = remoteAddr;
            }
        }
    }
    
    if ((address4 == nil) && (address6 == nil)) {
        if (errPtr) *errPtr = [self otherError:@"A valid IPv4 or IPv6 address was not given"];
        
        return NO;
    }
    
    if (!self.isIPv4Enabled && (address4 != nil)) {
        if (errPtr) *errPtr = [self otherError:@"IPv4 has been disabled and an IPv4 address was passed."];
        
        return NO;
    }
    
    if (!self.isIPv6Enabled && (address6 != nil)) {
        if (errPtr) *errPtr = [self otherError:@"IPv6 has been disabled and an IPv6 address was passed."];
        
        return NO;
    }
    
    // Run through standard pre-connect checks
    
    if (![self preConnectWithInterface:interface error:errPtr]) {
        return NO;
    }
    
    // We've made it past all the checks.
    // It's time to start the connection process.
    
    if (![self connectWithAddress4:address4 address6:address6 error:errPtr]) {
        return NO;
    }
    
    return YES;
}

/**
 Shutdown the connection to the remote host.
 
 Close vs shutdown socket:
 
 shutdown is a flexible way to block communication in one or both directions. When the second parameter is SHUT_RDWR, it will block both sending and receiving (like close). However, close is the way to actually destroy a socket.
 
 With shutdown, you will still be able to receive pending data the peer already sent (thanks to Joey Adams for noting this).
 
 Big difference between shutdown and close on a socket is the behavior when the socket is shared by other processes. A shutdown() affects all copies of the socket while close() affects only the file descriptor in one process.
 
 Someone also had success under linux using shutdown() from one pthread to force another pthread currently blocked in connect() to abort early.
 
 Under other OSes (OSX at least), I found calling close() was enough to get connect() fail.
 */
- (void)disconnect
{
    if (_socketFD != SOCKET_NULL) {
        shutdown(_socketFD, SHUT_RDWR);
        close(_socketFD);
    }
}

- (BOOL)writeData:(NSData *)theData error:(NSError *__autoreleasing *)errPtr
{
    fd_set writemask;
    
    if (theData.length <= 0) {
        if (errPtr) *errPtr = [self otherError:@"Socket write data length must bigger than zero"];
        return NO;
    }
    
    const char * dataBytes = theData.bytes;
    ssize_t index = 0;
    
    struct timeval timeout = get_timeval(_timeout);
    struct timeval *timeoutPtr = NULL;
    if (_timeout>0) {
        timeoutPtr = &timeout;
    }
    
    while (index < theData.length) {
        /* We must set all this information on each select we do */
        FD_ZERO(&writemask);   /* empty readmask */
        
        /* Then we put all the descriptors we want to wait for in a */
        /* mask = writemask */
        FD_SET(_socketFD, &writemask);
        
        /* The first parameter is the biggest descriptor+1. The first one
         was 0, so every other descriptor will be bigger.*/
        /* readfds = we are not waiting for readfds */
        /* writefds = &writemask */
        /* exceptfds = we are not waiting for exception fds */
        int select_result = select(_socketFD+1, NULL, &writemask, NULL, timeoutPtr);
        
        if (select_result==-1) {
            if (errPtr) *errPtr = [self errnoError];
            [self disconnect];
            return NO;
        }
        
        if (select_result==0) {     // Timeout
            errno = ETIMEDOUT;
            if (errPtr) *errPtr = [self errnoErrorWithReason:@"Socket write timed out"];
            
            [self disconnect];
            return NO;
        }
        
        /* If something was received */
        if (FD_ISSET(_socketFD, &writemask)) {
            ssize_t toWrite = MIN((theData.length - index), _size);
            
            ssize_t wrote = send(_socketFD, &dataBytes[index], toWrite, 0);
            
            if (wrote == 0) {
                // socket has been closed or shutdown for send
                if (errPtr) *errPtr = [self otherError:@"Peer has closed the socket"];
                [self disconnect];
                return NO;
            }
            
            if (wrote < 0) {
                if (errPtr) *errPtr = [self errnoError];
                [self disconnect];
                return NO;
            }
            
            index += wrote;
        }
    }
    
    return YES;
}

- (NSData *)readDataToLength:(NSUInteger)length error:(NSError *__autoreleasing *)errPtr
{
    fd_set readmask;
    
    if (length == 0) {
        if (errPtr) *errPtr = [self otherError:@"Socket read length must bigger than zero"];
        [self disconnect];
        return nil;
    }
    
    struct timeval timeout = get_timeval(_timeout);
    struct timeval *timeoutPtr = NULL;
    if (_timeout>0) {
        timeoutPtr = &timeout;
    }
    
    ssize_t hasRead = 0;
    while (hasRead < length) {
        /* We must set all this information on each select we do */
        FD_ZERO(&readmask);   /* empty readmask */
        
        /* Then we put all the descriptors we want to wait for in a */
        /* mask = readmask */
        FD_SET(_socketFD, &readmask);
        
        /* The first parameter is the biggest descriptor+1. The first one
         was 0, so every other descriptor will be bigger.*/
        /* readfds = &readmask */
        /* writefds = we are not waiting for writefds */
        /* exceptfds = we are not waiting for exception fds */
        int select_result = select(_socketFD+1, &readmask, NULL, NULL, timeoutPtr);
        if (select_result==-1) {    // On error
            if (errPtr) *errPtr = [self errnoError];
            [self disconnect];
            return nil;
        }
        
        if (select_result==0) {     // Timeout
            errno = ETIMEDOUT;
            if (errPtr) *errPtr = [self errnoErrorWithReason:@"Socket read timed out"];
            
            [self disconnect];
            return nil;
        }
        
        /* If something was received */
        if (FD_ISSET(_socketFD, &readmask)) {
            ssize_t toRead = MIN( (length - hasRead), _size);
            
            ssize_t justRead = recv(_socketFD, &_buffer[hasRead], toRead, 0);
            
            if (justRead == 0) {
                // socket has been closed or shutdown for send
                if (errPtr) *errPtr = [self otherError:@"Peer has closed the socket"];
                [self disconnect];
                return nil;
            }
            
            if (justRead < 0) {
                if (errPtr) *errPtr = [self errnoError];
                [self disconnect];
                return nil;
            }
            
            hasRead += justRead;
        }
    }
    
    NSData * theData = [NSData dataWithBytes:_buffer length:hasRead];
    return theData;
}


- (NSData *)readDataToData:(NSData *)data error:(NSError *__autoreleasing *)errPtr
{
    fd_set readmask;
    
    if (!data.length) {
        if (errPtr) *errPtr = [self otherError:@"Socket passed nil or zero-length data as a separator"];
        [self disconnect];
        return nil;
    }
    
    ssize_t hasRead     = 0;
    
    const char *separator   = (const char*)data.bytes;
    NSUInteger cursor       = 0;
    NSUInteger terminal     = data.length;
    
    struct timeval timeout = get_timeval(_timeout);
    struct timeval *timeoutPtr = NULL;
    if (_timeout>0) {
        timeoutPtr = &timeout;
    }
    
    while (cursor < terminal) {
        /* We must set all this information on each select we do */
        FD_ZERO(&readmask);   /* empty readmask */
        
        /* Then we put all the descriptors we want to wait for in a */
        /* mask = readmask */
        FD_SET(_socketFD, &readmask);
        
        /* The first parameter is the biggest descriptor+1. The first one
         was 0, so every other descriptor will be bigger.*/
        /* readfds = &readmask */
        /* writefds = we are not waiting for writefds */
        /* exceptfds = we are not waiting for exception fds */
        int select_result = select(_socketFD+1, &readmask, NULL, NULL, timeoutPtr);
        if (select_result==-1) {
            if (errPtr) *errPtr = [self errnoError];
            [self disconnect];
            return nil;
        }
        
        if (select_result==0) {     // Timeout
            errno = ETIMEDOUT;
            if (errPtr) *errPtr = [self errnoErrorWithReason:@"Socket read timed out"];
            [self disconnect];
            return nil;
        }
        
        /* If something was received */
        if (FD_ISSET(_socketFD, &readmask)) {
            if ( hasRead >= _size ) {
                if (errPtr) *errPtr = [self otherError:@"The separator could not be found in socket stream"];
                [self disconnect];
                return nil;
            }
            
            ssize_t justRead = recv(_socketFD, &_buffer[hasRead], 1, 0);
            
            if (justRead == 0) {
                // socket has been closed or shutdown for send
                if (errPtr) *errPtr = [self otherError:@"Peer has closed the socket"];
                [self disconnect];
                return nil;
            }
            
            if (justRead < 0) {
                if (errPtr) *errPtr = [self errnoError];
                [self disconnect];
                return nil;
            }
            
            if ( ((const char*)_buffer)[hasRead] == separator[cursor]) {
                cursor++;
            } else {
                cursor = 0;
            }
            
            hasRead += justRead;
        }
    }
    
    NSData * theData = [NSData dataWithBytes:_buffer length:hasRead];
    return theData;
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Diagnostics
///////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)isConnected
{
    int error = 0;
    socklen_t len = sizeof (error);
    int retval = getsockopt (_socketFD, SOL_SOCKET, SO_ERROR, &error, &len );
    return retval==0;
}

- (NSString *)connectedHost
{
    return [self.class hostFromAddress:[self connectedAddress]];
}

- (uint16_t)connectedPort
{
    return [self.class portFromAddress:[self connectedAddress]];
}

- (NSString *)localHost
{
    return [self.class hostFromAddress:[self localAddress]];
}

- (uint16_t)localPort
{
    return [self.class portFromAddress:[self localAddress]];
}

- (NSData *)connectedAddress
{
    NSData *result = nil;
    
    if (_socketFD != SOCKET_NULL) {
        struct sockaddr_storage sock_addr;
        socklen_t sock_addr_len = sizeof(sock_addr);
        
        if (getpeername(_socketFD, (struct sockaddr *)&sock_addr, &sock_addr_len) == 0) {
            result = [[NSData alloc] initWithBytes:&sock_addr length:sock_addr_len];
        }
    }
    
    return result;
}

- (NSData *)localAddress
{
    NSData *result = nil;
    
    if (_socketFD != SOCKET_NULL) {
        struct sockaddr_storage sock_addr;
        socklen_t sock_addr_len = sizeof(sock_addr);
        
        if (getsockname(_socketFD, (struct sockaddr *)&sock_addr, &sock_addr_len) == 0) {
            result = [[NSData alloc] initWithBytes:&sock_addr length:sock_addr_len];
        }
    }
    
    return result;
}

- (BOOL)isIPv4
{
    return [self.class isIPv4Address:[self localAddress]];
}

- (BOOL)isIPv6
{
    return [self.class isIPv6Address:[self localAddress]];
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Utilities
///////////////////////////////////////////////////////////////////////////////////////////////////////////

/**
 * Finds the address of an interface description.
 * An inteface description may be an interface name (en0, en1, lo0) or corresponding IP (192.168.4.34).
 *
 * The interface description may optionally contain a port number at the end, separated by a colon.
 * If a non-zero port parameter is provided, any port number in the interface description is ignored.
 *
 * The returned value is a 'struct sockaddr' wrapped in an NSMutableData object.
 **/
- (void)getInterfaceAddress4:(NSMutableData **)interfaceAddr4Ptr
                    address6:(NSMutableData **)interfaceAddr6Ptr
             fromDescription:(NSString *)interfaceDescription
                        port:(uint16_t)port
{
    NSMutableData *addr4 = nil;
    NSMutableData *addr6 = nil;
    
    NSString *interface = nil;
    
    NSArray *components = [interfaceDescription componentsSeparatedByString:@":"];
    
    if ([components count] > 0) {
        NSString *temp = [components objectAtIndex:0];

        if ([temp length] > 0) {
            interface = temp;
        }
    }
    
    if ([components count] > 1 && port == 0) {
        long portL = strtol([[components objectAtIndex:1] UTF8String], NULL, 10);
        
        if (portL > 0 && portL <= UINT16_MAX) {
            port = (uint16_t)portL;
        }
    }
    
    if (interface == nil) {
        // ANY address
        
        struct sockaddr_in sockaddr4;
        memset(&sockaddr4, 0, sizeof(sockaddr4));
        
        sockaddr4.sin_len         = sizeof(sockaddr4);
        sockaddr4.sin_family      = AF_INET;
        sockaddr4.sin_port        = htons(port);
        sockaddr4.sin_addr.s_addr = htonl(INADDR_ANY);
        
        struct sockaddr_in6 sockaddr6;
        memset(&sockaddr6, 0, sizeof(sockaddr6));
        
        sockaddr6.sin6_len       = sizeof(sockaddr6);
        sockaddr6.sin6_family    = AF_INET6;
        sockaddr6.sin6_port      = htons(port);
        sockaddr6.sin6_addr      = in6addr_any;
        
        addr4 = [NSMutableData dataWithBytes:&sockaddr4 length:sizeof(sockaddr4)];
        addr6 = [NSMutableData dataWithBytes:&sockaddr6 length:sizeof(sockaddr6)];
    } else if ([interface isEqualToString:@"localhost"] || [interface isEqualToString:@"loopback"]) {
        // LOOPBACK address
        
        struct sockaddr_in sockaddr4;
        memset(&sockaddr4, 0, sizeof(sockaddr4));
        
        sockaddr4.sin_len         = sizeof(sockaddr4);
        sockaddr4.sin_family      = AF_INET;
        sockaddr4.sin_port        = htons(port);
        sockaddr4.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        
        struct sockaddr_in6 sockaddr6;
        memset(&sockaddr6, 0, sizeof(sockaddr6));
        
        sockaddr6.sin6_len       = sizeof(sockaddr6);
        sockaddr6.sin6_family    = AF_INET6;
        sockaddr6.sin6_port      = htons(port);
        sockaddr6.sin6_addr      = in6addr_loopback;
        
        addr4 = [NSMutableData dataWithBytes:&sockaddr4 length:sizeof(sockaddr4)];
        addr6 = [NSMutableData dataWithBytes:&sockaddr6 length:sizeof(sockaddr6)];
    } else {
        const char *iface = [interface UTF8String];
        
        struct ifaddrs *addrs;
        const struct ifaddrs *cursor;
        
        if ((getifaddrs(&addrs) == 0)) {
            cursor = addrs;
            while (cursor != NULL) {
                if ((addr4 == nil) && (cursor->ifa_addr->sa_family == AF_INET)) {
                    // IPv4
                    
                    struct sockaddr_in nativeAddr4;
                    memcpy(&nativeAddr4, cursor->ifa_addr, sizeof(nativeAddr4));
                    
                    if (strcmp(cursor->ifa_name, iface) == 0) {
                        // Name match
                        
                        nativeAddr4.sin_port = htons(port);
                        
                        addr4 = [NSMutableData dataWithBytes:&nativeAddr4 length:sizeof(nativeAddr4)];
                    } else {
                        char ip[INET_ADDRSTRLEN];
                        
                        const char *conversion = inet_ntop(AF_INET, &nativeAddr4.sin_addr, ip, sizeof(ip));
                        
                        if ((conversion != NULL) && (strcmp(ip, iface) == 0))  {
                            // IP match
                            
                            nativeAddr4.sin_port = htons(port);
                            
                            addr4 = [NSMutableData dataWithBytes:&nativeAddr4 length:sizeof(nativeAddr4)];
                        }
                    }
                } else if ((addr6 == nil) && (cursor->ifa_addr->sa_family == AF_INET6)) {
                    // IPv6
                    
                    struct sockaddr_in6 nativeAddr6;
                    memcpy(&nativeAddr6, cursor->ifa_addr, sizeof(nativeAddr6));
                    
                    if (strcmp(cursor->ifa_name, iface) == 0) {
                        // Name match
                        
                        nativeAddr6.sin6_port = htons(port);
                        
                        addr6 = [NSMutableData dataWithBytes:&nativeAddr6 length:sizeof(nativeAddr6)];
                    } else {
                        char ip[INET6_ADDRSTRLEN];
                        
                        const char *conversion = inet_ntop(AF_INET6, &nativeAddr6.sin6_addr, ip, sizeof(ip));
                        
                        if ((conversion != NULL) && (strcmp(ip, iface) == 0)) {
                            // IP match
                            
                            nativeAddr6.sin6_port = htons(port);
                            
                            addr6 = [NSMutableData dataWithBytes:&nativeAddr6 length:sizeof(nativeAddr6)];
                        }
                    }
                }
                
                cursor = cursor->ifa_next;
            }
            
            freeifaddrs(addrs);
        }
    }
    
    if (interfaceAddr4Ptr) *interfaceAddr4Ptr = addr4;
    if (interfaceAddr6Ptr) *interfaceAddr6Ptr = addr6;
}

//////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Class Utilities
//////////////////////////////////////////////////////////////////////////////////////////////////////////

+ (NSMutableArray *)lookupHost:(NSString *)host port:(uint16_t)port error:(NSError **)errPtr
{
    NSMutableArray *addresses = nil;
    NSError *error = nil;
    
    if ([host isEqualToString:@"localhost"] || [host isEqualToString:@"loopback"]) {
        // Use LOOPBACK address
        struct sockaddr_in nativeAddr4;
        nativeAddr4.sin_len         = sizeof(struct sockaddr_in);
        nativeAddr4.sin_family      = AF_INET;
        nativeAddr4.sin_port        = htons(port);
        nativeAddr4.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        memset(&(nativeAddr4.sin_zero), 0, sizeof(nativeAddr4.sin_zero));
        
        struct sockaddr_in6 nativeAddr6;
        nativeAddr6.sin6_len        = sizeof(struct sockaddr_in6);
        nativeAddr6.sin6_family     = AF_INET6;
        nativeAddr6.sin6_port       = htons(port);
        nativeAddr6.sin6_flowinfo   = 0;
        nativeAddr6.sin6_addr       = in6addr_loopback;
        nativeAddr6.sin6_scope_id   = 0;
        
        // Wrap the native address structures
        
        NSData *address4 = [NSData dataWithBytes:&nativeAddr4 length:sizeof(nativeAddr4)];
        NSData *address6 = [NSData dataWithBytes:&nativeAddr6 length:sizeof(nativeAddr6)];
        
        addresses = [NSMutableArray arrayWithCapacity:2];
        [addresses addObject:address4];
        [addresses addObject:address6];
    } else {
        NSString *portStr = [NSString stringWithFormat:@"%hu", port];
        
        struct addrinfo hints, *res, *res0;
        
        memset(&hints, 0, sizeof(hints));
        hints.ai_family   = PF_UNSPEC;
        hints.ai_socktype = SOCK_STREAM;
        hints.ai_protocol = IPPROTO_TCP;
        
        int gai_error = getaddrinfo([host UTF8String], [portStr UTF8String], &hints, &res0);
        
        if (gai_error) {
            error = [self gaiError:gai_error];
        } else {
            NSUInteger capacity = 0;
            for (res = res0; res; res = res->ai_next) {
                if (res->ai_family == AF_INET || res->ai_family == AF_INET6) {
                    capacity++;
                }
            }
            
            addresses = [NSMutableArray arrayWithCapacity:capacity];
            
            for (res = res0; res; res = res->ai_next) {
                if (res->ai_family == AF_INET) {
                    // Found IPv4 address.
                    // Wrap the native address structure, and add to results.
                    
                    NSData *address4 = [NSData dataWithBytes:res->ai_addr length:res->ai_addrlen];
                    [addresses addObject:address4];
                } else if (res->ai_family == AF_INET6) {
                    // Found IPv6 address.
                    // Wrap the native address structure, and add to results.
                    
                    NSData *address6 = [NSData dataWithBytes:res->ai_addr length:res->ai_addrlen];
                    [addresses addObject:address6];
                }
            }
            
            freeaddrinfo(res0);
            
            if ([addresses count] == 0) {
                error = [self gaiError:EAI_FAIL];
            }
        }
    }
    
    if (errPtr) *errPtr = error;
    return addresses;
}

+ (NSString *)hostFromSockaddr:(const struct sockaddr *)pSockaddr
{
    if (pSockaddr->sa_family == AF_INET) {
        const struct sockaddr_in *pSockaddr4 = (const struct sockaddr_in *)pSockaddr;
        char addrBuf[INET_ADDRSTRLEN];
        
        if (inet_ntop(AF_INET, &pSockaddr4->sin_addr, addrBuf, (socklen_t)sizeof(addrBuf)) == NULL) {
            addrBuf[0] = '\0';
        }
        
        return [NSString stringWithCString:addrBuf encoding:NSASCIIStringEncoding];
    }
    
    if (pSockaddr->sa_family == AF_INET6) {
        const struct sockaddr_in6 *pSockaddr6 = (const struct sockaddr_in6 *)pSockaddr;
        char addrBuf[INET6_ADDRSTRLEN] = {0};
        
        if (inet_ntop(AF_INET6, &pSockaddr6->sin6_addr, addrBuf, (socklen_t)sizeof(addrBuf)) == NULL) {
            addrBuf[0] = '\0';
        }
        
        return [NSString stringWithCString:addrBuf encoding:NSASCIIStringEncoding];
    }
    
    return nil;
}

+ (uint16_t)portFromSockaddr:(const struct sockaddr *)pSockaddr
{
    if (pSockaddr->sa_family == AF_INET) {
        const struct sockaddr_in *pSockaddr4 = (const struct sockaddr_in *)pSockaddr;
        return ntohs(pSockaddr4->sin_port);
    }
    
    if (pSockaddr->sa_family == AF_INET6) {
        const struct sockaddr_in6 *pSockaddr6 = (const struct sockaddr_in6 *)pSockaddr;
        return ntohs(pSockaddr6->sin6_port);
    }
    
    return 0;
}

+ (NSString *)hostFromAddress:(NSData *)address
{
    NSString *host;
    
    if ([self getHost:&host port:NULL fromAddress:address])
        return host;
    else
        return nil;
}

+ (uint16_t)portFromAddress:(NSData *)address
{
    uint16_t port;
    
    if ([self getHost:NULL port:&port fromAddress:address])
        return port;
    else
        return 0;
}

+ (BOOL)isIPv4Address:(NSData *)address
{
    if ([address length] >= sizeof(struct sockaddr)) {
        const struct sockaddr *sockaddrX = [address bytes];
        
        if (sockaddrX->sa_family == AF_INET) {
            return YES;
        }
    }
    
    return NO;
}

+ (BOOL)isIPv6Address:(NSData *)address
{
    if ([address length] >= sizeof(struct sockaddr)) {
        const struct sockaddr *sockaddrX = [address bytes];
        
        if (sockaddrX->sa_family == AF_INET6) {
            return YES;
        }
    }
    
    return NO;
}

+ (BOOL)getHost:(NSString **)hostPtr port:(uint16_t *)portPtr fromAddress:(NSData *)address
{
    return [self getHost:hostPtr port:portPtr family:NULL fromAddress:address];
}

+ (BOOL)getHost:(NSString **)hostPtr port:(uint16_t *)portPtr family:(sa_family_t *)afPtr fromAddress:(NSData *)address
{
    if ([address length] >= sizeof(struct sockaddr)) {
        const struct sockaddr *sockaddrX = [address bytes];
        
        if (hostPtr) *hostPtr = [self hostFromSockaddr:sockaddrX];
        if (portPtr) *portPtr = [self portFromSockaddr:sockaddrX];
        if (afPtr)   *afPtr   = sockaddrX->sa_family;
        return YES;
    }
    
    return NO;
}

+ (NSData *)CRLFData
{
    return [NSData dataWithBytes:"\x0D\x0A" length:2];
}

+ (NSData *)CRData
{
    return [NSData dataWithBytes:"\x0D" length:1];
}

+ (NSData *)LFData
{
    return [NSData dataWithBytes:"\x0A" length:1];
}

+ (NSData *)ZeroData
{
    return [NSData dataWithBytes:"" length:1];
}

@end

static struct timeval get_timeval(NSTimeInterval interval)
{
    struct timeval tval;
    tval.tv_sec = (int)floor(interval);
    tval.tv_usec = (int)(1e6 * (interval - tval.tv_sec));
    return tval;
}

#if 0
static NSTimeInterval get_interval(struct timeval tv)
{
    NSTimeInterval interval = tv.tv_sec;
    return interval + 1e-6 * tv.tv_usec;
}
#endif

/**
 This method is adapted from section 16.3 in Unix Network Programming (2003) by Richard Stevens et al.
 See http://books.google.com/books?id=ptSC4LpwGA0C&lpg=PP1&pg=PA448
 */
static int connect_timeout(int sockfd, const struct sockaddr *address, socklen_t address_len, struct timeval * timeout, CoSocketLogHandler logDebug)
{
	int error = 0;
	
	// Connect should return immediately in the "in progress" state.
	int result = 0;
	if ((result = connect(sockfd, address, address_len)) < 0) {
        if (errno != EINPROGRESS) {
			return -1;
		}
	}
	
	// If connection completed immediately, skip waiting.
    if (result == 0) {
        if (logDebug) logDebug(@"Connection completed immediately, skip waiting");
		goto done;
	}
	
	// Call select() to wait for the connection.
    // NOTE: If timeout is zero, then pass NULL in order to use default timeout. Zero seconds indicates no waiting.
    fd_set rset, wset;
	FD_ZERO(&rset);
	FD_SET(sockfd, &rset);
	wset = rset;
    
    result = select(sockfd + 1, &rset, &wset, NULL, timeout);
    
    if (result==-1) {
        if (logDebug) logDebug(@"Socket select() failed");
        close(sockfd);
        return -1;
    }
    
	if (result == 0) {
		close(sockfd);
        errno = ETIMEDOUT;
        if (logDebug) logDebug(@"Socket connect timed out");
		return -1;
	}
	
	// Check whether the connection succeeded. If the socket is readable or writable, check for an error.
	if (FD_ISSET(sockfd, &rset) || FD_ISSET(sockfd, &wset)) {
		socklen_t len = sizeof(error);
        if (getsockopt(sockfd, SOL_SOCKET, SO_ERROR, &error, &len) != 0) {
            if (logDebug) logDebug(@"Failed to set socket option SO_ERROR");
			return -1;
		}
	}
	
done:
	// NOTE: On some systems, getsockopt() will fail and set errno. On others, it will succeed and set the error parameter.
    if (error) {
		close(sockfd);
		errno = error;
		return -1;
    }
    
    if (logDebug) logDebug(@"Socket is connected successfully");
	return 0;
}
