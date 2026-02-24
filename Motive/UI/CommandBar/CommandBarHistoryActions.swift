//
//  CommandBarHistoryActions.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import SwiftUI

extension CommandBarView {
    // MARK: - Histories

    func requestDeleteHistorySession(at index: Int) {
        guard index < filteredHistorySessions.count else { return }
        // Set the selected index to the one being deleted
        selectedHistoryIndex = index
        deleteCandidateIndex = index
        deleteCandidateId = filteredHistorySessions[index].id
        selectedHistoryId = filteredHistorySessions[index].id
        // Show confirmation dialog
        showDeleteConfirmation = true
    }

    var filteredHistorySessions: [Session] {
        if inputText.isEmpty {
            return Array(historySessions.prefix(20))
        }
        let query = inputText.lowercased()
        // Fuzzy score: consecutive bonus, word-boundary bonus, position penalty
        typealias Scored = (session: Session, score: Int)
        let scored: [Scored] = historySessions.compactMap { session in
            guard let score = fuzzyScore(text: session.intent.lowercased(), query: query) else {
                return nil
            }
            return (session, score)
        }
        return scored
            .sorted { $0.score > $1.score }
            .prefix(20)
            .map(\.session)
    }

    /// Returns a fuzzy match score (higher = better) or nil if query chars are not a subsequence.
    private func fuzzyScore(text: String, query: String) -> Int? {
        var score = 0
        var textIdx = text.startIndex
        var queryIdx = query.startIndex
        var lastMatchIdx: String.Index? = nil
        var consecutive = 0

        while queryIdx < query.endIndex {
            guard textIdx < text.endIndex else { return nil }

            if text[textIdx] == query[queryIdx] {
                // Consecutive bonus
                if let last = lastMatchIdx, text.index(after: last) == textIdx {
                    consecutive += 1
                    score += 5 * consecutive
                } else {
                    consecutive = 0
                }
                // Word boundary bonus
                if textIdx == text.startIndex || text[text.index(before: textIdx)] == " " {
                    score += 10
                }
                // Early-position bonus (penalise matches far into text)
                let pos = text.distance(from: text.startIndex, to: textIdx)
                score += max(0, 20 - pos)

                lastMatchIdx = textIdx
                queryIdx = query.index(after: queryIdx)
            }
            textIdx = text.index(after: textIdx)
        }
        return score
    }

    func loadHistorySessions() {
        refreshHistorySessions(preferredIndex: nil)
    }

    func refreshHistorySessions(preferredIndex: Int?) {
        historySessions = appState.getAllSessions()
        let list = filteredHistorySessions
        guard !list.isEmpty else {
            selectedHistoryIndex = 0
            selectedHistoryId = nil
            return
        }

        if let selectedHistoryId,
           let index = list.firstIndex(where: { $0.id == selectedHistoryId })
        {
            selectedHistoryIndex = index
            return
        }

        if let preferredIndex {
            selectedHistoryIndex = min(preferredIndex, list.count - 1)
            selectedHistoryId = list[selectedHistoryIndex].id
            return
        }

        // Select current session if exists, otherwise default to first
        if let currentSession = appState.currentSessionRef,
           let index = list.firstIndex(where: { $0.id == currentSession.id })
        {
            selectedHistoryIndex = index
            selectedHistoryId = currentSession.id
        } else {
            selectedHistoryIndex = 0
            selectedHistoryId = list[0].id
        }
    }

    func selectHistorySession(_ session: Session) {
        appState.switchToSession(session)
        inputText = ""
        if let index = filteredHistorySessions.firstIndex(where: { $0.id == session.id }) {
            selectedHistoryIndex = index
        }
        selectedHistoryId = session.id
        // Stay in CommandBar, switch to appropriate mode based on session status
        if appState.sessionStatus == .running {
            mode = .running
        } else {
            mode = .completed
        }
    }

    func deleteHistorySession(at index: Int) {
        guard index < filteredHistorySessions.count else { return }
        let deleteId = filteredHistorySessions[index].id
        removeHistorySession(id: deleteId, preferredIndex: index)
        appState.deleteSession(id: deleteId)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            refreshHistorySessions(preferredIndex: selectedHistoryIndex)
        }
    }

    func removeHistorySession(id: UUID, preferredIndex: Int) {
        historySessions.removeAll { $0.id == id }
        let list = filteredHistorySessions
        if list.isEmpty {
            selectedHistoryIndex = 0
            selectedHistoryId = nil
        } else {
            selectedHistoryIndex = min(preferredIndex, list.count - 1)
            selectedHistoryId = list[selectedHistoryIndex].id
        }
    }

    // MARK: - Projects

    func selectProject(_ path: String?) {
        appState.switchProjectDirectory(path)
        inputText = ""
        mode = .idle
    }
}
