"""Build the isolated Reflect Demo; never alter the tracked project or real saves."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import urllib.request
import zipfile

VERSION = "4.6.3"
ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / ".demo-build"
PROJECT = WORK / "project"
LOGS = ROOT / "build-logs"
DIST = ROOT / "dist" / "FOLDLIGHT_Demo"


def download(asset: dict, target: Path) -> None:
    expected = asset.get("digest", "")
    if not expected.startswith("sha256:"):
        raise RuntimeError("Official release has no SHA256 digest: " + asset["name"])
    for attempt in range(3):
        try:
            h = hashlib.sha256()
            request = urllib.request.Request(asset["browser_download_url"], headers={"User-Agent": "FOLDLIGHT-demo-builder"})
            with urllib.request.urlopen(request, timeout=120) as response, target.open("wb") as output:
                while chunk := response.read(1024 * 1024):
                    output.write(chunk)
                    h.update(chunk)
            if h.hexdigest() != expected.split(":", 1)[1]:
                raise RuntimeError("SHA256 mismatch for " + target.name)
            print("Verified", asset["name"], target.stat().st_size, flush=True)
            return
        except Exception:
            if attempt == 2:
                raise
            time.sleep(2 + attempt)


def run(label: str, command: list[str], marker: str = "", timeout: int = 240) -> None:
    print("RUN", label, flush=True)
    logfile = LOGS / (label + ".log")
    result = subprocess.run(command + ["--log-file", str(logfile)], cwd=PROJECT,
                            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
    output = result.stdout + result.stderr
    if logfile.exists():
        output += "\n" + logfile.read_text(encoding="utf-8", errors="replace")
    (LOGS / (label + "-combined.txt")).write_text(output, encoding="utf-8")
    print(output[-28000:], flush=True)
    bad = re.search(r"SCRIPT ERROR:|Parse Error:|Compile Error:|Failed to load script|ERROR:", output)
    if result.returncode or bad or (marker and marker not in output):
        raise RuntimeError(f"{label} failed: exit={result.returncode}; inspect build-logs")


def prepare() -> None:
    if PROJECT.exists():
        shutil.rmtree(PROJECT)
    shutil.copytree(ROOT / "foldlight", PROJECT, ignore=shutil.ignore_patterns(
        ".godot", ".codex-runtime", "artifacts", "docs", "*.exe", "*.pck", "*.zip", "__pycache__"))
    project_file = PROJECT / "project.godot"
    text = project_file.read_text(encoding="utf-8-sig")
    text = re.sub(r'^config/name=.*$', 'config/name="FOLDLIGHT Reflect Demo"', text, flags=re.M)
    text = re.sub(r'^config/version=.*$', 'config/version="0.1.0-demo"', text, flags=re.M)
    text = re.sub(r'^run/main_scene=.*$', 'run/main_scene="res://rebuild/scenes/boss_lab.tscn"', text, flags=re.M)
    text = re.sub(r'^.*\.pixel_demo=.*\n?', '', text, flags=re.M)
    text = text.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="FOLDLIGHT_ReflectDemo"')
    project_file.write_text(text, encoding="utf-8")
    (PROJECT / "export_presets.cfg").write_text('''[preset.0]
name="Windows Demo"
platform="Windows Desktop"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter="rebuild/config/*.json"
exclude_filter="tests/*,tools/*,docs/*,artifacts/*,*.md,*.ps1,.codex-runtime/*"
export_path=""
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]
custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=0
binary_format/embed_pck=true
binary_format/architecture="x86_64"
codesign/enable=false
application/modify_resources=false
texture_format/bptc=true
texture_format/s3tc=true
texture_format/etc2=false
texture_format/etc2_astc=false
''', encoding="utf-8")


def main() -> None:
    if sys.platform != "win32":
        raise SystemExit("Run on Windows: the build validates the actual Windows executable.")
    WORK.mkdir(exist_ok=True)
    LOGS.mkdir(exist_ok=True)
    DIST.mkdir(parents=True, exist_ok=True)
    url = f"https://api.github.com/repos/godotengine/godot-builds/releases/tags/{VERSION}-stable"
    headers = {"User-Agent": "FOLDLIGHT-demo-builder", "Accept": "application/vnd.github+json"}
    if os.environ.get("GH_TOKEN"):
        headers["Authorization"] = "Bearer " + os.environ["GH_TOKEN"]
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as response:
        release = json.load(response)
    assets = {asset["name"]: asset for asset in release["assets"]}
    editor_name = f"Godot_v{VERSION}-stable_win64.exe.zip"
    templates_name = f"Godot_v{VERSION}-stable_export_templates.tpz"
    download(assets[editor_name], WORK / "editor.zip")
    with zipfile.ZipFile(WORK / "editor.zip") as archive:
        archive.extractall(WORK / "engine")
    engine = next((WORK / "engine").glob("*_console.exe"))
    prepare()
    run("import", [str(engine), "--headless", "--path", str(PROJECT), "--import"])
    run("mechanics", [str(engine), "--headless", "--path", str(PROJECT), "--script", "res://rebuild/tests/test_ci_demo.gd"], "FOLDLIGHT_DEMO_TESTS_PASS")
    download(assets[templates_name], WORK / "templates.tpz")
    target = Path(os.environ["APPDATA"]) / "Godot" / "export_templates" / f"{VERSION}.stable"
    target.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(WORK / "templates.tpz") as archive:
        for info in archive.infolist():
            name = Path(info.filename).name
            if name.startswith("windows_") or name == "version.txt":
                if not info.is_dir():
                    (target / name).write_bytes(archive.read(info))
    exe = DIST / "FOLDLIGHT_Demo.exe"
    run("export", [str(engine), "--headless", "--path", str(PROJECT), "--export-release", "Windows Demo", str(exe)], timeout=420)
    if not exe.exists() or exe.stat().st_size < 10000000 or exe.read_bytes()[:2] != b"MZ":
        raise RuntimeError("Export did not create a valid-sized PE executable")
    run("windows-exe-smoke", [str(exe), "--headless", "--", "--demo-smoke-test"], "FOLDLIGHT_EXE_SMOKE_PASS", timeout=90)
    digest = hashlib.sha256(exe.read_bytes()).hexdigest()
    (DIST / "SHA256.txt").write_text(digest + "  FOLDLIGHT_Demo.exe\n", encoding="ascii")
    (DIST / "README_先看这里.txt").write_text(
        "FOLDLIGHT 折光 · 反弹战斗 Demo\n\n解压整个压缩包，双击 FOLDLIGHT_Demo.exe。无需安装 Godot、Python 或其他开发软件。\n"
        "WASD / 方向键：移动\n空格：按住收弹，松开发射\nShift：冲刺（持有弹药时先反弹再冲刺）\nEsc：暂停 / 继续\n"
        "Normal：标准难度；Relaxed：较轻松；Challenge：挑战。鼠标点击开始。\n"
        "紫色弹可收纳；黑芯金边弹要躲开。死亡后 Retry 直接重试。\n\n"
        "此包是单 Boss 试玩，不是完整战役。已做 Windows 导入、机制及 EXE 无界面启动检查；未做人工手感验收。\n"
        "程序未做商业代码签名。不要为运行本游戏关闭杀毒软件。\n", encoding="utf-8-sig")
    shutil.copy2(ROOT / "LICENSE", DIST / "LICENSE.txt")
    (DIST / "BUILD_INFO.json").write_text(json.dumps({
        "commit": os.environ.get("GITHUB_SHA", "local"), "godot": VERSION,
        "windows_headless_smoke": "passed", "sha256": digest,
        "manual_playtest": "not performed by CI"}, indent=2), encoding="utf-8")
    print("WINDOWS_DEMO_BUILD_PASS", digest, flush=True)


if __name__ == "__main__":
    main()
