package com.genymobile.scrcpy.device;

import com.genymobile.scrcpy.carbon.SecureChannel;
import com.genymobile.scrcpy.carbon.SessionSetup;
import com.genymobile.scrcpy.control.ControlChannel;
import com.genymobile.scrcpy.util.StringUtils;

import android.net.LocalServerSocket;
import android.net.LocalSocket;

import java.io.Closeable;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;

/**
 * The two sockets the Mac reaches through {@code adb forward}: video first, then control. Each is wrapped by
 * {@link SessionSetup#accept} (inner TLS when enabled) and must present the session secret before anything
 * is sent; a socket that fails is closed and the server stops.
 */
public final class DesktopConnection implements Closeable {

    private static final int DEVICE_NAME_FIELD_LENGTH = 64;

    private static final String SOCKET_NAME_PREFIX = "scrcpy";

    private final SecureChannel video;
    private final SecureChannel control;
    private final ControlChannel controlChannel;

    private DesktopConnection(SecureChannel video, SecureChannel control) {
        this.video = video;
        this.control = control;
        controlChannel = new ControlChannel(control.getInputStream(), control.getOutputStream());
    }

    private static String getSocketName(int scid) {
        return SOCKET_NAME_PREFIX + String.format("_%08x", scid);
    }

    public static DesktopConnection open(int scid, boolean sendDummyByte, SessionSetup setup) throws IOException {
        SecureChannel video = null;
        try (LocalServerSocket localServerSocket = new LocalServerSocket(getSocketName(scid))) {
            LocalSocket videoSocket = localServerSocket.accept();
            video = setup.accept(videoSocket);
            if (sendDummyByte) {
                // send one byte so the client may read() to detect a connection error
                video.getOutputStream().write(0);
            }
            LocalSocket controlSocket = localServerSocket.accept();
            SecureChannel control = setup.accept(controlSocket);
            return new DesktopConnection(video, control);
        } catch (IOException | RuntimeException e) {
            if (video != null) {
                video.close();
            }
            throw e;
        }
    }

    public void shutdown() throws IOException {
        video.shutdown();
        control.shutdown();
    }

    @Override
    public void close() throws IOException {
        video.close();
        control.close();
    }

    public void sendDeviceMeta(String deviceName) throws IOException {
        byte[] buffer = new byte[DEVICE_NAME_FIELD_LENGTH];

        byte[] deviceNameBytes = deviceName.getBytes(StandardCharsets.UTF_8);
        int len = StringUtils.getUtf8TruncationIndex(deviceNameBytes, DEVICE_NAME_FIELD_LENGTH - 1);
        System.arraycopy(deviceNameBytes, 0, buffer, 0, len);
        // byte[] are always 0-initialized in java, no need to set '\0' explicitly

        video.getOutputStream().write(buffer, 0, buffer.length);
    }

    public OutputStream getVideoOutput() {
        return video.getOutputStream();
    }

    public ControlChannel getControlChannel() {
        return controlChannel;
    }
}
