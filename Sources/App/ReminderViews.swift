import SwiftUI
import UserNotifications

final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey:Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self; return true
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner,.list,.sound])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == "snooze", let content = response.notification.request.content.mutableCopy() as? UNMutableNotificationContent {
            center.add(UNNotificationRequest(identifier:"moyu-snooze/"+UUID().uuidString,content:content,trigger:UNTimeIntervalNotificationTrigger(timeInterval:300,repeats:false))) { _ in completionHandler() }
        } else {
            if response.actionIdentifier == UNNotificationDefaultActionIdentifier, let day = response.notification.request.content.userInfo["day"] as? String { DispatchQueue.main.async { NotificationCenter.default.post(name:Notification.Name("moyu.openDay"),object:day) } }
            completionHandler()
        }
    }
}
struct ReminderPreferences: View {
    @EnvironmentObject var store: Store
    @State private var editing: CustomReminder?
    private var settings: ReminderSettings { store.data.reminderSettings ?? ReminderSettings() }
    var body: some View {
        Form {
            Section("班前提醒") {
                Toggle("开启本地通知",isOn:$store.reminders)
                Stepper("提前 \(store.lead) 分钟",value:$store.lead,in:0...1440,step:5)
                ForEach(store.data.people) { p in Toggle(p.name,isOn:membership(p.id,people:true)) }
                Toggle("白班",isOn:membership("day")); Toggle("夜班",isOn:membership("night")); Toggle("独立值班",isOn:membership("duty"))
                Button("保存并启用提醒") { Task { await store.authorizeReminders() } }
            }
            Section("明日排班简报") {
                Toggle("每天提醒明日安排",isOn:Binding(get:{ settings.briefing },set:{ value in update { $0.briefing = value } }))
                DatePicker("通知时间",selection:timeBinding(get:{ settings.briefingTime },set:{ value in update { $0.briefingTime = value } }),displayedComponents:.hourAndMinute)
            }
            Section("自定义提醒") {
                ForEach(settings.custom) { item in
                    Button { editing = item } label: {
                        VStack(alignment:.leading) { Text(item.title); Text(item.date+" "+item.time+(item.enabled ? "" : " · 已停用")).font(.caption) }
                    }
                }.onDelete { indices in update { value in value.custom.remove(atOffsets:indices) } }
                Button("添加提醒") { editing = CustomReminder() }
            }
            Section {
                Button("5秒后发送测试通知") { Task { await store.testNotification() } }
                Link("打开系统设置",destination:URL(string:UIApplication.openSettingsURLString)!)
                Text("通知支持关闭和5分钟后再提醒。iOS专注模式、静音及调度可能影响声音；不是持续响铃闹钟。系统待发通知有数量上限，应用安排最近60条以内，每次打开自动补充。关闭总开关后点击保存生效。").font(.caption)
            }
        }.navigationTitle("通知与提醒").sheet(item:$editing) { item in CustomReminderEditor(item:item) }
    }
    private func update(_ body: (inout ReminderSettings) -> Void) {
        store.change { d in var r = d.reminderSettings ?? ReminderSettings(); body(&r); d.reminderSettings = r }
    }
    private func membership(_ id: String, people: Bool = false) -> Binding<Bool> {
        Binding(get:{ (people ? settings.people : settings.kinds).contains(id) },set:{ selected in update { r in
            var list = people ? r.people : r.kinds; list.removeAll { $0 == id }; if selected { list.append(id) }
            if people { r.people = list } else { r.kinds = list }
        } })
    }
}
struct CustomReminderEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var item: CustomReminder
    @State private var problem: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("提醒内容",text:$item.title)
                DatePicker("日期",selection:dateBinding($item.date),displayedComponents:.date)
                DatePicker("时间",selection:timeBinding(get:{ item.time },set:{ item.time = $0 }),displayedComponents:.hourAndMinute)
                Toggle("启用",isOn:$item.enabled)
            }.navigationTitle("自定义提醒").toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button("保存") {
                    do {
                        var d = store.data, r = d.reminderSettings ?? ReminderSettings()
                        r.custom.removeAll { $0.id == item.id }; r.custom.append(item); d.reminderSettings = r
                        try store.save(d); dismiss()
                    } catch { problem = error.localizedDescription }
                } }
            }.alert("无法保存",isPresented:Binding(get:{ problem != nil },set:{ if !$0 { problem = nil } })) { Button("知道了",role:.cancel) {} } message: { Text(problem ?? "") }
        }
    }
}
func timeBinding(get: @escaping () -> String, set: @escaping (String) -> Void) -> Binding<Date> {
    Binding(get:{ let m = Day.minutes(get()); return Day.calendar.date(bySettingHour:m/60,minute:m%60,second:0,of:Date()) ?? Date() },
            set:{ let c = Day.calendar.dateComponents([.hour,.minute],from:$0); set(String(format:"%02d:%02d",c.hour ?? 0,c.minute ?? 0)) })
}
