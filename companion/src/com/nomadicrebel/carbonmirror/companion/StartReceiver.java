package com.nomadicrebel.carbonmirror.companion;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Starts {@link ReadyService} after boot (including OS updates), app updates and the watchdog alarm. Not exported. */
public final class StartReceiver extends BroadcastReceiver {
    static final String WATCHDOG = "com.nomadicrebel.carbonmirror.companion.WATCHDOG";

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        if (Intent.ACTION_BOOT_COMPLETED.equals(action) || Intent.ACTION_MY_PACKAGE_REPLACED.equals(action) || WATCHDOG.equals(action)) {
            try {
                ReadyService.start(context);
            } catch (IllegalStateException e) {
                // Android refuses a background start while battery use is restricted; the next boot or app open starts it.
            }
        }
    }
}
