//
//  CommandBarView+Lists.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import SwiftUI

extension CommandBarView {
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
        .frame(maxHeight: .infinity)  // Fill available space
    }
}
