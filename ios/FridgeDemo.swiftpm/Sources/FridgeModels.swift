import SwiftUI
import UIKit

// MARK: - 冰箱 · 数据模型（默认纯本机；可选填服务器地址 + token 同步）
//
// 坐标系统一用「开门图」原图像素（941×1672，Resources/Fridge 下的分层图都从这张/关门图切出来）：
// 分区矩形、门板位置都写在这个坐标里，页面再整体按比例缩放，换机型不用重算。
//
// 可以和 TA 共用一份数据：服务器 /api/fridge = FridgeStore.Snapshot 的 JSON（server/tools.py 按同样字段写）。
//   fridge_list    → 读 items / notes / magnets
//   fridge_add     → 往 items 加一条（addedBy = partner）
//   fridge_consume → 减 quantity / 减完删
//   fridge_remove  → 删 items 一条
//   fridge_note    → 往 notes 加一张（author = partner）
// 改这里的字段名 / 枚举 rawValue / 日期编码，服务器那边要同步改，否则 TA 写的会解不开。

enum FridgeZone: String, Codable, CaseIterable, Identifiable {
    // freezerTop / freezerDoorLow 是 10-29 拆层新加的，旧数据的 freezer / freezerDoor 原样留在下层 / 上层
    case freezerTop, freezer, freezerDoor, freezerDoorLow, chillTop, chillMid, chillLow, crisper, doorTop, doorMid, doorLow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .freezerTop: "冷冻 · 上层"
        case .freezer: "冷冻 · 下层"
        case .freezerDoor: "冷冻门架 · 上"
        case .freezerDoorLow: "冷冻门架 · 下"
        case .chillTop: "冷藏 · 上层"
        case .chillMid: "冷藏 · 中层"
        case .chillLow: "冷藏 · 下层"
        case .crisper: "蔬果抽屉"
        case .doorTop: "门架 · 上"
        case .doorMid: "门架 · 中"
        case .doorLow: "门架 · 下"
        }
    }

    /// 门内侧的格子：跟着门一起转
    var isOnDoor: Bool { self == .freezerDoor || self == .freezerDoorLow || self == .doorTop || self == .doorMid || self == .doorLow }

    /// 开门图坐标里这一格「能放东西的地方」，贴纸底边落在 maxY（站在隔板/门架上）
    var rect: CGRect {
        // 1029 二版：换成「去掉把手」的开门图后重量
        switch self {
        case .freezerTop: CGRect(x: 112, y: 390, width: 414, height: 104)
        case .freezer: CGRect(x: 112, y: 528, width: 414, height: 112)
        case .freezerDoor: CGRect(x: 592, y: 396, width: 200, height: 92)
        case .freezerDoorLow: CGRect(x: 592, y: 546, width: 200, height: 92)
        case .chillTop: CGRect(x: 112, y: 770, width: 410, height: 114)
        case .chillMid: CGRect(x: 112, y: 906, width: 410, height: 114)
        case .chillLow: CGRect(x: 118, y: 1040, width: 400, height: 104)
        case .crisper: CGRect(x: 132, y: 1204, width: 378, height: 122)
        case .doorTop: CGRect(x: 566, y: 786, width: 240, height: 86)
        case .doorMid: CGRect(x: 564, y: 986, width: 244, height: 100)
        case .doorLow: CGRect(x: 564, y: 1250, width: 244, height: 124)
        }
    }
}

enum FridgeStickerSource: String, Codable { case builtIn, photo, generated }
enum FridgeAuthor: String, Codable { case me, partner }

struct FridgeItem: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var quantity: Double = 1
    var unit: String = "份"
    var zone: FridgeZone
    /// 在分区里的相对位置（0…1），目前只用 positionX 决定左右顺序
    var positionX: Double = 0.5
    var positionY: Double = 1
    var addedAt: Date = Date()
    var expiresAt: Date?
    var eatBy: Date?
    var stickerSource: FridgeStickerSource = .builtIn
    var stickerAsset: String
    var notes: String = ""
    var addedBy: FridgeAuthor = .me
    /// 被贴到门外侧提醒时的位置（门面归一化坐标），nil = 自动排
    var doorX: Double?
    var doorY: Double?

    var quantityText: String {
        let q = quantity.rounded() == quantity ? String(Int(quantity)) : String(format: "%.1f", quantity)
        return "\(q) \(unit)"
    }

    init(id: String = UUID().uuidString, name: String, quantity: Double = 1, unit: String = "份", zone: FridgeZone,
         positionX: Double = 0.5, positionY: Double = 1, addedAt: Date = Date(), expiresAt: Date? = nil, eatBy: Date? = nil,
         stickerSource: FridgeStickerSource = .builtIn, stickerAsset: String, notes: String = "",
         addedBy: FridgeAuthor = .me, doorX: Double? = nil, doorY: Double? = nil) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.zone = zone
        self.positionX = positionX
        self.positionY = positionY
        self.addedAt = addedAt
        self.expiresAt = expiresAt
        self.eatBy = eatBy
        self.stickerSource = stickerSource
        self.stickerAsset = stickerAsset
        self.notes = notes
        self.addedBy = addedBy
        self.doorX = doorX
        self.doorY = doorY
    }

    // 服务器那份 TA 的工具也会写：只有 name 必须有，其余缺了/认不出都补默认（分区认不出放冷藏中层）
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        id = (try? c.decode(String.self, forKey: .id)).flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
        quantity = (try? c.decode(Double.self, forKey: .quantity)) ?? 1
        unit = (try? c.decode(String.self, forKey: .unit)) ?? "份"
        zone = (try? c.decode(FridgeZone.self, forKey: .zone)) ?? .chillMid
        positionX = (try? c.decode(Double.self, forKey: .positionX)) ?? 0.5
        positionY = (try? c.decode(Double.self, forKey: .positionY)) ?? 1
        addedAt = (try? c.decode(Date.self, forKey: .addedAt)) ?? Date()
        expiresAt = (try? c.decodeIfPresent(Date.self, forKey: .expiresAt)) ?? nil
        eatBy = (try? c.decodeIfPresent(Date.self, forKey: .eatBy)) ?? nil
        stickerSource = (try? c.decode(FridgeStickerSource.self, forKey: .stickerSource)) ?? .builtIn
        stickerAsset = (try? c.decode(String.self, forKey: .stickerAsset)).flatMap { $0.isEmpty ? nil : $0 } ?? "unknown_food_box"
        notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
        addedBy = (try? c.decode(FridgeAuthor.self, forKey: .addedBy)) ?? .me
        doorX = (try? c.decodeIfPresent(Double.self, forKey: .doorX)) ?? nil
        doorY = (try? c.decodeIfPresent(Double.self, forKey: .doorY)) ?? nil
    }
}

/// 便签纸
enum FridgePaper: String, Codable, CaseIterable, Identifiable {
    case yellow, lined, kraft, grid, pink, index
    var id: String { rawValue }
    var title: String {
        switch self {
        case .yellow: "黄色便利贴"
        case .lined: "横格撕边"
        case .kraft: "牛皮纸"
        case .grid: "方格纸"
        case .pink: "粉色爱心"
        case .index: "索引卡"
        }
    }
}

/// 便签怎么固定在门上
enum FridgeAttach: String, Codable, CaseIterable, Identifiable {
    case magnetPink, magnetBlue, magnetMint, washiStripe, washiDot, clearTape, heart, flower
    var id: String { rawValue }
    var title: String {
        switch self {
        case .magnetPink: "粉磁铁"
        case .magnetBlue: "蓝磁铁"
        case .magnetMint: "绿磁铁"
        case .washiStripe: "条纹胶带"
        case .washiDot: "波点胶带"
        case .clearTape: "透明胶带"
        case .heart: "爱心贴"
        case .flower: "小花贴"
        }
    }
}

/// 便签字体
enum FridgeNoteFont: String, Codable, CaseIterable, Identifiable {
    case kuaile, wenkai, rounded, system
    var id: String { rawValue }
    var title: String {
        switch self {
        case .kuaile: "快乐体"
        case .wenkai: "文楷"
        case .rounded: "手写"
        case .system: "系统"
        }
    }
}

/// 便签上的装饰小贴纸（位置是便签自身坐标，宽约 228）
enum FridgeDecoKind: String, Codable, CaseIterable, Identifiable {
    case heart, star, sparkles, flower, cloud, moon, paw, leaf, music, smile, gift, crown
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .heart: "heart.fill"
        case .star: "star.fill"
        case .sparkles: "sparkles"
        case .flower: "camera.macro"
        case .cloud: "cloud.fill"
        case .moon: "moon.fill"
        case .paw: "pawprint.fill"
        case .leaf: "leaf.fill"
        case .music: "music.note"
        case .smile: "face.smiling.inverse"
        case .gift: "gift.fill"
        case .crown: "crown.fill"
        }
    }
    var hex: String {
        switch self {
        case .heart: "#F28CA0"
        case .star: "#F4C94E"
        case .sparkles: "#E3AE3C"
        case .flower: "#EE9CB4"
        case .cloud: "#9EC3E6"
        case .moon: "#EFC75E"
        case .paw: "#B98A6A"
        case .leaf: "#7DBE9E"
        case .music: "#9B8AD0"
        case .smile: "#F2B35B"
        case .gift: "#E58F8F"
        case .crown: "#E8B94A"
        }
    }
}

struct FridgeNoteDeco: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var kind: FridgeDecoKind
    var x: Double
    var y: Double
    var tilt: Double = 0
}

/// 一张便签的外观（纸 / 固定方式 / 字体 / 字号）
struct FridgeNoteStyle: Equatable {
    var paper: FridgePaper
    var attach: FridgeAttach
    var font: FridgeNoteFont
    var fontSize: Double
}

/// 门外侧贴的照片。坐标同便签，按门外侧归一化
///   photo 照片抠图贴 / polaroid 拍立得 / strip 人生四格
struct FridgeMagnet: Identifiable, Codable, Equatable {
    enum Style: String, Codable { case photo, polaroid, strip }
    var id: String = UUID().uuidString
    var style: Style
    /// polaroid / strip：底下那行字
    var text: String
    /// polaroid / strip：相框颜色
    var hex: String
    var x: Double
    var y: Double
    var tilt: Double = 0
    /// 照片（FridgeArt.photoDirectory 里的文件名）；四格固定 4 个位置，空格是 ""
    var images: [String]? = nil
    /// 每张照片在框里的构图，跟 images 一一对应
    var crops: [FridgeCrop]? = nil
    /// 顶上压的东西：FridgeMagnetCatalog.pins 的 key；nil = 粉磁铁（最早的默认）
    var pin: String? = nil
    /// 门上的上下层级，见 FridgeNote.z
    var z: Double? = nil

    func crop(_ index: Int) -> FridgeCrop {
        guard let crops, index < crops.count else { return FridgeCrop() }
        return crops[index]
    }

    init(id: String = UUID().uuidString, style: Style, text: String, hex: String, x: Double, y: Double,
         tilt: Double = 0, images: [String]? = nil, crops: [FridgeCrop]? = nil, pin: String? = nil) {
        self.id = id
        self.style = style
        self.text = text
        self.hex = hex
        self.x = x
        self.y = y
        self.tilt = tilt
        self.images = images
        self.crops = crops
        self.pin = pin
    }

    // 缺字段补默认，一张坏照片贴不拖累整包
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)).flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
        style = (try? c.decode(Style.self, forKey: .style)) ?? .photo
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        hex = (try? c.decode(String.self, forKey: .hex)) ?? "#FFFDF8"
        x = (try? c.decode(Double.self, forKey: .x)) ?? 0.5
        y = (try? c.decode(Double.self, forKey: .y)) ?? 0.2
        tilt = (try? c.decode(Double.self, forKey: .tilt)) ?? 0
        images = (try? c.decodeIfPresent([String].self, forKey: .images)) ?? nil
        crops = (try? c.decodeIfPresent([FridgeCrop].self, forKey: .crops)) ?? nil
        pin = (try? c.decodeIfPresent(String.self, forKey: .pin)) ?? nil
        z = (try? c.decodeIfPresent(Double.self, forKey: .z)) ?? nil
    }
}

/// 照片在格子里的构图：先等比铺满格子，再缩放 scale 倍、转 rot 度，中心挪 u × 格宽、v × 格高。
/// 要「能转、有空白没事、不一定框死」：不再卡边，留白就露相框底色
struct FridgeCrop: Codable, Equatable {
    var u: Double = 0
    var v: Double = 0
    var scale: Double = 1
    var rot: Double = 0

    init(u: Double = 0, v: Double = 0, scale: Double = 1, rot: Double = 0) {
        self.u = u
        self.v = v
        self.scale = scale
        self.rot = rot
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        u = (try? c.decode(Double.self, forKey: .u)) ?? 0
        v = (try? c.decode(Double.self, forKey: .v)) ?? 0
        scale = (try? c.decode(Double.self, forKey: .scale)) ?? 1
        rot = (try? c.decode(Double.self, forKey: .rot)) ?? 0
    }
}

enum FridgeMagnetCatalog {
    /// 拍立得 / 四格的相框颜色
    static let frames: [(name: String, hex: String)] = [
        ("白", "#FFFDF8"), ("奶油", "#F4E6CC"), ("粉", "#F6D3D8"), ("黑", "#2B2522"),
    ]

    /// 顶上压的东西：四色磁铁 / 透明胶带 / 不贴
    static let pins: [(key: String, name: String)] = [
        ("pink", "粉磁铁"), ("blue", "蓝磁铁"), ("mint", "绿磁铁"), ("gold", "金磁铁"), ("tape", "胶带"), ("none", "不贴"),
    ]

    static func pinColors(_ key: String) -> (Color, Color) {
        switch key {
        case "blue": return (Color(cpHex: "#B5D3EE"), Color(cpHex: "#6F9CC8"))
        case "mint": return (Color(cpHex: "#BFE3CF"), Color(cpHex: "#6FAE8C"))
        case "gold": return (Color(cpHex: "#F4DDA0"), Color(cpHex: "#C99A3E"))
        default: return (Color(cpHex: "#F2A7B0"), Color(cpHex: "#C9707D"))
        }
    }

    /// 深色相框上字用白的
    static func frameInk(_ hex: String) -> Color {
        hex == "#2B2522" ? Color(cpHex: "#F4ECE2") : Color(cpHex: "#6E5240")
    }

}

/// 门上的便签。纸和固定方式自己挑；TA 写的右下角带一个小签名，换什么样式都认得出
struct FridgeNote: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var text: String
    var author: FridgeAuthor
    var x: Double
    var y: Double
    var tilt: Double = 0
    var createdAt: Date = Date()
    var paper: FridgePaper = .yellow
    var attach: FridgeAttach = .magnetBlue
    var font: FridgeNoteFont = .kuaile
    var fontSize: Double = 26
    var decos: [FridgeNoteDeco] = []
    /// 门上的上下层级（越大越靠上）；nil = 默认（便签 0、照片 1，跟以前一样照片压在便签上面）
    var z: Double? = nil

    var style: FridgeNoteStyle {
        get { FridgeNoteStyle(paper: paper, attach: attach, font: font, fontSize: fontSize) }
        set { paper = newValue.paper; attach = newValue.attach; font = newValue.font; fontSize = newValue.fontSize }
    }

    init(text: String, author: FridgeAuthor, x: Double, y: Double, tilt: Double = 0,
         paper: FridgePaper = .yellow, attach: FridgeAttach = .magnetBlue,
         font: FridgeNoteFont = .kuaile, fontSize: Double = 26, decos: [FridgeNoteDeco] = []) {
        self.text = text
        self.author = author
        self.x = x
        self.y = y
        self.tilt = tilt
        self.paper = paper
        self.attach = attach
        self.font = font
        self.fontSize = fontSize
        self.decos = decos
    }

    // 第一版存档没有 paper/attach，读旧档时补默认；服务器上 TA 写的也只要求有 text，其余缺了认不出都补默认
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        id = (try? c.decode(String.self, forKey: .id)).flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
        author = (try? c.decode(FridgeAuthor.self, forKey: .author)) ?? .me
        x = (try? c.decode(Double.self, forKey: .x)) ?? 0.5
        y = (try? c.decode(Double.self, forKey: .y)) ?? 0.3
        tilt = (try? c.decode(Double.self, forKey: .tilt)) ?? 0
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        paper = (try? c.decode(FridgePaper.self, forKey: .paper)) ?? (author == .partner ? .lined : .yellow)
        attach = (try? c.decode(FridgeAttach.self, forKey: .attach)) ?? (author == .partner ? .washiStripe : .magnetBlue)
        font = (try? c.decode(FridgeNoteFont.self, forKey: .font)) ?? .kuaile
        fontSize = (try? c.decode(Double.self, forKey: .fontSize)) ?? 26
        decos = (try? c.decode(FridgeLossyArray<FridgeNoteDeco>.self, forKey: .decos))?.elements ?? []
        z = (try? c.decodeIfPresent(Double.self, forKey: .z)) ?? nil
    }
}

// MARK: - 内置贴纸库

enum FridgeFoodCategory: String, CaseIterable, Identifiable {
    case fruit, veggie, protein, dairy, meal, drink, frozen, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fruit: "水果"
        case .veggie: "蔬菜"
        case .protein: "肉蛋海鲜"
        case .dairy: "奶制品"
        case .meal: "主食熟食"
        case .drink: "饮品酱料"
        case .frozen: "冷冻"
        case .other: "自定义"
        }
    }
}

struct FridgeCatalogEntry: Identifiable {
    let asset: String
    let name: String
    let zone: FridgeZone
    let shelfDays: Int
    let unit: String
    var isDrink = false
    var id: String { asset }

    var category: FridgeFoodCategory {
        switch asset {
        case "strawberry", "blueberries", "grapes", "banana", "apple", "orange": .fruit
        case "lettuce", "tomato", "broccoli", "carrot", "cucumber", "bell_pepper", "mushroom", "potato", "onion": .veggie
        case "beef", "chicken", "fish", "shrimp", "bacon", "eggs": .protein
        case "yogurt", "cheese", "butter", "milk": .dairy
        case "rice", "noodles", "soup", "leftovers", "lunchbox", "bread": .meal
        case "juice", "soda", "water", "sauce", "glass_jar": .drink
        case "ice_cream", "frozen_dumplings", "frozen_meat": .frozen
        default: .other
        }
    }
}

enum FridgeCatalog {
    static let all: [FridgeCatalogEntry] = [
        .init(asset: "strawberry", name: "草莓", zone: .chillTop, shelfDays: 3, unit: "盒"),
        .init(asset: "blueberries", name: "蓝莓", zone: .chillTop, shelfDays: 5, unit: "盒"),
        .init(asset: "grapes", name: "葡萄", zone: .chillTop, shelfDays: 6, unit: "串"),
        .init(asset: "lettuce", name: "生菜", zone: .crisper, shelfDays: 4, unit: "颗"),
        .init(asset: "tomato", name: "西红柿", zone: .crisper, shelfDays: 7, unit: "个"),
        .init(asset: "broccoli", name: "西兰花", zone: .crisper, shelfDays: 5, unit: "颗"),
        .init(asset: "carrot", name: "胡萝卜", zone: .crisper, shelfDays: 14, unit: "根"),
        .init(asset: "cucumber", name: "黄瓜", zone: .crisper, shelfDays: 6, unit: "根"),
        .init(asset: "bell_pepper", name: "彩椒", zone: .crisper, shelfDays: 7, unit: "个"),
        .init(asset: "mushroom", name: "蘑菇", zone: .crisper, shelfDays: 4, unit: "盒"),
        .init(asset: "potato", name: "土豆", zone: .crisper, shelfDays: 20, unit: "个"),
        .init(asset: "onion", name: "洋葱", zone: .crisper, shelfDays: 20, unit: "个"),
        .init(asset: "apple", name: "苹果", zone: .crisper, shelfDays: 14, unit: "个"),
        .init(asset: "orange", name: "橙子", zone: .crisper, shelfDays: 14, unit: "个"),
        .init(asset: "banana", name: "香蕉", zone: .chillTop, shelfDays: 4, unit: "根"),
        .init(asset: "eggs", name: "鸡蛋", zone: .chillTop, shelfDays: 20, unit: "个"),
        .init(asset: "yogurt", name: "酸奶", zone: .chillTop, shelfDays: 7, unit: "杯"),
        .init(asset: "cheese", name: "芝士", zone: .chillTop, shelfDays: 20, unit: "块"),
        .init(asset: "butter", name: "黄油", zone: .chillTop, shelfDays: 30, unit: "块"),
        .init(asset: "beef", name: "牛肉", zone: .chillLow, shelfDays: 2, unit: "盒"),
        .init(asset: "chicken", name: "鸡肉", zone: .chillLow, shelfDays: 2, unit: "盒"),
        .init(asset: "fish", name: "鱼", zone: .chillLow, shelfDays: 1, unit: "块"),
        .init(asset: "shrimp", name: "虾", zone: .freezer, shelfDays: 60, unit: "袋"),
        .init(asset: "bacon", name: "培根", zone: .chillLow, shelfDays: 7, unit: "包"),
        .init(asset: "rice", name: "米饭", zone: .chillMid, shelfDays: 2, unit: "碗"),
        .init(asset: "noodles", name: "面条", zone: .chillMid, shelfDays: 3, unit: "份"),
        .init(asset: "soup", name: "汤", zone: .chillMid, shelfDays: 2, unit: "碗"),
        .init(asset: "leftovers", name: "剩菜盒", zone: .chillMid, shelfDays: 2, unit: "盒"),
        .init(asset: "lunchbox", name: "饭盒", zone: .chillMid, shelfDays: 2, unit: "盒"),
        .init(asset: "bread", name: "面包", zone: .chillMid, shelfDays: 5, unit: "袋"),
        .init(asset: "milk", name: "牛奶", zone: .doorMid, shelfDays: 5, unit: "瓶", isDrink: true),
        .init(asset: "juice", name: "果汁", zone: .doorMid, shelfDays: 5, unit: "瓶", isDrink: true),
        .init(asset: "soda", name: "汽水", zone: .doorLow, shelfDays: 90, unit: "罐", isDrink: true),
        .init(asset: "water", name: "矿泉水", zone: .doorLow, shelfDays: 180, unit: "瓶", isDrink: true),
        .init(asset: "sauce", name: "酱料", zone: .doorTop, shelfDays: 60, unit: "瓶"),
        .init(asset: "glass_jar", name: "果酱", zone: .doorTop, shelfDays: 30, unit: "罐"),
        .init(asset: "ice_cream", name: "冰淇淋", zone: .freezer, shelfDays: 60, unit: "盒"),
        .init(asset: "frozen_dumplings", name: "速冻水饺", zone: .freezer, shelfDays: 90, unit: "袋"),
        .init(asset: "frozen_meat", name: "冷冻肉", zone: .freezer, shelfDays: 90, unit: "块"),
        .init(asset: "paper_bag", name: "袋装", zone: .chillMid, shelfDays: 3, unit: "袋"),
        .init(asset: "unknown_food_box", name: "盒装", zone: .chillMid, shelfDays: 3, unit: "盒"),
    ]

    static func entry(_ asset: String) -> FridgeCatalogEntry? { all.first { $0.asset == asset } }
}

// MARK: - 到期文字（前端算，不画进图里）

enum FridgeDueTone { case overdue, today, soon, fine, none }

enum FridgeDue {
    static func daysLeft(_ item: FridgeItem, now: Date = Date()) -> Int? {
        guard let due = item.eatBy ?? item.expiresAt else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: due)).day
    }

    static func tone(_ item: FridgeItem) -> FridgeDueTone {
        guard let d = daysLeft(item) else { return .none }
        if d < 0 { return .overdue }
        if d == 0 { return .today }
        if d <= 2 { return .soon }
        return .fine
    }

    /// 「今天吃掉 / 还剩2天 / 周五前喝完」
    static func label(_ item: FridgeItem) -> String {
        guard let d = daysLeft(item), let due = item.eatBy ?? item.expiresAt else { return "不着急" }
        let verb = (FridgeCatalog.entry(item.stickerAsset)?.isDrink ?? false) ? "喝" : "吃"
        switch d {
        case ..<0: return "过期\(-d)天啦"
        case 0: return "今天\(verb)掉"
        case 1: return "明天\(verb)完"
        case 2...3: return "还剩\(d)天"
        case 4...6: return "\(weekday(due))前\(verb)完"
        default: return "还能放\(d)天"
        }
    }

    static func weekday(_ date: Date) -> String {
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return names[Calendar.current.component(.weekday, from: date) - 1]
    }

    static func color(_ tone: FridgeDueTone) -> Color {
        switch tone {
        case .overdue: Color(cpHex: "#C9524F")
        case .today: Color(cpHex: "#D9744A")
        case .soon: Color(cpHex: "#C98A2E")
        case .fine: Color(cpHex: "#6E9A6A")
        case .none: Color(cpHex: "#9A8A89")
        }
    }
}

// MARK: - 素材与字体

enum FridgeArt {
    private static let cache = NSCache<NSString, UIImage>()

    /// 拍照抠出来的贴纸存在 Application Support/FridgePhotos/<asset>.png
    static var photoDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("FridgePhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func sticker(for item: FridgeItem) -> UIImage? {
        guard item.stickerSource == .photo else { return image(item.stickerAsset, sticker: true) }
        let key = "p/\(item.stickerAsset)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let url = photoDirectory.appendingPathComponent(item.stickerAsset + ".png")
        guard let image = UIImage(contentsOfFile: url.path) else { return image("unknown_food_box", sticker: true) }
        cache.setObject(image, forKey: key)
        return image
    }

    static func savePhotoSticker(_ image: UIImage) -> String? {
        let name = "photo-" + UUID().uuidString
        guard let data = image.pngData() else { return nil }
        do {
            try data.write(to: photoDirectory.appendingPathComponent(name + ".png"), options: .atomic)
            return name
        } catch { return nil }
    }

    /// 拍立得 / 四格的原图：摆正后压到 maxSide 以内存 JPG（用 image.size，竖图不会压扁）
    static func savePhoto(_ source: UIImage, maxSide: CGFloat = 900) -> String? {
        let ratio = min(1, maxSide / max(source.size.width, source.size.height))
        let size = CGSize(width: source.size.width * ratio, height: source.size.height * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: size))
        }
        let name = "magnet-" + UUID().uuidString + ".jpg"
        guard let data = upright.jpegData(compressionQuality: 0.85) else { return nil }
        do {
            try data.write(to: photoDirectory.appendingPathComponent(name), options: .atomic)
            return name
        } catch { return nil }
    }

    /// 冰箱贴用的照片：文件名带扩展名（抠图贴是 photo-xxx，补 .png）
    static func photo(_ name: String) -> UIImage? {
        guard !name.isEmpty else { return nil }
        let file = name.contains(".") ? name : name + ".png"
        let key = "m/\(file)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = UIImage(contentsOfFile: photoDirectory.appendingPathComponent(file).path) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    static func deletePhoto(_ name: String) {
        let file = name.contains(".") ? name : name + ".png"
        try? FileManager.default.removeItem(at: photoDirectory.appendingPathComponent(file))
        cache.removeObject(forKey: "m/\(file)" as NSString)
    }

    static func image(_ name: String, sticker: Bool = false) -> UIImage? {
        let key = (sticker ? "s/" : "") + name as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let dir = sticker ? "Fridge/stickers" : "Fridge"
        guard let path = Bundle.main.path(forResource: name, ofType: "png", inDirectory: dir),
              let image = UIImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

enum FridgeFont {
    /// 站酷快乐体（SIL OFL 1.1，随 App 打包）。取不到就退回圆体
    static func cute(_ size: CGFloat) -> Font {
        if let font = UIFont(name: "ZCOOLKuaiLe-Regular", size: size) { return Font(font) }
        return .system(size: size, weight: .semibold, design: .rounded)
    }
}

// MARK: - 容错编解码（服务器那份 TA 也会写：缺字段补默认、坏一条跳一条，不让整包退回示例数据）

/// 数组里某一条解不出来就跳过，不让整个数组（进而整包）作废
struct FridgeLossyArray<Element: Decodable>: Decodable {
    var elements: [Element] = []

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            if let value = try? container.decode(Element.self) {
                elements.append(value)
            } else {
                _ = try? container.decode(FridgeSkippedJSON.self)
            }
        }
    }
}

/// 占位：把坏掉的那一条吃掉，让 unkeyedContainer 往前走
private struct FridgeSkippedJSON: Decodable {
    init(from decoder: Decoder) throws {}
}

enum FridgeJSON {
    /// 编码保持 JSONEncoder 默认（Date = 2001-01-01 起的秒数），旧本机存档和服务器工具都按这个写
    static let encoder = JSONEncoder()

    /// 解码容忍三种日期：默认的秒数、ISO8601 字符串、unix 秒（明显大于 2001 基准的数字）
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                // 2001 基准要到 2048 年才超过 15 亿，而 unix 秒 2017 年起就超过了：超过就当 unix 秒
                return seconds > 1_500_000_000 ? Date(timeIntervalSince1970: seconds) : Date(timeIntervalSinceReferenceDate: seconds)
            }
            if let text = try? container.decode(String.self) {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: text) { return date }
                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: text) { return date }
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "日期认不出来")
        }
        return decoder
    }()
}

// MARK: - Store（配了服务器就以服务器为准；本机 UserDefaults 是存档/镜像）
//
// 读：启动先回放本机镜像（没有就种示例），再从服务器 /api/fridge 拉；回前台再拉一次。
// 写：每个改动先落本地（页面立刻看到）→ 排进串行队列 → GET 服务器最新 → 把这次改动套上去 → PUT。
//     GET/PUT 失败就静默保留本地，不拿陈旧本地整包覆盖服务器（TA 的工具同样先读再写）。
//     队列里最后一个任务成功后才用「服务器最新+改动」回填本地，中间的不回填，免得把后续本地改动冲掉。

@MainActor
final class FridgeStore: ObservableObject {
    static let shared = FridgeStore()

    @Published private(set) var items: [FridgeItem] = []
    @Published private(set) var notes: [FridgeNote] = []
    @Published private(set) var magnets: [FridgeMagnet] = []
    /// 冰箱漆面颜色，nil = 原本的奶油色
    @Published private(set) var paintHex: String?
    /// 门外侧要不要自动贴「快到期」提醒
    @Published private(set) var showDoorReminders = true

    private let key = "fridge.v1"
    private let paintKey = "fridge.paint"
    private let remindersKey = "fridge.doorReminders"

    /// 服务器通用数据接口上的键；形状就是 Snapshot 的 JSON（照片字段只是本机文件名，照片本身不上传）
    /// 同步配置（设置页里填）：地址形如 https://example.com 或直接 .../api/fridge；token 走 Bearer
    @Published private(set) var syncBaseURL: String = UserDefaults.standard.string(forKey: "fridge.sync.url") ?? ""
    @Published private(set) var syncToken: String = UserDefaults.standard.string(forKey: "fridge.sync.token") ?? ""
    var syncEnabled: Bool { serverURL != nil }
    private var serverURL: URL? {
        var text = syncBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        if !text.hasSuffix("/api/fridge") { text += "/api/fridge" }
        return URL(string: text)
    }
    private let session: URLSession
    /// 排队中（含正在跑）的服务器任务数：==1 说明当前这个是最后一个，可以回填本地
    private var queued = 0
    private var chain: Task<Void, Never>?
    /// 第一次和服务器对上账之后置 true；之前服务器已有数据的话，要把本机原有的东西按 id 并进去，两边都不丢
    private let syncedKey = "fridge.syncedOnce"
    /// 这次启动本机没有存档、刚种的示例：服务器有数据就直接认服务器，不把示例并上去
    private var localIsFreshSample = false

    struct Snapshot: Codable {
        var items: [FridgeItem] = []
        var notes: [FridgeNote] = []
        var magnets: [FridgeMagnet] = []

        init(items: [FridgeItem], notes: [FridgeNote], magnets: [FridgeMagnet]) {
            self.items = items
            self.notes = notes
            self.magnets = magnets
        }

        // 三个数组都可缺（旧档没有 magnets；TA 写的可能只有 items），单条坏了只丢那一条
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            items = (try? c.decodeIfPresent(FridgeLossyArray<FridgeItem>.self, forKey: .items))??.elements ?? []
            notes = (try? c.decodeIfPresent(FridgeLossyArray<FridgeNote>.self, forKey: .notes))??.elements ?? []
            magnets = (try? c.decodeIfPresent(FridgeLossyArray<FridgeMagnet>.self, forKey: .magnets))??.elements ?? []
        }
    }

    private typealias Mutation = (inout Snapshot) -> Void

    private enum ServerJob {
        case refresh
        case push(Mutation)
    }

    private enum ServerValue {
        /// 服务器从没写过（value 是 null）
        case empty
        case snapshot(Snapshot)
    }

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        session = URLSession(configuration: configuration)

        if let data = UserDefaults.standard.data(forKey: key),
           let snap = try? FridgeJSON.decoder.decode(Snapshot.self, from: data) {
            items = snap.items
            notes = snap.notes
            magnets = snap.magnets
        } else {
            seedSample()
            localIsFreshSample = true
        }
        paintHex = UserDefaults.standard.string(forKey: paintKey)
        showDoorReminders = UserDefaults.standard.object(forKey: remindersKey) as? Bool ?? true

        enqueue(.refresh)
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// 从服务器拉一次最新（失败静默）。进页/回前台都会自动调，页面一般不用管
    func refresh() {
        enqueue(.refresh)
    }

    /// 保存同步设置；留空 = 关闭同步（纯本机）。保存后立刻对一次账
    func setSync(url: String, token: String) {
        syncBaseURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        syncToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(syncBaseURL, forKey: "fridge.sync.url")
        UserDefaults.standard.set(syncToken, forKey: "fridge.sync.token")
        syncedOnce = false
        refresh()
    }

    func setShowDoorReminders(_ on: Bool) {
        showDoorReminders = on
        UserDefaults.standard.set(on, forKey: remindersKey)
    }

    func setPaint(_ hex: String?) {
        paintHex = hex
        UserDefaults.standard.set(hex, forKey: paintKey)
    }

    func items(in zone: FridgeZone) -> [FridgeItem] {
        items.filter { $0.zone == zone }.sorted { $0.positionX < $1.positionX }
    }

    /// 门外侧自动贴出来的「快到期」提醒：两天内要吃掉的，最多 5 张
    var doorReminders: [FridgeItem] {
        guard showDoorReminders else { return [] }
        return items.filter { item in
            guard let d = FridgeDue.daysLeft(item) else { return false }
            return d <= 2
        }
        .sorted { (FridgeDue.daysLeft($0) ?? 0) < (FridgeDue.daysLeft($1) ?? 0) }
        .prefix(5).map { $0 }
    }

    /// 新放进来的排在这一格最前面，贴上去的动画才看得见（不会被 +N 收起来）
    func add(_ item: FridgeItem) {
        mutate { snap in
            var item = item
            item.positionX = (snap.items.filter { $0.zone == item.zone }.map(\.positionX).min() ?? 0) - 1
            snap.items.append(item)
        }
    }

    func update(_ item: FridgeItem) {
        guard items.contains(where: { $0.id == item.id }) else { return }
        mutate { snap in
            guard let index = snap.items.firstIndex(where: { $0.id == item.id }) else { return }
            var item = item
            if snap.items[index].zone != item.zone {
                item.positionX = (snap.items.filter { $0.zone == item.zone }.map(\.positionX).max() ?? 0) + 1
            }
            snap.items[index] = item
        }
    }

    /// 吃掉一份：还有剩就减一，吃完就整张揭下来
    @discardableResult
    func consume(_ id: String) -> Bool {
        guard let current = items.first(where: { $0.id == id }) else { return true }
        let gone = current.quantity <= 1
        mutate { snap in
            guard let index = snap.items.firstIndex(where: { $0.id == id }) else { return }
            if snap.items[index].quantity > 1 {
                snap.items[index].quantity -= 1
            } else {
                snap.items.remove(at: index)
            }
        }
        return gone
    }

    func remove(_ id: String) {
        mutate { snap in snap.items.removeAll { $0.id == id } }
    }

    func moveOnDoor(_ id: String, x: Double, y: Double) {
        guard items.contains(where: { $0.id == id }) else { return }
        mutate { snap in
            guard let index = snap.items.firstIndex(where: { $0.id == id }) else { return }
            snap.items[index].doorX = x
            snap.items[index].doorY = y
        }
    }

    func addNote(_ text: String, author: FridgeAuthor, style: FridgeNoteStyle) {
        let spots: [(Double, Double)] = [(0.62, 0.16), (0.36, 0.30), (0.66, 0.42), (0.40, 0.92)]
        let spot = spots[notes.count % spots.count]
        var note = FridgeNote(text: text, author: author, x: spot.0, y: spot.1, tilt: Double.random(in: -6...6))
        note.style = style
        mutate { snap in snap.notes.append(note) }
    }

    func restyleNote(_ id: String, style: FridgeNoteStyle) {
        guard notes.contains(where: { $0.id == id }) else { return }
        mutate { snap in
            guard let index = snap.notes.firstIndex(where: { $0.id == id }) else { return }
            snap.notes[index].style = style
        }
    }

    func addDeco(_ kind: FridgeDecoKind, to noteID: String) {
        guard notes.contains(where: { $0.id == noteID }) else { return }
        let deco = FridgeNoteDeco(kind: kind, x: Double.random(in: 150...200),
                                  y: Double.random(in: 90...130), tilt: Double.random(in: -15...15))
        mutate { snap in
            guard let index = snap.notes.firstIndex(where: { $0.id == noteID }) else { return }
            snap.notes[index].decos.append(deco)
        }
    }

    func moveDeco(_ decoID: String, in noteID: String, x: Double, y: Double) {
        mutate { snap in
            guard let n = snap.notes.firstIndex(where: { $0.id == noteID }),
                  let d = snap.notes[n].decos.firstIndex(where: { $0.id == decoID }) else { return }
            snap.notes[n].decos[d].x = x
            snap.notes[n].decos[d].y = y
        }
    }

    func rotateDeco(_ decoID: String, in noteID: String, tilt: Double) {
        // 收回 -180...180，转多圈也不会越存越大
        let wrapped = (tilt + 540).truncatingRemainder(dividingBy: 360) - 180
        mutate { snap in
            guard let n = snap.notes.firstIndex(where: { $0.id == noteID }),
                  let d = snap.notes[n].decos.firstIndex(where: { $0.id == decoID }) else { return }
            snap.notes[n].decos[d].tilt = wrapped
        }
    }

    func removeDeco(_ decoID: String, in noteID: String) {
        mutate { snap in
            guard let n = snap.notes.firstIndex(where: { $0.id == noteID }) else { return }
            snap.notes[n].decos.removeAll { $0.id == decoID }
        }
    }

    func moveNote(_ id: String, x: Double, y: Double) {
        guard notes.contains(where: { $0.id == id }) else { return }
        mutate { snap in
            guard let index = snap.notes.firstIndex(where: { $0.id == id }) else { return }
            snap.notes[index].x = x
            snap.notes[index].y = y
        }
    }

    func removeNote(_ id: String) {
        mutate { snap in snap.notes.removeAll { $0.id == id } }
    }

    /// 整台换回示例冰箱（服务器那份也一起换，TA 看到的和本机一致）
    func resetToSample() {
        let sample = Self.sampleSnapshot()
        mutate { snap in snap = sample }
    }

    /// 整台清空：食物、便签、门上的照片都拿掉（服务器那份一起清）。照片文件也删掉
    func clearAll() {
        for magnet in snapshot.magnets {
            for name in magnet.images ?? [] where !name.isEmpty { FridgeArt.deletePhoto(name) }
        }
        mutate { snap in snap = Snapshot(items: [], notes: [], magnets: []) }
    }

    // MARK: 门上的照片

    /// 落在门上半截随机位置，带一点歪
    func addMagnet(style: FridgeMagnet.Style, text: String, hex: String, images: [String]) {
        let magnet = FridgeMagnet(style: style, text: text, hex: hex,
                                  x: Double.random(in: 0.35...0.7), y: Double.random(in: 0.14...0.3),
                                  tilt: Double.random(in: -6...6), images: images)
        mutate { snap in snap.magnets.append(magnet) }
    }

    /// 编辑页里调好的整张（拍立得 / 四格）贴上去：位置随机落在门上半截
    func addMagnet(_ draft: FridgeMagnet) {
        var magnet = draft
        magnet.x = Double.random(in: 0.35...0.7)
        magnet.y = Double.random(in: 0.14...0.3)
        magnet.tilt = Double.random(in: -6...6)
        mutate { snap in snap.magnets.append(magnet) }
    }

    /// 编辑页改完存回去：照片、构图、相框、文字，位置不动
    func updateMagnet(_ edited: FridgeMagnet) {
        guard magnets.contains(where: { $0.id == edited.id }) else { return }
        mutate { snap in
            guard let index = snap.magnets.firstIndex(where: { $0.id == edited.id }) else { return }
            snap.magnets[index].images = edited.images
            snap.magnets[index].crops = edited.crops
            snap.magnets[index].hex = edited.hex
            snap.magnets[index].text = edited.text
            snap.magnets[index].pin = edited.pin
        }
    }

    /// 门上东西的上下顺序：放到最上面 / 最下面（便签和照片一起排）
    func layerDoorItem(_ id: String, toTop: Bool) {
        mutate { snap in
            let all = snap.notes.map { $0.z ?? 0 } + snap.magnets.map { $0.z ?? 1 }
            let target = toTop ? (all.max() ?? 0) + 1 : (all.min() ?? 0) - 1
            if let i = snap.notes.firstIndex(where: { $0.id == id }) { snap.notes[i].z = target }
            if let i = snap.magnets.firstIndex(where: { $0.id == id }) { snap.magnets[i].z = target }
        }
    }

    /// 门上那张照片整张转（拍立得 / 四格 / 抠图贴）
    func setMagnetTilt(_ id: String, tilt: Double) {
        guard magnets.contains(where: { $0.id == id }) else { return }
        let normalized = (tilt + 540).truncatingRemainder(dividingBy: 360) - 180
        mutate { snap in
            guard let index = snap.magnets.firstIndex(where: { $0.id == id }) else { return }
            snap.magnets[index].tilt = normalized
        }
    }

    func moveMagnet(_ id: String, x: Double, y: Double) {
        guard magnets.contains(where: { $0.id == id }) else { return }
        mutate { snap in
            guard let index = snap.magnets.firstIndex(where: { $0.id == id }) else { return }
            snap.magnets[index].x = x
            snap.magnets[index].y = y
        }
    }

    func removeMagnet(_ id: String) {
        // 照片只这一枚用，跟着删
        for name in magnets.first(where: { $0.id == id })?.images ?? [] where !name.isEmpty { FridgeArt.deletePhoto(name) }
        mutate { snap in snap.magnets.removeAll { $0.id == id } }
    }

    // MARK: 本地 + 服务器

    private var snapshot: Snapshot { Snapshot(items: items, notes: notes, magnets: magnets) }

    /// 改动先套在本地（页面立刻看到、镜像落盘），再排队推到服务器
    private func mutate(_ change: @escaping Mutation) {
        var snap = snapshot
        change(&snap)
        apply(snap)
        localIsFreshSample = false
        enqueue(.push(change))
    }

    private var syncedOnce: Bool {
        get { UserDefaults.standard.bool(forKey: syncedKey) }
        set { UserDefaults.standard.set(newValue, forKey: syncedKey) }
    }

    /// 首次接上服务器而服务器已经有东西：本机原有的（按 id 服务器没有的）并进去
    private func mergedWithLocal(_ server: Snapshot) -> Snapshot {
        var merged = server
        let itemIDs = Set(merged.items.map(\.id))
        merged.items += items.filter { !itemIDs.contains($0.id) }
        let noteIDs = Set(merged.notes.map(\.id))
        merged.notes += notes.filter { !noteIDs.contains($0.id) }
        let magnetIDs = Set(merged.magnets.map(\.id))
        merged.magnets += magnets.filter { !magnetIDs.contains($0.id) }
        return merged
    }

    private func apply(_ snap: Snapshot) {
        items = snap.items
        notes = snap.notes
        magnets = snap.magnets
        saveMirror(snap)
    }

    private func saveMirror(_ snap: Snapshot) {
        guard let data = try? FridgeJSON.encoder.encode(snap) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func enqueue(_ job: ServerJob) {
        guard syncEnabled else { return } // 没配服务器：纯本机
        queued += 1
        let previous = chain
        chain = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await self.run(job)
            self.queued -= 1
        }
    }

    private func run(_ job: ServerJob) async {
        let isLast = queued == 1
        switch job {
        case .refresh:
            guard let fetched = await fetchServer() else { return }
            switch fetched {
            case .empty:
                // 服务器从没写过：把本机这份先传上去，当作共用的起点
                if await putServer(snapshot) { syncedOnce = true }
            case .snapshot(let snap):
                if !syncedOnce && !localIsFreshSample {
                    let merged = mergedWithLocal(snap)
                    guard await putServer(merged) else { return }
                    syncedOnce = true
                    if isLast { apply(merged) }
                } else {
                    syncedOnce = true
                    if isLast { apply(snap) }
                }
            }
        case .push(let change):
            guard let fetched = await fetchServer() else { return } // GET 失败拒写，本地照旧
            var snap: Snapshot
            switch fetched {
            case .empty:
                snap = snapshot // 本地已经套过这次改动，整份作为首写
            case .snapshot(let latest):
                snap = syncedOnce ? latest : mergedWithLocal(latest)
                change(&snap)
            }
            guard await putServer(snap) else { return }
            syncedOnce = true
            if isLast { apply(snap) }
        }
    }

    private func fetchServer() async -> ServerValue? {
        guard let url = serverURL else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !syncToken.isEmpty { request.setValue("Bearer \(syncToken)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            guard let value = root["value"], !(value is NSNull) else { return .empty }
            // value 存在却不是对象 = 形状被写坏，当失败处理，不碰本地也不覆盖服务器
            guard value is [String: Any] else { return nil }
            let valueData = try JSONSerialization.data(withJSONObject: value)
            return .snapshot(try FridgeJSON.decoder.decode(Snapshot.self, from: valueData))
        } catch {
            return nil
        }
    }

    private func putServer(_ snap: Snapshot) async -> Bool {
        guard let url = serverURL else { return false }
        guard let body = try? FridgeJSON.encoder.encode(snap),
              let value = try? JSONSerialization.jsonObject(with: body),
              let payload = try? JSONSerialization.data(withJSONObject: ["value": value]) else { return false }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !syncToken.isEmpty { request.setValue("Bearer \(syncToken)", forHTTPHeaderField: "Authorization") }
        request.httpBody = payload
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return false }
            return true
        } catch {
            return false
        }
    }

    // MARK: 示例

    /// 只在本机没有任何存档时用；不推服务器（服务器有数据的话拉下来会盖掉）
    private func seedSample() {
        apply(Self.sampleSnapshot())
    }

    private static func sampleSnapshot() -> Snapshot {
        let now = Date()
        func make(_ asset: String, _ zone: FridgeZone, days: Int, qty: Double = 1,
                  name: String? = nil, by: FridgeAuthor = .me, note: String = "", added: Int = -1) -> FridgeItem {
            let entry = FridgeCatalog.entry(asset)
            let due = Calendar.current.date(byAdding: .day, value: days, to: now)
            return FridgeItem(name: name ?? entry?.name ?? asset, quantity: qty, unit: entry?.unit ?? "份",
                              zone: zone,
                              addedAt: Calendar.current.date(byAdding: .day, value: added, to: now) ?? now,
                              expiresAt: due.flatMap { Calendar.current.date(byAdding: .day, value: 1, to: $0) },
                              eatBy: due, stickerAsset: asset, notes: note, addedBy: by)
        }
        var seeded: [FridgeItem] = [
            make("frozen_dumplings", .freezer, days: 40, qty: 2),
            make("ice_cream", .freezerTop, days: 25, by: .partner, note: "给你囤的，一次只许吃两勺"),
            make("frozen_meat", .freezer, days: 30),
            make("shrimp", .freezer, days: 45),
            make("bacon", .freezerDoor, days: 20),
            make("yogurt", .chillTop, days: 2, qty: 3),
            make("strawberry", .chillTop, days: 1),
            make("eggs", .chillTop, days: 12, qty: 6),
            make("cheese", .chillTop, days: 9),
            make("leftovers", .chillMid, days: 1, name: "昨晚的红烧肉", by: .partner, note: "热一下就能吃"),
            make("lunchbox", .chillMid, days: 0, name: "午饭便当"),
            make("soup", .chillMid, days: 2),
            make("beef", .chillLow, days: 1),
            make("chicken", .chillLow, days: 3),
            make("lettuce", .crisper, days: 3),
            make("carrot", .crisper, days: 10, qty: 3),
            make("broccoli", .crisper, days: 4),
            make("tomato", .crisper, days: 5, qty: 4),
            make("cucumber", .crisper, days: 5, qty: 2),
            make("apple", .crisper, days: 12, qty: 5),
            make("sauce", .doorTop, days: 60),
            make("glass_jar", .doorTop, days: 30),
            make("milk", .doorMid, days: 2, by: .partner, note: "周五前喝完，不许又放过期"),
            make("juice", .doorMid, days: 5),
            make("water", .doorLow, days: 120, qty: 4),
            make("soda", .doorLow, days: 80, qty: 2),
        ]
        for zone in FridgeZone.allCases {
            var order = 0.0
            for index in seeded.indices where seeded[index].zone == zone {
                seeded[index].positionX = order
                order += 1
            }
        }
        let notes = [
            FridgeNote(text: "牛奶周五前喝完哦\n不许又放过期", author: .partner, x: 0.60, y: 0.15, tilt: 4,
                       paper: .lined, attach: .washiStripe),
            FridgeNote(text: "要买：\n鸡蛋 / 草莓 / 酸奶", author: .me, x: 0.38, y: 0.29, tilt: -5,
                       paper: .yellow, attach: .magnetBlue,
                       decos: [FridgeNoteDeco(kind: .heart, x: 186, y: 118, tilt: 12)]),
        ]
        return Snapshot(items: seeded, notes: notes, magnets: [])
    }
}

extension FridgeFont {
    /// 便签正文字体：快乐体 / 文楷是随包字体，圆体和系统用系统自带
    static func note(_ font: FridgeNoteFont, _ size: CGFloat) -> Font {
        switch font {
        case .kuaile: return cute(size)
        case .wenkai:
            if let ui = UIFont(name: "LXGWWenKaiLite-Medium", size: size) { return Font(ui) }
            return .system(size: size)
        // 圆体换成随包手写体（我爱万伟伟手写体）；rawValue 还叫 rounded，旧便签自动跟着换
        case .rounded:
            if let ui = UIFont(name: "WoAiWanWeiWeiShouXieTi-Regular", size: size) { return Font(ui) }
            return .system(size: size, weight: .medium, design: .rounded)
        case .system: return .system(size: size)
        }
    }
}
