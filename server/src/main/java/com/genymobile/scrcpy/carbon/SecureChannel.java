package com.genymobile.scrcpy.carbon;

import android.net.LocalSocket;

import java.io.Closeable;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

/**
 * One accepted socket, either plaintext (USB, "Encrypt over USB" off) or wrapped in the inner TLS 1.3
 * session from libcarbon_core.so. Native calls are serialised by {@code lock}; ciphertext is written under
 * {@code sendLock} so records leave in order even when the reader thread flushes key updates.
 */
public final class SecureChannel implements Closeable {

    private static final int HANDSHAKE_TIMEOUT_MS = 10_000;
    private static final int BUFFER = 64 * 1024;

    private final LocalSocket socket;
    private final InputStream rawIn;
    private final OutputStream rawOut;
    private final long session;
    private final Object lock = new Object();
    private final Object sendLock = new Object();
    private final byte[] outBuf = new byte[BUFFER];
    private final InputStream in;
    private final OutputStream out;
    private boolean closed;
    private boolean freed;

    private SecureChannel(LocalSocket socket, long session) throws IOException {
        this.socket = socket;
        this.rawIn = socket.getInputStream();
        this.rawOut = socket.getOutputStream();
        this.session = session;
        this.in = session == 0 ? rawIn : new TlsInput();
        this.out = session == 0 ? rawOut : new TlsOutput();
    }

    public static SecureChannel plain(LocalSocket socket) throws IOException {
        return new SecureChannel(socket, 0);
    }

    public static SecureChannel tls(LocalSocket socket, long identity) throws IOException {
        long session = CarbonCore.sessionNew(identity);
        if (session <= 0) {
            socket.close();
            throw new IOException("TLS session could not be created");
        }
        SecureChannel channel = new SecureChannel(socket, session);
        try {
            channel.handshake();
        } catch (IOException e) {
            channel.close();
            throw e;
        }
        return channel;
    }

    private void handshake() throws IOException {
        socket.setSoTimeout(HANDSHAKE_TIMEOUT_MS);
        byte[] buf = new byte[BUFFER];
        while (true) {
            flush();
            int status;
            synchronized (lock) {
                ensureLive();
                status = CarbonCore.check(CarbonCore.status(session));
            }
            if ((status & CarbonCore.STATUS_HANDSHAKING) == 0) {
                break;
            }
            int n = rawIn.read(buf);
            if (n < 0) {
                throw new IOException("Connection closed during the TLS handshake");
            }
            synchronized (lock) {
                ensureLive();
                CarbonCore.check(CarbonCore.readTls(session, buf, 0, n));
            }
        }
        flush();
        socket.setSoTimeout(0);
    }

    /** Throws once the native session is gone; call with {@code lock} held. */
    private void ensureLive() throws IOException {
        if (freed) {
            throw new IOException("Channel closed");
        }
    }

    /** Sends every pending TLS record. */
    private void flush() throws IOException {
        synchronized (sendLock) {
            while (true) {
                int n;
                synchronized (lock) {
                    ensureLive();
                    n = CarbonCore.check(CarbonCore.writeTls(session, outBuf, 0, outBuf.length));
                }
                if (n == 0) {
                    break;
                }
                rawOut.write(outBuf, 0, n);
            }
            rawOut.flush();
        }
    }

    public InputStream getInputStream() {
        return in;
    }

    public OutputStream getOutputStream() {
        return out;
    }

    public LocalSocket getSocket() {
        return socket;
    }

    public void shutdown() throws IOException {
        socket.shutdownInput();
        socket.shutdownOutput();
    }

    @Override
    public void close() throws IOException {
        synchronized (lock) {
            if (closed) {
                return;
            }
            closed = true;
        }
        try {
            if (session != 0) {
                synchronized (lock) {
                    CarbonCore.close(session);
                }
                flush();
            }
        } catch (IOException e) {
            // the peer may already be gone
        } finally {
            if (session != 0) {
                synchronized (lock) {
                    CarbonCore.sessionFree(session);
                    freed = true;
                }
            }
            socket.close();
        }
    }

    private final class TlsInput extends InputStream {
        private final byte[] cipher = new byte[BUFFER];

        @Override
        public int read() throws IOException {
            byte[] one = new byte[1];
            int n = read(one, 0, 1);
            return n < 0 ? -1 : one[0] & 0xff;
        }

        @Override
        public int read(byte[] b, int off, int len) throws IOException {
            if (len == 0) {
                return 0;
            }
            while (true) {
                int n;
                synchronized (lock) {
                    if (closed || freed) {
                        return -1;
                    }
                    n = CarbonCore.readPlain(session, b, off, len);
                }
                if (n == -CarbonCore.STATUS_TLS_CLOSED) {
                    return -1;
                }
                if (CarbonCore.check(n) > 0) {
                    return n;
                }
                int c = rawIn.read(cipher);
                if (c < 0) {
                    return -1;
                }
                synchronized (lock) {
                    ensureLive();
                    CarbonCore.check(CarbonCore.readTls(session, cipher, 0, c));
                }
                flush();
            }
        }
    }

    private final class TlsOutput extends OutputStream {
        @Override
        public void write(int b) throws IOException {
            write(new byte[] {(byte) b}, 0, 1);
        }

        @Override
        public void write(byte[] b, int off, int len) throws IOException {
            int done = 0;
            while (done < len) {
                int n;
                synchronized (lock) {
                    ensureLive();
                    n = CarbonCore.check(CarbonCore.writePlain(session, b, off + done, len - done));
                }
                flush();
                if (n == 0) {
                    throw new IOException("TLS write made no progress");
                }
                done += n;
            }
        }
    }
}
