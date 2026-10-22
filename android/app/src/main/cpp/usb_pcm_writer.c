#include <jni.h>
#include <dlfcn.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

/* Android 10 tinyalsa ABI; system implementation is loaded only by the root
 * helper, not by the sandboxed application. No private library is bundled. */
struct pcm;
struct pcm_config {
    unsigned int channels, rate, period_size, period_count;
    int format;
    unsigned int start_threshold, stop_threshold, silence_threshold, silence_size;
    int avail_min;
};

static int failure(const char *message, const char *detail) {
    fprintf(stdout, "ERROR:%s%s%s\n", message, detail ? ": " : "", detail ? detail : "");
    fflush(stdout);
    return 1;
}

JNIEXPORT jint JNICALL
Java_com_cmwen_codex_1micro_1tablet_UsbPcmWriter_streamPcm(
        JNIEnv *env, jobject self, jint card, jint device) {
    (void)env;
    (void)self;
    if (card < 0 || card > 255 || device < 0 || device > 255)
        return failure("Invalid USB audio-source PCM identity", NULL);
    void *library = dlopen("libtinyalsa.so", RTLD_NOW | RTLD_LOCAL);
    if (!library) return failure("Cannot load system tinyalsa", dlerror());
    struct pcm *(*open_pcm)(unsigned int, unsigned int, unsigned int, struct pcm_config *) =
            (struct pcm *(*)(unsigned int, unsigned int, unsigned int, struct pcm_config *))dlsym(library, "pcm_open");
    int (*is_ready)(struct pcm *) = (int (*)(struct pcm *))dlsym(library, "pcm_is_ready");
    const char *(*get_error)(struct pcm *) = (const char *(*)(struct pcm *))dlsym(library, "pcm_get_error");
    int (*write_pcm)(struct pcm *, const void *, unsigned int) =
            (int (*)(struct pcm *, const void *, unsigned int))dlsym(library, "pcm_write");
    int (*close_pcm)(struct pcm *) = (int (*)(struct pcm *))dlsym(library, "pcm_close");
    if (!open_pcm || !is_ready || !get_error || !write_pcm || !close_pcm) {
        dlclose(library);
        return failure("System tinyalsa is missing required PCM functions", NULL);
    }
    struct pcm_config config = {
        .channels = 2, .rate = 44100, .period_size = 1024, .period_count = 4,
        .format = 0, /* PCM_FORMAT_S16_LE */
        .start_threshold = 1024, .stop_threshold = 4096,
        .silence_threshold = 0, .silence_size = 0, .avail_min = 0
    };
    struct pcm *pcm = open_pcm((unsigned int)card, (unsigned int)device, 0, &config);
    if (!pcm || !is_ready(pcm)) {
        int result = failure("Cannot open USB audio-source PCM", pcm ? get_error(pcm) : "no PCM handle");
        if (pcm) close_pcm(pcm);
        dlclose(library);
        return result;
    }
    fprintf(stdout, "READY\n");
    fflush(stdout);
    uint8_t bytes[4096 + 3];
    size_t retained = 0;
    uint64_t frames = 0, reported = 0;
    int result = 0;
    for (;;) {
        ssize_t count = read(STDIN_FILENO, bytes + retained, sizeof(bytes) - retained);
        if (count == 0) break;
        if (count < 0) {
            if (errno == EINTR) continue;
            result = failure("USB microphone pipe read failed", strerror(errno));
            break;
        }
        size_t available = retained + (size_t)count;
        size_t whole = available & ~(size_t)3; /* stereo 16-bit frames */
        if (whole && write_pcm(pcm, bytes, (unsigned int)whole) != 0) {
            result = failure("USB audio write failed; check the cable and selected Mac input", get_error(pcm));
            break;
        }
        retained = available - whole;
        if (retained) memmove(bytes, bytes + whole, retained);
        frames += whole / 4;
        if (frames - reported >= 44100) {
            fprintf(stdout, "FRAMES:%llu\n", (unsigned long long)frames);
            fflush(stdout);
            reported = frames;
        }
    }
    if (retained && !result) result = failure("Incomplete USB PCM frame", NULL);
    close_pcm(pcm);
    dlclose(library);
    fprintf(stdout, "DONE:%llu\n", (unsigned long long)frames);
    fflush(stdout);
    return result;
}
