import UIKit

// MARK: - 返回数据模型

struct ImageMatchResponse: Decodable {
    let success: Bool?
    let message: String?
    let best_match: BestMatch?
}

struct BestMatch: Decodable {
    let card_id: String?
    let description: String?
    let player: String?
    let set: String?
    let number: String?
    let variant: String?
    let image: String?
    let category: String?
    let similarity: String?   // 接口返回的是字符串,如 "67.35"
    let confidence: Double?   // 如 0.98
    let reasoning: String?
}

struct PricesResponse: Decodable {
    let prices: [PriceRow]?
}

struct PriceRow: Decodable, Identifiable {
    let card_id: String?
    let grade: String
    let grader: String?
    let price: String          // 接口返回字符串,如 "254.00"
    let display_order: String?  // 如 "1"、"-1"

    var id: String { grade }
    var orderValue: Int { Int(display_order ?? "999") ?? 999 }
}

// MARK: - 错误类型

enum CardHedgeError: LocalizedError {
    case encodeFailed
    case noMatch(String)
    case http(Int, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .encodeFailed:        return "Couldn't process the photo"
        case .noMatch(let m):      return m
        case .http(let c, let m):  return "Request failed (HTTP \(c))\(m.isEmpty ? "" : ": \(m)")"
        case .decoding(let m):     return "Couldn't parse the response: \(m)"
        }
    }
}

// MARK: - Card Hedge API 客户端

enum CardHedgeAPI {

    /// 缩放 + 压缩 + base64(Card Hedge 接口收 base64;原图过大会被拒,这里压到长边 1500px)
    static func encodeImage(_ image: UIImage, maxDimension: CGFloat = 1500, quality: CGFloat = 0.7) -> String? {
        let resized = image.resized(maxDimension: maxDimension)
        guard let data = resized.jpegData(compressionQuality: quality) else { return nil }
        return data.base64EncodedString()
    }

    private static func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        guard let url = URL(string: Config.baseURL + path) else {
            throw CardHedgeError.http(0, "URL 错误")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 90   // image-match 冷调用实测 14~49s,30s 会超时
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Config.apiKey, forHTTPHeaderField: "X-API-Key")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw CardHedgeError.http(0, "无响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw CardHedgeError.http(http.statusCode, String(msg.prefix(120)))
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw CardHedgeError.decoding(error.localizedDescription)
        }
    }

    /// 第①步:拍照识别 → 返回最佳匹配卡
    static func identify(_ image: UIImage) async throws -> BestMatch {
        guard let b64 = encodeImage(image) else { throw CardHedgeError.encodeFailed }
        let resp: ImageMatchResponse = try await post(
            "/v1/cards/image-match",
            body: ["image_base64": b64, "k": 5]
        )
        guard let match = resp.best_match, (match.card_id?.isEmpty == false) else {
            throw CardHedgeError.noMatch(resp.message ?? "Couldn't recognize this card — try a sharper, straight-on photo")
        }
        return match
    }

    /// 第②步:用 card_id 查各评级最新价格
    static func prices(cardId: String) async throws -> [PriceRow] {
        let resp: PricesResponse = try await post(
            "/v1/cards/all-prices-by-card",
            body: ["card_id": cardId]
        )
        return (resp.prices ?? []).sorted { $0.orderValue < $1.orderValue }
    }
}

// MARK: - 图片缩放工具

extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - CardSight 数据模型

struct CSIdentifyResponse: Decodable {
    let success: Bool?
    let requestId: String?        // 可用于 POST /v1/feedback/identify/{id} 上报识别错误
    let detections: [CSDetection]?
    let processingTime: Double?   // 服务端处理耗时(毫秒)
}

struct CSDetection: Decodable {
    let confidence: String?       // "High"(90-100%) / "Medium"(75-89%) / "Low"(50-74%)
    let card: CSCard?
}

struct CSCard: Decodable {
    let id: String?               // 仅"精确到卡"时有;只匹配到 set 级时为空
    let name: String?
    let number: String?
    let year: String?
    let manufacturer: String?
    let releaseName: String?
    let setName: String?
    let attributes: [String]?     // 如 "pokemon-holo-rare"
    let fields: [CSField]?        // ⚠️ 实测是 [{key,value}] 数组,不是 OpenAPI 里写的字典
    let parallel: CSParallel?             // 识别出的平行卡/异画变体
    let suggestions: [CSSuggestion]?      // 多个再版得分接近时的备选卡

    /// 按 key 取字段值,如 field("CARD_LANGUAGE") → "ja"
    func field(_ key: String) -> String? {
        fields?.first { $0.key == key }?.value?.text
    }
}

struct CSField: Decodable {
    let key: String?
    let value: CSFieldValue?
}

/// 字段值兼容字符串/数字/布尔,统一转字符串
struct CSFieldValue: Decodable {
    let text: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { text = s }
        else if let d = try? c.decode(Double.self) {
            text = d == d.rounded() ? String(Int(d)) : String(d)
        } else if let b = try? c.decode(Bool.self) { text = b ? "Yes" : "No" }
        else { text = "" }
    }
}

struct CSParallel: Decodable {
    let id: String?
    let name: String?
    let description: String?
}

struct CSSuggestion: Decodable {
    let id: String?
    let setName: String?
    let fields: [CSField]?
}

struct CSPricingResponse: Decodable {
    let raw: CSRawBlock?              // 未评级(Raw)成交
    let graded: [CSGradedCompany]?    // 按评级公司分组的成交
    let meta: CSMeta?
}

struct CSRawBlock: Decodable {
    let count: Int?
    let records: [CSSaleRecord]?
}

struct CSSaleRecord: Decodable {
    let title: String?
    let price: Double?
    let date: String?             // ISO 8601
    let source: String?           // "ebay"
    let listing_type: String?     // "auction" / "fixed"
}

struct CSGradedCompany: Decodable {
    let company_name: String?     // "PSA" / "BGS" / "CGC"…
    let grades: [CSGradeBlock]?
}

struct CSGradeBlock: Decodable {
    let grade_value: String?      // "10" / "9.5" / "8"…
    let count: Int?
    let records: [CSSaleRecord]?
}

struct CSMeta: Decodable {
    let total_records: Int?
    let last_sale_date: String?
}

// MARK: - CardSight API 客户端(当前启用)

enum CardSightAPI {

    /// 网关实测上限 1MB(2026-08 实测:972KB 通过、1.12MB 413;文档写 20MB 不可信)
    private static let identifyMaxBytes = 900_000

    /// 压到 1MB 网关上限内,同时尽量保住分辨率:先试 2200px 高质量,超了逐级降质量、再降尺寸
    static func encodeForIdentify(_ image: UIImage) -> Data? {
        var dimension: CGFloat = 2200
        while dimension >= 1000 {
            let resized = image.resized(maxDimension: dimension)
            for q: CGFloat in [0.85, 0.7, 0.55] {
                if let d = resized.jpegData(compressionQuality: q), d.count <= identifyMaxBytes {
                    return d
                }
            }
            dimension -= 400
        }
        return image.resized(maxDimension: 800).jpegData(compressionQuality: 0.5)
    }

    /// 第①步:拍照识别(原始 JPEG 二进制直传,实测 ~0.8s)
    /// segment 传 "pokemon"/"baseball"/"magic" 等可锁定类目提升准确度;nil = 自动检测
    static func identify(_ image: UIImage, segment: String? = nil) async throws -> CSIdentifyResponse {
        guard let data = encodeForIdentify(image) else {
            throw CardHedgeError.encodeFailed
        }
        var path = "/v1/identify/card"
        if let segment,
           let enc = segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
            path += "/" + enc
        }
        guard let url = URL(string: Config.cardSightBaseURL + path) else {
            throw CardHedgeError.http(0, "URL error")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.setValue(Config.cardSightKey, forHTTPHeaderField: "X-API-Key")
        req.setValue("CardScanner/1.0 iOS", forHTTPHeaderField: "User-Agent")
        req.httpBody = data

        let (respData, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw CardHedgeError.http(0, "无响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            // segment 名不被认可时自动退回全类目识别
            if segment != nil, http.statusCode == 404 {
                return try await identify(image, segment: nil)
            }
            let msg = String(data: respData, encoding: .utf8) ?? ""
            throw CardHedgeError.http(http.statusCode, String(msg.prefix(120)))
        }
        let decoded: CSIdentifyResponse
        do {
            decoded = try JSONDecoder().decode(CSIdentifyResponse.self, from: respData)
        } catch {
            throw CardHedgeError.decoding(error.localizedDescription)
        }
        // set 级匹配(有 setName 无卡 id)也放行,由界面提示"具体卡未确定"
        guard let first = decoded.detections?.first,
              first.card?.id != nil || first.card?.setName != nil || first.card?.name != nil else {
            throw CardHedgeError.noMatch("Couldn't recognize this card — try a sharper, straight-on photo")
        }
        return decoded
    }

    /// 第②步:用 card_id 查成交记录(Raw + 各评级)
    static func pricing(cardId: String, limit: Int = 20) async throws -> CSPricingResponse {
        guard var comps = URLComponents(string: Config.cardSightBaseURL + "/v1/pricing/\(cardId)") else {
            throw CardHedgeError.http(0, "URL 错误")
        }
        comps.queryItems = [
            URLQueryItem(name: "period", value: "all"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        guard let url = comps.url else { throw CardHedgeError.http(0, "URL 错误") }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        req.setValue(Config.cardSightKey, forHTTPHeaderField: "X-API-Key")
        req.setValue("CardScanner/1.0 iOS", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw CardHedgeError.http(0, "无响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw CardHedgeError.http(http.statusCode, String(msg.prefix(120)))
        }
        do {
            return try JSONDecoder().decode(CSPricingResponse.self, from: data)
        } catch {
            throw CardHedgeError.decoding(error.localizedDescription)
        }
    }
}
