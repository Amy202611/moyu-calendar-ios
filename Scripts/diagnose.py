import json,pathlib,re,sys
root=pathlib.Path(sys.argv[1] if len(sys.argv)>1 else "build");root.mkdir(parents=True,exist_ok=True)
text="\n".join(p.read_text(errors="replace") for p in sorted(root.glob("*.log")))
errors=[s.strip()[:1500] for s in text.splitlines() if re.search(r"\berror:|fatal error:|BUILD FAILED|TEST FAILED",s)]
transient=bool(re.search(r"(?i)timed out|connection (?:was )?reset|could not resolve host|failed to clone|unable to access.*https",text))
compiler=bool(re.search(r"\.swift:\d+:\d+:\s*(?:fatal )?error:",text));retryable=transient and not compiler
if "--retryable" in sys.argv:sys.exit(0 if retryable else 1)
hints=[]
if re.search(r"(?i)provisioning profile|development team|signing.*requires",text):hints.append("Inspect CODE_SIGNING_ALLOWED=NO and CODE_SIGNING_REQUIRED=NO.")
if compiler:hints.append("Read the source line and fix Swift code; retries without changes are not a repair.")
if transient:hints.append("A transient dependency/network failure was detected; bounded retry is enabled.")
if not hints:hints.append("Inspect job steps and logs for setup, tests or IPA packaging failures.")
report={"errors":errors[-40:],"retryableTransientFailure":retryable,"hints":hints,"automaticSourceRepair":False}
(root/"diagnosis.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
(root/"diagnosis.md").write_text("# Build diagnosis\n\n"+"\n".join("- "+h for h in hints)+"\n\n~~~text\n"+"\n".join(errors[-40:])+"\n~~~\n",encoding="utf-8")
