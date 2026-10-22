package com.cmwen.codex_micro_tablet;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/** Report bodies exclude report ID 6. Matches the FNK0104B vendor channel. */
public final class MicroWire {
    public static final int REPORT_ID = 6;
    public static final int BODY_SIZE = 63;
    public static final int MAX_JSON = 2048;
    public static final byte[] DESCRIPTOR = new byte[] {
        0x06,0x00,(byte)0xff,0x09,0x01,(byte)0xa1,0x01,(byte)0x85,0x06,
        0x09,0x02,0x15,0x00,0x26,(byte)0xff,0x00,0x75,0x08,(byte)0x95,0x3f,(byte)0x81,0x02,
        0x09,0x03,(byte)0x91,0x02,0x09,0x04,(byte)0xb1,0x02,(byte)0xc0
    };

    public static List<byte[]> frame(String json) {
        byte[] source = (json + "\r\n").getBytes(StandardCharsets.UTF_8);
        if (source.length > MAX_JSON + 2) throw new IllegalArgumentException("Oversized HID message");
        List<byte[]> result = new ArrayList<>();
        for (int offset = 0; offset < source.length; offset += 61) {
            byte[] body = new byte[BODY_SIZE];
            int count = Math.min(61, source.length - offset);
            body[0] = 2;
            body[1] = (byte)count;
            System.arraycopy(source, offset, body, 2, count);
            result.add(body);
        }
        return result;
    }

    public static String key(int key, boolean pressed) {
        if (key < 0 || key > 16) throw new IllegalArgumentException("Unknown control");
        int action = pressed ? 1 : 0;
        if (key >= 13) {
            String[] angles = {"0.75", "0.25", "0", "0.5"};
            return "{\"m\":\"v.oai.rad\",\"p\":{\"a\":" + (pressed ? angles[key - 13] : "0") + ",\"d\":" + action + "}}";
        }
        String name = key < 6 ? "AG0" + key : "ACT" + (key < 10 ? "0" : "") + key;
        return "{\"m\":\"v.oai.hid\",\"p\":{\"k\":\"" + name + "\",\"act\":" + action + (key < 6 ? ",\"ag\":" + key : "") + "}}";
    }

    public interface Consumer { void accept(String json); }

    /** macOS can retain the report ID when writing a report characteristic. */
    public static byte[] bleBody(byte[] value) {
        if (value == null) return null;
        if (value.length == BODY_SIZE + 1) {
            if ((value[0] & 255) == REPORT_ID && value[1] == 2)
                return java.util.Arrays.copyOfRange(value, 1, value.length);
            // Some HID backends pad the body to their 64-byte transfer size.
            if (value[0] == 2 && value[BODY_SIZE] == 0)
                return java.util.Arrays.copyOf(value, BODY_SIZE);
            return null;
        }
        return value.length >= 2 && value.length <= BODY_SIZE ? value.clone() : null;
    }

    public static final class Decoder {
        private final ByteArrayOutputStream data = new ByteArrayOutputStream();
        private int depth;
        private boolean quoted, escaped, dropping;
        public void reset() { data.reset(); depth = 0; quoted = escaped = dropping = false; }
        public boolean feed(byte[] body, Consumer output) {
            if (body == null || body.length < 2 || body.length > BODY_SIZE || body[0] != 2 ||
                (body[1] & 255) > 61 || (body[1] & 255) > body.length - 2) {
                reset(); return false;
            }
            int count = body[1] & 255;
            for (int i = 2; i < count + 2; i++) {
                int c = body[i] & 255;
                if (depth == 0) {
                    if (c == ' ' || c == '\r' || c == '\n' || c == '\t') continue;
                    if (c != '{') { reset(); return false; }
                    depth = 1; data.write(c); continue;
                }
                if (!dropping) {
                    if (data.size() >= MAX_JSON) { dropping = true; data.reset(); }
                    else data.write(c);
                }
                if (quoted) {
                    if (escaped) escaped = false;
                    else if (c == '\\') escaped = true;
                    else if (c == '"') quoted = false;
                } else if (c == '"') quoted = true;
                else if (c == '{') depth++;
                else if (c == '}' && --depth == 0) {
                    if (!dropping) output.accept(new String(data.toByteArray(), StandardCharsets.UTF_8));
                    reset();
                }
                if (c == '\n' && depth > 0) { reset(); return false; }
            }
            return !dropping;
        }
    }
}
