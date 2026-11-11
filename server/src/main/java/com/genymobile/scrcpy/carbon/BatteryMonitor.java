package com.genymobile.scrcpy.carbon;

import com.genymobile.scrcpy.FakeContext;
import com.genymobile.scrcpy.control.DeviceMessage;
import com.genymobile.scrcpy.control.DeviceMessageSender;
import com.genymobile.scrcpy.util.Ln;

import android.content.Intent;
import android.content.IntentFilter;
import android.os.BatteryManager;

/**
 * Sends the fixed-size battery status message (level 0–100, charging yes/no) every 30 s and whenever it
 * changes. Read in-process from the sticky battery broadcast — no adb shell commands.
 */
public final class BatteryMonitor {

    private static final long POLL_MS = 5_000;
    private static final long RESEND_MS = 30_000;

    private final DeviceMessageSender sender;
    private Thread thread;

    public BatteryMonitor(DeviceMessageSender sender) {
        this.sender = sender;
    }

    public void start() {
        thread = new Thread(this::loop, "carbon-battery");
        thread.setDaemon(true);
        thread.start();
    }

    public void stop() {
        if (thread != null) {
            thread.interrupt();
        }
    }

    private void loop() {
        int lastLevel = -1;
        boolean lastCharging = false;
        long lastSent = 0;
        try {
            while (!Thread.currentThread().isInterrupted()) {
                Intent intent = FakeContext.get().registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
                if (intent != null) {
                    int level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
                    int scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, 100);
                    int status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1);
                    if (level >= 0 && scale > 0) {
                        int percent = Math.max(0, Math.min(100, level * 100 / scale));
                        boolean charging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL;
                        long now = System.currentTimeMillis();
                        if (percent != lastLevel || charging != lastCharging || now - lastSent >= RESEND_MS) {
                            sender.send(DeviceMessage.createBattery(percent, charging));
                            lastLevel = percent;
                            lastCharging = charging;
                            lastSent = now;
                        }
                    }
                }
                Thread.sleep(POLL_MS);
            }
        } catch (InterruptedException e) {
            // stopped
        } catch (RuntimeException e) {
            Ln.w("Battery status unavailable", e);
        }
    }
}
