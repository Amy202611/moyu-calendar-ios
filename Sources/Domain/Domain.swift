import Foundation

enum Day {
    static var calendar: Calendar { Calendar(identifier: .gregorian) }
    static var today: String { key(Date()) }
    static func key(_ d: Date) -> String { let c = calendar.dateComponents([.year,.month,.day], from: d); return String(format:"%04d-%02d-%02d",c.year!,c.month!,c.day!) }
    static func date(_ s: String) -> Date? {
        let p = s.split(separator:"-").compactMap { Int($0) }
        guard p.count == 3, (1901...2099).contains(p[0]), let d = calendar.date(from: DateComponents(year:p[0],month:p[1],day:p[2],hour:12)), key(d) == s else { return nil }; return d
    }
    static func add(_ s: String, _ n: Int) -> String { guard let d = date(s), let r = calendar.date(byAdding:.day,value:n,to:d) else { return s }; return key(r) }
    static func distance(_ a: String, _ b: String) -> Int { guard let a = date(a), let b = date(b) else { return 0 }; return calendar.dateComponents([.day],from:b,to:a).day ?? 0 }
    static func weekday(_ s: String) -> Int { date(s).map { calendar.component(.weekday,from:$0)-1 } ?? 0 }
    static func validTime(_ s: String) -> Bool { let a = s.split(separator:":").compactMap { Int($0) }; return s.count == 5 && a.count == 2 && (0...23).contains(a[0]) && (0...59).contains(a[1]) }
    static func minutes(_ s: String) -> Int { let a = s.split(separator:":").compactMap { Int($0) }; return a.count == 2 ? a[0]*60+a[1] : 0 }
    static func lunar(_ s: String) -> String {
        guard let d = date(s) else { return "" }
        let c = Calendar(identifier:.chinese).dateComponents([.month,.day],from:d)
        let m = ["正","二","三","四","五","六","七","八","九","十","冬","腊"]
        let n = ["初一","初二","初三","初四","初五","初六","初七","初八","初九","初十","十一","十二","十三","十四","十五","十六","十七","十八","十九","二十","廿一","廿二","廿三","廿四","廿五","廿六","廿七","廿八","廿九","三十"]
        guard let month = c.month, let day = c.day, (1...12).contains(month), (1...30).contains(day) else { return "" }
        return day == 1 ? ((c.isLeapMonth ?? false) ? "闰" : "")+m[month-1]+"月" : n[day-1]
    }
}
enum Shift: String, Codable, CaseIterable, Identifiable {
    case day, night, off
    var id: String { rawValue }
    var title: String { switch self { case .day: return "白班"; case .night: return "夜班"; case .off: return "休息" } }
}
enum Kind: String, Codable, CaseIterable, Identifiable {
    case overtime, leave, annual
    var id: String { rawValue }
    var title: String { switch self { case .overtime: return "加班"; case .leave: return "倒休"; case .annual: return "年假" } }
}
struct BaseRule: Codable, Equatable {
    var mode = "weekly", enabled = true, start = Day.today
    var sequence: [Shift] = [.day,.night,.off,.off]
    var weekly = ["off","day","day","day","day","day","off"]
    var dayStart = "08:00", dayEnd = "17:00", nightStart = "20:00", nightEnd = "08:00"
}
struct DutyRule: Codable, Equatable {
    var mode = "interval", enabled = false, start = Day.today, intervalDays = 5
    var startTime = "20:00", endTime = "08:00"
}
struct Duty: Equatable {
    var startTime: String, endTime: String
    var minutes: Int { let n = Day.minutes(endTime)-Day.minutes(startTime); return n <= 0 ? n+1440 : n }
    var time: String { startTime+" – "+(endTime <= startTime ? "次日" : "")+endTime }
}
struct Person: Codable, Equatable, Identifiable {
    var id: String, name: String
    var enabled = false, start = Day.today
    var sequence: [Shift] = [.day,.night,.off,.off]
    var dayStart = "08:00", dayEnd = "20:00", nightStart = "20:00", nightEnd = "08:00"
    var mode: String?, intervalDays: Int?, intervalShift: Shift?, intervalRest: Bool?
    var base: BaseRule?, duty: DutyRule?
    var baseDraft: BaseRule {
        if let base { return base }; var b = BaseRule(); b.start = start
        if enabled && mode != "interval" { b.mode = "cycle"; b.sequence = sequence; b.dayStart = dayStart; b.dayEnd = dayEnd; b.nightStart = nightStart; b.nightEnd = nightEnd }; return b
    }
    var dutyDraft: DutyRule {
        if let duty { return duty }; var d = DutyRule(); d.start = start
        if mode == "interval" { d.enabled = enabled; d.intervalDays = intervalDays ?? 5; d.startTime = intervalShift == .day ? dayStart : nightStart; d.endTime = intervalShift == .day ? dayEnd : nightEnd }; return d
    }
}
struct Allocation: Codable, Equatable { var overtimeId: String; var minutes: Int }
struct Entry: Codable, Equatable, Identifiable {
    var id = UUID().uuidString, date = Day.today, person = "p1"
    var type: Kind
    var minutes = 240, note = ""
    var part: String?, allocations: [Allocation]?
}
struct DutyOverride: Codable, Equatable { var enabled: Bool; var startTime: String?, endTime: String? }
struct Settings: Codable, Equatable {
    var china = true, usa = true, lunar = true, hoursPerDay = 8.0
    var weekStart: Int?
}
struct CalendarData: Codable, Equatable {
    var version = 1
    var people = [Person(id:"p1",name:"我"),Person(id:"p2",name:"搭班人")]
    var overrides: [String:[String:String]] = [:], entries: [Entry] = []
    var settings = Settings()
    var colors = ["day":"#39856a","p1":"#5556a6","p2":"#9761ad","off":"#90979c","duty":"#7951c9","overtime":"#d77542","leave":"#3a8f94","annual":"#b78b30","today":"#e2edf9"]
    var annualAllowances: [String:[String:Double]]?
    var dutyOverrides: [String:[String:DutyOverride]]?
    var reminderSettings: ReminderSettings?
    var dayNotes: [String:[String:String]]?
    var unit: Int { Int((settings.hoursPerDay*60).rounded()) }
    var weekStart: Int { settings.weekStart ?? 1 }
}
enum AppError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { switch self { case .invalid(let s): return s } }
}
struct Statistics { var overtime = 0, leave = 0, planned = 0, balance = 0, night = 0, duty = 0, dutyMinutes = 0; var rest = 0.0 }
enum Roster {
    static func shift(_ d: CalendarData, _ id: String, _ day: String) -> Shift? {
        guard let p = d.people.first(where: { $0.id == id }) else { return nil }
        if let v = d.overrides[day]?[id] { return Shift(rawValue:v) }
        if let b = p.base {
            guard b.enabled, day >= b.start, b.mode != "manual" else { return nil }
            return b.mode == "weekly" ? Shift(rawValue:b.weekly[Day.weekday(day)]) : b.sequence[Day.distance(day,b.start)%b.sequence.count]
        }
        guard p.enabled, day >= p.start else { return nil }
        let n = Day.distance(day,p.start)
        if p.mode == "interval" { return n%(p.intervalDays ?? 5) == 0 ? (p.intervalShift ?? .night) : ((p.intervalRest ?? true) ? .off : nil) }
        return p.sequence[n%p.sequence.count]
    }
    static func duty(_ d: CalendarData, _ id: String, _ day: String) -> Duty? {
        if let o = d.dutyOverrides?[day]?[id] { guard o.enabled, let a = o.startTime, let b = o.endTime else { return nil }; return Duty(startTime:a,endTime:b) }
        guard let r = d.people.first(where: { $0.id == id })?.duty, r.enabled, r.mode == "interval", day >= r.start, Day.distance(day,r.start)%r.intervalDays == 0 else { return nil }
        return Duty(startTime:r.startTime,endTime:r.endTime)
    }
    static func time(_ p: Person, _ s: Shift) -> String {
        let a = s == .day ? (p.base?.dayStart ?? p.dayStart) : (p.base?.nightStart ?? p.nightStart)
        let b = s == .day ? (p.base?.dayEnd ?? p.dayEnd) : (p.base?.nightEnd ?? p.nightEnd)
        return s == .off ? "全天休息" : a+" – "+(b <= a ? "次日" : "")+b
    }
    static func available(_ d: CalendarData, _ person: String, excluding: String? = nil, asOf: String = Day.today) -> [(Entry,Int)] {
        var used: [String:Int] = [:]
        for e in d.entries where e.type == .leave && e.id != excluding { for a in e.allocations ?? [] { used[a.overtimeId,default:0] += a.minutes } }
        return d.entries.filter { $0.person == person && $0.type == .overtime && $0.date <= asOf }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }.compactMap { e in let left = e.minutes-(used[e.id] ?? 0); return left > 0 ? (e,left) : nil }
    }
    static func allocate(_ d: CalendarData, _ person: String, _ minutes: Int, asOf: String, sourceIDs: [String]? = nil) throws -> [Allocation] {
        var left = minutes, result: [Allocation] = []
        for (e,m) in available(d,person,asOf:asOf) where sourceIDs == nil || sourceIDs!.contains(e.id) { let take = min(left,m); if take > 0 { result.append(Allocation(overtimeId:e.id,minutes:take)); left -= take } }
        guard left == 0 else { throw AppError.invalid("加班余额不足，不能超额销假。") }; return result
    }
    static func annual(_ d: CalendarData, _ person: String, _ year: String, today: String = Day.today) -> (total:Int, used:Int, planned:Int, remaining:Int) {
        let total = Int((d.annualAllowances?[year]?[person] ?? 10)*Double(d.unit))
        let entries = d.entries.filter { $0.person == person && $0.type == .annual && $0.date.hasPrefix(year+"-") }
        let used = entries.filter { $0.date <= today }.reduce(0) { $0+$1.minutes }
        let planned = entries.filter { $0.date > today }.reduce(0) { $0+$1.minutes }
        return (total,used,planned,total-used-planned)
    }
    static func statistics(_ d: CalendarData, _ person: String, _ start: String, _ end: String, today: String = Day.today) -> Statistics {
        var s = Statistics()
        for e in d.entries where person == "all" || e.person == person {
            if e.type == .overtime && e.date <= today { s.balance += e.minutes }; if e.type == .leave { s.balance -= e.minutes }
            if e.date >= start && e.date <= end { if e.type == .overtime { s.overtime += e.minutes }; if e.type == .leave { if e.date <= today { s.leave += e.minutes } else { s.planned += e.minutes } } }
        }
        guard Day.date(start) != nil, Day.date(end) != nil, start <= end, Day.distance(end,start) <= 3660 else { return s }
        var day = start
        while day <= end {
            for p in d.people where person == "all" || p.id == person {
                if let r = duty(d,p.id,day) { s.duty += 1; s.dutyMinutes += r.minutes }
                let leave = d.entries.filter { $0.person == p.id && $0.date == day && $0.type != .overtime }.reduce(0) { $0+$1.minutes }
                if leave < d.unit { if shift(d,p.id,day) == .night { s.night += 1 }; if shift(d,p.id,day) == .off { s.rest += max(0,1-Double(leave)/Double(d.unit)) } }
            }
            day = Day.add(day,1)
        }
        return s
    }
    static func validate(_ d: CalendarData) throws {
        func check(_ ok: Bool, _ s: String) throws { if !ok { throw AppError.invalid(s) } }
        try check(d.version == 1 && d.people.map(\.id) == ["p1","p2"],"备份或人员格式无效")
        try check(d.settings.hoursPerDay.isFinite && d.settings.hoursPerDay >= 1 && d.settings.hoursPerDay <= 24 && (0...6).contains(d.weekStart),"日历设置无效")
        for p in d.people {
            try check(!p.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && p.name.count <= 16 && Day.date(p.start) != nil && !p.sequence.isEmpty && p.sequence.count <= 60 && [p.dayStart,p.dayEnd,p.nightStart,p.nightEnd].allSatisfy(Day.validTime),"人员或轮班规则无效")
            if p.mode == "interval" { try check((1...365).contains(p.intervalDays ?? 0) && p.intervalShift != nil,"旧间隔规则无效") }
            if let b = p.base { try check(["weekly","cycle","manual"].contains(b.mode) && Day.date(b.start) != nil && !b.sequence.isEmpty && b.sequence.count <= 60 && b.weekly.count == 7 && b.weekly.allSatisfy { ["","day","night","off"].contains($0) } && [b.dayStart,b.dayEnd,b.nightStart,b.nightEnd].allSatisfy(Day.validTime),"基础班表无效") }
            if let r = p.duty { try check(["interval","manual"].contains(r.mode) && Day.date(r.start) != nil && (1...365).contains(r.intervalDays) && [r.startTime,r.endTime].allSatisfy(Day.validTime),"独立值班规则无效") }
        }
        for (day,people) in d.overrides { try check(Day.date(day) != nil,"单日日期无效"); for (id,s) in people { try check(["p1","p2"].contains(id) && ["none","day","night","off"].contains(s),"单日班次无效") } }
        for (day,people) in d.dutyOverrides ?? [:] { try check(Day.date(day) != nil,"值班日期无效"); for (id,v) in people { try check(["p1","p2"].contains(id) && (!v.enabled || (Day.validTime(v.startTime ?? "") && Day.validTime(v.endTime ?? ""))),"单日值班无效") } }
        for (day,people) in d.dayNotes ?? [:] { try check(Day.date(day) != nil,"备注日期无效"); for (id,n) in people { try check(["p1","p2"].contains(id) && n.utf16.count <= 200,"备注无效或超过200字") } }
        if let reminders = d.reminderSettings { try reminders.validate() }
        var ids = Set<String>(), used: [String:Int] = [:], daily: [String:Int] = [:]
        for e in d.entries {
            try check(!e.id.isEmpty && ids.insert(e.id).inserted && Day.date(e.date) != nil && ["p1","p2"].contains(e.person) && (1...1440).contains(e.minutes) && e.note.utf16.count <= 200,"加班或休假记录无效")
            if e.type != .overtime { daily[e.date+e.person,default:0] += e.minutes }
            if e.type == .leave {
                let a = e.allocations ?? []; try check(!a.isEmpty && a.allSatisfy { (1...1440).contains($0.minutes) } && a.reduce(0,{ $0+$1.minutes }) == e.minutes,"倒休必须关联足额加班")
                for a in a { guard let o = d.entries.first(where: { $0.id == a.overtimeId }) else { throw AppError.invalid("加班来源不存在") }; try check(o.type == .overtime && o.person == e.person && o.date <= e.date && a.minutes > 0,"倒休来源无效"); used[o.id,default:0] += a.minutes }
            }
        }
        try check(daily.values.allSatisfy { $0 <= d.unit },"当天年假和倒休不能超过一天")
        for (id,m) in used { try check(m <= (d.entries.first { $0.id == id }?.minutes ?? 0),"加班已超额销假") }
        for (year,people) in d.annualAllowances ?? [:] { try check(Int(year).map { (1901...2099).contains($0) } ?? false,"年假年份无效"); for (id,n) in people { try check(["p1","p2"].contains(id) && n.isFinite && n >= 0 && n <= 366,"年假额度无效") } }
        for e in d.entries where e.type == .annual { try check(annual(d,e.person,String(e.date.prefix(4))).remaining >= 0,"年假超过年度额度") }
    }
}

func number(_ d: Double) -> String { String(format:"%.2f",d).replacingOccurrences(of:#"(\.\d*?)0+$"#,with:"$1",options:.regularExpression).replacingOccurrences(of:#"\.$"#,with:"",options:.regularExpression) }
