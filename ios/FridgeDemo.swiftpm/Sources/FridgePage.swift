import SwiftUI
import UIKit

// MARK: - 冰箱页
//
// 整台冰箱是一块 941×1672 的「舞台」（开门图原图坐标），分层叠：
//   箱体内胆 → 内胆里的贴纸 → 门内侧（含门架贴纸）→ 门外侧（含便签和快到期提醒）
// 开门 = 门外侧绕右边合页转到 90°，再换门内侧从 90° 转平；同时镜头从「只看箱体」推到「箱体+门」。
// 点某一层 = 镜头推近那一层，底下浮出这一层的全部贴纸（名字 + 到期）。
// 1029 二版：开门图换成去掉把手的版本；点空白关门；贴上/揭下动画；便签居中大图 + 多样式；漆面换色。

enum FridgeCanvas {
    static let size = CGSize(width: 941, height: 1672)
    static let body = CGRect(x: 30, y: 230, width: 551, height: 1240)
    static let doorTopOut = CGRect(x: 37, y: 237, width: 541, height: 428)
    static let doorBottomOut = CGRect(x: 37, y: 665, width: 541, height: 757)
    static let doorTopIn = CGRect(x: 578, y: 180, width: 338, height: 488)
    static let doorBottomIn = CGRect(x: 548, y: 665, width: 368, height: 865)
    /// 门外侧整面（便签、提醒贴纸的归一化坐标基准）
    static let front = CGRect(x: 37, y: 237, width: 541, height: 1185)
    static let hingeX: CGFloat = 578
    static let openFrame = CGRect(x: 30, y: 180, width: 886, height: 1350)
    /// 两个内腔，关门时压暗、开门亮灯
    static let cavities = [CGRect(x: 70, y: 318, width: 498, height: 342),
                           CGRect(x: 70, y: 693, width: 498, height: 699)]
}

struct FridgePageView: View {
    @ObservedObject var theme: FridgeTheme
    var safeAreaTop: CGFloat = 0
    var safeAreaBottom: CGFloat = 0
    @State private var settingsOpen = false

    @ObservedObject private var store = FridgeStore.shared
    @State private var isOpen = false
    @State private var progress: CGFloat = 0
    @State private var focusedZone: FridgeZone?
    @State private var detailItem: FridgeItem?
    @State private var editorTarget: FridgeEditorTarget?
    @State private var composingNote = false
    @State private var paintOpen = false
    @State private var magnetSheetOpen = false
    @State private var confirmClear = false
    /// 门上选中的照片（显示 ×）
    @State private var selectedMagnet: String?
    /// 门上点铅笔进编辑页的那张拍立得 / 四格
    @State private var editingMagnet: FridgeMagnet?
    /// 正在用把手转的那张：起手时手指的角度、照片原来的角度、现在的角度
    @State private var turning: (id: String, startAngle: Double, startTilt: Double, tilt: Double)?
    @State private var peeling: [String: CGFloat] = [:]
    @State private var landing: [String: CGFloat] = [:]
    @State private var dragging: (id: String, delta: CGSize)?
    @State private var toast: String?
    @State private var viewport: CGRect = .zero
    // 居中查看的便签
    @State private var bigNote: FridgeNote?
    @State private var bigNoteShown = false
    @State private var bigNotePeel: CGFloat = 0
    /// 大便签下面展开的面板：换样式 / 加贴纸
    @State private var bigNotePanel: BigNotePanel?

    var body: some View {
        ZStack {
            backdrop.ignoresSafeArea()
            VStack(spacing: 0) {
                FridgeTopBar(theme: theme, title: "我们的冰箱", sub: "FRIDGE") {
                    Button { settingsOpen = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.textSub)
                            .frame(width: 36, height: 36)
                    }
                    Menu {
                        Button { paintOpen = true } label: { Label("给冰箱换颜色", systemImage: "paintpalette") }
                        Toggle(isOn: Binding(get: { store.showDoorReminders },
                                             set: { on in withAnimation(.easeOut(duration: 0.25)) { store.setShowDoorReminders(on) } })) {
                            Label("门上贴快到期的", systemImage: "clock.badge.exclamationmark")
                        }
                        Button(role: .destructive) { confirmClear = true } label: { Label("清空冰箱", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.textSub)
                            .frame(width: 36, height: 36)
                    }
                }
                GeometryReader { geo in
                    stageViewport(geo.size)
                        .onAppear { viewport = geo.frame(in: .named("fridgeRoot")) }
                        .onChange(of: geo.frame(in: .named("fridgeRoot"))) { viewport = $0 }
                }
                controls
                    .padding(.bottom, max(safeAreaBottom, 12) + 6)
                    .opacity(focusedZone == nil ? 1 : 0)
            }

            if let zone = focusedZone {
                VStack {
                    Spacer()
                    FridgeZoneCard(theme: theme, zone: zone, items: store.items(in: zone),
                                   peeling: peeling, landing: landing, bottomInset: safeAreaBottom,
                                   onPick: { detailItem = $0 },
                                   onAdd: { editorTarget = FridgeEditorTarget(item: nil, zone: zone) },
                                   onClose: { setFocus(nil) })
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            }

            if let note = bigNote { bigNoteOverlay(note).zIndex(4) }

            if let toast {
                Text(toast)
                    .font(FridgeFont.cute(15))
                    .foregroundStyle(theme.textMain)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Capsule().fill(theme.surface))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, safeAreaBottom + 96)
                    .transition(.opacity)
                    .zIndex(5)
            }
        }
        .coordinateSpace(name: "fridgeRoot")
        .onAppear(perform: applyDebugLaunch)
        .sheet(item: $detailItem) { item in
            FridgeItemSheet(theme: theme, item: item,
                            onEat: { eat(item) },
                            onEdit: { later(0.45) { editorTarget = FridgeEditorTarget(item: item, zone: nil) } },
                            onRemove: { peelOff(item, toast: nil) })
                .environment(\.colorScheme, theme.effectiveDark ? .dark : .light)
        }
        .sheet(item: $editorTarget) { target in
            FridgeEditorSheet(theme: theme, target: target) { saved in
                if target.item == nil { stickOn(saved) } else { store.update(saved) }
            }
            .environment(\.colorScheme, theme.effectiveDark ? .dark : .light)
        }
        .sheet(isPresented: $composingNote) {
            FridgeNoteComposer(theme: theme) { text, style in
                store.addNote(text, author: .me, style: style)
            }
            .environment(\.colorScheme, theme.effectiveDark ? .dark : .light)
        }
        .fullScreenCover(item: $editingMagnet) { magnet in
            FridgePhotoFrameEditor(magnet: magnet, isNew: false) { edited in
                withAnimation(.easeOut(duration: 0.2)) { store.updateMagnet(edited) }
            }
        }
        .alert("清空冰箱？", isPresented: $confirmClear) {
            Button("清空", role: .destructive) {
                if focusedZone != nil { setFocus(nil) }
                withAnimation(.easeOut(duration: 0.25)) { store.clearAll() }
                showToast("冰箱清空啦")
            }
            Button("算了", role: .cancel) {}
        } message: {
            Text("里面的东西、门上的便签和照片都会拿掉，同步的话 TA 那边也会看到空冰箱。")
        }
        .sheet(isPresented: $magnetSheetOpen) {
            FridgeMagnetSheet(theme: theme, store: store)
                .environment(\.colorScheme, theme.effectiveDark ? .dark : .light)
        }
        .sheet(isPresented: $settingsOpen) {
            FridgeSyncSettingsSheet(store: store)
        }
        .sheet(isPresented: $paintOpen) {
            FridgePaintSheet(theme: theme, store: store)
                .environment(\.colorScheme, theme.effectiveDark ? .dark : .light)
        }
    }

    // MARK: 背景：奶油色墙面 + 一点地板

    private var backdrop: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(cpHex: "#FBF4EA"), Color(cpHex: "#F4E7D8")],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [Color(cpHex: "#E9D6C2").opacity(0), Color(cpHex: "#E3CDB6")],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 220)
        }
    }

    // MARK: 舞台

    private func stageViewport(_ size: CGSize) -> some View {
        let cam = camera(in: size)
        return Color.clear
            .overlay {
                stage
                    .frame(width: FridgeCanvas.size.width, height: FridgeCanvas.size.height)
                    .scaleEffect(cam.scale)
                    .offset(cam.offset)
            }
            // 镜头推近时舞台会比视口大很多：只裁上边别盖住顶栏；下边放开，地上的影子能自然淡进按钮区
            .mask(alignment: .top) {
                Rectangle().padding(.bottom, -400)
            }
            .contentShape(Rectangle())
            // 空白处：先收起放大的那一层，再点才关门
            .onTapGesture {
                if focusedZone != nil { setFocus(nil) } else if isOpen { toggleDoor() }
            }
    }

    /// 镜头：关门只框箱体，开门框住箱体+两扇门，聚焦某层时推近那一层放在上半屏
    private func camera(in size: CGSize) -> (scale: CGFloat, offset: CGSize) {
        guard size.width > 0, size.height > 0 else { return (0.4, .zero) }
        let canvasCenter = CGPoint(x: FridgeCanvas.size.width / 2, y: FridgeCanvas.size.height / 2)
        let target: CGRect
        let anchor: CGPoint
        let scale: CGFloat
        if let zone = focusedZone {
            target = zone.rect.insetBy(dx: -36, dy: -54)
            scale = min(size.width * 0.94 / target.width, size.height * 0.36 / target.height)
            anchor = CGPoint(x: size.width / 2, y: size.height * 0.22)
        } else {
            target = isOpen ? FridgeCanvas.openFrame : FridgeCanvas.body
            scale = min(size.width * (isOpen ? 0.96 : 0.74) / target.width, size.height * 0.95 / target.height)
            anchor = CGPoint(x: size.width / 2, y: size.height / 2)
        }
        let mapped = CGSize(width: (target.midX - canvasCenter.x) * scale,
                            height: (target.midY - canvasCenter.y) * scale)
        return (scale, CGSize(width: anchor.x - size.width / 2 - mapped.width,
                              height: anchor.y - size.height / 2 - mapped.height))
    }

    /// 舞台坐标 → 根坐标（居中便签从门上飞出来时要知道它在屏幕哪）
    private func screenPoint(_ point: CGPoint) -> CGPoint {
        let cam = camera(in: viewport.size)
        return CGPoint(x: viewport.midX + cam.offset.width + (point.x - FridgeCanvas.size.width / 2) * cam.scale,
                       y: viewport.midY + cam.offset.height + (point.y - FridgeCanvas.size.height / 2) * cam.scale)
    }

    private var currentScale: CGFloat { camera(in: viewport.size).scale }

    private var stage: some View {
        ZStack(alignment: .topLeading) {
            // 地上的影子跟着镜头一起挪
            Ellipse()
                .fill(Color(cpHex: "#7A5A3A").opacity(0.22))
                .frame(width: isOpen ? 880 : 600, height: 56)
                .blur(radius: 22)
                .position(x: isOpen ? 470 : 306, y: 1466)
                .allowsHitTesting(false)

            bodyLayer
            innerDoorLayer
                .modifier(FridgeDoorSwing(progress: progress, inner: true))
                .allowsHitTesting(isOpen)
            frontDoorLayer
                .modifier(FridgeDoorSwing(progress: progress, inner: false))
                .allowsHitTesting(!isOpen)
            // 开门后两扇门内侧整片都是门架点按区（门架之间的空处也算最近那层），以前漏到空白处会关门
            openDoorHitLayer
                .allowsHitTesting(isOpen && focusedZone == nil)
        }
    }

    private var bodyLayer: some View {
        ZStack(alignment: .topLeading) {
            FridgePaintedArt(name: "fridge_body", paintHex: store.paintHex)
                .frame(width: FridgeCanvas.body.width, height: FridgeCanvas.body.height)
                .mask(alignment: .topLeading) { closedBodyMask }
                .position(x: FridgeCanvas.body.midX, y: FridgeCanvas.body.midY)
            ForEach(Array(FridgeCanvas.cavities.enumerated()), id: \.offset) { _, rect in
                Rectangle()
                    .fill(Color(cpHex: "#2A2018").opacity(0.42 * (1 - progress)))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
            }
            // 内胆整块吞点击：冷冻室以玻璃隔板为界分上下层，冷藏隔板之间的缝点了也不会当成空白处关门
            ForEach(freezerBands, id: \.0) { zone, rect in
                Color.clear
                    .frame(width: rect.width, height: rect.height)
                    .contentShape(Rectangle())
                    .position(x: rect.midX, y: rect.midY)
                    .onTapGesture { setFocus(zone) }
            }
            Color.clear
                .frame(width: FridgeCanvas.cavities[1].width, height: FridgeCanvas.cavities[1].height)
                .contentShape(Rectangle())
                .position(x: FridgeCanvas.cavities[1].midX, y: FridgeCanvas.cavities[1].midY)
                .onTapGesture {}
            ForEach([FridgeZone.freezerTop, .freezer, .chillTop, .chillMid, .chillLow, .crisper]) { zone in
                zoneLayer(zone)
            }
        }
        .frame(width: FridgeCanvas.size.width, height: FridgeCanvas.size.height, alignment: .topLeading)
    }

    /// 箱体图比门外侧大一圈（上 7、右 3），关着门时那圈边会从门的圆角后面露出来。
    /// 门完全关上时只按两扇门的形状 + 门下面的底座显示箱体；门一动就整张放开
    @ViewBuilder private var closedBodyMask: some View {
        if progress > 0 {
            Color.black
        } else {
            ZStack(alignment: .topLeading) {
                ForEach([("fridge_door_top_out", FridgeCanvas.doorTopOut),
                         ("fridge_door_bottom_out", FridgeCanvas.doorBottomOut)], id: \.0) { name, rect in
                    if let image = FridgeArt.image(name) {
                        Image(uiImage: image).resizable()
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX - FridgeCanvas.body.minX, y: rect.minY - FridgeCanvas.body.minY)
                    }
                }
                Rectangle()
                    .frame(width: FridgeCanvas.body.width, height: FridgeCanvas.body.maxY - FridgeCanvas.doorBottomOut.maxY + 8)
                    .offset(y: FridgeCanvas.doorBottomOut.maxY - 8 - FridgeCanvas.body.minY)
            }
            .frame(width: FridgeCanvas.body.width, height: FridgeCanvas.body.height, alignment: .topLeading)
        }
    }

    private var innerDoorLayer: some View {
        ZStack(alignment: .topLeading) {
            art("fridge_door_top_in", FridgeCanvas.doorTopIn)
            art("fridge_door_bottom_in", FridgeCanvas.doorBottomIn)
            ForEach([FridgeZone.freezerDoor, .freezerDoorLow, .doorTop, .doorMid, .doorLow]) { zone in
                zoneLayer(zone)
            }
        }
        .frame(width: FridgeCanvas.size.width, height: FridgeCanvas.size.height, alignment: .topLeading)
    }

    private var frontDoorLayer: some View {
        ZStack(alignment: .topLeading) {
            art("fridge_door_top_out", FridgeCanvas.doorTopOut)
                .onTapGesture { tapFrontDoor() }
            art("fridge_door_bottom_out", FridgeCanvas.doorBottomOut)
                .onTapGesture { tapFrontDoor() }
            ForEach(Array(store.doorReminders.enumerated()), id: \.element.id) { index, item in
                doorReminder(item, index: index)
            }
            ForEach(store.notes) { note in
                doorNote(note)
            }
            ForEach(store.magnets) { magnet in
                doorMagnet(magnet)
            }
        }
        .frame(width: FridgeCanvas.size.width, height: FridgeCanvas.size.height, alignment: .topLeading)
    }

    /// 冷冻室内胆按两层中线切成上下两块
    private var freezerBands: [(FridgeZone, CGRect)] {
        let cavity = FridgeCanvas.cavities[0]
        let cut = (FridgeZone.freezerTop.rect.maxY + FridgeZone.freezer.rect.minY) / 2
        return [
            (.freezerTop, CGRect(x: cavity.minX, y: cavity.minY, width: cavity.width, height: cut - cavity.minY)),
            (.freezer, CGRect(x: cavity.minX, y: cut, width: cavity.width, height: cavity.maxY - cut)),
        ]
    }

    /// 两扇门内侧都以相邻两层门架的中线为界分段，整扇都能点
    private var openDoorHitLayer: some View {
        let top = FridgeCanvas.doorTopIn
        let bottom = FridgeCanvas.doorBottomIn
        let cut0 = (FridgeZone.freezerDoor.rect.maxY + FridgeZone.freezerDoorLow.rect.minY) / 2
        let cut1 = (FridgeZone.doorTop.rect.maxY + FridgeZone.doorMid.rect.minY) / 2
        let cut2 = (FridgeZone.doorMid.rect.maxY + FridgeZone.doorLow.rect.minY) / 2
        let bands: [(FridgeZone, CGRect)] = [
            (.freezerDoor, CGRect(x: top.minX, y: top.minY, width: top.width, height: cut0 - top.minY)),
            (.freezerDoorLow, CGRect(x: top.minX, y: cut0, width: top.width, height: top.maxY - cut0)),
            (.doorTop, CGRect(x: bottom.minX, y: bottom.minY, width: bottom.width, height: cut1 - bottom.minY)),
            (.doorMid, CGRect(x: bottom.minX, y: cut1, width: bottom.width, height: cut2 - cut1)),
            (.doorLow, CGRect(x: bottom.minX, y: cut2, width: bottom.width, height: bottom.maxY - cut2)),
        ]
        return ZStack(alignment: .topLeading) {
            ForEach(bands, id: \.0) { zone, rect in
                Color.clear
                    .frame(width: rect.width, height: rect.height)
                    .contentShape(Rectangle())
                    .position(x: rect.midX, y: rect.midY)
                    .onTapGesture { setFocus(zone) }
            }
        }
        .frame(width: FridgeCanvas.size.width, height: FridgeCanvas.size.height, alignment: .topLeading)
    }

    private func art(_ name: String, _ rect: CGRect) -> some View {
        FridgePaintedArt(name: name, paintHex: store.paintHex)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    // MARK: 分区：最多 4 张代表贴纸，多的叠起来 +N

    private func zoneLayer(_ zone: FridgeZone) -> some View {
        let list = store.items(in: zone)
        let shown = Array(list.prefix(list.count > 4 ? 3 : 4))
        let rest = Array(list.dropFirst(shown.count))
        let slots = max(shown.count + (rest.isEmpty ? 0 : 1), 1)
        let rect = zone.rect
        // 10-30 真机上贴纸好小、又忽大忽小：所有层统一一个大小，只有这一层挤不下时才缩
        let side = min(124, rect.width / CGFloat(slots) * 1.18)
        let slotWidth = rect.width / CGFloat(slots)
        return ZStack(alignment: .topLeading) {
            // 整格都是点按区，空格也能点进去放东西；放在贴纸下面，贴纸本身不拦点击
            Color.clear
                .frame(width: rect.width + 20, height: rect.height + 30)
                .contentShape(Rectangle())
                .position(x: rect.midX, y: rect.midY - 6)
                .onTapGesture { setFocus(zone) }
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                FridgeSticker(item: item, peel: peeling[item.id] ?? 0, land: landing[item.id], dot: true)
                    .frame(width: side, height: side)
                    .rotationEffect(.degrees(FridgeSticker.tilt(item.id)))
                    .position(x: rect.minX + slotWidth * (CGFloat(index) + 0.5), y: rect.maxY - side / 2)
                    .allowsHitTesting(false)
            }
            if !rest.isEmpty {
                ZStack {
                    ForEach(Array(rest.prefix(2).enumerated().reversed()), id: \.element.id) { index, item in
                        FridgeSticker(item: item, peel: peeling[item.id] ?? 0)
                            .frame(width: side * 0.86, height: side * 0.86)
                            .rotationEffect(.degrees(index == 0 ? -6 : 8))
                            .offset(x: CGFloat(index) * side * 0.22, y: -CGFloat(index) * side * 0.06)
                    }
                    Text("+\(rest.count)")
                        .font(FridgeFont.cute(30))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Capsule().fill(Color(cpHex: "#C98A92")))
                        .overlay(Capsule().stroke(Color.white, lineWidth: 3))
                        .offset(x: side * 0.3, y: -side * 0.36)
                }
                .frame(width: side, height: side)
                .position(x: rect.minX + slotWidth * (CGFloat(shown.count) + 0.5), y: rect.maxY - side / 2)
                .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(focusedZone == nil)
    }

    // MARK: 门外侧：快到期提醒 + 便签，都能拖

    private func frontPoint(x: Double, y: Double, id: String) -> CGPoint {
        var point = CGPoint(x: FridgeCanvas.front.minX + FridgeCanvas.front.width * x,
                            y: FridgeCanvas.front.minY + FridgeCanvas.front.height * y)
        if let dragging, dragging.id == id {
            point.x += dragging.delta.width
            point.y += dragging.delta.height
        }
        return point
    }

    private func dragGesture(id: String, x: Double, y: Double,
                             commit: @escaping (Double, Double) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                let scale = max(currentScale, 0.01)
                dragging = (id, CGSize(width: value.translation.width / scale,
                                       height: value.translation.height / scale))
            }
            .onEnded { value in
                let scale = max(currentScale, 0.01)
                let nx = x + Double(value.translation.width / scale / FridgeCanvas.front.width)
                let ny = y + Double(value.translation.height / scale / FridgeCanvas.front.height)
                commit(min(max(nx, 0.12), 0.9), min(max(ny, 0.06), 0.94))
                dragging = nil
            }
    }

    private static let reminderSpots: [(Double, Double)] = [
        (0.42, 0.50), (0.74, 0.57), (0.40, 0.70), (0.73, 0.78), (0.52, 0.88),
    ]

    private func doorReminder(_ item: FridgeItem, index: Int) -> some View {
        let spot = Self.reminderSpots[index % Self.reminderSpots.count]
        let x = item.doorX ?? spot.0
        let y = item.doorY ?? spot.1
        return FridgeDoorReminder(item: item, peel: peeling[item.id] ?? 0)
            .rotationEffect(.degrees(FridgeSticker.tilt(item.id) * 0.8))
            .position(frontPoint(x: x, y: y, id: item.id))
            .onTapGesture { detailItem = item }
            .gesture(dragGesture(id: item.id, x: x, y: y) { nx, ny in
                store.moveOnDoor(item.id, x: nx, y: ny)
            })
    }

    private func doorNote(_ note: FridgeNote) -> some View {
        FridgeNoteView(note: note)
            .rotationEffect(.degrees(note.tilt))
            .position(frontPoint(x: note.x, y: note.y, id: note.id))
            // +100：「放到最下面」是负层级，别掉到门板图（zIndex 0）后面去
            .zIndex(dragging?.id == note.id ? 10_000 : 100 + (note.z ?? 0))
            .opacity(bigNote?.id == note.id ? 0 : 1)
            .onTapGesture { openNote(note) }
            .gesture(dragGesture(id: note.id, x: note.x, y: note.y) { nx, ny in
                store.moveNote(note.id, x: nx, y: ny)
            })
    }

    /// 选着照片时点门 = 取消选中，不开门
    private func tapFrontDoor() {
        if selectedMagnet != nil {
            withAnimation(.easeOut(duration: 0.15)) { selectedMagnet = nil }
        } else {
            toggleDoor()
        }
    }

    private func doorMagnet(_ magnet: FridgeMagnet) -> some View {
        let selected = selectedMagnet == magnet.id
        // × 按屏幕上 24pt 算，舞台被镜头缩放过，要除回去
        let button = 24 / max(currentScale, 0.01)
        return FridgeMagnetView(magnet: magnet)
            .overlay(alignment: .topLeading) {
                if selected {
                    Image(systemName: "xmark")
                        .font(.system(size: button * 0.42, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: button, height: button)
                        .background(Circle().fill(Color(cpHex: "#C98A92")))
                        .overlay(Circle().stroke(Color.white, lineWidth: button * 0.09))
                        .offset(x: -button * 0.4, y: -button * 0.4)
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.easeOut(duration: 0.2)) {
                                store.removeMagnet(magnet.id)
                                selectedMagnet = nil
                            }
                        }
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(alignment: .topTrailing) {
                if selected && magnet.style != .photo {
                    Image(systemName: "pencil")
                        .font(.system(size: button * 0.42, weight: .heavy))
                        .foregroundStyle(Color(cpHex: "#6E5240"))
                        .frame(width: button, height: button)
                        .background(Circle().fill(Color.white))
                        .overlay(Circle().stroke(Color(cpHex: "#E6D3BF"), lineWidth: button * 0.06))
                        .shadow(color: .black.opacity(0.2), radius: button * 0.1, y: button * 0.05)
                        .offset(x: button * 0.4, y: -button * 0.4)
                        .onTapGesture {
                            selectedMagnet = nil
                            editingMagnet = magnet
                        }
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if selected {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: button * 0.42, weight: .heavy))
                        .foregroundStyle(Color(cpHex: "#6E5240"))
                        .frame(width: button, height: button)
                        .background(Circle().fill(Color.white))
                        .overlay(Circle().stroke(Color(cpHex: "#E6D3BF"), lineWidth: button * 0.06))
                        .shadow(color: .black.opacity(0.2), radius: button * 0.1, y: button * 0.05)
                        .offset(x: button * 0.4, y: button * 0.4)
                        .highPriorityGesture(turnGesture(magnet))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottomLeading) {
                if selected {
                    Menu {
                        Button { layer(magnet.id, toTop: true) } label: { Label("放到最上面", systemImage: "square.3.layers.3d.top.filled") }
                        Button { layer(magnet.id, toTop: false) } label: { Label("放到最下面", systemImage: "square.3.layers.3d.bottom.filled") }
                    } label: {
                        Image(systemName: "square.3.layers.3d")
                            .font(.system(size: button * 0.42, weight: .heavy))
                            .foregroundStyle(Color(cpHex: "#6E5240"))
                            .frame(width: button, height: button)
                            .background(Circle().fill(Color.white))
                            .overlay(Circle().stroke(Color(cpHex: "#E6D3BF"), lineWidth: button * 0.06))
                            .shadow(color: .black.opacity(0.2), radius: button * 0.1, y: button * 0.05)
                    }
                    .offset(x: -button * 0.4, y: button * 0.4)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .scaleEffect(selected ? 1.06 : 1)
            .rotationEffect(.degrees(turning?.id == magnet.id ? turning!.tilt : magnet.tilt))
            .position(frontPoint(x: magnet.x, y: magnet.y, id: magnet.id))
            // 选中 / 拖动时临时浮到最上面，按钮才不会被别的东西盖住
            .zIndex(selected || dragging?.id == magnet.id ? 10_000 : 100 + (magnet.z ?? 1))
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) { selectedMagnet = selected ? nil : magnet.id }
            }
            .gesture(dragGesture(id: magnet.id, x: magnet.x, y: magnet.y) { nx, ny in
                store.moveMagnet(magnet.id, x: nx, y: ny)
            })
    }

    private func layer(_ id: String, toTop: Bool) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeOut(duration: 0.2)) { store.layerDoorItem(id, toTop: toTop) }
        showToast(toTop ? "放到最上面啦" : "放到最下面啦")
    }

    /// 按住把手绕照片中心拖：转过的角度 = 手指现在的方向 − 起手时的方向（屏幕坐标里算，不受镜头缩放影响）
    private func turnGesture(_ magnet: FridgeMagnet) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("fridgeRoot"))
            .onChanged { value in
                let center = screenPoint(frontPoint(x: magnet.x, y: magnet.y, id: magnet.id))
                func angle(_ p: CGPoint) -> Double { atan2(Double(p.y - center.y), Double(p.x - center.x)) * 180 / .pi }
                if turning?.id != magnet.id {
                    turning = (magnet.id, angle(value.startLocation), magnet.tilt, magnet.tilt)
                }
                if let t = turning { turning?.tilt = t.startTilt + (angle(value.location) - t.startAngle) }
            }
            .onEnded { _ in
                if let t = turning, t.id == magnet.id { store.setMagnetTilt(magnet.id, tilt: t.tilt) }
                turning = nil
            }
    }

    // MARK: 居中看便签（不是弹窗：从门上飞到正中放大，点暗处飞回去）

    private func bigNoteOverlay(_ note: FridgeNote) -> some View {
        let live = store.notes.first { $0.id == note.id } ?? note
        let origin = screenPoint(frontPoint(x: live.x, y: live.y, id: live.id))
        let panelOpen = bigNotePanel != nil
        let center = CGPoint(x: viewport.midX,
                             y: viewport.minY + viewport.height * (bigNotePanel == .style ? 0.2 : panelOpen ? 0.27 : 0.36))
        let bigScale = min(viewport.width * 0.78 / 228, 1.5) * (bigNotePanel == .style ? 0.74 : panelOpen ? 0.88 : 1)
        // 便签大约 230×(150~220) 舞台单位；按钮排在它正下方
        let actionsTop = center.y + 120 * bigScale + 26
        return ZStack {
            Color.black.opacity(bigNoteShown ? 0.45 : 0)
                .ignoresSafeArea()
                .onTapGesture { closeNote() }
            FridgeNoteView(note: live, peel: bigNotePeel, editable: bigNoteShown,
                           onMoveDeco: { id, x, y in store.moveDeco(id, in: live.id, x: x, y: y) },
                           onRemoveDeco: { id in
                               UIImpactFeedbackGenerator(style: .light).impactOccurred()
                               withAnimation(.easeOut(duration: 0.2)) { store.removeDeco(id, in: live.id) }
                           },
                           onRotateDeco: { id, tilt in store.rotateDeco(id, in: live.id, tilt: tilt) })
                .rotationEffect(.degrees(live.tilt * (bigNoteShown ? 0.4 : 1)))
                .scaleEffect(bigNoteShown ? bigScale : currentScale)
                .position(bigNoteShown ? center : origin)

            VStack(spacing: 12) {
                Text(live.decos.isEmpty ? (live.author == .partner ? "TA 留的" : "你写的")
                                        : "拖贴纸换位置 · 点一下可以删掉、转方向")
                    .font(FridgeFont.cute(13))
                    .foregroundStyle(Color.white.opacity(0.9))
                HStack(spacing: 10) {
                    noteAction(bigNotePanel == .style ? "好啦" : "换样式", icon: "paintbrush.pointed") {
                        togglePanel(.style)
                    }
                    noteAction(bigNotePanel == .deco ? "好啦" : "贴贴纸", icon: "heart.circle") {
                        togglePanel(.deco)
                    }
                    noteAction("揭下来", icon: "hand.raised") { peelBigNote(live) }
                    Menu {
                        Button { layer(live.id, toTop: true) } label: { Label("放到最上面", systemImage: "square.3.layers.3d.top.filled") }
                        Button { layer(live.id, toTop: false) } label: { Label("放到最下面", systemImage: "square.3.layers.3d.bottom.filled") }
                    } label: {
                        Image(systemName: "square.3.layers.3d")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(cpHex: "#6E5240"))
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color(cpHex: "#FFFBF4")))
                    }
                }
                if bigNotePanel == .style {
                    FridgeNoteStylePicker(style: live.style) { style in
                        withAnimation(.easeOut(duration: 0.2)) { store.restyleNote(live.id, style: style) }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                if bigNotePanel == .deco {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(FridgeDecoKind.allCases) { kind in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        store.addDeco(kind, to: live.id)
                                    }
                                } label: {
                                    FridgeDecoGlyph(kind: kind, size: 26)
                                        .frame(width: 52, height: 52)
                                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color.white.opacity(0.75)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                    }
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(cpHex: "#FFFBF4")))
                    .padding(.horizontal, 14)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, actionsTop)
            .opacity(bigNoteShown && bigNotePeel == 0 ? 1 : 0)
        }
    }

    private func noteAction(_ title: String, icon: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(title).font(FridgeFont.cute(16)).lineLimit(1)
            }
            .fixedSize()
            .foregroundStyle(Color(cpHex: "#6E5240"))
            .padding(.horizontal, 13).frame(height: 44)
            .background(Capsule().fill(Color(cpHex: "#FFFBF4")))
        }
        .buttonStyle(.plain)
    }

    private func togglePanel(_ panel: BigNotePanel) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            bigNotePanel = bigNotePanel == panel ? nil : panel
        }
    }

    private func openNote(_ note: FridgeNote) {
        bigNotePeel = 0
        bigNotePanel = nil
        bigNoteShown = false
        bigNote = note
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        later(0.02) {
            withAnimation(.spring(response: 0.46, dampingFraction: 0.82)) { bigNoteShown = true }
        }
    }

    private func closeNote() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
            bigNoteShown = false
            bigNotePanel = nil
        }
        later(0.42) { if !bigNoteShown { bigNote = nil } }
    }

    private func peelBigNote(_ note: FridgeNote) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeOut(duration: 0.2)) { bigNotePanel = nil }
        withAnimation(.easeInOut(duration: 1.3)) { bigNotePeel = 1 }
        later(1.35) {
            store.removeNote(note.id)
            withAnimation(.easeOut(duration: 0.25)) { bigNoteShown = false }
            later(0.26) { bigNote = nil; bigNotePeel = 0 }
            showToast("便签揭下来啦")
        }
    }

    // MARK: 底部按钮

    private var controls: some View {
        VStack(spacing: 10) {
            Text(isOpen ? "点一层凑近看看 · 点空白处关门" : "点门打开 · 门上的东西可以拖")
                .font(FridgeFont.cute(13))
                .foregroundStyle(Color(cpHex: "#9C8470"))
            HStack(spacing: 12) {
                if isOpen {
                    pillButton("关门", icon: "door.left.hand.closed") { toggleDoor() }
                } else {
                    pillButton("贴便签", icon: "note.text", compact: true) { composingNote = true }
                    pillButton("贴照片", icon: "photo.on.rectangle", compact: true) { magnetSheetOpen = true }
                }
                pillButton("放进冰箱", icon: "plus", filled: true, compact: !isOpen) {
                    editorTarget = FridgeEditorTarget(item: nil, zone: nil)
                }
            }
        }
        .padding(.top, 6)
    }

    private func pillButton(_ title: String, icon: String, filled: Bool = false, compact: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(title).font(FridgeFont.cute(16))
            }
            .foregroundStyle(filled ? Color.white : Color(cpHex: "#6E5240"))
            .padding(.horizontal, compact ? 15 : 20).frame(height: 44)
            .background(Capsule().fill(filled ? Color(cpHex: "#C98A92") : Color(cpHex: "#FFFBF4")))
            .overlay(Capsule().stroke(Color(cpHex: "#E6D3BF"), lineWidth: filled ? 0 : 1))
            .shadow(color: Color(cpHex: "#8A6A4A").opacity(0.14), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: 动作

    private func toggleDoor() {
        UIImpactFeedbackGenerator(style: isOpen ? .rigid : .medium).impactOccurred()
        let opening = !isOpen
        selectedMagnet = nil
        withAnimation(opening ? .timingCurve(0.32, 0.0, 0.2, 1, duration: 0.74)
                              : .timingCurve(0.5, 0.0, 0.3, 1, duration: 0.56)) {
            isOpen = opening
            progress = opening ? 1 : 0
        }
    }

    private func setFocus(_ zone: FridgeZone?) {
        if zone != nil { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) { focusedZone = zone }
    }

    /// 放进冰箱：门关着先开门，再让新贴纸从下面飞进那一层、按下去贴平
    private func stickOn(_ item: FridgeItem) {
        later(0.4) {
            if focusedZone != nil { setFocus(nil) }
            let needsOpen = !isOpen
            if needsOpen { toggleDoor() }
            later(needsOpen ? 0.78 : 0.15) {
                landing[item.id] = 0
                store.add(item)
                later(0.02) {
                    withAnimation(.linear(duration: 0.78)) { landing[item.id] = 1 }
                }
                later(0.5) { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                later(0.85) {
                    landing[item.id] = nil
                    showToast("\(item.name)放进\(item.zone.title)啦")
                }
            }
        }
    }

    /// 吃掉：还有剩就减一份；最后一份就从角上揭起来飞走
    private func eat(_ item: FridgeItem) {
        later(0.32) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if item.quantity > 1 {
                store.consume(item.id)
                showToast("吃掉一\(item.unit)\(item.name)，还剩 \(Int(item.quantity - 1)) \(item.unit)")
                return
            }
            peelOff(item, toast: "\(item.name)吃光光啦", delay: 0)
        }
    }

    private func peelOff(_ item: FridgeItem, toast message: String?, delay: Double = 0.32) {
        later(delay) {
            peeling[item.id] = 0
            later(0.02) {
                withAnimation(.easeInOut(duration: 1.15)) { peeling[item.id] = 1 }
            }
            later(1.2) {
                withAnimation(.easeOut(duration: 0.2)) {
                    store.remove(item.id)
                    peeling[item.id] = nil
                }
                if let message { showToast(message) }
            }
        }
    }

    private func later(_ seconds: Double, _ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: action)
    }

    private func showToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.2)) { toast = text }
        later(2.2) {
            withAnimation(.easeOut(duration: 0.3)) { if toast == text { toast = nil } }
        }
    }

    private func applyDebugLaunch() {
#if DEBUG
        // 截图/调试用（仅 Debug 构建）：环境变量 FRIDGE_DEMO_SCENE=open | zone:<rawValue> | note | note:style | note:deco | notepeel:0.4 | 0.3（门停在动画中途）| peel:0.3 | land:0.6
        guard let raw = ProcessInfo.processInfo.environment["FRIDGE_DEMO_SCENE"] else { return }
        if raw == "open" { isOpen = true; progress = 1 }
        if raw.hasPrefix("zone:"), let zone = FridgeZone(rawValue: String(raw.dropFirst(5))) {
            isOpen = true; progress = 1; focusedZone = zone
        }
        if raw == "magnets" {
            // 测试用：三种照片贴（照片先拿食物贴纸图顶）
            let pics = ["strawberry", "grapes", "milk", "eggs"].compactMap { FridgeArt.image($0, sticker: true) }
            let names = pics.compactMap { FridgeArt.savePhoto($0) }
            if let first = pics.first, let sticker = FridgeArt.savePhotoSticker(FridgeMagnetSheet.roundedSticker(first)) {
                store.addMagnet(style: .photo, text: "", hex: "#FFFFFF", images: [sticker])
            }
            store.addMagnet(style: .polaroid, text: "第一次一起做饭", hex: "#FFFDF8", images: Array(names.prefix(1)))
            store.addMagnet(style: .strip, text: "2026.10.29", hex: "#2B2522", images: names)
        }
        if raw == "magnets:spread" {
            let spots: [FridgeMagnet.Style: (Double, Double)] = [.photo: (0.3, 0.62),
                                                                  .polaroid: (0.32, 0.27), .strip: (0.74, 0.33)]
            for magnet in store.magnets {
                if let spot = spots[magnet.style] { store.moveMagnet(magnet.id, x: spot.0, y: spot.1) }
            }
        }
        if raw == "magnets:clear" {
            for magnet in store.magnets { store.removeMagnet(magnet.id) }
        }
        if raw.hasPrefix("note"), let note = store.notes.first {
            later(0.6) { openNote(note) }
            if raw == "note:style" { later(1.2) { withAnimation { bigNotePanel = .style } } }
            if raw == "note:deco" { later(1.2) { withAnimation { bigNotePanel = .deco } } }
            if raw.hasPrefix("notepeel:"), let value = Double(raw.dropFirst(9)) {
                later(1.2) { bigNotePeel = CGFloat(value) }
            }
        }
        if raw.hasPrefix("peel:"), let value = Double(raw.dropFirst(5)) {
            isOpen = true; progress = 1
            for item in store.items(in: .crisper).prefix(2) { peeling[item.id] = CGFloat(value) }
        }
        if raw.hasPrefix("land:"), let value = Double(raw.dropFirst(5)) {
            isOpen = true; progress = 1
            if let item = store.items(in: .chillMid).first { landing[item.id] = CGFloat(value) }
        }
        if let value = Double(raw) { progress = CGFloat(value); isOpen = value > 0.5 }
#endif
    }
}

enum BigNotePanel { case style, deco }

/// 门的转动分两段：外侧 0→90°（合页在右），过了一半换内侧 90°→0 摊平。
/// 必须做成 Animatable：系统默认只会把起止角度线性插值，两段就叠在一起了。
struct FridgeDoorSwing: ViewModifier, Animatable {
    var progress: CGFloat
    let inner: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let anchor = UnitPoint(x: FridgeCanvas.hingeX / FridgeCanvas.size.width, y: 0.5)
        let phase = inner ? max(0, (progress - 0.5) * 2) : min(1, progress * 2)
        let angle = inner ? (phase - 1) * 90 : phase * 90
        let visible = inner ? progress > 0.5 : progress < 0.5
        content
            .rotation3DEffect(.degrees(Double(angle)), axis: (x: 0, y: 1, z: 0),
                              anchor: anchor, perspective: 0.45)
            .opacity(visible ? 1 : 0)
    }
}

// MARK: - 贴纸

struct FridgeSticker: View {
    let item: FridgeItem
    var peel: CGFloat = 0
    var land: CGFloat? = nil
    var dot = false

    static func tilt(_ id: String) -> Double {
        let sum = id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Double(sum % 11) - 5
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = FridgeArt.sticker(for: item) {
                Image(uiImage: image).resizable().scaledToFit()
                    .shadow(color: Color(cpHex: "#5A4030").opacity(0.22), radius: 4, y: 3)
            } else {
                RoundedRectangle(cornerRadius: 14).fill(Color(cpHex: "#F3E6C8"))
            }
            if dot, peel == 0, land == nil, FridgeDue.tone(item) != .fine, FridgeDue.tone(item) != .none {
                Circle()
                    .fill(FridgeDue.color(FridgeDue.tone(item)))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(Color.white, lineWidth: 3))
                    .offset(x: -4, y: 4)
            }
        }
        .modifier(FridgeStickOn(progress: land ?? 1))
        .modifier(FridgeCurl(progress: peel, corner: .topLeading, fullPeel: true))
    }
}

/// 门上的提醒：磁铁压着贴纸，下面一张小纸签写名字和到期
struct FridgeDoorReminder: View {
    let item: FridgeItem
    var peel: CGFloat = 0

    var body: some View {
        VStack(spacing: -6) {
            FridgeSticker(item: item)
                .frame(width: 128, height: 128)
            VStack(spacing: 2) {
                Text(item.name)
                    .font(FridgeFont.cute(26))
                    .foregroundStyle(Color(cpHex: "#5A4334"))
                    .lineLimit(1)
                Text(FridgeDue.label(item))
                    .font(FridgeFont.cute(22))
                    .foregroundStyle(FridgeDue.color(FridgeDue.tone(item)))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(cpHex: "#FFFCF5")))
            .shadow(color: Color(cpHex: "#5A4030").opacity(0.16), radius: 4, y: 2)
        }
        .fixedSize()
        .modifier(FridgeCurl(progress: max(0, (peel - 0.22) / 0.78), corner: .topLeading, fullPeel: true))
        .overlay(alignment: .top) {
            FridgeMagnetDot(color: Color(cpHex: "#E58F8F"))
                .offset(y: -6)
                .modifier(FridgeAttachOff(progress: min(peel / 0.3, 1), isTape: false))
        }
    }
}

// MARK: - 某一层放大后的卡片

struct FridgeZoneCard: View {
    @ObservedObject var theme: FridgeTheme
    let zone: FridgeZone
    let items: [FridgeItem]
    let peeling: [String: CGFloat]
    let landing: [String: CGFloat]
    let bottomInset: CGFloat
    let onPick: (FridgeItem) -> Void
    let onAdd: () -> Void
    let onClose: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(cpHex: "#E3D2C2")).frame(width: 38, height: 5).padding(.top, 9)
            HStack(alignment: .firstTextBaseline) {
                Text(zone.title).font(FridgeFont.cute(22)).foregroundStyle(Color(cpHex: "#5A4334"))
                Text("\(items.count) 样").font(FridgeFont.cute(14)).foregroundStyle(Color(cpHex: "#A88E78"))
                Spacer()
                Button(action: onAdd) {
                    Label("放这层", systemImage: "plus")
                        .font(FridgeFont.cute(14))
                        .foregroundStyle(Color(cpHex: "#C98A92"))
                }
                .buttonStyle(.plain)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(cpHex: "#A88E78"))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color(cpHex: "#F4E9DD")))
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 8)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 12).onEnded { if $0.translation.height > 50 { onClose() } })

            if items.isEmpty {
                Text("这一层空空的，放点什么进来吧")
                    .font(FridgeFont.cute(15))
                    .foregroundStyle(Color(cpHex: "#A88E78"))
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(items) { item in
                            Button { onPick(item) } label: { cell(item) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 16)
                }
                .frame(maxHeight: 330)
            }
        }
        .padding(.bottom, bottomInset + 8)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(cpHex: "#FFFBF4"))
                .shadow(color: Color(cpHex: "#6A5030").opacity(0.18), radius: 20, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func cell(_ item: FridgeItem) -> some View {
        VStack(spacing: 4) {
            FridgeSticker(item: item, peel: peeling[item.id] ?? 0, land: landing[item.id])
                .frame(width: 74, height: 74)
                .rotationEffect(.degrees(FridgeSticker.tilt(item.id) * 0.6))
            Text(item.name)
                .font(FridgeFont.cute(15))
                .foregroundStyle(Color(cpHex: "#5A4334"))
                .lineLimit(1)
            Text(FridgeDue.label(item))
                .font(FridgeFont.cute(12))
                .foregroundStyle(FridgeDue.color(FridgeDue.tone(item)))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(Capsule().fill(FridgeDue.color(FridgeDue.tone(item)).opacity(0.12)))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(cpHex: "#F8EFE4")))
    }
}
