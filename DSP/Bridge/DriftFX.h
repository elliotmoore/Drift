// Drift — the effects on the whole mix: Phaser -> Delay -> Reverb -> Beat Repeat.
// Included once, by DriftEngine.cpp; runs on the audio thread only.
//
// The reverb is Mutable Instruments' (Rings, vendored unmodified in DSP/third_party/rings,
// MIT, Emilie Gillet), set up as Rings and Elements set it up. The phaser, delay and beat
// repeat are Drift's own (MIT). Everything takes and gives samples around +-1.

#ifndef DRIFT_FX_H
#define DRIFT_FX_H

#include <algorithm>
#include <cmath>
#include <cstring>

#include "rings/dsp/fx/reverb.h"

namespace drift_fx {

const float kRate = 48000.0f;
const float kTwoPi = 6.28318530718f;

inline float SoftClip(float x) {          // gentle, for feedback paths
  return x / (1.0f + fabsf(x) * 0.25f);
}

// A smoothed 0..1 "how much of this effect" so switching it on or off never clicks.
struct Fade {
  float v = 0.0f;
  float Next(bool on) { v += ((on ? 1.0f : 0.0f) - v) * 0.0025f; return v; }   // ~8 ms
  bool silent() const { return v < 1e-4f; }
};

// ---- Phaser: six first-order allpasses swept by a sine LFO, with feedback ----
class Phaser {
 public:
  void Clear() { std::memset(this, 0, sizeof(*this)); }

  // rate 0..1 (0.03..6 Hz), depth 0..1, feedback 0..1; amount 0..1 fades it in.
  void Process(float* l, float* r, int n, float rate, float depth, float feedback, float amount) {
    const float hz = 0.03f * powf(200.0f, rate);
    phase_ += hz * n / kRate;
    phase_ -= floorf(phase_);
    // The two sides sweep a quarter-cycle apart, for width.
    const float sweep_l = sinf(kTwoPi * phase_);
    const float sweep_r = sinf(kTwoPi * (phase_ + 0.25f));
    const float a_l = Coefficient(800.0f * powf(8.0f, depth * sweep_l));
    const float a_r = Coefficient(800.0f * powf(8.0f, depth * sweep_r));
    const float fb = feedback * 0.85f;
    for (int i = 0; i < n; ++i) {
      l[i] += (Stages(l[i], a_l, fb, ap_l_, last_l_) - l[i]) * amount;
      r[i] += (Stages(r[i], a_r, fb, ap_r_, last_r_) - r[i]) * amount;
    }
  }

 private:
  static float Coefficient(float hz) {
    const float t = tanf(3.14159265f * std::min(hz, 18000.0f) / kRate);
    return (t - 1.0f) / (t + 1.0f);
  }

  // Dry plus the allpass chain: where they're out of phase, notches appear.
  static float Stages(float x, float a, float fb, float* z, float& last) {
    float y = x + SoftClip(last * fb);
    for (int k = 0; k < 6; ++k) {
      const float out = a * y + z[k];
      z[k] = y - a * out;
      y = out;
    }
    last = y;
    return (x + y) * 0.6f;
  }

  float phase_;
  float ap_l_[6], ap_r_[6];
  float last_l_, last_r_;
};

// ---- Delay: stereo or ping-pong, synced to the beat or free, with a tone control ----
class Delay {
 public:
  static const int kSize = 4 * 48000;          // 4 s per side

  void Clear() {
    std::memset(buf_l_, 0, sizeof(buf_l_));
    std::memset(buf_r_, 0, sizeof(buf_r_));
    lp_l_ = lp_r_ = 0.0f;
  }

  // seconds: the delay time; feedback 0..1; tone 0..1 (dark..bright); mix 0..1.
  void Process(float* l, float* r, int n, float seconds, float feedback, float tone,
               float mix, bool ping_pong, float amount) {
    const float target = std::min(std::max(seconds * kRate, 16.0f), static_cast<float>(kSize - 4));
    if (time_ <= 0.0f) time_ = target;
    const float fb = feedback * 0.95f;
    const float coef = 1.0f - expf(-kTwoPi * (700.0f * powf(20.0f, tone)) / kRate);
    for (int i = 0; i < n; ++i) {
      time_ += (target - time_) * 0.0004f;      // glides, like tape, when the time changes
      const float dl = Read(buf_l_, time_);
      const float dr = Read(buf_r_, time_);
      lp_l_ += (dl - lp_l_) * coef;
      lp_r_ += (dr - lp_r_) * coef;
      float in_l, in_r;
      if (ping_pong) {                           // in on the left, then back and forth
        in_l = (l[i] + r[i]) * 0.5f * amount + SoftClip(lp_r_ * fb);
        in_r = SoftClip(lp_l_ * fb);
      } else {
        in_l = l[i] * amount + SoftClip(lp_l_ * fb);
        in_r = r[i] * amount + SoftClip(lp_r_ * fb);
      }
      buf_l_[head_] = in_l;
      buf_r_[head_] = in_r;
      head_ = (head_ + 1) % kSize;
      l[i] += dl * mix * amount;
      r[i] += dr * mix * amount;
    }
  }

 private:
  float Read(const float* buf, float delay) const {
    float pos = static_cast<float>(head_) - delay;
    while (pos < 0.0f) pos += kSize;
    const int i = static_cast<int>(pos);
    const float f = pos - i;
    const float a = buf[i % kSize];
    const float b = buf[(i + 1) % kSize];
    return a + (b - a) * f;
  }

  float buf_l_[kSize], buf_r_[kSize];
  int head_ = 0;
  float time_ = 0.0f;
  float lp_l_ = 0.0f, lp_r_ = 0.0f;
};

// ---- Reverb: Rings' (Griesinger/Dattorro), with Elements' freeze ----
class Reverb {
 public:
  void Init() { reverb_.Init(buffer_); }
  void Clear() { reverb_.Clear(); }

  // mix 0..1, size 0..1, brightness 0..1, freeze: hold the tail and take no new input.
  void Process(float* l, float* r, int n, float mix, float size, float brightness,
               bool freeze, float amount) {
    reverb_.set_amount(mix * amount);
    reverb_.set_diffusion(0.625f);
    if (freeze) {
      reverb_.set_time(1.0f);
      reverb_.set_input_gain(0.0f);
      reverb_.set_lp(1.0f);
    } else {
      reverb_.set_time(0.35f + 0.63f * size);       // Rings' range
      reverb_.set_input_gain(0.2f);
      reverb_.set_lp(0.3f + 0.6f * brightness);
    }
    reverb_.Process(l, r, n);
  }

 private:
  uint16_t buffer_[32768];
  rings::Reverb reverb_;
};

// ---- Beat Repeat: hold to loop the current slice of the beat ----
// The slice starts on the last grid point (1/div of a beat). Until the slice is full you
// hear it live as it's recorded; then it repeats until you let go.
class BeatRepeat {
 public:
  static const int kSize = 4 * 48000;

  void Clear() { std::memset(this, 0, sizeof(*this)); }

  // hold: a finger is down; slice: samples per repeat; since_grid: samples since the last
  // grid point when the hold starts (0 when Marbles is stopped).
  void Process(float* l, float* r, int n, bool hold, int slice, int since_grid) {
    slice = std::min(std::max(slice, 96), kSize);
    if (hold && (!holding_ || slice != slice_)) Start(slice, since_grid);
    holding_ = hold;
    for (int i = 0; i < n; ++i) {
      ring_l_[head_] = l[i];
      ring_r_[head_] = r[i];
      head_ = (head_ + 1) % kSize;
      mix_ += ((hold ? 1.0f : 0.0f) - mix_) * 0.004f;
      if (mix_ < 1e-4f) continue;
      float rl, rr;
      if (t_ < slice_) {                         // still recording the slice: live
        slice_l_[t_] = l[i];
        slice_r_[t_] = r[i];
        rl = l[i];
        rr = r[i];
      } else {
        const int k = t_ % slice_;
        // A 1.5 ms dip at each repeat, so the loop points don't click.
        const float edge = std::min(1.0f, std::min(k, slice_ - 1 - k) / 72.0f);
        rl = slice_l_[k] * edge;
        rr = slice_r_[k] * edge;
      }
      if (hold) ++t_;
      l[i] += (rl - l[i]) * mix_;
      r[i] += (rr - r[i]) * mix_;
    }
  }

 private:
  void Start(int slice, int since_grid) {
    since_grid = std::min(std::max(since_grid, 0), slice);
    // The part of the slice already played goes in from the ring.
    for (int k = 0; k < since_grid; ++k) {
      const int p = (head_ - since_grid + k + kSize) % kSize;
      slice_l_[k] = ring_l_[p];
      slice_r_[k] = ring_r_[p];
    }
    slice_ = slice;
    t_ = since_grid;
  }

  float ring_l_[kSize], ring_r_[kSize];
  float slice_l_[kSize], slice_r_[kSize];
  int head_;
  int slice_;
  int t_;
  bool holding_;
  float mix_;
};

}  // namespace drift_fx

#endif  // DRIFT_FX_H
