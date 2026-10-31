#!/usr/bin/env python3
"""Reproducible local Godot tooling. All paths resolve relative to this checkout."""
from __future__ import annotations
import argparse, contextlib, fcntl, hashlib, io, json, math, os, plistlib, re, shutil, struct, subprocess, sys, time, urllib.request, wave, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = "4.7.2"
ENGINE = ROOT / ".tools/godot/Godot.app/Contents/MacOS/Godot"
BLENDER = ROOT / ".tools/blender/Blender.app/Contents/MacOS/Blender"
ART = ROOT / ".artifacts"
MAP_LIST = ROOT / "content/manifest/map_list"
# .tools is symlinked into every worktree from the main checkout, so this resolves
# to one lock file shared by all checkouts on the machine.
RENDER_LOCK = (ROOT / ".tools").resolve() / "render.lock"
GUNS = {
 "ar_a4": ("AssaultRifle_4", "1jhBwTCDW-gF6NsRmq3HdGQ4w9Lop7QA0"),
 "ar_k47": ("AssaultRifle2_1", "1kIe2RIx_nnym-HDqjbDLaBlKrH4BRk4q"),
 "ar_b56": ("Bullpup_1", "1Y_7m9DwXXEWZiSwoLCqU6dxuTaBj9y31"),
 "smg_mp9": ("SubmachineGun_1", "1FfwQlsCiKpWxFWm6IcRPlJT7JW56ejnV"),
 "smg_v45": ("SubmachineGun_2", "1aC5FQHFJEq5dJyobboDg5RMs2SwEodSn"),
 "smg_p90": ("SubmachineGun_3", "1tJp2mNm9zN0BuVMkWfW7iKl91CnQ63Sb"),
 "sg_p12": ("Shotgun_1", "1VNVqPzeE7tRpVE7Yy9SOmrZ4WHi5Dgs5"),
 "sg_a12": ("Shotgun_2", "1Bu0kHgYXtBxFjSemMsMubn2Utp3HxMxC"),
 "lmg_l56": ("AssaultRifle_4", "1_RM5f1tA3gUQT9Qk6resqN0HStoKvDK2"),
 "lmg_l762": ("AssaultRifle2_4", "1LFPXw9NHz8AV2Tb4XgmoHN5PYuZGYkmf"),
 "dmr_d14": ("SniperRifle_2", "1lWd8h2qfKUmTn-s4ijZM0ePOUuLnDz81"),
 "sniper_s90": ("SniperRifle_1", "15iOCbvwHwFu7KDrbHurlzpMp9FBpUlsu"),
 "pistol_p9": ("Pistol_1", "1p_BUZNSwSpZPkDORqMowXqpImA_l2uce"),
 "pistol_p45": ("Pistol_2", "1_4oTGeRiXLsN2qrLxwNlA7QrA9XxTpV8"),
 "pistol_r357": ("Revolver_1", "14vVEBiP1-TXtZdpxTPXbe1nTViHvtGco"),
}
MIRRORS = [
 "9a0e478c-de82-4773-9b70-a0219bb0057c", "db2d564c-63b2-4316-a89e-0f7d7a2416c9", "44e99086-b803-4f8f-b1e4-302068cff16a",
 "fb8ae707-d5b9-4eb8-ab8c-1c78d3c1f710", "100fd5db-d5e8-4db7-8ad3-9a96cc217e56", "44e99086-b803-4f8f-b1e4-302068cff16a",
 "032e6589-3188-41bc-b92b-e25528344275", "f71d6771-f512-4374-bd23-ba00b564db68",
 "9a0e478c-de82-4773-9b70-a0219bb0057c", "db2d564c-63b2-4316-a89e-0f7d7a2416c9",
 "2def4aa0-1f3a-40dd-aa92-0661ce39ae50", "701c17ec-1b9b-4091-8c8b-54ed125078b9",
 "3b53f0fe-f86e-451c-816d-6ab9bd265cdc", "f5a88c73-af97-49ca-8650-4bde579d2f80", "9e728565-67a3-44db-9567-982320abff09"]

def map_entries(mode=None):
    """Registered maps (content/manifest/map_list/<id>.json), ordered as in the game menu."""
    entries = [json.loads(path.read_text()) for path in sorted(MAP_LIST.glob("*.json"))]
    return sorted([entry for entry in entries if mode is None or (mode == "campaign" and entry["id"] == "blackout") or mode in entry.get("supported_modes", ["tdm"])], key=lambda entry: (entry.get("order", 0), entry["id"]))

def map_ids(mode=None):
    return [entry["id"] for entry in map_entries(mode)]

class RenderLock:
    """Exclusive machine-wide lock for anything that renders or bakes (GPU-bound runs from
    two checkouts at once wreck benchmarks and can time out Metal fences). Re-entrant within
    one dev.py process; blocks until free."""
    depth = 0
    handle = None
    def __init__(self, tag=""): self.tag = tag
    def __enter__(self):
        if RenderLock.depth == 0:
            RENDER_LOCK.parent.mkdir(parents=True, exist_ok=True)
            handle = RENDER_LOCK.open("a+")
            try: fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                handle.seek(0); holder = handle.read().strip()
                print("waiting for render lock" + (f" (held by {holder})" if holder else ""), flush=True)
                fcntl.flock(handle, fcntl.LOCK_EX)
            handle.seek(0); handle.truncate(); handle.write(f"pid {os.getpid()} {self.tag} in {ROOT}\n"); handle.flush()
            RenderLock.handle = handle
        RenderLock.depth += 1
        return self
    def __exit__(self, *_):
        RenderLock.depth -= 1
        if RenderLock.depth == 0:
            RenderLock.handle.seek(0); RenderLock.handle.truncate(); RenderLock.handle.close(); RenderLock.handle = None

def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""): h.update(chunk)
    return h.hexdigest()

def build_fingerprint():
    digest=hashlib.sha256()
    for path in sorted([ROOT / "project.godot", *[p for directory in ["game", "content"] for p in (ROOT / directory).rglob("*") if p.is_file()]]):
        digest.update(str(path.relative_to(ROOT)).encode());digest.update(bytes.fromhex(sha(path)))
    return digest.hexdigest()

def download(url, target, expected_sha=None, fallback_urls=()):
    target = Path(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() and target.stat().st_size > 100 and (not expected_sha or sha(target) == expected_sha): return
    partial = target.with_suffix(target.suffix + ".tmp")
    print("DOWNLOAD", target.name, flush=True)
    for source in [url, *fallback_urls]:
        try:
            subprocess.run(["curl", "-fsSL", "--retry", "2", "--max-time", "180", "-o", str(partial), source], check=True)
            if expected_sha and sha(partial) != expected_sha: raise RuntimeError("Checksum mismatch: " + str(target))
            partial.replace(target)
            return
        except Exception as error:
            print("DOWNLOAD ATTEMPT FAILED", source, str(error), flush=True)
    raise RuntimeError("All download mirrors failed for " + str(target))

class RemoteZip(io.RawIOBase):
    """Fetch only the macOS entry from the 1.2GB official template archive."""
    def __init__(self, url):
        self.url = url
        with urllib.request.urlopen(urllib.request.Request(url, method="HEAD"), timeout=60) as r:
            self.size = int(r.headers["Content-Length"])
        self.pos = 0
        self.cache_start = 0
        self.cache = b""
    def seekable(self): return True
    def tell(self): return self.pos
    def seek(self, offset, whence=0):
        self.pos = offset if whence == 0 else (self.pos + offset if whence == 1 else self.size + offset)
        return self.pos
    def read(self, n=-1):
        n = min(self.size - self.pos, n if n >= 0 else self.size)
        if n <= 0: return b""
        if self.cache_start <= self.pos and self.pos + n <= self.cache_start + len(self.cache):
            start = self.pos - self.cache_start
            self.pos += n
            return self.cache[start:start+n]
        fetch = max(n, 8 * 1024 * 1024) if self.pos < self.size - 1024 * 1024 else n
        end = min(self.size - 1, self.pos + fetch - 1)
        req = urllib.request.Request(self.url, headers={"Range": f"bytes={self.pos}-{end}"})
        with urllib.request.urlopen(req, timeout=180) as response:
            if response.status != 206: raise RuntimeError("Template mirror did not honor byte ranges")
            self.cache = response.read()
        self.cache_start = self.pos
        result = self.cache[:n]
        self.pos += len(result)
        return result

def setup():
    lock = json.loads((ROOT / "content/toolchain-lock.json").read_text())
    previous = json.loads((ROOT / "content/asset_manifest.json").read_text()) if (ROOT / "content/asset_manifest.json").exists() else {}
    if not ENGINE.exists() or sha(ENGINE) != lock["engine_binary_sha256"]:
        archive = ROOT / ".tools/downloads/godot-macos.zip"
        entry = lock["engine_archive"]
        download(entry["url"], archive, entry["sha256"], [entry["mirror"]])
        with zipfile.ZipFile(archive) as z: z.extractall(ROOT / ".tools/godot")
        ENGINE.chmod(0o755)
    version = subprocess.check_output([str(ENGINE), "--version"], text=True).strip()
    if version != lock["build"]: raise RuntimeError(f"Wrong engine: {version}")
    template = ROOT / ".tools/templates/macos.zip"
    if not template.exists() or sha(template) != lock["macos_template"]["sha256"]:
        template.parent.mkdir(parents=True, exist_ok=True)
        print("DOWNLOAD macOS export template (range extraction)", flush=True)
        for url in [lock["macos_template"]["archive_url"], lock["macos_template"]["mirror"]]:
            try:
                with zipfile.ZipFile(RemoteZip(url)) as archive:
                    name = next(n for n in archive.namelist() if n.endswith("/macos.zip"))
                    with archive.open(name) as src, template.with_suffix(".tmp").open("wb") as dst: shutil.copyfileobj(src, dst)
                if sha(template.with_suffix(".tmp")) != lock["macos_template"]["sha256"]: raise RuntimeError("Template checksum mismatch")
                template.with_suffix(".tmp").replace(template)
                break
            except Exception as error: print("TEMPLATE MIRROR FAILED", url, str(error), flush=True)
        else: raise RuntimeError("All official template mirrors failed")
    manifest = {**previous, "engine": version, "assets": {}, "template_sha256": sha(template)}
    for index, (weapon_id, (name, drive_id)) in enumerate(GUNS.items()):
        path = ROOT / "content/models" / (name + ".glb")
        url = f"https://static.poly.pizza/{MIRRORS[index]}.glb"
        download(url, path, previous.get("assets", {}).get(weapon_id, {}).get("sha256"))
        if path.read_bytes()[:4] != b"glTF": raise RuntimeError(f"Not a GLB model: {path}")
        manifest["assets"][weapon_id] = {**previous.get("assets", {}).get(weapon_id, {}), "path": str(path.relative_to(ROOT)), "url": url, "sha256": sha(path), "license": "CC0-1.0", "source_pack": "https://quaternius.com/packs/ultimategun.html", "mirror": "https://poly.pizza/bundle/Ultimate-Guns-Pack-cpgUfI4t2F"}
    soldier = ROOT / "content/models/soldier.glb"
    download("https://static.poly.pizza/713f6535-f4f3-4367-a4c6-ced126ae0936.glb", soldier, previous.get("soldier", {}).get("sha256"))
    data = soldier.read_bytes()
    model = json.loads(data[20:20+struct.unpack_from('<I',data,12)[0]])
    manifest["soldier"] = {**previous.get("soldier", {}), "path": "content/models/soldier.glb", "sha256": sha(soldier), "license": "CC0-1.0", "source": "https://poly.pizza/m/Btfn3G5Xv4", "animations": [x.get("name", "") for x in model.get("animations", [])], "nodes": [x.get("name", "") for x in model.get("nodes", [])]}
    for name, drive_id in [("guns", "13L56XcV3IlLxMUqoDyqvcYVEfe0y_sie"), ("characters", "1TTvylHa1CsiJuHFWWiv6PFGhLM-aAH5z")]:
        (ROOT / f"content/licenses/{name}.txt").write_text("Quaternius — " + name + "\nCreative Commons CC0 1.0 Universal\nhttps://creativecommons.org/publicdomain/zero/1.0/\nhttps://quaternius.com/\nCreator's Poly Pizza listing explicitly licenses these models as CC0 1.0.\n")
    (ROOT / "content/asset_manifest.json").write_text(json.dumps(manifest, indent=2))
    print("SETUP PASS", version, flush=True)

def engine(args, tag="godot", rendered=False, activate=False):
    """Run Godot. Rendered runs (editor imports, bakes, captures, benchmarks, play) take the
    render lock first; headless runs do not."""
    with (RenderLock(tag) if rendered else contextlib.nullcontext()):
        run_engine(args, tag, rendered, activate)

def run_engine(args, tag, rendered, activate):
    if not ENGINE.exists(): raise RuntimeError("Engine missing. Run: python3 tools/dev.py setup")
    ART.mkdir(exist_ok=True)
    logs = ART / "logs"
    logs.mkdir(exist_ok=True)
    log = logs / f"{tag}.log"
    command = [str(ENGINE), "--path", str(ROOT), "--log-file", str(log)]
    if not rendered: command += ["--headless"]
    command += args
    print("RUN", tag, flush=True)
    log.unlink(missing_ok=True)
    process = subprocess.Popen(command, cwd=ROOT)
    started=time.monotonic()
    # Interactive play has no time limit; automated runs are stopped if they hang.
    deadline=float("inf") if tag=="play" else started+(1800 if tag.startswith("benchmark") else 600)
    while process.poll() is None:
        # macOS will not let a process started from a shell take focus, and it paces
        # background windows to the display refresh (a hard 60 FPS cap). Activating
        # the running bundle through LaunchServices brings the window to the front.
        if activate and sys.platform=="darwin" and started and time.monotonic()-started>4:
            subprocess.run(["open", "-a", str(ENGINE.parents[2])], check=False);started=0
        content=log.read_text(errors="replace") if log.exists() else ""
        fatal="SCRIPT ERROR:" in content or "Parse Error:" in content or (tag!="lightmaps" and re.search(r"^ERROR:",content,re.M))
        if fatal or time.monotonic()>deadline:
            process.terminate()
            try:process.wait(timeout=10)
            except subprocess.TimeoutExpired:process.kill();process.wait()
            raise RuntimeError(f"{tag} stopped after an error or timeout; see {log}")
        try:process.wait(timeout=.5)
        except subprocess.TimeoutExpired:pass
    content = log.read_text(errors="replace") if log.exists() else ""
    errors = re.findall(r"^ERROR:.*", content, re.M)
    if tag == "lightmaps":
        known = ['ERROR: Condition "p_I->data != this" is true. Returning: false', "ERROR: Can't use get_node() with absolute paths from outside the active scene tree.", "ERROR: Plugin is not attached to debugger."]
        editor_diagnostics = [line for line in errors if line in known]
        errors = [line for line in errors if line not in known]
        if editor_diagnostics:
            print("Godot editor teardown diagnostics retained in", log, flush=True)
    if process.returncode or "SCRIPT ERROR:" in content or "Parse Error:" in content or errors:
        raise RuntimeError(f"{tag} failed (exit {process.returncode}); see {log}")

def blender(script, args, tag):
    """Run a conversion script in the pinned local Blender, headless, with auto-run scripts disabled."""
    if not BLENDER.exists(): raise RuntimeError("Blender missing at " + str(BLENDER))
    (ART / "logs").mkdir(parents=True, exist_ok=True)
    log = ART / "logs" / f"blender-{tag}.log"
    print("RUN blender", script, flush=True)
    with RenderLock("blender-" + tag), log.open("w") as output:
        result = subprocess.run([str(BLENDER), "--background", "--factory-startup", "--disable-autoexec", "--python-exit-code", "1", "--python", str(ROOT / script), "--", *args], cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
    if result.returncode: raise RuntimeError(f"Blender {script} failed (exit {result.returncode}); see {log}")

def fetch_command(domain, only, dry_run, map_id=None):
    return [sys.executable, str(ROOT / "tools/fetch_assets.py"), "--domain", domain] + (["--map", map_id] if map_id else []) + (["--only", *only] if only else []) + (["--dry-run"] if dry_run else [])

def asset_specs(domain, map_id=None):
    """Source lists for a domain: content/asset_sources/<domain>.json, plus for maps one
    content/asset_sources/maps/<id>.json per map (only that map's with --map)."""
    from fetch_assets import source_specs
    return [path for path, _ in source_specs(domain, map_id)]

def ingest(domain, only, dry_run, map_id=None):
    """Fetch a domain's pinned sources, run its conversion pipeline, then import into Godot."""
    subprocess.run(fetch_command(domain, only, dry_run, map_id), cwd=ROOT, check=True)
    if dry_run: return
    for spec_path in asset_specs(domain, map_id):
        spec = json.loads(spec_path.read_text()); name = spec_path.stem
        for index, step in enumerate(spec.get("pipeline", [])):
            if "blender" in step: blender(step["blender"], step.get("args", []), f"{name}-{index}")
            elif "python" in step: subprocess.run([sys.executable, str(ROOT / step["python"]), *step.get("args", [])], cwd=ROOT, check=True)
            elif "godot" in step: engine(["--script", step["godot"], "--", *step.get("args", [])], f"ingest-{name}-{index}", rendered=step.get("rendered", False))
            else: raise RuntimeError(f"Unknown pipeline step in {spec_path}: {step}")
    engine(["--editor", "--import"], f"import-{domain}")

def main():
    # `dev.py blender <script> [args...]` passes everything after the script through to it.
    if len(sys.argv) > 2 and sys.argv[1] == "blender":
        blender(sys.argv[2], sys.argv[3:], Path(sys.argv[2]).stem); return
    p = argparse.ArgumentParser()
    p.add_argument("command", choices=["inspect-zombies-game", "inspect-zombies", "zombies-smoke", "zombies-probe", "setup", "prepare", "check", "test", "run", "capture", "benchmark", "match-test", "render-cleanup", "graphics-check", "audio-check", "inspect-arsenal", "inspect-optics", "inspect-operators", "inspect-throw", "inspect-map", "minimap-bake", "clip", "export", "smoke-export", "inspect-replay", "fetch", "ingest"])
    p.add_argument("--suite", default="core", choices=["core", "integration", "content", "audio", "zombies", "campaign", "local-multiplayer"])
    p.add_argument("--mode", choices=["tdm", "zombies", "campaign"], default="tdm")
    p.add_argument("--domain", choices=["maps", "weapons", "characters"])
    p.add_argument("--only", nargs="*", default=[])
    p.add_argument("--dry-run", action="store_true")
    # Defaults to the first registered map; prepare without --map prepares and bakes every map.
    p.add_argument("--map", default=None, choices=map_ids())
    p.add_argument("--seed", type=int, default=1201)
    p.add_argument("--seconds", type=int, default=600)
    p.add_argument("--stress", action="store_true")
    p.add_argument("--profile-simulation", action="store_true")
    p.add_argument("--swap", action="store_true")
    a = p.parse_args()
    if a.command == "setup": setup(); return
    if a.command in ["fetch", "ingest"]:
        if not a.domain: raise RuntimeError(a.command + " requires --domain maps|weapons|characters")
        if a.map and a.domain != "maps": raise RuntimeError("--map only applies to --domain maps")
        if a.command == "fetch": subprocess.run(fetch_command(a.domain, a.only, a.dry_run, a.map), cwd=ROOT, check=True)
        else: ingest(a.domain, a.only, a.dry_run, a.map)
        return
    if a.command in ["zombies-smoke", "inspect-zombies-game"]: a.mode = "zombies"
    selected = [a.map] if a.map else map_ids()
    a.map = a.map or map_ids(a.mode)[0]
    if a.mode == "zombies" and a.command in ["capture", "benchmark", "render-cleanup", "match-test", "smoke-export"]:
        tag = a.command+"-zombies-"+a.map+"-"+str(a.seed)
        with (RenderLock(tag) if a.command != "match-test" else contextlib.nullcontext()):
            before = build_fingerprint()
            report = ART / (tag+".json")
            report.unlink(missing_ok=True)
            args = ["--disable-vsync", "--max-fps", "0", "--", "--mode=zombies", "--qa="+a.command, "--map="+a.map, "--seed="+str(a.seed), "--seconds="+str(a.seconds), "--profile-dir="+str(ART / "zombies-profile")]
            if a.command == "match-test": args = ["--fixed-fps", "60", *args]
            if a.command == "smoke-export":
                app = ROOT / "builds/FPSMode.app"
                with (app / "Contents/Info.plist").open("rb") as file: metadata = plistlib.load(file)
                binary = app / "Contents/MacOS" / metadata["CFBundleExecutable"]
                with RenderLock(tag), (ART / "logs" / (tag+".log")).open("w") as output:
                    subprocess.run([str(binary), "--log-file", str(ART / "logs" / (tag+"-runtime.log")), *args], cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, check=True, timeout=180)
            else:
                engine(args, tag, rendered=a.command != "match-test", activate=a.command=="benchmark")
            report = ART / (tag+".json")
            if report.exists():
                result = json.loads(report.read_text()); result["content_build_sha256"] = before; result["source_unchanged"] = before==build_fingerprint()
                if a.command == "smoke-export":
                    result["content_build_sha256"] = json.loads((ART / "export-build.json").read_text())["content_build_sha256"]
                    result["export_matches_source"] = result["content_build_sha256"] == before
                report.write_text(json.dumps(result,indent=2))
                if not result["source_unchanged"]: raise RuntimeError("Game source changed during Zombies verification")
                if a.command == "smoke-export" and not result["export_matches_source"]: raise RuntimeError("Export does not match source")
                if not result.get("passed",False): raise RuntimeError("Zombies QA failed; see "+str(report))
            else: raise RuntimeError("Missing Zombies QA report: "+str(report))
            return
    if a.command == "prepare":
        from generate_content import generate
        generate(ROOT)
        from generate_surfaces import generate as generate_surfaces
        generate_surfaces(ROOT)
        from generate_fabric import generate as generate_fabric
        generate_fabric(ROOT)
        # The native importer resolves layered lightmap formats and 3D texture
        # detection on macOS. Gameplay test runners below remain headless.
        engine(["--rendering-driver", "metal", "--editor", "--import", "--recovery-mode"], "import", rendered=True)
        engine(["--script", "res://tools/manifest_assets.gd"], "asset-manifest")
        engine(["--script", "res://tools/build_arms.gd"], "first-person-arms")
        for map_id in selected:
            script = "res://tools/prepare_zombies.gd" if map_id in map_ids("zombies") else "res://tools/prepare.gd"
            engine(["--script", script, "--", "--map=" + map_id], "prepare-" + map_id)
        bake = [f"--bake-scene=res://game/maps/generated/{map_id}.tscn" for map_id in selected] if len(selected) == 1 else ["--bake-maps"]
        engine(["--rendering-driver", "metal", "--editor", "--language", "en", "--", *bake], "lightmaps", rendered=True)
        engine(["--script", "res://tests/test_runner.gd", "--", "--suite=content"], "prepared-content")
        return
    if a.command == "check":
        engine(["--rendering-driver", "metal", "--editor", "--import", "--recovery-mode"], "parse", rendered=True)
        engine(["--script", "res://tools/check_scripts.gd"], "script-check")
        engine(["--script", "res://tests/test_runner.gd", "--", "--suite=content"], "content-check")
    elif a.command == "zombies-smoke":
        engine(["--", "--qa=smoke-export", "--mode=zombies", "--map="+a.map, "--seed="+str(a.seed), "--profile-dir="+str(ART / "zombies-profile")],"zombies-source-smoke",rendered=True)
    elif a.command == "zombies-probe":
        engine(["--fixed-fps", "60", "--script", "res://tools/zombies_path_probe.gd"],"zombies-path-probe")
    elif a.command == "test":
        engine(["--script", "res://tests/test_runner.gd", "--", f"--suite={a.suite}"], f"tests-{a.suite}")
    elif a.command == "run": engine(["--", "--mode="+a.mode, "--map="+a.map], "play", rendered=True, activate=True)
    elif a.command == "render-cleanup":engine(["--", "--qa=cleanup", "--map="+a.map, "--profile-dir="+str(ART / "qa-profile")],"render-cleanup-"+a.map,rendered=True)
    elif a.command == "graphics-check":engine(["--script", "res://tools/graphics_check.gd", "--", "--profile-dir="+str(ART / "graphics-profile")],"graphics-check",rendered=True)
    elif a.command == "audio-check":engine(["--rendering-driver","metal","--script","res://tools/audio_probe.gd"],"audio-output",rendered=True)
    elif a.command == "inspect-arsenal":engine(["--script","res://tools/inspect_arsenal.gd"],"arsenal-inspection",rendered=True)
    elif a.command == "inspect-optics":engine(["--script","res://tools/inspect_optics.gd","--","--profile-dir="+str(ART / "optics-profile")],"optics-inspection",rendered=True)
    elif a.command == "inspect-replay":engine(["--script","res://tools/inspect_replay.gd","--","--profile-dir="+str(ART / "replay-profile")],"replay-inspection",rendered=True)
    elif a.command == "inspect-zombies-game":engine(["--script","res://tools/inspect_zombies_game.gd","--","--mode=zombies","--map="+a.map,"--profile-dir="+str(ART / "art-profile")],"zombie-game-art-"+a.map,rendered=True)
    elif a.command == "inspect-zombies":engine(["--script","res://tools/inspect_zombies.gd"],"zombie-art-inspection",rendered=True)
    elif a.command == "inspect-operators":engine(["--script","res://tools/inspect_operators.gd"],"operator-inspection",rendered=True)
    elif a.command == "inspect-throw":engine(["--script","res://tools/inspect_throw.gd"],"throw-inspection",rendered=True)
    elif a.command == "inspect-map":engine(["--script","res://tools/map_overview.gd","--","--map="+a.map],"map-overview-"+a.map,rendered=True)
    elif a.command == "minimap-bake":
        for map_id in selected:engine(["--script","res://tools/minimap_bake.gd","--","--map="+map_id],"minimap-bake-"+map_id,rendered=True)
    elif a.command == "clip":
        before=build_fingerprint()
        engine(["--write-movie",str(ART / ("gameplay-"+a.map+".avi")),"--fixed-fps","60","--disable-vsync","--","--qa=clip","--seconds="+str(a.seconds),"--map="+a.map,"--profile-dir="+str(ART / "qa-profile")],"clip-"+a.map,rendered=True)
        (ART / ("gameplay-"+a.map+".json")).write_text(json.dumps({"map":a.map,"seconds":a.seconds,"fixed_fps":60,"mode":"Scripted fixed-step recording; not a rendering benchmark or human playtest","content_build_sha256":before,"source_unchanged":before==build_fingerprint()},indent=2))
    elif a.command == "match-test":
        args=["--fixed-fps", "60", "--", "--qa=matchtest", "--map="+a.map, "--seed="+str(a.seed), "--profile-dir="+str(ART / "match-profile")]
        if a.swap:args.append("--swap")
        engine(args,"full-match-"+a.map+("-swapped" if a.swap else ""))
    elif a.command in ["capture", "benchmark"]:
        before=build_fingerprint()
        args = ["--disable-vsync", "--max-fps", "0", "--", f"--qa={a.command}", f"--mode={a.mode}", f"--map={a.map}", f"--seed={a.seed}", f"--seconds={a.seconds}", "--profile-dir=" + str(ART / "qa-profile")]
        if a.stress: args.append("--stress")
        if a.profile_simulation:args.append("--profile-simulation")
        engine(args, f"{a.command}-{a.map}" + ("-stress" if a.stress else ""), rendered=True, activate=a.command=="benchmark")
        if a.command == "benchmark":
            report=ART / ("benchmark-"+a.map+("-stress" if a.stress else "")+".json")
            result=json.loads(report.read_text());result["content_build_sha256"]=before
            result["source_unchanged"]=before==build_fingerprint();report.write_text(json.dumps(result,indent=2))
            if not result["source_unchanged"]:raise RuntimeError("Game source changed during benchmark")
            if result.get("focused_fraction",1)<.9:print(f"WARNING benchmark window was frontmost for only {result['focused_fraction']:.0%} of frames; unfocused windows are paced to 60 FPS", flush=True)
            if not result["passed"]:raise RuntimeError("Rendering acceptance targets failed; see " + str(report))
    elif a.command == "export":
        engine(["--script", "res://tools/check_scripts.gd"], "export-script-check")
        (ROOT / "builds").mkdir(exist_ok=True)
        engine(["--export-release", "macOS", str(ROOT / "builds/FPSMode.app")], "export")
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(ROOT / "builds/FPSMode.app")], check=True)
        (ART / "export-build.json").write_text(json.dumps({"content_build_sha256":build_fingerprint(),"engine":VERSION,"signed":True,"export_config_sha256":sha(ROOT / "export_presets.cfg"),"exported_unix":time.time()},indent=2))
    elif a.command == "smoke-export":
        app = ROOT / "builds/FPSMode.app"
        with (app / "Contents/Info.plist").open("rb") as f: metadata = plistlib.load(f)
        binary = app / "Contents/MacOS" / metadata["CFBundleExecutable"]
        output = ART / "logs/export-smoke.log"
        report = ART / "export-smoke.json"
        report.unlink(missing_ok=True)
        with RenderLock("smoke-export"), output.open("w") as log:
            subprocess.run([str(binary), "--log-file", str(ART / "logs/export-runtime.log"), "--", "--qa=smoke", "--profile-dir=" + str(ART / "export-profile")], check=True, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=180)
        if "EXPORT SMOKE PASS" not in output.read_text() or "SCRIPT ERROR:" in output.read_text() or re.search(r"^ERROR:",output.read_text(),re.M):raise RuntimeError("Export smoke failed; see " + str(output))
        result=json.loads(report.read_text());result["content_build_sha256"]=json.loads((ART / "export-build.json").read_text())["content_build_sha256"] if (ART / "export-build.json").exists() else None
        result["tested_unix"]=time.time();report.write_text(json.dumps(result,indent=2))

if __name__ == "__main__":
    try: main()
    except Exception as exc:
        print(f"FAILED: {exc}", file=sys.stderr)
        sys.exit(1)
