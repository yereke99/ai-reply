import SwiftUI

/// Current plan, what is left today, and the plans that can replace it.
///
/// Тариф пен күндік квота: шешімді әрқашан сервер қабылдайды.
///
/// The numbers on this screen come from the server on every appearance. The app
/// keeps a cached copy only so the keyboard can render instantly; it is never
/// the source of truth, and a stale cache can only ever be pessimistic.
struct SubscriptionView: View {

    @Environment(AppSettings.self) private var settings
    @Environment(AccountModel.self) private var account

    @State private var isChanging = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                usageCard
                if !account.plans.isEmpty { plansSection }
                Text("subscription.demo.footer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DS.Spacing.l)
            .padding(.vertical, DS.Spacing.l)
            .frame(maxWidth: DS.Layout.readableWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color.dsBackground)
        .navigationTitle("subscription.title")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await account.loadPlans()
            await account.refresh()
        }
    }

    // MARK: Pieces

    private var usageCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text("subscription.current").font(.caption).foregroundStyle(.secondary)
                    Text(verbatim: planName)
                        .font(.title3.weight(.semibold))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: DS.Spacing.xxs) {
                    Text(verbatim: "\(account.usage.remainingToday)")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(account.usage.remainingToday > 0 ? Color.accentColor : Color.red)
                    Text("subscription.remaining").font(.caption).foregroundStyle(.secondary)
                }
            }

            ProgressView(value: progress)
                .tint(account.usage.remainingToday > 0 ? Color.accentColor : Color.red)

            Text("subscription.usedToday \(account.usage.usedToday) \(account.usage.dailyLimit)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let expiry = account.subscription?.expiresAt, !expiry.isEmpty {
                Label(LocalizedStringKey("subscription.renews \(formatted(expiry))"), systemImage: "calendar")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .dsCard()
    }

    private var plansSection: some View {
        DSSection(title: "subscription.available") {
            VStack(spacing: DS.Spacing.s) {
                ForEach(account.plans) { plan in
                    planRow(plan)
                }
            }
        }
    }

    private func planRow(_ plan: AccountAPI.Plan) -> some View {
        let language = settings.effectiveLanguage.rawValue
        let isCurrent = account.subscription?.plan.id == plan.id

        return VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: plan.localizedName(language))
                    .font(.body.weight(.semibold))
                Spacer()
                Text(verbatim: plan.isFree ? "" : plan.priceText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(verbatim: plan.localizedDescription(language))
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Label {
                    Text("subscription.perDay \(plan.dailyLimit)")
                } icon: {
                    Image(systemName: "bolt.fill")
                }
                .font(.footnote)
                .foregroundStyle(Color.accentColor)

                Spacer()

                if isCurrent {
                    Text("subscription.currentBadge")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, DS.Spacing.xs)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(Color.accentColor.opacity(0.15))
                        )
                        .foregroundStyle(Color.accentColor)
                } else if !plan.isFree {
                    Button("subscription.choose") {
                        Task {
                            isChanging = true
                            _ = await account.choosePlan(plan)
                            isChanging = false
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(isChanging || account.isBusy)
                }
            }
        }
        .dsCard()
    }

    // MARK: Values

    private var planName: String {
        account.subscription?.plan.localizedName(settings.effectiveLanguage.rawValue) ?? ""
    }

    private var progress: Double {
        guard account.usage.dailyLimit > 0 else { return 0 }
        return min(1, Double(account.usage.usedToday) / Double(account.usage.dailyLimit))
    }

    /// The server sends ISO-8601; the user gets their own locale's date.
    private func formatted(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return iso }
        return date.formatted(.dateTime.day().month().year().locale(settings.locale))
    }
}
