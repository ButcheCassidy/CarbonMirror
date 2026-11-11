package com.genymobile.scrcpy.control;

public final class DeviceMessage {

    public static final int TYPE_CLIPBOARD = 0;
    public static final int TYPE_ACK_CLIPBOARD = 1;
    public static final int TYPE_UHID_OUTPUT = 2;
    /** CarbonMirror fork: battery level 0–100 and charging flag. */
    public static final int TYPE_BATTERY = 0x40;
    /** CarbonMirror fork: answer to a control-channel ping (round-trip latency). */
    public static final int TYPE_PONG = 0x41;

    private int type;
    private String text;
    private long sequence;
    private int id;
    private byte[] data;
    private int level;
    private boolean charging;

    private DeviceMessage() {
    }

    public static DeviceMessage createClipboard(String text) {
        DeviceMessage event = new DeviceMessage();
        event.type = TYPE_CLIPBOARD;
        event.text = text;
        return event;
    }

    public static DeviceMessage createAckClipboard(long sequence) {
        DeviceMessage event = new DeviceMessage();
        event.type = TYPE_ACK_CLIPBOARD;
        event.sequence = sequence;
        return event;
    }

    public static DeviceMessage createUhidOutput(int id, byte[] data) {
        DeviceMessage event = new DeviceMessage();
        event.type = TYPE_UHID_OUTPUT;
        event.id = id;
        event.data = data;
        return event;
    }

    public static DeviceMessage createBattery(int level, boolean charging) {
        DeviceMessage event = new DeviceMessage();
        event.type = TYPE_BATTERY;
        event.level = level;
        event.charging = charging;
        return event;
    }

    public static DeviceMessage createPong(long value) {
        DeviceMessage event = new DeviceMessage();
        event.type = TYPE_PONG;
        event.sequence = value;
        return event;
    }

    public int getLevel() {
        return level;
    }

    public boolean getCharging() {
        return charging;
    }

    public int getType() {
        return type;
    }

    public String getText() {
        return text;
    }

    public long getSequence() {
        return sequence;
    }

    public int getId() {
        return id;
    }

    public byte[] getData() {
        return data;
    }
}
