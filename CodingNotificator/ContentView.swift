import SwiftUI
import AppKit
import Combine
import Foundation

enum StatusMode {
    case idle
    case running
    case done
    case needsInput
    case failed
}

struct TokenUsage: Sendable {
    var input: Int = 0
    var output: Int = 0
    var reasoning: Int = 0
    var cached: Int = 0
    var total: Int = 0

    nonisolated init(input: Int = 0, output: Int = 0, reasoning: Int = 0, cached: Int = 0, total: Int = 0) {
        self.input = input
        self.output = output
        self.reasoning = reasoning
        self.cached = cached
        self.total = total
    }
}

struct OpenCodeUsageWindow: Sendable {
    var messages: Int = 0
    var cost: Double = 0
    var tokens = TokenUsage()
    var resetAt: Date?

    nonisolated init(messages: Int = 0, cost: Double = 0, tokens: TokenUsage = TokenUsage(), resetAt: Date? = nil) {
        self.messages = messages
        self.cost = cost
        self.tokens = tokens
        self.resetAt = resetAt
    }
}

struct UsageSnapshot: Sendable {
    var openCodeProvider: String = "Not found"
    var openCodeModel: String = "Not found"
    var openCodeCost: Double = 0
    var openCodeTokens = TokenUsage()
    var openCodeMessages: Int = 0
    var openCodeFiveHour = OpenCodeUsageWindow()
    var openCodeWeekly = OpenCodeUsageWindow()
    var openCodeMonthly = OpenCodeUsageWindow()
    var codexModel: String = "Not found"
    var codexTokens = TokenUsage()
    var codexPrimaryLimit: Double?
    var codexSecondaryLimit: Double?
    var codexPrimaryResetAt: Date?
    var codexSecondaryResetAt: Date?
    var codexUpdatedAt: Date?
    var claudeFiveHourLimit: Double?
    var claudeSevenDayLimit: Double?
    var claudeFiveHourResetAt: Date?
    var claudeSevenDayResetAt: Date?
    var claudeUpdatedAt: Date?
    var refreshedAt = Date()

    nonisolated init(
        openCodeProvider: String = "Not found",
        openCodeModel: String = "Not found",
        openCodeCost: Double = 0,
        openCodeTokens: TokenUsage = TokenUsage(),
        openCodeMessages: Int = 0,
        openCodeFiveHour: OpenCodeUsageWindow = OpenCodeUsageWindow(),
        openCodeWeekly: OpenCodeUsageWindow = OpenCodeUsageWindow(),
        openCodeMonthly: OpenCodeUsageWindow = OpenCodeUsageWindow(),
        codexModel: String = "Not found",
        codexTokens: TokenUsage = TokenUsage(),
        codexPrimaryLimit: Double? = nil,
        codexSecondaryLimit: Double? = nil,
        codexPrimaryResetAt: Date? = nil,
        codexSecondaryResetAt: Date? = nil,
        codexUpdatedAt: Date? = nil,
        claudeFiveHourLimit: Double? = nil,
        claudeSevenDayLimit: Double? = nil,
        claudeFiveHourResetAt: Date? = nil,
        claudeSevenDayResetAt: Date? = nil,
        claudeUpdatedAt: Date? = nil,
        refreshedAt: Date = Date()
    ) {
        self.openCodeProvider = openCodeProvider
        self.openCodeModel = openCodeModel
        self.openCodeCost = openCodeCost
        self.openCodeTokens = openCodeTokens
        self.openCodeMessages = openCodeMessages
        self.openCodeFiveHour = openCodeFiveHour
        self.openCodeWeekly = openCodeWeekly
        self.openCodeMonthly = openCodeMonthly
        self.codexModel = codexModel
        self.codexTokens = codexTokens
        self.codexPrimaryLimit = codexPrimaryLimit
        self.codexSecondaryLimit = codexSecondaryLimit
        self.codexPrimaryResetAt = codexPrimaryResetAt
        self.codexSecondaryResetAt = codexSecondaryResetAt
        self.codexUpdatedAt = codexUpdatedAt
        self.claudeFiveHourLimit = claudeFiveHourLimit
        self.claudeSevenDayLimit = claudeSevenDayLimit
        self.claudeFiveHourResetAt = claudeFiveHourResetAt
        self.claudeSevenDayResetAt = claudeSevenDayResetAt
        self.claudeUpdatedAt = claudeUpdatedAt
        self.refreshedAt = refreshedAt
    }
}

private nonisolated final class CodexAppServerResponseBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let completed: DispatchSemaphore
    private var data = Data()
    private var didSignal = false
    private var didReceiveRateLimits = false

    init(completed: DispatchSemaphore) {
        self.completed = completed
    }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }

        guard !chunk.isEmpty else {
            signalOnce()
            return
        }

        data.append(chunk)
        if let text = String(data: data, encoding: .utf8),
           text.contains("\"id\":1") {
            didReceiveRateLimits = true
            signalOnce()
        }
    }

    func snapshot() -> (data: Data, didReceiveRateLimits: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (data, didReceiveRateLimits)
    }

    private func signalOnce() {
        if !didSignal {
            didSignal = true
            completed.signal()
        }
    }
}

actor UsageReader {
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var cachedSnapshot: UsageSnapshot?
    private var cachedAt: Date?

    func readSnapshot(force: Bool = false) -> UsageSnapshot {
        if !force,
           let cachedSnapshot,
           let cachedAt,
           Date().timeIntervalSince(cachedAt) < 20 {
            return cachedSnapshot
        }

        let previousSnapshot = cachedSnapshot
        var snapshot = UsageSnapshot()
        readOpenCodeUsage(into: &snapshot)
        readCodexUsage(into: &snapshot)
        readClaudeUsage(into: &snapshot)
        carryForwardCodexUsageIfNeeded(from: previousSnapshot, into: &snapshot)
        carryForwardClaudeUsageIfNeeded(from: previousSnapshot, into: &snapshot)
        snapshot.refreshedAt = Date()
        cachedSnapshot = snapshot
        cachedAt = snapshot.refreshedAt
        return snapshot
    }

    private func carryForwardCodexUsageIfNeeded(from previousSnapshot: UsageSnapshot?, into snapshot: inout UsageSnapshot) {
        guard snapshot.codexUpdatedAt == nil,
              let previousSnapshot,
              previousSnapshot.codexUpdatedAt != nil else {
            return
        }

        snapshot.codexTokens = previousSnapshot.codexTokens
        snapshot.codexUpdatedAt = previousSnapshot.codexUpdatedAt
        snapshot.codexPrimaryResetAt = previousSnapshot.codexPrimaryResetAt
        snapshot.codexSecondaryResetAt = previousSnapshot.codexSecondaryResetAt
        snapshot.codexPrimaryLimit = carriedRateLimit(previousSnapshot.codexPrimaryLimit, resetAt: previousSnapshot.codexPrimaryResetAt)
        snapshot.codexSecondaryLimit = carriedRateLimit(previousSnapshot.codexSecondaryLimit, resetAt: previousSnapshot.codexSecondaryResetAt)
    }

    private func carriedRateLimit(_ usedPercent: Double?, resetAt: Date?) -> Double? {
        guard let usedPercent else { return nil }
        guard let resetAt else { return usedPercent }
        return resetAt > Date() ? usedPercent : 0
    }

    private func carryForwardClaudeUsageIfNeeded(from previousSnapshot: UsageSnapshot?, into snapshot: inout UsageSnapshot) {
        guard snapshot.claudeUpdatedAt == nil,
              let previousSnapshot,
              previousSnapshot.claudeUpdatedAt != nil else {
            return
        }

        snapshot.claudeUpdatedAt = previousSnapshot.claudeUpdatedAt
        snapshot.claudeFiveHourResetAt = previousSnapshot.claudeFiveHourResetAt
        snapshot.claudeSevenDayResetAt = previousSnapshot.claudeSevenDayResetAt
        snapshot.claudeFiveHourLimit = carriedRateLimit(previousSnapshot.claudeFiveHourLimit, resetAt: previousSnapshot.claudeFiveHourResetAt)
        snapshot.claudeSevenDayLimit = carriedRateLimit(previousSnapshot.claudeSevenDayLimit, resetAt: previousSnapshot.claudeSevenDayResetAt)
    }

    private func readOpenCodeUsage(into snapshot: inout UsageSnapshot) {
        let databaseURL = home.appendingPathComponent(".local/share/opencode/opencode.db")
        if FileManager.default.fileExists(atPath: databaseURL.path) {
            _ = readOpenCodeUsageFromDatabase(into: &snapshot)
            return
        }

        let messageURL = home.appendingPathComponent(".local/share/opencode/storage/message")
        guard let enumerator = FileManager.default.enumerator(
            at: messageURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        var latestDate = Date.distantPast
        let now = Date()
        let fiveHourStart = now.addingTimeInterval(-5 * 60 * 60)
        let weeklyStart = Date(timeIntervalSince1970: TimeInterval(startOfCurrentWeek(for: now)))
        let monthlyStart = now.addingTimeInterval(-30 * 24 * 60 * 60)
        let nextWeekStart = startOfNextWeek(for: now)

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "json" {
            guard let data = try? Data(contentsOf: fileURL),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["role"] as? String == "assistant" else {
                continue
            }

            let messageCost = object["cost"] as? Double ?? 0
            let messageTokens = openCodeTokens(from: object)

            snapshot.openCodeMessages += 1
            snapshot.openCodeCost += messageCost
            snapshot.openCodeTokens.input += messageTokens.input
            snapshot.openCodeTokens.output += messageTokens.output
            snapshot.openCodeTokens.reasoning += messageTokens.reasoning
            snapshot.openCodeTokens.cached += messageTokens.cached

            let time = object["time"] as? [String: Any]
            let millis = intValue(time?["completed"] ?? time?["created"])
            let modifiedAt = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let date = millis > 0 ? Date(timeIntervalSince1970: TimeInterval(millis) / 1000) : modifiedAt ?? .distantPast

            if date >= fiveHourStart {
                addOpenCodeMessage(cost: messageCost, tokens: messageTokens, to: &snapshot.openCodeFiveHour)
                updateResetIfEarlier(date.addingTimeInterval(5 * 60 * 60), for: &snapshot.openCodeFiveHour)
            }

            if date >= weeklyStart {
                addOpenCodeMessage(cost: messageCost, tokens: messageTokens, to: &snapshot.openCodeWeekly)
            }

            if date >= monthlyStart {
                addOpenCodeMessage(cost: messageCost, tokens: messageTokens, to: &snapshot.openCodeMonthly)
                updateResetIfEarlier(date.addingTimeInterval(30 * 24 * 60 * 60), for: &snapshot.openCodeMonthly)
            }

            if date >= latestDate {
                latestDate = date
                snapshot.openCodeProvider = object["providerID"] as? String ?? "Unknown"
                snapshot.openCodeModel = object["modelID"] as? String ?? "Unknown"
            }
        }

        snapshot.openCodeTokens.total = snapshot.openCodeTokens.input
            + snapshot.openCodeTokens.output
            + snapshot.openCodeTokens.reasoning
        snapshot.openCodeWeekly.resetAt = nextWeekStart
    }

    private func readOpenCodeUsageFromDatabase(into snapshot: inout UsageSnapshot) -> Bool {
        let databaseURL = home.appendingPathComponent(".local/share/opencode/opencode.db")
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return false }

        let latestSQL = """
        select coalesce(json_extract(data,'$.model.providerID'),'Not found') || '\t' || coalesce(json_extract(data,'$.model.modelID'),'Not found')
        from message
        where json_extract(data,'$.role')='user'
          and json_extract(data,'$.model.providerID') is not null
        order by time_updated desc
        limit 1;
        """

        if let latest = runSQLiteQuery(databaseURL: databaseURL, sql: latestSQL, timeout: 0.7)?
            .split(separator: "\t", omittingEmptySubsequences: false),
           latest.count >= 2 {
            snapshot.openCodeProvider = String(latest[0])
            snapshot.openCodeModel = String(latest[1])
        }

        let now = Date()
        let fiveHourStart = Int(now.timeIntervalSince1970) - 5 * 60 * 60
        let weeklyStart = startOfCurrentWeek(for: now)
        let monthlyStart = Int(now.timeIntervalSince1970) - 30 * 24 * 60 * 60

        let usageSQL = """
        with assistant as (
          select a.time_updated/1000.0 as ts,
                 coalesce(cast(json_extract(a.data,'$.cost') as real),0) as cost,
                 coalesce(cast(json_extract(a.data,'$.tokens.input') as integer),0) as input,
                 coalesce(cast(json_extract(a.data,'$.tokens.output') as integer),0) as output,
                 coalesce(cast(json_extract(a.data,'$.tokens.reasoning') as integer),0) as reasoning,
                 coalesce(cast(json_extract(a.data,'$.tokens.cache.read') as integer),0)
                   + coalesce(cast(json_extract(a.data,'$.tokens.cache.write') as integer),0) as cached,
                 json_extract(u.data,'$.model.providerID') as provider
          from message a
          left join message u on u.id = json_extract(a.data,'$.parentID')
          where json_extract(a.data,'$.role')='assistant'
        ), msgs as (
          select * from assistant where provider='opencode-go'
        ), bounds as (
          select
            \(fiveHourStart) as five_hour_start,
            \(weeklyStart) as weekly_start,
            \(monthlyStart) as monthly_start
        )
        select
          count(*),
          coalesce(sum(cost),0),
          coalesce(sum(input),0),
          coalesce(sum(output),0),
          coalesce(sum(reasoning),0),
          coalesce(sum(cached),0),
          coalesce(sum(input + output + reasoning),0),
          coalesce(sum(case when ts >= five_hour_start then 1 else 0 end),0),
          coalesce(sum(case when ts >= five_hour_start then cost else 0 end),0),
          coalesce(sum(case when ts >= five_hour_start then input else 0 end),0),
          coalesce(sum(case when ts >= five_hour_start then output else 0 end),0),
          coalesce(sum(case when ts >= five_hour_start then reasoning else 0 end),0),
          coalesce(sum(case when ts >= five_hour_start then cached else 0 end),0),
          coalesce(sum(case when ts >= five_hour_start then input + output + reasoning else 0 end),0),
          coalesce(min(case when ts >= five_hour_start then ts end),0),
          coalesce(sum(case when ts >= weekly_start then 1 else 0 end),0),
          coalesce(sum(case when ts >= weekly_start then cost else 0 end),0),
          coalesce(sum(case when ts >= weekly_start then input else 0 end),0),
          coalesce(sum(case when ts >= weekly_start then output else 0 end),0),
          coalesce(sum(case when ts >= weekly_start then reasoning else 0 end),0),
          coalesce(sum(case when ts >= weekly_start then cached else 0 end),0),
          coalesce(sum(case when ts >= weekly_start then input + output + reasoning else 0 end),0),
          coalesce(min(case when ts >= weekly_start then ts end),0),
          coalesce(sum(case when ts >= monthly_start then 1 else 0 end),0),
          coalesce(sum(case when ts >= monthly_start then cost else 0 end),0),
          coalesce(sum(case when ts >= monthly_start then input else 0 end),0),
          coalesce(sum(case when ts >= monthly_start then output else 0 end),0),
          coalesce(sum(case when ts >= monthly_start then reasoning else 0 end),0),
          coalesce(sum(case when ts >= monthly_start then cached else 0 end),0),
          coalesce(sum(case when ts >= monthly_start then input + output + reasoning else 0 end),0),
          coalesce(min(case when ts >= monthly_start then ts end),0)
        from msgs, bounds;
        """

        guard let output = runSQLiteQuery(databaseURL: databaseURL, sql: usageSQL, timeout: 1.2) else { return false }
        let values = output.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard values.count >= 31, intValue(values[0]) > 0 else { return false }

        snapshot.openCodeMessages = intValue(values[0])
        snapshot.openCodeCost = doubleValue(values[1]) ?? 0
        snapshot.openCodeTokens = TokenUsage(
            input: intValue(values[2]),
            output: intValue(values[3]),
            reasoning: intValue(values[4]),
            cached: intValue(values[5]),
            total: intValue(values[6])
        )
        snapshot.openCodeFiveHour = openCodeWindow(from: values, start: 7, resetOffset: 5 * 60 * 60)
        snapshot.openCodeWeekly = openCodeWindow(from: values, start: 15, resetAt: startOfNextWeek(for: now))
        snapshot.openCodeMonthly = openCodeWindow(from: values, start: 23, resetOffset: 30 * 24 * 60 * 60)

        return true
    }

    private func startOfCurrentWeek(for date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2

        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return Int(start.timeIntervalSince1970)
    }

    private func startOfNextWeek(for date: Date) -> Date {
        let weekStart = Date(timeIntervalSince1970: TimeInterval(startOfCurrentWeek(for: date)))
        return weekStart.addingTimeInterval(7 * 24 * 60 * 60)
    }

    private func openCodeWindow(from values: [String], start: Int, resetOffset: TimeInterval? = nil, resetAt: Date? = nil) -> OpenCodeUsageWindow {
        let oldestTimestamp = doubleValue(values[start + 7]) ?? 0
        let calculatedReset: Date?
        if let resetOffset, oldestTimestamp > 0 {
            calculatedReset = Date(timeIntervalSince1970: oldestTimestamp + resetOffset)
        } else {
            calculatedReset = resetAt
        }

        return OpenCodeUsageWindow(
            messages: intValue(values[start]),
            cost: doubleValue(values[start + 1]) ?? 0,
            tokens: TokenUsage(
                input: intValue(values[start + 2]),
                output: intValue(values[start + 3]),
                reasoning: intValue(values[start + 4]),
                cached: intValue(values[start + 5]),
                total: intValue(values[start + 6])
            ),
            resetAt: calculatedReset
        )
    }

    private func runSQLiteQuery(databaseURL: URL, sql: String, timeout: TimeInterval = 0.8) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-tabs", "-noheader", databaseURL.path, sql]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        let completed = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            completed.signal()
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        if completed.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func openCodeTokens(from object: [String: Any]) -> TokenUsage {
        var usage = TokenUsage()

        if let tokens = object["tokens"] as? [String: Any] {
            usage.input = intValue(tokens["input"])
            usage.output = intValue(tokens["output"])
            usage.reasoning = intValue(tokens["reasoning"])

            if let cache = tokens["cache"] as? [String: Any] {
                usage.cached = intValue(cache["read"]) + intValue(cache["write"])
            }
        }

        usage.total = usage.input + usage.output + usage.reasoning
        return usage
    }

    private func addOpenCodeMessage(cost: Double, tokens: TokenUsage, to window: inout OpenCodeUsageWindow) {
        window.messages += 1
        window.cost += cost
        window.tokens.input += tokens.input
        window.tokens.output += tokens.output
        window.tokens.reasoning += tokens.reasoning
        window.tokens.cached += tokens.cached
        window.tokens.total += tokens.total
    }

    private func updateResetIfEarlier(_ date: Date, for window: inout OpenCodeUsageWindow) {
        guard date > Date() else { return }
        if let current = window.resetAt {
            window.resetAt = min(current, date)
        } else {
            window.resetAt = date
        }
    }

    private func readClaudeUsage(into snapshot: inout UsageSnapshot) {
        let cacheURL = codingNotificatorSupportURL().appendingPathComponent("claude-usage.json")
        guard let data = try? Data(contentsOf: cacheURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rateLimits = object["rate_limits"] as? [String: Any] else {
            return
        }

        if let fiveHour = rateLimits["five_hour"] as? [String: Any],
           let usedPercent = doubleValue(fiveHour["used_percentage"]) {
            let resetAt = unixDate(from: fiveHour["resets_at"])
            snapshot.claudeFiveHourLimit = activeCachedUsedPercent(usedPercent, resetAt: resetAt)
            snapshot.claudeFiveHourResetAt = resetAt
        }

        if let sevenDay = rateLimits["seven_day"] as? [String: Any],
           let usedPercent = doubleValue(sevenDay["used_percentage"]) {
            let resetAt = unixDate(from: sevenDay["resets_at"])
            snapshot.claudeSevenDayLimit = activeCachedUsedPercent(usedPercent, resetAt: resetAt)
            snapshot.claudeSevenDayResetAt = resetAt
        }

        let values = try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey])
        snapshot.claudeUpdatedAt = values?.contentModificationDate ?? Date()
    }

    private func codingNotificatorSupportURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodingNotificator", isDirectory: true)
    }

    private func readCodexUsage(into snapshot: inout UsageSnapshot) {
        if readCodexUsageFromAppServer(into: &snapshot) {
            return
        }

        readCodexUsageFromSessionFiles(into: &snapshot)
    }

    private func readCodexUsageFromAppServer(into snapshot: inout UsageSnapshot) -> Bool {
        guard let output = runCodexAppServerRateLimitQuery() else { return false }

        for line in output.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  intValue(object["id"]) == 1,
                  let result = object["result"] as? [String: Any],
                  let rateLimits = result["rateLimits"] as? [String: Any] else {
                continue
            }

            var foundRateLimit = false

            if let primary = rateLimits["primary"] as? [String: Any],
               let usedPercent = doubleValue(primary["usedPercent"] ?? primary["used_percent"]) {
                snapshot.codexPrimaryLimit = clampedPercent(usedPercent)
                snapshot.codexPrimaryResetAt = appServerResetDate(from: primary)
                foundRateLimit = true
            }

            if let secondary = rateLimits["secondary"] as? [String: Any],
               let usedPercent = doubleValue(secondary["usedPercent"] ?? secondary["used_percent"]) {
                snapshot.codexSecondaryLimit = clampedPercent(usedPercent)
                snapshot.codexSecondaryResetAt = appServerResetDate(from: secondary)
                foundRateLimit = true
            }

            if foundRateLimit {
                snapshot.codexUpdatedAt = Date()
                return true
            }
        }

        return false
    }

    private func runCodexAppServerRateLimitQuery(timeout: TimeInterval = 5) -> String? {
        guard let executableURL = codexExecutableURL() else { return nil }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--listen", "stdio://"]

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()

        let completed = DispatchSemaphore(value: 0)
        let responseBuffer = CodexAppServerResponseBuffer(completed: completed)

        output.fileHandleForReading.readabilityHandler = { handle in
            responseBuffer.append(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        let request = """
        {"method":"initialize","id":0,"params":{"clientInfo":{"name":"codingnotificator","title":"Coding Notificator","version":"1.0"}}}
        {"method":"initialized","params":{}}
        {"method":"account/rateLimits/read","id":1,"params":{}}

        """

        if let data = request.data(using: .utf8) {
            input.fileHandleForWriting.write(data)
        }

        let didComplete = completed.wait(timeout: .now() + timeout) == .success

        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()

        if process.isRunning {
            process.terminate()
        }

        let response = responseBuffer.snapshot()

        guard didComplete, response.didReceiveRateLimits else { return nil }
        return String(data: response.data, encoding: .utf8)
    }

    private func codexExecutableURL() -> URL? {
        let candidates = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]

        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func readCodexUsageFromSessionFiles(into snapshot: inout UsageSnapshot) {
        let files = codexSessionFiles(limit: 8)

        var latestEventDate = Date.distantPast

        for file in files {
            guard let contents = tailString(from: file.url, maxBytes: 300_000) else { continue }

            for line in contents.split(whereSeparator: \.isNewline).reversed() {
                guard line.contains("\"token_count\""),
                      let data = String(line).data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      object["type"] as? String == "event_msg",
                      let payload = object["payload"] as? [String: Any],
                      payload["type"] as? String == "token_count",
                      let rateLimits = payload["rate_limits"] as? [String: Any] else {
                    continue
                }

                let eventDate = dateValue(object["timestamp"]) ?? file.modifiedAt ?? .distantPast
                guard eventDate >= latestEventDate else {
                    continue
                }

                latestEventDate = eventDate
                snapshot.codexUpdatedAt = eventDate

                if let info = payload["info"] as? [String: Any],
                   let usage = info["total_token_usage"] as? [String: Any] {
                    snapshot.codexTokens.input = intValue(usage["input_tokens"])
                    snapshot.codexTokens.output = intValue(usage["output_tokens"])
                    snapshot.codexTokens.reasoning = intValue(usage["reasoning_output_tokens"])
                    snapshot.codexTokens.cached = intValue(usage["cached_input_tokens"])
                    snapshot.codexTokens.total = intValue(usage["total_tokens"])
                }

                if let primary = rateLimits["primary"] as? [String: Any],
                   let usedPercent = doubleValue(primary["used_percent"]) {
                    let resetAt = resetDate(from: primary)
                    snapshot.codexPrimaryLimit = activeUsedPercent(usedPercent, rateLimit: primary, eventDate: eventDate)
                    snapshot.codexPrimaryResetAt = resetAt
                }

                if let secondary = rateLimits["secondary"] as? [String: Any],
                   let usedPercent = doubleValue(secondary["used_percent"]) {
                    let resetAt = resetDate(from: secondary)
                    snapshot.codexSecondaryLimit = activeUsedPercent(usedPercent, rateLimit: secondary, eventDate: eventDate)
                    snapshot.codexSecondaryResetAt = resetAt
                }

                break
            }

            if snapshot.codexUpdatedAt != nil {
                return
            }
        }
    }

    private func codexSessionFiles(limit: Int) -> [(url: URL, modifiedAt: Date?)] {
        let indexURL = home.appendingPathComponent(".codex/state_5.sqlite")
        if FileManager.default.fileExists(atPath: indexURL.path) {
            return codexSessionFilesFromIndex(limit: limit) ?? []
        }

        return Array(
            jsonlFiles(in: home.appendingPathComponent(".codex/sessions"))
                .sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }
                .prefix(limit)
        )
    }

    private func codexSessionFilesFromIndex(limit: Int) -> [(url: URL, modifiedAt: Date?)]? {
        let databaseURL = home.appendingPathComponent(".codex/state_5.sqlite")
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }

        let sql = """
        select rollout_path, updated_at
        from threads
        where rollout_path != ''
        order by updated_at desc
        limit \(limit);
        """

        guard let output = runSQLiteQuery(databaseURL: databaseURL, sql: sql, timeout: 0.35), !output.isEmpty else {
            return nil
        }

        return output.split(whereSeparator: \.isNewline).compactMap { line in
            let values = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard let path = values.first else { return nil }

            let url = URL(fileURLWithPath: String(path))
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }

            let updatedAt = values.count > 1 ? intValue(String(values[1])) : 0
            let date = updatedAt > 0 ? Date(timeIntervalSince1970: TimeInterval(updatedAt)) : nil
            return (url, date)
        }
    }

    private func latestModel(in contents: String) -> String? {
        for line in contents.split(whereSeparator: \.isNewline).reversed() {
            guard line.contains("\"model\""),
                  let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = object["payload"] as? [String: Any],
                  let model = payload["model"] as? String else {
                continue
            }

            return model
        }

        return nil
    }

    private func jsonlFiles(in directory: URL) -> [(url: URL, modifiedAt: Date?)] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "jsonl" else { return nil }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            return (url, values?.contentModificationDate)
        }
    }

    private func tailString(from url: URL, maxBytes: UInt64 = 2_000_000) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > maxBytes ? size - maxBytes : 0
        try? handle.seek(toOffset: offset)

        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func intValue(_ value: Any?) -> Int {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private func dateValue(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return ISO8601DateFormatter().date(from: string)
    }

    private func resetDate(from object: [String: Any]) -> Date? {
        let timestamp = intValue(object["resets_at"])
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    private func appServerResetDate(from object: [String: Any]) -> Date? {
        let timestamp = intValue(object["resetsAt"] ?? object["resets_at"])
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    private func unixDate(from value: Any?) -> Date? {
        let timestamp = intValue(value)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    private func clampedPercent(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    private func activeCachedUsedPercent(_ usedPercent: Double, resetAt: Date?) -> Double {
        guard let resetAt else { return clampedPercent(usedPercent) }
        return resetAt > Date() ? clampedPercent(usedPercent) : 0
    }

    private func activeUsedPercent(_ usedPercent: Double, rateLimit: [String: Any], eventDate: Date) -> Double {
        let resetAt = resetDate(from: rateLimit)
        guard let resetAt else { return usedPercent }

        guard resetAt > Date() else { return 0 }

        let windowMinutes = doubleValue(rateLimit["window_minutes"]) ?? 0
        if windowMinutes > 0 {
            let windowStart = resetAt.addingTimeInterval(-windowMinutes * 60)
            guard eventDate >= windowStart.addingTimeInterval(-60) else { return 0 }
        }

        return usedPercent
    }
}

@MainActor
final class UsagePanelModel: ObservableObject {
    @Published var snapshot = UsageSnapshot()
    @Published var isLoading = false
    private static let reader = UsageReader()
    private var refreshTask: Task<Void, Never>?

    func refresh(force: Bool = false) {
        refreshTask?.cancel()
        isLoading = true

        refreshTask = Task {
            let nextSnapshot = await Self.reader.readSnapshot(force: force)

            guard !Task.isCancelled else { return }
            snapshot = nextSnapshot
            isLoading = false
        }
    }
}

struct NotchMetrics {
    let screenFrame: CGRect
    let topUnsafeHeight: CGFloat
    let notchWidth: CGFloat
    let hasNotch: Bool

    static let fallback = NotchMetrics(
        screenFrame: NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1512, height: 982),
        topUnsafeHeight: 0,
        notchWidth: 180,
        hasNotch: false
    )
}

extension NSScreen {
    func readNotchMetrics() -> NotchMetrics {
        if #available(macOS 12.0, *) {
            let full = frame
            let topInset = safeAreaInsets.top

            let leftArea = auxiliaryTopLeftArea
            let rightArea = auxiliaryTopRightArea

            let left = leftArea ?? .zero
            let right = rightArea ?? .zero

            let hasBothAreas = leftArea != nil && rightArea != nil
            let gap: CGFloat

            if hasBothAreas {
                gap = max(0, right.minX - left.maxX)
            } else {
                gap = 180
            }

            let hasNotch = topInset > 0 && hasBothAreas && gap > 20
            let width = hasNotch ? max(170, min(260, gap)) : 180

            return NotchMetrics(
                screenFrame: full,
                topUnsafeHeight: topInset,
                notchWidth: width,
                hasNotch: hasNotch
            )
        } else {
            return .fallback
        }
    }
}

struct IslandLayout {
    let width: CGFloat
    let height: CGFloat

    static func forMode(_ mode: StatusMode, notchWidth: CGFloat) -> IslandLayout {
        switch mode {
        case .idle:
            return IslandLayout(width: notchWidth, height: 32)
        case .running, .done, .needsInput, .failed:
            return IslandLayout(width: notchWidth, height: 72)
        }
    }
}

struct NotchSlabShape: Shape {
    var bottomRadius: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(bottomRadius, rect.width / 2, rect.height / 2)

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()

        return path
    }
}

final class OpenCodeEventFileMonitor {
    private let fileURLs: [URL]
    private var timer: Timer?
    private var onEvent: (([String: Any]) -> Void)?

    init(fileURL: URL) {
        self.fileURLs = [fileURL]
    }

    init(fileURLs: [URL]) {
        self.fileURLs = Array(NSOrderedSet(array: fileURLs)) as? [URL] ?? fileURLs
    }

    func start(onEvent: @escaping ([String: Any]) -> Void) {
        self.onEvent = onEvent
        ensureDirectoryExists()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.poll()
        }

        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }

        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func ensureDirectoryExists() {
        for fileURL in fileURLs {
            let directory = fileURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func poll() {
        for fileURL in fileURLs {
            poll(fileURL: fileURL)
        }
    }

    private func poll(fileURL: URL) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return }
        let payloads = Self.parsePayloads(from: data)
        guard !payloads.isEmpty else { return }

        payloads.forEach { onEvent?($0) }
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func parsePayloads(from data: Data) -> [[String: Any]] {
        if let json = try? JSONSerialization.jsonObject(with: data) {
            if let object = json as? [String: Any] {
                return [object]
            }

            if let objects = json as? [[String: Any]] {
                return objects
            }
        }

        guard let text = String(data: data, encoding: .utf8) else { return [] }

        return text
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                guard let lineData = String(line).data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                    return nil
                }

                return json
            }
    }
}

final class CodexSessionQuestionMonitor {
    private let sessionsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/sessions", isDirectory: true)
    private var timer: Timer?
    private var seenLines = Set<String>()
    private var fileOffsets: [URL: UInt64] = [:]
    private var onQuestion: (([String: Any]) -> Void)?
    private var didBootstrap = false

    func start(onQuestion: @escaping ([String: Any]) -> Void) {
        self.onQuestion = onQuestion

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.poll()
        }

        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }

        poll()
        didBootstrap = true
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        for file in latestSessionFiles().prefix(8) {
            guard let contents = appendedString(from: file.url) else { continue }

            for rawLine in contents.split(whereSeparator: \.isNewline) {
                let line = String(rawLine)
                guard line.contains("request_user_input") else { continue }
                guard !seenLines.contains(line) else { continue }
                seenLines.insert(line)

                guard didBootstrap,
                      let payload = questionPayload(from: line) else {
                    continue
                }

                logQuestionPayload(payload)
                onQuestion?(payload)
            }
        }
    }

    private func questionPayload(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["payload"] as? [String: Any],
              payload["name"] as? String == "request_user_input",
              let argumentsText = payload["arguments"] as? String,
              let argumentsData = argumentsText.data(using: .utf8),
              let arguments = try? JSONSerialization.jsonObject(with: argumentsData) as? [String: Any] else {
            return nil
        }

        let message = questionMessage(from: arguments)

        return [
            "event": "question_asked",
            "source": "codex",
            "title": "Approval needed",
            "message": message.isEmpty ? "Codex has a question for you" : message,
            "properties": arguments
        ]
    }

    private func logQuestionPayload(_ payload: [String: Any]) {
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodingNotificator", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)

        let logURL = supportURL.appendingPathComponent("session-question-log.jsonl")
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let line = String(data: data, encoding: .utf8) else {
            return
        }

        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data((line + "\n").utf8))
        } else {
            try? (line + "\n").write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

    private func questionMessage(from arguments: [String: Any]) -> String {
        guard let questions = arguments["questions"] as? [[String: Any]] else { return "" }

        if let question = questions.first?["question"] as? String,
           !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return question.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let header = questions.first?["header"] as? String,
           !header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return header.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return ""
    }

    private func latestSessionFiles() -> [(url: URL, modifiedAt: Date?)] {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "jsonl" else { return nil }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            return (url, values?.contentModificationDate)
        }
        .sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }
    }

    private func appendedString(from url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let defaultOffset: UInt64 = didBootstrap ? 0 : size
        let previousOffset = min(fileOffsets[url] ?? defaultOffset, size)
        fileOffsets[url] = size

        guard didBootstrap, size > previousOffset else { return nil }

        try? handle.seek(toOffset: previousOffset)

        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

@MainActor
final class NotchNotifierModel: ObservableObject {
    static let shared = NotchNotifierModel()

    @Published var statusText: String = "Done"
    @Published var detailText: String = ""
    @Published var mode: StatusMode = .idle
    @Published var isBusy: Bool = false
    @Published var successPulse: Int = 0
    @Published var approvalPulse: Int = 0

    // Sandbox-aware path. This is the actual path your installed app uses.
    static let supportDirectory: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodingNotificator", isDirectory: true)
    }()

    static let eventFileURL: URL = supportDirectory.appendingPathComponent("event.json")
    static let containerEventFileURL: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/Viidvuds-Calitis.CodingNotificator/Data/Library/Application Support/CodingNotificator/event.json")

    private let monitor = OpenCodeEventFileMonitor(fileURLs: [
        NotchNotifierModel.eventFileURL,
        NotchNotifierModel.containerEventFileURL
    ])
    private let codexQuestionMonitor = CodexSessionQuestionMonitor()
    private var overlayController: NotchOverlayController?
    private var didStart = false

    private init() {}

    func start() {
        guard !didStart else { return }
        didStart = true

        ensureOverlay()
        print("Watching event files:", Self.eventFileURL.path, Self.containerEventFileURL.path)

        monitor.start { [weak self] payload in
            Task { @MainActor in
                self?.handle(payload: payload)
            }
        }

        codexQuestionMonitor.start { [weak self] payload in
            Task { @MainActor in
                self?.handle(payload: payload)
            }
        }
    }

    func dismissOverlayState() {
        print("dismissOverlayState called, mode =", mode)

        switch mode {
        case .done, .needsInput, .failed:
            overlayController?.hide()
            mode = .idle
            isBusy = false
            print("overlay dismissed")
        default:
            print("dismiss ignored")
        }
    }

    private func ensureOverlay() {
        if overlayController == nil {
            overlayController = NotchOverlayController(
                rootView: OverlayIslandView().environmentObject(self)
            )
        }
    }

    private func handle(payload: [String: Any]) {
        print("Received payload:", payload)

        guard let event = normalizedEventName(from: payload) else {
            print("Payload missing 'event'")
            return
        }

        let title = textValue(for: "title", in: payload)
        let message = messageText(from: payload)
        let source = sourceName(for: payload, event: event)

        switch event {
        case "agent_turn_complete", "agent_turn_completed":
            guard shouldShowCodexTurnComplete(payload, source: source) else {
                print("Ignored Codex background turn completion")
                return
            }

            let codexChatName = codexChatDisplayName(from: payload)
            showDone(
                title: title.isEmpty ? "Done: \(codexChatName)" : title,
                message: message.isEmpty ? "\(source) finished" : message
            )

        case "done", "completed", "complete", "finished", "finish", "success", "session.idle", "session_idle", "task_completed", "task_complete", "turn_completed", "turn_complete":
            showDone(
                title: title.isEmpty ? "\(source) done" : title,
                message: message.isEmpty ? "\(source) finished" : message
            )

        case "approval", "approval_requested", "permission", "permission.asked", "permission.updated", "permission_asked", "permission_updated", "permission_request", "question.asked", "question_asked", "requires_input", "required_input", "input_required", "needs_input", "user_input_requested":
            showApproval(
                title: title.isEmpty ? "Approval needed" : title,
                message: message.isEmpty ? "\(source) needs your input" : message
            )

        case "failed", "failure", "error", "errored", "session.error", "session_error", "task_failed", "task_error":
            showFailure(
                title: title.isEmpty ? "Failed" : title,
                message: message.isEmpty ? "\(source) hit an error" : message
            )

        case "running", "busy", "started", "start", "session.busy", "session_busy", "task_started", "task_start", "turn_started", "turn_start", "agent_turn_started", "agent_turn_start":
            showRunning(
                title: title,
                message: message
            )

        case "hide":
            overlayController?.hide()
            mode = .idle
            isBusy = false

        default:
            print("Unknown event:", event)
        }
    }

    private func normalizedEventName(from payload: [String: Any]) -> String? {
        let rawEvent = textValue(for: "event", in: payload)
        let rawType = textValue(for: "type", in: payload)

        let event = rawEvent.isEmpty ? rawType : rawEvent
        guard !event.isEmpty else { return nil }

        if event == "session.status",
           let properties = payload["properties"] as? [String: Any],
           let status = properties["status"] as? [String: Any] {
            let statusType = textValue(for: "type", in: status)
            if statusType == "busy" {
                return "busy"
            }
        }

        return event
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
    }

    private func sourceName(for payload: [String: Any], event: String) -> String {
        let rawSource = textValue(for: "source", in: payload)
            .lowercased()

        if rawSource.contains("claude") {
            return "Claude Code"
        }

        if rawSource.contains("codex")
            || event.hasPrefix("task_")
            || event.hasPrefix("turn_")
            || event.hasPrefix("agent_turn_")
            || payload["turn_id"] != nil
            || payload["rate_limits"] != nil
            || payload["model_context_window"] != nil {
            return "Codex"
        }

        return "OpenCode"
    }

    private func textValue(for key: String, in payload: [String: Any]) -> String {
        if let value = payload[key] as? String {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let properties = payload["properties"] as? [String: Any],
           let value = properties[key] as? String {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let nestedPayload = payload["payload"] as? [String: Any],
           let value = nestedPayload[key] as? String {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return ""
    }

    private func messageText(from payload: [String: Any]) -> String {
        let directMessage = textValue(for: "message", in: payload)
        if !directMessage.isEmpty {
            return directMessage
        }

        for key in ["text", "summary", "body", "detail", "details"] {
            let value = textValue(for: key, in: payload)
            if !value.isEmpty {
                return value
            }
        }

        guard let properties = payload["properties"] as? [String: Any] else { return "" }

        if let error = properties["error"] as? [String: Any],
           let data = error["data"] as? [String: Any],
           let message = data["message"] as? String {
            return message.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let questions = properties["questions"] as? [[String: Any]],
           let question = questions.first?["question"] as? String {
            return question.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return ""
    }

    func shouldShowCodexTurnComplete(_ payload: [String: Any], source: String) -> Bool {
        guard source == "Codex" else { return true }

        if codexInputMessages(in: payload).contains(where: isCodexBackgroundPrompt) {
            return false
        }

        let assistantMessage = textValue(for: "last-assistant-message", in: payload)
        if looksLikeCodexTitleResponse(assistantMessage) {
            return false
        }

        return true
    }

    func codexChatDisplayName(from payload: [String: Any]) -> String {
        let cwd = textValue(for: "cwd", in: payload)
        if !cwd.isEmpty {
            let projectName = URL(fileURLWithPath: cwd).lastPathComponent
            if !projectName.isEmpty {
                return projectName
            }
        }

        let threadID = textValue(for: "thread-id", in: payload)
        if !threadID.isEmpty {
            return "Codex \(threadID.prefix(8))"
        }

        let alternateThreadID = textValue(for: "thread_id", in: payload)
        if !alternateThreadID.isEmpty {
            return "Codex \(alternateThreadID.prefix(8))"
        }

        return "Codex"
    }

    private func codexInputMessages(in payload: [String: Any]) -> [String] {
        if let messages = payload["input-messages"] as? [String] {
            return messages
        }

        if let messages = payload["input_messages"] as? [String] {
            return messages
        }

        return []
    }

    private func isCodexBackgroundPrompt(_ text: String) -> Bool {
        let normalized = text.lowercased()

        return normalized.contains("generate a concise ui title")
            || normalized.contains("short title for a task")
            || normalized.contains("the tasks typically have to do with coding-related tasks")
            || normalized.contains("fill the structured title field")
            || normalized.contains("do not respond to the user")
    }

    private func looksLikeCodexTitleResponse(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{\"title\"")
            || trimmed.hasPrefix("{\n  \"title\"")
            || trimmed.hasPrefix("{\n    \"title\"")
    }

    private func showRunning(title: String, message: String) {
        guard !isBusy || mode != .idle else { return }

        statusText = ""
        detailText = ""
        isBusy = true
        mode = .idle
        print("showRunning called")
        overlayController?.hide()
    }

    private func showDone(title: String, message: String) {
        ensureOverlay()
        statusText = title
        detailText = message
        isBusy = false
        mode = .done
        successPulse += 1
        print("showDone called")
        playCompletionChime()
        overlayController?.show(mode: .done)
    }

    private func showApproval(title: String, message: String) {
        ensureOverlay()
        statusText = title
        detailText = message
        isBusy = false
        mode = .needsInput
        approvalPulse += 1
        print("showApproval called")
        playApprovalChime()
        overlayController?.show(mode: .needsInput)
    }

    private func showFailure(title: String, message: String) {
        ensureOverlay()
        statusText = title
        detailText = message
        isBusy = false
        mode = .failed
        print("showFailure called")
        playFailureChime()
        overlayController?.show(mode: .failed)
    }

    private func playCompletionChime() {
        if let sound = NSSound(named: NSSound.Name("Glass")) {
            sound.play()
        } else if let sound = NSSound(named: NSSound.Name("Morse")) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    private func playApprovalChime() {
        if let sound = NSSound(named: NSSound.Name("Hero")) {
            sound.play()
        } else if let sound = NSSound(named: NSSound.Name("Ping")) {
            sound.play()
        } else if let sound = NSSound(named: NSSound.Name("Tink")) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    private func playFailureChime() {
        if let sound = NSSound(named: NSSound.Name("Basso")) {
            sound.play()
        } else if let sound = NSSound(named: NSSound.Name("Funk")) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    private func playRunningChime() {
        if let sound = NSSound(named: NSSound.Name("Pop")) {
            sound.play()
        } else if let sound = NSSound(named: NSSound.Name("Tink")) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }
}

struct UsagePanelView: View {
    @StateObject private var model = UsagePanelModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("AI Usage", systemImage: "bolt.horizontal.circle.fill")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                if model.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }

                Button {
                    model.refresh(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(model.isLoading)
            }

            UsageSectionView(
                title: "OpenCode",
                rows: [
                    usageRow(
                        "5h",
                        usedPercent: openCodePercent(model.snapshot.openCodeFiveHour, limit: 12)
                    ),
                    usageRow(
                        "Weekly",
                        usedPercent: openCodePercent(model.snapshot.openCodeWeekly, limit: 30)
                    ),
                    usageRow(
                        "Monthly",
                        usedPercent: openCodePercent(model.snapshot.openCodeMonthly, limit: 60)
                    )
                ]
            )

            UsageSectionView(
                title: "Codex",
                rows: [
                    remainingRow(
                        "5h left",
                        remainingPercent: codexPrimaryLeft,
                        resetAt: model.snapshot.codexPrimaryResetAt
                    ),
                    remainingRow(
                        "Weekly left",
                        remainingPercent: codexSecondaryLeft,
                        resetAt: model.snapshot.codexSecondaryResetAt
                    )
                ]
            )

            UsageSectionView(
                title: "Claude Code",
                rows: [
                    remainingRow(
                        "5h left",
                        remainingPercent: claudeFiveHourLeft,
                        resetAt: model.snapshot.claudeFiveHourResetAt
                    ),
                    remainingRow(
                        "7d left",
                        remainingPercent: claudeSevenDayLeft,
                        resetAt: model.snapshot.claudeSevenDayResetAt
                    )
                ]
            )

        }
        .padding(10)
        .frame(width: 300)
        .onAppear {
            model.refresh()
        }
    }

    private var codexPrimaryLeft: Double? {
        model.snapshot.codexPrimaryLimit.map { 100 - $0 }
    }

    private var codexSecondaryLeft: Double? {
        model.snapshot.codexSecondaryLimit.map { 100 - $0 }
    }

    private var claudeFiveHourLeft: Double? {
        model.snapshot.claudeFiveHourLimit.map { 100 - $0 }
    }

    private var claudeSevenDayLeft: Double? {
        model.snapshot.claudeSevenDayLimit.map { 100 - $0 }
    }

    private func usageRow(_ label: String, usedPercent: Double) -> UsageDisplayRow {
        UsageDisplayRow(
            label: label,
            value: "\(formatPercent(usedPercent))%",
            progress: usedPercent / 100,
            color: usageColor(for: usedPercent)
        )
    }

    private func remainingRow(_ label: String, remainingPercent: Double?, resetAt: Date?) -> UsageDisplayRow {
        guard let remainingPercent else {
            return UsageDisplayRow(label: label, value: "n/a", progress: 0, color: .secondary)
        }

        return UsageDisplayRow(
            label: label,
            value: valueText(percent: remainingPercent, resetAt: resetAt),
            progress: remainingPercent / 100,
            color: remainingColor(for: remainingPercent)
        )
    }

    private func openCodePercent(_ window: OpenCodeUsageWindow, limit: Double) -> Double {
        limit > 0 ? (window.cost / limit) * 100 : 0
    }

    private func usageColor(for percent: Double) -> Color {
        if percent >= 85 { return barCritical }
        if percent >= 60 { return barWarning }
        return barHealthy
    }

    private func remainingColor(for percent: Double) -> Color {
        if percent <= 15 { return barCritical }
        if percent <= 40 { return barWarning }
        return barHealthy
    }

    private var barHealthy: Color {
        Color(red: 0.22, green: 0.84, blue: 0.55)
    }

    private var barWarning: Color {
        Color(red: 1.00, green: 0.68, blue: 0.25)
    }

    private var barCritical: Color {
        Color(red: 0.98, green: 0.32, blue: 0.28)
    }

    private func formatPercent(_ value: Double) -> String {
        min(100, max(0, value)).formatted(.number.precision(.fractionLength(0)))
    }

    private func valueText(percent: Double, resetAt: Date?) -> String {
        guard let resetText = resetText(until: resetAt) else {
            return "\(formatPercent(percent))%"
        }

        return "\(formatPercent(percent))% · \(resetText)"
    }

    private func resetText(until resetAt: Date?) -> String? {
        guard let resetAt else { return nil }

        let seconds = Int(resetAt.timeIntervalSince(Date()))
        guard seconds > 0 else { return "reset now" }

        let hours = seconds / 3600
        let days = hours / 24
        let remainingHours = hours % 24

        if days > 0 {
            return remainingHours > 0 ? "\(days)d \(remainingHours)h" : "\(days)d"
        }

        if hours > 0 {
            return "\(hours)h"
        }

        return "<1h"
    }
}

struct UsageDisplayRow {
    let label: String
    let value: String
    let progress: Double
    let color: Color
}

struct UsageSectionView: View {
    let title: String
    var subtitle: String? = nil
    let rows: [UsageDisplayRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            VStack(spacing: 5) {
                ForEach(rows, id: \.label) { row in
                    VStack(spacing: 2) {
                        HStack {
                            Text(row.label)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text(row.value)
                                .fontWeight(.semibold)
                                .textSelection(.enabled)
                        }

                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.12))

                                Capsule()
                                    .fill(row.color)
                                    .frame(width: geometry.size.width * min(1, max(0, row.progress)))
                            }
                        }
                        .frame(height: 4)
                    }
                }
            }
            .font(.caption)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct StatusGlyph: View {
    let mode: StatusMode
    let isBusy: Bool
    let successPulse: Int
    let approvalPulse: Int
    let size: CGFloat
    let darkBackground: Bool

    @State private var ringScale: CGFloat = 0.75
    @State private var ringOpacity: Double = 0
    @State private var ringColor: Color = .green
    @State private var spin = false

    private var visualSize: CGFloat { size + 2 }

    var body: some View {
        ZStack {
            if isBusy && mode == .running {
                Circle()
                    .trim(from: 0.18, to: 0.92)
                    .stroke(
                        Color.blue,
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                    )
                    .frame(width: visualSize, height: visualSize)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .onAppear { spin = true }
                    .onDisappear { spin = false }
                    .animation(
                        .linear(duration: 0.9).repeatForever(autoreverses: false),
                        value: spin
                    )
            } else {
                if ringOpacity > 0 {
                    Circle()
                        .stroke(ringColor.opacity(0.95), lineWidth: 1.7)
                        .frame(width: visualSize + 2, height: visualSize + 2)
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)
                }

                Image(systemName: symbolName)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(symbolTint)
                    .frame(width: visualSize, height: visualSize)
            }
        }
        .frame(width: visualSize + 4, height: visualSize + 4)
        .onChange(of: successPulse) { _, _ in
            triggerRing(color: .green)
        }
        .onChange(of: approvalPulse) { _, _ in
            triggerRing(color: .yellow)
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: mode)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isBusy)
    }

    private func triggerRing(color: Color) {
        ringColor = color
        ringScale = 0.75
        ringOpacity = 0.95
        withAnimation(.easeOut(duration: 0.7)) {
            ringScale = 1.9
            ringOpacity = 0
        }
    }

    private var symbolName: String {
        switch mode {
        case .idle:
            return "circle.fill"
        case .running:
            return "circle.fill"
        case .done:
            return "checkmark.circle.fill"
        case .needsInput:
            return "bell.circle.fill"
        case .failed:
            return "exclamationmark.circle.fill"
        }
    }

    private var symbolTint: Color {
        switch mode {
        case .idle:
            return darkBackground ? .white.opacity(0.9) : .primary
        case .running:
            return .blue
        case .done:
            return .green
        case .needsInput:
            return .yellow
        case .failed:
            return .red
        }
    }
}

struct OverlayIslandView: View {
    @EnvironmentObject private var model: NotchNotifierModel

    private var metrics: NotchMetrics {
        NSScreen.main?.readNotchMetrics() ?? .fallback
    }

    private var layout: IslandLayout {
        IslandLayout.forMode(model.mode, notchWidth: metrics.notchWidth)
    }

    private func hiddenTopHeight(totalHeight: CGFloat) -> CGFloat {
        min(metrics.topUnsafeHeight, totalHeight * 0.5)
    }

    private func visibleHeight(totalHeight: CGFloat) -> CGFloat {
        max(1, totalHeight - hiddenTopHeight(totalHeight: totalHeight))
    }

    var body: some View {
        ZStack {
            NotchSlabShape(bottomRadius: 18)
                .fill(Color.black)

            GeometryReader { geo in
                if model.mode != .idle {
                    VStack(spacing: 2) {
                        HStack(spacing: 8) {
                            StatusGlyph(
                                mode: model.mode,
                                isBusy: model.isBusy,
                                successPulse: model.successPulse,
                                approvalPulse: model.approvalPulse,
                                size: 13,
                                darkBackground: true
                            )

                            Text(model.statusText)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Spacer(minLength: 0)
                        }

                        if !model.detailText.isEmpty {
                            Text(model.detailText)
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.70))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 25)
                        }
                    }
                    .frame(
                        width: max(1, geo.size.width - 24),
                        height: visibleHeight(totalHeight: geo.size.height),
                        alignment: .center
                    )
                    .offset(y: hiddenTopHeight(totalHeight: geo.size.height))
                    .padding(.horizontal, 12)
                }
            }
        }
        .frame(width: layout.width, height: layout.height, alignment: .top)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            model.dismissOverlayState()
        }
    }
}

final class NotchOverlayController {
    private let panel: NSPanel
    private var currentMode: StatusMode = .idle

    init(rootView: some View) {
        let metrics = NSScreen.main?.readNotchMetrics() ?? .fallback
        let layout = IslandLayout.forMode(.done, notchWidth: metrics.notchWidth)

        let startRect = NSRect(
            x: metrics.screenFrame.midX - (layout.width / 2),
            y: metrics.screenFrame.maxY - layout.height,
            width: layout.width,
            height: layout.height
        )

        panel = NSPanel(
            contentRect: startRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.contentView = DismissHostingView(rootView: AnyView(rootView)) {
            Task { @MainActor in
                NotchNotifierModel.shared.dismissOverlayState()
            }
        }
        panel.orderOut(nil)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.repositionForCurrentMode()
        }
    }

    func show(mode: StatusMode) {
        currentMode = mode

        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        repositionForCurrentMode()
        NSAnimationContext.endGrouping()

        panel.ignoresMouseEvents = (mode == .idle || mode == .running)
        print("panel show mode =", mode, "ignoresMouseEvents =", panel.ignoresMouseEvents)

        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func repositionForCurrentMode() {
        let metrics = NSScreen.main?.readNotchMetrics() ?? .fallback
        let layout = IslandLayout.forMode(currentMode, notchWidth: metrics.notchWidth)

        let newFrame = NSRect(
            x: metrics.screenFrame.midX - (layout.width / 2),
            y: metrics.screenFrame.maxY - layout.height,
            width: layout.width,
            height: layout.height
        )

        panel.setFrame(newFrame, display: true)
    }
}

final class DismissHostingView: NSHostingView<AnyView> {
    private let onDoubleClick: () -> Void

    init(rootView: AnyView, onDoubleClick: @escaping () -> Void) {
        self.onDoubleClick = onDoubleClick
        super.init(rootView: rootView)
    }

    @MainActor @preconcurrency required dynamic init(rootView: AnyView) {
        self.onDoubleClick = {
            Task { @MainActor in
                NotchNotifierModel.shared.dismissOverlayState()
            }
        }
        super.init(rootView: rootView)
    }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onDoubleClick()
            return
        }

        super.mouseDown(with: event)
    }
}
