import re
rows=[]
for line in open('scan-all.txt',encoding='utf-8'):
    m=re.match(r'\s*([\d.]+) GB\s+(\d+) f\s+(.+)$', line.rstrip())
    if m: rows.append((float(m.group(1)), int(m.group(2)), m.group(3).strip()))
names={r[2] for r in rows}
# leaf = no other bucket starts with name+"\\"
leaves=[r for r in rows if not any(n.startswith(r[2]+"\\") for n in names)]
leaves.sort(key=lambda r:-r[0])
print("== TOP leaf dirs (depth<=3) ==")
for g,c,n in leaves[:26]:
    print("%7.3f GiB  %7d f  %s" % (g,c,n))
print()
print("== depth1 ==")
for g,c,n in rows:
    if "\\" not in n: print("%7.3f GiB  %7d f  %s" % (g,c,n))
tot=sum(r[0] for r in rows if "\\" not in r[2])
print("depth1 sum %.3f GiB"%tot)
