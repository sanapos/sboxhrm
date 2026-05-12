f=r'e:\Flutter\ZKTecoADMS-master\ZKTecoADMS-master\flutter_client\lib\screens\system_admin\landing_content_tab.dart'
s=open(f,'r',encoding='utf-8').read()
lines=s.split('\n')
skip_patterns=['?v=','?.toString','??','orElse','firstWhere','?? {}','?? []','?? \'\'','?? ""']
for i,line in enumerate(lines):
    if '?' not in line: continue
    stripped=line.strip()
    if stripped.startswith('//'): continue
    if any(p in stripped for p in skip_patterns): continue
    # Only check string literals
    if "'" in stripped or '"' in stripped:
        # Skip dart null-safety ? operators
        parts=[p.strip("'\"") for p in stripped.split("'")]
        for p in parts:
            if '?' in p and len(p)>2:
                print(f'L{i+1}: {stripped[:120]}')
                break
