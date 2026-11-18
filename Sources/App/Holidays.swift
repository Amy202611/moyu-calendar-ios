import SwiftUI
import Network
struct HolidayRow: Codable, Identifiable {
    var country: String, date: String, name: String, kind: String, source: String
    var id: String { country+"/"+date+"/"+kind+"/"+name }
}
private struct CNFeed: Decodable {
    var year: Int
    struct Row: Decodable { var date: String, name: String; var isOffDay: Bool }
    var days: [Row]
}
private struct USFeed: Decodable { var date: String, name: String, localName: String, countryCode: String; var global: Bool; var types: [String] }
private struct HolidayCache: Codable { var chunks: [String:[HolidayRow]] = [:]; var checkedAt = 0.0 }
@MainActor final class Holidays: ObservableObject {
    @Published var auto = UserDefaults.standard.object(forKey:"holidayAuto") as? Bool ?? true { didSet { UserDefaults.standard.set(auto,forKey:"holidayAuto") } }
    @Published var wifiOnly = UserDefaults.standard.bool(forKey:"holidayWifi") { didSet { UserDefaults.standard.set(wifiOnly,forKey:"holidayWifi") } }
    @Published private(set) var status = "内置节假日，联网后校对"
    @Published private(set) var updating = false
    @Published private(set) var checkedAt = 0.0
    private var chunks: [String:[HolidayRow]] = [:], cachedRows: [Int:[HolidayRow]] = [:], builtin: [HolidayRow] = []
    private var connected = false, wifi = false
    private let monitor = NWPathMonitor()
    private let file: URL
    init() {
        let root = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("MoyuCalendar")
        try? FileManager.default.createDirectory(at:root,withIntermediateDirectories:true); file = root.appendingPathComponent("holidays.json")
        if let raw = try? Data(contentsOf:file), let c = try? JSONDecoder().decode(HolidayCache.self,from:raw) { chunks = c.chunks; checkedAt = c.checkedAt }
        if let u = Bundle.main.url(forResource:"china2026",withExtension:"json"), let raw = try? Data(contentsOf:u), let c = try? JSONDecoder().decode(CNFeed.self,from:raw) { builtin = c.days.map { HolidayRow(country:"CN",date:$0.date,name:$0.name+($0.isOffDay ? "·休" : "·补班"),kind:$0.isOffDay ? "off" : "workday",source:"内置 holiday-cn") } }
        monitor.pathUpdateHandler = { [weak self] p in Task { @MainActor in guard let self else { return }; self.connected = p.status == .satisfied; self.wifi = p.usesInterfaceType(.wifi) || p.usesInterfaceType(.wiredEthernet); if self.auto { await self.refresh(force:false) } } }
        monitor.start(queue:DispatchQueue(label:"moyu.network"))
    }
    func labels(_ day: String, settings: Settings) -> [String] { rows(Int(day.prefix(4)) ?? 2026).filter { $0.date == day && ($0.country == "CN" ? settings.china : settings.usa) }.map { ($0.country == "CN" ? "中·" : "美·")+$0.name } }
    func rows(_ year: Int) -> [HolidayRow] {
        if let rows = cachedRows[year] { return rows }
        var rows = chunks["CN:\(year)"] ?? builtin.filter { $0.date.hasPrefix("\(year)-") }
        if rows.isEmpty && chunks["CN:\(year)"] == nil {
            for (suffix,title) in [("01-01","元旦"),("05-01","劳动节"),("10-01","国庆节")] { rows.append(HolidayRow(country:"CN",date:"\(year)-"+suffix,name:title,kind:"holiday",source:"内置本日，未推算调休")) }
            for i in 0..<366 {
                let day = Day.add("\(year)-01-01",i); guard day.hasPrefix("\(year)-"), let date = Day.date(day) else { break }
                let c = Calendar(identifier:.chinese).dateComponents([.month,.day],from:date)
                if c.isLeapMonth == true { continue }
                let title = c.month == 1 && c.day == 1 ? "春节" : c.month == 5 && c.day == 5 ? "端午节" : c.month == 8 && c.day == 15 ? "中秋节" : ""
                if !title.isEmpty { rows.append(HolidayRow(country:"CN",date:day,name:title,kind:"holiday",source:"内置本日，未推算调休")) }
            }
        }
        rows += chunks["US:\(year)"] ?? Self.us(year)
        let result = rows.filter { $0.date.hasPrefix("\(year)-") }.sorted { $0.date == $1.date ? $0.country < $1.country : $0.date < $1.date }
        cachedRows[year] = result; return result
    }
    func refresh(force: Bool, year: Int? = nil) async {
        guard !updating, force || auto else { return }
        if !force && Date().timeIntervalSince1970-checkedAt < 6*3600 { return }
        guard connected else { status = "当前离线，使用已有数据"; return }
        guard !wifiOnly || wifi else { status = "仅 Wi-Fi 校对，保留已有数据"; return }
        updating = true; status = "正在联网校对…"; defer { updating = false }
        let current = Day.calendar.component(.year,from:Date()), years = Set([current,current+1,year ?? current]).filter { (1901...2099).contains($0) }
        var success = 0, failed = 0
        for y in years.sorted() { for country in ["CN","US"] {
            do {
                let rows: [HolidayRow]
                if country == "CN" {
                    let raw: Data
                    do { raw = try await fetch("https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/\(y).json") }
                    catch { raw = try await fetch("https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master/\(y).json") }
                    let c = try JSONDecoder().decode(CNFeed.self,from:raw)
                    guard c.year == y, (1...150).contains(c.days.count), Set(c.days.map(\.date)).count == c.days.count, c.days.allSatisfy({ Day.date($0.date) != nil && $0.date.hasPrefix("\(y)-") && !$0.name.isEmpty && $0.name.count <= 100 }) else { throw AppError.invalid("来源校验失败") }
                    rows = c.days.map { HolidayRow(country:"CN",date:$0.date,name:$0.name+($0.isOffDay ? "·休" : "·补班"),kind:$0.isOffDay ? "off" : "workday",source:"holiday-cn（公开维护）") }
                } else {
                    let raw = try await fetch("https://date.nager.at/api/v3/PublicHolidays/\(y)/US"), feed = try JSONDecoder().decode([USFeed].self,from:raw)
                    guard (8...100).contains(feed.count), feed.allSatisfy({ $0.countryCode == "US" && Day.date($0.date) != nil }) else { throw AppError.invalid("美国来源无效") }
                    var result: [String:HolidayRow] = [:]
                    let fixed = ["元旦":"01-01","六月节":"06-19","独立日":"07-04","退伍军人节":"11-11","圣诞节":"12-25"]
                    for item in feed where item.types.contains("Public") {
                        let known = Self.name(item.name); if !item.global && known == nil { continue }
                        let title = known ?? item.localName, actual = fixed[title].map { "\(y)-"+$0 } ?? item.date
                        let observed = actual != item.date, n = title+(observed ? "（补假）" : ""), k = observed ? "observed" : "holiday"
                        result[item.date+"/"+n] = HolidayRow(country:"US",date:item.date,name:n,kind:k,source:"Nager.Date（公开维护）")
                        if observed { result[actual+"/"+title] = HolidayRow(country:"US",date:actual,name:title,kind:"holiday",source:"Nager.Date（公开维护）") }
                    }
                    guard result.count >= 8 else { throw AppError.invalid("全国假日数据不完整") }; rows = Array(result.values)
                }
                chunks["\(country):\(y)"] = rows; success += 1
            } catch { failed += 1 }
        } }
        cachedRows.removeAll(); checkedAt = Date().timeIntervalSince1970
        do { try JSONEncoder().encode(HolidayCache(chunks:chunks,checkedAt:checkedAt)).write(to:file,options:.atomic) } catch { status = "缓存保存失败，个人排班未改变"; return }
        status = failed == 0 ? "已校对最新可用数据" : success > 0 ? "部分来源或年度暂不可用，保留已有数据" : "校对失败，保留内置/缓存"
    }
    private func fetch(_ address: String) async throws -> Data {
        var r = URLRequest(url:URL(string:address)!); r.timeoutInterval = 15; r.cachePolicy = .reloadIgnoringLocalCacheData
        let (data,response) = try await URLSession.shared.data(for:r)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 512*1024 else { throw AppError.invalid("来源不可用") }; return data
    }
    private static func name(_ name: String) -> String? {
        let s = name.lowercased()
        for (token,title) in [("new year","元旦"),("martin","马丁·路德·金日"),("washington","总统日"),("president","总统日"),("memorial","阵亡将士纪念日"),("juneteenth","六月节"),("independence","独立日"),("labor","劳动节"),("columbus","哥伦布日"),("veteran","退伍军人节"),("thanksgiving","感恩节"),("christmas","圣诞节")] { if s.contains(token) { return title } }; return nil
    }
    private static func us(_ year: Int) -> [HolidayRow] {
        var result: [HolidayRow] = []
        func add(_ day: String, _ title: String, _ kind: String = "holiday") { if day.hasPrefix("\(year)-") { result.append(HolidayRow(country:"US",date:day,name:title,kind:kind,source:"内置联邦假日规则")) } }
        func nth(_ y: Int, _ m: Int, _ n: Int) -> String { let first = String(format:"%04d-%02d-01",y,m); return Day.add(first,(1-Day.weekday(first)+7)%7+(n-1)*7) }
        for y in (year-1)...(year+1) where (1901...2099).contains(y) {
            for (m,n,title) in [(1,1,"元旦"),(6,19,"六月节"),(7,4,"独立日"),(11,11,"退伍军人节"),(12,25,"圣诞节")] {
                if title == "六月节" && y < 2021 { continue }
                let day = String(format:"%04d-%02d-%02d",y,m,n); add(day,title)
                if Day.weekday(day) == 6 { add(Day.add(day,-1),title+"（补假）","observed") }; if Day.weekday(day) == 0 { add(Day.add(day,1),title+"（补假）","observed") }
            }
            add(nth(y,1,3),"马丁·路德·金日"); add(nth(y,2,3),"总统日")
            var memorial = "\(y)-05-31"; while Day.weekday(memorial) != 1 { memorial = Day.add(memorial,-1) }; add(memorial,"阵亡将士纪念日")
            add(nth(y,9,1),"劳动节"); add(nth(y,10,2),"哥伦布日")
            let first = "\(y)-11-01"; add(Day.add(first,(4-Day.weekday(first)+7)%7+21),"感恩节")
        }; return result
    }
}
struct HolidayList: View {
    @EnvironmentObject var holidays: Holidays
    @State private var year = Day.calendar.component(.year,from:Date())
    @State private var country = "all"
    var body: some View {
        List {
            Section {
                Stepper("\(String(year))年",value:$year,in:1901...2099)
                Picker("国家",selection:$country) { Text("中国与美国").tag("all"); Text("中国").tag("CN"); Text("美国").tag("US") }
                Text(holidays.status).font(.caption)
                Button("校对所选年度") { Task { await holidays.refresh(force:true,year:year) } }.disabled(holidays.updating)
            }
            Section { ForEach(holidays.rows(year).filter { country == "all" || $0.country == country }) { h in VStack(alignment:.leading) { Text(h.date+" · "+h.name); Text((h.country == "CN" ? "中国" : "美国")+" · "+h.source).font(.caption).foregroundStyle(.secondary) } } } footer: { Text("公开维护来源，非政府官方接口。未收录年度不推算中国官方调休；单位安排以单位通知为准。") }
        }.navigationTitle("节假日表")
    }
}
