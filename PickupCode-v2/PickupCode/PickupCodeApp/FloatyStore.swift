import Combine
import Foundation
import os

/// 全局状态中心：内容列表、识别模板、设置、看板状态。
///
/// 数据落地在共享 UserDefaults（App Group 可用时主 App 与扩展互通）。
final class FloatyStore: ObservableObject, FloatyStoreProtocol {

    static let shared = FloatyStore()

    private let logger = Logger(subsystem: "com.yourteam.pickupcode", category: "FloatyStore")

    @Published private(set) var items: [FloatyItem] = []
    @Published private(set) var templates: [RecognitionTemplate] = []
    @Published private(set) var settings: FloatySettings = FloatySettings()
    @Published private(set) var boardPageIndex: Int = 0
    @Published private(set) var boardFocusIndex: Int = 0

    private init() {
        items = FloatyRepository.loadItems()
        templates = FloatyRepository.loadTemplates()
        settings = FloatyRepository.loadSettings()
        boardPageIndex = FloatyBoard.pageIndex()
        boardFocusIndex = FloatyBoard.focusIndex()
    }

    // MARK: - 列表查询

    var activeItems: [FloatyItem] {
        items.filter { !$0.isCompleted && !$0.isExpired }
    }

    func items(of kind: FloatyKind) -> [FloatyItem] {
        items.filter { $0.kind == kind }
    }

    func item(id: UUID) -> FloatyItem? {
        items.first { $0.id == id }
    }

    /// 看板可见内容（按设置过滤 + 排序）
    var boardItems: [FloatyItem] {
        FloatyBoard.visibleItems(from: items, settings: settings)
    }

    var boardPageCount: Int {
        FloatyBoard.pageCount(boardItems, perPage: settings.itemsPerPage)
    }

    var currentPageItems: [FloatyItem] {
        FloatyBoard.page(boardItems, index: boardPageIndex, perPage: settings.itemsPerPage)
    }

    // MARK: - 写入

    /// 读取全部内容（FloatyStoreProtocol）
    func loadAll() -> [FloatyItem] {
        items
    }

    func insertOrUpdate(_ item: FloatyItem) {
        items = FloatyRepository.upsert(item, into: items)
        FloatyRepository.saveItems(items)
    }

    func deleteRecord(id: UUID) {
        items = FloatyRepository.deleteItem(id: id, from: items)
        FloatyRepository.saveItems(items)
    }

    func markCompleted(id: UUID) {
        items = FloatyRepository.markCompleted(id: id, in: items)
        FloatyRepository.saveItems(items)
    }

    func markExpired(id: UUID) {
        items = FloatyRepository.markExpired(id: id, in: items)
        FloatyRepository.saveItems(items)
    }

    func clearCompleted() {
        items = FloatyRepository.clearCompleted(in: items)
        FloatyRepository.saveItems(items)
    }

    func clearAll() {
        items = []
        FloatyRepository.saveItems(items)
    }

    func markActivityStarted(id: UUID) {
        items = FloatyRepository.markActivityStarted(id: id, in: items)
        FloatyRepository.saveItems(items)
    }

    /// 按取件码标记完成（旧契约 / 灵动岛深链兼容路径）
    func markCompleted(code: String) {
        guard let target = items.first(where: { $0.kind == .pickup && $0.title == code && !$0.isCompleted && !$0.isExpired }) else {
            return
        }
        markCompleted(id: target.id)
    }

    func toggleChecklist(itemID: UUID, lineID: UUID) {
        items = FloatyRepository.toggleChecklist(itemID: itemID, lineID: lineID, in: items)
        FloatyRepository.saveItems(items)
    }

    // MARK: - 模板

    func addTemplate(_ template: RecognitionTemplate) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = template
        } else {
            templates.append(template)
        }
        FloatyRepository.saveTemplates(templates)
    }

    func deleteTemplate(id: UUID) {
        templates.removeAll { $0.id == id && !$0.isBuiltin }
        FloatyRepository.saveTemplates(templates)
    }

    /// 用文本识别一条内容并入库；命中返回内容。
    @discardableResult
    func recognizeAndInsert(text: String) -> FloatyItem? {
        guard let result = RecognitionEngine.recognize(text: text,
                                                     templates: templates,
                                                     builtinPickupEnabled: settings.builtinPickupEnabled) else {
            return nil
        }
        insertOrUpdate(result.item)
        return result.item
    }

    // MARK: - 设置

    func updateSettings(_ newValue: FloatySettings) {
        settings = newValue
        FloatyRepository.saveSettings(settings)
    }

    func updateSettings(_ mutate: (inout FloatySettings) -> Void) {
        var copy = settings
        mutate(&copy)
        updateSettings(copy)
    }

    // MARK: - 看板

    func setPageIndex(_ value: Int) {
        let maxIndex = max(0, boardPageCount - 1)
        boardPageIndex = min(max(0, value), maxIndex)
        FloatyBoard.setPageIndex(boardPageIndex)
    }

    func setFocusIndex(_ value: Int) {
        let count = max(1, currentPageItems.count)
        boardFocusIndex = min(max(0, value), count - 1)
        FloatyBoard.setFocusIndex(boardFocusIndex)
    }

    func resetBoard() {
        FloatyBoard.reset()
        boardPageIndex = 0
        boardFocusIndex = 0
    }
}
