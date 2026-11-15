"""Loads the addon in Lua 5.1 against a stubbed WoW API and exercises it."""
import sys, re
from pathlib import Path
import lupa.lua51 as lupa

root = Path(__file__).resolve().parent.parent / 'ItemInfo'
locale = sys.argv[1] if len(sys.argv) > 1 else 'enUS'
lua = lupa.LuaRuntime(unpack_returned_tuples=True)
lua.execute(open(Path(__file__).parent / 'stubs.lua', encoding='utf-8').read())
lua.globals().TEST_LOCALE = locale
ns = lua.table()
for line in (root / 'ItemInfo.toc').read_text().splitlines():
    line = line.strip()
    if not line or line.startswith('#'): continue
    src = (root / line.replace('\\', '/')).read_text(encoding='utf-8')
    fn = lua.eval('function(src, name) return assert(loadstring(src, name)) end')(src, '@' + line)
    fn('ItemInfo', ns)
lua.globals().NS = ns
lua.execute(open(Path(__file__).parent / 'scenario.lua', encoding='utf-8').read())
print('OK', locale)
