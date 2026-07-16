//
//  SpiritDesk.swift
//  Daymark
//
//  The Spirit Desk: tarot (78 cards, question-led three-card spread),
//  a house oracle deck, the day's crystal, the day's chakra, and raw
//  material for the AI-composed reading and meditation. Daily draws are
//  deterministic per day; tarot spreads are truly random per question.
//

import Foundation

// MARK: - Tarot

struct TarotCard: Identifiable, Hashable {
    let name: String
    let keywords: String          // upright
    let shadow: String            // reversed
    var reversed = false
    var id: String { name }

    var meaning: String { reversed ? shadow : keywords }
}

enum Tarot {
    static let majorArcana: [(String, String, String)] = [
        ("The Fool", "beginnings, leap of faith, openness", "hesitation, recklessness, false starts"),
        ("The Magician", "will, resourcefulness, manifestation", "scattered energy, untapped talent"),
        ("The High Priestess", "intuition, the inner voice, mystery", "ignored instincts, secrets kept too long"),
        ("The Empress", "abundance, nurture, creation", "creative block, smothering, depletion"),
        ("The Emperor", "structure, authority, stability", "rigidity, control issues, absent discipline"),
        ("The Hierophant", "tradition, mentorship, systems", "dogma, empty convention, rebellion"),
        ("The Lovers", "alignment, choice, union", "misalignment, avoidance of a choice"),
        ("The Chariot", "drive, willpower, momentum", "stalling, pulled in two directions"),
        ("Strength", "quiet courage, patience, resolve", "self-doubt, forcing what needs coaxing"),
        ("The Hermit", "solitude, reflection, inner guidance", "isolation, refusing counsel"),
        ("Wheel of Fortune", "turning points, cycles, luck", "resisting change, bad timing"),
        ("Justice", "fairness, truth, consequence", "imbalance, avoidance of accountability"),
        ("The Hanged Man", "surrender, new perspective, pause", "stalling for its own sake, martyrdom"),
        ("Death", "endings that feed beginnings", "clinging to what is finished"),
        ("Temperance", "balance, patience, blending", "excess, impatience, extremes"),
        ("The Devil", "attachment, patterns, appetite", "breaking chains, reclaiming power"),
        ("The Tower", "sudden change, revelation, release", "disaster resisted, prolonged collapse"),
        ("The Star", "hope, renewal, guidance", "dimmed faith, disconnection"),
        ("The Moon", "uncertainty, dreams, the subconscious", "clarity emerging, fears named"),
        ("The Sun", "vitality, success, plain joy", "clouded optimism, delayed wins"),
        ("Judgement", "reckoning, awakening, the call", "self-judgment, ignoring the call"),
        ("The World", "completion, integration, arrival", "loose ends, the last mile"),
    ]

    static let suits: [(String, String)] = [
        ("Wands", "will, work, and fire"),
        ("Cups", "feeling, relationship, and water"),
        ("Swords", "mind, truth, and air"),
        ("Pentacles", "body, money, and earth"),
    ]

    static let ranks: [(String, String, String)] = [
        ("Ace", "a seed of", "a delayed start in"),
        ("Two", "a choice within", "indecision about"),
        ("Three", "early growth in", "setbacks in"),
        ("Four", "stability in", "stagnation in"),
        ("Five", "conflict over", "recovery from strife in"),
        ("Six", "harmony and progress in", "nostalgia blocking"),
        ("Seven", "assessment of", "doubt about"),
        ("Eight", "movement and mastery in", "burnout around"),
        ("Nine", "near-completion in", "anxiety about"),
        ("Ten", "culmination of", "overload from"),
        ("Page", "curiosity toward", "immaturity around"),
        ("Knight", "pursuit of", "recklessness in"),
        ("Queen", "mastery and care in", "insecurity within"),
        ("King", "command of", "misuse of"),
    ]

    static let deck: [TarotCard] = {
        var cards = majorArcana.map { TarotCard(name: $0.0, keywords: $0.1, shadow: $0.2) }
        for (suit, domain) in suits {
            for (rank, upright, reversed) in ranks {
                cards.append(TarotCard(
                    name: "\(rank) of \(suit)",
                    keywords: "\(upright) \(domain)",
                    shadow: "\(reversed) \(domain)"
                ))
            }
        }
        return cards
    }()

    /// A fresh three-card spread — past, present, future. Truly random.
    static func spread() -> [TarotCard] {
        var drawn = deck.shuffled().prefix(3).map { $0 }
        for index in drawn.indices where Bool.random() {
            drawn[index].reversed = true
        }
        return drawn
    }
}

// MARK: - Oracle

struct OracleCard: Hashable {
    let name: String
    let message: String
}

enum Oracle {
    static let deck: [OracleCard] = [
        OracleCard(name: "The Threshold", message: "A door you already opened is waiting for you to walk through it."),
        OracleCard(name: "The Anchor", message: "Hold one thing steady today and let the rest move around it."),
        OracleCard(name: "The Ember", message: "Something small is still burning. Feed it before tending anything new."),
        OracleCard(name: "The Tide", message: "This is a pulling day, not a pushing day. Time your effort to the water."),
        OracleCard(name: "The Ledger", message: "Count what you actually have. The math is better than the feeling."),
        OracleCard(name: "The Compass", message: "You know the direction. The speed matters less than you think."),
        OracleCard(name: "The Garden", message: "Whatever you planted needs tending, not replanting."),
        OracleCard(name: "The Bridge", message: "Someone on the other side is closer than they appear. Reach."),
        OracleCard(name: "The Lantern", message: "Light only the next few feet. That is enough to keep walking."),
        OracleCard(name: "The Bell", message: "Say the thing plainly today. It will ring louder than eloquence."),
        OracleCard(name: "The Root", message: "Go down before you go up. The foundation is asking for attention."),
        OracleCard(name: "The Feather", message: "Carry today lightly. Not everything needs your full weight."),
        OracleCard(name: "The Key", message: "The lock you keep testing opens from the other side. Ask."),
        OracleCard(name: "The Mirror", message: "What irritates you today is information. Read it, then release it."),
        OracleCard(name: "The Harvest", message: "Take the win that is ready. Perfection would cost the season."),
        OracleCard(name: "The Quiet", message: "The answer arrives in the gap. Make one on purpose."),
        OracleCard(name: "The Knot", message: "Untangle, do not cut — the thread is worth keeping."),
        OracleCard(name: "The Horizon", message: "Lift your eyes once today. Fuel comes from distance, not detail."),
        OracleCard(name: "The Spark", message: "Follow the flicker of interest. It is not a distraction; it is a lead."),
        OracleCard(name: "The Stone", message: "Be unmoved once today, kindly and completely."),
        OracleCard(name: "The River", message: "The current is doing some of the work. Stop swimming against the easy part."),
        OracleCard(name: "The Nest", message: "Home is an instrument. Tune it and everything plays better."),
    ]

    /// Deterministic daily card — the same all day, new each morning.
    static func daily(for date: Date = Date()) -> OracleCard {
        deck[stableDayIndex(date, count: deck.count)]
    }
}

// MARK: - Crystals

struct Crystal: Hashable {
    let name: String
    let property: String
    let use: String
    let intentions: [String]      // what it's best used for
    let practice: String          // how to actually work with it
}

enum Crystals {
    static let cabinet: [Crystal] = [
        Crystal(name: "Clear Quartz", property: "amplification and clarity", use: "hold your first intention of the day",
                intentions: ["Manifesting", "Clarity", "Amplifying"],
                practice: "Program it: hold it, state the intention once, plainly, and keep the stone where you can see it. It amplifies whatever it's charged with — including the other stones on this shelf."),
        Crystal(name: "Amethyst", property: "calm and intuition", use: "keep near during deep work",
                intentions: ["Calm", "Intuition", "Sleep"],
                practice: "Bedside for sleep, desk edge for deep work. When the head races, hold it and take ten slow breaths — it's the settling stone."),
        Crystal(name: "Citrine", property: "confidence and abundance", use: "carry into interviews and negotiations",
                intentions: ["Confidence", "Abundance", "Manifesting"],
                practice: "Pocket it into interviews and negotiations; touch it once before you speak first. It's the merchant's stone — it likes bold, specific asks."),
        Crystal(name: "Black Tourmaline", property: "protection and grounding", use: "set by the door or the desk edge",
                intentions: ["Protection", "Grounding", "Boundaries"],
                practice: "Set it at the door or the edge of the desk to catch the day's static before it reaches you. Rinse and sun it weekly — it works by absorbing."),
        Crystal(name: "Rose Quartz", property: "warmth and self-regard", use: "keep close on heavy days",
                intentions: ["Self-regard", "Warmth", "Healing"],
                practice: "Wear it near the heart or keep it within reach on heavy days. Its work is the inner voice — it softens how you speak to yourself."),
        Crystal(name: "Tiger's Eye", property: "focus and courage", use: "pocket it before hard conversations",
                intentions: ["Courage", "Focus", "Strength"],
                practice: "Pocket it before hard conversations and roll it in the palm when resolve wavers. It holds the middle ground between caution and nerve."),
        Crystal(name: "Green Aventurine", property: "luck and new opportunity", use: "carry when applying and pitching",
                intentions: ["Luck", "Opportunity", "Growth"],
                practice: "Carry it when applying, pitching, or betting on yourself. The gambler's stone only works in motion — pair it with an actual swing taken."),
        Crystal(name: "Labradorite", property: "transformation and insight", use: "hold while journaling",
                intentions: ["Transformation", "Insight", "Magic"],
                practice: "Hold it while journaling or before a crossroads decision, and write down the first thing that surfaces. It favors the question you've been avoiding."),
        Crystal(name: "Carnelian", property: "vitality and momentum", use: "keep near during workouts",
                intentions: ["Vitality", "Momentum", "Creativity"],
                practice: "Keep it near workouts and morning starts. It backs the first move of anything — the opening rep, the first sentence, the send button."),
        Crystal(name: "Sodalite", property: "clear communication", use: "wear or hold before writing",
                intentions: ["Communication", "Truth", "Logic"],
                practice: "Wear it at the throat or hold it before writing and interviews. It steadies the voice by cooling the head first."),
        Crystal(name: "Moonstone", property: "cycles and intuition", use: "best on new and full moon days",
                intentions: ["New beginnings", "Cycles", "Intuition"],
                practice: "Strongest on new and full moons — carry it at fresh starts and endings. Set it on the windowsill overnight to recharge in moonlight."),
        Crystal(name: "Obsidian", property: "truth and release", use: "hold when letting something go",
                intentions: ["Release", "Truth", "Protection"],
                practice: "Hold it when letting something go: name the thing out loud, breathe out slowly, set the stone down. The putting-down is the practice."),
        Crystal(name: "Selenite", property: "cleansing and reset", use: "sweep the aura of the week",
                intentions: ["Cleansing", "Reset", "Peace"],
                practice: "Sweep it slowly from crown to floor at week's end to clear the residue. It cleanses the other stones too — lay them beside it overnight. Never water; it dissolves."),
        Crystal(name: "Pyrite", property: "prosperity and will", use: "keep on the work desk",
                intentions: ["Prosperity", "Will", "Action"],
                practice: "Keep it on the desk where money matters get handled. Fool's gold is the reminder that real gold takes work — it backs effort, not wishes."),
    ]

    static func daily(for date: Date = Date()) -> Crystal {
        cabinet[stableDayIndex(date, count: cabinet.count)]
    }
}

// MARK: - Chakras

struct Chakra: Hashable {
    let name: String
    let sanskrit: String
    let color: String
    let theme: String
    let practice: String
    let location: String          // where it sits in the body
    let signs: String             // how it feels when blocked
}

enum Chakras {
    static let wheel: [Chakra] = [
        Chakra(name: "Root", sanskrit: "Muladhara", color: "red",
               theme: "safety, grounding, the body",
               practice: "Stand barefoot for two minutes; exhale longer than you inhale.",
               location: "Base of the spine",
               signs: "Anxiety with no clear cause, money dread, restlessness, feeling unsafe in a safe room."),
        Chakra(name: "Sacral", sanskrit: "Svadhisthana", color: "orange",
               theme: "creativity, pleasure, flow",
               practice: "Do one thing today purely because it feels good.",
               location: "Just below the navel",
               signs: "Creative block, numbness to things you used to enjoy, guilt about rest and pleasure."),
        Chakra(name: "Solar Plexus", sanskrit: "Manipura", color: "yellow",
               theme: "will, confidence, fire",
               practice: "Name one boundary and keep it all day.",
               location: "Upper abdomen, below the ribs",
               signs: "Self-doubt, people-pleasing, swallowing decisions, a fire that won't light."),
        Chakra(name: "Heart", sanskrit: "Anahata", color: "green",
               theme: "connection, compassion, breath",
               practice: "Send one unprompted kind message.",
               location: "Center of the chest",
               signs: "Guardedness, old grudges kept warm, loneliness even in company, shallow breath."),
        Chakra(name: "Throat", sanskrit: "Vishuddha", color: "blue",
               theme: "voice, truth, expression",
               practice: "Say the true thing once, gently and without apology.",
               location: "The throat",
               signs: "Swallowed words, saying yes while meaning no, a tight jaw, honesty by omission."),
        Chakra(name: "Third Eye", sanskrit: "Ajna", color: "indigo",
               theme: "insight, imagination, pattern",
               practice: "Before deciding anything big, sit with eyes closed for ten breaths.",
               location: "Between the brows",
               signs: "Overthinking that never lands, ignoring a gut call you knew was right, fog where the pattern should be."),
        Chakra(name: "Crown", sanskrit: "Sahasrara", color: "violet",
               theme: "meaning, perspective, stillness",
               practice: "Spend five minutes under open sky doing absolutely nothing.",
               location: "Crown of the head",
               signs: "Cynicism, disconnection, the sense that none of it means anything — usually a tired crown, not a true verdict."),
    ]

    /// How the wheel works as a system — shown at the top of the guide.
    static let systemNote = """
    The seven centers stack like a ladder up the spine, each governing a \
    register of the day: the lower three run survival, appetite, and will; \
    the heart bridges; the upper three run voice, insight, and meaning. \
    Energy moves bottom-up, so a blocked lower center starves everything \
    above it — confidence trouble is often a root problem, and a lost \
    voice is often a heart problem. Balance from the ground up: steady \
    the body first, then the appetites, then the will, and the upper \
    centers usually right themselves.
    """

    static func daily(for date: Date = Date()) -> Chakra {
        wheel[stableDayIndex(date, count: wheel.count)]
    }
}

// MARK: - Shared

/// A stable index for the day: same result all day, changes at midnight.
private func stableDayIndex(_ date: Date, count: Int) -> Int {
    let days = Int(date.timeIntervalSince1970 / 86400)
    return ((days % count) + count) % count
}
