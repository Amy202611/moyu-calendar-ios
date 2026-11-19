# 摸鱼日历 · Native iPhone

Swift + SwiftUI，iOS 16 起，真机 ARM64。固定应用标识：`com.banli.shift`。Windows 用户通过 GitHub Actions 的 macOS/Xcode 运行器打包，无需本地 Xcode 或付费 Apple 开发者会员。

## 功能

- 两人独立排班：按星期、循环序列、手动基础班表；独立值班按起始日与间隔轮换，白班或休息可叠加值班。规则预览、时间、跨夜、单日修改/取消/恢复和备注。
- 加班、倒休、年假：半天/全天/15分钟时长，上午/下午备注；倒休 FIFO 或手动选加班来源，保留原始日期及备注，防止超额核销或删除已被核销的来源。
- 年假额度、已休、已安排、剩余分开显示；日历首页、统计筛选、基础夜班/休息/独立值班、加班销假台账、配色设置。
- 中国/美国节假日、农历、联网校对与缓存、按年/月/国家/类型筛选、节假日 Excel；可授权读取手机里所选节假日日历的全天事件。
- 真正的 XLSX 导出（统计、明细、来源、余额、年假、每日排班、完整恢复数据、节假日），JSON/XLSX 恢复，保留 BANLI_BACKUP_V1 和旧版记录兼容。
- 按人员、白班/夜班/值班分别选择本地通知，提前时间、明日简报、自定义提醒、测试、关闭/5分钟后再提醒。
- WidgetKit 今日卡片与月历，分别提供我/搭班人/两人，农历/节假日/备注/颜色和统计，点击日期跳到应用。

## 构建和下载

推送或 PR 自动运行 `Build iPhone IPA`；也可在 Actions 页面点 Run workflow。XcodeGen 管理工程，Xcode 构建时始终关闭自动签名：`CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`。

每次构建先执行 Python 元数据测试、Swift 核心与 Excel 测试，然后编译真机应用及小组件、检查结构并上传两个独立 Artifact：

1. `MoyuCalendar-ARM64-unsigned-...`：完全未签名基础版，无 Widget 扩展，保留应用内功能。解压 ZIP 后用 SideStore 的加号导入其中的 IPA。
2. `MoyuCalendar-Widgets-adhoc-SideStore-...`：含 Widget 扩展，构建后以本机 ad-hoc 签名携带 App Groups 权限，没有 Apple 开发者证书签名，必须由 SideStore 重新签名。不要删除小组件或共享容器权限。它不叫“完全未签名”包。主应用和扩展共享 `group.com.banli.shift.shared`，运行时从重签后的自身 profile 解析实际组名。是否能为免费账号注册此组需以 SideStore 实际返回为准。
3. `MoyuCalendar-logs-...`：编译和测试日志。两个安装包的 SHA256 及结构报告一并上传。

小组件添加：安装含 Widget 的包后打开应用，在“我的 → 桌面小组件”同步，长按桌面添加摸鱼日历，选择对应人员和尺寸。基础版和 Widget 版共用主应用标识；更新前先备份个人记录。

## 实际限制及验证边界

- 免费 Apple ID 的有效期、App ID/活跃应用数量由 Apple/SideStore 管理；本仓库不收集 Apple ID、证书或账号密码。SideStore 会重签应用标识，原工程保持固定。
- 普通本地通知不能保证静音/专注模式下强制响铃，也不是持续响铃闹钟或服务器 APNs 推送。iOS 限制待发通知数量，应用安排最近60条以内，每次打开补充；小组件刷新由系统调度。
- 节假日网络校对在前台或网络恢复时按6小时间隔执行，使用公开维护的 holiday-cn/Nager.Date；不是后台永久在线。失败保留缓存。手机日历数据点击同步更新。
- 桌面图标使用用户授权重新制作的鱼与日历插画，源文件为 `Resources/AppIcon.png`。构建固定校验图稿 Git blob SHA，生成全部 iOS 图标尺寸并附带 IconManifest.json；缺少图稿或校验不符时停止，不再使用临时占位图。该图为新制作版本，并非上传原图的逐像素复制。
- CI 的 ARM64、Widget 结构、共享权限、恢复格式校验不等于用户真机安装或权限行为已验证。真机验证状态写在每次产物的报告中，不伪报成功。

## 维护

修改 `Sources/`、`Shared/` 或 `WidgetExtension/`，普通快进提交后自动打包；禁止强制推送。功能修改不得通过删除测试或放宽校验掩盖失败。流水线仅对明确的临时依赖网络错误重试一次；实际源码错误需要修复后提交。

注册名称采用安全 ASCII 的 MoyuCalendar，桌面名称用本地化显示“摸鱼日历”，避免 SideStore 的 appIdName 中文注册错误。
