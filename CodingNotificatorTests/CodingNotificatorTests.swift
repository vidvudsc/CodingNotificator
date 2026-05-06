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

}
