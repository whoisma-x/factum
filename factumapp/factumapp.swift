//
//  pigeonWidget.swift
//  pigeon
//
//  Live Activity widget for Dynamic Island during study sessions.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct StudyActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StudySessionAttributes.self) { context in
            // Lock Screen banner
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.subject, systemImage: "book.fill")
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(formatTime(context.state.elapsedSeconds))
                        .font(.system(size: 20, weight: .light, design: .monospaced))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if context.state.isPaused {
                            Label("Paused", systemImage: "pause.circle.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.yellow)
                        } else {
                            Label("Studying", systemImage: "timer")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        Text("Started \(context.attributes.startDate, style: .relative) ago")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            } compactLeading: {
                Image(systemName: "book.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
            } compactTrailing: {
                Text(formatTime(context.state.elapsedSeconds))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            } minimal: {
                Image(systemName: "timer")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<StudySessionAttributes>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "book.fill")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.7))

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.subject)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                Text(context.state.isPaused ? "Paused" : "Studying")
                    .font(.system(size: 11))
                    .foregroundStyle(context.state.isPaused ? .yellow : .green)
            }

            Spacer()

            Text(formatTime(context.state.elapsedSeconds))
                .font(.system(size: 28, weight: .light, design: .monospaced))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func formatTime(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
