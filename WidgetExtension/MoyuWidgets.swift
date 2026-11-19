import SwiftUI
import WidgetKit
struct CalendarWidgetEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot?
}
struct CalendarProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalendarWidgetEntry { CalendarWidgetEntry(date:Date(),snapshot:nil) }
    func getSnapshot(in context: Context, completion: @escaping (CalendarWidgetEntry) -> Void) { completion(CalendarWidgetEntry(date:Date(),snapshot:WidgetStorage.read())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarWidgetEntry>) -> Void) {
        let now = Date(), snapshot = WidgetStorage.read()
        var entries = [CalendarWidgetEntry(date:now,snapshot:snapshot)]
        for offset in 1...7 {
            if let next = Calendar.current.date(byAdding:.day,value:offset,to:Calendar.current.startOfDay(for:now)) { entries.append(CalendarWidgetEntry(date:next,snapshot:snapshot)) }
        }
        completion(Timeline(entries:entries,policy:.after(now.addingTimeInterval(3600))))
    }
}
struct CalendarWidgetView: View {
    var entry: CalendarWidgetEntry
    var person: String
    @Environment(\.widgetFamily) private var family
    private var key: String {
        let c = Calendar(identifier:.gregorian).dateComponents([.year,.month,.day],from:entry.date)
        return String(format:"%04d-%02d-%02d",c.year!,c.month!,c.day!)
    }
    private func badges(_ day: WidgetDay) -> [WidgetBadge] { day.badges.filter { person == "all" || $0.person == person } }
    var body: some View {
        VStack(alignment:.leading,spacing:7) {
            Text("摸鱼日历 · "+(person == "all" ? "两人" : (entry.snapshot?.names[person] ?? (person == "p1" ? "我" : "搭班人")))).font(.caption.bold())
            if let snapshot = entry.snapshot {
                if family == .systemLarge { month(snapshot) } else { today(snapshot) }
                Spacer(minLength:0)
                Text(snapshot.summaries[person] ?? "").font(.system(size:10)).foregroundStyle(.secondary)
            } else {
                Text("打开摸鱼日历同步数据").font(.headline)
                Text("需保留小组件扩展和共享容器权限").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(12).widgetURL(URL(string:"moyu-calendar://date/"+key))
        .modifier(WidgetBackground())
    }
    private func today(_ snapshot: WidgetSnapshot) -> some View {
        VStack(alignment:.leading,spacing:5) {
            Text(key).font(.headline)
            if let day = snapshot.days.first(where: { $0.date == key }) {
                Text(day.lunar+" "+day.holiday).font(.caption2).lineLimit(2)
                ForEach(Array(badges(day).prefix(family == .systemSmall ? 3 : 5).enumerated()),id: \.offset) { _,badge in
                    Text(badge.title).font(.caption).foregroundStyle(Color(widgetHex:badge.color)).lineLimit(1)
                }
                if !day.note.isEmpty { Text(day.note).font(.caption2).lineLimit(2) }
                if badges(day).isEmpty { Text("今天未排班").font(.caption) }
            } else { Text("请打开应用更新日历").font(.caption) }
        }
    }
    private func month(_ snapshot: WidgetSnapshot) -> some View {
        let calendar = Calendar(identifier:.gregorian)
        let parts = calendar.dateComponents([.year,.month],from:entry.date)
        let first = calendar.date(from:DateComponents(year:parts.year,month:parts.month,day:1,hour:12))!
        let count = calendar.range(of:.day,in:.month,for:first)!.count
        let offset = (calendar.component(.weekday,from:first)-1-snapshot.weekStart+7)%7
        let rows = Dictionary(uniqueKeysWithValues:snapshot.days.map { ($0.date,$0) })
        return VStack(spacing:5) {
            Text(String(key.prefix(7))).font(.headline)
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:2),count:7),spacing:4) {
                ForEach(0..<7,id: \.self) { i in Text(["日","一","二","三","四","五","六"][(i+snapshot.weekStart)%7]).font(.system(size:10)).foregroundStyle(.secondary) }
                ForEach(0..<(offset+count),id: \.self) { i in
                    if i < offset { Color.clear.frame(height:32) }
                    else {
                        let date = String(format:"%04d-%02d-%02d",parts.year!,parts.month!,i-offset+1)
                        Link(destination:URL(string:"moyu-calendar://date/"+date)!) {
                            VStack(spacing:1) {
                                Text(String(i-offset+1)).font(.system(size:13,weight:.semibold)).foregroundStyle(Color(widgetHex:rows[date]?.color ?? "#24364b"))
                                if let day = rows[date] {
                                    Text(day.lunar).font(.system(size:7)).foregroundStyle(.secondary)
                                    let labels = badges(day).prefix(2).map(\.title).joined(separator:" ")
                                    Text(labels.isEmpty ? day.holiday : labels).font(.system(size:7)).lineLimit(1).minimumScaleFactor(0.5)
                                }
                            }.frame(maxWidth:.infinity,minHeight:32)
                            .background(date == key ? Color(widgetHex:snapshot.todayColor) : Color.clear,in:RoundedRectangle(cornerRadius:5))
                        }
                    }
                }
            }
            if let note = rows[key]?.note, !note.isEmpty { Text(note).font(.system(size:10)).lineLimit(1) }
        }
    }
}
private struct WidgetBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) { content.containerBackground(for:.widget) { Color.white } }
        else { content.background(Color.white) }
    }
}
private extension Color {
    init(widgetHex: String) {
        let n = UInt64(widgetHex.trimmingCharacters(in:CharacterSet(charactersIn:"#")),radix:16) ?? 0x39856a
        self.init(red:Double((n>>16)&255)/255,green:Double((n>>8)&255)/255,blue:Double(n&255)/255)
    }
}
struct MoyuWidget: Widget {
    var person: String
    var body: some WidgetConfiguration {
        StaticConfiguration(kind:"MoyuCalendar."+person,provider:CalendarProvider()) { CalendarWidgetView(entry:$0,person:person) }
            .configurationDisplayName("摸鱼日历 · "+(person == "p1" ? "我" : person == "p2" ? "搭班人" : "两人"))
            .description("今日安排、月历、农历、节假日与休假统计")
            .supportedFamilies([.systemSmall,.systemMedium,.systemLarge])
    }
}
@main struct MoyuWidgetBundle: WidgetBundle {
    var body: some Widget { MoyuWidget(person:"p1"); MoyuWidget(person:"p2"); MoyuWidget(person:"all") }
}
