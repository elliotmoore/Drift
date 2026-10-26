// Drift — C interface to the voice (Plaits DSP) and the random sequencer (Marbles'
// t and X/Y generators), both by Emilie Gillet / Mutable Instruments, MIT licence,
// vendored unmodified in DSP/third_party. Glue modelled on Worldwave's Wakes (MIT).
//
// Threads:
//   drift_init()            main thread, once, before audio starts
//   drift_render()          audio thread only
//   everything else         any thread; lock-free (atomics), read once per Plaits block
#ifndef DRIFT_ENGINE_H
#define DRIFT_ENGINE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Every continuous or discrete control, addressed by index. Values are in the units
// noted; discrete values are passed as floats and rounded.
typedef enum {
  // ---- voice ----
  DP_ENGINE = 0,      // 0..23, Plaits engine index (voice.cc registration order)
  DP_NOTE,            // MIDI semitones, 0..127
  DP_HARMONICS,       // 0..1
  DP_TIMBRE,          // 0..1
  DP_MORPH,           // 0..1
  DP_FM_AMT,          // -1..1  envelope -> pitch (Plaits' FM attenuverter)
  DP_TIMBRE_AMT,      // -1..1  envelope -> timbre
  DP_MORPH_AMT,       // -1..1  envelope -> morph
  DP_DECAY,           // 0..1
  DP_LPG_COLOUR,      // 0..1
  DP_VOLUME,          // 0..1
  DP_OUTPUT,          // 0 out, 1 aux, 2 out+aux, 3 split (out L / aux R)
  DP_DRONE,           // 0/1  no trigger: the voice sounds continuously
  DP_SUSTAIN,         // 0/1  touch holds the gate open (VCA) instead of a strike

  // ---- random sequencer: t ----
  DM_RUN,             // 0/1
  DM_RATE,            // semitones around 120 BPM, -48..+48
  DM_T_RANGE,         // 0 x1/4, 1 x1, 2 x4
  DM_T_MODEL,         // 0..5 coin toss, clusters, drums, independent, divider, three states
  DM_T_BIAS,          // 0..1
  DM_T_JITTER,        // 0..1
  DM_T_DEJAVU,        // 0..1
  DM_GATE_LEN,        // 0..1
  DM_GATE_RAND,       // 0..1
  DM_LENGTH,          // 1..16 steps in the deja vu loop

  // ---- random sequencer: X and Y ----
  DM_X_SPREAD,        // 0..1
  DM_X_BIAS,          // 0..1
  DM_X_STEPS,         // 0..1
  DM_X_DEJAVU,        // 0..1
  DM_X_DIVERSITY,     // 0 identical, 1 bump, 2 tilt
  DM_X_RANGE,         // 0 0..2 V, 1 0..5 V, 2 -5..+5 V
  DM_X_SCALE,         // 0..5 major, minor, pentatonic, pelog, bhairav, shri; 6 = the pad's
  DM_Y_SPREAD,        // 0..1
  DM_Y_BIAS,          // 0..1
  DM_Y_STEPS,         // 0..1
  DM_Y_DIVIDER,       // 0..11 -> 1/64 ... 1/1 of t2

  // ---- the sequencer playing the voice ----
  DR_DRIVE,           // 0/1  the sequencer plays the voice while it runs
  DR_TRIG_SRC,        // 0 t1, 1 t2, 2 t3, 3 t1+t3, 4 none
  DR_X1_DEST,         // enum drift_dest
  DR_X2_DEST,
  DR_X3_DEST,
  DR_Y_DEST,
  DR_X1_DEPTH,        // -1..1
  DR_X2_DEPTH,
  DR_X3_DEPTH,
  DR_Y_DEPTH,

  DM_X_CLOCK,         // 0 each X on its own t (X1 t1, X2 t2, X3 t3), 1 all on t1, 2 t2, 3 t3

  // ---- Wakes' burst (the SP-1's FFWD) ----
  DB_BURST,           // 0/1 held: re-strike at the division below
  DB_BURST_DIV,       // 0 1/4, 1 1/8, 2 1/8T, 3 1/16, 4 1/16T, 5 1/32 of a beat
  DB_STRIP,           // 0/1 a finger is on the burst strip: chops a drone
  DB_VOICE,           // 0..2 which voice the burst strip plays

  // ---- voices ----
  DV_VOICES,          // 1 or 3 voices sounding
  DP_LEVEL,           // 0..1 per voice: its level in the mix

  // ---- effects, shared, on the whole mix: phaser -> delay -> reverb -> beat repeat ----
  FX_PH_ON,           // 0/1
  FX_PH_RATE,         // 0..1  0.03..6 Hz
  FX_PH_DEPTH,        // 0..1
  FX_PH_FEEDBACK,     // 0..1
  FX_DL_ON,           // 0/1
  FX_DL_SYNC,         // 0/1  time from Marbles' tempo (FX_DL_DIV) or free (FX_DL_TIME)
  FX_DL_DIV,          // 0..7 1/16, 1/8T, 1/8, 1/8 dotted, 1/4, 1/4 dotted, 1/2, 1 bar
  FX_DL_TIME,         // 0..1  20 ms..2 s
  FX_DL_FEEDBACK,     // 0..1
  FX_DL_TONE,         // 0..1  dark..bright
  FX_DL_MIX,          // 0..1
  FX_DL_PINGPONG,     // 0/1
  FX_RV_ON,           // 0/1  Rings' reverb
  FX_RV_MIX,          // 0..1
  FX_RV_SIZE,         // 0..1
  FX_RV_BRIGHT,       // 0..1
  FX_RV_FREEZE,       // 0/1  hold the tail (Elements' freeze)
  FX_BR_HOLD,         // 0/1  held: repeat the current slice
  FX_BR_DIV,          // 0..5 slice 1/4, 1/8, 1/8T, 1/16, 1/16T, 1/32 of a beat

  DP_COUNT
} drift_param;

typedef enum {
  DD_NONE = 0,
  DD_PITCH,
  DD_HARMONICS,
  DD_TIMBRE,
  DD_MORPH,
  DD_LEVEL,
  DD_ENGINE,          // Plaits' MODEL input: changes engine on each strike
  DD_COUNT
} drift_dest;

// Up to three Plaits voices, each with its own copy of the per-voice controls (engine,
// pitch, the timbre sliders, envelope, Drone, Hold, Level, Triggers and the X/Y routes).
// drift_set / drift_get / drift_gate act on voice 0; the _v versions take a voice.
// Everything else (Marbles, Volume, Output, the burst, the effects) is shared.
#define DRIFT_VOICES 3
int drift_is_per_voice(drift_param p);

// Live values for the UI, updated once per Plaits block.
typedef struct {
  uint8_t gates;      // bit0 t1, bit1 t2, bit2 t3
  float volts[4];     // X1, X2, X3, Y in volts
  float ramp;         // master clock phase 0..1
  uint32_t beats;     // t2 rising edges since start
  uint32_t strikes;   // voice trigger edges since start
  float peak;         // output peak 0..1 (decaying)
  float bpm;
  int engine;         // voice 0's engine actually playing (Marbles can change it)
  int caught_beats;   // 0, or how many beats long the caught loop is
  int engines[DRIFT_VOICES];          // each voice's engine actually playing
  uint32_t voice_strikes[DRIFT_VOICES];  // strikes per voice since start
} drift_meters;

void drift_init(void);
void drift_set(drift_param p, float value);
float drift_get(drift_param p);
void drift_set_v(int voice, drift_param p, float value);
float drift_get_v(int voice, drift_param p);

// A finger down (on) or up (off) on any play surface. Counted, so several surfaces can
// hold the gate at once and releasing one doesn't cut the others. Each "on" strikes.
void drift_gate(int on);
// Strike again without changing who is holding the gate (a new note while sliding).
void drift_strike(void);
void drift_gate_v(int voice, int on);
void drift_strike_v(int voice);
// Release every held gate (app going to the background, a lost touch).
void drift_gate_reset(void);

// The scale DM_X_SCALE = 6 uses: semitones above the voice's current note, ascending,
// 0 <= s < 12, each with a weight (255 = most likely). Up to 16. Any thread.
void drift_set_pad_scale(const float* semitones, const uint8_t* weights, int count);

// Catch: loop what the sequencer just played -- the last Loop Length beats of every gate
// and every X/Y value, Y included -- exactly, until released. The generators pause while
// a loop is caught. on = catch now (needs the sequencer running), off = let go.
void drift_catch(int on);

// New random seed for the sequencer. Safe while running; takes effect next block.
void drift_reseed(uint32_t seed);
uint32_t drift_seed(void);

void drift_meters_read(drift_meters* out);

// The last `count` samples (up to DRIFT_SCOPE_SIZE) of Plaits' OUT and AUX, before the
// output stage, for the Scope. Any thread; a torn read only means one odd frame.
#define DRIFT_SCOPE_SIZE 8192
void drift_scope_read(float* out, float* aux, int count);

// AUDIO THREAD. Non-interleaved stereo float at 48 kHz, any frame count.
void drift_render(float* left, float* right, uint32_t frames);

#ifdef __cplusplus
}
#endif

#endif  // DRIFT_ENGINE_H
