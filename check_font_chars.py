import sys
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
filepath = r'E:/SBOX CURSOR/ZKTecoADMS-master/flutter_client/lib/l10n/app_localizations.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

idx = content.find('attendanceApproval')
if idx >= 0:
    snippet = content[idx:idx+80]
    print('Snippet:', repr(snippet))
    for ch in snippet:
        cp = ord(ch)
        if cp > 127:
            print(f'U+{cp:04X}', end=' ')
    print()

# Check specific chars from common vietnamese words 
test_chars = [0x1ec7, 0x1ea5, 0x00f4, 0x1ed5, 0x1ea7, 0x0103, 0x01a1, 0x01b0, 0x1ee3, 0x1ecb, 0x1ed3]
print('Checking specific chars:')
for cp in test_chars:
    print(f'U+{cp:04X} = chr', end=' ')
