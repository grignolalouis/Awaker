import SwiftUI

/// The Claude Code mascot, showing what an agent is doing: trotting while it works, hopping when it
/// needs you, standing still when it is done, asleep and dimmed when it idles. Each agent wears its
/// own accessory, so sessions can be told apart at a glance.
/// Its sub-agents at work trot around it as small bare mascots.
/// The mascot is Anthropic's; it is redrawn here from the block art Claude Code prints at startup.
struct AgentAvatar: View {
    enum Pose {
        case working, waiting, standing, asleep
    }

    let pose: Pose
    /// Picks the accessory. The same seed always gives the same one.
    var seed = ""
    /// Shows this skin whatever the seed and the user's choice. For the showcase in Settings.
    var fixedSkin: AvatarSkin?
    /// How many sub-agents are at work for this agent.
    var companions = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppSettings.self) private var settings

    private let size = CGSize(width: 32, height: 25)
    private let frameInterval = 0.35
    /// Claude's orange.
    private let orange = Color(red: 0.85, green: 0.47, blue: 0.34)
    /// A lighter shade for the small mascots, so they stand out in front of the big one.
    private let lightOrange = Color(red: 0.96, green: 0.66, blue: 0.52)

    var body: some View {
        let skin = fixedSkin ?? AvatarSkin.pick(seed: seed, hidden: settings.hiddenSkins)
        TimelineView(SteadySchedule(interval: frameInterval, paused: !isAnimated)) { timeline in
            let step = isAnimated ? Int(timeline.date.timeIntervalSinceReferenceDate / frameInterval) : 0
            let isAsleep = pose == .asleep
            ZStack(alignment: .topTrailing) {
                PixelSprite(rows: bodyRows(step: step))
                    .fill(orange)
                ForEach(Array(skin.layers.enumerated()), id: \.offset) { _, layer in
                    // Asleep, the mascot sits two cells lower; what it wears follows.
                    PixelSprite(rows: layer.rows, rowOffset: isAsleep ? Sprite.sleepDrop : 0)
                        .fill(layer.fill)
                }
                if let mark {
                    Text(mark)
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundStyle(isAsleep ? AnyShapeStyle(.secondary) : AnyShapeStyle(orange))
                        .offset(x: 5, y: step.isMultiple(of: 2) ? -2 : -5)
                }
            }
            .frame(width: size.width, height: size.height)
            .opacity(isAsleep ? 0.6 : 1)
            .offset(y: lift(step: step))
            // Drawn in the same timeline as the mascot: one timer per row, however many helpers there are.
            .overlay {
                ForEach(0..<min(companions, Self.companionSpots.count), id: \.self) { index in
                    let stepping = isAnimated && (step + index).isMultiple(of: 2)
                    PixelSprite(rows: stepping ? Sprite.stepping : Sprite.standing)
                        .fill(lightOrange)
                        .frame(width: companionSize.width, height: companionSize.height)
                        .offset(x: Self.companionSpots[index].x, y: Self.companionSpots[index].y + (stepping ? -1 : 0))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private let companionSize = CGSize(width: 15, height: 12)
    /// Where the small mascots stand, from the mascot's centre: in front of its feet on both sides, then by its head.
    /// On the left they spill into the row's margin; on the right they must stay clear of the text.
    private static let companionSpots: [CGPoint] = [CGPoint(x: 16, y: 10), CGPoint(x: -18, y: 10), CGPoint(x: -20, y: -8)]

    /// Only agents that are doing something animate; the others are drawn once.
    private var isAnimated: Bool {
        !reduceMotion && (pose == .working || pose == .waiting || companions > 0)
    }

    /// A small sign next to the mascot: asleep, or asking for you.
    private var mark: String? {
        switch pose {
        case .asleep: "z"
        case .waiting: "!"
        case .working, .standing: nil
        }
    }

    /// Vertical hop, in points (negative is up).
    private func lift(step: Int) -> CGFloat {
        switch pose {
        case .working: step.isMultiple(of: 2) ? 0 : -1
        case .waiting: step.isMultiple(of: 2) ? 0 : -4
        case .standing, .asleep: 0
        }
    }

    private func bodyRows(step: Int) -> [String] {
        switch pose {
        case .asleep: Sprite.asleep
        case .standing: Sprite.standing
        case .working, .waiting: step.isMultiple(of: 2) ? Sprite.standing : Sprite.stepping
        }
    }
}

/// What an agent's mascot wears: colored layers on the mascot's grid (`#` is ink).
/// Skins live in `Assets/Skins/skins.json`; preview them with `Scripts/preview-skins.swift`.
struct AvatarSkin: Decodable, Identifiable {
    var id: String { name }

    struct Layer: Decodable {
        let color: String
        let rows: [String]

        /// `color` is "#RRGGBB".
        var fill: Color {
            let value = UInt32(color.dropFirst(), radix: 16) ?? 0xFFFFFF
            return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                         blue: Double(value & 0xFF) / 255)
        }
    }

    let name: String
    let layers: [Layer]

    private static let plain = AvatarSkin(name: "plain", layers: [])

    /// The bundled skins. Empty when the file is missing or invalid: mascots then go bare.
    static let all: [AvatarSkin] = {
        guard let url = Bundle.main.url(forResource: "skins", withExtension: "json", subdirectory: "Skins"),
              let data = try? Data(contentsOf: url),
              let skins = try? JSONDecoder().decode([AvatarSkin].self, from: data) else { return [] }
        return skins
    }()

    /// The same seed always gets the same skin, across launches (not `hashValue`, which changes per process).
    /// Skins the user unchecked are skipped: the agent takes the next one in the list, so hiding a skin
    /// only changes the agents that wore it. With every skin hidden, mascots go bare.
    static func pick(seed: String, hidden: Set<String> = []) -> AvatarSkin {
        guard !all.isEmpty else { return plain }
        let sum = seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        for offset in 0..<all.count {
            let skin = all[(sum + offset) % all.count]
            if !hidden.contains(skin.name) { return skin }
        }
        return plain
    }
}

/// The mascot's frames on an 18 × 14 grid of square cells: 4 rows of headroom for accessories,
/// then the body. The eyes are the two gaps, one cell wide and two tall.
private enum Sprite {
    /// How many rows lower the mascot sits when asleep.
    static let sleepDrop = 2

    private static let headroom = Array(repeating: "..................", count: 4)
    private static let head = "...############..."
    private static let eyes = "...##.######.##..."
    private static let arms = ".################."
    private static let legs = "....#.#....#.#...."
    private static let legsStepping = ".....#.#..#.#....."

    static let standing = headroom + [head, head, eyes, eyes, arms, arms, head, head, legs, legs]
    static let stepping = headroom + [head, head, eyes, eyes, arms, arms, head, head, legsStepping, legs]
    /// Eyes closed, legs tucked in, sitting on the ground.
    static let asleep = headroom + Array(repeating: "..................", count: sleepDrop)
        + [head, head, head, head, arms, arms, head, head]
}

/// Fills the `#` cells of a pixel grid of square cells. The grid is always 18 × 14, so layers line up.
private struct PixelSprite: Shape {
    let rows: [String]
    var rowOffset = 0

    private let columns = 18
    private let gridRows = 14

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cell = min(rect.width / CGFloat(columns), rect.height / CGFloat(gridRows))
        let origin = CGPoint(x: rect.midX - cell * CGFloat(columns) / 2, y: rect.midY - cell * CGFloat(gridRows) / 2)
        for (y, row) in rows.enumerated() {
            for (x, character) in row.enumerated() where character == "#" {
                // A hair of overlap hides the seams between neighbouring cells.
                path.addRect(CGRect(x: origin.x + CGFloat(x) * cell, y: origin.y + CGFloat(y + rowOffset) * cell,
                                    width: cell + 0.3, height: cell + 0.3))
            }
        }
        return path
    }
}
