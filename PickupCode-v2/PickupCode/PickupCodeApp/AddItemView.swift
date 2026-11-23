import SwiftUI

/// 添加内容：取件码 / 待办 / 火车票 / 机票 四种表单（对应 Floaty 的 Compose 流程）。
struct AddItemView: View {
    @EnvironmentObject private var store: FloatyStore
    @Environment(\.dismiss) private var dismiss

    @State private var kind: FloatyKind = .pickup

    init(kind: FloatyKind = .pickup) {
        _kind = State(initialValue: kind)
    }

    // 取件码
    @State private var code: String = ""
    @State private var place: String = ""
    @State private var courier: String = ""
    @State private var pickupDeadline: Date = Date().addingTimeInterval(24 * 3600)
    @State private var pickupHasDeadline: Bool = true
    @State private var pickupReminder: Bool = false

    // 待办
    @State private var headline: String = ""
    @State private var todoNote: String = ""
    @State private var todoDeadline: Date = Date().addingTimeInterval(24 * 3600)
    @State private var todoHasDeadline: Bool = false
    @State private var checklistDraft: String = ""
    @State private var checklist: [ChecklistLine] = []

    // 火车票 / 机票
    @State private var tripNumber: String = ""
    @State private var fromPlace: String = ""
    @State private var toPlace: String = ""
    @State private var departure: Date = Date().addingTimeInterval(24 * 3600)
    @State private var arrival: Date = Date().addingTimeInterval(26 * 3600)
    @State private var hasArrival: Bool = false
    @State private var seat: String = ""
    @State private var car: String = ""
    @State private var gate: String = ""
    @State private var terminal: String = ""
    @State private var tripNote: String = ""
    @State private var tripReminder: Bool = true

    var body: some View {
        Form {
            Section {
                Picker("类型", selection: $kind) {
                    ForEach(FloatyKind.allCases) { item in
                        Label(item.displayName, systemImage: item.symbolName).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }

            switch kind {
            case .pickup:
                pickupForm
            case .todo:
                todoForm
            case .train:
                tripForm(isFlight: false)
            case .flight:
                tripForm(isFlight: true)
            }

            Section {
                Button {
                    save()
                    dismiss()
                } label: {
                    Label("保存", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!canSave)
            }
        }
        .navigationTitle("添加")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 取件码表单

    private var pickupForm: some View {
        Group {
            Section("取件信息") {
                TextField("取件码", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                TextField("取件地点（如 丰巢 / 前台）", text: $place)
                TextField("快递公司", text: $courier)
            }
            Section("截止与提醒") {
                Toggle("设置取件截止时间", isOn: $pickupHasDeadline)
                if pickupHasDeadline {
                    DatePicker("取件截止", selection: $pickupDeadline, displayedComponents: [.date, .hourAndMinute])
                    Toggle("到点提醒我", isOn: $pickupReminder)
                }
            }
        }
    }

    // MARK: - 待办表单

    private var todoForm: some View {
        Group {
            Section("待办") {
                TextField("要做什么", text: $headline)
                TextField("备注", text: $todoNote, axis: .vertical)
                    .lineLimit(1...4)
                Toggle("设置截止时间", isOn: $todoHasDeadline)
                if todoHasDeadline {
                    DatePicker("截止", selection: $todoDeadline, displayedComponents: [.date, .hourAndMinute])
                }
            }
            Section("清单子项") {
                ForEach(checklist) { line in
                    Button {
                        checklist.removeAll { $0.id == line.id }
                    } label: {
                        HStack {
                            Image(systemName: line.isDone ? "checkmark.square.fill" : "square")
                            Text(line.text)
                                .strikethrough(line.isDone)
                                .foregroundStyle(line.isDone ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.red)
                        }
                    }
                    .buttonStyle(.plain)
                }
                HStack {
                    TextField("添加子项", text: $checklistDraft)
                    Button {
                        addChecklistLine()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(checklistDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - 火车票 / 机票表单

    private func tripForm(isFlight: Bool) -> some View {
        Group {
            Section(isFlight ? "航班信息" : "车次信息") {
                TextField(isFlight ? "航班号（如 CA9527）" : "车次（如 G9527）", text: $tripNumber)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                TextField("出发地", text: $fromPlace)
                TextField("目的地", text: $toPlace)
                DatePicker("出发", selection: $departure, displayedComponents: [.date, .hourAndMinute])
                Toggle("填写到达时间", isOn: $hasArrival)
                if hasArrival {
                    DatePicker("到达", selection: $arrival, displayedComponents: [.date, .hourAndMinute])
                }
            }
            Section("座位与登机") {
                if !isFlight {
                    TextField("车厢（如 05）", text: $car)
                }
                TextField("座位（如 12A）", text: $seat)
                TextField(isFlight ? "登机口（如 C12）" : "检票口（如 B12）", text: $gate)
                if isFlight {
                    TextField("航站楼（如 T3）", text: $terminal)
                }
                TextField("备注", text: $tripNote)
                Toggle("出发前提醒", isOn: $tripReminder)
            }
        }
    }

    // MARK: - 逻辑

    private var canSave: Bool {
        switch kind {
        case .pickup:
            return !code.trimmingCharacters(in: .whitespaces).isEmpty
        case .todo:
            return !headline.trimmingCharacters(in: .whitespaces).isEmpty
        case .train, .flight:
            return !tripNumber.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func addChecklistLine() {
        let text = checklistDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        checklist.append(ChecklistLine(text: text))
        checklistDraft = ""
    }

    private func save() {
        let item: FloatyItem
        switch kind {
        case .pickup:
            item = FloatyItem(
                kind: .pickup,
                title: code.trimmingCharacters(in: .whitespaces),
                subtitle: place.trimmingCharacters(in: .whitespaces).isEmpty ? nil : place,
                detail: courier.trimmingCharacters(in: .whitespaces).isEmpty ? nil : courier,
                due: pickupHasDeadline ? FloatyDate.normalizeISO(pickupDeadline) : nil,
                dailyReminder: pickupReminder
            )
        case .todo:
            item = FloatyItem(
                kind: .todo,
                title: headline.trimmingCharacters(in: .whitespaces),
                due: todoHasDeadline ? FloatyDate.normalizeISO(todoDeadline) : nil,
                note: todoNote.trimmingCharacters(in: .whitespaces).isEmpty ? nil : todoNote,
                checklist: checklist
            )
        case .train:
            item = FloatyItem(
                kind: .train,
                title: tripNumber.trimmingCharacters(in: .whitespaces),
                from: fromPlace.trimmingCharacters(in: .whitespaces).isEmpty ? nil : fromPlace,
                to: toPlace.trimmingCharacters(in: .whitespaces).isEmpty ? nil : toPlace,
                departure: FloatyDate.normalizeISO(departure),
                arrival: hasArrival ? FloatyDate.normalizeISO(arrival) : nil,
                seat: seat.trimmingCharacters(in: .whitespaces).isEmpty ? nil : seat,
                car: car.trimmingCharacters(in: .whitespaces).isEmpty ? nil : car,
                gate: gate.trimmingCharacters(in: .whitespaces).isEmpty ? nil : gate,
                note: tripNote.trimmingCharacters(in: .whitespaces).isEmpty ? nil : tripNote
            )
        case .flight:
            item = FloatyItem(
                kind: .flight,
                title: tripNumber.trimmingCharacters(in: .whitespaces),
                from: fromPlace.trimmingCharacters(in: .whitespaces).isEmpty ? nil : fromPlace,
                to: toPlace.trimmingCharacters(in: .whitespaces).isEmpty ? nil : toPlace,
                departure: FloatyDate.normalizeISO(departure),
                arrival: hasArrival ? FloatyDate.normalizeISO(arrival) : nil,
                seat: seat.trimmingCharacters(in: .whitespaces).isEmpty ? nil : seat,
                gate: gate.trimmingCharacters(in: .whitespaces).isEmpty ? nil : gate,
                terminal: terminal.trimmingCharacters(in: .whitespaces).isEmpty ? nil : terminal,
                note: tripNote.trimmingCharacters(in: .whitespaces).isEmpty ? nil : tripNote
            )
        }

        store.insertOrUpdate(item)

        if item.kind == .todo {
            ReminderScheduler.scheduleDeadlineReminder(for: item)
        }
        if item.dailyReminder {
            ReminderScheduler.scheduleDailyReminder(enabled: true, time: store.settings.dailyReminderTime)
        }
        AutoAddEngine.refreshBoard()
    }
}

#Preview {
    NavigationStack {
        AddItemView()
            .environmentObject(FloatyStore.shared)
    }
}
