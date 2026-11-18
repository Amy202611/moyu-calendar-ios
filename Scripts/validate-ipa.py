import hashlib,json,pathlib,plistlib,struct,sys,zipfile
def validate(path):
 with zipfile.ZipFile(path) as z:
  infos=[n for n in z.namelist() if n.startswith("Payload/") and n.count("/")==2 and n.endswith(".app/Info.plist")]
  if len(infos)!=1:raise ValueError("Expected exactly one Payload/<app>.app/Info.plist")
  info=plistlib.loads(z.read(infos[0]))
  if info.get("CFBundleSupportedPlatforms")!=["iPhoneOS"]:raise ValueError("Wrong SDK / simulator build")
  exe=info.get("CFBundleExecutable","")
  if not exe or "/" in exe:raise ValueError("Invalid executable")
  binary=z.read(infos[0].rsplit("/",1)[0]+"/"+exe)
  if len(binary)<32:raise ValueError("Missing executable")
  magic,cpu,subtype,kind,count,size,flags,reserved=struct.unpack_from("<8I",binary)
  if (magic,cpu,kind)!=(0xfeedfacf,0x0100000c,2):raise ValueError("Expected thin ARM64 Mach-O executable")
  if count>10000 or size+32>len(binary):raise ValueError("Malformed Mach-O")
  pos=32;platforms=[];encrypted=False
  for _ in range(count):
   if pos+8>len(binary):raise ValueError("Truncated load command")
   cmd,length=struct.unpack_from("<II",binary,pos)
   if length<8 or pos+length>size+32:raise ValueError("Invalid load command")
   if cmd==0x32:platforms.append(struct.unpack_from("<I",binary,pos+8)[0])
   if cmd==0x2c:encrypted|=struct.unpack_from("<I",binary,pos+16)[0]!=0
   pos+=length
  if platforms!=[2] or encrypted:raise ValueError("Not a re-signable real iPhone build")
  if any(n.endswith("/embedded.mobileprovision") for n in z.namelist()):raise ValueError("Unexpected provisioning profile")
  return {"bundleIdentifier":info["CFBundleIdentifier"],"displayName":info.get("CFBundleDisplayName"),"version":info["CFBundleShortVersionString"],"build":info["CFBundleVersion"],"minimumIOS":info.get("MinimumOSVersion"),"architecture":"arm64","platform":"iPhoneOS","unsignedBuild":True,"sideStoreInstallationVerified":False,"sha256":hashlib.sha256(path.read_bytes()).hexdigest()}
if __name__=="__main__":
 p=pathlib.Path(sys.argv[1]);r=validate(p);(p.parent/"ipa-validation.json").write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding="utf-8");print(json.dumps(r,ensure_ascii=False,indent=2))
