import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import ZIPFoundation
enum Excel {
    static func esc(_ s: String) -> String { s.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;").replacingOccurrences(of:"'",with:"&apos;") }
    static func xml(_ rows: [[String]], numbers: Set<Int> = []) -> String {
        let body = rows.enumerated().map { i,row in
            "<row r=\"\(i+1)\">"+row.enumerated().map { j,value in
                let ref = "\(String(UnicodeScalar(65+j)!))\(i+1)"
                if i > 0, numbers.contains(j), let number = Double(value), number.isFinite { return "<c r=\"\(ref)\"><v>\(value)</v></c>" }
                return "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(esc(value))</t></is></c>"
            }.joined()+"</row>"
        }.joined()
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>"+body+"</sheetData></worksheet>"
    }
    static func export(_ d: CalendarData, start: String, end: String, person: String) throws -> URL {
        guard Day.date(start) != nil, Day.date(end) != nil, start <= end, Day.distance(end,start) <= 3660 else { throw AppError.invalid("导出范围无效或超过10年") }
        let people = d.people.filter { person == "all" || $0.id == person }
        func name(_ id: String) -> String { d.people.first { $0.id == id }?.name ?? id }
        var stats = [["人员","开始","结束","加班天","倒休已休天","已安排倒休天","可倒休天","基础夜班天","基础休息天","独立值班天","值班小时"]]
        for p in people { let s = Roster.statistics(d,p.id,start,end); stats.append([p.name,start,end,number(Double(s.overtime)/Double(d.unit)),number(Double(s.leave)/Double(d.unit)),number(Double(s.planned)/Double(d.unit)),number(Double(s.balance)/Double(d.unit)),"\(s.night)",number(s.rest),"\(s.duty)",number(Double(s.dutyMinutes)/60)]) }
        var details = [["编号","日期","人员","类型","小时","折算天","时段","备注"]]
        for e in d.entries.filter({ $0.date >= start && $0.date <= end && (person == "all" || $0.person == person) }).sorted(by:{ $0.date < $1.date }) { details.append([e.id,e.date,name(e.person),e.type.title,number(Double(e.minutes)/60),number(Double(e.minutes)/Double(d.unit)),e.part ?? "",e.note]) }
        var links = [["人员","加班日期","加班备注","倒休日期","倒休备注","核销小时","加班编号","倒休编号"]], relevant = Set<String>()
        for e in d.entries where e.type == .leave && (person == "all" || e.person == person) {
            for a in e.allocations ?? [] {
                guard let o = d.entries.first(where:{ $0.id == a.overtimeId }) else { continue }
                if (e.date >= start && e.date <= end) || (o.date >= start && o.date <= end) { relevant.insert(o.id); links.append([name(e.person),o.date,o.note,e.date,e.note,number(Double(a.minutes)/60),o.id,e.id]) }
            }
        }
        var ledger = [["人员","日期","编号","备注","加班小时","核销小时","剩余小时"]]
        for e in d.entries where e.type == .overtime && (person == "all" || e.person == person) && ((e.date >= start && e.date <= end) || relevant.contains(e.id)) {
            let used = d.entries.filter { $0.type == .leave }.flatMap { $0.allocations ?? [] }.filter { $0.overtimeId == e.id }.reduce(0) { $0+$1.minutes }
            ledger.append([name(e.person),e.date,e.id,e.note,number(Double(e.minutes)/60),number(Double(used)/60),number(Double(e.minutes-used)/60)])
        }
        var annual = [["年份","人员","年假总额天","已使用及安排天","剩余天"]]
        for y in (Int(start.prefix(4))!)...(Int(end.prefix(4))!) { for p in people { let a = Roster.annual(d,p.id,String(y)); annual.append([String(y),p.name,number(Double(a.total)/Double(d.unit)),number(Double(a.used)/Double(d.unit)),number(Double(a.remaining)/Double(d.unit))]) } }
        var daily = [["日期","人员","基础班次","基础时间","独立值班","值班时间","值班小时","农历","单日备注"]], day = start
        while day <= end {
            for p in people { let s = Roster.shift(d,p.id,day), r = Roster.duty(d,p.id,day); daily.append([day,p.name,s?.title ?? "未排班",s.map { Roster.time(p,$0) } ?? "",r == nil ? "" : "值班",r?.time ?? "",number(Double(r?.minutes ?? 0)/60),Day.lunar(day),d.dayNotes?[day]?[p.id] ?? ""]) }
            day = Day.add(day,1)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; let raw = String(decoding:try encoder.encode(d),as:UTF8.self)
        var backup = [["字段","内容"],["format","BANLI_BACKUP_V1"],["说明","完整恢复数据包含全部人员和历史记录，编辑其他统计表不会更改这里。"],["length",String(raw.utf16.count)]]
        var chunk = "", units = 0, count = 0
        for scalar in raw.unicodeScalars { let n = scalar.value > 0xffff ? 2 : 1; if units+n > 28000 { backup.append([String(format:"chunk%05d",count),chunk]); count += 1; chunk = ""; units = 0 }; chunk.unicodeScalars.append(scalar); units += n }
        if !chunk.isEmpty { backup.append([String(format:"chunk%05d",count),chunk]) }
        let names = ["统计汇总","加班休假明细","销假对应关系","加班余额台账","年度年假","每日排班","完整恢复数据"], tables = [stats,details,links,ledger,annual,daily,backup]
        let numeric: [Set<Int>] = [Set(3...10),[4,5],[5],[4,5,6],[0,2,3,4],[6],[]]
        let head = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        var parts: [String:String] = [:]
        parts["[Content_Types].xml"] = head+"<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"+(1...7).map { "<Override PartName=\"/xl/worksheets/sheet\($0).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>" }.joined()+"</Types>"
        parts["_rels/.rels"] = head+"<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"
        parts["xl/workbook.xml"] = head+"<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets>"+names.enumerated().map { "<sheet name=\"\($0.element)\" sheetId=\"\($0.offset+1)\" r:id=\"rId\($0.offset+1)\"/>" }.joined()+"</sheets></workbook>"
        parts["xl/_rels/workbook.xml.rels"] = head+"<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"+(1...7).map { "<Relationship Id=\"rId\($0)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\($0).xml\"/>" }.joined()+"</Relationships>"
        for (i,t) in tables.enumerated() { parts["xl/worksheets/sheet\(i+1).xml"] = xml(t,numbers:numeric[i]) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("摸鱼日历统计_\(UUID().uuidString.prefix(8)).xlsx"), archive = try Archive(url:url,accessMode:.create)
        for (path,text) in parts.sorted(by:{ $0.key < $1.key }) { let data = Data(text.utf8); try archive.addEntry(with:path,type:.file,uncompressedSize:Int64(data.count),compressionMethod:.deflate) { position,size in data.subdata(in:Int(position)..<min(Int(position)+size,data.count)) } }
        return url
    }
    static func restore(_ url: URL) throws -> Data {
        let archive = try Archive(url:url,accessMode:.read)
        func read(_ path: String) throws -> Data {
            guard let e = archive[path], e.uncompressedSize <= 12*1024*1024 else { throw AppError.invalid("Excel恢复表缺失或过大") }; var data = Data()
            _ = try archive.extract(e) { c in guard data.count+c.count <= 12*1024*1024 else { throw AppError.invalid("恢复内容过大") }; data.append(c) }; return data
        }
        let book = TableParser(); try book.parse(read("xl/workbook.xml")); guard let id = book.sheets["完整恢复数据"] else { throw AppError.invalid("Excel不含完整恢复数据表") }
        let rel = TableParser(); try rel.parse(read("xl/_rels/workbook.xml.rels")); guard let target = rel.relationships[id], !target.contains("..") else { throw AppError.invalid("Excel关系表无效") }
        let parser = TableParser()
        if archive["xl/sharedStrings.xml"] != nil { let s = TableParser(); try s.parse(read("xl/sharedStrings.xml")); parser.shared = s.strings }
        try parser.parse(read(target.hasPrefix("/") ? String(target.dropFirst()) : "xl/"+target))
        let values = Dictionary(parser.rows.compactMap { row -> (String,String)? in guard let a = row["A"], let b = row["B"] else { return nil }; return (a,b) },uniquingKeysWith:{ _,new in new })
        guard values["format"] == "BANLI_BACKUP_V1" else { throw AppError.invalid("不是本应用备份格式") }
        let keys = values.keys.filter { $0.hasPrefix("chunk") }.sorted(); guard !keys.isEmpty else { throw AppError.invalid("备份分段缺失") }; var raw = ""
        for (i,key) in keys.enumerated() { guard key == String(format:"chunk%05d",i) else { throw AppError.invalid("备份分段不完整") }; raw += values[key] ?? ""; guard raw.utf16.count <= 10*1024*1024 else { throw AppError.invalid("备份超过10MB") } }
        guard raw.utf16.count == Int(values["length"] ?? "") else { throw AppError.invalid("备份长度不完整") }
        if let checksum = values["checksum-fnv1a32"] { var hash: UInt32 = 2166136261; for n in raw.utf16 { hash = (hash ^ UInt32(n)) &* 16777619 }; guard String(format:"%08x",hash) == checksum else { throw AppError.invalid("恢复数据校验失败") } }
        return Data(raw.utf8)
    }
}
private final class TableParser: NSObject, XMLParserDelegate {
    var rows: [[String:String]] = [], sheets: [String:String] = [:], relationships: [String:String] = [:], strings: [String] = [], shared: [String] = []
    private var row: [String:String] = [:], column = "", type = "", value = "", item = "", capture = false, inItem = false
    func parse(_ data: Data) throws { let p = XMLParser(data:data); p.delegate = self; p.shouldResolveExternalEntities = false; guard p.parse() else { throw p.parserError ?? AppError.invalid("Excel XML无效") } }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String:String]) {
        if name == "sheet", let n = a["name"], let id = a["r:id"] { sheets[n] = id }; if name == "Relationship", let id = a["Id"], let target = a["Target"] { relationships[id] = target }
        if name == "row" { row = [:] }; if name == "si" { inItem = true; item = "" }
        if name == "c" { column = String((a["r"] ?? "").prefix { $0.isLetter }); type = a["t"] ?? ""; value = "" }
        if name == "t" || name == "v" { capture = true }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if capture { if inItem { item += string } else { value += string } } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "t" || name == "v" { capture = false }; if name == "si" { strings.append(item); inItem = false }
        if name == "c" { if type == "s", let n = Int(value), shared.indices.contains(n) { row[column] = shared[n] } else { row[column] = value } }
        if name == "row" { rows.append(row) }
    }
}
