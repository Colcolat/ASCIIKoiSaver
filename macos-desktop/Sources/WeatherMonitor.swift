import Foundation

struct LiveWeatherState {
    var isRaining: Bool = false
    var isSnowing: Bool = false
    var cloudDensity: CGFloat = 0.85 // 0.35 = clear, 0.85 = partly cloudy, 1.35 = overcast
    var summary: String = "Weather: Checking..."
}

/// Lightweight background weather monitor using wttr.in JSON API (no API key, no Location Services prompt).
/// Polls once at startup and every 25 minutes (~0% CPU).
final class WeatherMonitor {
    var onWeatherUpdated: ((LiveWeatherState) -> Void)?

    private var timer: Timer?
    private var isEnabled: Bool = false
    private var currentState = LiveWeatherState()

    func start() {
        guard !isEnabled else { return }
        isEnabled = true
        fetchWeather()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1500.0, repeats: true) { [weak self] _ in
            self?.fetchWeather()
        }
        timer?.tolerance = 60.0
    }

    func stop() {
        isEnabled = false
        timer?.invalidate()
        timer = nil
    }

    func fetchWeather() {
        guard isEnabled else { return }
        guard let url = URL(string: "https://wttr.in/?format=j1") else { return }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10.0)
        req.setValue("ASCIIKoiDesktop/1.0", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: req) { [weak self] data, _, err in
            guard let self = self, self.isEnabled else { return }
            guard err == nil, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let currentArr = json["current_condition"] as? [[String: Any]],
                  let curr = currentArr.first else {
                DispatchQueue.main.async {
                    var st = self.currentState
                    st.summary = "Weather: Offline"
                    self.currentState = st
                    self.onWeatherUpdated?(st)
                }
                return
            }

            let tempC = curr["temp_C"] as? String ?? "--"
            let cloudStr = curr["cloudcover"] as? String ?? "50"
            let cloudPct = CGFloat(Double(cloudStr) ?? 50.0) / 100.0
            let descArr = curr["weatherDesc"] as? [[String: Any]]
            let desc = (descArr?.first?["value"] as? String ?? "Clear").trimmingCharacters(in: .whitespacesAndNewlines)
            let descLow = desc.lowercased()

            var city = ""
            if let areaArr = json["nearest_area"] as? [[String: Any]],
               let area = areaArr.first,
               let nameArr = area["areaName"] as? [[String: Any]],
               let areaName = nameArr.first?["value"] as? String {
                city = areaName
            }

            let isRain = descLow.contains("rain") || descLow.contains("drizzle") || descLow.contains("shower") || descLow.contains("thunder") || descLow.contains("storm")
            let isSnow = descLow.contains("snow") || descLow.contains("sleet") || descLow.contains("blizzard") || descLow.contains("ice")
            let density: CGFloat = 0.30 + cloudPct * 1.15 // 0.30 (clear) .. 1.45 (overcast)

            let prefix = city.isEmpty ? "Weather" : city
            let state = LiveWeatherState(
                isRaining: isRain,
                isSnowing: isSnow,
                cloudDensity: density,
                summary: "\(prefix): \(tempC)°C · \(desc)"
            )

            DispatchQueue.main.async {
                self.currentState = state
                self.onWeatherUpdated?(state)
            }
        }.resume()
    }
}
