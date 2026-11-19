import XCTest
import ZIPFoundation
@testable import MoyuCore
final class DomainTests: XCTestCase {
    func dual() -> CalendarData {
        var d = CalendarData(), b = BaseRule(), r = DutyRule()
        b.start = "2026-11-01"; r.enabled = true; r.start = "2026-11-09"; r.intervalDays = 5
        d.people[0].base = b; d.people[0].duty = r; return d
    }
    func testWhiteAndRestBothSupportDuty() throws {
        let d = dual(); try Roster.validate(d)
        XCTAssertEqual(Roster.shift(d,"p1","2026-11-09"),.day)
        XCTAssertEqual(Roster.shift(d,"p1","2026-11-14"),.off)
        XCTAssertEqual(Roster.duty(d,"p1","2026-11-14")?.minutes,720)
        XCTAssertNil(Roster.duty(d,"p1","2026-11-13"))
    }
    func testWeekStartDoesNotMoveDates() {
        var d = dual()
        for n in 0...6 { d.settings.weekStart = n; XCTAssertEqual(Roster.shift(d,"p1","2026-11-09"),.day); XCTAssertNotNil(Roster.duty(d,"p1","2026-11-14")) }
    }
    func testManualCancellationKeepsBaseAndOtherPerson() throws {
        var d = dual(); d.people[1].duty = d.people[0].duty
        d.dutyOverrides = ["2026-11-14":["p1":DutyOverride(enabled:false)]]
        XCTAssertNil(Roster.duty(d,"p1","2026-11-14")); XCTAssertNotNil(Roster.duty(d,"p2","2026-11-14")); XCTAssertEqual(Roster.shift(d,"p1","2026-11-14"),.off); try Roster.validate(d)
    }
    func testHalfDayRedemptionAndDeletionProtection() throws {
        var d = dual(); d.entries = [Entry(id:"ot",date:"2026-11-01",person:"p1",type:.overtime,minutes:480,note:"项目支持")]
        let links = try Roster.allocate(d,"p1",240,asOf:"2026-11-10")
        d.entries.append(Entry(id:"leave",date:"2026-11-10",person:"p1",type:.leave,minutes:240,note:"半天倒休",allocations:links))
        try Roster.validate(d)
        XCTAssertEqual(Roster.available(d,"p1",asOf:"2026-11-10").first?.1,240)
        XCTAssertThrowsError(try Roster.allocate(d,"p1",480,asOf:"2026-11-10"))
        d.entries.removeAll { $0.id == "ot" }; XCTAssertThrowsError(try Roster.validate(d))
    }
    func testSelectedSourcesNeverConsumeUnselectedOvertime() throws {
        var d = dual()
        d.entries = [
            Entry(id:"old",date:"2026-11-01",person:"p1",type:.overtime,minutes:480,note:"旧记录"),
            Entry(id:"chosen",date:"2026-11-03",person:"p1",type:.overtime,minutes:240,note:"指定记录"),
            Entry(id:"other",date:"2026-11-02",person:"p2",type:.overtime,minutes:480,note:"他人记录")
        ]
        let links = try Roster.allocate(d,"p1",240,asOf:"2026-11-10",sourceIDs:["chosen"])
        XCTAssertEqual(links,[Allocation(overtimeId:"chosen",minutes:240)])
        XCTAssertThrowsError(try Roster.allocate(d,"p1",480,asOf:"2026-11-10",sourceIDs:["chosen"]))
        XCTAssertThrowsError(try Roster.allocate(d,"p1",240,asOf:"2026-11-10",sourceIDs:["other"]))
        XCTAssertThrowsError(try Roster.allocate(d,"p1",240,asOf:"2026-11-02",sourceIDs:["chosen"]))
        XCTAssertEqual(try Roster.allocate(d,"p1",240,asOf:"2026-11-10").first?.overtimeId,"old")
        d.entries.append(Entry(id:"redeem",date:"2026-11-10",person:"p1",type:.leave,minutes:240,allocations:links))
        try Roster.validate(d)
        XCTAssertEqual(Roster.available(d,"p1",excluding:"redeem",asOf:"2026-11-10").first(where: { $0.0.id == "chosen" })?.1,240)
    }
    func testAnnualHalfDayAndIndependentBalance() throws {
        var d = dual(); d.entries = [Entry(date:"2026-11-11",person:"p1",type:.annual,minutes:240,note:"半天年假")]
        try Roster.validate(d); XCTAssertEqual(Roster.annual(d,"p1","2026").remaining,4560)
        XCTAssertEqual(Roster.statistics(d,"p1","2026-11-01","2026-11-30",today:"2026-11-18").balance,0)
    }
    func testLegacyIntervalDoesNotMigrateAutomatically() throws {
        var d = CalendarData(); d.people[0].enabled = true; d.people[0].start = "2026-11-09"; d.people[0].mode = "interval"; d.people[0].intervalDays = 5; d.people[0].intervalShift = .night; d.people[0].intervalRest = true
        let raw = try JSONEncoder().encode(d), restored = try JSONDecoder().decode(CalendarData.self,from:raw)
        try Roster.validate(restored); XCTAssertNil(restored.people[0].base); XCTAssertEqual(Roster.shift(restored,"p1","2026-11-14"),.night)
    }
    func testInvalidRulesAndLeapDay() throws {
        var d = dual(); d.people[0].duty?.intervalDays = 0
        XCTAssertThrowsError(try Roster.validate(d)); XCTAssertNil(Day.date("2026-02-30")); XCTAssertEqual(Day.add("2028-02-28",1),"2028-02-29")
    }
    func testRealExcelRoundTripWithUnicodeAndAllData() throws {
        var d = dual(); d.settings.weekStart = 0; d.dayNotes = ["2026-11-14":["p1":"休息＋值班🙂"]]
        for n in 0..<250 { d.entries.append(Entry(id:"ot\(n)",date:"2026-11-01",person:n%2 == 0 ? "p1" : "p2",type:.overtime,minutes:240,note:String(repeating:"项目🙂",count:20))) }
        try Roster.validate(d)
        let url = try Excel.export(d,start:"2026-11-01",end:"2026-11-02",person:"p1"); defer { try? FileManager.default.removeItem(at:url) }
        let raw = try Excel.restore(url), restored = try JSONDecoder().decode(CalendarData.self,from:raw)
        XCTAssertEqual(restored,d)
        let zip = try Archive(url:url,accessMode:.read); XCTAssertNotNil(zip["xl/worksheets/sheet7.xml"])
    }
    func testAnnualSeparatesUsedAndPlannedAndPreservesBalance() throws {
        var d = dual()
        d.entries = [
            Entry(date:"2026-11-01",person:"p1",type:.annual,minutes:240),
            Entry(date:"2026-12-01",person:"p1",type:.annual,minutes:480)
        ]
        let a = Roster.annual(d,"p1","2026",today:"2026-11-19")
        XCTAssertEqual(a.total,4800); XCTAssertEqual(a.used,240)
        XCTAssertEqual(a.planned,480); XCTAssertEqual(a.remaining,4080)
        try Roster.validate(d)
    }
    func testReminderSelectionLeavesDutyIndependentAndIncludesCustom() throws {
        var d = dual()
        d.people[0].duty?.start = "2026-11-11"; d.people[0].duty?.intervalDays = 1
        d.entries = [Entry(date:"2026-11-11",person:"p1",type:.annual,minutes:480)]
        var settings = ReminderSettings()
        settings.people = ["p1"]; settings.briefing = true
        settings.custom = [CustomReminder(id:"custom",title:"填写日报",date:"2026-11-11",time:"09:00",enabled:true)]
        let now = Day.calendar.startOfDay(for:Day.date("2026-11-11")!)
        let plans = ReminderPlanner.plan(d,settings:settings,lead:30,now:now)
        XCTAssertFalse(plans.contains { $0.id == "moyu/p1/2026-11-11/day" })
        XCTAssertTrue(plans.contains { $0.id == "moyu/p1/2026-11-11/duty" })
        XCTAssertTrue(plans.contains { $0.id == "moyu/custom/custom" && $0.title == "填写日报" })
        XCTAssertTrue(plans.contains { $0.id == "moyu/briefing/2026-11-11" && $0.body.contains("值班") })
        XCTAssertFalse(plans.contains { $0.id.hasPrefix("moyu/p2/") })
        settings.kinds = []
        XCTAssertFalse(ReminderPlanner.plan(d,settings:settings,lead:30,now:now).contains { $0.id.hasSuffix("/duty") })
        try settings.validate()
        settings.custom[0].time = "25:00"; XCTAssertThrowsError(try settings.validate())
    }
    func testExcelIncludesHolidayRowsAndBackupStillRestores() throws {
        let d = dual()
        let holiday = ExportHoliday(date:"2026-11-11",country:"US",name:"退伍军人节",kind:"holiday",source:"测试来源")
        let url = try Excel.export(d,start:"2026-11-01",end:"2026-11-30",person:"p1",holidays:[holiday])
        defer { try? FileManager.default.removeItem(at:url) }
        let archive = try Archive(url:url,accessMode:.read)
        for sheet in [6,8] {
            var bytes = Data()
            _ = try archive.extract(archive["xl/worksheets/sheet\(sheet).xml"]!) { bytes.append($0) }
            XCTAssertTrue(String(decoding:bytes,as:UTF8.self).contains("退伍军人节"))
        }
        XCTAssertEqual(try JSONDecoder().decode(CalendarData.self,from:Excel.restore(url)),d)
        let table = try Excel.holidayTable([holiday]); defer { try? FileManager.default.removeItem(at:table) }
        XCTAssertThrowsError(try Excel.restore(table))
    }
    func testReminderSettingsSurviveBackupAndLegacyDefaults() throws {
        var d = dual(), settings = ReminderSettings()
        settings.custom = [CustomReminder(title:"提醒",date:"2026-12-01",time:"10:00")]
        d.reminderSettings = settings
        let raw = try JSONEncoder().encode(d)
        XCTAssertEqual(try JSONDecoder().decode(CalendarData.self,from:raw),d)
        var object = try JSONSerialization.jsonObject(with:raw) as! [String:Any]
        object.removeValue(forKey:"reminderSettings")
        let legacy = try JSONDecoder().decode(CalendarData.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertNil(legacy.reminderSettings); try Roster.validate(legacy)
    }
    func testFormulaLikeNotesArePlainText() throws {
        var d = dual(); d.entries = [Entry(date:"2026-11-01",person:"p1",type:.overtime,minutes:240,note:"=SUM(1,1)")]
        let url = try Excel.export(d,start:"2026-11-01",end:"2026-11-01",person:"p1"); defer { try? FileManager.default.removeItem(at:url) }
        let zip = try Archive(url:url,accessMode:.read); var xml = Data()
        _ = try zip.extract(zip["xl/worksheets/sheet2.xml"]!) { xml.append($0) }
        let text = String(decoding:xml,as:UTF8.self); XCTAssertTrue(text.contains("=SUM(1,1)")); XCTAssertFalse(text.contains("<f>"))
    }
}
