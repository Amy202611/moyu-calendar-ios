import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

@MainActor final class Store: ObservableObject {
    @Published private(set) var data = CalendarData()
    @Published var error: String?
    @Published var reminders = UserDefaults.standard.bool(forKey:"reminders")
    @Published var lead = UserDefaults.standard.object(forKey:"lead") as? Int ?? 30
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
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers:pending.filter { $0.identifier.hasPrefix("moyu/") }.map(\.identifier))
        guard reminders else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        var list: [(String,Date,String,String)] = []
        let now = Date()
        for offset in 0..<120 {
            let day = Day.add(Day.today,offset)
            for p in data.people {
                let absent = data.entries.filter { $0.person == p.id && $0.date == day && $0.type != .overtime }.reduce(0) { $0+$1.minutes } >= data.unit
                var events: [(String,String,String)] = []
                if let sh = Roster.shift(data,p.id,day), sh != .off, !absent { events.append((sh.rawValue,sh == .day ? (p.base?.dayStart ?? p.dayStart) : (p.base?.nightStart ?? p.nightStart),sh.title+" "+Roster.time(p,sh))) }
                if let duty = Roster.duty(data,p.id,day) { events.append(("duty",duty.startTime,"值班 "+duty.time)) }
                for (kind,time,title) in events {
                    guard let d = Day.date(day), let at = Day.calendar.date(bySettingHour:Day.minutes(time)/60,minute:Day.minutes(time)%60,second:0,of:d), at > now else { continue }
                    list.append(("moyu/\(p.id)/\(day)/\(kind)",max(now.addingTimeInterval(1),at.addingTimeInterval(-Double(lead*60))),p.name+" · "+title,data.dayNotes?[day]?[p.id] ?? "班前提醒"))
                }
            }
        }
        for (id,date,title,note) in list.sorted(by:{ $0.1 < $1.1 }).prefix(60) {
            let c = UNMutableNotificationContent(); c.title = title; c.body = note; c.sound = .default
            let t = UNCalendarNotificationTrigger(dateMatching:Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second],from:date),repeats:false)
            do { try await center.add(UNNotificationRequest(identifier:id,content:c,trigger:t)) } catch { self.error = error.localizedDescription; break }
        }
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
