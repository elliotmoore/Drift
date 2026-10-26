// Drift — the voice and the sequencer behind one C interface. See DriftEngine.h.
//
// The sequencer runs once per Plaits block (12 samples at 48 kHz = 4 kHz): Plaits reads
// its modulation and trigger inputs once per block, so anything faster is thrown away.
// Wakes verified that Marbles' generators produce the same sequences at 4 kHz as at
// their native 32 kHz. The routing constants below follow Wakes' sp1_synth.cc.

#include "DriftEngine.h"

#include <atomic>
#include <cmath>
#include <cstring>

#include "plaits/dsp/dsp.h"
#include "plaits/dsp/voice.h"
#include "stmlib/utils/buffer_allocator.h"

#include "marbles/random/random_generator.h"
#include "marbles/random/random_stream.h"
#include "marbles/random/t_generator.h"
#include "marbles/random/x_y_generator.h"

#include "DriftFX.h"

namespace marbles {
#include "marbles_scales.inc"   // the six preset scales, from marbles/settings.cc
}

namespace {

const uint32_t kBlock = plaits::kBlockSize;            // 12
const float kSeqRate = 48000.0f / kBlock;              // 4 kHz
const float kGateVolts = 5.0f;
const float kVoltPerOct = 12.0f;                       // semitones per volt
const float kParamPerVolt = 0.2f;                      // +-5 V -> +-1

// ---- parameters: one atomic per control, per voice ----
// Shared controls live in voice 0's row; per-voice ones (drift_is_per_voice) in each row.
const int kVoices = DRIFT_VOICES;
std::atomic<float> params[kVoices][DP_COUNT];
std::atomic<int32_t> gate_on[kVoices];      // how many surfaces hold each voice's gate
std::atomic<uint32_t> gate_presses[kVoices];
std::atomic<uint32_t> reseed_req{0};
std::atomic<uint32_t> reseed_val{1};
std::atomic<uint32_t> seed_now{1};

// ---- meters: audio -> UI ----
std::atomic<uint32_t> m_gates{0}, m_beats{0};
std::atomic<uint32_t> m_strikes[kVoices];
std::atomic<int> m_engines[kVoices];
std::atomic<float> m_volts[4];
std::atomic<float> m_ramp{0.0f}, m_peak{0.0f};
std::atomic<int> m_caught_beats{0};

// ---- the voices: everything that belongs to one Plaits ----
struct VoiceState {
  plaits::Voice voice;
  char arena[32768];
  plaits::Patch patch;
  plaits::Modulations mods;
  plaits::Voice::Frame frames[plaits::kBlockSize];
  float smooth[DP_COUNT];
  uint8_t gates_prev = 0;
  bool trig_level_prev = false;
  uint32_t presses_seen = 0;
  float hold_vca = 1.0f;          // our own gate for Hold on self-enveloped engines
  float chop_vca = 1.0f;          // the strip chopping a drone
  bool strip_was = false;
  int strip_blocks = 0;           // blocks since the strip was touched
  bool was_sounding = false;      // rendered last block (a voice switched on starts clean)
};
VoiceState vs[kVoices];

// ---- sequencer ----
marbles::RandomGenerator random_generator;
marbles::RandomStream random_stream;
marbles::TGenerator t_generator;
marbles::XYGenerator xy_generator;
int loaded_scale = -1;
uint32_t loaded_pad_version = 0;

// The pad's scale (DM_X_SCALE = 6): double-buffered, main writes the spare buffer and
// publishes it with the version; the audio thread loads it at its next block.
const int kPadScale = 6;
marbles::Scale pad_scales[2];
std::atomic<uint32_t> pad_scale_live{0};
std::atomic<uint32_t> pad_scale_version{0};

const marbles::Ratio kYDividerRatios[12] = {
  { 1, 64 }, { 1, 48 }, { 1, 32 }, { 1, 24 }, { 1, 16 }, { 1, 12 },
  { 1, 8 }, { 1, 6 }, { 1, 4 }, { 1, 3 }, { 1, 2 }, { 1, 1 },
};

// ---- effects (audio thread) ----
drift_fx::Phaser fx_phaser;
drift_fx::Delay fx_delay;
drift_fx::Reverb fx_reverb;
drift_fx::BeatRepeat fx_repeat;
drift_fx::Fade fade_phaser, fade_delay, fade_reverb;
// Delay divisions in beats: 1/16, 1/8T, 1/8, 1/8 dotted, 1/4, 1/4 dotted, 1/2, 1 bar.
const float kDelayBeats[8] = { 0.25f, 1.0f / 3.0f, 0.5f, 0.75f, 1.0f, 1.5f, 2.0f, 4.0f };
const float kRepeatPerBeat[6] = { 1.0f, 2.0f, 3.0f, 4.0f, 6.0f, 8.0f };

// ---- audio-thread state ----
bool initialised = false;
bool was_running = false;
bool t2_was = false;
uint32_t reseed_seen = 0;
float smooth_vol = 0.8f;        // Volume, shared
float out_l[kBlock], out_r[kBlock];

// Burst state (audio thread).
bool burst_was = false;
int burst_slot = 0;            // which subdivision of the beat we are in (running)
float burst_phase = 0.0f;      // 0..1 within a subdivision (stopped)
float burst_ramp_prev = 0.0f;  // last block's beat phase, to see the beat wrap
int burst_gate_blocks = 0;     // how long the current burst strike stays high
// ---- Catch: a memory of what the sequencer played (audio thread) ----
// One frame per sequencer sample (4 kHz): ~30 s, 2.9 MB. Beat starts (t2 rising edges)
// are remembered too, so a caught loop starts and ends on the beat.
struct SeqFrame { float volts[4]; float ramp; uint8_t gates; };
const uint32_t kHistory = 4000u * 30u;
SeqFrame history[kHistory];
uint64_t history_n = 0;                 // frames ever written
const int kMarks = 33;
uint64_t beat_marks[kMarks];            // frame index of the last few beat starts
int marks_n = 0;                        // valid entries (newest at the end)
uint64_t caught_start = 0;
uint32_t caught_len = 0;                // 0 = nothing caught
uint32_t caught_pos = 0;
int caught_beats = 0;
std::atomic<uint32_t> catch_req{0};
std::atomic<uint32_t> catch_on{0};
uint32_t catch_seen = 0;

void Remember(uint8_t gates, const float* volts, float ramp, bool beat_start) {
  SeqFrame& f = history[history_n % kHistory];
  for (int k = 0; k < 4; ++k) f.volts[k] = volts[k];
  f.ramp = ramp;
  f.gates = gates;
  if (beat_start) {
    if (marks_n == kMarks) {
      for (int i = 1; i < kMarks; ++i) beat_marks[i - 1] = beat_marks[i];
      --marks_n;
    }
    beat_marks[marks_n++] = history_n;
  }
  ++history_n;
}

// Loop the last `beats` whole beats, continuing in phase from where we are now.
void Catch(int beats) {
  // Only beat starts still inside the memory count.
  int first = 0;
  while (first < marks_n && history_n - beat_marks[first] >= kHistory) ++first;
  const int avail = marks_n - first - 1;          // complete beats remembered
  if (avail < 1) return;
  if (beats > avail) beats = avail;
  const uint64_t end = beat_marks[marks_n - 1];
  const uint64_t start = beat_marks[marks_n - 1 - beats];
  caught_start = start;
  caught_len = static_cast<uint32_t>(end - start);
  caught_pos = static_cast<uint32_t>((history_n - end) % caught_len);
  caught_beats = beats;
}


// Scope: a ring of recent OUT / AUX samples, written by the audio thread.
float scope_out[DRIFT_SCOPE_SIZE], scope_aux[DRIFT_SCOPE_SIZE];
std::atomic<uint32_t> scope_head{0};

// Engines Plaits gives their own envelope (voice.cc registers them "already
// enveloped"): 6-op FM x3, string, modal, kick, snare, hi-hat. Plaits' LPG -- and so
// its LEVEL input -- is bypassed for them, which is why holding LEVEL can't sustain them.
bool SelfEnveloped(int engine) {
  return (engine >= 2 && engine <= 4) || engine >= 19;
}
uint32_t fifo_pos = kBlock;     // empty

// Clean below 0.7 of full scale, then a smooth knee that never exceeds 1.0: loud peaks
// are rounded off without colouring everything else.
inline float SoftLimit(float x) {
  const float a = fabsf(x);
  if (a <= 0.7f) return x;
  const float y = 0.7f + 0.3f * tanhf((a - 0.7f) / 0.3f);
  return x < 0.0f ? -y : y;
}

inline float P(int i) { return params[0][i].load(std::memory_order_relaxed); }
inline int PI(int i) { return static_cast<int>(lroundf(P(i))); }
inline float PV(int v, int i) { return params[v][i].load(std::memory_order_relaxed); }
inline int PVI(int v, int i) { return static_cast<int>(lroundf(PV(v, i))); }
inline float Clamp(float x, float lo, float hi) { return x < lo ? lo : (x > hi ? hi : x); }
inline int ClampI(int x, int lo, int hi) { return x < lo ? lo : (x > hi ? hi : x); }

// Continuous controls are smoothed per block so sliders and the gyro (60 Hz) never
// zipper: about 8 ms for the timbral controls, 3 ms for pitch so the pad stays snappy.
// 1 = no smoothing.
float SmoothCoefficient(int i) {
  switch (i) {
    case DP_HARMONICS: case DP_TIMBRE: case DP_MORPH:
    case DP_FM_AMT: case DP_TIMBRE_AMT: case DP_MORPH_AMT:
    case DP_DECAY: case DP_LPG_COLOUR: case DP_LEVEL:
      return 0.03f;
    case DP_NOTE:
      return 0.08f;
    default:
      return 1.0f;
  }
}

void InitSequencer(uint32_t seed) {
  random_generator.Init(seed ? seed : 1u);
  random_stream.Init(&random_generator);
  t_generator.Init(&random_stream, kSeqRate);
  xy_generator.Init(&random_stream, kSeqRate);
  loaded_scale = -1;   // Init resets every quantizer
  t2_was = false;
}

void LoadScaleIfNeeded(int s) {
  s = ClampI(s, 0, kPadScale);
  const uint32_t v = pad_scale_version.load(std::memory_order_acquire);
  if (s == loaded_scale && (s != kPadScale || v == loaded_pad_version)) return;
  const marbles::Scale& scale = s == kPadScale
      ? pad_scales[pad_scale_live.load(std::memory_order_relaxed)]
      : marbles::preset_scales[s];
  for (int ch = 0; ch < 4; ++ch) {
    xy_generator.LoadScale(ch, 0, scale);
  }
  loaded_scale = s;
  loaded_pad_version = v;
}

marbles::VoltageRange Range(int r) {
  return r == 0 ? marbles::VOLTAGE_RANGE_NARROW
       : r == 1 ? marbles::VOLTAGE_RANGE_POSITIVE
       : marbles::VOLTAGE_RANGE_FULL;
}

float Bpm(float rate, int range) {
  const float k = range == 0 ? 0.25f : (range == 2 ? 4.0f : 1.0f);
  return 120.0f * k * exp2f(rate / 12.0f);
}

// One sequencer sample. Returns gates (bit0 t1, bit1 t2, bit2 t3), writes volts[4].
uint8_t RunSequencer(bool reset, float* volts) {
  const int range = ClampI(PI(DM_T_RANGE), 0, 2);
  t_generator.set_model(static_cast<marbles::TGeneratorModel>(ClampI(PI(DM_T_MODEL), 0, 5)));
  t_generator.set_range(static_cast<marbles::TGeneratorRange>(range));
  // Cap the master clock at 1/8 cycle per sample so it can never run away (Wakes).
  const float range_k = range == 0 ? 0.5f : (range == 2 ? 8.0f : 2.0f);
  const float max_st = 12.0f * log2f(kSeqRate * 0.125f / range_k);
  float r = P(DM_RATE);
  if (!(r <= max_st)) r = max_st;
  t_generator.set_rate(r);
  t_generator.set_bias(P(DM_T_BIAS));
  t_generator.set_jitter(P(DM_T_JITTER));
  t_generator.set_deja_vu(P(DM_T_DEJAVU));
  t_generator.set_length(ClampI(PI(DM_LENGTH), 1, 16));
  t_generator.set_pulse_width_mean(P(DM_GATE_LEN));
  t_generator.set_pulse_width_std(P(DM_GATE_RAND));

  float ramp_buffer[4];
  bool gate_buffer[2];
  stmlib::GateFlags no_clock[1] = { stmlib::GATE_FLAG_LOW };
  marbles::Ramps ramps;
  ramps.master = &ramp_buffer[0];
  ramps.external = &ramp_buffer[1];
  ramps.slave[0] = &ramp_buffer[2];
  ramps.slave[1] = &ramp_buffer[3];

  bool t_reset = reset;
  t_generator.Process(false, &t_reset, no_clock, ramps, gate_buffer, 1);

  marbles::GroupSettings x;
  x.control_mode = static_cast<marbles::ControlMode>(ClampI(PI(DM_X_DIVERSITY), 0, 2));
  x.voltage_range = Range(PI(DM_X_RANGE));
  x.register_mode = false;
  x.register_value = 0.0f;
  x.spread = P(DM_X_SPREAD);
  x.bias = P(DM_X_BIAS);
  x.steps = P(DM_X_STEPS);
  x.deja_vu = P(DM_X_DEJAVU);
  LoadScaleIfNeeded(PI(DM_X_SCALE));
  x.scale_index = 0;
  x.length = ClampI(PI(DM_LENGTH), 1, 16);
  x.ratio.p = 1;
  x.ratio.q = 1;

  marbles::GroupSettings y;
  y.control_mode = marbles::CONTROL_MODE_IDENTICAL;
  y.voltage_range = marbles::VOLTAGE_RANGE_FULL;
  y.register_mode = false;
  y.register_value = 0.0f;
  y.spread = P(DM_Y_SPREAD);
  y.bias = P(DM_Y_BIAS);
  y.steps = P(DM_Y_STEPS);
  y.deja_vu = 0.0f;
  y.scale_index = 0;
  y.length = 1;
  y.ratio = kYDividerRatios[ClampI(PI(DM_Y_DIVIDER), 0, 11)];

  bool xy_reset = reset;
  // Which t clocks the X outputs: Marbles' X clock input, minus the jack. Patching t2
  // into it on the module ("a global loop length") is option 2 here.
  static const marbles::ClockSource kXClock[4] = {
    marbles::CLOCK_SOURCE_INTERNAL_T1_T2_T3, marbles::CLOCK_SOURCE_INTERNAL_T1,
    marbles::CLOCK_SOURCE_INTERNAL_T2, marbles::CLOCK_SOURCE_INTERNAL_T3,
  };
  xy_generator.Process(kXClock[ClampI(PI(DM_X_CLOCK), 0, 3)], x, y, &xy_reset,
                       no_clock, ramps, volts, 1);

  const bool t1 = gate_buffer[0];
  const bool t3 = gate_buffer[1];
  const bool t2 = ramps.master[0] < 0.5f;
  if (t2 && !t2_was) m_beats.fetch_add(1, std::memory_order_relaxed);
  t2_was = t2;
  m_ramp.store(ramps.master[0], std::memory_order_relaxed);
  return static_cast<uint8_t>((t1 ? 1u : 0u) | (t2 ? 2u : 0u) | (t3 ? 4u : 0u));
}

// The effects chain, on one block of the mix before volume and the limiter. Each effect
// fades in and out (no clicks) and costs nothing once it has faded out; switched back
// on, it starts clean rather than replaying an old tail.
void ApplyEffects(float* l, float* r, bool running) {
  const int n = static_cast<int>(kBlock);
  const float bpm = Bpm(P(DM_RATE), ClampI(PI(DM_T_RANGE), 0, 2));
  const float beat_s = 60.0f / bpm;

  const bool ph_on = PI(FX_PH_ON) != 0;
  if (ph_on && fade_phaser.silent()) fx_phaser.Clear();
  const float ph = fade_phaser.Next(ph_on);
  if (!fade_phaser.silent()) {
    fx_phaser.Process(l, r, n, P(FX_PH_RATE), P(FX_PH_DEPTH), P(FX_PH_FEEDBACK), ph);
  }

  const bool dl_on = PI(FX_DL_ON) != 0;
  if (dl_on && fade_delay.silent()) fx_delay.Clear();
  const float dl = fade_delay.Next(dl_on);
  if (!fade_delay.silent()) {
    const float seconds = PI(FX_DL_SYNC) != 0
        ? kDelayBeats[ClampI(PI(FX_DL_DIV), 0, 7)] * beat_s
        : 0.02f * powf(100.0f, Clamp(P(FX_DL_TIME), 0.0f, 1.0f));
    fx_delay.Process(l, r, n, seconds, Clamp(P(FX_DL_FEEDBACK), 0.0f, 1.0f),
                     Clamp(P(FX_DL_TONE), 0.0f, 1.0f), Clamp(P(FX_DL_MIX), 0.0f, 1.0f),
                     PI(FX_DL_PINGPONG) != 0, dl);
  }

  const bool rv_on = PI(FX_RV_ON) != 0;
  if (rv_on && fade_reverb.silent()) fx_reverb.Clear();
  const float rv = fade_reverb.Next(rv_on);
  if (!fade_reverb.silent()) {
    fx_reverb.Process(l, r, n, Clamp(P(FX_RV_MIX), 0.0f, 1.0f), Clamp(P(FX_RV_SIZE), 0.0f, 1.0f),
                      Clamp(P(FX_RV_BRIGHT), 0.0f, 1.0f), PI(FX_RV_FREEZE) != 0, rv);
  }

  // Beat repeat: slices of the beat, on the grid when Marbles plays.
  const float per_beat = kRepeatPerBeat[ClampI(PI(FX_BR_DIV), 0, 5)];
  const int slice = static_cast<int>(beat_s / per_beat * 48000.0f);
  int since_grid = 0;
  if (running) {
    const float pos = m_ramp.load(std::memory_order_relaxed) * per_beat;
    since_grid = static_cast<int>((pos - floorf(pos)) * slice);
  }
  fx_repeat.Process(l, r, n, PI(FX_BR_HOLD) != 0, slice, since_grid);
}

void RenderBlock() {
  float mix_o[kBlock] = {}, mix_a[kBlock] = {};
  // A re-seed requested from the UI: done here, where nothing else is inside the
  // generators. Re-INIT, not just re-seed: the deja vu loop is drawn at Init.
  const uint32_t rr = reseed_req.load(std::memory_order_acquire);
  if (rr != reseed_seen) {
    reseed_seen = rr;
    const uint32_t s = reseed_val.load(std::memory_order_relaxed);
    InitSequencer(s);
    seed_now.store(s, std::memory_order_relaxed);
  }

  smooth_vol += (P(DP_VOLUME) - smooth_vol) * 0.03f;

  // ---- sequencer ----
  const bool running = PI(DM_RUN) != 0;
  uint8_t gates = 0;
  float volts[4] = { 0.0f, 0.0f, 0.0f, 0.0f };
  // Catch / release, asked for by the UI, done here between blocks.
  const uint32_t cr = catch_req.load(std::memory_order_acquire);
  if (cr != catch_seen) {
    catch_seen = cr;
    if (catch_on.load(std::memory_order_relaxed) != 0) {
      if (running) Catch(ClampI(PI(DM_LENGTH), 1, 16));
    } else {
      caught_len = 0;
      caught_beats = 0;
    }
  }
  if (running && caught_len > 0) {
    // Play the caught loop back exactly; the generators wait.
    const SeqFrame& f = history[(caught_start + caught_pos) % kHistory];
    gates = f.gates;
    for (int k = 0; k < 4; ++k) volts[k] = f.volts[k];
    m_ramp.store(f.ramp, std::memory_order_relaxed);
    const bool t2 = (gates & 2u) != 0;
    if (t2 && !t2_was) m_beats.fetch_add(1, std::memory_order_relaxed);
    t2_was = t2;
    caught_pos = (caught_pos + 1) % caught_len;
  } else if (running) {
    const bool t2_before = t2_was;
    gates = RunSequencer(!was_running, volts);
    Remember(gates, volts, m_ramp.load(std::memory_order_relaxed), t2_was && !t2_before);
  } else {
    t2_was = false;
    m_ramp.store(0.0f, std::memory_order_relaxed);
  }
  was_running = running;
  m_gates.store(gates, std::memory_order_relaxed);
  for (int k = 0; k < 4; ++k) m_volts[k].store(volts[k], std::memory_order_relaxed);

  // ---- the burst: Wakes' FFWD (shared; plays the voice the strip is set to) ----
  // While held, strike again on every 1/div of the beat. With the sequencer running the
  // grid is read off its own master clock, so a burst is an exact subdivision of the beat
  // you hear and can never drift; the first strike lands on the NEAREST grid point (fire
  // now if less than half a step has passed, else wait). Stopped, it free-runs at Rate's
  // tempo and fires on the press. It re-strikes the note -- a roll -- and never moves the
  // sequence on (Wakes, M4e).
  bool burst_fire = false, burst_high = false;
  {
    static const float kDivPerBeat[6] = { 1.0f, 2.0f, 3.0f, 4.0f, 6.0f, 8.0f };
    const bool burst = PI(DB_BURST) != 0;
    const float div = kDivPerBeat[ClampI(PI(DB_BURST_DIV), 0, 5)];
    const float bpm = Bpm(P(DM_RATE), ClampI(PI(DM_T_RANGE), 0, 2));
    if (burst) {
      if (running) {
        const float ramp = m_ramp.load(std::memory_order_relaxed);
        const float pos = ramp * div;
        const int slot = static_cast<int>(floorf(pos));
        const bool wrapped = ramp < burst_ramp_prev;   // a new beat (needed at 1/4)
        if (!burst_was) {
          burst_fire = (pos - static_cast<float>(slot)) < 0.5f;
          burst_slot = slot;
        } else if (slot != burst_slot || wrapped) {
          burst_fire = true;
          burst_slot = slot;
        }
      } else if (!burst_was) {
        burst_fire = true;
        burst_phase = 0.0f;
      } else {
        burst_phase += div * bpm / 60.0f / kSeqRate;
        if (burst_phase >= 1.0f) { burst_phase -= floorf(burst_phase); burst_fire = true; }
      }
    }
    burst_was = burst;
    burst_ramp_prev = m_ramp.load(std::memory_order_relaxed);
    if (burst_fire) {
      // High for half a step, at least half a millisecond.
      const float blocks_per_step = kSeqRate * 60.0f / (bpm * div);
      burst_gate_blocks = static_cast<int>(blocks_per_step * 0.5f);
      if (burst_gate_blocks < 2) burst_gate_blocks = 2;
    }
    burst_high = burst_gate_blocks > 0;
    if (burst_high) --burst_gate_blocks;
  }
  const int strip_voice = ClampI(PI(DB_VOICE), 0, kVoices - 1);
  const int voices = PI(DV_VOICES) >= 3 ? kVoices : 1;
  m_caught_beats.store(caught_len > 0 ? caught_beats : 0, std::memory_order_relaxed);

  for (int v = 0; v < kVoices; ++v) {
    VoiceState& st = vs[v];
    if (v >= voices) {
      st.was_sounding = false;
      continue;
    }
    if (!st.was_sounding) {            // just switched on: start from its settings
      for (int i = 0; i < DP_COUNT; ++i) st.smooth[i] = PV(v, i);
      st.hold_vca = 1.0f;
      st.chop_vca = 1.0f;
      st.presses_seen = gate_presses[v].load(std::memory_order_relaxed);
      st.was_sounding = true;
    }
    for (int i = 0; i < DP_COUNT; ++i) {
      st.smooth[i] += (PV(v, i) - st.smooth[i]) * SmoothCoefficient(i);
    }
    float* smooth = st.smooth;
    plaits::Patch& patch = st.patch;
    plaits::Modulations& mods = st.mods;

    // ---- what plays this voice ----
    // While the sequencer runs, it plays the voice. (DR_DRIVE is kept for old saves, unused.)
    const bool drive = running;
    const bool drone = PVI(v, DP_DRONE) != 0;
    const bool sustain = PVI(v, DP_SUSTAIN) != 0;
    const bool touch = gate_on[v].load(std::memory_order_relaxed) > 0;
    const uint32_t presses = gate_presses[v].load(std::memory_order_relaxed);
    bool new_edge = presses != st.presses_seen;
    st.presses_seen = presses;

    float m_note = 0.0f, m_harm = 0.0f, m_timbre = 0.0f, m_morph = 0.0f;
    float m_level = 0.0f, m_engine = 0.0f;
    bool level_routed = false;
    bool level = touch;
    bool gate_held = touch;        // finger down, or a routed Marbles gate high

    if (drive) {
      static const uint8_t kTrigMask[5] = { 1u, 2u, 4u, 5u, 0u };
      const uint8_t mask = kTrigMask[ClampI(PVI(v, DR_TRIG_SRC), 0, 4)];
      if (gates & static_cast<uint8_t>(~st.gates_prev) & mask) new_edge = true;
      level = level || (gates & mask) != 0u;
      gate_held = gate_held || (gates & mask) != 0u;

      for (int k = 0; k < 4; ++k) {
        const int dest = PVI(v, DR_X1_DEST + k);
        const float x = volts[k] * PV(v, DR_X1_DEPTH + k);
        switch (dest) {
          case DD_PITCH:     m_note += x * kVoltPerOct; break;
          case DD_HARMONICS: m_harm += x * kParamPerVolt; break;
          case DD_TIMBRE:    m_timbre += x * kParamPerVolt; break;
          case DD_MORPH:     m_morph += x * kParamPerVolt; break;
          case DD_LEVEL:     m_level += x * kParamPerVolt; level_routed = true; break;
          // Plaits' engine quantizer spans 24 engines over 0..1; +-5 V at full depth moves
          // up to 8 engines either way. Plaits itself latches it on each strike.
          case DD_ENGINE:    m_engine += x * (8.0f / (5.0f * 23.0f)); break;
          default: break;
        }
      }
    }
    st.gates_prev = gates;

    // The burst plays the strip's voice.
    if (v == strip_voice) {
      if (burst_fire) new_edge = true;
      if (burst_high) { level = true; gate_held = true; }
    }

    // ---- the strip over a drone: chop it ----
    // A drone isn't struck, so instead the strip gates it: while held at a burst speed the
    // sound pulses on and off at that rate (on for the burst's half-step, off for the
    // rest); in the Trig zone a touch gives a short dip. Each pulse also re-strikes Plaits
    // (TRIG patched, LEVEL held open so it stays continuous), so any Env -> amount accents
    // the pulses.
    const bool strip = drone && v == strip_voice && PI(DB_STRIP) != 0;
    st.strip_blocks = (strip && st.strip_was) ? st.strip_blocks + 1 : 0;
    st.strip_was = strip;
    const int kDipBlocks = static_cast<int>(0.06f * kSeqRate);   // 60 ms
    bool chop_open = true;
    if (strip) {
      chop_open = PI(DB_BURST) != 0 ? burst_high : st.strip_blocks >= kDipBlocks;
    }

    // A new strike while the trigger is already high: one low block, so Plaits sees it.
    if (new_edge && st.trig_level_prev) level = false;
    if (level && !st.trig_level_prev) m_strikes[v].fetch_add(1, std::memory_order_relaxed);
    st.trig_level_prev = level;

    patch.engine = ClampI(PVI(v, DP_ENGINE), 0, 23);
    patch.note = Clamp(smooth[DP_NOTE], 0.0f, 127.0f);
    patch.harmonics = Clamp(smooth[DP_HARMONICS] + m_harm, 0.0f, 1.0f);
    patch.timbre = Clamp(smooth[DP_TIMBRE] + m_timbre, 0.0f, 1.0f);
    patch.morph = Clamp(smooth[DP_MORPH] + m_morph, 0.0f, 1.0f);
    patch.frequency_modulation_amount = smooth[DP_FM_AMT];
    patch.timbre_modulation_amount = smooth[DP_TIMBRE_AMT];
    patch.morph_modulation_amount = smooth[DP_MORPH_AMT];
    patch.decay = smooth[DP_DECAY];
    patch.lpg_colour = smooth[DP_LPG_COLOUR];

    mods.engine = m_engine;
    mods.note = Clamp(m_note, -60.0f, 60.0f);
    mods.frequency = 0.0f;
    mods.harmonics = 0.0f;
    mods.timbre = 0.0f;
    mods.morph = 0.0f;
    mods.frequency_patched = false;
    mods.timbre_patched = false;
    mods.morph_patched = false;
    // Drone: nothing patched into TRIG, so Plaits bypasses its gate and sounds
    // continuously. The sequencer's gates are ignored then, but its voltages still move
    // pitch and timbre: Drone + Marbles is a drone that wanders.
    //
    // Hold: the note sounds for as long as the gate is held -- your finger, or a Marbles
    // gate (so Gate Length shapes the notes). Two ways, by engine:
    //   most engines      LEVEL held open, through Plaits' own low-pass gate (Colour and
    //                     Decay shape it, as on the module)
    //   self-enveloped    Plaits bypasses its gate for these, so they are run unpatched
    //                     (continuously excited, as with TRIG unplugged) and our own
    //                     gate opens and closes them, releasing over Decay
    const bool hold = sustain && !drone;
    const int engine_now = st.voice.active_engine() >= 0 ? st.voice.active_engine() : patch.engine;
    m_engines[v].store(engine_now, std::memory_order_relaxed);
    const bool own_gate = hold && SelfEnveloped(engine_now);
    // Chiptune, once struck, is an arpeggiator with its own envelope whose length is the
    // Env -> Timbre amount; at 0 it never decays (the module does the same). Our gate
    // closes it when the note is let go, fading over Decay, in every mode but Drone.
    const bool chip_gate = engine_now == 7 && !drone;
    mods.trigger_patched = (!drone && !own_gate) || strip;
    mods.trigger = strip ? (chop_open ? 1.0f : 0.0f) : (level ? 1.0f : 0.0f);
    mods.level_patched = level_routed || (hold && !own_gate) || strip;
    mods.level = level_routed ? Clamp(m_level + (hold && gate_held ? 1.0f : 0.0f), 0.0f, 1.0f)
                              : (strip ? 1.0f : (gate_held ? 1.0f : 0.0f));
    // Attack 3 ms; release 20 ms .. 3 s with Decay.
    const float vca_target = (own_gate || chip_gate) ? (gate_held ? 1.0f : 0.0f) : 1.0f;
    const float release_s = 0.02f * powf(150.0f, smooth[DP_DECAY]);
    const float vca_coef = vca_target > st.hold_vca ? 1.0f - expf(-1.0f / (0.003f * 48000.0f))
                                                    : 1.0f - expf(-1.0f / (release_s * 48000.0f));

    st.voice.Render(patch, mods, st.frames, kBlock);

    // Into the mix, at this voice's level.
    const float lvl = Clamp(smooth[DP_LEVEL], 0.0f, 1.0f);
    for (uint32_t i = 0; i < kBlock; ++i) {
      st.hold_vca += (vca_target - st.hold_vca) * vca_coef;
      // 2 ms each way: a clean chop, no clicks.
      st.chop_vca += ((chop_open ? 1.0f : 0.0f) - st.chop_vca) * 0.0104f;
      const float g = st.hold_vca * st.chop_vca * lvl;
      mix_o[i] += st.frames[i].out / 32768.0f * g;
      mix_a[i] += st.frames[i].aux / 32768.0f * g;
    }
  }

  // ---- output select, volume, a soft ceiling ----
  const int mode = ClampI(PI(DP_OUTPUT), 0, 3);
  // Plaits peaks at about 0.6 of full scale: makeup gain brings 80 (the default) to
  // about x1.4, loud engines peaking near 0.85; 100 is x2.2 and pushes into the limiter.
  // Squared, so the slider's lower half gives finer control. Several voices sum before
  // the limiter, which keeps the kit from clipping.
  const float vol = 2.2f * smooth_vol * smooth_vol;
  float l[kBlock], r[kBlock];
  for (uint32_t i = 0; i < kBlock; ++i) {
    const float o = mix_o[i];
    const float a = mix_a[i];
    switch (mode) {
      case 1: l[i] = r[i] = a; break;
      case 2: l[i] = r[i] = (o + a) * 0.71f; break;
      case 3: l[i] = o; r[i] = a; break;
      default: l[i] = r[i] = o; break;
    }
    {
      const uint32_t h = scope_head.load(std::memory_order_relaxed);
      scope_out[h] = o;
      scope_aux[h] = a;
      scope_head.store((h + 1) % DRIFT_SCOPE_SIZE, std::memory_order_release);
    }
  }

  ApplyEffects(l, r, running);

  float peak = m_peak.load(std::memory_order_relaxed) * 0.995f;
  for (uint32_t i = 0; i < kBlock; ++i) {
    out_l[i] = SoftLimit(l[i] * vol);
    out_r[i] = SoftLimit(r[i] * vol);
    const float p = fabsf(out_l[i]) > fabsf(out_r[i]) ? fabsf(out_l[i]) : fabsf(out_r[i]);
    if (p > peak) peak = p;
  }
  m_peak.store(peak, std::memory_order_relaxed);
}

void Defaults() {
  float d[DP_COUNT] = {};
  d[DP_ENGINE] = 8;            // virtual analog
  d[DP_NOTE] = 48;
  d[DP_HARMONICS] = 0.5f;
  d[DP_TIMBRE] = 0.5f;
  d[DP_MORPH] = 0.5f;
  d[DP_DECAY] = 0.5f;
  d[DP_LPG_COLOUR] = 0.5f;
  d[DP_VOLUME] = 0.8f;
  d[DP_LEVEL] = 1.0f;
  d[DM_T_RANGE] = 1;
  d[DM_T_BIAS] = 0.5f;
  d[DM_GATE_LEN] = 0.5f;
  d[DM_LENGTH] = 8;
  d[DM_X_SPREAD] = 0.5f;
  d[DM_X_BIAS] = 0.5f;
  d[DM_X_STEPS] = 0.7f;
  d[DM_X_RANGE] = 0;
  d[DM_Y_SPREAD] = 0.5f;
  d[DM_Y_BIAS] = 0.5f;
  d[DM_Y_DIVIDER] = 4;          // 1/16 of X2, as the module
  d[DR_DRIVE] = 1;
  d[DR_TRIG_SRC] = 3;           // t1 + t3: in Coin Toss, a note on every beat
  d[DR_X1_DEST] = DD_PITCH;
  d[DR_X1_DEPTH] = 1.0f;
  d[DR_X2_DEPTH] = 0.5f;
  d[DR_X3_DEPTH] = 0.5f;
  d[DR_Y_DEPTH] = 0.5f;
  d[DV_VOICES] = 1;
  d[FX_PH_RATE] = 0.3f;
  d[FX_PH_DEPTH] = 0.7f;
  d[FX_PH_FEEDBACK] = 0.5f;
  d[FX_DL_SYNC] = 1;
  d[FX_DL_DIV] = 3;             // dotted 1/8
  d[FX_DL_TIME] = 0.45f;
  d[FX_DL_FEEDBACK] = 0.4f;
  d[FX_DL_TONE] = 0.6f;
  d[FX_DL_MIX] = 0.35f;
  d[FX_DL_PINGPONG] = 1;
  d[FX_RV_MIX] = 0.35f;
  d[FX_RV_SIZE] = 0.5f;
  d[FX_RV_BRIGHT] = 0.6f;
  d[FX_BR_DIV] = 3;             // 1/16
  for (int v = 0; v < kVoices; ++v) {
    for (int i = 0; i < DP_COUNT; ++i) params[v][i].store(d[i], std::memory_order_relaxed);
  }
  // Voices 2 and 3 start as a snare on t3 and a hi-hat on t2, not following the melody.
  params[1][DP_ENGINE].store(22); params[1][DR_TRIG_SRC].store(2); params[1][DR_X1_DEST].store(DD_NONE);
  params[2][DP_ENGINE].store(23); params[2][DR_TRIG_SRC].store(1); params[2][DR_X1_DEST].store(DD_NONE);
}

}  // namespace

extern "C" void drift_init(void) {
  if (initialised) return;
  Defaults();
  for (int v = 0; v < kVoices; ++v) {
    stmlib::BufferAllocator allocator(vs[v].arena, sizeof(vs[v].arena));
    vs[v].voice.Init(&allocator);
    std::memset(&vs[v].patch, 0, sizeof(vs[v].patch));
    std::memset(&vs[v].mods, 0, sizeof(vs[v].mods));
  }
  fx_reverb.Init();
  pad_scales[0] = marbles::preset_scales[0];
  pad_scales[1] = marbles::preset_scales[0];
  InitSequencer(1u);
  initialised = true;
}

extern "C" int drift_is_per_voice(drift_param p) {
  switch (p) {
    case DP_ENGINE: case DP_NOTE: case DP_HARMONICS: case DP_TIMBRE: case DP_MORPH:
    case DP_FM_AMT: case DP_TIMBRE_AMT: case DP_MORPH_AMT: case DP_DECAY: case DP_LPG_COLOUR:
    case DP_DRONE: case DP_SUSTAIN: case DP_LEVEL:
    case DR_TRIG_SRC: case DR_X1_DEST: case DR_X2_DEST: case DR_X3_DEST: case DR_Y_DEST:
    case DR_X1_DEPTH: case DR_X2_DEPTH: case DR_X3_DEPTH: case DR_Y_DEPTH:
      return 1;
    default:
      return 0;
  }
}

extern "C" void drift_set_v(int voice, drift_param p, float value) {
  if (p < 0 || p >= DP_COUNT || !std::isfinite(value)) return;
  if (voice < 0 || voice >= kVoices || !drift_is_per_voice(p)) voice = 0;
  params[voice][p].store(value, std::memory_order_relaxed);
}

extern "C" float drift_get_v(int voice, drift_param p) {
  if (p < 0 || p >= DP_COUNT) return 0.0f;
  if (voice < 0 || voice >= kVoices || !drift_is_per_voice(p)) voice = 0;
  return params[voice][p].load(std::memory_order_relaxed);
}

extern "C" void drift_set(drift_param p, float value) { drift_set_v(0, p, value); }
extern "C" float drift_get(drift_param p) { return drift_get_v(0, p); }

extern "C" void drift_gate_v(int voice, int on) {
  if (voice < 0 || voice >= kVoices) return;
  if (on) {
    gate_on[voice].fetch_add(1, std::memory_order_relaxed);
    gate_presses[voice].fetch_add(1, std::memory_order_relaxed);
  } else {
    int32_t n = gate_on[voice].load(std::memory_order_relaxed);
    while (n > 0 && !gate_on[voice].compare_exchange_weak(n, n - 1, std::memory_order_relaxed)) {}
  }
}

extern "C" void drift_strike_v(int voice) {
  if (voice < 0 || voice >= kVoices) return;
  gate_presses[voice].fetch_add(1, std::memory_order_relaxed);
}

extern "C" void drift_gate(int on) { drift_gate_v(0, on); }
extern "C" void drift_strike(void) { drift_strike_v(0); }

extern "C" void drift_gate_reset(void) {
  for (int v = 0; v < kVoices; ++v) gate_on[v].store(0, std::memory_order_relaxed);
}

extern "C" void drift_set_pad_scale(const float* semitones, const uint8_t* weights, int count) {
  if (count < 1) return;
  if (count > static_cast<int>(marbles::kMaxDegrees)) count = marbles::kMaxDegrees;
  const uint32_t next = pad_scale_live.load(std::memory_order_relaxed) ^ 1u;
  marbles::Scale& sc = pad_scales[next];
  sc.base_interval = 1.0f;
  sc.num_degrees = count;
  for (int i = 0; i < count; ++i) {
    sc.degree[i].voltage = semitones[i] / 12.0f;
    sc.degree[i].weight = weights[i];
  }
  pad_scale_live.store(next, std::memory_order_relaxed);
  pad_scale_version.fetch_add(1, std::memory_order_release);
}

extern "C" void drift_catch(int on) {
  catch_on.store(on ? 1u : 0u, std::memory_order_relaxed);
  catch_req.fetch_add(1, std::memory_order_release);
}

extern "C" void drift_reseed(uint32_t seed) {
  reseed_val.store(seed ? seed : 1u, std::memory_order_relaxed);
  reseed_req.fetch_add(1, std::memory_order_release);
}

extern "C" uint32_t drift_seed(void) {
  return seed_now.load(std::memory_order_relaxed);
}

extern "C" void drift_meters_read(drift_meters* out) {
  out->gates = static_cast<uint8_t>(m_gates.load(std::memory_order_relaxed));
  for (int k = 0; k < 4; ++k) out->volts[k] = m_volts[k].load(std::memory_order_relaxed);
  out->ramp = m_ramp.load(std::memory_order_relaxed);
  out->beats = m_beats.load(std::memory_order_relaxed);
  out->strikes = m_strikes[0].load(std::memory_order_relaxed);
  for (int v = 0; v < kVoices; ++v) {
    out->engines[v] = m_engines[v].load(std::memory_order_relaxed);
    out->voice_strikes[v] = m_strikes[v].load(std::memory_order_relaxed);
  }
  out->peak = m_peak.load(std::memory_order_relaxed);
  out->bpm = Bpm(params[0][DM_RATE].load(), static_cast<int>(lroundf(params[0][DM_T_RANGE].load())));
  out->engine = m_engines[0].load(std::memory_order_relaxed);
  out->caught_beats = m_caught_beats.load(std::memory_order_relaxed);
}

extern "C" void drift_scope_read(float* out, float* aux, int count) {
  if (count > DRIFT_SCOPE_SIZE) count = DRIFT_SCOPE_SIZE;
  const uint32_t head = scope_head.load(std::memory_order_acquire);
  for (int i = 0; i < count; ++i) {
    const uint32_t k = (head + DRIFT_SCOPE_SIZE - count + i) % DRIFT_SCOPE_SIZE;
    out[i] = scope_out[k];
    aux[i] = scope_aux[k];
  }
}

extern "C" void drift_render(float* left, float* right, uint32_t n) {
  if (!initialised) {
    std::memset(left, 0, n * sizeof(float));
    std::memset(right, 0, n * sizeof(float));
    return;
  }
  for (uint32_t i = 0; i < n; ++i) {
    if (fifo_pos >= kBlock) {
      RenderBlock();
      fifo_pos = 0;
    }
    left[i] = out_l[fifo_pos];
    right[i] = out_r[fifo_pos];
    ++fifo_pos;
  }
}
