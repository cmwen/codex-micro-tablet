package com.cmwen.codex_micro_tablet;

import java.util.ArrayList;
import java.util.List;

public final class MicroWireCheck {
    static void check(boolean value, String name) { if (!value) throw new AssertionError(name); }
    public static void main(String[] args) {
        List<String> received = new ArrayList<>();
        MicroWire.Decoder decoder = new MicroWire.Decoder();
        String json = "{\"text\":\"Unicode 中文 and \\\" braces { } \\\"\",\"array\":[{\"a\":1}],\"padding\":\"" + "x".repeat(130) + "\"}";
        List<byte[]> reports = MicroWire.frame(json);
        check(reports.size() > 2, "fragmentation");
        for (byte[] report : reports) {
            check(report.length == 63 && report[0] == 2 && report[1] <= 61, "wire envelope");
            check(decoder.feed(report, received::add), "valid report");
        }
        check(received.size() == 1 && received.get(0).equals(json), "UTF8 fragmented round trip");
        check(!decoder.feed(new byte[]{2,62}, received::add), "bad length reset");
        for (byte[] report : MicroWire.frame("{\"a\":1}{\"b\":2}")) decoder.feed(report, received::add);
        check(received.size() == 3, "multiple newline-free calls");
        check(MicroWire.key(0,true).contains("\"k\":\"AG00\",\"act\":1,\"ag\":0"), "agent press");
        check(MicroWire.key(5,false).contains("\"AG05\""), "six slots");
        check(MicroWire.key(10,false).contains("\"ACT10\",\"act\":0"), "mic release");
        check(MicroWire.key(12,true).contains("\"ACT12\""), "send");
        check(MicroWire.key(13,true).contains("\"a\":0.75,\"d\":1"), "up");
        check(MicroWire.key(14,true).contains("\"a\":0.25"), "down");
        check(MicroWire.key(15,true).contains("\"a\":0,"), "right");
        check(MicroWire.key(16,true).contains("\"a\":0.5"), "left");
        for (int id=13; id<=16; id++) check(MicroWire.key(id,false).contains("\"a\":0,\"d\":0"), "neutral release");
        try { MicroWire.key(17,true); throw new AssertionError("invalid key"); } catch (IllegalArgumentException expected) {}
        decoder.reset();
        byte[] bad = new byte[63]; bad[0]=2; bad[1]=61;
        java.util.Arrays.fill(bad,2,63,(byte)'x'); bad[2]='{';
        decoder.feed(bad, received::add);
        for(int i=0;i<40;i++) { bad[2]='x'; decoder.feed(bad,received::add); }
        byte[] close = {2,1,'}'}; decoder.feed(close,received::add);
        int previous = received.size();
        for(byte[] report: MicroWire.frame("{\"recovered\":true}")) decoder.feed(report,received::add);
        check(received.size()==previous+1, "oversized frame discarded and recovered");
        System.out.println("MicroWire: fragmentation, UTF8, recovery, key identities and neutral releases passed");
    }
}
