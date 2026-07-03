import SwiftUI

struct PregnancyCalendarDayCell: View {
    let day: Int
    let isToday: Bool
    let isPregnancyDay: Bool
    let monthDate: Date
    let locale: Locale

    var body: some View {
        ZStack {
            if isPregnancyDay {
                Circle()
                    .fill(AppTheme.usesPremiumEditorStyling ? AnyShapeStyle(AppTheme.premiumEditorAccentGradient) : AnyShapeStyle(AppTheme.accentColor.opacity(0.15)))
            } else if isToday {
                Circle()
                    .strokeBorder(AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorAccentColor : AppTheme.accentColor, lineWidth: 2)
            }

            Text("\(day)")
                .appFont(.subheadline, weight: isToday ? .bold : .regular)
                .foregroundStyle(dayTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var dayTextColor: Color {
        if isPregnancyDay {
            return AppTheme.usesPremiumEditorStyling ? AppTheme.premiumEditorCTAForeground : AppTheme.accentColor
        }
        return AppTheme.usesPremiumEditorStyling ? AppTheme.primaryText : .primary
    }

    private var accessibilityDescription: String {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month], from: monthDate)
        components.day = day
        let dateString: String
        if let date = calendar.date(from: components) {
            dateString = date.formatted(
                Date.FormatStyle(date: .long, time: .omitted)
                    .locale(locale)
            )
        } else {
            dateString = L10n.format("Day %lld", defaultValue: "Day %lld", day)
        }

        var parts = [dateString]
        if isToday {
            parts.append(L10n.string("Today", defaultValue: "today"))
        }
        if isPregnancyDay {
            parts.append(L10n.string("Pregnancy", defaultValue: "pregnancy"))
        }
        return parts.joined(separator: ", ")
    }
}
