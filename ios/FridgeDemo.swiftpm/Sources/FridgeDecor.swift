import SwiftUI
import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - 冰箱 · 装饰件：漆面换色、贴上/揭下动画、便签样式、拍照抠贴纸

// MARK: 漆面换色

enum FridgePaint {
    struct Preset: Identifiable {
        let name: String
        let hex: String?
        var id: String { name }
    }

    static let presets: [Preset] = [
        .init(name: "奶油", hex: nil),
        .init(name: "薄荷绿", hex: "#A9D9C6"),
        .init(name: "樱花粉", hex: "#F3C3CC"),
        .init(name: "天蓝", hex: "#B5D3EC"),
        .init(name: "黄油黄", hex: "#F6DE8D"),
        .init(name: "鼠尾草", hex: "#B7C6A5"),
        .init(name: "奶咖", hex: "#D8BFA5"),
    ]

    static func hex(_ color: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

/// 一层冰箱图。换色时在原图上盖「明暗层 × 颜色」再补一层高光，
/// 遮罩只认奶油色漆面，镀铬把手、白内胆、透明门架都不会被染。
struct FridgePaintedArt: View {
    let name: String
    let paintHex: String?

    var body: some View {
        ZStack {
            if let image = FridgeArt.image(name) {
                Image(uiImage: image).resizable()
            } else {
                Color(cpHex: "#F3E6C8")
            }
            if let paintHex, let shade = FridgeArt.image(name + "_shade"),
               let gloss = FridgeArt.image(name + "_gloss") {
                Image(uiImage: shade).resizable().colorMultiply(Color(cpHex: paintHex))
                Image(uiImage: gloss).resizable()
            }
        }
    }
}

// MARK: 揭下 / 贴上

enum FridgeCurlCorner { case topLeading, bottomTrailing }

/// 软贴纸揭下来：从一个角起，一道折痕沿对角线往前推，翻起来的那块对折过去露出背面，
/// 底下压一道软影；揭过一大半后整张被拎走。progress 0→1，必须 Animatable。
///
/// 翻起部分 = 原内容的剪影（按 alpha）× 背纸色，再沿折痕做镜像（u+v=k 的反射），
/// 所以形状跟着贴纸轮廓走，不是一块方板。
struct FridgeCurl: ViewModifier, Animatable {
    var progress: CGFloat
    var corner: FridgeCurlCorner = .topLeading
    var back: Color = Color(cpHex: "#FBF5EA")
    /// 折痕最远推到哪（对角线 = 1）。长方形的纸折过头会变成一大块三角，便签要小一点
    var maxReach: CGFloat = 0.95
    /// true = 一口气从这个角揭到对角，整张翻过去再消失，中间不停（食物贴纸用）
    var fullPeel = false

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let foldEnd: CGFloat = fullPeel ? 0.86 : 0.66
        let fold = min(progress / foldEnd, 1)
        let lift = max(0, (progress - foldEnd) / (1 - foldEnd))
        let eased = fullPeel ? lift : lift * lift
        // 分段模式：折痕不推过对角线，翻起的那片不会把还贴着的部分整个盖住。
        // 一口气模式：折痕匀速扫过整张（k 从 0 到 2），揭完再淡出
        let reach = fullPeel ? fold * 2 : (1 - pow(1 - fold, 2)) * maxReach
        let k = corner == .topLeading ? reach : 2 - reach
        let liftedLess = corner == .topLeading
        return content
            .opacity(progress > 0 ? 0 : 1)
            .overlay {
                if progress > 0 {
                    GeometryReader { geo in
                        let w = max(geo.size.width, 1), h = max(geo.size.height, 1)
                        let flip = CGAffineTransform(a: 0, b: -(h / w), c: -(w / h), d: 0, tx: k * w, ty: k * h)
                        let tip = liftedLess ? UnitPoint.topLeading : UnitPoint.bottomTrailing
                        let foldPoint = UnitPoint(x: k / 2, y: k / 2)
                        ZStack {
                            // 还贴着的部分
                            content.mask(FridgeHalfPlane(k: k, keepLess: !liftedLess))
                            // 翻起来那块压在下面的软影
                            Color.black.opacity(0.28)
                                .mask(content)
                                .mask(FridgeHalfPlane(k: k, keepLess: liftedLess))
                                .transformEffect(flip)
                                .blur(radius: 3 + fold * 3)
                                .offset(x: 2, y: 3 + fold * 3)
                                .mask(FridgeHalfPlane(k: k, keepLess: !liftedLess))
                            // 翻过来的背面：靠折痕处暗一点、往尖上渐亮，像软纸卷起来
                            back
                                .overlay(LinearGradient(colors: [Color.white.opacity(0.85), Color.black.opacity(0.16)],
                                                        startPoint: tip, endPoint: foldPoint))
                                .mask(content)
                                .mask(FridgeHalfPlane(k: k, keepLess: liftedLess))
                                .transformEffect(flip)
                        }
                        .frame(width: w, height: h)
                    }
                }
            }
            .scaleEffect(1 + fold * 0.04 - eased * (fullPeel ? 0.15 : 0.5))
            .rotationEffect(.degrees(Double(eased) * (fullPeel ? 8 : 22)))
            .offset(x: eased * (fullPeel ? 30 : 80), y: -eased * (fullPeel ? 60 : 320))
            .opacity(fullPeel ? 1 - Double(lift) : 1 - Double(max(0, (lift - 0.5) / 0.5)))
    }
}

/// 单位方块里 u+v=k 这条线的一侧（keepLess = 靠左上那侧）
struct FridgeHalfPlane: Shape {
    var k: CGFloat
    var keepLess: Bool

    func path(in rect: CGRect) -> Path {
        func p(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + u * rect.width, y: rect.minY + v * rect.height)
        }
        let far: CGFloat = keepLess ? -40 : 40
        var path = Path()
        path.move(to: p(k + 12, -12))
        path.addLine(to: p(-12, k + 12))
        path.addLine(to: p(k / 2 + far, k / 2 + far))
        path.closeSubpath()
        return path
    }
}

/// 纸被手拿走：先轻轻离开门面（放大一点、影子变深），再往上斜着飞走
struct FridgeTakeAway: ViewModifier, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let pick = min(progress / 0.3, 1)
        let fly = max(0, (progress - 0.3) / 0.7)
        let ease = fly * fly
        return content
            .shadow(color: .black.opacity(0.22 * Double(pick) * (1 - Double(fly))), radius: 6 + pick * 14, y: 4 + pick * 12)
            .scaleEffect(1 + pick * 0.05 - ease * 0.25)
            .rotationEffect(.degrees(Double(pick) * -3 + Double(ease) * 14))
            .offset(x: ease * 90, y: -pick * 8 - ease * 420)
            .opacity(1 - Double(max(0, (fly - 0.4) / 0.6)))
    }
}

/// 固定物先拿掉：胶带从一头撕起再卷走，磁铁弹一下飞走，小贴纸转着飞走
struct FridgeAttachOff: ViewModifier, Animatable {
    var progress: CGFloat
    var isTape: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let first = min(progress / 0.5, 1)
        let fly = max(0, (progress - 0.5) / 0.5)
        return content
            .rotation3DEffect(.degrees(isTape ? Double(first) * 75 : 0), axis: (x: 0, y: 1, z: 0),
                              anchor: .leading, perspective: 0.6)
            .scaleEffect(isTape ? 1 : 1 + sin(first * .pi) * 0.25)
            .offset(x: fly * 50, y: -fly * 180 - (isTape ? 0 : first * 12))
            .rotationEffect(.degrees(Double(fly) * 30))
            .opacity(1 - Double(fly))
    }
}

/// 贴上去：从下面飞进来，悬一下（影子大）→ 按下去压扁一点 → 回弹贴平
struct FridgeStickOn: ViewModifier, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let travel = min(progress / 0.58, 1)
        let ease = 1 - pow(1 - travel, 3)
        let scale: CGFloat
        if progress < 0.58 {
            scale = 1.45 - 0.3 * ease
        } else if progress < 0.8 {
            scale = 1.15 - (progress - 0.58) / 0.22 * 0.23
        } else {
            scale = 0.92 + (progress - 0.8) / 0.2 * 0.08
        }
        let lift = progress < 0.8 ? max(0, 1 - (progress - 0.4) / 0.4) : 0
        return content
            .shadow(color: .black.opacity(0.25 * Double(min(lift, 1))), radius: 6 + 18 * min(lift, 1),
                    y: 6 + 22 * min(lift, 1))
            .scaleEffect(scale)
            .offset(y: (1 - ease) * 520)
            .opacity(Double(min(progress / 0.12, 1)))
    }
}

// MARK: 便签

/// 门上的便签（舞台坐标，宽约 228）。peel：固定物先拿掉，再整张纸被拿走。
/// editable 时（居中大图）装饰小贴纸可以拖；点一下选中，选中后能删、能转方向。
struct FridgeNoteView: View {
    let note: FridgeNote
    var peel: CGFloat = 0
    var editable = false
    var onMoveDeco: (String, Double, Double) -> Void = { _, _, _ in }
    var onRemoveDeco: (String) -> Void = { _ in }
    var onRotateDeco: (String, Double) -> Void = { _, _ in }
    @State private var selectedDeco: String?

    private var ink: Color {
        note.paper == .kraft ? Color(cpHex: "#4A3424") : Color(cpHex: "#4F3D33")
    }

    private var isTape: Bool {
        note.attach == .washiStripe || note.attach == .washiDot || note.attach == .clearTape
    }

    var body: some View {
        let attachProgress = min(peel / 0.4, 1)
        let takeProgress = max(0, (peel - 0.42) / 0.58)
        paper
            .overlay(alignment: .topLeading) { decoLayer }
            .overlay(alignment: .top) {
                FridgeAttachView(kind: note.attach)
                    .offset(y: -14)
                    .modifier(FridgeAttachOff(progress: attachProgress, isTape: isTape))
            }
            .modifier(FridgeTakeAway(progress: takeProgress))
    }

    private var decoLayer: some View {
        ZStack(alignment: .topLeading) {
            // 选中时点便签空白处取消选中；没选中时不拦点击
            Color.clear
                .contentShape(Rectangle())
                .allowsHitTesting(editable && selectedDeco != nil)
                .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { selectedDeco = nil } }
            ForEach(note.decos) { deco in
                FridgeDecoSticker(deco: deco, editable: editable, selected: editable && selectedDeco == deco.id,
                                  onSelect: {
                                      withAnimation(.easeOut(duration: 0.15)) {
                                          selectedDeco = selectedDeco == deco.id ? nil : deco.id
                                      }
                                  },
                                  onMove: { x, y in onMoveDeco(deco.id, x, y) },
                                  onRotate: { onRotateDeco(deco.id, $0) },
                                  onRemove: {
                                      selectedDeco = nil
                                      onRemoveDeco(deco.id)
                                  })
            }
        }
        .coordinateSpace(name: "fridgeNoteDeco")
        .onChange(of: editable) { if !$0 { selectedDeco = nil } }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.text)
                .font(FridgeFont.note(note.font, CGFloat(note.fontSize)))
                .foregroundStyle(ink)
                .lineSpacing(note.paper == .lined || note.paper == .index ? 9 : 4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if note.author == .partner {
                Text("— TA")
                    .font(FridgeFont.cute(19))
                    .foregroundStyle(Color(cpHex: "#C98A92"))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(width: 196, alignment: .topLeading)
        .padding(.horizontal, 16).padding(.top, 28).padding(.bottom, 22)
        .frame(minHeight: 150, alignment: .topLeading)
    }

    @ViewBuilder private var paper: some View {
        switch note.paper {
        case .yellow:
            content.background(Rectangle().fill(Color(cpHex: "#FFE9A6")))
                .shadow(color: Color(cpHex: "#6A5030").opacity(0.2), radius: 5, x: 2, y: 4)
        case .lined:
            content.background(
                FridgeTornPaper().fill(Color(cpHex: "#FFFDF8"))
                    .overlay(FridgeRuledLines(spacing: 35, top: 62, color: Color(cpHex: "#BFD3E6"))
                        .clipShape(FridgeTornPaper()))
            )
            .shadow(color: Color(cpHex: "#6A5030").opacity(0.18), radius: 5, x: 1, y: 4)
        case .kraft:
            content.background(
                RoundedRectangle(cornerRadius: 4).fill(Color(cpHex: "#D9BC94"))
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color(cpHex: "#B8946A").opacity(0.6),
                                      style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        .padding(8))
            )
            .shadow(color: Color(cpHex: "#6A5030").opacity(0.2), radius: 5, x: 2, y: 4)
        case .grid:
            content.background(
                Rectangle().fill(Color(cpHex: "#FFFEFA"))
                    .overlay(FridgeGrid(step: 22).stroke(Color(cpHex: "#D5E2EE"), lineWidth: 1.2))
            )
            .shadow(color: Color(cpHex: "#6A5030").opacity(0.16), radius: 5, x: 1, y: 4)
        case .pink:
            content.background(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(cpHex: "#FFD9E0"))
                    .overlay(alignment: .bottomLeading) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color(cpHex: "#F2A3B3").opacity(0.7))
                            .padding(12)
                    }
            )
            .shadow(color: Color(cpHex: "#8A4A5A").opacity(0.16), radius: 5, x: 1, y: 4)
        case .index:
            content.background(
                RoundedRectangle(cornerRadius: 6).fill(Color.white)
                    .overlay(FridgeRuledLines(spacing: 35, top: 62, color: Color(cpHex: "#C9DAEA")))
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color(cpHex: "#E8A0A0")).frame(height: 2).padding(.top, 50)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            )
            .shadow(color: Color(cpHex: "#6A5030").opacity(0.16), radius: 5, x: 1, y: 4)
        }
    }
}

/// 便签上的一枚装饰贴纸：白描边 + 小投影；可编辑时能拖，点一下选中：左上 × 删，右下把手转方向（也能两指转）
struct FridgeDecoSticker: View {
    let deco: FridgeNoteDeco
    var editable = false
    var selected = false
    var onSelect: () -> Void = {}
    var onMove: (Double, Double) -> Void = { _, _ in }
    var onRotate: (Double) -> Void = { _ in }
    var onRemove: () -> Void = {}
    @GestureState private var drag: CGSize = .zero
    @GestureState private var twist: Double = 0
    @State private var handleTilt: Double?

    /// 选中框半径（便签坐标），把手在右下 45° 方向
    private let ring: CGFloat = 32

    var body: some View {
        let tilt = (handleTilt ?? deco.tilt) + twist
        let center = CGPoint(x: deco.x + drag.width, y: deco.y + drag.height)
        ZStack {
            FridgeDecoGlyph(kind: deco.kind, size: 40)
                .rotationEffect(.degrees(tilt))
                .scaleEffect(drag == .zero ? 1 : 1.15)
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .updating($drag) { value, state, _ in state = value.translation }
                        .onEnded { value in
                            onMove(min(max(deco.x + value.translation.width, 10), 218),
                                   min(max(deco.y + value.translation.height, 10), 260))
                        }
                )
                .simultaneousGesture(
                    RotationGesture()
                        .updating($twist) { value, state, _ in state = value.degrees }
                        .onEnded { value in onRotate(deco.tilt + value.degrees) }
                )
                .simultaneousGesture(TapGesture().onEnded { onSelect() })
            if selected {
                Circle()
                    .strokeBorder(Color.white, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    .shadow(color: .black.opacity(0.25), radius: 2)
                    .frame(width: ring * 2, height: ring * 2)
                    .rotationEffect(.degrees(tilt))
                    .allowsHitTesting(false)
                // × 和把手跟着贴纸一起转：把手始终在手指底下
                deleteButton
                    .offset(ringOffset(tilt + 225))
                rotateHandle(center: center)
                    .offset(ringOffset(tilt + 45))
            }
        }
        .position(center)
        .allowsHitTesting(editable)
    }

    private func ringOffset(_ degrees: Double) -> CGSize {
        let r = degrees * .pi / 180
        return CGSize(width: cos(r) * ring, height: sin(r) * ring)
    }

    private var deleteButton: some View {
        Image(systemName: "xmark")
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(Color(cpHex: "#C98A92")))
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            .contentShape(Circle().inset(by: -8))
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onRemove()
            }
    }

    /// 按住把手绕贴纸中心拖，手指方向减去把手本来的 45° 就是新角度
    private func rotateHandle(center: CGPoint) -> some View {
        Image(systemName: "arrow.clockwise")
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(Color(cpHex: "#7A5A3A"))
            .frame(width: 22, height: 22)
            .background(Circle().fill(Color.white))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .contentShape(Circle().inset(by: -8))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("fridgeNoteDeco"))
                    .onChanged { value in
                        let angle = atan2(value.location.y - center.y, value.location.x - center.x) * 180 / .pi
                        handleTilt = angle - 45
                    }
                    .onEnded { _ in
                        if let handleTilt { onRotate(handleTilt) }
                        handleTilt = nil
                    }
            )
    }
}

struct FridgeDecoGlyph: View {
    let kind: FridgeDecoKind
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(Color(cpHex: kind.hex))
            // 四个方向各描一圈白，模拟贴纸的白边
            .shadow(color: .white, radius: 0, x: 2.5, y: 0)
            .shadow(color: .white, radius: 0, x: -2.5, y: 0)
            .shadow(color: .white, radius: 0, x: 0, y: 2.5)
            .shadow(color: .white, radius: 0, x: 0, y: -2.5)
            .shadow(color: .black.opacity(0.2), radius: 2, y: 2)
            .frame(width: size * 1.3, height: size * 1.3)
    }
}

/// 固定便签用的东西（磁铁 / 胶带 / 贴纸）
struct FridgeAttachView: View {
    let kind: FridgeAttach

    var body: some View {
        switch kind {
        case .magnetPink: FridgeMagnetDot(color: Color(cpHex: "#E58F8F"))
        case .magnetBlue: FridgeMagnetDot(color: Color(cpHex: "#86B3D1"))
        case .magnetMint: FridgeMagnetDot(color: Color(cpHex: "#8CC7AE"))
        case .washiStripe:
            tape(Color(cpHex: "#F2B8C2").opacity(0.8)) {
                HStack(spacing: 10) {
                    ForEach(0..<5, id: \.self) { _ in Rectangle().fill(Color.white.opacity(0.38)).frame(width: 5) }
                }
            }
        case .washiDot:
            tape(Color(cpHex: "#A9D9C6").opacity(0.82)) {
                HStack(spacing: 12) {
                    ForEach(0..<5, id: \.self) { _ in Circle().fill(Color.white.opacity(0.6)).frame(width: 7, height: 7) }
                }
            }
        case .clearTape:
            tape(Color.white.opacity(0.45)) {
                Rectangle().stroke(Color.white.opacity(0.7), lineWidth: 1)
            }
        case .heart:
            Image(systemName: "heart.fill")
                .font(.system(size: 34))
                .foregroundStyle(Color(cpHex: "#F28CA0"))
                .shadow(color: .white, radius: 0, x: 2, y: 2)
                .shadow(color: .white, radius: 0, x: -2, y: -2)
                .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
        case .flower:
            ZStack {
                ForEach(0..<5, id: \.self) { index in
                    Circle().fill(Color(cpHex: "#F7C8D4"))
                        .frame(width: 18, height: 18)
                        .offset(y: -10)
                        .rotationEffect(.degrees(Double(index) * 72))
                }
                Circle().fill(Color(cpHex: "#F6D77C")).frame(width: 12, height: 12)
            }
            .frame(width: 40, height: 40)
            .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
        }
    }

    private func tape<Pattern: View>(_ fill: Color, @ViewBuilder _ pattern: () -> Pattern) -> some View {
        Rectangle()
            .fill(fill)
            .overlay(pattern())
            .frame(width: 98, height: 30)
            .clipped()
            .rotationEffect(.degrees(-4))
            .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
    }
}

struct FridgeMagnetDot: View {
    var color: Color
    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(0.75), color], center: .init(x: 0.35, y: 0.3),
                                 startRadius: 1, endRadius: 18))
            .frame(width: 30, height: 30)
            .overlay(Circle().fill(Color.white.opacity(0.7)).frame(width: 8, height: 8).offset(x: -5, y: -6))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 3)
    }
}

struct FridgeRuledLines: View {
    let spacing: CGFloat
    let top: CGFloat
    let color: Color
    var body: some View {
        GeometryReader { geo in
            Path { path in
                var y = top
                while y < geo.size.height - 10 {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    y += spacing
                }
            }
            .stroke(color.opacity(0.7), lineWidth: 1.5)
        }
    }
}

struct FridgeGrid: Shape {
    let step: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX + step
        while x < rect.maxX { path.move(to: CGPoint(x: x, y: rect.minY)); path.addLine(to: CGPoint(x: x, y: rect.maxY)); x += step }
        var y = rect.minY + step
        while y < rect.maxY { path.move(to: CGPoint(x: rect.minX, y: y)); path.addLine(to: CGPoint(x: rect.maxX, y: y)); y += step }
        return path
    }
}

/// 下沿撕开的纸
struct FridgeTornPaper: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 8))
        let teeth = 14
        let step = rect.width / CGFloat(teeth)
        for index in 0..<teeth {
            let x = rect.maxX - step * (CGFloat(index) + 0.5)
            let y = rect.maxY - (index.isMultiple(of: 2) ? 0 : 9)
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - 6))
        path.closeSubpath()
        return path
    }
}

// MARK: 拍照抠贴纸（只抠图，不重画）

enum FridgePhotoCutout {
    enum Failure: Error { case unsupported, noSubject, render }

    /// 系统主体识别抠图（相册长按拎出主体同一套），外面补一圈奶白裁切边，输出 512 方图
    static func makeSticker(from source: UIImage) async throws -> UIImage {
        guard #available(iOS 17.0, *) else { throw Failure.unsupported }
        // 先按方向摆正并压到 1400 以内（用 image.size，不用 cgImage 像素尺寸，竖图才不会压扁）
        let maxSide: CGFloat = 1400
        let ratio = min(1, maxSide / max(source.size.width, source.size.height))
        let size = CGSize(width: source.size.width * ratio, height: source.size.height * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cg = upright.cgImage else { throw Failure.render }

        return try await Task.detached(priority: .userInitiated) {
            let handler = VNImageRequestHandler(cgImage: cg)
            let request = VNGenerateForegroundInstanceMaskRequest()
            try handler.perform([request])
            guard let result = request.results?.first, !result.allInstances.isEmpty else { throw Failure.noSubject }
            let maskBuffer = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)

            let photo = CIImage(cgImage: cg)
            let mask = CIImage(cvPixelBuffer: maskBuffer)
            let border = max(10, min(photo.extent.width, photo.extent.height) * 0.028)
            let grown = mask
                .applyingFilter("CIMorphologyMaximum", parameters: ["inputRadius": border])
                .applyingGaussianBlur(sigma: 1.5)
                .cropped(to: photo.extent)
            let cutout = photo.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: mask])
            let cream = CIImage(color: CIColor(red: 1, green: 0.985, blue: 0.95)).cropped(to: photo.extent)
                .applyingFilter("CIBlendWithMask", parameters: [
                    kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: grown])
            let sticker = cutout.composited(over: cream)

            let context = CIContext()
            guard let rendered = context.createCGImage(sticker, from: photo.extent) else { throw Failure.render }
            guard let bounds = opaqueBounds(rendered) else { throw Failure.noSubject }
            let side = max(bounds.width, bounds.height) * 1.08
            let canvas = CGSize(width: 512, height: 512)
            let scale = 512 / side
            let out = UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
                let drawSize = CGSize(width: CGFloat(rendered.width) * scale, height: CGFloat(rendered.height) * scale)
                let origin = CGPoint(x: (256 - bounds.midX * scale), y: (256 - bounds.midY * scale))
                UIImage(cgImage: rendered).draw(in: CGRect(origin: origin, size: drawSize))
            }
            return out
        }.value
    }

    /// 不透明像素的包围盒（UIKit 坐标，原点左上）
    private static func opaqueBounds(_ image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) where data[(y * width + x) * 4 + 3] > 24 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

// MARK: - 门上的照片

/// 门上的一张照片（舞台单位，门外侧宽 541）
struct FridgeMagnetView: View {
    let magnet: FridgeMagnet
    var size: CGFloat = 1
    /// 编辑页用：点格子选中，拖 / 捏改构图；门上不传
    var editing: FridgePhotoCell.Editing? = nil

    var body: some View {
        switch magnet.style {
        case .photo: photoSticker
        case .polaroid: polaroid
        case .strip: strip
        }
    }

    private func image(_ index: Int) -> UIImage? {
        guard let names = magnet.images, index < names.count else { return nil }
        return FridgeArt.photo(names[index])
    }

    /// 照片抠图（自带奶白边）当亚克力贴
    private var photoSticker: some View {
        Group {
            if let ui = image(0) {
                Image(uiImage: ui).resizable().scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 16).fill(Color(cpHex: "#EFE6DA"))
            }
        }
        .frame(width: 130 * size, height: 130 * size)
        .shadow(color: .black.opacity(0.25), radius: 3 * size, x: 1, y: 4 * size)
    }

    private func photoCell(_ index: Int, width: CGFloat, height: CGFloat) -> some View {
        FridgePhotoCell(image: image(index), crop: magnet.crop(index), index: index,
                        width: width, height: height, editing: editing)
    }

    /// 顶上压的东西：四色磁铁 / 半透明胶带 / 不贴（magnet.pin，nil 是最早的粉磁铁）
    @ViewBuilder private var pin: some View {
        let key = magnet.pin ?? "pink"
        if key == "tape" {
            Rectangle()
                .fill(Color.white.opacity(0.55))
                .overlay(Rectangle().stroke(Color.white.opacity(0.7), lineWidth: 0.5))
                .frame(width: 58 * size, height: 18 * size)
                .rotationEffect(.degrees(-4))
                .shadow(color: .black.opacity(0.08), radius: 1 * size, y: 1 * size)
                .offset(y: 2 * size)
        } else if key != "none" {
            let colors = FridgeMagnetCatalog.pinColors(key)
            Circle()
                .fill(RadialGradient(colors: [colors.0, colors.1],
                                     center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: 16 * size))
                .frame(width: 26 * size, height: 26 * size)
                .shadow(color: .black.opacity(0.3), radius: 2 * size, y: 2 * size)
        }
    }

    private var polaroid: some View {
        let w: CGFloat = 196 * size
        let inner = w - 24 * size
        return VStack(spacing: 0) {
            photoCell(0, width: inner, height: inner)
            Text(magnet.text)
                .font(FridgeFont.note(.kuaile, 19 * size))
                .foregroundStyle(FridgeMagnetCatalog.frameInk(magnet.hex))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: inner, height: 48 * size)
        }
        .padding([.top, .horizontal], 12 * size)
        .background(Color(cpHex: magnet.hex))
        .shadow(color: .black.opacity(0.22), radius: 4 * size, x: 1, y: 5 * size)
        .overlay(alignment: .top) { pin.offset(y: -9 * size) }
    }

    private var strip: some View {
        let inner: CGFloat = 100 * size
        return VStack(spacing: 7 * size) {
            ForEach(0..<4, id: \.self) { index in
                photoCell(index, width: inner, height: inner * 0.75)
            }
            Text(magnet.text)
                .font(.system(size: 11 * size, weight: .semibold, design: .monospaced))
                .foregroundStyle(FridgeMagnetCatalog.frameInk(magnet.hex))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: inner, height: 22 * size)
        }
        .padding([.top, .horizontal], 9 * size)
        .padding(.bottom, 2 * size)
        .background(Color(cpHex: magnet.hex))
        .shadow(color: .black.opacity(0.22), radius: 4 * size, x: 1, y: 5 * size)
        .overlay(alignment: .top) { pin.offset(y: -9 * size) }
    }
}

/// 拍立得 / 四格里的一格：照片先等比铺满，再按 crop 放大、挪位置；编辑时能点选、拖、捏
struct FridgePhotoCell: View {
    struct Editing {
        var active: Int
        /// 只有一格（拍立得）时不画选中框：一直亮着的粉框像相框本身
        var showsSelection = true
        var onSelect: (Int) -> Void
        /// 提交的是「在最新构图上做什么改动」而不是整份构图：拖 / 捏 / 转三个手势同时松手时各交一次，
        /// 交整份的话后到的会拿手势开始时的旧构图把先到的盖掉
        var onCrop: (Int, @escaping (FridgeCrop) -> FridgeCrop) -> Void
    }

    let image: UIImage?
    let crop: FridgeCrop
    let index: Int
    let width: CGFloat
    let height: CGFloat
    var editing: Editing?

    @GestureState private var drag: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var twist: Angle = .zero

    private var isActive: Bool { editing?.active == index }

    /// 拖 / 捏 / 转进行中的构图（松手时同一个算法套到最新构图上存回去）。不卡边，留白没关系
    private func live(_ translation: CGSize, _ magnification: CGFloat, _ rotation: Angle) -> FridgeCrop {
        Self.apply(crop, translation, magnification, rotation, width: width, height: height)
    }

    static func apply(_ base: FridgeCrop, _ translation: CGSize, _ magnification: CGFloat, _ rotation: Angle,
                      width: CGFloat, height: CGFloat) -> FridgeCrop {
        FridgeCrop(u: min(max(base.u + Double(translation.width / width), -1), 1),
                   v: min(max(base.v + Double(translation.height / height), -1), 1),
                   scale: min(max(base.scale * Double(magnification), 0.3), 5),
                   rot: base.rot + rotation.degrees)
    }

    static func fillSize(image: UIImage, width: CGFloat, height: CGFloat) -> CGSize {
        let aspect = image.size.width / max(image.size.height, 1)
        return aspect > width / height ? CGSize(width: height * aspect, height: height)
                                      : CGSize(width: width, height: width / aspect)
    }

    var body: some View {
        ZStack {
            Color(cpHex: "#E9E1D6").opacity(image == nil ? 1 : 0)
            if let image {
                let now = live(drag, pinch, twist)
                let fill = Self.fillSize(image: image, width: width, height: height)
                Image(uiImage: image)
                    .resizable()
                    .frame(width: fill.width * now.scale, height: fill.height * now.scale)
                    .rotationEffect(.degrees(now.rot))
                    .offset(x: now.u * width, y: now.v * height)
            } else if editing != nil {
                Image(systemName: "plus")
                    .font(.system(size: min(width, height) * 0.22, weight: .semibold))
                    .foregroundStyle(Color(cpHex: "#A88E78"))
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .overlay {
            if isActive, let editing, editing.showsSelection {
                Rectangle().strokeBorder(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .shadow(color: .black.opacity(0.3), radius: 1.5)
            }
        }
        .contentShape(Rectangle())
        .modifier(EditGestures(enabled: editing != nil, active: isActive, drag: $drag, pinch: $pinch, twist: $twist,
                               onSelect: { editing?.onSelect(index) },
                               onEnd: { [width, height] t, m, r in
                                   guard image != nil else { return }
                                   editing?.onCrop(index) { latest in
                                       Self.apply(latest, t, m, r, width: width, height: height)
                                   }
                               }))
    }

    private struct EditGestures: ViewModifier {
        let enabled: Bool
        let active: Bool
        var drag: GestureState<CGSize>
        var pinch: GestureState<CGFloat>
        var twist: GestureState<Angle>
        let onSelect: () -> Void
        let onEnd: (CGSize, CGFloat, Angle) -> Void

        func body(content: Content) -> some View {
            if enabled {
                content
                    // 拖动自己当主手势（起手就接管，松手时几乎没动就算点选）；捏合、旋转并行挂着。
                    // 不能拖+捏合成一个组合手势再配 onTapGesture：组合手势认不出来，点击会把拖动吃掉
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .updating(drag) { value, state, _ in if active { state = value.translation } }
                            .onEnded { value in
                                let moved = hypot(value.translation.width, value.translation.height)
                                if moved < 6 || !active { onSelect() } else { onEnd(value.translation, 1, .zero) }
                            }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .updating(pinch) { value, state, _ in if active { state = value } }
                            .onEnded { value in if active { onEnd(.zero, value, .zero) } }
                    )
                    .simultaneousGesture(
                        RotationGesture()
                            .updating(twist) { value, state, _ in if active { state = value } }
                            .onEnded { value in if active { onEnd(.zero, 1, value) } }
                    )
            } else {
                content
            }
        }
    }
}

// MARK: - 键盘

extension View {
    /// 点空白处收起键盘（不拦其它点击）
    func fridgeDismissKeyboardOnTap() -> some View {
        simultaneousGesture(TapGesture().onEnded {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        })
    }
}
