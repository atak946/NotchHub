import SwiftUI

struct WeatherSettingsSection: View {
    @Bindable var weather: WeatherService

    @State private var query = ""

    private static let searchDebounce: Duration = .milliseconds(400)

    var body: some View {
        Section("Hava Durumu") {
            Toggle("Hava durumu", isOn: $weather.isEnabled)
            Picker("Konum", selection: $weather.locationMode) {
                ForEach(WeatherLocationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!weather.isEnabled)

            switch weather.locationMode {
            case .automatic:
                if weather.isLocationDenied {
                    Text("Konum izni yok. Sistem Ayarları > Gizlilik ve Güvenlik > Konum Servisleri'nden izin ver veya bir şehir seç.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .city:
                citySearch
            }

            Text("Hava durumu Open-Meteo'dan yaklaşık koordinatlarla alınır ve 30 dakikada bir yenilenir.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onDisappear { weather.clearSearch() }
    }

    @ViewBuilder
    private var citySearch: some View {
        LabeledContent("Şehir") {
            Text(verbatim: weather.city?.displayName ?? String(localized: "Seçilmedi"))
                .foregroundStyle(weather.city == nil ? .secondary : .primary)
        }
        TextField("Şehir ara", text: $query)
            .textFieldStyle(.roundedBorder)
            .disabled(!weather.isEnabled)
            .task(id: query) {
                try? await Task.sleep(for: Self.searchDebounce)
                guard !Task.isCancelled else { return }
                await weather.search(query)
            }
        if weather.searchFailed {
            Text("Şehir araması başarısız oldu.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        ForEach(weather.searchResults) { result in
            Button {
                weather.city = result
                query = ""
                weather.clearSearch()
            } label: {
                HStack {
                    Text(verbatim: result.displayName)
                    Spacer()
                    if result == weather.city {
                        Image(systemName: "checkmark")
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }
}
