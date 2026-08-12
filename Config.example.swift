import Foundation

// 使用方法:复制本文件为 Config.swift,填入真实 key(Config.swift 已被 .gitignore 排除)
enum Config {
    // ⚠️ 仅用于本地真机测试。
    // 正式上线时务必把 key 移到你自己的后端,App 端不要硬编码 key。

    // —— CardSight(TCG 类目:识别 + 查价)——
    static let cardSightKey = "YOUR_CARDSIGHT_API_KEY"
    static let cardSightBaseURL = "https://api.cardsight.ai"

    // —— Card Hedge(体育卡类目 Baseball/Basketball/Football)——
    static let apiKey = "YOUR_CARDHEDGE_API_KEY"
    static let baseURL = "https://api.cardhedger.com"
}
