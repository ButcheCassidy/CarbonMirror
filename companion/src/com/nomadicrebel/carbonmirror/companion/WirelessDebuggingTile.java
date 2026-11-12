package com.nomadicrebel.carbonmirror.companion;

import android.app.PendingIntent;
import android.content.Intent;
import android.os.Build;
import android.service.quicksettings.Tile;
import android.service.quicksettings.TileService;

/**
 * Quick Settings tile "CarbonMirror" (spec 9.1): tap turns Wireless debugging on (or off). Stateless, see
 * {@link WirelessDebugging}. Without WRITE_SECURE_SETTINGS the tile opens Developer options instead of failing.
 */
public final class WirelessDebuggingTile extends TileService {
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
        if (WirelessDebugging.set(this, !WirelessDebugging.on(this))) {
            refresh();
        } else {
            openDeveloperOptions();
        }
    }

    /** Off / Ready / Mirroring, from the live settings. */
    private void refresh() {
        Tile tile = getQsTile();
        if (tile == null) {
            return;
        }
        boolean on = WirelessDebugging.on(this);
        boolean mirroring = WirelessDebugging.mirroring(this);
        tile.setState(on || mirroring ? Tile.STATE_ACTIVE : Tile.STATE_INACTIVE);
        tile.setSubtitle(getString(mirroring ? R.string.state_mirroring : on ? R.string.state_ready : R.string.state_off));
        tile.updateTile();
    }

    /** Fallback when the permission is missing (e.g. reset by an OS update). */
    private void openDeveloperOptions() {
        Intent intent = WirelessDebugging.developerOptions();
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
