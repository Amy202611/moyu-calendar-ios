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
    func testFormulaLikeNotesArePlainText() throws {
        var d = dual(); d.entries = [Entry(date:"2026-11-01",person:"p1",type:.overtime,minutes:240,note:"=SUM(1,1)")]
        let url = try Excel.export(d,start:"2026-11-01",end:"2026-11-01",person:"p1"); defer { try? FileManager.default.removeItem(at:url) }
        let zip = try Archive(url:url,accessMode:.read); var xml = Data()
        _ = try zip.extract(zip["xl/worksheets/sheet2.xml"]!) { xml.append($0) }
        let text = String(decoding:xml,as:UTF8.self); XCTAssertTrue(text.contains("=SUM(1,1)")); XCTAssertFalse(text.contains("<f>"))
    }
}
