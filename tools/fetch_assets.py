#!/usr/bin/env python3
"""Fetch pinned third-party CC0 content for one domain (maps, weapons, characters).

Each domain lists its sources in content/asset_sources/<domain>.json:

  {"assets": [
    {"id": "concrete_floor_02", "source": "polyhaven", "type": "texture", "resolution": "2k",
     "maps": {"Diffuse": "jpg", "nor_gl": "png", "arm": "jpg"}, "dest": "content/materials/concrete_floor_02"},
    {"id": "kloofendal_overcast_puresky", "source": "polyhaven", "type": "hdri", "resolution": "2k",
     "format": "hdr", "dest": "content/sky"},
    {"id": "Barrel_01", "source": "polyhaven", "type": "model", "resolution": "2k", "dest": "content/models/props/Barrel_01"},
    {"id": "Leaking012A", "source": "ambientcg", "attribute": "2K-JPG", "dest": "content/decals/Leaking012A"},
    {"id": "guns_pack", "source": "manual", "page": "https://3dmodelscc0.itch.io/free-cc0-guns-explosives-pack",
     "filename": "Guns&Explosives.rar", "extract": true, "include": ["*/AK47/*"], "dest": "content/models/weapons/source",
     "license": "CC0-1.0", "creator": "3DModelsCC0"},
    {"id": "some_file", "source": "url", "url": "https://...", "sha256": "...", "extract": true,
     "dest": "...", "license": "CC0-1.0", "creator": "..."}
  ]}

Downloads are cached in .tools/asset-cache. The first successful download of a file
records its SHA-256 in content/asset_sources/<domain>.lock.json; later fetches must
match it. Provenance for every delivered file is written to content/manifest/<domain>.json.

Maps can also keep their own source list, so a new map never edits the shared one:
content/asset_sources/maps/<id>.json (same format, optional "pipeline") locks into
content/asset_sources/maps/<id>.lock.json and records provenance in
content/manifest/maps/<id>.json; the game merges those with content/manifest/maps.json
(MapCatalog.asset_manifest). `--domain maps` fetches the shared list and every map's;
`--domain maps --map <id>` fetches only that map's.
"""
from __future__ import annotations
import argparse, fnmatch, hashlib, http.cookiejar, json, shutil, subprocess, sys, time, urllib.parse, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".tools/asset-cache"
USER_ASSETS = ROOT / ".tools/user-assets"
AGENT = "FPSMode-asset-fetch/1.0 (offline game build tooling)"
cookies = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookies))

def digest(path: Path, kind="sha256") -> str:
    value = hashlib.new(kind)
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""): value.update(block)
    return value.hexdigest()

def request(url: str, data: dict | None = None, headers: dict | None = None):
    body = urllib.parse.urlencode(data).encode() if data is not None else None
    req = urllib.request.Request(url, data=body, headers={"User-Agent": AGENT, **(headers or {})})
    return opener.open(req, timeout=120)

def get_json(url: str, data: dict | None = None, headers: dict | None = None):
    with request(url, data, headers) as response: return json.loads(response.read())

def source_specs(domain: str, map_id: str | None = None) -> list[tuple[Path, Path]]:
    """(source list, provenance manifest) pairs for a domain, shared list first."""
    shared = (ROOT / f"content/asset_sources/{domain}.json", ROOT / f"content/manifest/{domain}.json")
    if domain != "maps": return [shared]
    folder = ROOT / "content/asset_sources/maps"
    per_map = sorted(path for path in folder.glob("*.json") if not path.name.endswith(".lock.json")) if folder.exists() else []
    pairs = [(path, ROOT / "content/manifest/maps" / path.name) for path in per_map]
    if map_id is None: return [shared, *pairs]
    pairs = [pair for pair in pairs if pair[0].stem == map_id]
    if not pairs: raise RuntimeError(f"No source list for map {map_id}: create content/asset_sources/maps/{map_id}.json")
    return pairs

class Fetcher:
    def __init__(self, domain: str, dry_run: bool, spec: Path | None = None, manifest: Path | None = None):
        self.domain, self.dry_run = domain, dry_run
        self.spec_path = spec or ROOT / f"content/asset_sources/{domain}.json"
        self.lock_path = self.spec_path.with_name(self.spec_path.stem + ".lock.json")
        self.manifest_path = manifest or (ROOT / f"content/manifest/{domain}.json" if spec is None else self.spec_path.with_name(self.spec_path.stem + ".manifest.json"))
        self.spec = json.loads(self.spec_path.read_text())
        self.lock = json.loads(self.lock_path.read_text()) if self.lock_path.exists() else {"files": {}}
        self.manifest = json.loads(self.manifest_path.read_text()) if self.manifest_path.exists() else {"assets": {}}

    def download(self, url: str, target: Path, md5: str | None = None, size: int | None = None) -> Path:
        """Download url into the cache (once), verifying the upstream md5 and the locked sha256."""
        key = str(target.relative_to(CACHE))
        pinned = self.lock["files"].get(key, {}).get("sha256")
        if target.exists() and (pinned is None or digest(target) == pinned) and (md5 is None or digest(target, "md5") == md5):
            return target
        if self.dry_run:
            print(f"WOULD DOWNLOAD {url} ({(size or 0)/1e6:.1f} MB) -> {key}", flush=True); return target
        target.parent.mkdir(parents=True, exist_ok=True)
        partial = target.with_name(target.name + ".part")
        for attempt in range(4):
            try:
                with request(url) as response, partial.open("wb") as out: shutil.copyfileobj(response, out, 1 << 20)
                break
            except Exception as error:
                if attempt == 3: raise RuntimeError(f"Download failed: {url}: {error}")
                time.sleep(2 + attempt * 3)
        if md5 and digest(partial, "md5") != md5: raise RuntimeError(f"Upstream checksum mismatch for {url}")
        sha = digest(partial)
        if pinned and sha != pinned: raise RuntimeError(f"Pinned SHA-256 mismatch for {key}: upstream content changed")
        partial.replace(target)
        self.lock["files"][key] = {"url": url, "sha256": sha, "size": target.stat().st_size}
        print(f"DOWNLOADED {key} ({target.stat().st_size/1e6:.1f} MB)", flush=True)
        return target

    def deliver(self, source: Path, destination: Path, files: list) -> None:
        if self.dry_run: return
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        files.append({"path": str(destination.relative_to(ROOT)), "sha256": digest(destination)})

    def extract(self, archive: Path, include: list[str] | None) -> Path:
        out = archive.with_name(archive.name + ".extracted")
        if self.dry_run: return out
        if not out.exists():
            out.mkdir(parents=True)
            subprocess.run(["bsdtar", "-xf", str(archive), "-C", str(out)], check=True)
        return out

    def copy_tree(self, tree: Path, dest: Path, include: list[str] | None, files: list) -> None:
        if self.dry_run: return
        for path in sorted(p for p in tree.rglob("*") if p.is_file()):
            relative = path.relative_to(tree).as_posix()
            if include and not any(fnmatch.fnmatch(relative, pattern) for pattern in include): continue
            self.deliver(path, dest / relative, files)

    def polyhaven(self, entry: dict, files: list) -> dict:
        asset, kind, res = entry["id"], entry["type"], entry.get("resolution", "2k")
        listing = get_json(f"https://api.polyhaven.com/files/{asset}")
        info = get_json(f"https://api.polyhaven.com/info/{asset}")
        dest = ROOT / entry["dest"]
        if kind == "texture":
            for channel, fmt in entry.get("maps", {"Diffuse": "jpg", "nor_gl": "png", "arm": "jpg"}).items():
                item = listing[channel][res][fmt]
                cached = self.download(item["url"], CACHE / "polyhaven" / Path(urllib.parse.urlparse(item["url"]).path).name, item.get("md5"), item.get("size"))
                self.deliver(cached, dest / cached.name, files)
        elif kind == "hdri":
            item = listing["hdri"][res][entry.get("format", "hdr")]
            cached = self.download(item["url"], CACHE / "polyhaven" / Path(urllib.parse.urlparse(item["url"]).path).name, item.get("md5"), item.get("size"))
            self.deliver(cached, dest / cached.name, files)
        elif kind == "model":
            item = listing["gltf"][res]["gltf"]
            base = CACHE / "polyhaven/models" / f"{asset}_{res}"
            gltf = self.download(item["url"], base / Path(urllib.parse.urlparse(item["url"]).path).name, item.get("md5"), item.get("size"))
            self.deliver(gltf, dest / gltf.name, files)
            for relative, include in item.get("include", {}).items():
                cached = self.download(include["url"], base / relative, include.get("md5"), include.get("size"))
                self.deliver(cached, dest / relative, files)
        else: raise RuntimeError(f"Unknown Poly Haven type {kind} for {asset}")
        return {"source_page": f"https://polyhaven.com/a/{asset}", "license": "CC0-1.0", "creator": ", ".join(info.get("authors", {}).keys()), "polycount": info.get("polycount")}

    def ambientcg(self, entry: dict, files: list) -> dict:
        asset, attribute = entry["id"], entry.get("attribute", "2K-JPG")
        data = get_json(f"https://ambientcg.com/api/v2/full_json?id={urllib.parse.quote(asset)}&include=downloadData")
        downloads = data["foundAssets"][0]["downloadFolders"]["default"]["downloadFiletypeCategories"]["zip"]["downloads"]
        item = next(d for d in downloads if d["attribute"] == attribute)
        archive = self.download(item["fullDownloadPath"], CACHE / "ambientcg" / f"{asset}_{attribute}.zip", None, item.get("size"))
        self.copy_tree(self.extract(archive, None), ROOT / entry["dest"], entry.get("include"), files)
        return {"source_page": f"https://ambientcg.com/view?id={asset}", "license": "CC0-1.0", "creator": "ambientCG (Lennart Demes)"}

    def manual(self, entry: dict, files: list) -> dict:
        """Files that need a click or a login (itch.io, Mixamo) are downloaded by hand into
        .tools/user-assets/<domain>/; this verifies, unpacks and delivers them like any other source."""
        source = USER_ASSETS / self.domain / entry["filename"]
        provenance = {"source_page": entry["page"], "license": entry["license"], "creator": entry["creator"], "filename": entry["filename"]}
        if not source.exists():
            message = f"MISSING manual download {entry['filename']}: get it from {entry['page']} and save it to {source}"
            if self.dry_run: print(message, flush=True); return provenance
            raise RuntimeError(message)
        key = f"user-assets/{self.domain}/{entry['filename']}"
        sha = digest(source); pinned = self.lock["files"].get(key, {}).get("sha256")
        if pinned and sha != pinned: raise RuntimeError(f"{source} differs from the pinned download ({key})")
        self.lock["files"][key] = {"url": entry["page"], "sha256": sha, "size": source.stat().st_size}
        dest = ROOT / entry["dest"]
        if entry.get("extract"): self.copy_tree(self.extract(source, None), dest, entry.get("include"), files)
        else: self.deliver(source, dest / source.name, files)
        return provenance

    def url(self, entry: dict, files: list) -> dict:
        name = entry.get("filename") or Path(urllib.parse.urlparse(entry["url"]).path).name
        cached = self.download(entry["url"], CACHE / "url" / entry["id"] / name)
        if entry.get("sha256") and not self.dry_run and digest(cached) != entry["sha256"]: raise RuntimeError(f"SHA-256 mismatch for {entry['id']}")
        dest = ROOT / entry["dest"]
        if entry.get("extract"): self.copy_tree(self.extract(cached, None), dest, entry.get("include"), files)
        else: self.deliver(cached, dest / name, files)
        return {"source_page": entry.get("page", entry["url"]), "license": entry["license"], "creator": entry["creator"]}

    def run(self, only: list[str]) -> None:
        for entry in self.spec.get("assets", []):
            if only and entry["id"] not in only: continue
            files: list = []
            print(f"FETCH {self.domain}/{entry['id']} ({entry['source']})", flush=True)
            provenance = getattr(self, entry["source"])(entry, files)
            if not self.dry_run:
                self.manifest["assets"][entry["id"]] = {**provenance, "source": entry["source"], "type": entry.get("type"), "files": files, "fetched_unix": int(time.time())}
        if self.dry_run: return
        self.lock_path.write_text(json.dumps(self.lock, indent=2, sort_keys=True) + "\n")
        self.manifest_path.parent.mkdir(parents=True, exist_ok=True)
        self.manifest_path.write_text(json.dumps(self.manifest, indent=2, sort_keys=True) + "\n")
        print(f"FETCH PASS {self.domain} ({self.spec_path.relative_to(ROOT) if self.spec_path.is_relative_to(ROOT) else self.spec_path})", flush=True)

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--domain", required=True, choices=["maps", "weapons", "characters"])
    parser.add_argument("--only", nargs="*", default=[])
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--map", help="Maps only: fetch just content/asset_sources/maps/<id>.json")
    parser.add_argument("--spec", type=Path, help="Alternate source list (testing); lock and manifest are written beside it")
    args = parser.parse_args()
    if args.spec: Fetcher(args.domain, args.dry_run, args.spec).run(args.only); return
    for spec, manifest in source_specs(args.domain, args.map):
        Fetcher(args.domain, args.dry_run, spec, manifest).run(args.only)

if __name__ == "__main__":
    try: main()
    except Exception as error:
        print(f"FAILED: {error}", file=sys.stderr); sys.exit(1)
