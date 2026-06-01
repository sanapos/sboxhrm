# Dart UTF-8 encoding (SBOX Flutter)

## Prevention

- `.editorconfig` and VS Code `files.encoding: utf8` — always save Dart as UTF-8.
- Dialog batch scripts (`wrap_alert_dialog_*.py`, `fix_dialog_extra_parens.py`) read/write **UTF-8 only** (no `cp1252`, no `errors="replace"`).
- `run-local-tests.ps1` runs `check-dart-encoding.py` before build.

## If corruption appears again

```powershell
python scripts/repair-dart-encoding.py
python scripts/check-dart-encoding.py
```

Repair converts mixed Latin-1 bytes to UTF-8 and applies known broken→fixed phrases.  
Check fails on `U+FFFD` and common mojibake markers (`Thi?t`, `B?o hi?m`, …).

Do **not** run old dialog wrap scripts on the whole tree without a clean encoding check first.
