# 摸鱼日历 iOS · 原生 SwiftUI

最低 iOS 16，真实 iPhone ARM64。原生月历、农历、双人基础班表、每周/周期/手动排班、独立间隔值班、白班/休息叠加值班、单日备注、半天加班/倒休/年假、加班来源核销、统计、JSON与真正Excel备份恢复、本地通知和中美节假日联网校对。

## 下载与安装

仓库 **Actions → Build iPhone IPA → 最近成功的运行 → Artifacts → MoyuCalendar-ARM64-unsigned-编号-次数**。
下载 Artifact ZIP 后解压，将里面的 **MoyuCalendar-unsigned.ipa** 导入 SideStore。不是直接导入 Artifact ZIP。

不需要 Mac 或付费 Apple Developer Program；GitHub macOS运行器负责 Xcode 编译，SideStore 在手机上使用自己的 Apple ID 重新签名。免费签名通常需定期刷新，也受Apple活跃应用数等限制。iPhone可能要求开启开发者模式。SideStore安装准备见 https://docs.sidestore.io/ 。

构建成功及结构校验不等于在每款真机上的安装已验证。请保留原数据备份，使用同一Apple ID和应用标识更新，避免先卸载应用。

## 自动构建

推送任意代码或发起PR都会构建，Actions中也支持Run workflow手动触发。
使用XcodeGen管理工程。GitHub Actions使用标准macos-15-intel运行池（编译主机为Intel，输出仍是iPhone ARM64）、真实iphoneos SDK、generic/platform=iOS、ARCHS=arm64。
CODE_SIGNING_ALLOWED=NO / CODE_SIGNING_REQUIRED=NO，签名身份和DEVELOPMENT_TEAM均为空，无需在GitHub放Apple ID、证书或描述文件。
直接打包Release-iphoneos下的.app为Payload/*.app，不使用需描述文件的exportArchive。
产物检查Mach-O架构、平台、加密状态、Info.plist与SHA-256，拒绝模拟器构建。
每次运行同时上传日志、诊断；默认保留30天。公共仓库标准托管运行器通常免费，私有仓库受账户额度影响。

## 数据与平台差异

首次运行没有演示记录。安卓JSON和包含“完整恢复数据”的Excel备份可导入；普通手工统计Excel不能还原。
导入先校验，确认后替换；完整恢复表包含全部人员及历史数据，不受统计筛选影响。
独立值班不自动记加班，基础休息可以另有值班。
中国内置2026年公开源整理的放假补班数据；holiday-cn和Nager.Date是公开维护来源，并非政府官方接口。未收录年度不推算官方调休。联网失败保留缓存，不上传个人记录。
节假日更新在前台/网络恢复时按6小时间隔检查，不保证iOS后台持续执行。
本地通知按最近60条安排，受系统权限及专注模式影响，不是持续响铃闹钟。
此免费侧载版不包含App Groups/WidgetKit扩展、安卓小组件或远程推送服务器。

原图可保存为Resources/AppIconOriginal.png或.jpg，CI会生成图标尺寸；无原图时使用简约日历鱼图案，不声称与安卓原图完全一致。

## 日志与修复

Scripts/diagnose.py自动提取源文件错误、签名问题和网络故障。只对识别出的临时依赖问题重试一次，不把普通代码错误靠重跑伪装成修复。
有仓库权限的编码代理可读取失败日志、修改、提交并让push重新构建；GitHub Actions本身不会自动理解并修复任意Swift代码。未建立持续运行代理前，不应称为无人值守自动修复。

## 构建命令

swift test
bash Scripts/build-ipa.sh

Windows无需Xcode；后续提交代码即可获取新IPA。ZIPFoundation固定0.9.19（MIT）：https://github.com/weichsel/ZIPFoundation/blob/0.9.19/LICENSE

## 1.3.1 SideStore 注册名称兼容修复

针对 Apple 拒绝 appIdName=摸鱼日历 的安装错误，根 Info.plist 的 CFBundleName 和 CFBundleDisplayName 改为 ASCII 的 MoyuCalendar；桌面中文名称通过 en/zh-Hans/zh-Hant 的 InfoPlist.strings 保留。SideStore 列表或注册过程显示 MoyuCalendar 属正常。bundle ID 仍为 com.banli.shift。

流水线新增注册名称回归测试，并在实际 IPA 中检查英文注册名称和中文本地化资源。此检查不等同于已在用户 iPhone 上完成签名安装；安装仍需使用新版 IPA 在 SideStore 重试。
