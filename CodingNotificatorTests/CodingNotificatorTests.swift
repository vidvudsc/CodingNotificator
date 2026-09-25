//
//  CodingNotificatorTests.swift
//  CodingNotificatorTests
//
//  Created by Vidvuds Calitis on 11/04/2026.
//

import Testing
import Foundation
@testable import CodingNotificator

struct CodingNotificatorTests {

    @MainActor
    @Test func ignoresCodexDesktopTitleCompletions() async throws {
        let payload: [String: Any] = [
            "type": "agent-turn-complete",
            "client": "Codex Desktop",
            "input-messages": [
                "Generate a concise UI title for this coding task. Do not respond to the user."
            ],
            "last-assistant-message": "{\"title\":\"Fix notifier\"}"
        ]

        #expect(!NotchNotifierModel.shared.shouldShowCodexTurnComplete(payload, source: "Codex"))
    }

    @MainActor
    @Test func keepsNormalCodexDesktopCompletions() async throws {
        let payload: [String: Any] = [
            "type": "agent-turn-complete",
            "client": "Codex Desktop",
            "input-messages": [
                "please check why the done notification fires at the wrong time"
            ],
            "last-assistant-message": "Done, I fixed the notifier."
        ]

        #expect(NotchNotifierModel.shared.shouldShowCodexTurnComplete(payload, source: "Codex"))
    }

    @MainActor
    @Test func ignoresCodexAmbientSuggestionCompletions() async throws {
        let payload: [String: Any] = [
            "type": "agent-turn-complete",
            "client": "Codex Desktop",
            "cwd": "/Users/example/Project",
            "input-messages": [
                "# Overview\n\nGenerate 0 to 3 hyperpersonalized suggestions for what this user can do with Codex in this local project."
            ],
            "last-assistant-message": "{\"suggestions\":[{\"title\":\"Tighten launch checklist\"}]}"
        ]

        #expect(!NotchNotifierModel.shared.shouldShowCodexTurnComplete(payload, source: "Codex"))
    }

    @MainActor
    @Test func ignoresCodexAmbientSuggestionComplianceCompletions() async throws {
        let payload: [String: Any] = [
            "type": "agent-turn-complete",
            "client": "Codex Desktop",
            "cwd": "/",
            "input-messages": [
                "You are an expert at upholding safety and compliance standards for Codex ambient suggestions."
            ],
            "last-assistant-message": "{\"exclude\":[]}"
        ]

        #expect(!NotchNotifierModel.shared.shouldShowCodexTurnComplete(payload, source: "Codex"))
    }

    @MainActor
    @Test func ignoresCodexShortTitleHelperCompletions() async throws {
        let payload: [String: Any] = [
            "type": "agent-turn-complete",
            "client": "Codex Desktop",
            "input-messages": [
                "You are a helpful assistant. You will be presented with a user prompt, and your job is to provide a short title for a task that will be created."
            ],
            "last-assistant-message": "{\n  \"title\": \"Fix widget mode switching\"\n}"
        ]

        #expect(!NotchNotifierModel.shared.shouldShowCodexTurnComplete(payload, source: "Codex"))
    }

    @MainActor
    @Test func ignoresCodexNoToolsHelperCompletions() async throws {
        let payload: [String: Any] = [
            "type": "agent-turn-complete",
            "client": "Codex Desktop",
            "input-messages": [
                "Respond directly to the user's prompt. Do not run shell commands, apply patches, use MCP servers, use web search, or call any tools."
            ],
            "last-assistant-message": "fix-wishlist-visited-widgets"
        ]

        #expect(!NotchNotifierModel.shared.shouldShowCodexTurnComplete(payload, source: "Codex"))
    }

    @MainActor
    @Test func ignoresCodexUserActivitySummaryCompletions() async throws {
        let payload: [String: Any] = [
            "type": "agent-turn-complete",
            "client": "Codex Desktop",
            "input-messages": [
                "You write the one-line activity update displayed beneath an existing Codex task title. Fill the structured summary field with one plain-text sentence. Summarize the user's latest request without implying that the requested work is already complete."
            ],
            "last-assistant-message": "{\"summary\":\"Fix the popup that appears before Codex finishes\"}"
        ]

        #expect(!NotchNotifierModel.shared.shouldShowCodexTurnComplete(payload, source: "Codex"))
    }

    @MainActor
    @Test func ignoresCodexAssistantActivitySummaryCompletions() async throws {
        let payload: [String: Any] = [
            "type": "agent-turn-complete",
            "client": "Codex Desktop",
            "input-messages": [
                "Fill the structured summary field with one plain-text sentence of at most 280 characters. Summarize only what the assistant actually completed, found, answered, recommended, or could not do."
            ],
            "last-assistant-message": "{\"summary\":\"Fixed the notifier and verified the regression tests\"}"
        ]

        #expect(!NotchNotifierModel.shared.shouldShowCodexTurnComplete(payload, source: "Codex"))
    }

    @MainActor
    @Test func ignoresStandaloneCodexSummaryMetadata() async throws {
        let payload: [String: Any] = [
            "type": "agent-turn-complete",
            "client": "Codex Desktop",
            "input-messages": ["Internal metadata update"],
            "last-assistant-message": "{\"summary\":\"Update the visible task activity line\"}"
        ]

        #expect(!NotchNotifierModel.shared.shouldShowCodexTurnComplete(payload, source: "Codex"))
    }

    @MainActor
    @Test func keepsNormalOneMessageCodexCompletions() async throws {
        let payload: [String: Any] = [
            "type": "agent-turn-complete",
            "client": "Codex Desktop",
            "input-messages": [
                "Hey I want to experiment with a small Dit image generator?"
            ],
            "last-assistant-message": "Yep, I set up a small local DiT playground."
        ]

        #expect(NotchNotifierModel.shared.shouldShowCodexTurnComplete(payload, source: "Codex"))
    }

    @MainActor
    @Test func usesCodexCwdProjectNameForDoneTitle() async throws {
        let payload: [String: Any] = [
            "type": "agent-turn-complete",
            "cwd": "/Users/vidvudscalitis/Desktop/CODING/MacHub"
        ]

        #expect(NotchNotifierModel.shared.codexChatDisplayName(from: payload) == "MacHub")
    }

    @MainActor
    @Test func fallsBackToCodexThreadIDWhenCwdIsMissing() async throws {
        let payload: [String: Any] = [
            "type": "agent-turn-complete",
            "thread-id": "019dfd6d-5506-7060-af7e-1532a9f480c6"
        ]

        #expect(NotchNotifierModel.shared.codexChatDisplayName(from: payload) == "Codex 019dfd6d")
    }

    @MainActor
    @Test func keepsMultipleThreadCompletionsVisible() {
        var timeline = NoticeTimeline()
        timeline.record(source: "Codex", threadID: "thread-a", title: "First", detail: "Finished", mode: .done)
        timeline.record(source: "Codex", threadID: "thread-b", title: "Second", detail: "Finished", mode: .done)

        #expect(timeline.notices.map(\.title) == ["Second", "First"])
    }

    @MainActor
    @Test func completionReplacesOnlyItsOwnRunningThread() {
        var timeline = NoticeTimeline()
        timeline.record(source: "Codex", threadID: "thread-a", title: "Working A", detail: "", mode: .running)
        timeline.record(source: "Claude Code", threadID: "session-b", title: "Working B", detail: "", mode: .running)
        timeline.record(source: "Codex", threadID: "thread-a", title: "Finished A", detail: "Done", mode: .done)

        #expect(timeline.notices.count == 2)
        #expect(timeline.notices[0].title == "Finished A")
        #expect(timeline.notices[1].title == "Working B")
        #expect(timeline.notices[1].mode == .running)
    }

    @Test func recognizesPrimaryWeeklyCodexWindow() {
        let weekly: [String: Any] = ["usedPercent": 44, "windowDurationMins": 10_080]
        let limits: [String: Any] = ["primary": weekly, "secondary": NSNull()]

        let selected = UsageReader.codexWeeklyWindow(in: limits)
        #expect(selected?["usedPercent"] as? Int == 44)
    }

    @Test func recognizesSecondaryWeeklyCodexWindow() {
        let limits: [String: Any] = [
            "primary": ["usedPercent": 8, "windowDurationMins": 300],
            "secondary": ["usedPercent": 63, "windowDurationMins": 10_080]
        ]

        let selected = UsageReader.codexWeeklyWindow(in: limits)
        #expect(selected?["usedPercent"] as? Int == 63)
    }

}
