package com.nomadicrebel.carbonmirror.companion;

import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.ServiceInfo;
import android.database.ContentObserver;
import android.net.ConnectivityManager;
import android.net.LinkProperties;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.SystemClock;

/**
 * Keeps the phone ready for the Mac's auto-connect: Wireless debugging on while the phone is on a trusted
 * Wi-Fi network (one where CarbonMirror mirrored wirelessly), off again when it leaves one it turned on.
 * Foreground service (connectedDevice), restarted after process death (sticky), boot, app or OS updates
 * ({@link StartReceiver}) and by a 15-minute watchdog alarm. Opens no socket itself.
 */
public final class ReadyService extends Service {
    private static final String CHANNEL = "ready";
    private static final int NOTIFICATION = 1;
    private static final long WATCHDOG_MS = AlarmManager.INTERVAL_FIFTEEN_MINUTES;

    private final Handler main = new Handler(Looper.getMainLooper());
    private ConnectivityManager connectivity;
    /** Subnet of the current Wi-Fi network, or null when not on Wi-Fi. */
    private volatile String subnet;
    /** The network this service last tried to turn Wireless debugging on for (one try per network join). */
    private String tried;
    private boolean registered;

    private final ContentObserver settings = new ContentObserver(main) {
        @Override
        public void onChange(boolean selfChange) {
            evaluate();
        }
    };

    /** The Wi-Fi network itself, not the default one: with Mullvad always on the default network is the VPN. */
    private final ConnectivityManager.NetworkCallback network = new ConnectivityManager.NetworkCallback() {
        @Override
        public void onLinkPropertiesChanged(Network n, LinkProperties properties) {
            changed(TrustedNetworks.subnet(properties));
        }

        @Override
        public void onLost(Network n) {
            changed(null);
        }
    };

    static void start(Context context) {
        context.startForegroundService(new Intent(context, ReadyService.class));
    }

    @Override
    public void onCreate() {
        super.onCreate();
        connectivity = getSystemService(ConnectivityManager.class);
        getSystemService(NotificationManager.class).createNotificationChannel(
                new NotificationChannel(CHANNEL, getString(R.string.channel_ready), NotificationManager.IMPORTANCE_MIN));
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        startForeground(NOTIFICATION, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE);
        if (!registered) {
            WirelessDebugging.observe(this, settings);
            // Wi-Fi with or without internet access; VPNs are excluded by the request's default NOT_VPN capability.
            connectivity.registerNetworkCallback(new NetworkRequest.Builder().addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                    .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build(), network, main);
            registered = true;
        }
        scheduleWatchdog();
        evaluate();
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        if (registered) {
            getContentResolver().unregisterContentObserver(settings);
            connectivity.unregisterNetworkCallback(network);
            registered = false;
        }
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void changed(String newSubnet) {
        if (newSubnet == null || !newSubnet.equals(subnet)) {
            tried = null;
        }
        subnet = newSubnet;
        evaluate();
    }

    /** One decision from the live state; idempotent. */
    private void evaluate() {
        String current = subnet;
        boolean on = WirelessDebugging.on(this);
        // Only a wireless session marks the network trusted: a USB session may run while on any Wi-Fi.
        if (current != null && on && WirelessDebugging.mirroring(this) && !usbConnected()) {
            TrustedNetworks.add(this, current);
        }
        boolean triedHere = current != null && current.equals(tried);
        switch (decide(TrustedNetworks.contains(this, current), on, WirelessDebugging.mirroring(this), TrustedNetworks.enabledByUs(this), triedHere)) {
            case TURN_ON:
                tried = current;
                if (WirelessDebugging.set(this, true)) {
                    TrustedNetworks.setEnabledByUs(this, true);
                }
                break;
            case TURN_OFF:
                if (WirelessDebugging.set(this, false)) {
                    TrustedNetworks.setEnabledByUs(this, false);
                }
                break;
            case RELEASE:
                TrustedNetworks.setEnabledByUs(this, false);
                break;
            case NONE:
                break;
        }
        getSystemService(NotificationManager.class).notify(NOTIFICATION, notification());
    }

    /** Sticky USB state broadcast (no permission needed to read it); true while a USB data cable is attached. */
    private boolean usbConnected() {
        Intent state = registerReceiver(null, new IntentFilter("android.hardware.usb.action.USB_STATE"), Context.RECEIVER_NOT_EXPORTED);
        return state != null && state.getBooleanExtra("connected", false);
    }

    enum Change { TURN_ON, TURN_OFF, RELEASE, NONE }

    /**
     * On a trusted network: turn on, once per network join (Android turns it straight off again and asks
     * "Allow wireless debugging on this network?" for a Wi-Fi it doesn't trust yet; never ask twice). Elsewhere:
     * turn off only what this service turned on and never during a session. Turned off by the user or the
     * system: stop owning it.
     */
    static Change decide(boolean trusted, boolean on, boolean mirroring, boolean enabledByUs, boolean triedHere) {
        if (trusted && !on && !triedHere) {
            return Change.TURN_ON;
        }
        if (!trusted && on && enabledByUs && !mirroring) {
            return Change.TURN_OFF;
        }
        return !on && enabledByUs ? Change.RELEASE : Change.NONE;
    }

    private Notification notification() {
        int text = !WirelessDebugging.allowed(this) ? R.string.ready_setup
                : TrustedNetworks.contains(this, subnet) ? R.string.ready_trusted : R.string.ready_waiting;
        PendingIntent open = PendingIntent.getActivity(this, 0, new Intent(this, MainActivity.class), PendingIntent.FLAG_IMMUTABLE);
        return new Notification.Builder(this, CHANNEL)
                .setSmallIcon(R.drawable.ic_tile)
                .setContentTitle(getString(R.string.tile_label))
                .setContentText(getString(text))
                .setContentIntent(open)
                .setOngoing(true)
                .setVisibility(Notification.VISIBILITY_SECRET)
                .setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
                .build();
    }

    /** Restarts the service if the system stopped it; inexact, no exact-alarm permission. */
    private void scheduleWatchdog() {
        PendingIntent watchdog = PendingIntent.getBroadcast(this, 0, new Intent(this, StartReceiver.class).setAction(StartReceiver.WATCHDOG),
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        getSystemService(AlarmManager.class).setInexactRepeating(AlarmManager.ELAPSED_REALTIME_WAKEUP,
                SystemClock.elapsedRealtime() + WATCHDOG_MS, WATCHDOG_MS, watchdog);
    }
}
