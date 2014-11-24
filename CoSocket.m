//
//  CoSocket.m
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
#include <netdb.h>
#include <netinet/tcp.h>
#include <unistd.h>

#define CoTCPSocketBufferSize 65536

static struct timeval get_timeval(NSTimeInterval interval);

static int connect_timeout(int sockfd, const struct sockaddr *address, socklen_t address_len, struct timeval timeout);


@interface CoSocket () {
@protected
	void *_buffer;
	long _size;
    struct timeval _timeout;
}
@end


@implementation CoSocket


- (instancetype)initWithHost:(NSString *)host onPort:(uint16_t)port
{
    return [self initWithHost:host onPort:port timeout:75.0];
}

- (instancetype)initWithHost:(NSString *)host onPort:(uint16_t)port timeout:(NSTimeInterval)timeout
{
	if ((self = [super init])) {
		_sockfd = 0;
		_host = [host copy];
		_port = port;
		_size = getpagesize() * 1448 / 4;
		_buffer = valloc(_size);
        _timeout = get_timeval(timeout);
	}
	return self;
}

- (instancetype)initWithFileDescriptor:(int)fd
{
    return [self initWithFileDescriptor:fd timeout:75.0];
}

- (instancetype)initWithFileDescriptor:(int)fd timeout:(NSTimeInterval)timeout
{
	if ((self = [super init])) {
		// Assume the descriptor is an already connected socket.
		_sockfd = fd;
		_size = getpagesize() * 1448 / 4;
        _buffer = valloc(_size);
        _timeout = get_timeval(timeout);
		
		// Instead of receiving a SIGPIPE signal, have write() return an error.
		if (setsockopt(_sockfd, SOL_SOCKET, SO_NOSIGPIPE, &(int){1}, sizeof(int)) < 0) {
			_lastError = NEW_ERROR(errno, strerror(errno));
			return NO;
		}
		
		// Disable Nagle's algorithm.
		if (setsockopt(_sockfd, IPPROTO_TCP, TCP_NODELAY, &(int){1}, sizeof(int)) < 0) {
			_lastError = NEW_ERROR(errno, strerror(errno));
			return NO;
		}
		
		// Increase receive buffer size.
		if (setsockopt(_sockfd, SOL_SOCKET, SO_RCVBUF, &_size, sizeof(_size)) < 0) {
			// Ignore this because some systems have small hard limits.
		}
	}
	return self;
}

- (void)buffer:(void **)outBuf size:(long *)outSize {
	if (outBuf && outSize) {
		*outBuf = _buffer;
		*outSize = _size;
	}
}

- (void)dealloc {
	[self close];
	free(_buffer);
}

#pragma mark Actions

- (BOOL)connect
{
	// Construct server address information.
	struct addrinfo hints, *serverinfo, *p;
	
	bzero(&hints, sizeof(hints));
	hints.ai_family = AF_UNSPEC;
	hints.ai_socktype = SOCK_STREAM;
	
	int error = getaddrinfo(_host.UTF8String, @(_port).stringValue.UTF8String, &hints, &serverinfo);
	if (error) {
		_lastError = NEW_ERROR(error, gai_strerror(error));
		return NO;
	}
	
	// Loop through the results and connect to the first we can.
	@try {
		for (p = serverinfo; p != NULL; p = p->ai_next) {
			if ((_sockfd = socket(p->ai_family, p->ai_socktype, p->ai_protocol)) < 0) {
                _lastError = NEW_ERROR(errno, strerror(errno));
                [self close];
				return NO;
			}
			
			// Instead of receiving a SIGPIPE signal, have write() return an error.
			if (setsockopt(_sockfd, SOL_SOCKET, SO_NOSIGPIPE, &(int){1}, sizeof(int)) < 0) {
                _lastError = NEW_ERROR(errno, strerror(errno));
                [self close];
				return NO;
            }
			
			// Disable Nagle's algorithm.
			if (setsockopt(_sockfd, IPPROTO_TCP, TCP_NODELAY, &(int){1}, sizeof(int)) < 0) {
                _lastError = NEW_ERROR(errno, strerror(errno));
                [self close];
				return NO;
			}
			
			// Increase receive buffer size.
			if (setsockopt(_sockfd, SOL_SOCKET, SO_RCVBUF, &_size, sizeof(_size)) < 0) {
				// Ignore this because some systems have small hard limits.
			}
            
            // Get current flags to restore after.
            int flags = fcntl(_sockfd, F_GETFL, 0);
            
            // Set socket to non-blocking.
            fcntl(_sockfd, F_SETFL, flags | O_NONBLOCK);
			
            // Connect the socket using the given timeout.
            if (connect_timeout(_sockfd, p->ai_addr, p->ai_addrlen, _timeout) < 0) {
                _lastError = NEW_ERROR(errno, strerror(errno));
                continue;
            }
			
			// Found a working address, so move on.
			break;
		}
        
		if (p == NULL) {
            _lastError = NEW_ERROR(1, "Could not contact server");
            [self close];
			return NO;
		}
	}
	@finally {
		freeaddrinfo(serverinfo);
	}
	return YES;
}

- (BOOL)isConnected {
	if (_sockfd == 0) {
		return NO;
	}
	
	struct sockaddr remoteAddr;
	if (getpeername(_sockfd, &remoteAddr, &(socklen_t){sizeof(remoteAddr)}) < 0) {
		_lastError = NEW_ERROR(errno, strerror(errno));
		return NO;
	}
	return YES;
}

- (BOOL)close {
	if (_sockfd > 0 && close(_sockfd) < 0) {
		// _lastError = NEW_ERROR(errno, strerror(errno));
        _sockfd = 0;
		return NO;
	}
    
	_sockfd = 0;
	return YES;
}

- (BOOL)writeData:(NSData *)theData
{
    fd_set writemask;
    
    if (theData.length <= 0) {
        _lastError = NEW_ERROR(0, "Socket write data length must bigger than zero");
        [self close];
        return NO;
    }
    
    const char * dataBytes = theData.bytes;
    ssize_t index = 0;
    
    while (index < theData.length) {
        /* We must set all this information on each select we do */
        FD_ZERO(&writemask);   /* empty readmask */
        
        /* Then we put all the descriptors we want to wait for in a */
        /* mask = writemask */
        FD_SET(_sockfd, &writemask);
        
        /* The first parameter is the biggest descriptor+1. The first one
         was 0, so every other descriptor will be bigger.*/
        /* readfds = we are not waiting for readfds */
        /* writefds = &writemask */
        /* exceptfds = we are not waiting for exception fds */
        if (select(_sockfd+1, NULL, &writemask, NULL, &_timeout)==-1) {
            _lastError = NEW_ERROR(errno, strerror(errno));
            [self close];
            return NO;
        }
        
        
        /* If something was received */
        if (FD_ISSET(_sockfd, &writemask)) {
            ssize_t toWrite = MIN((theData.length - index), _size);
            
            ssize_t wrote = send(_sockfd, &dataBytes[index], toWrite, 0);
            
            if (wrote == 0) {
                // socket has been closed or shutdown for send
                _lastError = NEW_ERROR(0, "Peer has closed the socket");
                [self close];
                return NO;
            }
            
            if (wrote < 0) {
                _lastError = NEW_ERROR(errno, strerror(errno));
                [self close];
                return NO;
            }
            
            index += wrote;
        }
    }
    
    return YES;
}

- (NSData *)readDataToLength:(NSUInteger)length
{
    fd_set readmask;
    
    if (length == 0) {
        _lastError = NEW_ERROR(0, "Socket read length must bigger than zero");
        [self close];
        return nil;
    }
    
    ssize_t hasRead = 0;
    while (hasRead < length) {
        /* We must set all this information on each select we do */
        FD_ZERO(&readmask);   /* empty readmask */
        
        /* Then we put all the descriptors we want to wait for in a */
        /* mask = readmask */
        FD_SET(_sockfd, &readmask);
        
        /* The first parameter is the biggest descriptor+1. The first one
         was 0, so every other descriptor will be bigger.*/
        /* readfds = &readmask */
        /* writefds = we are not waiting for writefds */
        /* exceptfds = we are not waiting for exception fds */
        if (select(_sockfd+1, &readmask, NULL, NULL, &_timeout)==-1) {
            _lastError = NEW_ERROR(errno, strerror(errno));
            [self close];
            return nil;
        }
        
        /* If something was received */
        if (FD_ISSET(_sockfd, &readmask)) {
            ssize_t toRead = MIN( (length - hasRead), _size);
            
            ssize_t justRead = recv(_sockfd, &_buffer[hasRead], toRead, 0);
            
            if (justRead == 0) {
                // socket has been closed or shutdown for send
                _lastError = NEW_ERROR(0, "Peer has closed the socket");
                [self close];
                return nil;
            }
            
            if (justRead < 0) {
                _lastError = NEW_ERROR(errno, strerror(errno));
                [self close];
                return nil;
            }
            
            hasRead += justRead;
        }
    }
    
    NSData * theData = [NSData dataWithBytes:_buffer length:hasRead];
    return theData;
}

#pragma mark Settings

- (NSTimeInterval)timeout {
    NSTimeInterval to = 0.0;
    
	if (_sockfd > 0) {
		struct timeval tv;
		if (getsockopt(_sockfd, SOL_SOCKET, SO_RCVTIMEO, &tv, &(socklen_t){sizeof(tv)}) < 0) {
			_lastError = NEW_ERROR(errno, strerror(errno));
			return NO;
		}
        
		to = tv.tv_sec + 1e-6 * tv.tv_usec;
	}
    
	return to;
}

- (BOOL)setTimeout:(NSTimeInterval)seconds {
	if (_sockfd > 0) {
		struct timeval tv = get_timeval(seconds);
		if (setsockopt(_sockfd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv)) < 0 || setsockopt(_sockfd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv)) < 0) {
			_lastError = NEW_ERROR(errno, strerror(errno));
			return NO;
		}
	}
    
	return YES;
}

- (int)segmentSize {
    int bytes = 0;
    
	if (_sockfd > 0 && getsockopt(_sockfd, IPPROTO_TCP, TCP_MAXSEG, &bytes, &(socklen_t){sizeof(bytes)}) < 0) {
		_lastError = NEW_ERROR(errno, strerror(errno));
		return -1;
	}
    
	return bytes;
}

- (BOOL)setSegmentSize:(int)bytes {
	if (_sockfd > 0 && setsockopt(_sockfd, IPPROTO_TCP, TCP_MAXSEG, &bytes, sizeof(bytes)) < 0) {
		_lastError = NEW_ERROR(errno, strerror(errno));
		return NO;
	}

	return YES;
}

@end

static struct timeval get_timeval(NSTimeInterval interval)
{
    struct timeval tval;
    tval.tv_sec = (int)floor(interval);
    tval.tv_usec = (int)(1e6 * (interval - tval.tv_sec));
    return tval;
}

/**
 This method is adapted from section 16.3 in Unix Network Programming (2003) by Richard Stevens et al.
 See http://books.google.com/books?id=ptSC4LpwGA0C&lpg=PP1&pg=PA448
 */
static int connect_timeout(int sockfd, const struct sockaddr *address, socklen_t address_len, struct timeval timeout)
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
		goto done;
	}
	
	// Call select() to wait for the connection.
    // NOTE: If timeout is zero, then pass NULL in order to use default timeout. Zero seconds indicates no waiting.
    fd_set rset, wset;
	FD_ZERO(&rset);
	FD_SET(sockfd, &rset);
	wset = rset;
    
	if ((result = select(sockfd + 1, &rset, &wset, NULL, &timeout)) == 0) {
		close(sockfd);
		errno = ETIMEDOUT;
		return -1;
	}
	
	// Check whether the connection succeeded. If the socket is readable or writable, check for an error.
	if (FD_ISSET(sockfd, &rset) || FD_ISSET(sockfd, &wset)) {
		socklen_t len = sizeof(error);
		if (getsockopt(sockfd, SOL_SOCKET, SO_ERROR, &error, &len) < 0) {
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
	return 0;
}
