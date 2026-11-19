import SwiftUI
import UIKit

struct PaletteView: View {
    @EnvironmentObject var store: Store
    private var items: [(String,String)] {
        [("day","白班"),("p1",store.name("p1")+" · 夜班"),("p2",store.name("p2")+" · 夜班"),("off","休息"),("duty","独立值班"),("overtime","加班"),("leave","倒休"),("annual","年假"),("today","今天背景")]
    }
    var body: some View {
        Form {
            Section("自定义配色") {
                ForEach(items,id: \.0) { key,title in
                    ColorPicker(title,selection:binding(key),supportsOpacity:false)
                }
            }
            Section {
                Text("日期字体优先显示年假、倒休、加班、独立值班、夜班、基础班次的颜色。两人夜班分别配色；具体安排以当天标签为准。").font(.caption)
                Button("恢复默认颜色") { store.change { $0.colors = CalendarData().colors } }
            }
        }.navigationTitle("班次与日期颜色")
    }
    private func binding(_ key: String) -> Binding<Color> {
        Binding(get:{ store.color(key) },set:{ color in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            guard UIColor(color).getRed(&r,green:&g,blue:&b,alpha:&a) else { return }
            let hex = String(format:"#%02X%02X%02X",Int((r*255).rounded()),Int((g*255).rounded()),Int((b*255).rounded()))
            store.change { $0.colors[key] = hex }
        })
    }
}
