import hashlib,json,pathlib,struct,subprocess
root=pathlib.Path(__file__).resolve().parent.parent
source=root/"Resources/AppIcon.png"
if not source.exists():
 raise SystemExit("error: Resources/AppIcon.png is required; refusing placeholder icon")
raw=source.read_bytes()
expected="a9c3b2515718a2ed779f5794a248d9a04ca489c6"
actual=hashlib.sha1(b"blob "+str(len(raw)).encode()+b"\0"+raw).hexdigest()
if actual!=expected:raise SystemExit("error: app icon artwork differs from the approved generated asset; update its recorded blob SHA intentionally")
if raw[:8]!=b"\x89PNG\r\n\x1a\n":raise SystemExit("error: app icon must be PNG")
width,height=struct.unpack_from(">II",raw,16)
if width!=height or width<1024:raise SystemExit("error: app icon must be square and at least 1024 pixels")
dest=root/"Resources/Assets.xcassets/AppIcon.appiconset"
dest.mkdir(parents=True,exist_ok=True)
images=[]
specs=[(s,k,"iphone") for s in [20,29,40,60] for k in [2,3]]
specs += [(s,k,"ipad") for s in [20,29,40,76] for k in [1,2]]
specs += [(83.5,2,"ipad"),(1024,1,"ios-marketing")]
for size,scale,idiom in specs:
 n=int(size*scale); name=f"icon-{n}.png"; path=dest/name
 subprocess.run(["sips","-s","format","png","--resampleHeightWidth",str(n),str(n),str(source),"--out",str(path)],check=True,stdout=subprocess.DEVNULL)
 images.append({"idiom":idiom,"size":f"{size}x{size}","scale":f"{scale}x","filename":name})
(dest/"Contents.json").write_text(json.dumps({"images":images,"info":{"version":1,"author":"xcode"}},indent=2))
(dest.parent/"Contents.json").write_text(json.dumps({"info":{"version":1,"author":"xcode"}}))
manifest={"source":"AppIcon.png","artwork":"new-generated-artwork","sourceGitBlobSHA":actual,"sourceSHA256":hashlib.sha256(raw).hexdigest(),"width":width,"height":height,"placeholder":False}
(root/"Resources/IconManifest.json").write_text(json.dumps(manifest,indent=2))
print("Verified new app icon artwork:",manifest["sourceSHA256"])
