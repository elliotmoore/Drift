import SwiftUI

// The in-app Guide. This file is the single source for it: every release that changes
// what the app does updates the topic it touches and adds a What's New entry
// (see CLAUDE.md, "Releases").

struct GuideTopic: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let summary: String
    let body: [GuideBlock]
}

enum GuideBlock {
    case text(String)                 // a paragraph; **bold** and *italic* work
    case heading(String)
    case items([(String, String)])    // term, explanation
    case table([String], [[String]])  // header, rows
    case tip(String)
}

enum Guide {
    static let topics: [GuideTopic] = [
        GuideTopic(
            id: "start", title: "How It Fits Together", symbol: "point.3.connected.trianglepath.dotted",
            summary: "Plaits makes the sound. You, Drone or Marbles play it.",
            body: [
                .text("Drift is two instruments from Mutable Instruments, rebuilt from their original code: **Plaits**, a voice with 24 ways of making sound, and **Marbles**, a random sequencer that invents rhythms and melodies."),
                .text("**Plaits never plays by itself.** Something has to play it, and there are three ways:"),
                .items([
                    ("You", "Touch the pad. Each touch strikes a note."),
                    ("Drone", "The sound keeps going with nobody playing it."),
                    ("Marbles", "Its rhythm strikes the notes and its melody chooses the pitches."),
                ]),
                .text("Drone and Marbles combine:"),
                .table(["", "Marbles stopped", "Marbles playing"], [
                    ["Drone off", "You play the pad", "Marbles plays notes"],
                    ["Drone on", "A steady drone", "A drone that Marbles moves around, with no strikes"],
                ]),
                .text("The pad works in every case. With Marbles or Drone going, touching it sets the pitch everything is built on, so it transposes what you hear."),
                .tip("The quickest way in: pick an engine, tap ▶ Marbles, then move Timbre and Morph while it plays."),
            ]),

        GuideTopic(
            id: "plaits", title: "Plaits", symbol: "waveform",
            summary: "Engines, the four main sliders, and the envelope.",
            body: [
                .heading("Engines"),
                .text("The row of chips at the top picks one of 24 engines: analog-style oscillators, FM, formants, chords, speech, noise, physical models of strings and bells, and drums. Each is a different instrument."),
                .heading("The main sliders"),
                .items([
                    ("Pitch", "The note everything is built on. The pad sets it when you play."),
                    ("Harmonics, Timbre, Morph", "The three controls of the current engine. What they do changes with every engine, and the grey text under each slider says what it does right now."),
                ]),
                .heading("The envelope"),
                .text("Every strike starts a short envelope, a quick rise and fall. These shape it:"),
                .items([
                    ("Decay", "How long a struck note rings."),
                    ("Colour", "Low: notes darken as they fade, like a filter closing. High: they just get quieter."),
                    ("Env → Timbre, Morph, Pitch", "How much each strike pushes that control. Middle is off; either side pushes up or down. This is what makes a plucked FM bell or a laser zap."),
                ]),
                .text("**Volume** is the output level. Up to about 80 it's clean; higher, a limiter rounds off the loudest peaks."),
                .tip("Long-press any slider for a short explanation, to reset it, or to give it to motion. Double-tap a slider to reset it."),
            ]),

        GuideTopic(
            id: "voices", title: "Three Voices", symbol: "circle.grid.3x3.circle",
            summary: "A small kit: three Plaits, each played by its own Marbles rhythm.",
            body: [
                .text("Plaits plays one sound at a time. To play a beat, Eurorack players use one voice per drum, with Marbles' three rhythms (t1, t2, t3) playing them. Drift can do the same."),
                .text("Tap the **Plaits ⌄** title and choose **Three Voices**. A switcher appears: **1 · 2 · 3**, each showing its engine, with a dot that flashes when it plays. Tap one to see and change it."),
                .items([
                    ("Each voice has its own", "Engine, Pitch, Harmonics, Timbre, Morph, envelope, Drone, Hold and **Level** (its share of the mix, in place of Volume). On the Marbles page, Routing has the same switcher: each voice has its own **Triggers** and its own X and Y routes."),
                    ("Voice 1", "Is the voice you already had."),
                    ("Voices 2 and 3", "Start as a Snare played by t3 and a Hi-Hat played by t2. Change them to anything."),
                    ("Playing by hand", "The pad and touching the Scope play whichever voice is selected."),
                ]),
                .tip("For a beat: set Voice 1 to Kick with Triggers on t1, then on Marbles' Clock tab choose the **Drums** model and press Play."),
                .text("Choose **One Voice** to go back to a single Plaits. Voices 2 and 3 keep their settings for next time."),
            ]),

        GuideTopic(
            id: "pad", title: "The Pad", symbol: "pianokeys",
            summary: "Playing, scales, Hold, and what up and down does.",
            body: [
                .text("Left to right is pitch, locked to a scale so every note fits. The lighter columns are the key note."),
                .items([
                    ("↕ label (top left)", "What moving your finger up and down controls. Tap it to choose. **Follow Last Touched** (the default) hands up and down to whichever Plaits slider you last moved."),
                    ("♪ label (top right)", "The pad's key and scale, its range, and the output (Main, Aux, Mix, or Split: main on the left, aux on the right)."),
                    ("Hold", "Notes sound for as long as they are held instead of plucking: your finger on the pad, or each Marbles gate (so **Gate Length** sets how long Marbles' notes last). When released, they fade over **Decay**. Sliding along the pad glides between notes instead of restriking. Works on every engine, including the strings, bells, drums and 6-op FM, which normally ring out on their own."),
                    ("Drone", "Keeps the sound going. Hold does nothing while Drone is on."),
                ]),
                .tip("Marbles can use the pad's scale too: choose Same as Pad on the Marbles X tab."),
            ]),

        GuideTopic(
            id: "marbles", title: "Marbles", symbol: "dice",
            summary: "Rhythm (t), melody (X), slow change (Y) and routing.",
            body: [
                .text("Marbles has seven outputs, the same as the hardware module. The live view at the top shows all of them: the three rhythm lights, a meter for each voltage, and moving lines tracing X1 (blue), X2 (pink), X3 (green) and Y (purple) over the last two seconds, each on the same scale as its meter. Outputs that aren't routed anywhere are drawn faint. Underneath, the first row says which rhythm plays each voice (for example t3 → Snare) and the second where each voltage goes (X1 → Pitch)."),
                .items([
                    ("t1, t2, t3", "Three rhythm outputs. t2 is the steady clock. t1 and t3 are random; in Coin Toss every beat goes to one or the other."),
                    ("X1, X2, X3", "Three random melody voltages. Each changes when its own rhythm fires: X1 with t1, X2 with t2, X3 with t3."),
                    ("Y", "A slow fourth voltage that changes at a fraction of the clock."),
                ]),
                .text("**Headphones and the lock screen:** play/pause on AirPods or wired earbuds, or in Control Center, works too. Pause stops everything (Marbles, and any drone); play starts Marbles. Because iOS only sends those buttons to one app, Drift pauses other apps' music when it starts."),
                .heading("Clock tab"),
                .text("**Model** picks the kind of rhythm (Coin Toss, Clusters, Drums, Independent, Divider, Three States). **Rate** is the speed. **Bias** leans the choice between t1 and t3. **Jitter** loosens the timing. **Gate Length** and **Gate Variation** set how long each gate stays open."),
                .heading("X tab"),
                .text("**Spread** is how far the melody jumps (fully right, only the extremes, so X becomes random gates). **Bias** leans it low or high, and **Steps** goes from smooth curves (left) through classic stepped random (middle) to notes snapped to the scale (right); further right the scale is stripped back to its strongest notes, ending on the root. **Scale** sets which notes; **Same as Pad** follows the pad's key and scale. **Clocked By** chooses which rhythm moves the X outputs: each its own (X1 with t1, X2 with t2, X3 with t3), or all three on one t, like patching it into the module's X clock input."),
                .heading("Déjà Vu: repeating"),
                .text("Both Clock and X have **Déjà Vu**, read like the module's knob. **Left**: everything is new each beat. Towards the **middle** Marbles repeats itself more, and **at the middle** (it clicks and says Locked) it locks into a loop **Loop Length** steps long. **Right of the middle** it stays in that loop but jumps around it, and fully right plays it in random order. The **lock** button beside each Déjà Vu slider jumps straight to Locked (tap again to go back)."),
                .heading("New Loop"),
                .text("**New Loop** is Marbles' *reseed* (on the module, a double-press of the Déjà Vu buttons). Marbles draws its rhythms and melodies from a stream of random numbers; the sliders shape how those numbers become notes. New Loop swaps the stream for a fresh one without moving any slider, and the **Loop** number in the live view changes. You only hear it once Déjà Vu is towards Locked, because at Random Marbles is already playing new numbers every beat, so the button is dimmed until then. Double-tapping a Déjà Vu slider does the same. Saved sounds keep their stream, so a loop you liked comes back exactly."),
                .heading("Catch: keep what just happened"),
                .text("When Marbles plays something wonderful, tap **Catch** (next to New Loop, and on the Scope page). It takes the last few beats Marbles actually played (as many as **Loop Length**), every note, every gate and every X and Y value, and loops them exactly. That includes **Y**, which Déjà Vu never repeats. You can keep changing the engine, Timbre and everything else while the caught loop plays. The button turns orange and says how many beats it caught; tap it again to let Marbles go free. New Loop, loading a sound, or Reset also let go."),
                .heading("Routing tab"),
                .text("**Triggers** picks which rhythm strikes Plaits. The default, **t1 + t3**, plays a note on every beat in Coin Toss; **t1** alone plays about every other beat, the classic Marbles patch; **Off** lets Marbles move the sound without striking it. Each of X1, X2, X3 and Y can go to Pitch, Harmonics, Timbre, Morph, Level or **Engine**, with a depth. X1 → Pitch is the classic random melody. Engine works like Plaits' Model input: the engine changes on each strike, around the one you've chosen."),
                .tip("For a phrase you can keep: set both Déjà Vu sliders to the middle (Locked), press New Loop (or double-tap Déjà Vu) until you like it, then save it with the bookmark."),
            ]),

        GuideTopic(
            id: "fx", title: "FX", symbol: "fx",
            summary: "Phaser, delay, reverb and beat repeat on everything.",
            body: [
                .text("The FX tab adds effects to everything Drift plays: the pad, Marbles and all three voices together. The sound goes through them in order: **Phaser → Delay → Reverb → Beat Repeat**. Each has a switch; its sliders stay usable while it's off, so you can set it up first and then bring it in. The effects are saved with your sounds."),
                .items([
                    ("Phaser", "Sweeping notches for a swirling, jet-plane movement. **Rate** is the speed of the sweep, **Depth** how far it goes, **Feedback** how sharp and metallic it gets."),
                    ("Delay", "Echoes. **Follow Marbles' Beat** keeps them in time with Marbles' tempo (even when Marbles is stopped): 1/16 up to a whole bar, with dotted (1/8.) and triplet (1/8T) times. **Free** lets you set any time from 20 ms to 2 s. **Feedback** is how many echoes, **Tone** how dull or clear each repeat is, **Mix** how loud they are. **Ping-Pong** bounces them left and right."),
                    ("Reverb", "The reverb from Mutable Instruments' **Rings** (and Elements), from Émilie Gillet's code. **Mix** is how much you hear, **Size** how long it lasts, **Brightness** how airy. **Freeze**, from Elements, holds the reverb's sound for ever and stops taking in anything new: play over a frozen cloud, then switch it off to let it fade."),
                    ("Beat Repeat", "The strip at the bottom. Hold it to repeat the current slice of the beat, effects and all, like a DJ stutter. Where your finger is sets the slice: **1×** repeats a whole beat, **8×** a 32nd note. Slide while holding to change it. With Marbles playing, slices start on the beat, so the repeats stay in time; let go and the music carries on where it would have been."),
                ]),
                .tip("Turn on Delay at 1/8. (dotted eighth) and Reverb, press Something Nice a few times and let Marbles play."),
                .tip("Rate, Depth, Time, Feedback, Tone, Mix, Size and Brightness can all be given to tilt or an LFO: long-press the slider, then Motion."),
            ]),

        GuideTopic(
            id: "scope", title: "Scope", symbol: "waveform.path.ecg",
            summary: "See the sound: its wave, its harmonics, and Out against Aux.",
            body: [
                .text("The Scope tab shows what Plaits is producing, before the effects. Touch the display to play a note; when nothing is sounding, it says so. Shape the sound on the Plaits page and flip back to see what changed, or give a slider to the gyro and watch the wave move as you tilt. Drone, Hold and ▶ Marbles are on the Plaits page; whatever they're doing carries on while you watch here."),
                .items([
                    ("Wave", "The sound's shape, held still on the note. Watch a fold appear on Waveshaper, a pulse narrow on Virtual Analog, or a wave scan on Wavetable."),
                    ("Spectrum", "The sound split into frequencies, low to high. Each peak is a harmonic; brighter sounds have more peaks to the right."),
                    ("Out × Aux", "Plaits' two outputs drawn against each other. A thin diagonal line means Aux follows Out; loops and clouds mean it's doing something of its own."),
                ]),
                .tip("Assign tilt to Timbre, open Scope and lean the phone: you'll see the wave bend as you hear it."),
            ]),

        GuideTopic(
            id: "motion", title: "Motion", symbol: "gyroscope",
            summary: "Tilt, twist and shake as controls.",
            body: [
                .text("Moving the phone can move any slider on either page. The orange marker on a slider shows where motion has taken it."),
                .items([
                    ("Tilt Sideways", "Leaning the phone like a steering wheel."),
                    ("Tilt Forward", "Dipping the top edge towards you or away."),
                    ("Twist", "Turning the phone on the spot, like a dial or turning to look around. No leaning."),
                    ("All Tilt", "How far you've tilted in any direction, as one control."),
                    ("Shake", "A flick or shake swells it up, then it settles."),
                    ("LFO 1 and LFO 2", "Not movement: two LFOs that wobble whatever you give them, on their own. Each has a shape (Sine, Triangle, Ramps, Square, Smooth Random that wanders like Marbles' Y, Step Random) and either a speed (from once every 50 seconds to 8 times a second) or, with Follow Marbles' Beat, a length from 4 bars to half a beat that stays in time with Marbles. Set them up in the Motion sheet."),
                ]),
                .heading("Assigning"),
                .text("Long-press any slider, then Motion, and pick a source. Or open the gyroscope button: your assignments come first, each with a **Depth** (negative turns it upside down), then **Add Assignment**. New ones start on the voice you're looking at; with three voices on, each target says which voice it moves."),
                .heading("In the Motion sheet"),
                .items([
                    ("Motion switch", "Off returns everything to where you set it and stops the sensors. Your assignments are kept. Long-press the gyroscope button to switch it quickly."),
                    ("Set Level Here", "Makes however you're holding the phone the centre. Twist slowly drifts, so tap this now and then."),
                    ("Freeze", "Holds the current motion so you can put the phone down."),
                    ("Full tilt at", "How far you need to tilt for the full effect. Smaller is more sensitive."),
                ]),
            ]),

        GuideTopic(
            id: "saving", title: "Saving and Happy Accidents", symbol: "bookmark",
            summary: "Bookmark, Library, Recent Changes, Mutate and Reset.",
            body: [
                .items([
                    ("Bookmark", "Saves everything: Plaits, Marbles, the effects, motion assignments, the pad, and the Marbles dice roll, so a locked loop comes back."),
                    ("Undo and Redo", "Long-press the Library button (the stack of cards), or use the buttons at the top of the Library. Each Undo steps back one change; Redo steps forward again."),
                    ("Library", "Your saved sounds, plus **Recent Changes**: the last 100 moments, kept automatically, each named after what changed (\"Timbre → 72\", \"Shuffle\", \"New Loop\"). Tap any entry to hear it: if nothing is playing (no Drone, Marbles stopped), Drift plays a short note so you hear it. The Library stays open so you can audition one after another, and the one playing shows a speaker. Swipe **right** on a Recent Change to save it, **left** on any entry to delete it, or use **Clear Recent Changes** at the bottom; clearing never touches your saved sounds. Opening the Library records where you were, so browsing never loses it."),
                    ("Share and Import", "In the Library, long-press a saved sound (or swipe right on it) and choose **Share** to send it as a small .drift file: Messages, AirDrop, Mail or Files. **Share All**, next to the Saved heading, sends every saved sound in one file. To load sounds someone sent you, tap the file in Messages or Files, or use **Import Sounds…** at the top of the Library. They arrive at the top of Saved, with who made them (\"by Sam\"); long-press one for its full credit.\n\nShared sounds carry your name and a licence, set under **Sharing** at the bottom of the Library (Drift asks for your name the first time). The default is **free to use, please credit** (Creative Commons BY); you can choose **public domain** instead. If you save a sound made from someone else's, it says what it was based on, so the credit travels with it. iOS doesn't tell apps your name, which is why Drift asks."),
                    ("Wand: Nudge, Shuffle, Surprise", "The row of three at the top of the wand menu. Its heading says what they change: the voice on show (on Plaits and Scope) or Marbles. **Nudge** makes small random moves around the current sound."),
                    ("Wand: Shuffle", "Anywhere at all, on the page you're on."),
                    ("Wand: Something Nice", "Random, but pleasant, and all of it at once, from any page. Every voice that's on gets one of the gentler engines (no noise or speech) with its sliders in their sweet spot and a soft envelope; with three voices, drum voices stay drums but get well-set sounds and a lower level. Marbles gets a calm sequence in key with the pad, with small jumps and a little repetition, and the routing is set so it plays them musically. It adds a touch of reverb, and sometimes a soft echo in time: the first voice follows the X1 melody (the others X2 and X3 if they're tonal), sometimes with Y gently moving Timbre. Play, Drone and Hold stay as they are. Keep pressing until something speaks to you; Undo brings back what you had."),
                    ("Wand: Surprise", "Shuffle plus a new engine (Plaits) or a new model and scale (Marbles)."),
                    ("Wand: Keep This Sound", "Makes the sound you're hearing right now your starting point. Whatever Marbles' X and Y are adding to Harmonics, Timbre and Morph (or the engine it switched to) goes into the sliders, and those routes are switched off. Whatever the gyro is adding goes in too, and its level is reset to how you're holding the phone. Routes to Pitch stay, so the melody carries on. Undo brings back what you had."),
                    ("Wand: Reset to Default", "Back to the starting sound and sequence. Motion assignments and pad settings are kept. Undo brings back what you had."),
                ]),
                .text("Drift remembers where you left off, and keeps playing with the screen locked or while you use another app. When you open it fresh, it always starts silent: Marbles stopped and Drone off."),
            ]),
    ]

    static let thanks = GuideTopic(
        id: "thanks", title: "Thanks", symbol: "heart",
        summary: "The people whose work Drift is built on.",
        body: [
            .text("Drift started as an idea: a place on the phone to play with Plaits and Marbles. The hard work was done long before, by others, and shared openly."),
            .items([
                ("Émilie Gillet", "Designed Plaits and Marbles at [Mutable Instruments](https://pichenettes.github.io/mutable-instruments-documentation/), and released their code, with a decade of other modules, for anyone to use. Every voice and every Marbles sequence Drift plays is her code, unchanged, and so is its reverb, from her Rings module."),
                ("Adara Barami / Worldwave", "Built [Wakes](https://github.com/Worldwave/Wakes), which put Plaits and Marbles together on the SP-1 and worked out how to make them play each other, down to the Trig and Burst rocker. Drift follows Wakes closely."),
                ("The SP-1 community", "Whose work Wakes stands on: chattock, Tim Knapen, Eric Lewis, Benjamin Reece, Ryan Gilmore and solderless.engineering."),
            ]),
            .text("Put together by Elliot Moore, with Claude writing much of the code. Drift is open source under the MIT licence, and isn't affiliated with Mutable Instruments, Worldwave or Teenage Engineering."),
        ])

    // Newest first. Add an entry for every release that changes what the app does.
    static let releases: [(version: String, date: String, notes: [String])] = [
        ("0.9.1", "26 October 2026", [
            "The Trig and Burst strip is gone from the Scope page, leaving the display the whole height. For stutters, use Beat Repeat on the FX tab.",
        ]),
        ("0.9.0", "26 October 2026", [
            "FX: a new tab with Phaser, Delay, Reverb and Beat Repeat on the whole mix, saved with your sounds.",
            "Reverb is Mutable Instruments' own, from Rings, with Freeze from Elements.",
            "Delay follows Marbles' beat (1/16 to a bar, dotted and triplet) or runs free, with Feedback, Tone, Mix and Ping-Pong.",
            "Beat Repeat: hold the strip to stutter the current slice of the beat, 1× to 8×, in time with Marbles.",
            "The effects' sliders can be given to motion and the LFOs. Something Nice adds a touch of reverb, and sometimes a soft echo.",
        ]),
        ("0.8.7", "25 October 2026", [
            "Play/pause on AirPods, earbuds, the lock screen and Control Center: pause stops everything (Marbles and any drone), play starts Marbles. Drift now pauses other apps' music when it starts, because iOS only sends those buttons to one app.",
        ]),
        ("0.8.6", "25 October 2026", [
            "The wand menu fits on screen with large text: Nudge, Shuffle and Surprise (was Surprise Me) sit side by side in one row.",
        ]),
        ("0.8.5", "25 October 2026", [
            "Something Nice now sets everything at once, from any page: every voice, Marbles, and how Marbles plays them. Drum voices stay drums. It sits with Keep This Sound and Reset, the wand items that change everything.",
        ]),
        ("0.8.4", "25 October 2026", [
            "Voice switcher: all three labels are the same size. When they don't fit, each takes the width its name needs, then the numbers go, and only then are names shortened.",
        ]),
        ("0.8.3", "25 October 2026", [
            "Marbles: Play and Stop no longer wrap onto two lines with larger text. Catch and New Loop shrink to icons when there isn't room.",
            "The FM engines sit together in the engine row: 2-Op FM, then 6-Op FM I, II and III.",
            "The Marbles live view keeps its text inside the box at the largest text sizes.",
        ]),
        ("0.8.2", "25 October 2026", [
            "Recent Changes are named after what changed (\"Timbre → 72\", \"Voice 2 · Engine → Kick\", \"Shuffle\", \"New Loop\") instead of all saying the engine.",
            "Library: names in black and details in grey, so it no longer looks like a page of links. Sharing moved to the bottom; Undo and Redo grey out properly.",
            "Motion sheet: your assignments come first. Each motion has one name everywhere (Tilt Sideways, Tilt Forward), and with three voices each target says which voice it moves. New assignments start on the voice you're looking at.",
            "Marbles live view: a new row shows which rhythm plays each voice (t3 → Snare), so a pattern with every X route Off no longer looks unplugged. The dice code is now labelled Loop.",
            "Catch and New Loop show their names next to Play, not just icons.",
            "Scope says when nothing is sounding and how to start something.",
            "Burst strip: dashes grouped under each label (Trig · 1× … 8×), with the labels below them rather than behind.",
            "The wand menu says what it will change: Voice 2 · Snare, Virtual Analog, or Marbles.",
            "The voice switcher looks like a segmented control, so it no longer looks like another row of engine buttons.",
            "Gate Length and Gate Variation get a short description like the other sliders.",
        ]),
        ("0.8.1", "25 October 2026", [
            "Shared sounds carry your name and a licence (free to use with credit, or public domain), set under Sharing in the Library. Imported sounds show who made them, and sounds made from them keep the credit.",
        ]),
        ("0.8.0", "25 October 2026", [
            "Share and import sounds: share any saved sound, or all of them, as a .drift file; import from the Library or just tap a .drift file someone sent you.",
        ]),
        ("0.7.0", "23 October 2026", [
            "Two LFOs, as motion sources: give them to any slider like tilt or shake. Seven shapes, a free speed or synced to Marbles' beat, set up in the Motion sheet and saved with your sounds.",
        ]),
        ("0.6.1", "23 October 2026", [
            "Something Nice (wand menu): random but pleasant. Gentle engines in their sweet spots on Plaits; in-key, calm sequences on Marbles. Surprise Me stays wild.",
        ]),
        ("0.6.0", "22 October 2026", [
            "Three Voices: tap the Plaits title to play three Plaits at once, each with its own engine, settings and level, and each played by its own Marbles rhythm. A switcher on Plaits and on Marbles' Routing picks the voice you're working on. One Voice (the default) is the app as before.",
        ]),
        ("0.5.2", "21 October 2026", [
            "Marbles' explanations live only in the ⓘ buttons, so every tab reads the same way: the notes under Y and Routing moved there, and X's ⓘ now explains what X is.",
            "X → Clocked By: \"Each Own t\" is now \"Own t\".",
        ]),
        ("0.5.1", "21 October 2026", [
            "Marbles live view: Y now has its own purple line, so you can see it drift.",
            "The meters use the same scale as the lines, so a line ends at its meter's height. For 0–2 V and 0–5 V they fill from the bottom.",
        ]),
        ("0.5.0", "21 October 2026", [
            "Catch: one tap loops the last few beats Marbles played, exactly, Y included. On the Marbles page next to New Loop, and on Scope.",
            "Keep This Sound (wand menu): turns what Marbles and the gyro are doing right now into the sliders, so you can build from that moment.",
            "Scope no longer has Harmonics, Timbre and Morph underneath, so the display is bigger.",
        ]),
        ("0.4.7", "21 October 2026", [
            "Drift always starts silent: Drone is off at launch, even if it was on when the app was closed.",
        ]),
        ("0.4.6", "21 October 2026", [
            "Fixed: tapping a pad key often made no sound (only dragging worked). Touches on the pad, Scope and burst strip are now read directly from iOS, so every tap plays and every release lets go.",
        ]),
        ("0.4.5", "21 October 2026", [
            "The burst strip now chops a drone: hold it to pulse the sound at 1× to 8× per beat, or tap Trig for a short dip. Pulses re-strike Plaits, so Env amounts add accents.",
        ]),
        ("0.4.4", "21 October 2026", [
            "A Thanks page in the Guide, for Émilie Gillet, Worldwave's Wakes and the SP-1 community.",
        ]),
        ("0.4.3", "21 October 2026", [
            "Burst strip labelled in repeats per beat (Trig · 1× · 2× · 3× · 4× · 6× · 8×), so the numbers rise as it gets faster. The note value shows in the corner while you hold.",
        ]),
        ("0.4.2", "21 October 2026", [
            "Louder: about 4 dB more at the same Volume. Plaits was only using about two-thirds of the available level.",
            "The output's soft saturation is replaced by a limiter that only touches the loudest peaks, so quieter sounds stay clean.",
        ]),
        ("0.4.1", "21 October 2026", [
            "Fixed: Chiptune rang on forever after a note was released. It now fades out over Decay.",
            "Fixed: a touch that iOS cancelled (a sheet opening, a system swipe) could leave a note stuck on.",
            "Fixed: letting go of one surface (pad, Scope, burst strip) no longer cuts a note still held on another.",
            "Trig and Burst are now one strip of dashes on the Scope page: touch to strike, further right repeats faster. Removed from Marbles.",
            "Scope no longer repeats Drone, Hold and ▶ Marbles; they live on the Plaits page.",
            "Library: auditioning plays a short note when nothing else is playing, so you always hear it.",
            "Marbles' trace lines move at a steady speed, even while you drag sliders.",
            "Same as Pad stays in key when the gyro bends Pitch by whole semitones.",
            "Saving happens in the background, and audio retries if it failed to start.",
        ]),
        ("0.4.0", "21 October 2026", [
            "Trig and Burst at the bottom of the Marbles page, like the SP-1 rocker in Wakes. Burst re-strikes at 1/4 to 1/32 (with triplets) while held, locked to Marbles' clock when it plays.",
            "Marbles page sliders are slightly shorter to make room.",
            "Library: tapping a sound plays it and keeps the Library open, so you can audition them one after another. Swipe right on a Recent Change to save it.",
        ]),
        ("0.3.1", "21 October 2026", [
            "Scope now updates continuously. Before, it only redrew when something else on the page changed.",
            "The Marbles live view's trace lines get the same fix.",
        ]),
        ("0.3.0", "21 October 2026", [
            "New Scope tab: the waveform, the spectrum, and Out against Aux, with Harmonics, Timbre and Morph underneath. Touch the display to play.",
        ]),
        ("0.2.8", "21 October 2026", [
            "Removed the Déjà Vu hint under New Loop. The button still dims while Déjà Vu is on Random.",
        ]),
        ("0.2.7", "21 October 2026", [
            "Randomise is now New Loop, and dims (with a hint) until Déjà Vu is turned towards Locked, where you can hear it.",
            "Double-tap a Déjà Vu slider for a new loop, like double-pressing Marbles' Déjà Vu buttons.",
            "Lock button beside each Déjà Vu slider: one tap to Locked, another to go back. The Locked click zone is wider too.",
            "The Guide explains what New Loop (Marbles' reseed) actually changes.",
        ]),
        ("0.2.6", "21 October 2026", [
            "Hold now holds on every engine. String, Modal, the drums and 6-op FM used to ring out on their own and ignore it.",
            "Hold works with Marbles: each note lasts as long as its gate, so Gate Length shapes the notes.",
            "Released notes fade over Decay.",
        ]),
        ("0.2.5", "20 October 2026", [
            "Marbles live view traces X1, X2 and X3 in their own colours, with a legend showing where each output goes. Unrouted outputs are drawn faint.",
            "The meters use the same colours as the lines.",
        ]),
        ("0.2.4", "20 October 2026", [
            "Sturdier saving: a damaged save file can no longer crash Drift or wipe your saved sounds. Anything unreadable is set aside, and the rest still loads.",
            "Recent Changes are saved as you go, so they survive the app being force-quit.",
        ]),
        ("0.2.3", "20 October 2026", [
            "Recent Changes: swipe left on an entry to delete it.",
            "Clear Recent Changes at the bottom of the Library, with a confirmation. Saved sounds are never touched.",
        ]),
        ("0.2.2", "20 October 2026", [
            "Undo and Redo: long-press the Library button, or use the buttons in the Library.",
            "Marbles now strikes a note on every beat by default (Triggers t1 + t3). The clock was always 120 BPM; with t1 alone only about half the beats played.",
            "The Plaits page title stays \"Plaits\" instead of the engine name.",
            "App icon and tab icons use the Mutable Instruments, Plaits and Marbles logos.",
        ]),
        ("0.2.1", "20 October 2026", [
            "Déjà Vu now reads like Marbles' knob: random on the left, Locked in the middle (with a click), jumbled on the right. The Guide had this wrong before.",
            "X Clocked By: all three X outputs can follow one rhythm, like patching the module's X clock input.",
            "Engine is a Marbles destination, like Plaits' Model input: the engine changes on each strike.",
            "Y now defaults to 1/16 of the clock, as on the module.",
            "Surprise Me keeps Same as Pad instead of picking a clashing scale.",
            "Help text for Spread, Steps and Loop Length now follows the Marbles manual.",
        ]),
        ("0.2", "20 October 2026", [
            "This Guide.",
            "Same as Pad: Marbles can use the pad's key and scale.",
            "The pad shows its up and down target and its scale; tap either to change it.",
            "Up and down follows the last slider you touched.",
            "Drone and Marbles combine: Marbles moves a drone without striking it.",
            "Play bar: Drone, Hold and ▶ Marbles.",
            "Reset to Default in the wand menu.",
            "Motion on/off switch.",
            "Long-press help on every slider, and ⓘ help on the Marbles page.",
            "Randomise (was New Dice) shows a dice code that changes with each roll.",
            "Tabs renamed Plaits and Marbles.",
        ]),
        ("0.1", "20 October 2026", [
            "First version: Plaits, Marbles, the pad, motion, saving and Recent Changes.",
        ]),
    ]
}

// MARK: - Views

struct GuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Guide.topics) { t in
                        NavigationLink {
                            GuideTopicView(topic: t)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.title)
                                    Text(t.summary).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: t.symbol).foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
                Section {
                    NavigationLink {
                        GuideTopicView(topic: Guide.thanks)
                    } label: {
                        Label("Thanks", systemImage: "heart")
                    }
                    NavigationLink {
                        WhatsNewView()
                    } label: {
                        Label("What's New", systemImage: "sparkles")
                    }
                } footer: {
                    Text("Drift \(Bundle.main.version). Sound engines by Émilie Gillet / Mutable Instruments, via Worldwave's Wakes. See Thanks.")
                }
            }
            .navigationTitle("Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }
}

struct GuideTopicView: View {
    let topic: GuideTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(topic.body.indices, id: \.self) { i in
                    block(topic.body[i])
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(topic.title)
    }

    @ViewBuilder private func block(_ b: GuideBlock) -> some View {
        switch b {
        case .text(let s):
            Text(LocalizedStringKey(s))
        case .heading(let s):
            Text(s).font(.headline).padding(.top, 6)
        case .items(let rows):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(rows.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rows[i].0).font(.subheadline.weight(.semibold))
                        Text(LocalizedStringKey(rows[i].1)).foregroundStyle(.secondary)
                    }
                }
            }
        case .table(let header, let rows):
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    ForEach(header.indices, id: \.self) { Text(header[$0]).font(.caption.weight(.semibold)) }
                }
                Divider()
                ForEach(rows.indices, id: \.self) { r in
                    GridRow {
                        ForEach(rows[r].indices, id: \.self) { c in
                            Text(rows[r][c])
                                .font(c == 0 ? .subheadline.weight(.semibold) : .subheadline)
                                .foregroundStyle(c == 0 ? .primary : .secondary)
                        }
                    }
                }
            }
            .padding(12)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .tip(let s):
            Label { Text(LocalizedStringKey(s)) } icon: { Image(systemName: "lightbulb") }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

private struct WhatsNewView: View {
    var body: some View {
        List {
            ForEach(Guide.releases, id: \.version) { r in
                Section("Version \(r.version) · \(r.date)") {
                    ForEach(r.notes, id: \.self) { Text($0) }
                }
            }
        }
        .navigationTitle("What's New")
    }
}

extension Bundle {
    var version: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
    }
}
