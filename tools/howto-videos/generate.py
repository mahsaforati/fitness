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
VIDEO_MODEL = os.environ.get("HOWTO_VIDEO_MODEL", "gemini-omni-1.2-flash")    # Gemini Omni Flash

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
        sys.exit("Install the Google SDK first:  pip3 install google-genai")
    return genai.Client()


def retry(what, fn, attempts=3):
    for i in range(attempts):
        try:
            return fn()
        except Exception as err:  # network hiccups, rate limits, safety blocks…
            print(f"   {what} failed ({err}).", end="")
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


def make_video(api, ex, pose_bytes, pose_mime, dest):
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
    video = interaction.output_video
    if getattr(video, "uri", None):
        file_id = video.uri.split("/")[-1]
        while True:
            info = api.files.get(name=f"files/{file_id}")
            state = info.state.name
            if state == "ACTIVE":
                break
            if state == "FAILED":
                raise RuntimeError("generation failed")
            time.sleep(5)
        api.files.download(file=video.uri, destination=str(dest))
        if not dest.exists():   # some SDK versions return the bytes instead of writing the file
            dest.write_bytes(api.files.download(file=video.uri))
    else:
        dest.write_bytes(base64.b64decode(video.data))

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
        path = folder / ("pose.png" if "png" in mime else "pose.jpg")
        path.write_bytes(data)
        e.update(pose="ready", pose_file=str(path.relative_to(OUT)), pose_mime=mime, video="none")
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
        sys.exit("Nothing to do: approve some poses first (python3 generate.py approve <ids>).")
    api = client()
    for n, ex_id in enumerate(todo, 1):
        ex, e, folder = exercises[ex_id], status[ex_id], OUT / ex_id
        print(f"[{n}/{len(todo)}] Video: {ex['name']}")
        pose = (OUT / e["pose_file"]).read_bytes()
        raw = folder / "raw.mp4"
        if retry("video", lambda: make_video(api, ex, pose, e.get("pose_mime", "image/png"), raw)) is None and not raw.exists():
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
    sp = sub.add_parser("crop", help="re-crop generated videos"); sp.add_argument("ids", nargs="*"); sp.set_defaults(fn=cmd_crop)
    sp = sub.add_parser("install", help="5. copy accepted videos into the app"); sp.add_argument("ids", nargs="*"); sp.set_defaults(fn=cmd_install)
    sp = sub.add_parser("status", help="show where every exercise is"); sp.set_defaults(fn=cmd_status)

    args = p.parse_args()
    if args.cmd in ("approve", "reject-pose", "accept", "reject-video") and not (args.ids or args.all):
        p.error("give exercise ids, or --all")
    args.fn(args)


if __name__ == "__main__":
    main()
