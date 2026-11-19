import SwiftUI
struct PeopleView: View {
    @EnvironmentObject var store: Store
    var body: some View { List { Section { ForEach(store.data.people) { p in NavigationLink(p.name) { RosterEditor(person:p) } } } footer: { Text("两人的基础班表与独立值班互不覆盖。旧版规则在确认应用前保持原样。") } }.navigationTitle("轮班设置") }
}
struct RosterEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var person: Person
    @State private var base: BaseRule
    @State private var duty: DutyRule
    @State private var sequence: String
    @State private var preview = false
    @State private var problem: String?
    init(person: Person) { _person = State(initialValue:person); _base = State(initialValue:person.baseDraft); _duty = State(initialValue:person.dutyDraft); _sequence = State(initialValue:person.baseDraft.sequence.map(\.rawValue).joined(separator:",")) }
    var body: some View {
        Form {
            Section("人员") { TextField("姓名",text:$person.name) }
            Section("基础班表") {
                Toggle("启用基础排班",isOn:$base.enabled)
                Picker("模式",selection:$base.mode) { Text("每周安排").tag("weekly"); Text("周期轮换").tag("cycle"); Text("手动日期").tag("manual") }
                DatePicker("生效日期",selection:dateBinding($base.start),displayedComponents:.date)
                if base.mode == "weekly" { ForEach([1,2,3,4,5,6,0],id:\.self) { i in Picker("周"+["日","一","二","三","四","五","六"][i],selection:$base.weekly[i]) { Text("未排班").tag(""); ForEach(Shift.allCases) { Text($0.title).tag($0.rawValue) } } } }
                if base.mode == "cycle" { TextField("day,night,off,off",text:$sequence).textInputAutocapitalization(.never); Text("day=白班、night=夜班、off=休息，以英文逗号分隔，最多60天。").font(.caption) }
                timeField("白班开始",$base.dayStart); timeField("白班结束",$base.dayEnd); timeField("夜班开始",$base.nightStart); timeField("夜班结束",$base.nightEnd)
            }
            Section("独立值班") {
                Toggle("启用固定间隔值班",isOn:$duty.enabled)
                Picker("模式",selection:$duty.mode) { Text("固定间隔").tag("interval"); Text("手动日期").tag("manual") }
                DatePicker("首次值班",selection:dateBinding($duty.start),displayedComponents:.date)
                Stepper("每 \(duty.intervalDays) 个自然日一次",value:$duty.intervalDays,in:1...365)
                timeField("值班开始",$duty.startTime); timeField("值班结束",$duty.endTime)
                Text("白班、夜班、休息均可叠加值班；结束时间不晚于开始时按次日结束。单日修改优先。").font(.caption)
            }
            Section { Button("预览并应用") { do { try Roster.validate(proposed()); preview = true } catch { problem = error.localizedDescription } } }
        }.navigationTitle(person.name+" · 排班")
        .alert("设置无效",isPresented:Binding(get:{ problem != nil },set:{ if !$0 { problem = nil } })) { Button("知道了",role:.cancel) {} } message: { Text(problem ?? "") }
        .sheet(isPresented:$preview) { NavigationStack { List {
            Section("起始日期之后5次值班") { ForEach(previewDates(),id:\.self) { day in VStack(alignment:.leading) { Text(day+" · "+(Roster.shift(proposed(),person.id,day)?.title ?? "未排班")+"＋值班"); Text(Roster.duty(proposed(),person.id,day)?.time ?? "").font(.caption) } }; if previewDates().isEmpty { Text("尚无独立值班；基础班表仍可应用。") } }
            Section { Button("确认应用") { do { try store.save(proposed()); preview = false; dismiss() } catch { preview = false; problem = error.localizedDescription } } }
        }.navigationTitle("排班预览").toolbar { Button("返回修改") { preview = false } } } }
    }
    private func proposed() -> CalendarData {
        var d = store.data, p = person, b = base
        let parts = sequence.split(separator:",").map { $0.trimmingCharacters(in:.whitespaces) }, parsed = parts.compactMap(Shift.init(rawValue:))
        b.sequence = parsed.count == parts.count ? parsed : []
        p.base = b; p.duty = duty
        if let i = d.people.firstIndex(where:{ $0.id == p.id }) { d.people[i] = p }; return d
    }
    private func previewDates() -> [String] {
        var result: [String] = []
        for i in 0..<3660 { let day = Day.add(duty.start,i); if Day.date(day) == nil { break }; if Roster.duty(proposed(),person.id,day) != nil { result.append(day); if result.count == 5 { break } } }; return result
    }
}
func timeField(_ title: String, _ v: Binding<String>) -> some View { HStack { Text(title); Spacer(); TextField("HH:mm",text:v).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).frame(width:85) } }
struct RecordEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var entry: Entry
    @State private var hours: Double
    @State private var problem: String?
    @State private var deleting = false
    @State private var manualSources = false
    @State private var sources = Set<String>()
    init(entry: Entry) { _entry = State(initialValue:entry); _hours = State(initialValue:Double(entry.minutes)/60); _manualSources = State(initialValue:entry.type == .leave && !(entry.allocations ?? []).isEmpty); _sources = State(initialValue:Set((entry.allocations ?? []).map(\.overtimeId))) }
    var body: some View {
        NavigationStack { Form {
            Section {
                PersonPicker(person:$entry.person,all:false)
                Picker("类型",selection:$entry.type) { ForEach(Kind.allCases) { Text($0.title).tag($0) } }
                DatePicker("日期",selection:dateBinding($entry.date),displayedComponents:.date)
                HStack { Button("半天") { hours = store.data.settings.hoursPerDay/2 }; Spacer(); Button("一天") { hours = store.data.settings.hoursPerDay } }
                TextField("小时",value:$hours,format:.number).keyboardType(.decimalPad)
                Text("折合 \(number(hours/store.data.settings.hoursPerDay)) 天；最小15分钟。").font(.caption)
                Picker("时段备注",selection:Binding(get:{ entry.part ?? "" },set:{ entry.part = $0.isEmpty ? nil : $0 })) { Text("自定时长").tag(""); Text("上午").tag("am"); Text("下午").tag("pm"); Text("全天").tag("full") }
                TextField("备注（最多200字）",text:$entry.note,axis:.vertical)
            }
            if entry.type == .leave {
                Section("销假来源") {
                    Toggle("手动指定加班记录",isOn:$manualSources)
                    if manualSources {
                        ForEach(Roster.available(store.data,entry.person,excluding:entry.id,asOf:min(entry.date,Day.today)),id: \.0.id) { overtime,remaining in
                            Toggle(isOn:Binding(get:{ sources.contains(overtime.id) },set:{ selected in
                                if selected { sources.insert(overtime.id) } else { sources.remove(overtime.id) }
                            })) {
                                VStack(alignment:.leading) {
                                    Text(overtime.date+" · 可用 "+number(Double(remaining)/Double(store.data.unit))+"天")
                                    if !overtime.note.isEmpty { Text(overtime.note).font(.caption) }
                                }
                            }
                        }
                        Text("只从选中的记录核销；余额不足会阻止保存。").font(.caption)
                    } else { Text("按最早可用加班自动核销，保留加班日期和原备注。").font(.caption) }
                }
            }
            if store.data.entries.contains(where:{ $0.id == entry.id }) { Section { Button("删除记录",role:.destructive) { deleting = true } } }
        }.navigationTitle(entry.type.title)
        .toolbar {
            ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement:.confirmationAction) { Button("保存") { do { guard hours.isFinite, hours > 0, hours <= 24 else { throw AppError.invalid("时长应在0.25至24小时") }; let m = Int((hours*60).rounded()); guard m%15 == 0 else { throw AppError.invalid("请按15分钟递增") }; entry.minutes = m; try store.writeEntry(entry,sourceIDs:manualSources ? Array(sources) : nil); dismiss() } catch { problem = error.localizedDescription } } }
        }
        .confirmationDialog("删除记录？已核销的加班需先处理对应倒休。",isPresented:$deleting) { Button("删除",role:.destructive) { do { try store.delete(entry.id); dismiss() } catch { problem = error.localizedDescription } } }
        .alert("无法保存",isPresented:Binding(get:{ problem != nil },set:{ if !$0 { problem = nil } })) { Button("知道了",role:.cancel) {} } message: { Text(problem ?? "") } }
    }
}
struct DayEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    var day: String
    @State var person: String
    @State private var base = "auto"
    @State private var duty = "auto"
    @State private var start = "20:00"
    @State private var end = "08:00"
    @State private var note = ""
    @State private var problem: String?
    var body: some View {
        NavigationStack { Form {
            Section(day) { PersonPicker(person:$person,all:false) }
            Section("基础安排") { Picker("当天班次",selection:$base) { Text("跟随规则").tag("auto"); Text("未排班").tag("none"); ForEach(Shift.allCases) { Text($0.title).tag($0.rawValue) } } }
            Section("独立值班") { Picker("当天值班",selection:$duty) { Text("跟随规则").tag("auto"); Text("当天值班").tag("yes"); Text("当天不值班").tag("no") }; timeField("值班开始",$start); timeField("值班结束",$end) }
            Section("备注") { TextField("最多200字",text:$note,axis:.vertical) }
            Section { Button("恢复自动规则") { base = "auto"; duty = "auto" } }
        }.navigationTitle("修改当天安排").onAppear(perform:load).onChange(of:person) { _ in load() }
        .toolbar {
            ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement:.confirmationAction) { Button("保存") { do {
                var d = store.data, shifts = d.overrides[day] ?? [:]; shifts[person] = base == "auto" ? nil : base; d.overrides[day] = shifts.isEmpty ? nil : shifts
                var allDuty = d.dutyOverrides ?? [:], duties = allDuty[day] ?? [:]; duties[person] = duty == "auto" ? nil : DutyOverride(enabled:duty == "yes",startTime:start,endTime:end); allDuty[day] = duties.isEmpty ? nil : duties; d.dutyOverrides = allDuty
                var allNotes = d.dayNotes ?? [:], notes = allNotes[day] ?? [:]; notes[person] = note.isEmpty ? nil : note; allNotes[day] = notes.isEmpty ? nil : notes; d.dayNotes = allNotes
                try store.save(d); dismiss()
            } catch { problem = error.localizedDescription } } }
        }
        .alert("无法保存",isPresented:Binding(get:{ problem != nil },set:{ if !$0 { problem = nil } })) { Button("知道了",role:.cancel) {} } message: { Text(problem ?? "") } }
    }
    private func load() {
        base = store.data.overrides[day]?[person] ?? "auto"
        let o = store.data.dutyOverrides?[day]?[person], r = store.data.people.first { $0.id == person }?.dutyDraft ?? DutyRule()
        duty = o.map { $0.enabled ? "yes" : "no" } ?? "auto"; start = o?.startTime ?? r.startTime; end = o?.endTime ?? r.endTime; note = store.data.dayNotes?[day]?[person] ?? ""
    }
}
