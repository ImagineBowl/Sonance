//
//  MetronomeTimeSignatureSheet.swift
//  Sonance
//
//  Created by Ahsan Minhas on 18/06/2026.
//

import SwiftUI

struct MetronomeTimeSignatureSheet: View {
    @Binding var timeSignature: TimeSignature
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.12, green: 0.14, blue: 0.18)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    timeSignatureDisplay

                    beatAndNoteControls

                    accentsPreview

                    presetsGrid

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
            .navigationTitle("Time Signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .toolbarBackground(Color(red: 0.12, green: 0.14, blue: 0.18), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var timeSignatureDisplay: some View {
        VStack(spacing: 6) {
            Text("T.S.")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.65))

            Text(timeSignature.displayName)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.15), value: timeSignature.displayName)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Time signature \(timeSignature.displayName)")
    }

    private var beatAndNoteControls: some View {
        HStack(spacing: 16) {
            adjustmentGroup(
                title: "Beat",
                value: "\(timeSignature.beats)",
                decrementAction: decrementBeats,
                incrementAction: incrementBeats,
                decrementLabel: "Decrease beats per bar",
                incrementLabel: "Increase beats per bar"
            )

            adjustmentGroup(
                title: "Note",
                value: "\(timeSignature.noteValue)",
                decrementAction: decrementNoteValue,
                incrementAction: incrementNoteValue,
                decrementLabel: "Decrease note value",
                incrementLabel: "Increase note value"
            )
        }
    }

    private func adjustmentGroup(
        title: String,
        value: String,
        decrementAction: @escaping () -> Void,
        incrementAction: @escaping () -> Void,
        decrementLabel: String,
        incrementLabel: String
    ) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.75))

            HStack(spacing: 12) {
                stepButton(systemImage: "minus", label: decrementLabel, action: decrementAction)

                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .frame(minWidth: 36)

                stepButton(systemImage: "plus", label: incrementLabel, action: incrementAction)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.22))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stepButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.12))
                .clipShape(Circle())
        }
        .accessibilityLabel(label)
    }

    private var accentsPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Accents")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.75))

            HStack(spacing: 14) {
                ForEach(0..<timeSignature.beatsPerBar, id: \.self) { index in
                    VStack(spacing: 4) {
                        Image(systemName: "music.note")
                            .font(.system(size: index == 0 ? 22 : 18, weight: .semibold))
                            .foregroundStyle(index == 0 ? Color.accentColor : Color.white.opacity(0.75))

                        if index == 0 {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(Color.black.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Beat one is accented")
    }

    private var presetsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Presets")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.75))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], spacing: 10) {
                ForEach(TimeSignature.presets) { preset in
                    Button {
                        timeSignature = preset
                    } label: {
                        Text(preset.displayName)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(
                                timeSignature == preset ? Color(red: 0.12, green: 0.14, blue: 0.18) : Color.white
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                timeSignature == preset ? Color.white : Color.white.opacity(0.12)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .accessibilityLabel("Set time signature to \(preset.displayName)")
                }
            }
        }
    }

    private func incrementBeats() {
        var signature = timeSignature
        signature.incrementBeats()
        timeSignature = signature
    }

    private func decrementBeats() {
        var signature = timeSignature
        signature.decrementBeats()
        timeSignature = signature
    }

    private func incrementNoteValue() {
        var signature = timeSignature
        signature.incrementNoteValue()
        timeSignature = signature
    }

    private func decrementNoteValue() {
        var signature = timeSignature
        signature.decrementNoteValue()
        timeSignature = signature
    }
}

#Preview {
    MetronomeTimeSignatureSheet(timeSignature: .constant(.default))
}
