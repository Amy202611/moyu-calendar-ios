import importlib.util,io,pathlib,plistlib,unittest,zipfile
root=pathlib.Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location("ipa_validation",root/"Scripts/validate-ipa.py")
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)

class RegistrationNameTests(unittest.TestCase):
 def valid(self):return {"CFBundleName":"MoyuCalendar","CFBundleDisplayName":"MoyuCalendar"}
 def test_ascii_registration_names_are_accepted(self):
  self.assertEqual(module.validate_registration_names(self.valid()),"MoyuCalendar")
 def test_chinese_raw_display_name_is_rejected(self):
  info=self.valid();info["CFBundleDisplayName"]="摸鱼日历"
  with self.assertRaisesRegex(ValueError,"appIdName"):module.validate_registration_names(info)
 def test_chinese_raw_bundle_name_is_rejected(self):
  info=self.valid();info["CFBundleName"]="摸鱼日历"
  with self.assertRaisesRegex(ValueError,"appIdName"):module.validate_registration_names(info)
 def test_localized_desktop_name_remains_chinese(self):
  data=io.BytesIO();bundle="Payload/MoyuCalendar.app"
  with zipfile.ZipFile(data,"w") as z:
   for lang in ["en","zh-Hans","zh-Hant"]:z.writestr(bundle+"/"+lang+".lproj/InfoPlist.strings",plistlib.dumps({"CFBundleDisplayName":"摸鱼日历"}))
  with zipfile.ZipFile(io.BytesIO(data.getvalue())) as z:
   self.assertEqual(set(module.validate_localized_names(z,bundle).values()),{"摸鱼日历"})
 def test_missing_localization_is_rejected(self):
  data=io.BytesIO()
  with zipfile.ZipFile(data,"w"):pass
  with zipfile.ZipFile(io.BytesIO(data.getvalue())) as z:
   with self.assertRaisesRegex(ValueError,"localized"):module.validate_localized_names(z,"Payload/MoyuCalendar.app")
 def test_source_metadata_has_safe_registration_and_chinese_localizations(self):
  module.validate_registration_names(plistlib.loads((root/"Info.plist").read_bytes()))
  for lang in ["en","zh-Hans","zh-Hant"]:
   value=plistlib.loads((root/("Resources/"+lang+".lproj/InfoPlist.strings")).read_bytes())
   self.assertEqual(value["CFBundleDisplayName"],"摸鱼日历")

if __name__=="__main__":unittest.main()
