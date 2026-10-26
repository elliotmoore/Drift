// Host smoke test: renders a few seconds per scenario to a WAV and prints levels.
// Build and run from the repo root (macOS, Command Line Tools are enough):
//   clang++ -DTEST -std=c++17 -O2 -w -IDSP/shim -IDSP/third_party -IDSP/Bridge \
//     $(find DSP/third_party -name '*.cc') DSP/Bridge/DriftEngine.cpp tools/render_test.cpp \
//     -o render_test && ./render_test out.wav
#include "DriftEngine.h"
#include <cstdio>
#include <cmath>
#include <vector>
#include <cstdint>

static void wav(const char* path, const std::vector<float>& l, const std::vector<float>& r) {
  FILE* f = fopen(path, "wb");
  uint32_t n = l.size(), bytes = n * 4, sr = 48000, br = sr * 4, x;
  uint16_t s;
  fwrite("RIFF", 1, 4, f); x = 36 + bytes; fwrite(&x, 4, 1, f); fwrite("WAVEfmt ", 1, 8, f);
  x = 16; fwrite(&x, 4, 1, f); s = 1; fwrite(&s, 2, 1, f); s = 2; fwrite(&s, 2, 1, f);
  fwrite(&sr, 4, 1, f); fwrite(&br, 4, 1, f); s = 4; fwrite(&s, 2, 1, f); s = 16; fwrite(&s, 2, 1, f);
  fwrite("data", 1, 4, f); fwrite(&bytes, 4, 1, f);
  for (uint32_t i = 0; i < n; ++i) {
    int16_t a = (int16_t)(l[i] * 32767), b = (int16_t)(r[i] * 32767);
    fwrite(&a, 2, 1, f); fwrite(&b, 2, 1, f);
  }
  fclose(f);
}

int main(int argc, char** argv) {
  drift_init();
  std::vector<float> L, R;
  float bl[471], br[471];   // an awkward buffer size on purpose
  auto run = [&](float seconds, const char* name) {
    double sum = 0; float pk = 0; size_t n = 0;
    drift_meters m0; drift_meters_read(&m0);
    for (int k = 0; k < seconds * 48000 / 471; ++k) {
      drift_render(bl, br, 471);
      for (int i = 0; i < 471; ++i) { L.push_back(bl[i]); R.push_back(br[i]); sum += bl[i]*bl[i]; pk = fmaxf(pk, fabsf(bl[i])); ++n; }
    }
    drift_meters m; drift_meters_read(&m);
    printf("%-28s rms %.3f peak %.3f beats %u strikes %u bpm %.0f\n", name, sqrt(sum / n), pk,
           m.beats - m0.beats, m.strikes - m0.strikes, m.bpm);
  };
  drift_set(DP_DRONE, 1); run(1.0, "drone VA");
  for (int e = 0; e < 24; ++e) { drift_set(DP_ENGINE, e); char b[32]; snprintf(b, 32, "drone engine %d", e); run(0.25, b); }
  drift_set(DP_ENGINE, 8); drift_set(DP_DRONE, 0); run(0.5, "silent (no trigger)");
  drift_gate(1); run(0.3, "touch strike"); drift_gate(0); run(0.3, "release");
  drift_set(DP_ENGINE, 12); drift_set(DR_X2_DEST, DD_TIMBRE); drift_set(DM_RUN, 1); run(4.0, "sequencer plays modal");
  drift_set(DM_T_DEJAVU, 1.0f); drift_set(DM_X_DEJAVU, 1.0f); drift_reseed(1234); run(4.0, "deja vu locked, reseeded");
  drift_set(DM_RUN, 0); run(0.5, "stopped");
  wav(argc > 1 ? argv[1] : "drift_test.wav", L, R);
  return 0;
}
