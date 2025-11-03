
    final class Timer {
        var currentTime: Time?

    init() {
        // Set timezone to Berlin (Central European Time with DST)
        let timezone = "Europe/Berlin"
        let tzResult = esp_rmaker_time_set_timezone(timezone)
        if tzResult == ESP_OK {
            print("Timezone set to Berlin successfully")
        } else {
            print("Failed to set timezone: \(tzResult)")
        }

        // Initialize time synchronization
        let result = esp_rmaker_time_sync_init(nil)
        if result == ESP_OK {
            print("Time sync initialized successfully")
        } else {
            print("Time sync initialization failed with error: \(result)")
        }
    }

    func updateCurrentTime() {
        var now = time(nil)
        let timeinfo = localtime(&now)

        if let tm = timeinfo {
            let hour = tm.pointee.tm_hour
            let min = tm.pointee.tm_min
            let sec = tm.pointee.tm_sec

            currentTime = Time(hour: hour, minute: min, second: sec)
        }
    }
}

struct Time {
    let hour: Int32
    let minute: Int32
    let second: Int32

    func toString() -> String {
        let h = hour < 10 ? "0\(hour)" : "\(hour)"
        let m = minute < 10 ? "0\(minute)" : "\(minute)"
        let s = second < 10 ? "0\(second)" : "\(second)"
        return "\(h):\(m):\(s)"
    }
}

extension Time: Comparable {
    static func < (lhs: Time, rhs: Time) -> Bool {
        if lhs.hour != rhs.hour {
            return lhs.hour < rhs.hour
        }
        if lhs.minute != rhs.minute {
            return lhs.minute < rhs.minute
        }
        return lhs.second < rhs.second
    }
}
