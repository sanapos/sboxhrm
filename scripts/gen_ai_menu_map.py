# Sinh src/ZKTecoADMS.Api/Services/AiAssistantMenuMap.cs (đường dẫn menu cho Trợ lý AI) từ menu của app.
# Chạy lại khi đổi tên / nhóm menu: python scripts/gen_ai_menu_map.py
import io
import os
import re
R = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
s = open(R + r'\flutter_client\lib\screens\main_layout.dart', encoding='utf-8').read()
start = s.index('NavItem(')
entries = {}
for m in re.finditer(r'NavItem\((.*?)\n    \),', s[start:], re.S):
    body = m.group(1)
    lab = re.search(r"label: '([^']*)'", body)
    grp = re.search(r"group: '([^']*)'", body)
    mod = re.search(r"moduleCode: '([^']*)'", body)
    side = re.search(r"showInSidebar: (true|false)", body)
    if not (lab and mod):
        continue
    code = mod.group(1)
    if side and side.group(1) == 'false' and code in entries:
        continue
    path = (grp.group(1) + ' › ' if grp else '') + lab.group(1)
    entries.setdefault(code, path)

c = open(R + r'\flutter_client\lib\utils\settings_hub_catalog.dart', encoding='utf-8').read()
for m in re.finditer(r"label: '([^']*)', groupTitle: (\w+)", c):
    pass
# Mục Thiết lập SBOX: code nội bộ → «Thiết lập SBOX › <tên>» (theo moduleCode của mục nếu có).
for m in re.finditer(r"SettingsHubItemDef\((.*?)\),\n", c, re.S):
    body = m.group(1)
    lab = re.search(r"label: '([^']*)'", body)
    mod = re.search(r"moduleCode: '([^']*)'", body)
    if lab and mod and mod.group(1) not in entries:
        entries[mod.group(1)] = 'Thiết lập SBOX › ' + lab.group(1)

out = io.StringIO()
out.write('namespace ZKTecoADMS.Api.Services;\n\n')
out.write('/// <summary>\n/// Đường dẫn menu đúng như trên app (nhóm › tên menu) theo mã chức năng — sinh từ\n')
out.write('/// flutter_client/lib/screens/main_layout.dart + settings_hub_catalog.dart (scripts/gen_ai_menu_map.py).\n')
out.write('/// Đổi tên / nhóm menu trên app thì chạy lại script sinh file này.\n/// </summary>\n')
out.write('public static class AiAssistantMenuMap\n{\n')
out.write('    public static readonly IReadOnlyDictionary<string, string> Paths = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)\n    {\n')
for k, v in entries.items():
    out.write(f'        ["{k}"] = "{v}",\n')
out.write('    };\n}\n')
open(R + r'\src\ZKTecoADMS.Api\Services\AiAssistantMenuMap.cs', 'w', encoding='utf-8').write(out.getvalue())
print(len(entries))
for k in ['BonusPenalty', 'HrAnalyticsReport', 'AttendanceApproval', 'Feedback', 'Meal', 'KPI', 'PosSell', 'SettingsHub', 'Leave']:
    print(k, '->', entries.get(k))
