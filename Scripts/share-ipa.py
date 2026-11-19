"""Extract existing, verified IPA files and expose direct Release downloads.
No source rebuild, Apple certificate, or user credentials are needed here.
"""
import hashlib,json,os,pathlib,re,shutil,subprocess,sys,zipfile,plistlib
ROOT=pathlib.Path("release")
REPO=os.environ["GITHUB_REPOSITORY"]
def gh(*args):
 return subprocess.run(["gh",*args],check=True,capture_output=True,text=True).stdout
def run_metadata():
 data=json.loads((ROOT/"run.json").read_text())
 if data["name"]!="Build iPhone IPA" or data["head_branch"]!="main" or data["conclusion"]!="success" or data["repository"]["full_name"]!=REPO or data["event"] not in ["push","workflow_dispatch"]:
  raise ValueError("Only a successful main-branch device build can be shared")
 return data
def publish():
 run=run_metadata()
 records=[]
 for folder,report_name,widget,title in [
  ("basic","ipa-validation.json",False,"基础版"),
  ("widgets","widget-validation.json",True,"小组件版")
 ]:
  location=ROOT/folder
  report=json.loads((location/report_name).read_text())
  files=list(location.glob("*.ipa"))
  if len(files)!=1:raise ValueError("Expected exactly one IPA in "+folder)
  source=files[0]
  digest=hashlib.sha256(source.read_bytes()).hexdigest()
  if digest!=report.get("sha256"):raise ValueError("IPA differs from macOS validation report")
  if report.get("bundleIdentifier")!="com.banli.shift" or report.get("architecture")!="arm64" or report.get("platform")!="iPhoneOS" or report.get("widgetExtensionIncluded") is not widget or report.get("sideStoreInstallationVerified") is not False:
   raise ValueError("Unexpected IPA validation metadata")
  if widget and report.get("signatureType")!="ad-hoc-entitlements-carrier":raise ValueError("Wrong widget package")
  if not widget and report.get("unsignedBuild") is not True:raise ValueError("Basic package must remain unsigned")
  if str(report["build"])!=str(run["run_number"]):raise ValueError("Build number does not match source run")
  version=report["version"]
  if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,3}",version):raise ValueError("Invalid version")
  with zipfile.ZipFile(source) as archive:
   if archive.testzip() is not None:raise ValueError("Corrupt IPA")
   infos=[n for n in archive.namelist() if n.startswith("Payload/") and n.count("/")==2 and n.endswith(".app/Info.plist")]
   if len(infos)!=1:raise ValueError("Invalid Payload")
   info=plistlib.loads(archive.read(infos[0]))
   if info["CFBundleIdentifier"]!="com.banli.shift" or info["CFBundleShortVersionString"]!=version or str(info["CFBundleVersion"])!=str(run["run_number"]):raise ValueError("IPA metadata mismatch")
  destination=ROOT/"files"/("摸鱼日历-"+version+"-"+title+".ipa")
  shutil.copyfile(source,destination)
  shutil.copyfile(location/report_name,ROOT/"files"/report_name)
  records.append({"name":destination.name,"sha256":digest,"size":destination.stat().st_size,"version":version})
 if records[0]["version"]!=records[1]["version"]:raise ValueError("Package versions differ")
 tag="v"+records[0]["version"]+"-build"+str(run["run_number"])+"-attempt"+str(run["run_attempt"])
 notes=(
  "原生 iPhone ARM64 · iOS 16 及以上。\n\n"
  "直接下载下面的 .ipa 文件即可分享，无需解压 Actions Artifact。\n"
  "基础版完全未签名；小组件版带 ad-hoc 权限载体，均需收件人用自己的 SideStore/Apple ID 重签安装。小组件版需保留扩展与共享权限。\n"
  "未验证收件人真机安装；分享 IPA 不等于已签名或可直接点击安装。\n\n"
  "源构建："+run["html_url"]+"\n提交："+run["head_sha"]+"\n"
 )
 (ROOT/"notes.md").write_text(notes,encoding="utf-8")
 (ROOT/"files"/"SHA256SUMS.txt").write_text("".join(item["sha256"]+"  "+item["name"]+"\n" for item in records),encoding="utf-8")
 existing=subprocess.run(["gh","release","view",tag,"--repo",REPO,"--json","isDraft"],capture_output=True,text=True)
 if existing.returncode!=0:
  gh("release","create",tag,"--repo",REPO,"--target",run["head_sha"],"--draft","--title","摸鱼日历 "+records[0]["version"]+" · build "+str(run["run_number"]),"--notes-file",str(ROOT/"notes.md"),*[str(p) for p in sorted((ROOT/"files").iterdir())])
 data=json.loads(gh("api","repos/"+REPO+"/releases/tags/"+tag))
 assets={a["name"]:a for a in data["assets"]}
 for record in records:
  asset=assets.get(record["name"])
  if not asset or asset["size"]!=record["size"] or asset.get("digest")!="sha256:"+record["sha256"]:
   raise ValueError("Published IPA asset digest or size does not match verified source")
 if data["draft"]:gh("release","edit",tag,"--repo",REPO,"--draft=false")
 data=json.loads(gh("api","repos/"+REPO+"/releases/tags/"+tag))
 if data["draft"]:raise ValueError("Release is still a draft")
 links=[{"name":a["name"],"url":a["browser_download_url"],"size":a["size"],"digest":a.get("digest")} for a in data["assets"] if a["name"].endswith(".ipa")]
 print(json.dumps({"sourceRun":run["id"],"sourceSHA":run["head_sha"],"release":data["html_url"],"tag":tag,"files":links},ensure_ascii=False,indent=2))
 with open(os.environ["GITHUB_STEP_SUMMARY"],"a",encoding="utf-8") as summary:
  summary.write("## 可直接下载和分享的 IPA\n\n")
  for link in links:summary.write("- ["+link["name"]+"]("+link["url"]+")\n")
if __name__=="__main__":
 if sys.argv[1]=="check-run":run_metadata();print("Verified successful source run")
 elif sys.argv[1]=="publish":publish()
 else:raise ValueError("Unknown command")
