package com.nomadicrebel.carbonmirror.companion;

import android.content.Context;
import android.content.SharedPreferences;
import android.net.LinkAddress;
import android.net.LinkProperties;

import java.net.Inet4Address;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HashSet;
import java.util.Set;

/**
 * Wi-Fi networks where CarbonMirror mirrored wirelessly, identified like the Mac does: by the IPv4 subnet
 * (no Location permission, no SSID), stored only as a domain-separated SHA-256 in app-private storage.
 */
final class TrustedNetworks {
    static final int LIMIT = 8;
    private static final String PREFS = "trusted_networks";
    private static final String KEY = "subnets";
    private static final String ENABLED_BY_US = "enabled_by_us";

    private TrustedNetworks() {
    }

    /** `a.b.c.d/n` of the first IPv4 address, or null. */
    static String subnet(LinkProperties properties) {
        if (properties == null) {
            return null;
        }
        for (LinkAddress address : properties.getLinkAddresses()) {
            if (address.getAddress() instanceof Inet4Address) {
                return subnet(address.getAddress().getAddress(), address.getPrefixLength());
            }
        }
        return null;
    }

    static String subnet(byte[] ip, int prefix) {
        if (ip.length != 4 || prefix < 0 || prefix > 32) {
            return null;
        }
        int value = (ip[0] & 0xFF) << 24 | (ip[1] & 0xFF) << 16 | (ip[2] & 0xFF) << 8 | (ip[3] & 0xFF);
        int network = prefix == 0 ? 0 : value & (-1 << (32 - prefix));
        return (network >>> 24) + "." + (network >>> 16 & 0xFF) + "." + (network >>> 8 & 0xFF) + "." + (network & 0xFF) + "/" + prefix;
    }

    static String key(String subnet) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(("carbonmirror-companion-subnet-v1:" + subnet).getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder(64);
            for (byte b : digest) {
                hex.append(Character.forDigit(b >> 4 & 0xF, 16)).append(Character.forDigit(b & 0xF, 16));
            }
            return hex.toString();
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    static boolean contains(Context context, String subnet) {
        return subnet != null && prefs(context).getStringSet(KEY, Set.of()).contains(key(subnet));
    }

    /** Adds `subnet`; the oldest-unknown order is not kept, so at the limit the set is cleared first. */
    static void add(Context context, String subnet) {
        if (subnet == null || contains(context, subnet)) {
            return;
        }
        Set<String> set = new HashSet<>(prefs(context).getStringSet(KEY, Set.of()));
        if (set.size() >= LIMIT) {
            set.clear();
        }
        set.add(key(subnet));
        prefs(context).edit().putStringSet(KEY, set).apply();
    }

    static void forgetAll(Context context) {
        prefs(context).edit().clear().apply();
    }

    static boolean enabledByUs(Context context) {
        return prefs(context).getBoolean(ENABLED_BY_US, false);
    }

    static void setEnabledByUs(Context context, boolean value) {
        prefs(context).edit().putBoolean(ENABLED_BY_US, value).apply();
    }
}
