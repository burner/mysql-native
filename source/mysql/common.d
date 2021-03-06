﻿module mysql.common;

import std.algorithm;
import std.conv;
import std.datetime;
import std.digest.sha;
import std.exception;
import std.range;
import std.socket;
import std.stdio;
import std.string;
import std.traits;
import std.variant;

version(Have_vibe_d)
{
    static if(__traits(compiles, (){ import vibe.core.net; } ))
        import vibe.core.net;
    else
        static assert(false, "mysql-native can't find Vibe.d's 'vibe.core.net'.");
}

/**
 * An exception type to distinguish exceptions thrown by this module.
 */
class MySQLException: Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__) pure
    {
        super(msg, file, line);
    }
}
alias MySQLException MYX;

/**
 * Received invalid data from the server which violates the MySQL network protocol.
 */
class MySQLProtocolException: MySQLException
{
    this(string msg, string file, size_t line) pure
    {
        super(msg, file, line);
    }
}
alias MySQLProtocolException MYXProtocol;

// Phobos/Vibe.d type aliases
package alias std.socket.TcpSocket PlainPhobosSocket;
version(Have_vibe_d)
{
    package alias vibe.core.net.TCPConnection PlainVibeDSocket;
}
else
{
    // Dummy types
    package alias Object PlainVibeDSocket;
}

alias PlainPhobosSocket function(string,ushort) OpenSocketCallbackPhobos;
alias PlainVibeDSocket  function(string,ushort) OpenSocketCallbackVibeD;

enum MySQLSocketType { phobos, vibed }

// A minimal socket interface similar to Vibe.d's TCPConnection.
// Used to wrap both Phobos and Vibe.d sockets with a common interface.
package interface MySQLSocket
{
    void close();
    @property bool connected() const;
    void read(ubyte[] dst);
    void write(in ubyte[] bytes);

    void acquire();
    void release();
    bool isOwner();
    bool amOwner();
}

// Wraps a Phobos socket with the common interface
package class MySQLSocketPhobos : MySQLSocket
{
    private PlainPhobosSocket socket;

    // The socket should already be open
    this(PlainPhobosSocket socket)
    {
        enforceEx!MYX(socket, "Tried to use a null Phobos socket - Maybe the 'openSocket' callback returned null?");
        enforceEx!MYX(socket.isAlive, "Tried to use a closed Phobos socket - Maybe the 'openSocket' callback created a socket but forgot to open it?");
        this.socket = socket;
    }

    invariant()
    {
        assert(!!socket);
    }

    void close()
    {
        socket.shutdown(SocketShutdown.BOTH);
        socket.close();
    }

    @property bool connected() const
    {
        return socket.isAlive;
    }

    void read(ubyte[] dst)
    {
        // Note: I'm a little uncomfortable with this line as it doesn't
        // (and can't) update Connection._open. Not sure what can be done,
        // but perhaps Connection._open should be eliminated in favor of
        // querying the socket's opened/closed state directly.
        scope(failure) socket.close();

        auto bytesRead = socket.receive(dst);
        enforceEx!MYX(bytesRead == dst.length, "Wrong number of bytes read");
        enforceEx!MYX(bytesRead != socket.ERROR, "Received std.socket.Socket.ERROR");
    }

    void write(in ubyte[] bytes)
    {
        socket.send(bytes);
    }

    void acquire() { /+ Do nothing +/ }
    void release() { /+ Do nothing +/ }
    bool isOwner() { return true; }
    bool amOwner() { return true; }
}

// Wraps a Vibe.d socket with the common interface
version(Have_vibe_d) {
    package class MySQLSocketVibeD : MySQLSocket
    {
        private PlainVibeDSocket socket;

        // The socket should already be open
        this(PlainVibeDSocket socket)
        {
            enforceEx!MYX(socket, "Tried to use a null Vibe.d socket - Maybe the 'openSocket' callback returned null?");
            enforceEx!MYX(socket.connected, "Tried to use a closed Vibe.d socket - Maybe the 'openSocket' callback created a socket but forgot to open it?");
            this.socket = socket;
        }

        invariant()
        {
            assert(!!socket);
        }

        void close()
        {
            socket.close();
        }

        @property bool connected() const
        {
            return socket.connected;
        }

        void read(ubyte[] dst)
        {
            socket.read(dst);
        }

        void write(in ubyte[] bytes)
        {
            socket.write(bytes);
        }

        static if (is(typeof(&TCPConnection.isOwner))) {
            void acquire() { socket.acquire(); }
            void release() { socket.release(); }
            bool isOwner() { return socket.isOwner(); }
            bool amOwner() { return socket.isOwner(); }
        } else {
            void acquire() { /+ Do nothing +/ }
            void release() { /+ Do nothing +/ }
            bool isOwner() { return true; }
            bool amOwner() { return true; }
        }
    }
}
