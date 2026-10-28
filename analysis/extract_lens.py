import re, sys, json
D = sys.argv[1]
lines = open(D, errors="replace").read().split("\n")
label_re = re.compile(r"^__ZN14EMHidCmdHelper\d+(hidCmdSend[A-Za-z0-9]+)E.*:$")
res = {}
cur = None; lastw3 = None; lastw4 = None
for ln in lines:
    m = label_re.match(ln)
    if m:
        cur = m.group(1); lastw3 = None; continue
    if cur is None: continue
    if re.match(r"^__Z", ln) or re.match(r"^_[A-Za-z]", ln):  # new symbol
        cur = None; continue
    mm = re.search(r"mov\tw3, #(0x[0-9a-f]+|\d+)", ln)
    if mm: lastw3 = int(mm.group(1), 0)
    if re.search(r"mov\tx3, ", ln): lastw3 = "var"
    if "bl\t__ZN14EMHidCmdHelper10hidCmdSendE" in ln:
        res.setdefault(cur, []).append(lastw3)
for k in sorted(res): print("%-40s len=%s" % (k, res[k]))
