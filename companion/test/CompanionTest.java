package com.nomadicrebel.carbonmirror.companion;

import static com.nomadicrebel.carbonmirror.companion.ReadyService.Change.NONE;
import static com.nomadicrebel.carbonmirror.companion.ReadyService.Change.RELEASE;
import static com.nomadicrebel.carbonmirror.companion.ReadyService.Change.TURN_OFF;
import static com.nomadicrebel.carbonmirror.companion.ReadyService.Change.TURN_ON;

/** JVM checks of the companion's pure logic (run by scripts/test-companion.sh). */
public final class CompanionTest {
    private static int passed;

    private static void check(boolean condition, String name) {
        if (!condition) {
            throw new AssertionError(name);
        }
        passed++;
    }

    public static void main(String[] args) {
        check(TrustedNetworks.subnet(new byte[] {(byte) 192, (byte) 168, 1, 20}, 24).equals("192.168.1.0/24"), "subnet /24");
        check(TrustedNetworks.subnet(new byte[] {10, 1, 2, 3}, 8).equals("10.0.0.0/8"), "subnet /8");
        check(TrustedNetworks.subnet(new byte[] {(byte) 172, 16, 5, (byte) 255}, 32).equals("172.16.5.255/32"), "subnet /32");
        check(TrustedNetworks.subnet(new byte[] {1, 2, 3, 4}, 0).equals("0.0.0.0/0"), "subnet /0");
        check(TrustedNetworks.subnet(new byte[] {1, 2, 3}, 24) == null, "short address refused");
        check(TrustedNetworks.subnet(new byte[] {1, 2, 3, 4}, 33) == null, "prefix > 32 refused");
        check(TrustedNetworks.subnet(new byte[16], 64) == null, "IPv6 refused");
        String key = TrustedNetworks.key("192.168.1.0/24");
        check(key.length() == 64 && key.matches("[0-9a-f]+"), "key is SHA-256 hex");
        check(!key.equals(TrustedNetworks.key("192.168.2.0/24")), "keys differ per subnet");
        check(!key.contains("192"), "subnet not stored in plaintext");

        check(ReadyService.decide(true, false, false, false, false) == TURN_ON, "trusted, off: turn on");
        check(ReadyService.decide(true, true, false, true, false) == NONE, "trusted, on: keep");
        check(ReadyService.decide(false, true, false, true, false) == TURN_OFF, "left trusted Wi-Fi: turn off what we turned on");
        check(ReadyService.decide(false, true, false, false, false) == NONE, "user turned it on: never touched");
        check(ReadyService.decide(false, true, true, true, false) == NONE, "never cut a running session");
        check(ReadyService.decide(false, false, false, true, false) == RELEASE, "turned off elsewhere: release ownership");
        check(ReadyService.decide(false, false, false, false, false) == NONE, "untrusted, off: nothing");
        check(ReadyService.decide(true, false, false, false, true) == NONE, "Android said no on this network: never ask twice");
        check(ReadyService.decide(true, false, false, true, true) == RELEASE, "turned off by Android after our try: release");
        System.out.println("companion tests: " + passed + " passed");
    }
}
