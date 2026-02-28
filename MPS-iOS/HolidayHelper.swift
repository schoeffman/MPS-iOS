//
//  HolidayHelper.swift
//  MPS-iOS
//
//  Ported from client/src/lib/schedule-utils.ts
//

import Foundation

enum HolidayHelper {

    /// Returns US federal holidays (with observed dates) for a given year.
    static func usHolidays(year: Int) -> [(date: Date, name: String)] {
        // Swift Calendar: month 1=Jan…12=Dec, weekday 1=Sun, 2=Mon…7=Sat
        [
            (observed(makeDate(year, 1, 1)),            "New Year's Day"),
            (nthWeekday(year, month: 1,  weekday: 2, n: 3), "MLK Day"),
            (nthWeekday(year, month: 2,  weekday: 2, n: 3), "Presidents' Day"),
            (lastWeekday(year, month: 5,  weekday: 2),      "Memorial Day"),
            (observed(makeDate(year, 6, 19)),            "Juneteenth"),
            (observed(makeDate(year, 7,  4)),            "Independence Day"),
            (nthWeekday(year, month: 9,  weekday: 2, n: 1), "Labor Day"),
            (nthWeekday(year, month: 10, weekday: 2, n: 2), "Columbus Day"),
            (observed(makeDate(year, 11, 11)),           "Veterans Day"),
            (nthWeekday(year, month: 11, weekday: 5, n: 4), "Thanksgiving"),
            (observed(makeDate(year, 12, 25)),           "Christmas Day"),
        ]
    }

    /// Returns names of holidays that fall within the Monday–Sunday week
    /// starting on `weekStart`.
    static func holidaysInWeek(weekStart: Date) -> [String] {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart)!

        // Cover both years in case the week straddles Dec/Jan
        let y1 = cal.component(.year, from: weekStart)
        let y2 = cal.component(.year, from: weekEnd)
        var holidays = usHolidays(year: y1)
        if y2 != y1 { holidays += usHolidays(year: y2) }

        return holidays.compactMap { h in
            h.date >= weekStart && h.date <= weekEnd ? h.name : nil
        }
    }

    // MARK: - Private helpers

    /// Sat → Fri, Sun → Mon; other days unchanged.
    private static func observed(_ d: Date) -> Date {
        let cal = Calendar(identifier: .gregorian)
        let weekday = cal.component(.weekday, from: d)
        if weekday == 7 { return cal.date(byAdding: .day, value: -1, to: d)! } // Saturday
        if weekday == 1 { return cal.date(byAdding: .day, value:  1, to: d)! } // Sunday
        return d
    }

    /// Nth occurrence of a weekday in a month (e.g. n=3, weekday=2 → 3rd Monday).
    private static func nthWeekday(_ year: Int, month: Int, weekday: Int, n: Int) -> Date {
        let cal = Calendar(identifier: .gregorian)
        let firstOfMonth = makeDate(year, month, 1)
        let firstWeekday = cal.component(.weekday, from: firstOfMonth)
        var diff = weekday - firstWeekday
        if diff < 0 { diff += 7 }
        return cal.date(byAdding: .day, value: diff + (n - 1) * 7, to: firstOfMonth)!
    }

    /// Last occurrence of a weekday in a month (e.g. weekday=2 → last Monday).
    private static func lastWeekday(_ year: Int, month: Int, weekday: Int) -> Date {
        let cal = Calendar(identifier: .gregorian)
        // Last day of the month
        let firstOfNext = makeDate(year, month + 1, 1)
        let lastDay = cal.date(byAdding: .day, value: -1, to: firstOfNext)!
        let lastWeekdayVal = cal.component(.weekday, from: lastDay)
        var diff = lastWeekdayVal - weekday
        if diff < 0 { diff += 7 }
        return cal.date(byAdding: .day, value: -diff, to: lastDay)!
    }

    private static func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian)
            .date(from: DateComponents(year: year, month: month, day: day))!
    }
}
