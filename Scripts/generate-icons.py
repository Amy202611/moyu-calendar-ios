import json,pathlib,struct,subprocess,zlib
root=pathlib.Path(__file__).resolve().parent.parent
dest=root/"Resources/Assets.xcassets/AppIcon.appiconset";dest.mkdir(parents=True,exist_ok=True)
original=next((root/("Resources/AppIconOriginal."+e) for e in ["png","jpg","jpeg"] if (root/("Resources/AppIconOriginal."+e)).exists()),None)
def png(n):
 rows=[]
 for yy in range(n):
  y=yy/n;row=bytearray()
  for xx in range(n):
   x=xx/n;c=(int(15+10*y),int(125+85*y),245)
   if .13<x<.87 and .18<y<.85:c=(255,253,247)
   if .13<x<.87 and .18<y<.33:c=(255,204,55)
   if ((x-.47)/.25)**2+((y-.59)/.16)**2<1:c=(44,177,236)
   if .65<x<.84 and abs(y-.59)<(x-.65)*.8:c=(44,177,236)
   if ((x-.36)/.02)**2+((y-.55)/.025)**2<1:c=(15,58,126)
   row.extend(c)
  rows.append(b"\0"+row)
 def chunk(k,d):return struct.pack(">I",len(d))+k+d+struct.pack(">I",zlib.crc32(k+d)&0xffffffff)
 return b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",n,n,8,2,0,0,0))+chunk(b"IDAT",zlib.compress(b"".join(rows),9))+chunk(b"IEND",b"")
images=[]
for size,scale,idiom in [(s,k,"iphone") for s in [20,29,40,60] for k in [2,3]]+[(1024,1,"ios-marketing")]:
 n=size*scale;name=f"icon-{n}.png";path=dest/name
 if original:subprocess.run(["sips","-s","format","png","--resampleHeightWidth",str(n),str(n),str(original),"--out",str(path)],check=True,stdout=subprocess.DEVNULL)
 else:path.write_bytes(png(n))
 images.append({"idiom":idiom,"size":f"{size}x{size}","scale":f"{scale}x","filename":name})
(dest/"Contents.json").write_text(json.dumps({"images":images,"info":{"version":1,"author":"xcode"}},indent=2))
(dest.parent/"Contents.json").write_text(json.dumps({"info":{"version":1,"author":"xcode"}}))
