//
//  CommandBarView+Lists.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import SwiftUI

struct ModeChoice {
    let value: String
    let name: String
    let icon: String
    let description: String
}

extension CommandBarView {
    var availableModeChoices: [ModeChoice] {
        var choices: [ModeChoice] = [
            ModeChoice(
                value: "agent",
                name: "Agent",
                icon: "sparkle",
                description: "Default mode - full tool access"
            ),
            ModeChoice(
                value: "plan",
                name: "Plan",
                icon: "checklist",
                description: "Read-only analysis and planning"
            ),
        ]
        if !choices.contains(where: { $0.value == configManager.currentAgent }) {
            let value = configManager.currentAgent
            choices.append(
                ModeChoice(
                    value: value,
                    name: value.prefix(1).uppercased() + String(value.dropFirst()),
                    icon: "circle.hexagongrid.fill",
                    description: "Custom mode from OpenCode config"
                )
            )
        }
        return choices
    }

    var availableModels: [String] {
        var models = configManager.userModelsList
        // Ensure the currently active model appears in the list even if not in userModelsList
        let active = configManager.modelName.trimmingCharacters(in: .whitespaces)
        if !active.isEmpty, !models.contains(active) {
            models.insert(active, at: 0)
        }
        return models
    }

    // MARK: - Histories List (below input)

    var historiesListView: some View {
        CommandBarHistoriesView(
            sessions: filteredHistorySessions,
            selectedIndex: $selectedHistoryIndex,
            onSelect: selectHistorySession,
            onRequestDelete: requestDeleteHistorySession
        )
    }

    // MARK: - Projects List (below input)

    var projectsListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    // "Choose folder..." option at the top
                    ProjectListItem(
                        name: "Choose folder...",
                        path: "",
                        icon: "folder.badge.plus",
                        isSelected: selectedProjectIndex == 0,
                        isCurrent: false
                    ) {
                        appState.showProjectPicker()
                    }
                    .id(0)

                    // Default ~/.motive option
                    ProjectListItem(
                        name: "Default (~/.motive)",
                        path: "~/.motive",
                        icon: "house",
                        isSelected: selectedProjectIndex == 1,
                        isCurrent: configManager.currentProjectPath.isEmpty
                    ) {
                        selectProject(nil)
                    }
                    .id(1)

                    // Recent projects
                    ForEach(Array(configManager.recentProjects.enumerated()), id: \.element.id) { index, project in
                        ProjectListItem(
                            name: project.name,
                            path: project.shortPath,
                            icon: "folder",
                            isSelected: selectedProjectIndex == index + 2,
                            isCurrent: configManager.currentProjectPath == project.path
                        ) {
                            selectProject(project.path)
                        }
                        .id(index + 2)
                    }
                }
                .padding(.vertical, AuroraSpacing.space2)
                .padding(.horizontal, AuroraSpacing.space3)
            }
            .onChange(of: selectedProjectIndex) { _, newIndex in
                withAnimation(.auroraFast) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Modes List (below input)

    var modesListView: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(Array(availableModeChoices.enumerated()), id: \.offset) { index, modeChoice in
                    ModeListItem(
                        name: modeChoice.name,
                        icon: modeChoice.icon,
                        description: modeChoice.description,
                        isSelected: selectedModeIndex == index,
                        isCurrent: configManager.currentAgent == modeChoice.value
                    ) {
                        selectMode(modeChoice.value)
                    }
                    .id(index)
                }
            }
            .padding(.vertical, AuroraSpacing.space2)
            .padding(.horizontal, AuroraSpacing.space3)
        }
        .frame(maxHeight: .infinity)
    }

    private func selectMode(_ mode: String) {
        configManager.currentAgent = mode
        configManager.generateOpenCodeConfig()
        appState.reconfigureBridge()
        let wasFromSession = self.mode.isFromSession || !appState.messages.isEmpty
        self.mode = wasFromSession ? .completed : .idle
        inputText = ""
    }

    private func selectModel(_ model: String) {
        configManager.modelName = model
        // Apply immediately so the bridge uses the new model
        configManager.generateOpenCodeConfig()
        appState.reconfigureBridge()
        let wasFromSession = self.mode.isFromSession || !appState.messages.isEmpty
        self.mode = wasFromSession ? .completed : .idle
        inputText = ""
    }

    // MARK: - Models List (below input)

    var modelsListView: some View {
        Group {
            if availableModels.isEmpty {
                VStack(spacing: AuroraSpacing.space3) {
                    Image(systemName: "cpu")
                        .font(.Aurora.body)
                        .foregroundColor(Color.Aurora.textMuted)
                    Text("No models defined")
                        .font(.Aurora.caption)
                        .foregroundColor(Color.Aurora.textMuted)
                    Text("Add models in Settings")
                        .font(.Aurora.micro)
                        .foregroundColor(Color.Aurora.textMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(availableModels.prefix(20).enumerated()), id: \.offset) { index, model in
                                ModelListItem(
                                    name: model,
                                    isSelected: selectedModelIndex == index,
                                    isCurrent: configManager.modelName == model
                                ) {
                                    selectModel(model)
                                }
                                .id(index)
                            }
                        }
                        .padding(.vertical, AuroraSpacing.space2)
                        .padding(.horizontal, AuroraSpacing.space3)
                    }
                    .onChange(of: selectedModelIndex) { _, newIndex in
                        withAnimation(.auroraFast) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Command List View (Below Input)

    var commandListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, command in
                        CommandListItem(
                            command: command,
                            isSelected: index == selectedCommandIndex
                        ) {
                            executeCommand(command)
                        }
                        .id(index)
                    }
                }
                .padding(.vertical, AuroraSpacing.space2)
                .padding(.horizontal, AuroraSpacing.space3)
            }
            .onChange(of: selectedCommandIndex) { _, newIndex in
                withAnimation(.auroraFast) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
        .frame(maxHeight: .infinity) // Fill available space
    }
}
