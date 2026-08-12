import SwiftUI
import UIKit

// MARK: - 设计规范(深色现代风:近黑底 + 祖母绿渐变强调)

enum UI {
    static let accent = Color(red: 0.20, green: 0.84, blue: 0.55)
    static let accentGradient = LinearGradient(
        colors: [Color(red: 0.20, green: 0.84, blue: 0.55),
                 Color(red: 0.10, green: 0.66, blue: 0.74)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let pageBG = Color(red: 0.043, green: 0.055, blue: 0.051)
    static let cardBG = Color(red: 0.090, green: 0.110, blue: 0.102)
    static let hairline = Color.white.opacity(0.08)
    static let chipBG = Color.white.opacity(0.06)

    /// PriceCharting 的评级配色:10 橙、9.5 红、9 蓝、8 绿、Raw 黄
    static func gradeColor(_ grade: String) -> Color {
        let g = grade.lowercased()
        if g.contains("10") { return .orange }
        if g.contains("9.5") { return .red }
        if g.contains("9") { return .blue }
        if g.contains("8") { return .green }
        if g.contains("raw") || g.contains("ungraded") {
            return Color(red: 0.93, green: 0.74, blue: 0.05)
        }
        return .gray
    }

    /// 5505.0 → "$5,505",39.14 → "$39.14"
    static func money(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencySymbol = "$"
        let noCents = v >= 1000
        f.maximumFractionDigits = noCents ? 0 : 2
        f.minimumFractionDigits = noCents ? 0 : 2
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}

// MARK: - 通用卡片容器样式

private extension View {
    func panel() -> some View {
        self
            .padding(16)
            .background(UI.cardBG, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(UI.hairline, lineWidth: 1)
            )
    }
}

// MARK: - 主界面(打开即扫:常驻相机 + 卡框 + 快门,结果用底部弹层)

struct ContentView: View {
    @StateObject private var camera = CardCameraController()

    @State private var image: UIImage?
    @State private var detection: CSDetection?
    @State private var pricing: CSPricingResponse?
    @State private var isLoading = false
    @State private var statusMessage: String?
    @State private var isError = false
    @State private var isCapturing = false
    @State private var activeSheet: ActiveSheet?

    /// 锁定识别类目可显著减少跨类目误判;"auto" = 自动检测
    @AppStorage("scanSegment") private var scanSegment = "auto"
    @State private var activeCardId: String?   // 当前展示价格的卡(可切到备选卡)
    @State private var chPrices: [PriceRow] = []   // Card Hedge 各评级市场价(体育卡类目)

    /// 体育卡类目走 Card Hedge(识别+价格);其余走 CardSight
    private var isSportsSegment: Bool {
        ["baseball", "basketball", "football"].contains(scanSegment)
    }

    private enum ActiveSheet: String, Identifiable {
        case library, results
        var id: String { rawValue }
    }

    private static let segments: [(label: String, value: String)] = [
        ("Auto Detect", "auto"),
        ("Pokémon", "pokemon"),
        ("Magic", "magic"),
        ("One Piece", "one piece"),
        ("Baseball", "baseball"),
        ("Basketball", "basketball"),
        ("Football", "football"),
        ("Hockey", "hockey"),
    ]

    private var segmentLabel: String {
        Self.segments.first { $0.value == scanSegment }?.label ?? "Auto Detect"
    }

    /// ⚠️ GeometryReader 加了 .ignoresSafeArea() 后 geo.safeAreaInsets 恒为 0,
    /// 真实安全区必须从窗口取,否则标题会被顶进刘海区
    private var windowInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.keyWindow?.safeAreaInsets ?? .zero
    }

    var body: some View {
        // GeometryReader 覆盖全屏,保证卡框坐标与 previewLayer 坐标一致(裁剪才准)
        GeometryReader { geo in
            let insets = windowInsets
            // 标题区之下、快门区之上的可用高度,框高自适应不挤压两端
            let topOffset = insets.top + 112
            let bottomReserved = insets.bottom + 150
            let maxH = max(200, geo.size.height - topOffset - bottomReserved)
            // 竖版标准卡牌比例 63:88,框宽最多取屏宽 72%
            let w = min(geo.size.width * 0.72, maxH * 63.0 / 88.0)
            let h = w * 88.0 / 63.0
            let hole = CGRect(x: (geo.size.width - w) / 2,
                              y: topOffset,
                              width: w, height: h)

            ZStack {
                Color.black
                CameraPreview(controller: camera)

                CutoutMask(hole: hole, cornerRadius: 18)
                    .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))

                CameraCorners(length: 26)
                    .stroke(UI.accentGradient,
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                    .frame(width: hole.width, height: hole.height)
                    .position(x: hole.midX, y: hole.midY)

                Text("Fit the card inside the frame")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.45), in: Capsule())
                    .position(x: hole.midX, y: hole.maxY + 32)

                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 16)
                        .padding(.top, insets.top + 8)
                    Spacer()
                    bottomBar(hole: hole)
                        .padding(.bottom, insets.bottom + 22)
                }

                if camera.isDenied { deniedCard(center: CGPoint(x: hole.midX, y: hole.midY)) }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .tint(UI.accent)
        .onAppear { camera.configure() }
        .sheet(item: $activeSheet) { which in
            switch which {
            case .library:
                PhotoLibraryPicker { handlePicked($0) }
            case .results:
                resultsSheet
            }
        }
    }

    // MARK: - 顶部标题 + 类目锁定

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AI SCAN TO CHECK PRICE")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.6)
                    .foregroundStyle(UI.accent)
                Text("Card Scanner")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Spacer()
            Menu {
                ForEach(Self.segments, id: \.value) { seg in
                    Button {
                        scanSegment = seg.value
                    } label: {
                        if seg.value == scanSegment {
                            Label(seg.label, systemImage: "checkmark")
                        } else {
                            Text(seg.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "square.grid.2x2")
                        .font(.caption2)
                    Text(segmentLabel)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(scanSegment == "auto" ? Color.white.opacity(0.85) : UI.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.black.opacity(0.45), in: Capsule())
                .overlay(Capsule().strokeBorder(
                    scanSegment == "auto" ? Color.white.opacity(0.15) : UI.accent.opacity(0.5), lineWidth: 1))
            }
        }
    }

    // MARK: - 底部操作区(相册 / 快门 / 上次结果)

    private func bottomBar(hole: CGRect) -> some View {
        HStack {
            // 相册
            Button {
                activeSheet = .library
            } label: {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.black.opacity(0.45), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
            }

            Spacer()

            // 快门
            Button {
                capture(hole: hole)
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(.white, lineWidth: 4)
                        .frame(width: 76, height: 76)
                    Circle()
                        .fill(.white)
                        .frame(width: 62, height: 62)
                }
                .opacity(isCapturing || isLoading ? 0.5 : 1)
            }
            .disabled(isCapturing || !CardCameraController.isAvailable)

            Spacer()

            // 上次结果(有识别结果时可重新打开弹层)
            Button {
                activeSheet = .results
            } label: {
                Image(systemName: "tag")
                    .font(.title3)
                    .foregroundStyle(detection == nil ? Color.white.opacity(0.3) : .white)
                    .frame(width: 48, height: 48)
                    .background(.black.opacity(0.45), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
            }
            .disabled(detection == nil)
        }
        .padding(.horizontal, 36)
    }

    private func deniedCard(center: CGPoint) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "video.slash.fill")
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.7))
            Text("Camera unavailable")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Allow camera access, or pick a photo from the library")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(22)
        .frame(maxWidth: 280)
        .background(UI.cardBG, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .position(center)
    }

    // MARK: - 结果弹层

    private var resultsSheet: some View {
        ZStack {
            UI.pageBG.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: UI.accent.opacity(0.18), radius: 14, x: 0, y: 6)
                            .frame(maxWidth: .infinity)
                    }
                    if isLoading { loadingCard }
                    if let statusMessage { statusCard(statusMessage) }
                    if let detection, let card = detection.card {
                        resultCard(card, confidence: detection.confidence)
                    }
                    if !rawRecords.isEmpty { rawSalesCard }
                    if !gradedRows.isEmpty { gradedCard }
                    if !chPrices.isEmpty { chPricesCard }
                }
                .padding(16)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isLoading)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: pricing?.meta?.total_records)
            }
            .scrollIndicators(.hidden)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - 状态卡片

    private var loadingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(isSportsSegment
                 ? "Identifying via Card Hedge — can take up to a minute…"
                 : "Identifying card…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .panel()
    }

    private func statusCard(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(isError ? Color.red : UI.accent)
            Text(text)
                .font(.callout)
                .foregroundStyle(isError ? Color.red : Color.secondary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    // MARK: - 识别结果卡片

    private func resultCard(_ c: CSCard, confidence: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(c.name ?? "Unknown Card")
                .font(.title2.bold())
                .foregroundStyle(.white)
            let sub = subtitle(c)
            if !sub.isEmpty {
                Text(sub)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let n = c.number, !n.isEmpty { chip("#" + n, tint: .gray) }
                    if let conf = confidence { confidenceChip(conf) }
                    // 印刷语言(非英文时提示,如日版 "JA Print")
                    if let lang = c.field("CARD_LANGUAGE")?.lowercased(),
                       !lang.isEmpty, lang != "en" {
                        chip("\(lang.uppercased()) Print", tint: .blue)
                    }
                    // 平行卡/异画变体
                    if let p = c.parallel?.name, !p.isEmpty {
                        chip(p, tint: .purple)
                    }
                    ForEach((c.attributes ?? []).prefix(3), id: \.self) { a in
                        chip(prettyAttr(a), tint: .gray)
                    }
                }
            }

            // 多个再版得分接近时给备选,点按切换价格
            if let sugs = c.suggestions, !sugs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SIMILAR PRINTS — TAP TO SWITCH")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    suggestionRow(id: c.id, label: c.setName ?? "Current match")
                    ForEach(Array(sugs.enumerated()), id: \.offset) { _, s in
                        suggestionRow(id: s.id, label: s.setName ?? "Alternative print")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func suggestionRow(id: String?, label: String) -> some View {
        let isActive = id != nil && id == activeCardId
        return Button {
            guard let id, id != activeCardId else { return }
            Task { await loadPricing(cardId: id) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline)
                    .foregroundStyle(isActive ? UI.accent : Color.secondary)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(isActive ? .white : Color.secondary)
                Spacer()
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 10)
            .background(isActive ? UI.accent.opacity(0.10) : .clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func subtitle(_ c: CSCard) -> String {
        var parts: [String] = []
        if let y = c.year, !y.isEmpty { parts.append(y) }
        if let m = c.manufacturer, !m.isEmpty { parts.append(m) }
        if let r = c.releaseName, !r.isEmpty { parts.append(r) }
        if let s = c.setName, !s.isEmpty, s != c.releaseName { parts.append(s) }
        return parts.joined(separator: " · ")
    }

    /// "pokemon-holo-rare" → "Holo Rare"
    private func prettyAttr(_ a: String) -> String {
        var parts = a.split(separator: "-").map(String.init)
        if parts.count > 1 { parts.removeFirst() }
        return parts.map { $0.capitalized }.joined(separator: " ")
    }

    private func confidenceChip(_ conf: String) -> some View {
        let (label, tint): (String, Color) = {
            switch conf.lowercased() {
            case "high":   return ("High match", UI.accent)
            case "medium": return ("Medium match", .orange)
            case "low":    return ("Low match", .red)
            default:       return (conf, .gray)
            }
        }()
        return chip(label, tint: tint)
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint == .gray ? UI.chipBG : tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint == .gray ? Color.secondary : tint)
    }

    // MARK: - 价格数据整理

    private var rawRecords: [CSSaleRecord] {
        (pricing?.raw?.records ?? []).sorted { ($0.date ?? "") > ($1.date ?? "") }
    }

    private var gradedRows: [(label: String, count: Int, price: Double?)] {
        guard let companies = pricing?.graded else { return [] }
        var rows: [(label: String, count: Int, price: Double?)] = []
        for c in companies {
            for g in (c.grades ?? []) {
                let label = [c.company_name, g.grade_value]
                    .compactMap { $0 }
                    .joined(separator: " ")
                let latest = g.records?
                    .sorted { ($0.date ?? "") > ($1.date ?? "") }
                    .first?.price
                rows.append((label, g.count ?? g.records?.count ?? 0, latest))
            }
        }
        return rows.sorted { ($0.price ?? 0) > ($1.price ?? 0) }
    }

    private func dateStr(_ iso: String?) -> String {
        String((iso ?? "").prefix(10))
    }

    private func typeLabel(_ t: String?) -> String {
        switch t {
        case "auction": return "Auction"
        case "fixed":   return "Buy It Now"
        default:        return t ?? ""
        }
    }

    private func sectionHeader(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            Text(trailing)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func hairlineDivider() -> some View {
        Rectangle().fill(UI.hairline).frame(height: 1)
    }

    // MARK: - 未评级近期成交

    private var rawSalesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Recent Sales · Raw", trailing: "USD")

            // 最近一笔:渐变大字突出
            if let top = rawRecords.first, let price = top.price {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("LATEST SALE")
                            .font(.caption2.weight(.semibold))
                            .tracking(1.2)
                            .foregroundStyle(.secondary)
                        Text("\(typeLabel(top.listing_type)) · \(dateStr(top.date))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(UI.money(price))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(UI.accentGradient)
                        .monospacedDigit()
                }
                .padding(.vertical, 2)
            }

            // 其余成交:细分隔线行
            if rawRecords.count > 1 {
                VStack(spacing: 0) {
                    ForEach(Array(rawRecords.dropFirst().prefix(6).enumerated()), id: \.offset) { idx, r in
                        if idx > 0 { hairlineDivider() }
                        HStack {
                            Text(dateStr(r.date))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(typeLabel(r.listing_type))
                                .font(.caption2)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(UI.chipBG, in: Capsule())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(UI.money(r.price ?? 0))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 11)
                    }
                }
            }

            if let total = pricing?.meta?.total_records {
                Text("Source: eBay sold listings · \(total) records")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .panel()
    }

    // MARK: - Card Hedge 各评级市场价(体育卡类目)

    private var chPricesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Market Value by Grade", trailing: "Card Hedge · USD")

            VStack(spacing: 0) {
                ForEach(Array(chPrices.enumerated()), id: \.offset) { idx, row in
                    if idx > 0 { hairlineDivider() }
                    HStack {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(UI.gradeColor(chRowLabel(row)))
                                .frame(width: 9, height: 9)
                            Text(chRowLabel(row))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        if let p = Double(row.price) {
                            Text(UI.money(p))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                        } else {
                            Text(row.price)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(.vertical, 11)
                }
            }
        }
        .panel()
    }

    private func chRowLabel(_ r: PriceRow) -> String {
        var parts: [String] = []
        if let g = r.grader, !g.isEmpty { parts.append(g) }
        parts.append(r.grade)
        return parts.joined(separator: " ")
    }

    // MARK: - 评级卡成交

    private var gradedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Graded Sales", trailing: "Latest · USD")

            VStack(spacing: 0) {
                ForEach(Array(gradedRows.enumerated()), id: \.offset) { idx, row in
                    if idx > 0 { hairlineDivider() }
                    HStack {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(UI.gradeColor(row.label))
                                .frame(width: 9, height: 9)
                            Text(row.label)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                        }
                        if row.count > 1 {
                            Text("×\(row.count)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if let p = row.price {
                            Text(UI.money(p))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                        }
                    }
                    .padding(.vertical, 11)
                }
            }
        }
        .panel()
    }

    // MARK: - 逻辑

    private func capture(hole: CGRect) {
        guard !isCapturing else { return }
        isCapturing = true
        camera.capture(guideRect: hole) { img in
            isCapturing = false
            if let img { handlePicked(img) }
        }
    }

    private func handlePicked(_ img: UIImage) {
        image = img
        detection = nil
        pricing = nil
        chPrices = []
        statusMessage = nil
        isError = false
        activeCardId = nil
        activeSheet = .results
        Task { await scan(img) }
    }

    @MainActor
    private func scan(_ img: UIImage) async {
        isLoading = true
        defer { isLoading = false }
        do {
            // 体育卡类目:识别+价格全走 Card Hedge
            if isSportsSegment {
                let match = try await CardHedgeAPI.identify(img)
                detection = mapCHMatch(match)
                guard let cid = match.card_id else {
                    statusMessage = "Couldn't pin down the exact card — try a closer photo"
                    return
                }
                activeCardId = cid
                let rows = try await CardHedgeAPI.prices(cardId: cid)
                chPrices = rows
                if rows.isEmpty {
                    statusMessage = "Card identified, but no price data available"
                }
                return
            }

            let segment = scanSegment == "auto" ? nil : scanSegment
            let resp = try await CardSightAPI.identify(img, segment: segment)
            detection = resp.detections?.first
            if let n = resp.detections?.count, n > 1 {
                statusMessage = "\(n) cards detected — showing the first match"
                isError = false
            }
            guard let cid = detection?.card?.id else {
                // set 级匹配:认出了系列但没锁定到具体卡
                statusMessage = "Set recognized, but not the exact card — try a closer, straight-on photo filling the frame"
                isError = false
                return
            }
            activeCardId = cid
            await loadPricing(cardId: cid)
        } catch {
            isError = true
            statusMessage = error.localizedDescription
        }
    }

    /// 把 Card Hedge 的识别结果映射进现有结果卡片模型
    private func mapCHMatch(_ m: BestMatch) -> CSDetection {
        let conf: String? = {
            guard let c = m.confidence else { return nil }
            if c >= 0.9 { return "High" }
            if c >= 0.75 { return "Medium" }
            return "Low"
        }()
        let card = CSCard(id: m.card_id,
                          name: m.player ?? m.description,
                          number: m.number,
                          year: nil, manufacturer: nil,
                          releaseName: m.set,
                          setName: m.variant,
                          attributes: nil, fields: nil, parallel: nil, suggestions: nil)
        return CSDetection(confidence: conf, card: card)
    }

    @MainActor
    private func loadPricing(cardId: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let p = try await CardSightAPI.pricing(cardId: cardId)
            pricing = p
            activeCardId = cardId
            let hasRaw = !(p.raw?.records ?? []).isEmpty
            let hasGraded = (p.graded ?? []).contains { c in
                (c.grades ?? []).contains { !($0.records ?? []).isEmpty }
            }
            if !hasRaw && !hasGraded {
                statusMessage = "Card identified, but no sales data yet — common for brand-new sets and low-volume cards"
                isError = false
            } else {
                statusMessage = nil
            }
        } catch {
            isError = true
            statusMessage = error.localizedDescription
        }
    }
}

#Preview {
    ContentView()
}
