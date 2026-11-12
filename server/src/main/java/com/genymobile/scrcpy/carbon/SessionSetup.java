package com.genymobile.scrcpy.carbon;

import android.net.LocalSocket;
import android.util.Base64;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileDescriptor;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.util.Locale;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * Per-session parameters the Mac sends on the adb shell's stdin (never in argv, never in a file):
 * {@code CM1 <plain|tls> <secret: 64 hex> <mac-ca: base64 DER | -> <device-key: 64 hex | ->}. In TLS mode the
 * server pins the Mac's identity CA on first use, creates a fresh session identity and prints
 * {@code CM-PIN <hex> [<proof hex>]} on stdout (the adb channel) for the Mac to pin. Every socket must then
 * present the 32-byte session secret before any data flows.
 * <p>The device key arrives only over USB and is kept in a shell-only file. adb does not authenticate the
 * phone to the Mac, so on wireless sessions the proof, HMAC-SHA-256(device key, session pin), is what shows
 * the Mac that this is the phone it was plugged into and not another device on the network.
 */
public final class SessionSetup {

    public static final String MAC_PIN_PATH = "/data/local/tmp/carbonmirror-mac.pin";
    private static final String DEVICE_KEY_PATH = "/data/local/tmp/carbonmirror-device.key";
    private static final int MAX_LINE = 8192;
    private static final int SECRET_LEN = 32;

    private final boolean tls;
    private final byte[] secret;
    private final long identity;

    private SessionSetup(boolean tls, byte[] secret, long identity) {
        this.tls = tls;
        this.secret = secret;
        this.identity = identity;
    }

    /** Reads and validates the setup line; in TLS mode prepares the session identity. */
    public static SessionSetup read() throws IOException {
        String[] fields = readLine(System.in).split(" ");
        if (fields.length != 5 || !"CM1".equals(fields[0])) {
            throw new IOException("Malformed session setup");
        }
        boolean tls;
        if ("tls".equals(fields[1])) {
            tls = true;
        } else if ("plain".equals(fields[1])) {
            tls = false;
        } else {
            throw new IOException("Unknown session mode");
        }
        byte[] secret = hex(fields[2]);
        if (secret.length != SECRET_LEN) {
            throw new IOException("Bad session secret");
        }
        byte[] deviceKey = deviceKey(fields[4]);
        if (!tls) {
            return new SessionSetup(false, secret, 0);
        }
        CarbonCore.load();
        byte[] macCa = Base64.decode(fields[3], Base64.NO_WRAP);
        checkMacPin(macCa);
        long identity = CarbonCore.serverIdentityNew(macCa);
        if (identity <= 0) {
            throw new IOException("TLS identity could not be created");
        }
        byte[] pin = new byte[32];
        CarbonCore.check(CarbonCore.identityPin(identity, pin));
        PrintStream out = new PrintStream(new FileOutputStream(FileDescriptor.out), true);
        out.print("CM-PIN " + hex(pin) + (deviceKey == null ? "" : " " + hex(hmac(deviceKey, pin))) + "\n");
        return new SessionSetup(true, secret, identity);
    }

    /** Wraps an accepted socket, runs TLS if enabled and checks the session secret. */
    public SecureChannel accept(LocalSocket socket) throws IOException {
        SecureChannel channel = tls ? SecureChannel.tls(socket, identity) : SecureChannel.plain(socket);
        byte[] presented = new byte[SECRET_LEN];
        InputStream in = channel.getInputStream();
        socket.setSoTimeout(SecureChannel.HANDSHAKE_TIMEOUT_MS);
        int read = 0;
        while (read < SECRET_LEN) {
            int n = in.read(presented, read, SECRET_LEN - read);
            if (n < 0) {
                channel.close();
                throw new IOException("Connection closed before the session secret");
            }
            read += n;
        }
        if (!MessageDigest.isEqual(presented, secret)) {
            channel.close();
            throw new IOException("Wrong session secret");
        }
        socket.setSoTimeout(0);
        return channel;
    }

    /** Frees the TLS identity (sessions already created keep working). */
    public void release() {
        if (identity > 0) {
            CarbonCore.identityFree(identity);
        }
    }

    /** First use pins the Mac CA; afterwards a different CA is refused ("identity changed"). */
    private static void checkMacPin(byte[] macCa) throws IOException {
        byte[] digest = new byte[32];
        CarbonCore.check(CarbonCore.sha256(macCa, digest));
        File pinFile = new File(MAC_PIN_PATH);
        if (pinFile.exists()) {
            byte[] stored = hex(readLine(new FileInputStream(pinFile)));
            if (!CarbonCore.constantTimeEquals(stored, digest)) {
                PrintStream out = new PrintStream(new FileOutputStream(FileDescriptor.out), true);
                out.print("CM-ERROR identity-changed\n");
                throw new IOException("Mac identity changed");
            }
            return;
        }
        writePrivate(pinFile, digest);
    }

    /** Stores the device key when the Mac sends one (USB only); otherwise returns the stored key, or null. */
    private static byte[] deviceKey(String field) throws IOException {
        File keyFile = new File(DEVICE_KEY_PATH);
        if (!"-".equals(field)) {
            byte[] key = hex(field);
            if (key.length != SECRET_LEN) {
                throw new IOException("Bad device key");
            }
            writePrivate(keyFile, key);
            return key;
        }
        if (!keyFile.exists()) {
            return null;
        }
        byte[] key = hex(readLine(new FileInputStream(keyFile)));
        return key.length == SECRET_LEN ? key : null;
    }

    /** Writes {@code bytes} as one hex line, readable and writable by the shell user only. */
    private static void writePrivate(File file, byte[] bytes) throws IOException {
        if (!file.delete() && file.exists()) {
            throw new IOException("Could not replace " + file.getName());
        }
        if (!file.createNewFile() || !file.setReadable(false, false) || !file.setWritable(false, false)
                || !file.setReadable(true, true) || !file.setWritable(true, true)) {
            throw new IOException("Could not restrict " + file.getName());
        }
        try (FileOutputStream fos = new FileOutputStream(file)) {
            fos.write((hex(bytes) + "\n").getBytes(StandardCharsets.US_ASCII));
        }
    }

    private static byte[] hmac(byte[] key, byte[] data) throws IOException {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(key, "HmacSHA256"));
            return mac.doFinal(data);
        } catch (GeneralSecurityException e) {
            throw new IOException("HMAC unavailable", e);
        }
    }

    private static String readLine(InputStream in) throws IOException {
        ByteArrayOutputStream line = new ByteArrayOutputStream();
        while (true) {
            int b = in.read();
            if (b < 0 || b == '\n') {
                break;
            }
            if (line.size() >= MAX_LINE) {
                throw new IOException("Setup line too long");
            }
            line.write(b);
        }
        return line.toString("US-ASCII").trim();
    }

    private static byte[] hex(String s) throws IOException {
        if (s.length() % 2 != 0) {
            throw new IOException("Bad hex");
        }
        byte[] out = new byte[s.length() / 2];
        for (int i = 0; i < out.length; ++i) {
            int hi = Character.digit(s.charAt(2 * i), 16);
            int lo = Character.digit(s.charAt(2 * i + 1), 16);
            if (hi < 0 || lo < 0) {
                throw new IOException("Bad hex");
            }
            out[i] = (byte) ((hi << 4) | lo);
        }
        return out;
    }

    private static String hex(byte[] bytes) {
        StringBuilder sb = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) {
            sb.append(String.format(Locale.ROOT, "%02x", b & 0xff));
        }
        return sb.toString();
    }
}
