# How-video generator

Makes the How-page exercise videos with Google's AI models and gets them into the app.
Every video ends up at the app's spec: **4:5, 1080 × 1350, 30 fps, one rep (~4 s) looping, HEVC, no audio, ~0.5–0.7 MB**.

How it works, per exercise:

1. **Pose** — Nano Banana (`gemini-3.1-flash-image`) draws your reference woman in the exercise's start pose, as a tall 9:16 still. The model tends to draw her top to bottom, so the script then **reframes** it: it finds her outline and shrinks her into the part of the frame the app shows clear of its buttons and title, filling in matching background around her. The original is kept as `pose-raw.jpg`.
2. **You approve the pose** (nothing is animated until you do).
3. **Video** — Gemini Omni Flash animates one rep, using the approved pose as both the first and the last frame, so the clip loops seamlessly. Omni only makes 9:16 or 16:9, so the script then crops the middle 4:5 out of it, trims it to one rep, removes the sound and encodes it to the spec.
4. **You accept the video.**
5. **Install** — accepted videos are copied into `Fitness/HowToVideos/howto-<id>.mp4`. The How page uses them automatically; exercises without one keep showing the placeholder.

## One-time setup (on your Mac)

Google's current SDK needs **Python 3.10 or newer**; the Python that comes with macOS is 3.9, which only gets an old SDK without video support. So install Homebrew's Python and give the script its own environment:

```bash
brew install ffmpeg python
cd ~/projects/fitness/tools/howto-videos
$(brew --prefix)/bin/python3 -m venv .venv
source .venv/bin/activate
pip install -U google-genai pillow
export GEMINI_API_KEY=your-ai-studio-key     # add this line to ~/.zshrc so it's always set
```

Each time you open a new Terminal window to use the script:

```bash
cd ~/projects/fitness/tools/howto-videos
source .venv/bin/activate
```

(With the environment active, `python3` below is the new Python.)

Never put the key in a file in the repo.

## The reference image

Everything depends on `reference.png`: the same woman, look and background in every video. Make it from a frame of a video you like:

```bash
python3 generate.py reference --from ../../Fitness/HowToPlaceholder.mp4 --at 0.2
```

…or drop your own `reference.png` (a still, plain flat sage background, full body) into this folder.

## Making videos — start with the plan's 18 exercises

```bash
python3 generate.py poses                 # 1. stills for every plan exercise
open out/review.html                      #    look at them
python3 generate.py approve goblet-squat db-rdl …   # 2. or: approve --all
python3 generate.py reject-pose plank     #    bad ones; then `poses` again redoes only those
python3 generate.py videos                # 3. videos for the approved poses
open out/review.html                      #    watch them as the app will show them (4:5)
python3 generate.py accept goblet-squat … # 4. or: accept --all
python3 generate.py reject-video db-rdl   #    then `videos` again redoes only those
python3 generate.py install               # 5. into the app
cd ../.. && xcodegen generate             #    then build in Xcode
```

`python3 generate.py status` shows where every exercise is. If it stops halfway (no internet, a rate limit), run the same command again: finished ones are skipped.

Try one exercise first: `python3 generate.py poses --only goblet-squat`.

## The big list (1,324 exercises)

Same commands with `--catalog`, in batches so you can check quality and cost as you go:

```bash
python3 generate.py poses --catalog --limit 100              # first 100
python3 generate.py poses --catalog --limit 100 --offset 100 # next 100
```

Don't `install` these into the app: ~800 MB is too much to ship. They're meant to be hosted (e.g. Apple-hosted Background Assets) and downloaded on first view.

## Tuning

At the top of `generate.py`:

- `POSE_PROMPT` and `VIDEO_PROMPT`: the wording sent for every exercise.
- `HEAD_MIN` / `FEET_MAX`: where the figure must sit in the 9:16 frame so the crop keeps it clear of the app's buttons and title.
- `CLIP_SECONDS`, `OUT_BITRATE`: rep length and file size.
- Model names can be changed without editing: `HOWTO_IMAGE_MODEL=… HOWTO_VIDEO_MODEL=… python3 generate.py …`.

Poses made before reframing existed, or after changing `SAFE_TOP` / `SAFE_BOTTOM` / `SAFE_SIDE`: `python3 generate.py reframe` refits them, at no API cost.

Changed the crop or size settings? `python3 generate.py crop` re-crops everything already generated, at no API cost.
