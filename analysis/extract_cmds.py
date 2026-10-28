import re, sys, json
D = sys.argv[1]
lines = open(D, errors="replace").read().split("\n")
sym_re = re.compile(r"literal pool symbol address: (__ZN1[45](?:EMHidCmdHelper|EMHidCmdV1Helper)\d+(CMD_[A-Z0-9_]+)E)$")
mov_re = re.compile(r"mov\tw([1-4]), #(0x[0-9a-f]+|\d+)")
ctor_re = re.compile(r"bl\t__ZN14EMHidCmdV(1|2)HeadC[12]E")
out = {}
for i, ln in enumerate(lines):
    m = sym_re.search(ln)
    if not m: continue
    mangled, name = m.group(1), m.group(2)
    helper = "V1" if "V1Helper" in mangled else "V2"
    args = {}
    ver = None
    for j in range(i+1, min(i+10, len(lines))):
        mm = mov_re.search(lines[j])
        if mm: args[int(mm.group(1))] = int(mm.group(2), 0); continue
        mc = ctor_re.search(lines[j])
        if mc: ver = mc.group(1); break
        if "\tbl\t" in lines[j] or "\tb\t" in lines[j]: break
    if ver and len(args) >= 3:
        head = [args.get(k, 0) for k in (1,2,3,4)]
        key = f"{helper}:{name}"
        if key in out and out[key] != head: print("CONFLICT", key, out[key], head, file=sys.stderr)
        out[key] = head
json.dump(out, open(sys.argv[2], "w"), indent=1)
print(len(out), "heads extracted")
