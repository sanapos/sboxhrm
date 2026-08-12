"""Login without BACK — ESCAPE dismisses IME; verify focus stays on POS."""
import subprocess
import sys
import time
from pathlib import Path

ADB = r"C:\Users\TH DECOR\AppData\Local\Android\Sdk\platform-tools\adb.exe"
SERIAL = sys.argv[1] if len(sys.argv) > 1 else "V329221L21176"
OUT = Path(r"e:\SBOX CURSOR\ZKTecoADMS-master\.tmp-esp-audit")
PKG = "sbox.sana.vn.pos.flutter"
ACT = f"{PKG}/vn.sana.sbox.sbox_pos.MainActivity"


def adb(*args: str, timeout: float = 20) -> subprocess.CompletedProcess:
    return subprocess.run(
        [ADB, "-s", SERIAL, *args],
        check=False,
        timeout=timeout,
        capture_output=True,
        text=True,
    )


def focused() -> str:
    r = adb("shell", "dumpsys", "window", timeout=12)
    for line in (r.stdout or "").splitlines():
        if "mCurrentFocus" in line or "mFocusedApp" in line:
            return line.strip()
    return ""


def ensure_app() -> None:
    if PKG not in focused():
        adb("shell", "am", "start", "-n", ACT, timeout=10)
        time.sleep(2)


def tap(x: int, y: int) -> None:
    ensure_app()
    adb("shell", "input", "tap", str(x), str(y), timeout=8)
    time.sleep(0.35)


def text(s: str) -> None:
    print(f"  text {s!r} focus={focused()[:80]}", flush=True)
    ensure_app()
    adb("shell", "input", "text", s, timeout=20)
    time.sleep(0.3)


def dismiss_ime() -> None:
    # ESCAPE / hide — not BACK (BACK leaves the app on Sunmi).
    adb("shell", "input", "keyevent", "111", timeout=8)  # ESCAPE
    time.sleep(0.2)
    adb("shell", "input", "keyevent", "4", timeout=8)  # may hide IME
    time.sleep(0.35)
    ensure_app()
    if PKG not in focused():
        adb("shell", "am", "start", "-n", ACT, timeout=10)
        time.sleep(1.5)


def shot(name: str) -> None:
    adb("shell", "screencap", "-p", "/sdcard/v2s.png", timeout=10)
    adb("pull", "/sdcard/v2s.png", str(OUT / name), timeout=10)
    print(f"  shot {name} | {focused()[:100]}", flush=True)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    adb("shell", "am", "force-stop", PKG, timeout=10)
    time.sleep(0.5)
    adb("shell", "am", "start", "-n", ACT, timeout=10)
    time.sleep(4)
    print("focus", focused(), flush=True)
    shot("v2s-login-fresh.png")

    # Tap + type + unfocus via tapping logo (y~200) — no BACK.
    tap(360, 455)
    text("demopos")
    tap(360, 200)  # unfocus
    time.sleep(0.4)

    tap(360, 560)
    text("demopos@gmail.com")
    tap(360, 200)
    time.sleep(0.4)

    tap(360, 680)
    text("123456")
    tap(360, 200)
    time.sleep(0.5)
    shot("v2s-login-filled.png")

    ensure_app()
    tap(360, 1080)
    time.sleep(1)
    tap(360, 1140)
    time.sleep(8)
    shot("v2s-after-login.png")
    print("done", flush=True)


if __name__ == "__main__":
    main()
