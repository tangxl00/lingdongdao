import Foundation

/// 数据持久化层（主 App / App Intents / Widget Extension 共用）。
///
/// 数据落在共享 UserDefaults：配置了 App Group 时主 App 与扩展互通；
/// 未配置（免费 Apple ID）时各自读写本地容器，不影响核心展示。
enum FloatyRepository {

    private static let maxRecords = 500

    // MARK: - 内容列表

    static func loadItems() -> [FloatyItem] {
        let defaults = FloatyStorage.sharedDefaults()
        guard let data = defaults.data(forKey: FloatyStorage.historyKey) else { return [] }
        do {
            let decoded = try JSONDecoder().decode([FloatyItem].self, from: data)
            return decoded.sorted { $0.createdAt > $1.createdAt }
        } catch {
            return []
        }
    }

    static func saveItems(_ items: [FloatyItem]) {
        let defaults = FloatyStorage.sharedDefaults()
        let trimmed = Array(items.prefix(maxRecords))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        defaults.set(data, forKey: FloatyStorage.historyKey)
    }

    /// 插入或更新（同类型 + 同主标题且未完结 → 原地更新）。
    static func upsert(_ item: FloatyItem, into items: [FloatyItem]) -> [FloatyItem] {
        var result = items
        if let index = result.firstIndex(where: {
            $0.kind == item.kind && $0.title == item.title && !$0.isCompleted && !$0.isExpired
        }) {
            var merged = item
            merged.id = result[index].id
            result[index] = merged
        } else {
            result.insert(item, at: 0)
        }
        return result
    }

    static func deleteItem(id: UUID, from items: [FloatyItem]) -> [FloatyItem] {
        items.filter { $0.id != id }
    }

    static func markCompleted(id: UUID, in items: [FloatyItem]) -> [FloatyItem] {
        items.map { item in
            guard item.id == id else { return item }
            var updated = item
            updated.isCompleted = true
            updated.isExpired = false
            return updated
        }
    }

    static func markExpired(id: UUID, in items: [FloatyItem]) -> [FloatyItem] {
        items.map { item in
            guard item.id == id else { return item }
            var updated = item
            updated.isExpired = true
            return updated
        }
    }

    static func clearCompleted(in items: [FloatyItem]) -> [FloatyItem] {
        items.filter { !$0.isCompleted && !$0.isExpired }
    }

    /// 标记已启动 Live Activity
    static func markActivityStarted(id: UUID, in items: [FloatyItem]) -> [FloatyItem] {
        items.map { item in
            guard item.id == id else { return item }
            var updated = item
            updated.didStartActivity = true
            return updated
        }
    }

    /// 勾选 / 取消勾选待办子项
    static func toggleChecklist(itemID: UUID, lineID: UUID, in items: [FloatyItem]) -> [FloatyItem] {
        items.map { item in
            guard item.id == itemID else { return item }
            var updated = item
            updated.checklist = item.checklist.map { line in
                guard line.id == lineID else { return line }
                var newLine = line
                newLine.isDone.toggle()
                return newLine
            }
            return updated
        }
    }

    // MARK: - 设置

    static func loadSettings() -> FloatySettings {
        let defaults = FloatyStorage.sharedDefaults()
        guard let data = defaults.data(forKey: FloatyStorage.settingsKey),
              let decoded = try? JSONDecoder().decode(FloatySettings.self, from: data) else {
            return FloatySettings()
        }
        return decoded
    }

    static func saveSettings(_ settings: FloatySettings) {
        let defaults = FloatyStorage.sharedDefaults()
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: FloatyStorage.settingsKey)
    }

    // MARK: - 识别模板

    static func loadTemplates() -> [RecognitionTemplate] {
        let defaults = FloatyStorage.sharedDefaults()
        var stored: [RecognitionTemplate] = []
        if let data = defaults.data(forKey: FloatyStorage.templatesKey),
           let decoded = try? JSONDecoder().decode([RecognitionTemplate].self, from: data) {
            stored = decoded
        }

        // 保留用户保存的模板（含用户改过的内置模板），按 id 去重
        var result: [RecognitionTemplate] = []
        var seen = Set<UUID>()
        for template in stored where !seen.contains(template.id) {
            seen.insert(template.id)
            result.append(template)
        }

        // 补齐本次版本新增的内置模板
        for builtin in BuiltinTemplates.all where !seen.contains(builtin.id) {
            seen.insert(builtin.id)
            result.append(builtin)
        }
        return result
    }

    static func saveTemplates(_ templates: [RecognitionTemplate]) {
        let defaults = FloatyStorage.sharedDefaults()
        guard let data = try? JSONEncoder().encode(templates) else { return }
        defaults.set(data, forKey: FloatyStorage.templatesKey)
    }

    // MARK: - 完成标记（Widget 侧写入，主 App 对账时读取）

    static func writeCompletedMarker(id: UUID) {
        let defaults = FloatyStorage.sharedDefaults()
        defaults.set(Date(), forKey: FloatyStorage.completedMarkerPrefix + id.uuidString)
    }

    static func readCompletedMarker(id: UUID) -> Date? {
        let defaults = FloatyStorage.sharedDefaults()
        return defaults.object(forKey: FloatyStorage.completedMarkerPrefix + id.uuidString) as? Date
    }

    // MARK: - 待处理的添加类型（App Intents → 主 App）

    /// 记录快捷指令请求打开的添加类型
    static func savePendingComposeKind(_ kind: FloatyKind) {
        FloatyStorage.sharedDefaults().set(kind.rawValue, forKey: FloatyStorage.pendingComposeKindKey)
    }

    /// 读取并清除待处理的添加类型
    static func takePendingComposeKind() -> FloatyKind? {
        let defaults = FloatyStorage.sharedDefaults()
        guard let raw = defaults.string(forKey: FloatyStorage.pendingComposeKindKey),
              let kind = FloatyKind(rawValue: raw) else {
            return nil
        }
        defaults.removeObject(forKey: FloatyStorage.pendingComposeKindKey)
        return kind
    }
}
