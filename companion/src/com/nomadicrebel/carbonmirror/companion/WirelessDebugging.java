// SPDX-License-Identifier: PolyForm-Shield-1.0.0
// Required Notice: Copyright 2026 ButcheCassidy - The Nomadic Rebel
package com.nomadicrebel.carbonmirror.companion;

import android.Manifest;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.database.ContentObserver;
import android.provider.Settings;

/**
 * The live Wireless debugging state, shared by the tile and the app screen. Nothing is cached: every call
 * reads Settings.Global, so both keep working after GrapheneOS "Optimizing apps" / "Restart apps" (spec 9.3).
 */
final class WirelessDebugging {
    /** Settings.Global.ADB_WIFI_ENABLED (hidden constant, readable to apps). */
    private static final String ADB_WIFI_ENABLED = "adb_wifi_enabled";
    /** Set to 1 by the CarbonMirror server while a mirroring session runs (server CleanUp). */
    private static final String SESSION = "carbonmirror_session";

    private WirelessDebugging() {
    }

    static boolean on(Context context) {
        return Settings.Global.getInt(context.getContentResolver(), ADB_WIFI_ENABLED, 0) == 1;
    }

    static boolean mirroring(Context context) {
        return Settings.Global.getInt(context.getContentResolver(), SESSION, 0) == 1;
    }

    /** WRITE_SECURE_SETTINGS, granted once over USB by the Mac app; an OS update can reset it. */
    static boolean allowed(Context context) {
        return context.checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) == PackageManager.PERMISSION_GRANTED;
    }

    /** Turns Wireless debugging on or off; false when the permission is missing or refused. */
    static boolean set(Context context, boolean on) {
        if (!allowed(context)) {
            return false;
        }
        try {
            return Settings.Global.putInt(context.getContentResolver(), ADB_WIFI_ENABLED, on ? 1 : 0);
        } catch (SecurityException e) {
            return false;
        }
    }

    static void observe(Context context, ContentObserver observer) {
        ContentResolver resolver = context.getContentResolver();
        resolver.registerContentObserver(Settings.Global.getUriFor(ADB_WIFI_ENABLED), false, observer);
        resolver.registerContentObserver(Settings.Global.getUriFor(SESSION), false, observer);
    }

    static Intent developerOptions() {
        return new Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
    }
}
