import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

@MainActor final class Store: ObservableObject {
    @Published private(set) var data = CalendarData()
    @Published var error: String?
    @Published var linkDay: String?
    @Published var reminders = UserDefaults.standard.bool(forKey:"reminders")
    @Published var lead = UserDefaults.standard.object(forKey:"lead") as? Int ?? 30
    private var notificationGeneration = 0
    private var damaged = false
    let file: URL
    init() {
        let root = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("MoyuCalendar")
        file = root.appendingPathComponent("calendar.json")
        do {
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            if FileManager.default.fileExists(atPath:file.path) { let d = try JSONDecoder().decode(CalendarData.self,from:Data(contentsOf:file)); try Roster.validate(d); data = d }
        } catch { damaged = true; self.error = "原数据读取失败，暂停写入并保留原文件，请先备份再恢复。\n"+error.localizedDescription }
    }
    func name(_ id: String) -> String { data.people.first { $0.id == id }?.name ?? id }
    func color(_ key: String) -> Color { Color(hex:data.colors[key] ?? CalendarData().colors[key] ?? "#39856a") }
    func save(_ d: CalendarData, restoring: Bool = false) throws {
        guard !damaged || restoring else { throw AppError.invalid("请先恢复有效备份") }
        try Roster.validate(d)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(d).write(to:file,options:.atomic)
        data = d; damaged = false
        updateWidgets()
        Task { await scheduleNotifications() }
    }
    func change(_ update: (inout CalendarData) -> Void) { do { var d = data; update(&d); try save(d) } catch { self.error = error.localizedDescription } }
    func writeEntry(_ value: Entry, sourceIDs: [String]? = nil) throws {
        var e = value, d = data; d.entries.removeAll { $0.id == e.id }
        if e.type == .overtime && e.date > Day.today { throw AppError.invalid("加班应在实际发生后登记") }
        if e.type == .leave { e.allocations = try Roster.allocate(d,e.person,e.minutes,asOf:min(e.date,Day.today),sourceIDs:sourceIDs) }
        d.entries.append(e); try save(d)
    }
    func delete(_ id: String) throws { var d = data; d.entries.removeAll { $0.id == id }; try save(d) }
    func backup() throws -> URL {
        if damaged { return file }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("摸鱼日历备份_\(Day.today).json")
        try JSONEncoder().encode(data).write(to:url,options:.atomic); return url
    }
    func restore(_ raw: Data) throws -> CalendarData {
        guard raw.count <= 10*1024*1024 else { throw AppError.invalid("备份不能超过10MB") }
        let d = try JSONDecoder().decode(CalendarData.self,from:raw); try Roster.validate(d); return d
    }
    func authorizeReminders() async {
        UserDefaults.standard.set(reminders,forKey:"reminders"); UserDefaults.standard.set(lead,forKey:"lead")
        if reminders { do { let ok = try await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound,.badge]); if !ok { error = "请在系统设置允许应用通知" } } catch { self.error = error.localizedDescription } }
        await scheduleNotifications()
    }
    func scheduleNotifications() async {
        notificationGeneration += 1
        let generation = notificationGeneration
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        guard generation == notificationGeneration else { return }
        center.removePendingNotificationRequests(withIdentifiers:pending.filter { $0.identifier.hasPrefix("moyu/") }.map(\.identifier))
        guard reminders else {
            center.removePendingNotificationRequests(withIdentifiers:pending.filter { $0.identifier.hasPrefix("moyu-snooze/") }.map(\.identifier))
            return
        }
        let authorization = await center.notificationSettings()
        guard generation == notificationGeneration, authorization.authorizationStatus == .authorized || authorization.authorizationStatus == .provisional else { return }
        let stop = UNNotificationAction(identifier:"stop",title:"关闭",options:[])
        let snooze = UNNotificationAction(identifier:"snooze",title:"5分钟后提醒",options:[])
        center.setNotificationCategories([UNNotificationCategory(identifier:"moyu.reminder",actions:[snooze,stop],intentIdentifiers:[],options:[])])
        let plans = ReminderPlanner.plan(data,settings:data.reminderSettings ?? ReminderSettings(),lead:lead)
        let reserved = pending.filter { !$0.identifier.hasPrefix("moyu/") }.count
        for plan in plans.prefix(max(0,60-reserved)) {
            guard generation == notificationGeneration else { return }
            let c = UNMutableNotificationContent()
            c.title = plan.title; c.body = plan.body; c.sound = .default
            c.categoryIdentifier = "moyu.reminder"; c.userInfo = ["day":plan.day]
            let t = UNCalendarNotificationTrigger(dateMatching:Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second],from:plan.date),repeats:false)
            do { try await center.add(UNNotificationRequest(identifier:plan.id,content:c,trigger:t)) } catch { self.error = error.localizedDescription; break }
        }
    }
    func testNotification() async {
        do {
            let center = UNUserNotificationCenter.current()
            guard try await center.requestAuthorization(options:[.alert,.sound,.badge]) else { throw AppError.invalid("请在系统设置允许通知") }
            let content = UNMutableNotificationContent()
            content.title = "摸鱼日历 · 测试提醒"; content.body = "本地通知已送达"; content.sound = .default; content.categoryIdentifier = "moyu.reminder"
            try await center.add(UNNotificationRequest(identifier:"moyu-test",content:content,trigger:UNTimeIntervalNotificationTrigger(timeInterval:5,repeats:false)))
        } catch { self.error = error.localizedDescription }
    }

}
extension Color {
    init(hex: String) { let n = UInt64(hex.trimmingCharacters(in:CharacterSet(charactersIn:"#")),radix:16) ?? 0x39856a; self.init(red:Double((n>>16)&255)/255,green:Double((n>>8)&255)/255,blue:Double(n&255)/255) }
}
func dateBinding(_ v: Binding<String>) -> Binding<Date> { Binding(get:{ Day.date(v.wrappedValue) ?? Date() },set:{ v.wrappedValue = Day.key($0) }) }
struct ShareFile: Identifiable { var id = UUID(); var url: URL }
struct ShareView: UIViewControllerRepresentable {
    var url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems:[url],applicationActivities:nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
