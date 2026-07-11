//
//  CodingNotificatorTests.swift
//  CodingNotificatorTests
//
//  Created by Vidvuds Calitis on 11/04/2026.
//

import Testing
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

}
