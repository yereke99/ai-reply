import SwiftUI

/// Working-hours editor.
///
/// Seven rows, one per weekday, each with its own toggle and two times. That
/// covers "Monday to Friday 10:00-16:00" and an optional weekend schedule
/// without a separate weekend concept to keep in sync.
struct WorkingHoursView: View {

    @Environment(ReplyConfigurationModel.self) private var model

    @State private var hours: WorkingHours = .default

    /// The week in Monday-first order, which reads correctly whether or not the
    /// user's locale starts its week on Sunday.
    private let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        Form {
            Section {
                Toggle("hours.enable", isOn: $hours.isEnabled)
            } footer: {
                Text("hours.footer")
            }

            if hours.isEnabled {
                Section {
                    ForEach(weekdayOrder, id: \.self) { weekday in
                        dayRow(weekday)
                    }
                }

                Section {
                    Label {
                        Text(hours.context().isWithinWorkingHours ? "hours.now.inside" : "hours.now.outside")
                            .font(.footnote)
                    } icon: {
                        Image(systemName: hours.context().isWithinWorkingHours ? "checkmark.circle" : "moon")
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("hours.title")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { hours = model.profile.workingHours }
        .onDisappear {
            model.updateProfile { $0.workingHours = hours }
        }
    }

    @ViewBuilder
    private func dayRow(_ weekday: Int) -> some View {
        if let index = hours.days.firstIndex(where: { $0.weekday == weekday }) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Toggle(weekdayName(weekday), isOn: $hours.days[index].isEnabled)

                if hours.days[index].isEnabled {
                    HStack {
                        timePicker("hours.from", selection: $hours.days[index].start)
                        Spacer(minLength: DS.Spacing.m)
                        timePicker("hours.to", selection: $hours.days[index].end)
                    }
                    if !hours.days[index].isValid {
                        Text("hours.invalid")
                            .font(.caption)
                            .foregroundStyle(Color.orange)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func timePicker(_ titleKey: LocalizedStringKey, selection: Binding<TimeOfDay>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titleKey)
                .font(.caption)
                .foregroundStyle(.secondary)
            // `DatePicker` needs a `Date`, but the model stores wall-clock
            // minutes. The conversion is anchored to today and only the hour
            // and minute are read back, so no date or timezone is ever stored.
            DatePicker(
                "",
                selection: Binding(
                    get: { Self.date(from: selection.wrappedValue) },
                    set: { selection.wrappedValue = Self.time(from: $0) }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
        }
    }

    private func weekdayName(_ weekday: Int) -> String {
        Calendar.current.standaloneWeekdaySymbols[weekday - 1].capitalized
    }

    private static func date(from time: TimeOfDay) -> Date {
        Calendar.current.date(
            bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()
        ) ?? Date()
    }

    private static func time(from date: Date) -> TimeOfDay {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: components.hour ?? 0, minute: components.minute ?? 0)
    }
}
