import Foundation

func makeDate(_ s: String) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "Asia/Tokyo")
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: s)!
}
