CoSocket
===============

This project is originally forked from [FastSocket](http://github.com/dreese/fast-socket), and later influenced by [GCDAsyncSocket](https://github.com/robbiehanson/CocoaAsyncSocket).

Description
---------------

A fast, synchronous Objective-C wrapper around BSD sockets for iOS and OS X.
Send and receive raw bytes over a socket as fast as possible.

Use this class if fast network communication is what you need. If you want to
do something else while your network operations finish, then an asynchronous
API might be better.

Download
---------------

Examples
---------------

Create and connect a client socket.

	CoSocket *client = [[CoSocket alloc] init];
	BOOL result = [client connectToHost:@"localhost" onPort:34567 withTimeout:10.0 error:nil];

Send a string.

	NSData *data = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
	result = [client writeData:data error:nil];

Receive a string.

	NSData *data = [client readDataToLength:expectedLength error:nil];
	NSString *received = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

Send raw bytes.

	char rawData[] = {42};
	NSData *data = [NSData dataWithBytes:rawData length:42];
	long sent = [client writeData:data error:nil];

Reads bytes until (and including) a separator encountered.

	NSData *data = [client readDataToData:[CoSocket CRLFData] error:nil];

Close the connection.

	[client disconnect];

Please check out the unit tests for more examples of how to use these classes.

License
---------------

CoSocket is available under the [MIT license](http://opensource.org/licenses/MIT).
