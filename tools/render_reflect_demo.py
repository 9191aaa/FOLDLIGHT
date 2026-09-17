"""Render actual Godot frames on an Xvfb/Mesa runner; no generated concept images."""
from __future__ import annotations
import os
import zipfile
from build_reflect_demo import ROOT, WORK, LOGS, PROJECT, VERSION, release_assets, download, prepare, run


def main() -> None:
    WORK.mkdir(exist_ok=True)
    LOGS.mkdir(exist_ok=True)
    previews = ROOT / "render-previews"
    previews.mkdir(exist_ok=True)
    assets = release_assets()
    name = f"Godot_v{VERSION}-stable_linux.x86_64.zip"
    download(assets[name], WORK / "linux-editor.zip")
    with zipfile.ZipFile(WORK / "linux-editor.zip") as archive:
        archive.extractall(WORK / "linux-engine")
    engine = next((WORK / "linux-engine").glob("*.x86_64"))
    engine.chmod(0o755)
    prepare()
    run("linux-import", [str(engine), "--headless", "--path", str(PROJECT), "--import"])
    os.environ["LIBGL_ALWAYS_SOFTWARE"] = "1"
    os.environ["FOLDLIGHT_PREVIEW_DIR"] = str(previews)
    run("render-preview", ["xvfb-run", "-a", str(engine), "--path", str(PROJECT),
                          "--rendering-method", "gl_compatibility", "--audio-driver", "Dummy",
                          "--script", "res://rebuild/tests/capture_demo.gd", "--", "--capture-preview"],
        "FOLDLIGHT_RENDER_PREVIEW_PASS", timeout=180)
    if len(list(previews.glob("*.png"))) != 5:
        raise RuntimeError("Expected five rendered previews")


if __name__ == "__main__":
    main()
