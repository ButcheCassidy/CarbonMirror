// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
package com.genymobile.scrcpy.carbon;

import java.io.File;
import java.io.IOException;

/**
 * JNI bridge to libcarbon_core.so (the same Rust core the Mac links). All TLS state lives in Rust; Java only
 * moves bytes. Negative return values are negated CarbonMirror status codes.
 */
public final class CarbonCore {

    public static final String LIBRARY_PATH = "/data/local/tmp/libcarbon_core.so";
    /** C ABI version this server was written against. */
    public static final int ABI_VERSION = 2;
    /** Status codes used by the Java side. */
    public static final int STATUS_TLS_CLOSED = 83;
    public static final int STATUS_HANDSHAKING = 1;
    public static final int STATUS_WANTS_WRITE = 2;

    private static boolean loaded;

    private CarbonCore() {
        // not instantiable
    }

    /** Loads the pushed library once, then deletes the file so nothing else can load or replace it. */
    public static synchronized void load() throws IOException {
        if (loaded) {
            return;
        }
        try {
            System.load(LIBRARY_PATH);
        } catch (UnsatisfiedLinkError e) {
            throw new IOException("libcarbon_core.so could not be loaded", e);
        } finally {
            if (!new File(LIBRARY_PATH).delete()) {
                com.genymobile.scrcpy.util.Ln.w("Could not delete " + LIBRARY_PATH);
            }
        }
        if (abiVersion() != ABI_VERSION) {
            throw new IOException("libcarbon_core.so ABI mismatch");
        }
        loaded = true;
    }

    /** Throws for a negative native result, returns it otherwise. */
    public static int check(int result) throws IOException {
        if (result < 0) {
            throw new IOException("carbon-core status " + (-result));
        }
        return result;
    }

    public static native int abiVersion();

    public static native long serverIdentityNew(byte[] macCaDer);

    public static native int identityPin(long identity, byte[] out32);

    public static native void identityFree(long identity);

    public static native long sessionNew(long identity);

    public static native int readTls(long session, byte[] buf, int off, int len);

    public static native int writeTls(long session, byte[] out, int off, int len);

    public static native int readPlain(long session, byte[] out, int off, int len);

    public static native int writePlain(long session, byte[] buf, int off, int len);

    public static native int status(long session);

    public static native int negotiated(long session);

    public static native int close(long session);

    public static native void sessionFree(long session);

    public static native int sha256(byte[] data, byte[] out32);

    public static native boolean constantTimeEquals(byte[] a, byte[] b);
}
