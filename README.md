# CardScanner —— 拍照识卡 + 查价（当前使用 CardSight API）

拍照或选图 → CardSight 识别卡牌（实测 ~0.8s）→ 显示未评级近期成交 + 各评级最近成交价。

## 运行到手机上（3 步）

> 从 git 克隆的话先做第 0 步：复制 `Config.example.swift` 为 `Config.swift`，填入两个 API key（`Config.swift` 不进 git）。

1. **打开工程**：双击 `CardScanner.xcodeproj`（Xcode 打开）。
2. **配置签名**：
   - 左侧选中蓝色的 `CardScanner` 项目 → TARGETS 里的 `CardScanner` → 顶部 **Signing & Capabilities**。
   - 勾选 **Automatically manage signing**，**Team** 选你的 Apple ID（没有就点 Add an Account 登录，免费 Apple ID 即可）。
   - 如果 Bundle Identifier `com.lin.cardscanner` 报冲突，随便改成唯一的。
3. **连手机运行**：设备选你的 iPhone，按 **▶ Run**。

> 免费 Apple ID 签的 App 有效期 7 天，过期重新 Run 一下即可。

## 怎么用

- **打开即扫**：进 App 摄像头直接开启，中间是 63:88 竖版卡片取景框，把卡对进框里按快门。
- 底部三个键：相册（左）、**快门**（中）、上次结果（右）。
- 拍完自动：裁剪框内区域 → CardSight 识别（约 1 秒）→ 底部弹层显示结果（可上滑拉全屏）。
- 弹层内容：卡名/年份/系列/置信度/语言/平行卡 + 「Recent Sales · Raw」（最近一笔渐变大字 + 成交列表）+「Graded Sales」（PSA/BGS/CGC 按档位）。
- 界面为**深色现代风、全英文**（暗底 + 祖母绿渐变强调）。

## 文件说明

- `Config.swift` —— **两个 API key 都在这里**（CardSight：默认类目；Card Hedge：Baseball/Basketball/Football 类目）。⚠️ 硬编码仅供本地测试，正式上线要移到自己后端。
- **类目分流**：右上角选 Baseball/Basketball/Football 时识别+价格走 Card Hedge（image-match 冷调用 14~49s，慢是已知的；价格是各评级市场价）；其余类目走 CardSight（0.8s，价格是逐笔成交）。
- `CardHedgeAPI.swift` —— 网络层：CardSight 识别 + 查价（当前启用）；Card Hedge 识别 + 查价（保留备用，想切回改 ContentView 的 scan() 即可）。
- `ImagePickers.swift` —— 自定义拍卡相机（卡片取景框引导，**只裁剪框内区域送识别**）+ 相册选图。
- `ContentView.swift` —— 界面（深色现代风、全英文）。
- `CardScannerApp.swift` —— App 入口。

## 接口（已实测可用）

**CardSight（当前）**
- 识别：`POST https://api.cardsight.ai/v1/identify/card`，原始 JPEG 二进制直传，头 `X-API-Key`，实测 ~0.8s
- 查价：`GET .../v1/pricing/{card_id}?period=all&limit=20`，返回 raw（未评级成交）+ graded（按评级公司/档位）+ meta

**Card Hedge（备用）**
- 识别：`POST https://api.cardhedger.com/v1/cards/image-match`（慢，14~49s，带 LLM 推理）或 `/image-search`（~7s）
- 查价：`POST .../v1/cards/all-prices-by-card`

## 提升识别准确度（已内置）

- **类目锁定**：右上角菜单选 Pokémon/Baseball 等后走 `/v1/identify/card/{segment}`，避免跨类目误判（选错类目返回 404 时自动退回全类目）。
- **高清上传（自适应）**：优先 2200px/0.85 保细节；⚠️ 网关实测上限 **1MB**（972KB 过 / 1.12MB 413，文档写 20MB 不可信），超限自动逐级降质量→降尺寸，保证不再 413。
- **备选再版**：接口返回 `suggestions`（多个再版得分接近）时，结果卡片里可点按切换到正确的版本重新查价。
- **语言/平行卡**：显示 `CARD_LANGUAGE`（如 JA Print）和平行卡名。日版卡若其 set 未入库，官方行为是返回美版记录+语言标注（不算识别错误）。
- **自定义拍卡相机**：拍照界面带 63:88 卡片取景框（半透明遮罩+渐变四角），快门后只裁剪框内区域送识别——卡在成图里占比 100%，等于把"卡占满画面"这个最大准确度因素产品化了。相册选图仍走整图识别。

## 已知边界

- CardSight 价格库对**2026 全新卡集覆盖有限**（之前实测 3 张新卡 0/3 无价），老牌热门卡数据齐全；无价时会提示。若要补齐可切回 Card Hedge 或做混合方案。
- CardSight 成交记录按标题匹配，偶尔混入相近卡的记录（如 Base Set 2 混进 Base Set），高价值卡建议人工核对 listing 标题。
- 数据来源目前主要是 eBay。
- 平行卡识别覆盖按 set 逐步扩充（官方 FAQ 承认 varies by set），认错平行/变体属已知限制，可用 `POST /v1/feedback/identify/{requestId}` 上报（每 key 每天 50 条）。
