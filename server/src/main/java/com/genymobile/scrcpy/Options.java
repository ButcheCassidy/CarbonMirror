package com.genymobile.scrcpy;

import com.genymobile.scrcpy.model.CodecOption;
import com.genymobile.scrcpy.model.Orientation;
import com.genymobile.scrcpy.util.Ln;
import com.genymobile.scrcpy.video.VideoCodec;

import android.graphics.Rect;

import java.util.List;
import java.util.Locale;

/**
 * Server options, CarbonMirror fork. Only the keys the Mac app sends are accepted, and the keys that would
 * re-enable removed features (audio, camera, virtual displays, other displays, reverse tunnels) are accepted
 * only with their "off" value. Anything else stops the server before it opens a socket.
 */
public class Options {

    /** Largest accepted video bit rate (bit/s). */
    private static final int MAX_VIDEO_BIT_RATE = 100_000_000;
    /** Largest accepted frame-rate cap. */
    private static final float MAX_FPS_LIMIT = 240f;
    /** Largest accepted long side, pixels. */
    private static final int MAX_SIZE_LIMIT = 4096;

    private Ln.Level logLevel = Ln.Level.INFO;
    private int scid = -1;
    private int maxSize;
    private VideoCodec videoCodec = VideoCodec.H264;
    private int videoBitRate = 8_000_000;
    private float maxFps;
    private boolean stayAwake;
    private boolean clipboardAutosync = true;
    private boolean cleanup = true;
    private boolean powerOn = true;

    private boolean sendDeviceMeta = true;
    private boolean sendFrameMeta = true;
    private boolean sendDummyByte = true;
    private boolean sendStreamMeta = true;

    public Ln.Level getLogLevel() {
        return logLevel;
    }

    public int getScid() {
        return scid;
    }

    public int getMaxSize() {
        return maxSize;
    }

    public int getMinSizeAlignment() {
        return 1;
    }

    public VideoCodec getVideoCodec() {
        return videoCodec;
    }

    public int getVideoBitRate() {
        return videoBitRate;
    }

    public float getMaxFps() {
        return maxFps;
    }

    public float getAngle() {
        return 0;
    }

    public Rect getCrop() {
        return null;
    }

    /** CarbonMirror always mirrors the main display (spec 5.1). */
    public int getDisplayId() {
        return 0;
    }

    public boolean getShowTouches() {
        return false;
    }

    public boolean getStayAwake() {
        return stayAwake;
    }

    public int getScreenOffTimeout() {
        return -1;
    }

    public int getDisplayImePolicy() {
        return -1;
    }

    public List<CodecOption> getVideoCodecOptions() {
        return null;
    }

    public String getVideoEncoder() {
        return null;
    }

    public boolean getPowerOffScreenOnClose() {
        return false;
    }

    public boolean getClipboardAutosync() {
        return clipboardAutosync;
    }

    public boolean getDownsizeOnError() {
        return true;
    }

    public boolean getCleanup() {
        return cleanup;
    }

    public boolean getPowerOn() {
        return powerOn;
    }

    public Orientation getCaptureOrientation() {
        return Orientation.Orient0;
    }

    public Orientation.Lock getCaptureOrientationLock() {
        return Orientation.Lock.Unlocked;
    }

    public boolean getKeepActive() {
        return false;
    }

    public boolean getIgnoreVideoEncoderConstraints() {
        return false;
    }

    public boolean getSendDeviceMeta() {
        return sendDeviceMeta;
    }

    public boolean getSendFrameMeta() {
        return sendFrameMeta;
    }

    public boolean getSendDummyByte() {
        return sendDummyByte;
    }

    public boolean getSendStreamMeta() {
        return sendStreamMeta;
    }

    public static Options parse(String... args) {
        if (args.length < 1) {
            throw new IllegalArgumentException("Missing client version");
        }

        String clientVersion = args[0];
        if (!clientVersion.equals(BuildConfig.VERSION_NAME)) {
            throw new IllegalArgumentException(
                    "The server version (" + BuildConfig.VERSION_NAME + ") does not match the client " + "(" + clientVersion + ")");
        }

        Options options = new Options();

        for (int i = 1; i < args.length; ++i) {
            String arg = args[i];
            int equalIndex = arg.indexOf('=');
            if (equalIndex == -1) {
                throw new IllegalArgumentException("Invalid key=value pair: \"" + arg + "\"");
            }
            String key = arg.substring(0, equalIndex);
            String value = arg.substring(equalIndex + 1);
            switch (key) {
                case "scid":
                    int scid = Integer.parseInt(value, 0x10);
                    if (scid < 0) {
                        throw new IllegalArgumentException("scid must be a 31-bit non-negative value: " + scid);
                    }
                    options.scid = scid;
                    break;
                case "log_level":
                    options.logLevel = Ln.Level.valueOf(value.toUpperCase(Locale.ENGLISH));
                    break;
                case "audio":
                    requireValue(key, value, "false");
                    break;
                case "video":
                case "control":
                case "tunnel_forward":
                    requireValue(key, value, "true");
                    break;
                case "video_source":
                    requireValue(key, value, "display");
                    break;
                case "display_id":
                    requireValue(key, value, "0");
                    break;
                case "video_codec":
                    VideoCodec videoCodec = VideoCodec.findByName(value);
                    if (videoCodec == null) {
                        throw new IllegalArgumentException("Video codec " + value + " not supported");
                    }
                    options.videoCodec = videoCodec;
                    break;
                case "max_size":
                    options.maxSize = parseBoundedInt(key, value, 0, MAX_SIZE_LIMIT);
                    break;
                case "video_bit_rate":
                    options.videoBitRate = parseBoundedInt(key, value, 1, MAX_VIDEO_BIT_RATE);
                    break;
                case "max_fps":
                    options.maxFps = parseFps(value);
                    break;
                case "stay_awake":
                    options.stayAwake = Boolean.parseBoolean(value);
                    break;
                case "clipboard_autosync":
                    options.clipboardAutosync = Boolean.parseBoolean(value);
                    break;
                case "cleanup":
                    options.cleanup = Boolean.parseBoolean(value);
                    break;
                case "power_on":
                    options.powerOn = Boolean.parseBoolean(value);
                    break;
                case "send_device_meta":
                    options.sendDeviceMeta = Boolean.parseBoolean(value);
                    break;
                case "send_frame_meta":
                    options.sendFrameMeta = Boolean.parseBoolean(value);
                    break;
                case "send_dummy_byte":
                    options.sendDummyByte = Boolean.parseBoolean(value);
                    break;
                case "send_stream_meta":
                    options.sendStreamMeta = Boolean.parseBoolean(value);
                    break;
                default:
                    throw new IllegalArgumentException("Option not allowed in CarbonMirror: " + key);
            }
        }

        if (options.scid == -1) {
            throw new IllegalArgumentException("scid is required");
        }
        return options;
    }

    private static void requireValue(String key, String value, String allowed) {
        if (!allowed.equals(value)) {
            throw new IllegalArgumentException(key + " must be " + allowed + " in CarbonMirror");
        }
    }

    private static int parseBoundedInt(String key, String value, int min, int max) {
        int parsed = Integer.parseInt(value);
        if (parsed < min || parsed > max) {
            throw new IllegalArgumentException(key + " out of range: " + parsed);
        }
        return parsed;
    }

    private static float parseFps(String value) {
        float fps;
        try {
            fps = Float.parseFloat(value);
        } catch (NumberFormatException e) {
            throw new IllegalArgumentException("Invalid max_fps: \"" + value + "\"");
        }
        if (!(fps >= 0 && fps <= MAX_FPS_LIMIT)) {
            throw new IllegalArgumentException("max_fps out of range: " + fps);
        }
        return fps;
    }
}
