import Foundation
struct WidgetDay: Codable, Identifiable {
    var date: String, lunar: String, holiday: String, note: String
    var badges: [WidgetBadge]
    var color: String
    var id: String { date }
}
struct WidgetBadge: Codable {
    var title: String, color: String, person: String
}
struct WidgetSnapshot: Codable {
    var generated: Date, days: [WidgetDay], summaries: [String:String], names: [String:String]
    var weekStart: Int, todayColor: String
}
enum WidgetStorage {
    static let group = "group.com.banli.shift.shared"
    static func container() -> URL? {
        var candidates = [group]
        if let url = Bundle.main.url(forResource:"embedded",withExtension:"mobileprovision"),
           let raw = try? Data(contentsOf:url),
           let start = raw.range(of:Data("<?xml".utf8)),
           let end = raw.range(of:Data("</plist>".utf8)), end.upperBound > start.lowerBound,
           let plist = try? PropertyListSerialization.propertyList(from:raw.subdata(in:start.lowerBound..<end.upperBound),format:nil) as? [String:Any],
           let entitlements = plist["Entitlements"] as? [String:Any],
           let groups = entitlements["com.apple.security.application-groups"] as? [String] {
            candidates = groups.filter { $0.hasPrefix(group) } + candidates
        }
        for candidate in candidates {
            if let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:candidate) { return root }
        }
        return nil
    }
    static func read() -> WidgetSnapshot? {
        guard let root = container(), let raw = try? Data(contentsOf:root.appendingPathComponent("widget.json")), raw.count <= 2*1024*1024 else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self,from:raw)
    }
}
