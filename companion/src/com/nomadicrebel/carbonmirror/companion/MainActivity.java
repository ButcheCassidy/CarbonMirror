package com.nomadicrebel.carbonmirror.companion;

import android.app.Activity;
import android.app.StatusBarManager;
import android.content.ActivityNotFoundException;
import android.content.ComponentName;
import android.content.Intent;
import android.database.ContentObserver;
import android.graphics.Rect;
import android.graphics.drawable.Icon;
import android.media.AudioManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.widget.FrameLayout;
import android.widget.TextView;
import android.widget.Toast;
import android.widget.VideoView;

/**
 * The app screen: the startup animation on black, then one status screen (Off / Ready / Mirroring) with the
 * same actions as the tile. Stateless like the tile; it never reads its launch Intent.
 */
public final class MainActivity extends Activity {
    /** The clip is 1024 px square; it is shown at most 512 dp wide and never upscaled. */
    private static final int CLIP_PIXELS = 1024;
    private static final int CLIP_MAX_DP = 512;

    private final ContentObserver observer = new ContentObserver(new Handler(Looper.getMainLooper())) {
        @Override
        public void onChange(boolean selfChange) {
            refresh();
        }
    };
    private FrameLayout root;
    private View status;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        // Edge to edge on every Android version, so the animation is centred on the whole window.
        getWindow().setDecorFitsSystemWindows(false);
        root = new FrameLayout(this);
        setContentView(root);
        if (state == null) {
            playStartup();
        } else {
            showStatus();
        }
    }

    @Override
    protected void onStart() {
        super.onStart();
        WirelessDebugging.observe(this, observer);
        refresh();
    }

    @Override
    protected void onStop() {
        super.onStop();
        getContentResolver().unregisterContentObserver(observer);
        // A VideoView does not resume after its surface is destroyed; never come back to a black screen.
        showStatus();
    }

    private void playStartup() {
        Rect window = getWindowManager().getCurrentWindowMetrics().getBounds();
        int side = Math.min(Math.min(window.width(), window.height()),
                Math.min(CLIP_PIXELS, Math.round(CLIP_MAX_DP * getResources().getDisplayMetrics().density)));
        VideoView video = new VideoView(this);
        video.setAudioFocusRequest(AudioManager.AUDIOFOCUS_NONE);
        video.setVideoURI(Uri.parse("android.resource://" + getPackageName() + "/" + R.raw.startup));
        video.setOnCompletionListener(player -> showStatus());
        video.setOnErrorListener((player, what, extra) -> {
            showStatus();
            return true;
        });
        root.addView(video, new FrameLayout.LayoutParams(side, side, Gravity.CENTER));
        video.start();
    }

    private void showStatus() {
        if (status != null) {
            return;
        }
        root.removeAllViews();
        status = getLayoutInflater().inflate(R.layout.status, root, false);
        status.setAlpha(0);
        root.addView(status);
        status.animate().alpha(1).setDuration(250);
        status.findViewById(R.id.primary).setOnClickListener(view -> primaryAction());
        status.findViewById(R.id.add_tile).setOnClickListener(view -> addTile());
        refresh();
    }

    /** Off / Ready / Mirroring / setup needed, from the live settings. */
    private void refresh() {
        if (status == null) {
            return;
        }
        boolean on = WirelessDebugging.on(this);
        boolean mirroring = WirelessDebugging.mirroring(this);
        boolean allowed = WirelessDebugging.allowed(this);
        ((TextView) status.findViewById(R.id.title)).setText(
                mirroring ? R.string.state_mirroring : on ? R.string.state_ready : R.string.state_off);
        ((TextView) status.findViewById(R.id.subtitle)).setText(
                mirroring ? R.string.hint_mirroring : on ? R.string.hint_ready : allowed ? R.string.hint_off : R.string.hint_setup);
        TextView primary = status.findViewById(R.id.primary);
        primary.setText(!allowed ? R.string.developer_options : on ? R.string.turn_off : R.string.turn_on);
        // Turning Wireless debugging off would cut a wireless session; that is done from the Mac.
        primary.setVisibility(mirroring ? View.GONE : View.VISIBLE);
        status.findViewById(R.id.add_tile).setVisibility(Build.VERSION.SDK_INT >= 33 ? View.VISIBLE : View.GONE);
    }

    private void primaryAction() {
        if (WirelessDebugging.set(this, !WirelessDebugging.on(this))) {
            refresh();
            return;
        }
        try {
            startActivity(WirelessDebugging.developerOptions());
        } catch (ActivityNotFoundException e) {
            // Developer options are still off: About phone is where Build number is tapped.
            startActivity(new Intent(Settings.ACTION_DEVICE_INFO_SETTINGS));
        }
    }

    /** System dialog that adds the tile to Quick Settings (Android 13+). */
    private void addTile() {
        if (Build.VERSION.SDK_INT < 33) {
            return;
        }
        getSystemService(StatusBarManager.class).requestAddTileService(
                new ComponentName(this, WirelessDebuggingTile.class), getString(R.string.tile_label),
                Icon.createWithResource(this, R.drawable.ic_tile), getMainExecutor(), result -> {
                    if (result == StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED) {
                        Toast.makeText(this, R.string.tile_already_added, Toast.LENGTH_SHORT).show();
                    }
                });
    }
}
