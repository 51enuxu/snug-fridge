import SwiftUI

// MARK: - 冰箱 · 今天吃什么
//
// 菜谱库：随 App 打包的 Fridge/recipes.json，来自开源菜谱 HowToCook（程序员做饭指南，Unlicense），
// 353 道家常菜。按冰箱里的东西本地匹配，快过期的优先。想换成自己的菜谱，替换 assets/recipes.json
// 再跑 scripts/sync-assets.sh（格式见 README）。

private let fridgeInk = Color(cpHex: "#5A4334")
private let fridgeMuted = Color(cpHex: "#A88E78")
private let fridgePaper = Color(cpHex: "#FFFBF4")
private let fridgeCell = Color(cpHex: "#F6ECE0")
private let fridgeRose = Color(cpHex: "#C98A92")
private let fridgeSage = Color(cpHex: "#7E9A72")

struct FridgeRecipe: Identifiable, Decodable {
    struct Ingredient: Decodable {
        let name: String
        let optional: Bool
        let amount: String?
    }
    let name: String
    let cat: String
    let stars: Int
    let lead: String
    let ingredients: [Ingredient]
    let steps: [String]
    var id: String { name }
}

/// 一道菜对上冰箱的结果
struct FridgeRecipeMatch: Identifiable {
    let recipe: FridgeRecipe
    /// 主料里冰箱有的（菜谱里的叫法）
    let have: [String]
    /// 主料里还缺的
    let missing: [String]
    /// 用上的冰箱里的东西
    let usedItems: [FridgeItem]
    /// 用上的东西里快过期的有几样（排序用）
    let urgency: Int
    var id: String { recipe.id }
}

enum FridgeRecipeBook {
    static let all: [FridgeRecipe] = {
        guard let url = Bundle.main.url(forResource: "recipes", withExtension: "json", subdirectory: "Fridge"),
              let data = try? Data(contentsOf: url) else { return [] }
        struct Payload: Decodable { let recipes: [FridgeRecipe] }
        return (try? JSONDecoder().decode(Payload.self, from: data))?.recipes ?? []
    }()

    /// 一般家里都有的调料：不算「缺」，也不靠它们来匹配。只认完整名字——
    /// 按「包含」判断会把黄油当成油、洋葱当成葱、水饺当成水
    private static let pantry: Set<String> = [
        "盐", "食盐", "食用盐", "生抽", "老抽", "酱油", "食用油", "植物油", "油", "花生油", "橄榄油", "菜籽油",
        "料酒", "黄酒", "糖", "白糖", "白砂糖", "冰糖", "红糖", "蚝油", "淀粉", "生粉", "玉米淀粉", "鸡精", "鸡粉",
        "味精", "水", "清水", "开水", "热水", "温水", "冰水", "冰块", "香油", "芝麻油", "醋", "香醋", "陈醋", "白醋",
        "米醋", "八角", "香叶", "桂皮", "花椒", "花椒粉", "干辣椒", "五香粉", "孜然", "孜然粉", "番茄酱", "豆瓣酱",
        "葱", "小葱", "大葱", "香葱", "葱花", "葱段", "姜", "生姜", "姜片", "姜末", "老姜", "蒜", "大蒜", "蒜头",
        "蒜瓣", "蒜末", "蒜蓉", "芝麻", "白芝麻", "黑芝麻", "辣椒粉", "辣椒面", "辣椒油", "小米辣", "小米椒",
        "香菜", "十三香", "陈皮", "草果", "甜面酱", "腐乳", "鱼露", "胡椒", "胡椒粉", "白胡椒", "白胡椒粉",
        "黑胡椒", "黑胡椒粉",
    ]

    /// 同一种东西的不同叫法
    private static let synonyms: [[String]] = [
        ["西红柿", "番茄"], ["土豆", "马铃薯", "洋芋"], ["鸡蛋", "鸡蛋液", "蛋液", "鸡蛋黄", "蛋黄", "蛋清"],
        ["蘑菇", "香菇", "口蘑", "平菇", "杏鲍菇", "金针菇", "菌菇", "蟹味菇", "白玉菇"],
        ["彩椒", "甜椒", "青椒", "红椒", "灯笼椒", "青辣椒"], ["西兰花", "西蓝花", "花椰菜"],
        ["牛肉", "牛腩", "肥牛", "牛排", "牛里脊", "牛腱"], ["鸡肉", "鸡胸", "鸡腿", "鸡翅", "鸡块", "鸡爪"],
        ["猪肉", "五花肉", "里脊", "肉末", "肉馅", "排骨", "梅花肉", "瘦肉", "猪肉末"],
        ["虾", "虾仁", "大虾", "基围虾", "虾滑", "鲜虾"],
        ["鱼", "鲈鱼", "草鱼", "鳕鱼", "三文鱼", "鱼片", "鲫鱼", "龙利鱼", "巴沙鱼"],
        ["米饭", "剩饭", "隔夜饭", "白米饭", "熟米饭"], ["面条", "挂面", "拉面", "乌冬", "意面", "意大利面", "手擀面"],
        ["芝士", "奶酪", "马苏里拉"], ["牛奶", "纯牛奶", "鲜奶"], ["水饺", "饺子", "速冻水饺"],
        ["面包", "吐司"], ["橙子", "橙"], ["生菜", "球生菜"], ["培根", "烟肉"], ["黄油", "牛油"],
    ]

    private static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: " ", with: "").lowercased()
    }

    static func isPantry(_ ingredient: String) -> Bool {
        pantry.contains(normalized(ingredient))
    }

    private static func group(_ text: String) -> Int? {
        synonyms.firstIndex { words in words.contains { text == $0 || ($0.count >= 2 && text.contains($0)) } }
    }

    /// 冰箱里这样东西能不能当这个用料
    static func matches(item: String, ingredient: String) -> Bool {
        let a = normalized(item), b = normalized(ingredient)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        if a.count >= 2 && b.contains(a) { return true }
        if b.count >= 2 && a.contains(b) { return true }
        if let ga = group(a), let gb = group(b), ga == gb { return true }
        return false
    }

    static func match(_ recipe: FridgeRecipe, items: [FridgeItem]) -> FridgeRecipeMatch {
        var have: [String] = [], missing: [String] = [], used: [FridgeItem] = []
        for ingredient in recipe.ingredients where !isPantry(ingredient.name) {
            if let item = items.first(where: { matches(item: $0.name, ingredient: ingredient.name) }) {
                have.append(ingredient.name)
                if !used.contains(where: { $0.id == item.id }) { used.append(item) }
            } else if !ingredient.optional {
                missing.append(ingredient.name)
            }
        }
        let urgency = used.reduce(0) { sum, item in
            guard let days = FridgeDue.daysLeft(item) else { return sum }
            return sum + (days <= 2 ? 2 : days <= 5 ? 1 : 0)
        }
        return FridgeRecipeMatch(recipe: recipe, have: have, missing: missing, usedItems: used, urgency: urgency)
    }

    /// 冰箱能凑上的菜：至少用上一样，最多缺三样。能直接做的在前，其次快过期的用得多的
    static func suggestions(for items: [FridgeItem]) -> [FridgeRecipeMatch] {
        all.map { match($0, items: items) }
            .filter { !$0.have.isEmpty && $0.missing.count <= 3 }
            .sorted {
                if ($0.missing.isEmpty) != ($1.missing.isEmpty) { return $0.missing.isEmpty }
                if $0.urgency != $1.urgency { return $0.urgency > $1.urgency }
                if $0.missing.count != $1.missing.count { return $0.missing.count < $1.missing.count }
                if $0.have.count != $1.have.count { return $0.have.count > $1.have.count }
                return $0.recipe.stars < $1.recipe.stars
            }
    }
}

// MARK: - 弹层

struct FridgeRecipeSheet: View {
    @ObservedObject var theme: FridgeTheme
    @ObservedObject var store: FridgeStore
    /// 做完一道菜：把勾选的东西各吃掉一份（走冰箱页自己的吃掉动画和提示）
    let onCooked: ([FridgeItem]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var suggestions: [FridgeRecipeMatch] { FridgeRecipeBook.suggestions(for: store.items) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                library
            }
            .background(fridgePaper.ignoresSafeArea())
            .navigationTitle("今天吃什么")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关上") { dismiss() }.foregroundStyle(fridgeInk.opacity(0.7))
                }
            }
            .navigationDestination(for: String.self) { name in
                if let recipe = FridgeRecipeBook.all.first(where: { $0.name == name }) {
                    FridgeRecipeDetail(recipe: recipe, store: store, onCooked: { used in
                        dismiss()
                        onCooked(used)
                    })
                }
            }
        }
    }

    // MARK: 菜谱库

    private var library: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(fridgeMuted)
                    TextField("想做别的？搜菜名", text: $query)
                        .font(FridgeFont.cute(15)).foregroundStyle(fridgeInk)
                }
                .padding(.horizontal, 14).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))

                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    let found = FridgeRecipeBook.all.filter { $0.name.contains(query.trimmingCharacters(in: .whitespaces)) }
                    sectionTitle(found.isEmpty ? "没找到这道菜" : "搜到 \(found.count) 道")
                    ForEach(found.prefix(40)) { recipe in
                        row(FridgeRecipeBook.match(recipe, items: store.items))
                    }
                } else if store.items.isEmpty {
                    hint("冰箱是空的。先放点东西进去，或者直接搜菜名")
                } else {
                    let ready = suggestions.filter { $0.missing.isEmpty }
                    let close = suggestions.filter { !$0.missing.isEmpty && $0.missing.count <= 2 }
                    if ready.isEmpty && close.isEmpty {
                        hint("冰箱里的东西凑不出菜谱库里的菜，搜搜菜名看看")
                    }
                    if !ready.isEmpty {
                        sectionTitle("现在就能做")
                        ForEach(ready.prefix(20)) { row($0) }
                    }
                    if !close.isEmpty {
                        sectionTitle("差一两样")
                        ForEach(close.prefix(20)) { row($0) }
                    }
                }
                Text("菜谱来自开源项目 HowToCook（程序员做饭指南）")
                    .font(.system(size: 10.5)).foregroundStyle(fridgeMuted.opacity(0.8))
                    .frame(maxWidth: .infinity).padding(.top, 14)
            }
            .padding(.horizontal, 18).padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(FridgeFont.cute(15)).foregroundStyle(fridgeInk.opacity(0.75)).padding(.top, 8)
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(FridgeFont.cute(14)).foregroundStyle(fridgeMuted)
            .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 30)
    }

    private func row(_ match: FridgeRecipeMatch) -> some View {
        NavigationLink(value: match.recipe.name) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(match.recipe.name).font(FridgeFont.cute(17)).foregroundStyle(fridgeInk).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(match.recipe.cat + (match.recipe.stars > 0 ? " · " + String(repeating: "★", count: match.recipe.stars) : ""))
                        .font(.system(size: 11)).foregroundStyle(fridgeMuted)
                }
                if !match.usedItems.isEmpty {
                    Text("用上：" + match.usedItems.map(\.name).joined(separator: "、"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(match.urgency > 0 ? fridgeRose : fridgeSage)
                        .lineLimit(1)
                }
                if !match.missing.isEmpty {
                    Text("还缺：" + match.missing.joined(separator: "、"))
                        .font(.system(size: 12)).foregroundStyle(fridgeMuted).lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
        }
        .buttonStyle(.plain)
    }
}

private struct FridgeRecipeDetail: View {
    let recipe: FridgeRecipe
    @ObservedObject var store: FridgeStore
    let onCooked: ([FridgeItem]) -> Void
    @State private var cooking = false
    @State private var picked: Set<String> = []

    private var match: FridgeRecipeMatch { FridgeRecipeBook.match(recipe, items: store.items) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recipe.name).font(FridgeFont.cute(24)).foregroundStyle(fridgeInk)
                    Text(recipe.cat + (recipe.stars > 0 ? " · 难度 " + String(repeating: "★", count: recipe.stars) : ""))
                        .font(.system(size: 12)).foregroundStyle(fridgeMuted)
                    if !recipe.lead.isEmpty {
                        Text(recipe.lead).font(.system(size: 13.5)).foregroundStyle(fridgeInk.opacity(0.8)).lineSpacing(4)
                    }
                }

                card("用料（一人份）") {
                    ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { _, ingredient in
                        let pantry = FridgeRecipeBook.isPantry(ingredient.name)
                        let inFridge = store.items.first { FridgeRecipeBook.matches(item: $0.name, ingredient: ingredient.name) }
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: inFridge != nil ? "checkmark.circle.fill" : pantry ? "circle.dotted" : "circle")
                                .font(.system(size: 13))
                                .foregroundStyle(inFridge != nil ? fridgeSage : fridgeMuted.opacity(0.7))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ingredient.name + (ingredient.optional ? "（可选）" : ""))
                                    .font(.system(size: 14.5, weight: .medium)).foregroundStyle(fridgeInk)
                                if let amount = ingredient.amount {
                                    Text(amount.replacingOccurrences(of: "* 份数", with: "").replacingOccurrences(of: "*份数", with: ""))
                                        .font(.system(size: 11.5)).foregroundStyle(fridgeMuted)
                                }
                            }
                            Spacer(minLength: 0)
                            Text(inFridge.map { "冰箱有 · \($0.name)" } ?? (pantry ? "调料" : "要买"))
                                .font(.system(size: 11)).foregroundStyle(inFridge != nil ? fridgeSage : fridgeMuted)
                        }
                    }
                }

                card("步骤") {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1)").font(FridgeFont.cute(15)).foregroundStyle(fridgeRose).frame(width: 18)
                            Text(step).font(.system(size: 14)).foregroundStyle(fridgeInk).lineSpacing(4)
                        }
                    }
                }

                Text("菜谱来自开源项目 HowToCook（程序员做饭指南），分量按一人份写")
                    .font(.system(size: 10.5)).foregroundStyle(fridgeMuted.opacity(0.8))
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 100)
        }
        .background(fridgePaper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !match.usedItems.isEmpty {
                Button {
                    picked = Set(match.usedItems.map(\.id))
                    cooking = true
                } label: {
                    Text("做了这道").font(FridgeFont.cute(17)).foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Capsule().fill(fridgeRose))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18).padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $cooking) { cookedSheet }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(FridgeFont.cute(15)).foregroundStyle(fridgeInk.opacity(0.7))
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
    }

    /// 做完了：勾上的东西各从冰箱里拿掉一份，默认全勾，可以取消
    private var cookedSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("用掉了哪些？").font(FridgeFont.cute(19)).foregroundStyle(fridgeInk)
            Text("勾上的各吃掉一份，没用完的取消勾选就好").font(.system(size: 12.5)).foregroundStyle(fridgeMuted)
            ForEach(match.usedItems) { item in
                Button {
                    if picked.contains(item.id) { picked.remove(item.id) } else { picked.insert(item.id) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: picked.contains(item.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(picked.contains(item.id) ? fridgeRose : fridgeMuted)
                        Text(item.name).font(FridgeFont.cute(16)).foregroundStyle(fridgeInk)
                        Spacer()
                        Text(item.quantity > 1 ? "还有 \(Int(item.quantity)) \(item.unit)" : "最后一\(item.unit)")
                            .font(.system(size: 12)).foregroundStyle(fridgeMuted)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            Button {
                let used = match.usedItems.filter { picked.contains($0.id) }
                cooking = false
                // 等这层勾选弹窗收完再关外面的菜谱弹窗：两层同一拍收，外层那次会被系统吞掉
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { onCooked(used) }
            } label: {
                Text(picked.isEmpty ? "什么都没用掉" : "从冰箱拿掉").font(FridgeFont.cute(17)).foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(Capsule().fill(fridgeRose))
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .background(fridgePaper.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }
}
