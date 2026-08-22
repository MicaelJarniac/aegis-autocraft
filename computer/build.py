import os, sys, glob, re

src = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(src)
dst = os.path.join(root, "startup.lua")

# sort by BASENAME. NN_ prefix is the load order, fullpath sort interleaves folders.
lua = []
for p in glob.glob(os.path.join(src, "**", "*.lua"), recursive=True):
	if re.match(r"^\d\d_", os.path.basename(p)):
		lua.append(p)
lua.sort(key=lambda p: os.path.basename(p))

if not lua:
	print("no NN_*.lua under", src)
	sys.exit(1)

seen = {}
for p in lua:
	b = os.path.basename(p)
	if b in seen:
		print(f"dup basename {b}: {seen[b]} vs {p}")
		sys.exit(1)
	seen[b] = p


def clean(body):
	lines = []
	for line in body.split("\n"):
		s = line.lstrip("\t ")
		if s.startswith("--") and not s.startswith("--<") and not s.startswith("-->"):
			continue
		lines.append(s)
	return "\n".join(lines).rstrip("\n")


parts = []
for p in lua:
	rel = os.path.relpath(p, src).replace(os.sep, "/")
	with open(p, encoding="utf-8") as f:
		body = clean(f.read())
	parts.append(f"--<{rel}\n{body}\n-->{rel}")

if os.path.exists(dst):
	bak = dst + ".bak"
	if os.path.exists(bak):
		os.remove(bak)
	os.replace(dst, bak)

with open(dst, "w", encoding="utf-8", newline="") as f:
	f.write("\n".join(parts) + "\n")

print(f"wrote {dst}: {len(lua)} modules")
