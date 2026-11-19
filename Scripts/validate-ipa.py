import hashlib,json,pathlib,plistlib,re,struct,sys,zipfile,subprocess,tempfile
def validate_registration_names(info):
 for key in ["CFBundleName","CFBundleDisplayName"]:
  name=info.get(key)
  if not isinstance(name,str) or re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9 ]{0,49}",name) is None:
   raise ValueError(key+" must use a safe ASCII registration name for SideStore appIdName")
 return info["CFBundleDisplayName"]

def validate_localized_names(archive,root):
 names={}
 for language in ["en","zh-Hans","zh-Hant"]:
  path=root+"/"+language+".lproj/InfoPlist.strings"
  if path not in archive.namelist():raise ValueError("Missing localized desktop name: "+language)
  value=plistlib.loads(archive.read(path))
  if value.get("CFBundleDisplayName")!="摸鱼日历":raise ValueError("Localized desktop display name changed: "+language)
  names[language]=value["CFBundleDisplayName"]
 return names

def validate(path,widgets=False):
 with zipfile.ZipFile(path) as z:
  infos=[n for n in z.namelist() if n.startswith("Payload/") and n.count("/")==2 and n.endswith(".app/Info.plist")]
  if len(infos)!=1:raise ValueError("Expected exactly one Payload/<app>.app/Info.plist")
  info=plistlib.loads(z.read(infos[0]))
  registration_name=validate_registration_names(info)
  root=infos[0].rsplit("/",1)[0]
  localized_names=validate_localized_names(z,root)
  if root+"/china2026.json" not in z.namelist():raise ValueError("Missing bundled Chinese holiday data")
  if json.loads(z.read(root+"/china2026.json")).get("year")!=2026:raise ValueError("Wrong bundled holiday year")
  if not info.get("CFBundleIcons",{}).get("CFBundlePrimaryIcon",{}).get("CFBundleIconFiles"):raise ValueError("Missing compiled app icon metadata")
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
  extensions=[n for n in z.namelist() if n.startswith(root+"/PlugIns/") and n.endswith(".appex/Info.plist")]
  if widgets:
   if len(extensions)!=1:raise ValueError("Expected one WidgetKit extension")
   extension=plistlib.loads(z.read(extensions[0]))
   validate_registration_names(extension)
   if extension.get("CFBundleIdentifier")!="com.banli.shift.widgets":raise ValueError("Widget identity changed")
   if extension.get("NSExtension",{}).get("NSExtensionPointIdentifier")!="com.apple.widgetkit-extension":raise ValueError("Wrong extension type")
   if extension.get("CFBundleVersion")!=info.get("CFBundleVersion"):raise ValueError("Extension build mismatch")
   extension_root=extensions[0].rsplit("/",1)[0]
   extension_binary=z.read(extension_root+"/"+extension["CFBundleExecutable"])
   if struct.unpack_from("<II",extension_binary)!=(0xfeedfacf,0x0100000c):raise ValueError("Widget must be thin ARM64")
   if extension.get("CFBundleSupportedPlatforms")!=["iPhoneOS"]:raise ValueError("Widget built for wrong SDK")
   with tempfile.TemporaryDirectory() as folder:
    if any(".." in pathlib.PurePosixPath(n).parts or n.startswith("/") for n in z.namelist()):raise ValueError("Invalid archive paths")
    z.extractall(folder)
    for bundle_root in [root,extension_root]:
     bundle=pathlib.Path(folder)/bundle_root
     subprocess.run(["codesign","--verify","--strict",str(bundle)],check=True,capture_output=True)
     ent=subprocess.run(["codesign","-d","--entitlements",":-",str(bundle)],check=True,capture_output=True)
     groups=plistlib.loads(ent.stdout).get("com.apple.security.application-groups")
     if groups!=["group.com.banli.shift.shared"]:raise ValueError("Missing shared App Group entitlement")
  elif extensions:raise ValueError("Basic unsigned package unexpectedly contains an extension")
  if info["CFBundleIdentifier"]!="com.banli.shift":raise ValueError("Main identity changed")
  return {"bundleIdentifier":info["CFBundleIdentifier"],"displayName":info.get("CFBundleDisplayName"),"registrationName":registration_name,"bundleName":info["CFBundleName"],"localizedDisplayNames":localized_names,"version":info["CFBundleShortVersionString"],"build":info["CFBundleVersion"],"minimumIOS":info.get("MinimumOSVersion"),"architecture":"arm64","platform":"iPhoneOS","unsignedBuild":not widgets,"signatureType":"ad-hoc-entitlements-carrier" if widgets else "unsigned","widgetExtensionIncluded":widgets,"sideStoreInstallationVerified":False,"sha256":hashlib.sha256(path.read_bytes()).hexdigest()}
if __name__=="__main__":
 p=pathlib.Path(sys.argv[1]);widgets="--widgets" in sys.argv;r=validate(p,widgets=widgets);(p.parent/("widget-validation.json" if widgets else "ipa-validation.json")).write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding="utf-8");print(json.dumps(r,ensure_ascii=False,indent=2))
