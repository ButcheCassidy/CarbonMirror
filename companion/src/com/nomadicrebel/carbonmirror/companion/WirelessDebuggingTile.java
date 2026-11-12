package com.nomadicrebel.carbonmirror.companion;

import android.Manifest;
import android.app.PendingIntent;
import android.content.ContentResolver;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;
import android.provider.Settings;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

/**
 * Quick Settings tile "CarbonMirror" (spec 9.1): tap turns Wireless debugging on (or off). The tile is
 * stateless: every time it is shown or tapped it reads the real state from Settings.Global, so it keeps
 * working after GrapheneOS "Optimizing apps" / "Restart apps" without anything being reopened (spec 9.3).
 * Writing the setting needs WRITE_SECURE_SETTINGS, granted once over USB by the Mac app; without it the tile
 * opens Developer options instead of failing.
 */
public final class WirelessDebuggingTile extends TileService {
    /** Settings.Global.ADB_WIFI_ENABLED (hidden constant, readable to apps). */
    private static final String ADB_WIFI_ENABLED = "adb_wifi_enabled";
    /** Set to 1 by the CarbonMirror server while a mirroring session runs (server CleanUp). */
    private static final String SESSION = "carbonmirror_session";

    @Override
    public void onTileAdded() {
        refresh();
    }

    @Override
    public void onStartListening() {
        refresh();
    }

    @Override
    public void onClick() {
        if (checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) != PackageManager.PERMISSION_GRANTED) {
            openDeveloperOptions();
            return;
        }
        try {
            Settings.Global.putInt(getContentResolver(), ADB_WIFI_ENABLED, wirelessDebuggingOn() ? 0 : 1);
        } catch (SecurityException e) {
            openDeveloperOptions();
            return;
        }
        refresh();
    }

    private boolean wirelessDebuggingOn() {
        return Settings.Global.getInt(getContentResolver(), ADB_WIFI_ENABLED, 0) == 1;
    }

    /** Off / Ready / Mirroring, from the live settings. */
    private void refresh() {
        Tile tile = getQsTile();
        if (tile == null) {
            return;
        }
        ContentResolver resolver = getContentResolver();
        boolean on = wirelessDebuggingOn();
        boolean mirroring = Settings.Global.getInt(resolver, SESSION, 0) == 1;
        tile.setState(on || mirroring ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE);
        tile.setSubtitle(mirroring ? "Mirroring" : on ? "Ready" : "Off");
        tile.updateTile();
    }

    /** Fallback when the permission is missing (e.g. reset by an OS update). */
    private void openDeveloperOptions() {
        Intent intent = new Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE));
        } else {
            startActivityAndCollapseLegacy(intent);
        }
    }

    @SuppressWarnings("deprecation")
    private void startActivityAndCollapseLegacy(Intent intent) {
        startActivityAndCollapse(intent);
    }
}
