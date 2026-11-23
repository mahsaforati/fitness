#!/usr/bin/env python3
"""
Make the How-page videos with Google's AI models, one exercise at a time.

  1. poses    – a still of your reference woman in each exercise's start pose (Nano Banana image model)
  2. approve  – you look at the stills in out/review.html and approve the good ones
  3. videos   – one looping rep per approved pose (Gemini Omni Flash): first and last frame are the
                same start pose, so the clip loops seamlessly. Then it's cropped to the app's spec.
  4. accept   – you watch the videos in out/review.html and accept the good ones
  5. install  – accepted videos are copied into the app (Fitness/HowToVideos/howto-<id>.mp4)

Run `python3 generate.py --help` or see README.md in this folder.
Needs: Python 3.10+, `pip3 install google-genai`, ffmpeg (`brew install ffmpeg`), and your
AI Studio key in the GEMINI_API_KEY environment variable.
"""

import argparse
import base64
import html
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

# ---------------------------------------------------------------------------------------------
# Settings

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
OUT = HERE / "out"
STATUS_FILE = OUT / "status.json"
REFERENCE = HERE / "reference.png"            # your character: the same woman in every video
APP_VIDEOS = REPO / "Fitness" / "HowToVideos"

IMAGE_MODEL = os.environ.get("HOWTO_IMAGE_MODEL", "gemini-3.1-flash-image")   # Nano Banana 2
VIDEO_MODEL = os.environ.get("HOWTO_VIDEO_MODEL", "gemini-omni-1.1-flash")    # Gemini Omni Flash

CLIP_SECONDS = 4          # one rep
GEN_ASPECT = "9:16"       # Omni only makes 9:16 or 16:9; we crop to 4:5 afterwards
GEN_RESOLUTION = "1080p"  # 1080 × 1920

# Final spec (same as the README): 4:5, 1080 × 1350, 30 fps, HEVC ~1.2 Mbps, no audio.
OUT_W, OUT_H, OUT_FPS, OUT_BITRATE = 1080, 1350, 30, "1200k"

# Where the figure has to stay in the tall 9:16 frame so that, after the crop, it's clear of the
# app's Back/Pause buttons (top) and the exercise name (bottom). Fractions of the frame height.
HEAD_MIN, FEET_MAX = 0.24, 0.72

POSE_PROMPT = """\
Use the woman in the reference image: the same face, hair, body, skin tones, clothing and style, \
on the same plain flat sage-green studio background.

Show her standing still in the STARTING position of this exercise: {name}.
How the exercise is done: {steps}
Equipment: {equipment}.

Framing: a tall 9:16 image. Her whole body and any equipment fill the middle of the frame: the top \
of her head is no higher than {head}% down from the top edge, and her feet (or the lowest point of \
her body) are no lower than {feet}% down. Leave plain empty background above and below her. Centre \
her horizontally, full body visible, at a slight three-quarter angle so the movement will be easy \
to see.

Show the muscles this exercise works ({muscles}) in red, like the reference. Plain background, no \
floor markings, no shadows on the wall, no text, no logos, no extra people, no props except the \
equipment."""

VIDEO_PROMPT = """\
Both images are the same frame: the woman in her starting position for {name}. Animate exactly one \
slow, controlled repetition that starts in this pose and returns to exactly this pose at the end, \
so the clip loops seamlessly.
[0-{half}s] {down}
[{half}-{dur}s] She returns smoothly to the starting position.
Form: {steps}
Make sure she avoids: {avoid}

A single continuous shot with a locked-off static camera: no zoom, no pan, no cuts. She stays the \
same size and in the same place in the frame. Same plain flat sage-green background throughout, \
no text or captions. Silent: no music, no dialogue, no sound effects."""

# ---------------------------------------------------------------------------------------------
# Exercises

def plan_exercises():
    """The plan's exercises, with the steps written for the app (Fitness/ExerciseLibrary.swift)."""
    src = (REPO / "Fitness" / "ExerciseLibrary.swift").read_text()
    catalog = {c["id"]: c for c in json.loads((REPO / "Fitness" / "ExerciseCatalog.json").read_text())}
    plan_map = dict(re.findall(r'"([a-z0-9-]+)":\s*"(lib-\d+)"',
                               (REPO / "Fitness" / "ExerciseCatalog.swift").read_text()))
    out = {}
    for m in re.finditer(r'"([a-z0-9-]+)":\s*ExerciseInfo\((.*?)\n\s*(?:start|end):', src, re.S):
        ex_id, body = m.group(1), m.group(2)
        name = re.search(r'name:\s*"([^"]+)"', body).group(1)
        steps = re.findall(r'"([^"]+)"', re.search(r'steps:\s*\[(.*?)\]', body, re.S).group(1))
        avoid = re.search(r'avoid:\s*"([^"]+)"', body).group(1)
        muscles = re.findall(r'"([^"]+)"', re.search(r'muscles:\s*\[(.*?)\]', body, re.S).group(1))
        cat = catalog.get(plan_map.get(ex_id, ""), {})
        out[ex_id] = dict(name=name, steps=steps, avoid=avoid, muscles=muscles,
                          equipment=cat.get("equipment", "dumbbells"))
    return out


def catalog_exercises():
    """The big list (Fitness/ExerciseCatalog.json): 1,324 exercises, ids lib-0001…"""
    out = {}
    for c in json.loads((REPO / "Fitness" / "ExerciseCatalog.json").read_text()):
        steps = [s for s in c.get("steps", []) if not s.lower().startswith("repeat")]
        out[c["id"]] = dict(name=c["name"], steps=steps, avoid=c.get("avoid") or "poor form, jerky movement",
                            muscles=[c["target"]] + c.get("secondary", []), equipment=c["equipment"])
    return out


def pick(args):
    exercises = catalog_exercises() if args.catalog else plan_exercises()
    ids = list(exercises)
    if args.only:
        missing = [i for i in args.only if i not in exercises]
        if missing:
            sys.exit(f"Unknown exercise id(s): {', '.join(missing)}")
        ids = args.only
    if args.limit:
        ids = ids[args.offset:args.offset + args.limit]
    return exercises, ids

# ---------------------------------------------------------------------------------------------
# Status (out/status.json): pose = none|ready|approved|rejected, video = none|ready|accepted|rejected

def load_status():
    return json.loads(STATUS_FILE.read_text()) if STATUS_FILE.exists() else {}


def save_status(status):
    OUT.mkdir(exist_ok=True)
    STATUS_FILE.write_text(json.dumps(status, indent=2, sort_keys=True))
    write_review(status)


def entry(status, ex_id, ex):
    e = status.setdefault(ex_id, {"pose": "none", "video": "none"})
    e["name"] = ex["name"]
    return e

# ---------------------------------------------------------------------------------------------
# Google API

def client():
    if not (os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")):
        sys.exit("Set your AI Studio key first:  export GEMINI_API_KEY=...")
    try:
        from google import genai
    except ImportError:
        sys.exit("Install the Google SDK first:  pip install -U google-genai pillow")
    from google.genai import types
    # Omni (video) is only on the v1beta API; recent SDKs default to v1, which answers "model not found".
    api = genai.Client(http_options=types.HttpOptions(api_version="v1beta"))
    if not hasattr(api, "interactions"):
        # The Interactions API (needed for Omni video) is only in recent SDKs, which need Python 3.10+.
        sys.exit(f"Your Google SDK is too old for video (you're on Python {sys.version.split()[0]}).\n"
                 "Set up the newer Python once (see README.md, One-time setup):\n"
                 "  brew install python\n"
                 "  $(brew --prefix)/bin/python3 -m venv .venv\n"
                 "  source .venv/bin/activate\n"
                 "  pip install -U google-genai pillow")
    return api


def retry(what, fn, attempts=3):
    for i in range(attempts):
        try:
            return fn()
        except Exception as err:  # network hiccups, rate limits, safety blocks…
            import traceback
            frames = traceback.extract_tb(err.__traceback__)
            mine = [f for f in frames if Path(f.filename).name == "generate.py"]
            where = f"line {mine[-1].lineno}: {mine[-1].line}" if mine else ""
            print(f"   {what} failed ({type(err).__name__}: {err}) [{where}].", end="")
            if os.environ.get("HOWTO_DEBUG"):
                traceback.print_exc()
            if any(code in str(err) for code in ("404", "not_found", "NOT_FOUND", "PERMISSION_DENIED", "403")):
                print(" Not worth retrying.")
                return None
            if i == attempts - 1:
                print(" Giving up on this one.")
                return None
            wait = 20 * (i + 1)
            print(f" Retrying in {wait}s…")
            time.sleep(wait)


def make_pose(api, ex):
    from google.genai import types
    prompt = POSE_PROMPT.format(name=ex["name"], steps=" ".join(ex["steps"]), equipment=ex["equipment"],
                                muscles=", ".join(ex["muscles"]),
                                head=round(HEAD_MIN * 100), feet=round(FEET_MAX * 100))
    resp = api.models.generate_content(
        model=IMAGE_MODEL,
        contents=[types.Part.from_bytes(data=REFERENCE.read_bytes(), mime_type="image/png"), prompt],
        config=types.GenerateContentConfig(response_modalities=["IMAGE"],
                                           image_config=types.ImageConfig(aspect_ratio=GEN_ASPECT)),
    )
    for part in resp.candidates[0].content.parts:
        if getattr(part, "inline_data", None) and part.inline_data.data:
            return part.inline_data.data, part.inline_data.mime_type or "image/png"
    raise RuntimeError("no image in the response (it may have been blocked)")


def make_video(api, ex, pose_bytes, pose_mime, dest, on_created=lambda _id: None):
    b64 = base64.b64encode(pose_bytes).decode()
    steps = ex["steps"]
    down = next((s for s in steps if not s.lower().startswith(("hold", "stand", "lie", "sit", "start", "feet", "grab", "place"))),
                steps[-1] if steps else "She performs the movement.")
    half = CLIP_SECONDS / 2
    prompt = VIDEO_PROMPT.format(name=ex["name"], down=down, steps=" ".join(steps), avoid=ex["avoid"],
                                 half=f"{half:g}", dur=CLIP_SECONDS)
    frame = {"type": "image", "data": b64, "mime_type": pose_mime}
    interaction = api.interactions.create(
        model=VIDEO_MODEL,
        input=[frame, frame, {"type": "text", "text": prompt}],   # first frame = last frame → loop
        response_format={"type": "video", "aspect_ratio": GEN_ASPECT, "resolution": GEN_RESOLUTION,
                         "duration": f"{CLIP_SECONDS}s", "delivery": "uri"},
    )
    on_created(interaction.id)      # saved, so a failed download never means paying for the video twice
    fetch_video(api, interaction.id, dest, interaction)


def fetch_video(api, interaction_id, dest, interaction=None):
    """Save a finished interaction's video: from its file link, else inline from the interaction itself."""
    video = getattr(interaction, "output_video", None) if interaction else None
    uri = getattr(video, "uri", None)
    if uri:
        try:
            data = api.files.download(file=uri)
            if data:
                dest.write_bytes(data)
                return
        except Exception as err:
            print(f"   (file link didn't work: {err}; fetching it from the interaction instead)")
    # Google's docs: getting an interaction returns the video inline even when made with a file link.
    got = api.interactions.get(interaction_id)
    data = getattr(getattr(got, "output_video", None), "data", None)
    if not data:
        raise RuntimeError(f"no video in interaction {interaction_id} yet")
    dest.write_bytes(base64.b64decode(data))

# ---------------------------------------------------------------------------------------------
# Reframing: the image model ignores framing instructions and draws her top to bottom, so after the
# 4:5 crop her feet are cut off and her head is under the buttons. This finds her outline, shrinks
# her into the safe area of the crop, and fills the space around her with matching background.

# Safe area for the figure inside the final 1080 × 1350 frame (a little inside the app's limits).
SAFE_TOP, SAFE_BOTTOM, SAFE_SIDE = 175, 250, 60


def pillow():
    try:
        from PIL import Image, ImageChops, ImageDraw, ImageFilter
        return Image, ImageChops, ImageDraw, ImageFilter
    except ImportError:
        sys.exit("Install Pillow first:  pip3 install pillow")


def reframe(src_path, dest_path):
    """Shrink and place the figure inside the app's safe area. Returns the scale used (1.0 = untouched)."""
    Image, ImageChops, ImageDraw, ImageFilter = pillow()
    import statistics
    src = Image.open(src_path).convert("RGB")
    W, H = src.size
    px = src.load()

    # Background plate: every row filled with the colour at the left and right edges of that row,
    # which keeps the studio's top-to-bottom shading.
    edge = max(8, W // 12)
    plate = Image.new("RGB", (W, H))
    for y in range(H):
        cols = [px[x, y] for x in list(range(edge)) + list(range(W - edge, W))]
        plate.paste(tuple(int(statistics.median(ch)) for ch in zip(*cols)), (0, y, W, y + 1))
    plate = plate.filter(ImageFilter.GaussianBlur(6))

    # The figure: whatever differs clearly from that background.
    mask = ImageChops.difference(src, plate).convert("L").point(lambda v: 255 if v > 28 else 0)
    bbox = mask.filter(ImageFilter.MinFilter(5)).getbbox()
    if not bbox:
        shutil.copy2(src_path, dest_path)
        return 1.0
    x0, y0, x1, y1 = bbox

    # Where the figure may go in this image (the middle 4:5 band, minus the app's buttons and title).
    band_h = W * OUT_H / OUT_W
    band_top = (H - band_h) / 2
    s = W / OUT_W
    t_top, t_bot = band_top + SAFE_TOP * s, band_top + band_h - SAFE_BOTTOM * s
    t_w = W - 2 * SAFE_SIDE * s
    if y0 >= t_top and y1 <= t_bot and x0 >= SAFE_SIDE * s and x1 <= W - SAFE_SIDE * s:
        shutil.copy2(src_path, dest_path) if Path(src_path).suffix == ".jpg" else src.save(dest_path, quality=95)
        return 1.0                                      # already inside the safe area
    scale = min(1.0, (t_bot - t_top) / (y1 - y0), t_w / (x1 - x0))

    small = src.resize((round(W * scale), round(H * scale)), Image.LANCZOS)
    ox = round(W / 2 - (x0 + x1) / 2 * scale)          # centred on her
    oy = round(t_bot - y1 * scale)                      # feet on the bottom of the safe area

    feather = max(40, W // 10)                          # soft edges so the paste blends in
    soft = Image.new("L", small.size, 0)
    ImageDraw.Draw(soft).rectangle([feather, feather, small.size[0] - feather, small.size[1] - feather], fill=255)
    soft = soft.filter(ImageFilter.GaussianBlur(feather / 2))

    out = plate.copy()
    out.paste(small, (ox, oy), soft)
    out.save(dest_path, quality=95)
    return scale


# ---------------------------------------------------------------------------------------------
# ffmpeg

def run(cmd):
    if shutil.which(cmd[0]) is None:
        sys.exit(f"{cmd[0]} isn't installed. Install it with:  brew install ffmpeg\n"
                 "(No Homebrew? Get it first from https://brew.sh)")
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip().splitlines()[-1] if r.stderr.strip() else "ffmpeg failed")
    return r.stdout


def hevc_encoder():
    encoders = run(["ffmpeg", "-hide_banner", "-encoders"])
    if "libx265" in encoders:
        return ["-c:v", "libx265", "-preset", "slow", "-b:v", OUT_BITRATE, "-maxrate", "1500k",
                "-bufsize", "3000k", "-x265-params", "log-level=error"]
    return ["-c:v", "hevc_videotoolbox", "-b:v", OUT_BITRATE]   # Apple's built-in encoder


def crop(raw, final):
    """Any generated clip → 4:5, 1080 × 1350, 30 fps, one rep long, HEVC, no audio."""
    w, h = (int(x) for x in run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                 "stream=width,height", "-of", "csv=p=0", str(raw)]).strip().split(","))
    if w / h > OUT_W / OUT_H:   # too wide: keep the middle
        crop_f = "crop=ih*4/5:ih:(iw-ih*4/5)/2:0"
    else:                       # too tall (the usual 9:16): keep the middle band
        crop_f = "crop=iw:iw*5/4:0:(ih-iw*5/4)/2"
    vf = f"{crop_f},scale={OUT_W}:{OUT_H}:flags=lanczos,fps={OUT_FPS},format=yuv420p"
    run(["ffmpeg", "-y", "-v", "error", "-i", str(raw), "-t", str(CLIP_SECONDS), "-vf", vf, "-an",
         *hevc_encoder(), "-tag:v", "hvc1", "-movflags", "+faststart", str(final)])


def poster(final, dest):
    run(["ffmpeg", "-y", "-v", "error", "-i", str(final), "-vf",
         f"fps=5/{CLIP_SECONDS},scale=216:270,tile=5x1", "-frames:v", "1", str(dest)])

# ---------------------------------------------------------------------------------------------
# Commands

def cmd_reference(args):
    """Grab a frame from a video you like as the character reference."""
    run(["ffmpeg", "-y", "-v", "error", "-ss", str(args.at), "-i", str(Path(args.source).resolve()),
         "-frames:v", "1", str(REFERENCE)])
    print(f"Saved {REFERENCE.relative_to(REPO)}. Open it and check it's the look you want.")


def cmd_poses(args):
    if not REFERENCE.exists():
        sys.exit("No reference.png yet. Make one with:  python3 generate.py reference --from <video> --at <seconds>")
    exercises, ids = pick(args)
    pillow()   # check it's installed before spending anything
    status, api = load_status(), client()
    for n, ex_id in enumerate(ids, 1):
        ex = exercises[ex_id]
        e = entry(status, ex_id, ex)
        if e["pose"] in ("ready", "approved") and not args.redo:
            continue
        print(f"[{n}/{len(ids)}] Pose: {ex['name']}")
        got = retry("pose", lambda: make_pose(api, ex))
        if not got:
            continue
        data, mime = got
        folder = OUT / ex_id
        folder.mkdir(parents=True, exist_ok=True)
        raw = folder / ("pose-raw.png" if "png" in mime else "pose-raw.jpg")
        raw.write_bytes(data)
        scale = reframe(raw, folder / "pose.jpg")
        e.update(pose="ready", pose_file=f"{ex_id}/pose.jpg", pose_mime="image/jpeg", video="none")
        print(f"   done{'' if scale == 1.0 else f', shrunk to {scale:.0%} to fit the frame'}")
        save_status(status)
    save_status(status)
    print(f"\nOpen {(OUT / 'review.html').relative_to(REPO)} to check the poses, then approve them.")


def set_state(args, field, from_states, to_state):
    status = load_status()
    ids = [i for i, e in status.items() if e.get(field) in from_states] if args.all else args.ids
    for ex_id in ids:
        e = status.get(ex_id)
        if not e or e.get(field) == "none":
            print(f"   {ex_id}: no {field} yet, skipped")
            continue
        e[field] = to_state
        if field == "pose" and to_state == "rejected":
            e["video"] = "none"
    save_status(status)
    print(f"{len(ids)} {field}(s) marked {to_state}.")


def cmd_videos(args):
    exercises, ids = pick(args)
    status = load_status()
    todo = [i for i in ids if status.get(i, {}).get("pose") == "approved"
            and (args.redo or status[i].get("video") in ("none", "rejected"))]
    if not todo:
        waiting = [i for i in ids if status.get(i, {}).get("pose") == "ready"]
        if waiting:
            sys.exit("No approved poses yet. Check out/review.html, then approve them:\n"
                     f"  python3 generate.py approve {' '.join(waiting)}")
        sys.exit("Nothing to do: make poses first (python3 generate.py poses), then approve them.")
    api = client()
    for n, ex_id in enumerate(todo, 1):
        ex, e, folder = exercises[ex_id], status[ex_id], OUT / ex_id
        print(f"[{n}/{len(todo)}] Video: {ex['name']}")
        pose = (OUT / e["pose_file"]).read_bytes()
        raw = folder / "raw.mp4"
        if raw.exists() and args.redo:
            raw.unlink()
        if e.get("interaction") and not raw.exists() and not args.redo:
            print(f"   fetching the video already made (interaction {e['interaction']})")
            retry("download", lambda: fetch_video(api, e["interaction"], raw))
        if not raw.exists():
            def saved(interaction_id, e=e):
                e["interaction"] = interaction_id
                save_status(status)
            # One attempt: a failure after Google made the video is recovered above on the next run.
            retry("video", lambda: make_video(api, ex, pose, e.get("pose_mime", "image/png"), raw, saved), attempts=1)
        if not raw.exists():
            continue
        try:
            crop(raw, folder / "final.mp4")
            poster(folder / "final.mp4", folder / "frames.jpg")
        except RuntimeError as err:
            print(f"   crop failed: {err}")
            continue
        size = (folder / "final.mp4").stat().st_size / 1e6
        e.update(video="ready", size_mb=round(size, 2))
        print(f"   done, {size:.2f} MB")
        save_status(status)
    print(f"\nOpen {(OUT / 'review.html').relative_to(REPO)} to watch them, then accept the good ones.")


def cmd_reframe(args):
    """Reframe poses you already have (no API cost)."""
    status = load_status()
    ids = args.ids or [i for i, e in status.items() if e.get("pose_file")]
    for ex_id in ids:
        folder = OUT / ex_id
        raw = next((p for p in (folder / "pose-raw.jpg", folder / "pose-raw.png") if p.exists()), None)
        if raw is None:   # poses made before reframing existed: keep the original as the raw one
            old = OUT / status[ex_id]["pose_file"]
            raw = folder / ("pose-raw" + old.suffix)
            old.rename(raw)
        scale = reframe(raw, folder / "pose.jpg")
        status[ex_id].update(pose_file=f"{ex_id}/pose.jpg", pose_mime="image/jpeg")
        print(f"   {ex_id}: {'already fits' if scale == 1.0 else f'shrunk to {scale:.0%}'}")
    save_status(status)


def cmd_crop(args):
    """Re-crop already generated videos (e.g. after changing the spec above)."""
    status = load_status()
    for ex_id in (args.ids or [i for i, e in status.items() if (OUT / i / "raw.mp4").exists()]):
        folder = OUT / ex_id
        crop(folder / "raw.mp4", folder / "final.mp4")
        poster(folder / "final.mp4", folder / "frames.jpg")
        status[ex_id]["size_mb"] = round((folder / "final.mp4").stat().st_size / 1e6, 2)
        print(f"   {ex_id} re-cropped")
    save_status(status)


def cmd_install(args):
    status = load_status()
    APP_VIDEOS.mkdir(exist_ok=True)
    done = 0
    for ex_id, e in status.items():
        if e.get("video") == "accepted" and (not args.ids or ex_id in args.ids):
            shutil.copy2(OUT / ex_id / "final.mp4", APP_VIDEOS / f"howto-{ex_id}.mp4")
            done += 1
    print(f"Copied {done} video(s) into Fitness/HowToVideos/. Run `xcodegen generate`, then build the app.")


def cmd_status(args):
    status = load_status()
    if not status:
        print("Nothing generated yet.")
    for ex_id, e in sorted(status.items()):
        size = f"{e['size_mb']:.2f} MB" if "size_mb" in e else ""
        print(f"{ex_id:20} pose: {e['pose']:9} video: {e['video']:9} {size:>8}  {e.get('name', '')}")


def write_review(status):
    """out/review.html: every pose and video side by side, with the ids to approve/accept."""
    rows = []
    for ex_id, e in sorted(status.items()):
        pose = f'<img src="{e["pose_file"]}" alt="">' if e.get("pose_file") else "<div class=empty>no pose</div>"
        video = (f'<video src="{ex_id}/final.mp4" autoplay loop muted playsinline></video>'
                 if (OUT / ex_id / "final.mp4").exists() else "<div class=empty>no video</div>")
        rows.append(f"""<figure><figcaption><b>{html.escape(e.get('name', ex_id))}</b><code>{ex_id}</code>
        <span>pose: {e['pose']} · video: {e['video']}{' · ' + str(e['size_mb']) + ' MB' if 'size_mb' in e else ''}</span>
        </figcaption><div class=pair>{pose}{video}</div></figure>""")
    (OUT / "review.html").write_text(f"""<!doctype html><meta charset=utf-8><title>How videos – review</title>
<style>body{{font:14px -apple-system,sans-serif;margin:24px;background:#FAFAF9;color:#1C1917}}
main{{display:grid;grid-template-columns:repeat(auto-fill,minmax(420px,1fr));gap:24px}}
figure{{margin:0;background:#fff;border:1px solid #E7E5E4;border-radius:12px;padding:12px}}
figcaption{{display:flex;flex-direction:column;gap:2px;margin-bottom:8px}}code{{color:#57534E}}span{{color:#57534E}}
.pair{{display:grid;grid-template-columns:1fr 1fr;gap:8px;align-items:start}}
img{{width:100%;aspect-ratio:9/16;object-fit:contain;background:#eee;border-radius:8px}}
video{{width:100%;aspect-ratio:4/5;border-radius:8px;background:#eee}}
.empty{{aspect-ratio:4/5;display:grid;place-items:center;background:#F0EFEE;border-radius:8px;color:#57534E}}</style>
<h1>How videos</h1><p>Left: start pose (9:16, the figure must sit in the middle band). Right: final video as the app shows it (4:5).</p>
<main>{''.join(rows)}</main>""")

# ---------------------------------------------------------------------------------------------

def main():
    p = argparse.ArgumentParser(description="Generate the How-page exercise videos.")
    sub = p.add_subparsers(dest="cmd", required=True)

    def selection(sp):
        sp.add_argument("--only", nargs="+", metavar="ID", help="just these exercise ids")
        sp.add_argument("--catalog", action="store_true", help="the big 1,324-exercise list instead of the plan")
        sp.add_argument("--limit", type=int, help="at most this many (for batches)")
        sp.add_argument("--offset", type=int, default=0, help="skip this many first (with --limit)")
        sp.add_argument("--redo", action="store_true", help="regenerate even if one exists")

    sp = sub.add_parser("reference", help="grab a video frame as the character reference (reference.png)")
    sp.add_argument("--from", dest="source", required=True)
    sp.add_argument("--at", type=float, default=0.0, help="time in seconds")
    sp.set_defaults(fn=cmd_reference)

    sp = sub.add_parser("poses", help="1. generate start-pose stills"); selection(sp); sp.set_defaults(fn=cmd_poses)

    for name, field, frm, to, hlp in [
        ("approve", "pose", ("ready",), "approved", "2. approve poses"),
        ("reject-pose", "pose", ("ready", "approved"), "rejected", "reject poses (redo them with `poses`)"),
        ("accept", "video", ("ready",), "accepted", "4. accept videos"),
        ("reject-video", "video", ("ready", "accepted"), "rejected", "reject videos (redo them with `videos`)"),
    ]:
        sp = sub.add_parser(name, help=hlp)
        sp.add_argument("ids", nargs="*")
        sp.add_argument("--all", action="store_true", help="every one that's waiting")
        sp.set_defaults(fn=lambda a, f=field, fr=frm, t=to: set_state(a, f, fr, t))

    sp = sub.add_parser("videos", help="3. generate videos for approved poses"); selection(sp); sp.set_defaults(fn=cmd_videos)
    sp = sub.add_parser("reframe", help="refit existing poses into the safe area (no API cost)"); sp.add_argument("ids", nargs="*"); sp.set_defaults(fn=cmd_reframe)
    sp = sub.add_parser("crop", help="re-crop generated videos"); sp.add_argument("ids", nargs="*"); sp.set_defaults(fn=cmd_crop)
    sp = sub.add_parser("install", help="5. copy accepted videos into the app"); sp.add_argument("ids", nargs="*"); sp.set_defaults(fn=cmd_install)
    sp = sub.add_parser("status", help="show where every exercise is"); sp.set_defaults(fn=cmd_status)

    args = p.parse_args()
    if args.cmd in ("approve", "reject-pose", "accept", "reject-video") and not (args.ids or args.all):
        p.error("give exercise ids, or --all")
    args.fn(args)


if __name__ == "__main__":
    main()
