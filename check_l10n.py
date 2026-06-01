import sys, os, glob
sys.stdout.reconfigure(encoding='utf-8', errors='replace')

# Search all dart files in l10n folder
for f in glob.glob('E:/SBOX CURSOR/ZKTecoADMS-master/flutter_client/lib/l10n/*.dart'):
    with open(f, 'r', encoding='utf-8') as fh:
        content = fh.read()
    if 'attendanceApproval' in content and 'Duy' in content:
        print(f'Found in: {f}')
        idx = content.find('attendanceApproval')
        while idx >= 0:
            snippet = content[max(0,idx-5):idx+80]
            if 'Duy' in snippet:
                print(f'  Line: {repr(snippet)}')
                # Check encoding of Vietnamese chars
                for ch in snippet:
                    cp = ord(ch)
                    if cp > 0x00FF:
                        import unicodedata
                        nfc = unicodedata.normalize('NFC', ch)
                        nfd = unicodedata.normalize('NFD', ch)
                        print(f'    char U+{cp:04X}: NFC={repr(nfc)} NFD_len={len(nfd)}')
                break
            idx = content.find('attendanceApproval', idx+1)
        break

# Also search arb files
for f in glob.glob('E:/SBOX CURSOR/ZKTecoADMS-master/flutter_client/lib/**/*.arb', recursive=True) + \
         glob.glob('E:/SBOX CURSOR/ZKTecoADMS-master/flutter_client/l10n/**/*.arb', recursive=True):
    print(f'ARB file: {f}')
