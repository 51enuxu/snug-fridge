import SwiftUI
import PhotosUI
import UIKit

// MARK: - 冰箱 · 底部弹层：详情卡 / 放进冰箱&编辑 / 纸条

struct FridgeEditorTarget: Identifiable {
    let id = UUID()
    let item: FridgeItem?
    let zone: FridgeZone?
}

private let fridgeInk = Color(cpHex: "#5A4334")
private let fridgeMuted = Color(cpHex: "#A88E78")
private let fridgePaper = Color(cpHex: "#FFFBF4")
private let fridgeCell = Color(cpHex: "#F6ECE0")
private let fridgeRose = Color(cpHex: "#C98A92")

private func fridgeDate(_ date: Date?) -> String {
    guard let date else { return "—" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M月d日 E"
    return formatter.string(from: date)
}

/// 点贴纸弹出的详情卡
struct FridgeItemSheet: View {
    @ObservedObject var theme: FridgeTheme
    let item: FridgeItem
    let onEat: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRemove = false

    /// 保质期过了算过期；没填保质期就看建议吃完的日子
    private var expired: Bool {
        let cal = Calendar.current
        guard let due = item.expiresAt ?? item.eatBy else { return false }
        return cal.startOfDay(for: due) < cal.startOfDay(for: Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                FridgeSticker(item: item)
                    .frame(width: 96, height: 96)
                    .rotationEffect(.degrees(FridgeSticker.tilt(item.id)))
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name).font(FridgeFont.cute(26)).foregroundStyle(fridgeInk)
                    Text(FridgeDue.label(item))
                        .font(FridgeFont.cute(15))
                        .foregroundStyle(FridgeDue.color(FridgeDue.tone(item)))
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(FridgeDue.color(FridgeDue.tone(item)).opacity(0.12)))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22).padding(.top, 26)

            VStack(spacing: 0) {
                row("数量", item.quantityText)
                row("放在", item.zone.title)
                row("放进来", fridgeDate(item.addedAt))
                row("保质期到", fridgeDate(item.expiresAt))
                row("建议吃完", fridgeDate(item.eatBy))
                if !item.notes.isEmpty { row("备注", item.notes) }
            }
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(fridgeCell))
            .padding(.horizontal, 18).padding(.top, 18)

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                action(confirmRemove ? "真的移除" : "移除", icon: "trash",
                       tint: confirmRemove ? Color(cpHex: "#C9524F") : fridgeMuted) {
                    if confirmRemove { dismiss(); onRemove() } else { confirmRemove = true }
                }
                action("编辑", icon: "pencil", tint: fridgeMuted) { dismiss(); onEdit() }
                // 过期了就别「吃掉」了：主按钮换成「扔掉」
                Button { dismiss(); if expired { onRemove() } else { onEat() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: expired ? "trash" : "fork.knife").font(.system(size: 14, weight: .semibold))
                        Text(expired ? "扔掉" : item.quantity > 1 ? "吃掉一\(item.unit)" : "吃掉啦").font(FridgeFont.cute(17))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Capsule().fill(expired ? Color(cpHex: "#9A8A89") : fridgeRose))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18).padding(.bottom, 12)
        }
        .background(fridgePaper.ignoresSafeArea())
        .fridgeDismissKeyboardOnTap()
        .presentationDetents([.height(item.notes.isEmpty ? 470 : 520)])
        .presentationDragIndicator(.visible)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(FridgeFont.cute(15)).foregroundStyle(fridgeMuted)
            Spacer(minLength: 16)
            Text(value).font(FridgeFont.cute(15)).foregroundStyle(fridgeInk)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func action(_ title: String, icon: String, tint: Color, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                Text(title).font(FridgeFont.cute(12))
            }
            .foregroundStyle(tint)
            .frame(width: 70, height: 50)
            .background(Capsule().fill(fridgeCell))
        }
        .buttonStyle(.plain)
    }
}

/// 放进冰箱 / 编辑。选了贴纸就按贴纸库预填名字、位置和保质期
struct FridgeEditorSheet: View {
    @ObservedObject var theme: FridgeTheme
    let target: FridgeEditorTarget
    let onSave: (FridgeItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: FridgeItem
    @State private var hasDueDate: Bool
    /// 自己动过日期（拖日期 / 点快捷）就不再按类型自动改
    @State private var dateTouched = false
    @State private var photoItem: PhotosPickerItem?
    @State private var cameraOpen = false
    @State private var cutting = false
    @State private var cutError: String?
    /// nil = 全部
    @State private var category: FridgeFoodCategory?

    init(theme: FridgeTheme, target: FridgeEditorTarget, onSave: @escaping (FridgeItem) -> Void) {
        self.theme = theme
        self.target = target
        self.onSave = onSave
        if let item = target.item {
            _draft = State(initialValue: item)
            _hasDueDate = State(initialValue: item.eatBy != nil)
        } else {
            let entry = FridgeCatalog.all[0]
            var item = FridgeItem(name: entry.name, unit: entry.unit, zone: target.zone ?? entry.zone,
                                  stickerAsset: entry.asset)
            Self.applyShelfLife(entry.shelfDays, to: &item)
            _draft = State(initialValue: item)
            _hasDueDate = State(initialValue: true)
        }
    }

    private static func applyShelfLife(_ days: Int, to item: inout FridgeItem) {
        let cal = Calendar.current
        // 从放进来那天起算：补记前几天放的东西，日期不会被往后推
        let start = cal.startOfDay(for: item.addedAt)
        item.eatBy = cal.date(byAdding: .day, value: max(days - 1, 0), to: start)
        item.expiresAt = cal.date(byAdding: .day, value: days, to: start)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    stickerPicker
                    field("名字") {
                        TextField("比如：草莓", text: $draft.name)
                            .font(FridgeFont.cute(17)).foregroundStyle(fridgeInk)
                    }
                    field("数量") {
                        HStack {
                            Stepper(value: $draft.quantity, in: 1...99, step: 1) {
                                Text(draft.quantityText).font(FridgeFont.cute(17)).foregroundStyle(fridgeInk)
                            }
                        }
                    }
                    field("放在哪") {
                        Picker("放在哪", selection: $draft.zone) {
                            ForEach(FridgeZone.allCases) { zone in Text(zone.title).tag(zone) }
                        }
                        .pickerStyle(.menu)
                        .tint(fridgeInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    // 补记前几天买的东西：放入日期可以往前改
                    field("放进来") {
                        DatePicker("放进来的日期", selection: $draft.addedAt, in: ...Date(), displayedComponents: .date)
                            .font(FridgeFont.cute(15))
                    }
                    field("建议吃完") {
                        Toggle(isOn: $hasDueDate) {
                            Text(hasDueDate ? "要提醒" : "不着急").font(FridgeFont.cute(16)).foregroundStyle(fridgeInk)
                        }
                        .tint(fridgeRose)
                        if hasDueDate {
                            dueSuggestion
                            DatePicker("吃完日期", selection: Binding(
                                get: { draft.eatBy ?? Date() },
                                set: { draft.eatBy = $0; dateTouched = true }), displayedComponents: .date)
                                .font(FridgeFont.cute(15))
                            DatePicker("保质期到", selection: Binding(
                                get: { draft.expiresAt ?? draft.eatBy ?? Date() },
                                set: { draft.expiresAt = $0; dateTouched = true }), displayedComponents: .date)
                                .font(FridgeFont.cute(15))
                        }
                    }
                    field("备注") {
                        TextField("比如：热一下再吃", text: $draft.notes, axis: .vertical)
                            .font(FridgeFont.cute(16)).foregroundStyle(fridgeInk)
                            .lineLimit(1...4)
                    }
                }
                .padding(18)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: draft.zone) { _ in autoDue() }
            .onChange(of: draft.stickerAsset) { _ in autoDue() }
            .onChange(of: draft.addedAt) { _ in autoDue() }
            .background(fridgePaper.ignoresSafeArea())
            .fridgeDismissKeyboardOnTap()
            .navigationTitle(target.item == nil ? "放进冰箱" : "改一改")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.foregroundStyle(fridgeMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("放好了") {
                        var saved = draft
                        if !hasDueDate { saved.eatBy = nil; saved.expiresAt = nil }
                        saved.name = saved.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if saved.name.isEmpty { saved.name = FridgeCatalog.entry(saved.stickerAsset)?.name ?? "一样东西" }
                        onSave(saved)
                        dismiss()
                    }
                    .foregroundStyle(fridgeRose)
                    .font(.system(size: 16, weight: .semibold))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .overlay {
            if cutting {
                VStack(spacing: 10) {
                    ProgressView().tint(fridgeRose)
                    Text("正在把它剪成贴纸…").font(FridgeFont.cute(15)).foregroundStyle(fridgeInk)
                }
                .padding(24)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(fridgePaper))
                .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
            }
        }
        .sheet(isPresented: $cameraOpen) {
            FridgeCameraPicker { cut($0) }.ignoresSafeArea()
        }
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    cut(image)
                }
                photoItem = nil
            }
        }
    }

    /// 只抠图 + 加奶白边，不重画
    private func cut(_ image: UIImage) {
        cutError = nil
        cutting = true
        Task {
            do {
                let sticker = try await FridgePhotoCutout.makeSticker(from: image)
                guard let asset = FridgeArt.savePhotoSticker(sticker) else { throw FridgePhotoCutout.Failure.render }
                let previousDefault = FridgeCatalog.entry(draft.stickerAsset)?.name
                draft.stickerSource = .photo
                draft.stickerAsset = asset
                if draft.name == previousDefault { draft.name = "" }
            } catch FridgePhotoCutout.Failure.unsupported {
                cutError = "这台手机的系统太旧，抠不了图"
            } catch FridgePhotoCutout.Failure.noSubject {
                cutError = "没认出要剪的东西，换个角度再拍一张试试"
            } catch {
                // 系统抠图本身跑不起来（模拟器里固定是 Vision Code 9：没有神经网络推理环境），不是照片的问题
#if targetEnvironment(simulator)
                cutError = "模拟器里抠不了图，用手机试试"
#else
                cutError = "剪贴纸的时候出了点问题，再试一次"
#endif
            }
            cutting = false
        }
    }

    private var stickerPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("选一张贴纸，或者拍一张").font(FridgeFont.cute(14)).foregroundStyle(fridgeMuted)
            HStack(spacing: 10) {
                if draft.stickerSource == .photo {
                    FridgeSticker(item: draft)
                        .frame(width: 70, height: 70)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fridgeRose.opacity(0.16)))
                }
                Button { cameraOpen = true } label: { photoButton("拍照", icon: "camera") }
                    .buttonStyle(.plain)
                PhotosPicker(selection: $photoItem, matching: .images) { photoButton("从相册", icon: "photo") }
                    .buttonStyle(.plain)
                Spacer(minLength: 0)
            }
            if let cutError {
                Text(cutError).font(FridgeFont.cute(13)).foregroundStyle(Color(cpHex: "#C9524F"))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    categoryChip(nil, title: "全部")
                    ForEach(FridgeFoodCategory.allCases.filter { cat in
                        FridgeCatalog.all.contains { $0.category == cat }
                    }) { cat in
                        categoryChip(cat, title: cat.title)
                    }
                }
                .padding(3)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: [GridItem(.fixed(70)), GridItem(.fixed(70))], spacing: 8) {
                    ForEach(FridgeCatalog.all.filter { category == nil || $0.category == category }) { entry in
                        Button { pick(entry) } label: {
                            VStack(spacing: 0) {
                                if let image = FridgeArt.image(entry.asset, sticker: true) {
                                    Image(uiImage: image).resizable().scaledToFit().frame(width: 48, height: 48)
                                }
                                Text(entry.name).font(FridgeFont.cute(11)).foregroundStyle(fridgeInk).lineLimit(1)
                            }
                            .frame(width: 64, height: 70)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(draft.stickerSource == .builtIn && draft.stickerAsset == entry.asset
                                      ? fridgeRose.opacity(0.16) : fridgeCell))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(draft.stickerSource == .builtIn && draft.stickerAsset == entry.asset
                                        ? fridgeRose : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                // 四周留 3pt：选中贴纸的描边画在格子边上，贴着滚动区会被削掉一截
                .padding(3)
            }
        }
    }

    private func categoryChip(_ value: FridgeFoodCategory?, title: String) -> some View {
        let selected = category == value
        return Button {
            withAnimation(.easeOut(duration: 0.18)) { category = value }
        } label: {
            Text(title)
                .font(FridgeFont.cute(14))
                .foregroundStyle(selected ? Color.white : fridgeInk)
                .padding(.horizontal, 14).frame(height: 32)
                .background(Capsule().fill(selected ? fridgeRose : fridgeCell))
        }
        .buttonStyle(.plain)
    }

    private func photoButton(_ title: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 18, weight: .medium))
            Text(title).font(FridgeFont.cute(12))
        }
        .foregroundStyle(fridgeInk)
        .frame(width: 70, height: 70)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(fridgeMuted.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
    }

    private func pick(_ entry: FridgeCatalogEntry) {
        let previousDefault = FridgeCatalog.entry(draft.stickerAsset)?.name
        draft.stickerAsset = entry.asset
        draft.stickerSource = .builtIn
        // 名字还是上一张贴纸的默认名（或空）才跟着换，自己改过的名字不覆盖
        if draft.name.isEmpty || draft.name == previousDefault { draft.name = entry.name }
        draft.unit = entry.unit
        if target.item == nil {
            if target.zone == nil { draft.zone = entry.zone }
            autoDue()
        }
    }

    /// 新放的东西：按类型 + 位置自动填建议日期
    private func autoDue() {
        guard target.item == nil, !dateTouched else { return }
        Self.applyShelfLife(suggestedDays.days, to: &draft)
        hasDueDate = true
    }

    /// 拿不准保质期时给个参考：按贴纸认出的食材 + 放的位置估一个天数，下面一排点一下直接填
    private var suggestedDays: (days: Int, why: String) {
        let frozen: Set<FridgeZone> = [.freezerTop, .freezer, .freezerDoor, .freezerDoorLow]
        if frozen.contains(draft.zone) { return (60, "冷冻的东西一般 1–3 个月内吃掉，味道最好") }
        if draft.stickerSource == .builtIn, let entry = FridgeCatalog.entry(draft.stickerAsset),
           entry.asset != "paper_bag", entry.asset != "unknown_food_box" {
            return (entry.shelfDays, "\(entry.name)放冷藏，一般 \(Self.dayText(entry.shelfDays))内吃完比较新鲜")
        }
        if draft.zone.isOnDoor { return (30, "门架上的酱料、饮料，开封后一般 1 个月内用完") }
        return (5, "拿不准的话：剩菜熟食 2–3 天，蔬果一周左右，包装零食看开没开封")
    }

    private static func dayText(_ days: Int) -> String {
        switch days {
        case 30...: return "\(days / 30) 个月"
        case 7 where days % 7 == 0: return "1 周"
        case 14: return "2 周"
        default: return "\(days) 天"
        }
    }

    private static let dueChoices: [(String, Int)] = [("今天", 1), ("3 天", 3), ("1 周", 7), ("2 周", 14), ("1 个月", 30), ("3 个月", 90)]

    private var dueSuggestion: some View {
        let hint = suggestedDays
        let current = draft.eatBy.map { (Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: draft.addedAt),
                                                                          to: Calendar.current.startOfDay(for: $0)).day ?? 0) + 1 } ?? hint.days
        let closest = Self.dueChoices.min { abs($0.1 - current) < abs($1.1 - current) }?.1
        return VStack(alignment: .leading, spacing: 8) {
            Text(hint.why)
                .font(FridgeFont.cute(13))
                .foregroundStyle(fridgeMuted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.dueChoices, id: \.1) { choice in
                        let on = closest == choice.1
                        Button {
                            Self.applyShelfLife(choice.1, to: &draft)
                            dateTouched = true
                        } label: {
                            Text(choice.0)
                                .font(FridgeFont.cute(13))
                                .foregroundStyle(on ? Color.white : fridgeInk)
                                .padding(.horizontal, 11).frame(height: 28)
                                .background(Capsule().fill(on ? fridgeRose : fridgeCell))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
            }
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(FridgeFont.cute(14)).foregroundStyle(fridgeMuted)
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fridgeCell))
        }
    }
}

/// 贴一张新便签：写字 + 挑纸、固定方式、字体字号，上面实时预览
struct FridgeNoteComposer: View {
    @ObservedObject var theme: FridgeTheme
    let onSave: (String, FridgeNoteStyle) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var style = FridgeNoteStyle(paper: .yellow, attach: .magnetBlue, font: .kuaile, fontSize: 26)
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button("取消") { dismiss() }.foregroundStyle(fridgeMuted)
                Spacer()
                Text("贴便签").font(FridgeFont.cute(18)).foregroundStyle(fridgeInk)
                Spacer()
                Button("贴上") {
                    guard !trimmed.isEmpty else { return }
                    onSave(trimmed, style)
                    dismiss()
                }
                .foregroundStyle(trimmed.isEmpty ? fridgeMuted : fridgeRose)
                .font(.system(size: 16, weight: .semibold))
            }
            FridgeNoteView(note: FridgeNote(text: trimmed.isEmpty ? "写点什么…" : trimmed, author: .me,
                                            x: 0, y: 0, tilt: -3, paper: style.paper, attach: style.attach,
                                            font: style.font, fontSize: style.fontSize))
                .scaleEffect(0.8)
                .frame(height: 170)
                .padding(.top, 8)
            TextField("写点什么，比如：要买鸡蛋", text: $text, axis: .vertical)
                .font(FridgeFont.cute(18))
                .foregroundStyle(fridgeInk)
                .lineLimit(2...4)
                .focused($focused)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fridgeCell))
            ScrollView(showsIndicators: false) {
                FridgeNoteStylePicker(style: style, dark: false) { style = $0 }
            }
        }
        .padding(20)
        .background(fridgePaper.ignoresSafeArea())
        .fridgeDismissKeyboardOnTap()
        .presentationDetents([.large])
        .onAppear { focused = true }
    }
}

/// 纸 / 固定方式 / 字体三排小样 + 字号滑杆，点哪个换哪个
struct FridgeNoteStylePicker: View {
    let style: FridgeNoteStyle
    var dark = true
    let onChange: (FridgeNoteStyle) -> Void

    private func changed(_ edit: (inout FridgeNoteStyle) -> Void) {
        var next = style
        edit(&next)
        onChange(next)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row("纸") {
                ForEach(FridgePaper.allCases) { option in
                    chip(selected: option == style.paper, title: option.title) {
                        FridgeNoteView(note: FridgeNote(text: "", author: .me, x: 0, y: 0,
                                                        paper: option, attach: style.attach))
                            .scaleEffect(0.22)
                            .frame(width: 52, height: 44)
                    } action: { changed { $0.paper = option } }
                }
            }
            row("固定") {
                ForEach(FridgeAttach.allCases) { option in
                    chip(selected: option == style.attach, title: option.title) {
                        FridgeAttachView(kind: option)
                            .scaleEffect(0.62)
                            .frame(width: 52, height: 44)
                    } action: { changed { $0.attach = option } }
                }
            }
            row("字体") {
                ForEach(FridgeNoteFont.allCases) { option in
                    chip(selected: option == style.font, title: option.title) {
                        Text("便签")
                            .font(FridgeFont.note(option, 19))
                            .foregroundStyle(fridgeInk)
                            .frame(width: 52, height: 44)
                    } action: { changed { $0.font = option } }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("字号").font(FridgeFont.cute(13)).foregroundStyle(fridgeMuted)
                HStack(spacing: 10) {
                    Text("小").font(FridgeFont.note(style.font, 13)).foregroundStyle(fridgeMuted)
                    Slider(value: Binding(get: { style.fontSize },
                                          set: { size in changed { $0.fontSize = size.rounded() } }),
                           in: 16...42)
                        .tint(fridgeRose)
                    Text("大").font(FridgeFont.note(style.font, 22)).foregroundStyle(fridgeMuted)
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(dark ? Color(cpHex: "#FFFBF4") : fridgeCell))
        .padding(.horizontal, dark ? 14 : 0)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(FridgeFont.cute(13)).foregroundStyle(fridgeMuted).padding(.leading, 14)
            ScrollView(.horizontal, showsIndicators: false) {
                // 上下各留 3pt：选中项的描边会画到格子外面一点，贴着滚动区高度会被削平
                HStack(spacing: 8) { content() }.padding(.horizontal, 12).padding(.vertical, 3)
            }
        }
    }

    private func chip<Preview: View>(selected: Bool, title: String, @ViewBuilder preview: () -> Preview,
                                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                preview()
                Text(title).font(FridgeFont.cute(10)).foregroundStyle(fridgeInk).lineLimit(1)
            }
            .frame(width: 64, height: 66)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected ? fridgeRose.opacity(0.16) : Color.white.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selected ? fridgeRose : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

/// 给冰箱换颜色：预设色 + 调色盘
struct FridgePaintSheet: View {
    @ObservedObject var theme: FridgeTheme
    @ObservedObject var store: FridgeStore
    @Environment(\.dismiss) private var dismiss
    @State private var custom = Color(cpHex: "#A9D9C6")

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("给冰箱换颜色").font(FridgeFont.cute(20)).foregroundStyle(fridgeInk)
                Spacer()
                Button("好了") { dismiss() }.foregroundStyle(fridgeRose).font(.system(size: 16, weight: .semibold))
            }
            HStack(spacing: 0) {
                FridgePaintedArt(name: "fridge_door_top_out", paintHex: store.paintHex)
                    .frame(width: 90, height: 71)
                    .overlay(alignment: .bottom) {
                        FridgePaintedArt(name: "fridge_door_bottom_out", paintHex: store.paintHex)
                            .frame(width: 90, height: 126)
                            .offset(y: 126)
                    }
                    .frame(height: 197, alignment: .top)
            }
            .shadow(color: Color(cpHex: "#7A5A3A").opacity(0.2), radius: 10, y: 6)
            .animation(.easeInOut(duration: 0.25), value: store.paintHex)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                ForEach(FridgePaint.presets) { preset in
                    Button { store.setPaint(preset.hex) } label: {
                        VStack(spacing: 5) {
                            Circle()
                                .fill(Color(cpHex: preset.hex ?? "#F3E3BE"))
                                .frame(width: 40, height: 40)
                                .overlay(Circle().stroke(store.paintHex == preset.hex ? fridgeRose : Color.white,
                                                         lineWidth: store.paintHex == preset.hex ? 3 : 2))
                                .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
                            Text(preset.name).font(FridgeFont.cute(12)).foregroundStyle(fridgeInk)
                        }
                    }
                    .buttonStyle(.plain)
                }
                VStack(spacing: 5) {
                    ColorPicker("", selection: $custom, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 40, height: 40)
                    Text("自己调").font(FridgeFont.cute(12)).foregroundStyle(fridgeInk)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .background(fridgePaper.ignoresSafeArea())
        .fridgeDismissKeyboardOnTap()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onChange(of: custom) { store.setPaint(FridgePaint.hex($0)) }
    }
}

/// 冰箱专用的拍照器（饭饭作业那个是 private 的）
struct FridgeCameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: FridgeCameraPicker
        init(parent: FridgeCameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onCapture(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - 贴照片

/// 贴照片：照片抠图贴 / 拍立得 / 人生四格
struct FridgeMagnetSheet: View {
    @ObservedObject var theme: FridgeTheme
    @ObservedObject var store: FridgeStore
    @Environment(\.dismiss) private var dismiss

    /// 选完拍立得 / 四格的照片先进编辑页
    @State private var editorDraft: FridgeMagnet?
    @State private var photoItem: PhotosPickerItem?
    @State private var polaroidItem: PhotosPickerItem?
    @State private var stripItems: [PhotosPickerItem] = []
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("贴照片").font(FridgeFont.cute(20)).foregroundStyle(fridgeInk)
                Spacer()
                Button("好了") { dismiss() }.foregroundStyle(fridgeRose).font(.system(size: 16, weight: .semibold))
            }
            ScrollView(showsIndicators: false) {
                photoPanel
            }
        }
        .padding(22)
        .background(fridgePaper.ignoresSafeArea())
        .fridgeDismissKeyboardOnTap()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .overlay {
            if busy {
                ProgressView().controlSize(.large)
                    .padding(26)
                    .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
            }
        }
        .fullScreenCover(item: $editorDraft) { draft in
            FridgePhotoFrameEditor(magnet: draft, isNew: true) { finished in
                store.addMagnet(finished)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            }
        }
        .onChange(of: photoItem) { item in
            guard let item else { return }
            load([item]) { images in makePhotoSticker(images[0]) }
            photoItem = nil
        }
        .onChange(of: polaroidItem) { item in
            guard let item else { return }
            load([item]) { images in openEditor(images, style: .polaroid) }
            polaroidItem = nil
        }
        .onChange(of: stripItems) { items in
            guard !items.isEmpty else { return }
            load(items) { images in openEditor(images, style: .strip) }
            stripItems = []
        }
    }

    private func add(_ action: () -> Void) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        action()
        dismiss()
    }

    private var stripDate: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd"
        return f.string(from: Date())
    }

    private var photoPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                photoRow("照片冰箱贴", detail: "自动把主体抠出来，做成带白边的贴", icon: "scissors")
            }
            .buttonStyle(.plain)

            PhotosPicker(selection: $polaroidItem, matching: .images) {
                photoRow("拍立得", detail: "一张照片，选完能换框、写字、挪构图", icon: "photo")
            }
            .buttonStyle(.plain)
            PhotosPicker(selection: $stripItems, maxSelectionCount: 4, matching: .images) {
                photoRow("人生四格", detail: "选 1 到 4 张，竖着排成一条，选完能逐格调", icon: "rectangle.split.1x2")
            }
            .buttonStyle(.plain)

            if let error {
                Text(error).font(FridgeFont.cute(13)).foregroundStyle(fridgeRose)
            }
        }
    }

    private func photoRow(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(fridgeRose)
                .frame(width: 40, height: 40)
                .background(Circle().fill(fridgeRose.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(FridgeFont.cute(16)).foregroundStyle(fridgeInk)
                Text(detail).font(.system(size: 12)).foregroundStyle(fridgeInk.opacity(0.6))
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(fridgeInk.opacity(0.35))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.75)))
    }

    private func load(_ items: [PhotosPickerItem], then: @escaping ([UIImage]) -> Void) {
        error = nil
        busy = true
        Task {
            var images: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            if images.isEmpty {
                error = "照片没读出来，再选一次试试"
                busy = false
            } else {
                then(images)
            }
        }
    }

    private func openEditor(_ images: [UIImage], style: FridgeMagnet.Style) {
        var names = images.prefix(4).compactMap { FridgeArt.savePhoto($0) }
        busy = false
        guard !names.isEmpty else { error = "照片存不下来，再试一次"; return }
        // 四格固定 4 个位置，没选满的留空格，编辑页里点空格再补
        if style == .strip { names += Array(repeating: "", count: 4 - names.count) }
        editorDraft = FridgeMagnet(style: style, text: style == .strip ? stripDate : "",
                                   hex: FridgeMagnetCatalog.frames[0].hex, x: 0, y: 0, images: names)
    }

    /// 先抠主体；抠不出来（模拟器 / 没认出主体）就退回圆角方块 + 奶白边
    private func makePhotoSticker(_ image: UIImage) {
        Task {
            let sticker = (try? await FridgePhotoCutout.makeSticker(from: image)) ?? Self.roundedSticker(image)
            busy = false
            guard let name = FridgeArt.savePhotoSticker(sticker) else { error = "照片存不下来，再试一次"; return }
            add { store.addMagnet(style: .photo, text: "", hex: "#FFFFFF", images: [name]) }
        }
    }

    static func roundedSticker(_ source: UIImage) -> UIImage {
        let side: CGFloat = 512
        let border: CGFloat = 18
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let outer = CGRect(x: 0, y: 0, width: side, height: side)
            UIColor(Color(cpHex: "#FFF8EE")).setFill()
            UIBezierPath(roundedRect: outer, cornerRadius: 70).fill()
            let inner = outer.insetBy(dx: border, dy: border)
            UIBezierPath(roundedRect: inner, cornerRadius: 56).addClip()
            // 居中裁成正方形（用 image.size，竖图不会压扁）
            let scale = max(inner.width / source.size.width, inner.height / source.size.height)
            let drawn = CGSize(width: source.size.width * scale, height: source.size.height * scale)
            source.draw(in: CGRect(x: inner.midX - drawn.width / 2, y: inner.midY - drawn.height / 2,
                                   width: drawn.width, height: drawn.height))
        }
    }
}

/// 拍立得 / 四格编辑页：换照片、在框里拖动和捏合调构图、换相框颜色、改底下那行字。
/// 贴之前（isNew）和门上点铅笔进来都用它
struct FridgePhotoFrameEditor: View {
    let isNew: Bool
    let onSave: (FridgeMagnet) -> Void
    private let original: FridgeMagnet
    @Environment(\.dismiss) private var dismiss
    @State private var draft: FridgeMagnet
    @State private var active = 0
    /// 这次编辑里新存的照片文件：取消时删掉，保存时删掉被换下来的
    @State private var created: Set<String>
    @State private var pickerOpen = false
    @State private var pickItem: PhotosPickerItem?
    @State private var busy = false

    init(magnet: FridgeMagnet, isNew: Bool, onSave: @escaping (FridgeMagnet) -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        original = magnet
        _draft = State(initialValue: magnet)
        // 新建时一开始选的照片也算这次新存的，取消要一起删
        _created = State(initialValue: isNew ? Set((magnet.images ?? []).filter { !$0.isEmpty }) : [])
    }

    private var slots: Int { draft.style == .strip ? 4 : 1 }

    private func name(at index: Int) -> String {
        let names = draft.images ?? []
        return names.indices.contains(index) ? names[index] : ""
    }

    private var activeHasPhoto: Bool { !name(at: active).isEmpty }

    /// 不带缩放时的外框尺寸（跟 FridgeMagnetView 里的排版一致）
    private var baseSize: CGSize {
        draft.style == .strip ? CGSize(width: 118, height: 361) : CGSize(width: 196, height: 232)
    }

    /// 场景根把安全区和键盘都忽略掉了，这页拿不到系统给的避让：自己量窗口的安全区、自己听键盘高度
    @State private var keyboard: CGFloat = 0
    @FocusState private var captionFocused: Bool

    private static var windowInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)?.safeAreaInsets ?? .zero
    }

    var body: some View {
        GeometryReader { geo in
            editorBody(frame: geo.frame(in: .global))
        }
        .ignoresSafeArea()
    }

    /// 按这一页在屏幕上的真实位置补：顶上被灵动岛挡多少补多少；键盘挡住底部多少让多少。
    /// 从不同入口打开时系统有时自己会给键盘让位、有时不会，按实际位置算两种都对
    private func editorBody(frame: CGRect) -> some View {
        let insets = Self.windowInsets
        // 只有系统把整页往上推（minY < 0）、或者键盘起来时才按位置算；平时和收起滑走的过程里用固定安全区——
        // 滑走时 frame 一直往下走，按位置算会把底边距越补越大，把按钮顶出背景浮在冰箱上
        let topPad = insets.top + max(0, -frame.minY)
        let keyboardTop = UIScreen.main.bounds.height - keyboard
        let bottomPad = keyboard > 0 ? max(insets.bottom, frame.maxY - keyboardTop) : insets.bottom
        return VStack(spacing: 0) {
            HStack {
                Button("取消") { cancel() }
                    .font(.system(size: 16)).foregroundStyle(fridgeInk.opacity(0.7))
                Spacer()
                Text(draft.style == .strip ? "人生四格" : "拍立得").font(FridgeFont.cute(18)).foregroundStyle(fridgeInk)
                Spacer()
                Button(isNew ? "贴上去" : "保存") { save() }
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(fridgeRose)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            .padding(.top, topPad)

            GeometryReader { geo in
                if draft.style == .strip {
                    stripCanvas(geo.size)
                } else {
                    let k = min(geo.size.width * 0.8 / baseSize.width, geo.size.height * 0.88 / baseSize.height)
                    FridgeMagnetView(magnet: draft, size: k,
                                     editing: .init(active: active, showsSelection: false,
                                                    onSelect: select,
                                                    onCrop: { index, change in setCrop(index, change(draft.crop(index))) }))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(cpHex: "#F1E6D8"))
            .clipped()

            VStack(spacing: 14) {
                Text(slots > 1 ? "点一格选中 · 拖动挪位置 · 两指缩放、旋转" : "拖动挪位置 · 两指缩放、旋转")
                    .font(FridgeFont.cute(13)).foregroundStyle(fridgeInk.opacity(0.6))
                HStack(spacing: 8) {
                    actionButton(activeHasPhoto ? "换这张" : "加一张", icon: "photo") { pickerOpen = true }
                    actionButton("转 90°", icon: "rotate.right") {
                        var crop = draft.crop(active)
                        crop.rot += 90
                        withAnimation(.easeOut(duration: 0.2)) { setCrop(active, crop) }
                    }
                    .disabled(!activeHasPhoto)
                    .opacity(activeHasPhoto ? 1 : 0.4)
                    actionButton("摆正", icon: "arrow.counterclockwise") {
                        withAnimation(.easeOut(duration: 0.2)) { setCrop(active, FridgeCrop()) }
                    }
                    .disabled(!activeHasPhoto)
                    .opacity(activeHasPhoto ? 1 : 0.4)
                }
                // 顶上压的东西
                HStack(spacing: 8) {
                    ForEach(FridgeMagnetCatalog.pins, id: \.key) { pin in
                        let on = (draft.pin ?? "pink") == pin.key
                        Button { draft.pin = pin.key } label: {
                            VStack(spacing: 3) {
                                pinSwatch(pin.key)
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(Color.white))
                                    .overlay(Circle().stroke(on ? fridgeRose : Color(cpHex: "#E6D3BF"), lineWidth: on ? 2.5 : 1))
                                Text(pin.name).font(FridgeFont.cute(10)).foregroundStyle(fridgeInk)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 12) {
                    ForEach(FridgeMagnetCatalog.frames, id: \.hex) { frame in
                        Button { draft.hex = frame.hex } label: {
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(cpHex: frame.hex))
                                    .frame(width: 32, height: 32)
                                    .overlay(RoundedRectangle(cornerRadius: 6)
                                        .stroke(draft.hex == frame.hex ? fridgeRose : Color(cpHex: "#E6D3BF"),
                                                lineWidth: draft.hex == frame.hex ? 3 : 1))
                                Text(frame.name).font(FridgeFont.cute(11)).foregroundStyle(fridgeInk)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 8) {
                    TextField(draft.style == .strip ? "底下印的字（默认是日期）" : "底下写一句（可不填）", text: $draft.text)
                        .font(FridgeFont.cute(15))
                        .focused($captionFocused)
                        .submitLabel(.done)
                        .onSubmit { captionFocused = false }
                        .padding(.horizontal, 14).frame(height: 42)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                    if keyboard > 0 {
                        Button("完成") { captionFocused = false }
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(fridgeRose)
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 14)
            // 底部：键盘起来就让到键盘上面，没键盘就让开 Home 条
            .padding(.bottom, bottomPad + 10)
        }
        .frame(width: frame.width, height: frame.height)
        .background(fridgePaper)
        .fridgeDismissKeyboardOnTap()
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let overlap = max(0, UIScreen.main.bounds.height - end.minY)
            withAnimation(.easeOut(duration: 0.25)) { keyboard = overlap }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) { keyboard = 0 }
        }
        .overlay {
            if busy {
                ProgressView().controlSize(.large)
                    .padding(26)
                    .background(RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial))
            }
        }
        .photosPicker(isPresented: $pickerOpen, selection: $pickItem, matching: .images)
        .onChange(of: pickItem) { item in
            guard let item else { return }
            busy = true
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
                   let saved = FridgeArt.savePhoto(image) {
                    replace(active, with: saved)
                }
                busy = false
                pickItem = nil
            }
        }
    }

    /// 四格：左边一条小的四格用来点选，右边把选中那格放大来调。
    /// 构图按格子比例存，大图里调完小图和门上那张一起变
    private func stripCanvas(_ size: CGSize) -> some View {
        let miniK = size.height * 0.86 / baseSize.height
        let miniW = baseSize.width * miniK
        let bigW = min(size.width - miniW - 48, (size.height * 0.8) / 0.75)
        let bigH = bigW * 0.75
        let names = draft.images ?? []
        let name = names.indices.contains(active) ? names[active] : ""
        return HStack(spacing: 16) {
            FridgeMagnetView(magnet: draft, size: miniK)
                .overlay(alignment: .topLeading) {
                    // 四个点按区，位置跟 FridgeMagnetView 里的四格排版一致
                    ForEach(0..<4, id: \.self) { index in
                        Rectangle()
                            .strokeBorder(index == active ? Color.white : Color.clear,
                                          style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                            .shadow(color: .black.opacity(index == active ? 0.35 : 0), radius: 1.5)
                            .contentShape(Rectangle())
                            .frame(width: 100 * miniK, height: 75 * miniK)
                            .offset(x: 9 * miniK, y: 9 * miniK + CGFloat(index) * 82 * miniK)
                            .onTapGesture { select(index) }
                    }
                }
            VStack(spacing: 10) {
                FridgePhotoCell(image: FridgeArt.photo(name), crop: draft.crop(active), index: active,
                                width: bigW, height: bigH,
                                editing: .init(active: active, showsSelection: false,
                                               onSelect: select,
                                               onCrop: { index, change in setCrop(index, change(draft.crop(index))) }))
                    .padding(10 * bigW / 240)
                    .background(Color(cpHex: draft.hex))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 4)
                Text("第 \(active + 1) 格").font(FridgeFont.cute(13)).foregroundStyle(fridgeInk.opacity(0.6))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder private func pinSwatch(_ key: String) -> some View {
        switch key {
        case "tape":
            Rectangle().fill(Color(cpHex: "#E9E1D6")).frame(width: 22, height: 8).rotationEffect(.degrees(-8))
        case "none":
            Image(systemName: "nosign").font(.system(size: 13)).foregroundStyle(fridgeInk.opacity(0.45))
        default:
            let colors = FridgeMagnetCatalog.pinColors(key)
            Circle().fill(RadialGradient(colors: [colors.0, colors.1], center: .init(x: 0.35, y: 0.3),
                                         startRadius: 1, endRadius: 11))
                .frame(width: 18, height: 18)
        }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(title).font(FridgeFont.cute(15))
            }
            .foregroundStyle(fridgeInk)
            .padding(.horizontal, 13).frame(height: 40)
            .background(Capsule().fill(Color.white))
            .overlay(Capsule().stroke(Color(cpHex: "#E6D3BF"), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// 点空格直接去相册挑
    private func select(_ index: Int) {
        active = index
        if name(at: index).isEmpty { pickerOpen = true }
    }

    private func setCrop(_ index: Int, _ crop: FridgeCrop) {
        var crops = draft.crops ?? []
        while crops.count < slots { crops.append(FridgeCrop()) }
        crops[index] = crop
        draft.crops = crops
    }

    private func replace(_ index: Int, with saved: String) {
        var names = draft.images ?? []
        while names.count < slots { names.append("") }
        let old = names[index]
        names[index] = saved
        draft.images = names
        created.insert(saved)
        // 这次编辑里刚存又被换掉的直接删；原来就有的等保存时再删（取消还要还原）
        if created.contains(old) {
            FridgeArt.deletePhoto(old)
            created.remove(old)
        }
        setCrop(index, FridgeCrop())
    }

    private func cancel() {
        for saved in created { FridgeArt.deletePhoto(saved) }
        dismiss()
    }

    private func save() {
        if !isNew {
            let kept = Set(draft.images ?? [])
            for old in Set(original.images ?? []).subtracting(kept) where !old.isEmpty {
                FridgeArt.deletePhoto(old)
            }
        }
        onSave(draft)
        dismiss()
    }
}
