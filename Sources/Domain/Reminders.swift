import Foundation

struct CustomReminder: Codable, Equatable, Identifiable {
    var id = UUID().uuidString
    var title = "", date = Day.today, time = "09:00", enabled = true
}
struct ReminderSettings: Codable, Equatable {
    var people = ["p1","p2"], kinds = ["day","night","duty"]
    var briefing = false, briefingTime = "20:00"
    var custom: [CustomReminder] = []
    func validate() throws {
        guard people.allSatisfy({ ["p1","p2"].contains($0) }),
              kinds.allSatisfy({ ["day","night","duty"].contains($0) }),
              Day.validTime(briefingTime), custom.count <= 100,
              Set(custom.map(\.id)).count == custom.count,
              custom.allSatisfy({ !$0.id.isEmpty && !$0.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && $0.title.utf16.count <= 100 && Day.date($0.date) != nil && Day.validTime($0.time) })
        else { throw AppError.invalid("提醒设置无效，标题不能为空，最多100条") }
    }
}
struct PlannedReminder: Equatable {
    var id: String, date: Date, title: String, body: String, day: String
}
enum ReminderPlanner {
    static func plan(_ data: CalendarData, settings: ReminderSettings, lead: Int, now: Date = Date()) -> [PlannedReminder] {
        var result: [PlannedReminder] = []
        let today = Day.key(now)
        func at(_ day: String, _ time: String) -> Date? {
            guard let date = Day.date(day), Day.validTime(time) else { return nil }
            return Day.calendar.date(bySettingHour:Day.minutes(time)/60,minute:Day.minutes(time)%60,second:0,of:date)
        }
        func append(_ id: String, _ day: String, _ time: String, _ title: String, _ body: String, advance: Bool) {
            guard let date = at(day,time), date > now else { return }
            result.append(PlannedReminder(id:id,date:max(now.addingTimeInterval(1),date.addingTimeInterval(advance ? -Double(max(0,min(1440,lead))*60) : 0)),title:title,body:body,day:day))
        }
        for offset in 0..<120 {
            let day = Day.add(today,offset)
            for p in data.people where settings.people.contains(p.id) {
                let absent = data.entries.filter { $0.person == p.id && $0.date == day && $0.type != .overtime }.reduce(0) { $0+$1.minutes } >= data.unit
                if let s = Roster.shift(data,p.id,day), s != .off, !absent, settings.kinds.contains(s.rawValue) {
                    let time = s == .day ? (p.base?.dayStart ?? p.dayStart) : (p.base?.nightStart ?? p.nightStart)
                    append("moyu/\(p.id)/\(day)/\(s.rawValue)",day,time,p.name+" · "+s.title+" "+Roster.time(p,s),data.dayNotes?[day]?[p.id] ?? "班前提醒",advance:true)
                }
                if let duty = Roster.duty(data,p.id,day), settings.kinds.contains("duty") {
                    append("moyu/\(p.id)/\(day)/duty",day,duty.startTime,p.name+" · 值班 "+duty.time,data.dayNotes?[day]?[p.id] ?? "独立值班提醒",advance:true)
                }
            }
            if settings.briefing {
                let next = Day.add(day,1)
                let lines = data.people.filter { settings.people.contains($0.id) }.map { p -> String in
                    let shift = Roster.shift(data,p.id,next)?.title ?? "未排班"
                    let duty = Roster.duty(data,p.id,next).map { "；值班 "+$0.time } ?? ""
                    let leave = data.entries.filter { $0.person == p.id && $0.date == next && $0.type != .overtime }.map { $0.type.title+" "+number(Double($0.minutes)/Double(data.unit))+"天" }.joined(separator:"；")
                    return p.name+"："+shift+duty+(leave.isEmpty ? "" : "；"+leave)
                }
                if !lines.isEmpty { append("moyu/briefing/"+day,day,settings.briefingTime,"明日排班 · "+next,lines.joined(separator:"\n"),advance:false) }
            }
        }
        for item in settings.custom where item.enabled { append("moyu/custom/"+item.id,item.date,item.time,item.title,"自定义提醒",advance:false) }
        return result.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
}
