import SwiftUI
import UniformTypeIdentifiers
struct StatisticsView: View {
    @EnvironmentObject var store: Store
    @State private var person = "p1"
    @State private var start = Day.date(String(Day.today.prefix(4))+"-01-01") ?? Date()
    @State private var end = Date()
    @State private var sharing: ShareFile?
    @State private var editing: Entry?
    @State private var kind = "all"
    var body: some View {
        let a = Day.key(start), b = Day.key(end), s = Roster.statistics(store.data,person,a,b)
        List {
            Section { PersonPicker(person:$person);
                HStack { Button("本月") { setRange(year:false) }; Spacer(); Button("本年") { setRange(year:true) } }
                Picker("明细类型",selection:$kind) { Text("全部").tag("all"); ForEach(Kind.allCases) { Text($0.title).tag($0.rawValue) } }
                 DatePicker("开始",selection:$start,displayedComponents:.date); DatePicker("结束",selection:$end,displayedComponents:.date) }
            if a > b || Day.distance(b,a) > 3660 { Text("请选择有效范围，最多10年").foregroundStyle(.red) }
            else {
                Section("加班与倒休") {
                    LabeledContent("加班日期数",value:"\(recordDates(.overtime,a,b))天")
                    LabeledContent("倒休日期数（含已安排）",value:"\(recordDates(.leave,a,b))天")
                    LabeledContent("加班",value:number(Double(s.overtime)/Double(store.data.unit))+"天")
                    LabeledContent("倒休已休",value:number(Double(s.leave)/Double(store.data.unit))+"天")
                    LabeledContent("已安排倒休",value:number(Double(s.planned)/Double(store.data.unit))+"天")
                    LabeledContent("可倒休（全期余额）",value:number(Double(s.balance)/Double(store.data.unit))+"天")
                }
                Section("排班统计") {
                    LabeledContent("基础夜班",value:"\(s.night)天")
                    LabeledContent("基础休息",value:number(s.rest)+"天")
                    LabeledContent("独立值班",value:"\(s.duty)天 · \(number(Double(s.dutyMinutes)/60))小时")
                    ForEach(store.data.people.filter { person == "all" || $0.id == person }) { p in let r = Roster.annual(store.data,p.id,String(b.prefix(4))); LabeledContent(p.name+" · 年假剩余",value:number(Double(r.remaining)/Double(store.data.unit))+"天") }
                    Text("独立值班不自动计加班；两人合计按人次计算。").font(.caption)
                }
                Section { Button("导出 Excel（含完整恢复数据）") { do { sharing = ShareFile(url:try Excel.export(store.data,start:a,end:b,person:person)) } catch { store.error = error.localizedDescription } } }
                Section("明细与销假来源（按类型筛选）") { ForEach(store.data.entries.filter { $0.date >= a && $0.date <= b && (person == "all" || $0.person == person) && (kind == "all" || $0.type.rawValue == kind) }.sorted { $0.date > $1.date }) { e in Button { editing = e } label: { EntryRow(entry:e) }.buttonStyle(.plain) } }
            }
        }.navigationTitle("统计总览").sheet(item:$sharing) { ShareView(url:$0.url) }.sheet(item:$editing) { RecordEditor(entry:$0) }
    }
    private func recordDates(_ type: Kind, _ a: String, _ b: String) -> Int {
        Set(store.data.entries.filter { $0.type == type && $0.date >= a && $0.date <= b && (person == "all" || $0.person == person) }.map { $0.person + "/" + $0.date }).count
    }
    private func setRange(year: Bool) {
        let today = Day.today
        start = Day.date(year ? String(today.prefix(4))+"-01-01" : String(today.prefix(7))+"-01") ?? Date()
        end = Date()
    }
}
struct PreferencesView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var holidays: Holidays
    @State private var year = Day.calendar.component(.year,from:Date())
    @State private var importing = false
    @State private var pending: CalendarData?
    @State private var sharing: ShareFile?
    var body: some View {
        Form {
            Section("日历") {
                Picker("每周起始",selection:Binding(get:{ store.data.weekStart },set:{ n in store.change { $0.settings.weekStart = n } })) { ForEach(0..<7,id:\.self) { Text("周"+["日","一","二","三","四","五","六"][$0]).tag($0) } }
                Toggle("农历",isOn:flag(\.lunar)); Toggle("中国节假日",isOn:flag(\.china)); Toggle("美国联邦假日",isOn:flag(\.usa))
                NavigationLink("节假日表") { HolidayList() }
                NavigationLink("班次与日期颜色") { PaletteView() }
            }
            Section("节假日校对") {
                Toggle("联网自动校对",isOn:$holidays.auto); Toggle("仅 Wi-Fi",isOn:$holidays.wifiOnly)
                Text(holidays.status).font(.caption)
                if holidays.checkedAt > 0 { Text("最近检查："+Date(timeIntervalSince1970:holidays.checkedAt).formatted()).font(.caption2) }
                Button(holidays.updating ? "校对中…" : "立即校对") { Task { await holidays.refresh(force:true) } }.disabled(holidays.updating)
                Text("前台或网络恢复时按6小时间隔检查；不是服务器实时推送。失败保留内置/缓存。").font(.caption)
            }
            Section("年假额度与折算") {
                Stepper("\(String(year))年",value:$year,in:1901...2099)
                ForEach(store.data.people) { p in HStack {
                    Text(p.name)
                    TextField("年假天数",value:Binding(get:{ store.data.annualAllowances?[String(year)]?[p.id] ?? 10 },set:{ n in store.change { d in var all = d.annualAllowances ?? [:], people = all[String(year)] ?? [:]; people[p.id] = n; all[String(year)] = people; d.annualAllowances = all } }),format:.number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    Text("天")
                } }
                Stepper("1天折算 \(number(store.data.settings.hoursPerDay)) 小时",value:Binding(get:{ store.data.settings.hoursPerDay },set:{ n in store.change { $0.settings.hoursPerDay = n } }),in:1...24,step:0.5)
            }
            Section("班前本地通知") {
                Toggle("开启通知",isOn:$store.reminders); Stepper("提前 \(store.lead) 分钟",value:$store.lead,in:0...1440,step:5)
                Button("保存提醒设置") { Task { await store.authorizeReminders() } }
                Text("需系统通知授权，受专注模式和系统调度影响。不是持续响铃闹钟。每次进入应用重新安排最近60条。").font(.caption)
            }
            Section("数据备份") {
                Button("导出完整 JSON") { do { sharing = ShareFile(url:try store.backup()) } catch { store.error = error.localizedDescription } }
                Button("导出本年 Excel（含完整恢复数据）") { do { sharing = ShareFile(url:try Excel.export(store.data,start:"\(year)-01-01",end:"\(year)-12-31",person:"all")) } catch { store.error = error.localizedDescription } }
                Button("从 JSON / Excel 恢复") { importing = true }
                Text("Excel必须包含本应用“完整恢复数据”表；确认后替换。统计筛选不限制恢复表的全量范围。").font(.caption)
            }
            Section("关于") {
                Text("摸鱼日历 · 原生 SwiftUI " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
                Text("个人记录本机保存，不上传；节假日来源为公开维护的 holiday-cn 和 Nager.Date。").font(.caption)
                Text("此免费侧载版不含 App Groups / WidgetKit 扩展或持续响铃闹钟。").font(.caption)
            }
        }.navigationTitle("我的设置").sheet(item:$sharing) { ShareView(url:$0.url) }
        .fileImporter(isPresented:$importing,allowedContentTypes:[.json,UTType(filenameExtension:"xlsx")!]) { result in do {
            let url = try result.get(), allowed = url.startAccessingSecurityScopedResource(); defer { if allowed { url.stopAccessingSecurityScopedResource() } }
            guard ((try url.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0) <= 32*1024*1024 else { throw AppError.invalid("文件不能超过32MB") }
            let raw = url.pathExtension.lowercased() == "xlsx" ? try Excel.restore(url) : try Data(contentsOf:url)
            pending = try store.restore(raw)
        } catch { store.error = error.localizedDescription } }
        .confirmationDialog("将替换现有数据，请先备份。",isPresented:Binding(get:{ pending != nil },set:{ if !$0 { pending = nil } }),titleVisibility:.visible) {
            Button("恢复 \(pending?.entries.count ?? 0) 条记录",role:.destructive) { do { if let d = pending { try store.save(d,restoring:true) }; pending = nil } catch { store.error = error.localizedDescription } }
            Button("取消",role:.cancel) { pending = nil }
        }
    }
    private func flag(_ path: WritableKeyPath<Settings,Bool>) -> Binding<Bool> { Binding(get:{ store.data.settings[keyPath:path] },set:{ v in store.change { $0.settings[keyPath:path] = v } }) }
}
