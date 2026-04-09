import SwiftUI

struct ManualView: View {
    @State private var searchText = ""
    @State private var selectedTopicID: ManualTopic.ID?

    private let topics = ManualTopic.defaultTopics

    private var filteredTopics: [ManualTopic] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return topics
        }

        let needle = searchText.lowercased()
        return topics.filter { topic in
            topic.searchBlob.localizedCaseInsensitiveContains(needle)
        }
    }

    private var selectedTopic: ManualTopic? {
        if let selectedTopicID,
           let topic = filteredTopics.first(where: { $0.id == selectedTopicID }) {
            return topic
        }

        return filteredTopics.first
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Manual")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text("Terminology, workflows, transport guidance, and troubleshooting in one place.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Label("\(filteredTopics.count) topics", systemImage: "books.vertical")
                        Label("Searchable", systemImage: "magnifyingglass")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    TextField("Search manual", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(sidebarHeaderBackground)

                List(selection: selectionBinding) {
                    ForEach(filteredTopics) { topic in
                        topicRow(for: topic)
                            .tag(topic.id)
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 300, idealWidth: 320, maxWidth: 360)
            .onAppear {
                selectedTopicID = selectedTopicID ?? topics.first?.id
            }
            .onChange(of: searchText) {
                if filteredTopics.contains(where: { $0.id == selectedTopicID }) == false {
                    selectedTopicID = filteredTopics.first?.id
                }
            }

            if let selectedTopic {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        topicHero(for: selectedTopic)

                        ForEach(selectedTopic.sections) { section in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Circle()
                                        .fill(section.accent.opacity(0.9))
                                        .frame(width: 10, height: 10)

                                    Text(section.title)
                                        .font(.headline)
                                }

                                ForEach(section.paragraphs, id: \.self) { paragraph in
                                    Text(paragraph)
                                        .font(.body)
                                        .foregroundStyle(.primary.opacity(0.9))
                                        .lineSpacing(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                if !section.bullets.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(section.bullets, id: \.self) { bullet in
                                            HStack(alignment: .top, spacing: 10) {
                                                Image(systemName: "sparkle")
                                                    .font(.caption)
                                                    .foregroundStyle(section.accent)
                                                    .frame(width: 14)

                                                Text(bullet)
                                                    .font(.body)
                                                    .foregroundStyle(.primary)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(sectionBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .strokeBorder(section.accent.opacity(0.16), lineWidth: 1)
                            )
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(detailBackground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("No Matching Topic", systemImage: "doc.text.magnifyingglass", description: Text("Try a broader search term."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectionBinding: Binding<ManualTopic.ID?> {
        Binding(
            get: { selectedTopicID ?? filteredTopics.first?.id },
            set: { selectedTopicID = $0 }
        )
    }

    @ViewBuilder
    private func topicRow(for topic: ManualTopic) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(topic.tint.opacity(0.14))
                    .frame(width: 34, height: 34)

                Image(systemName: topic.icon)
                    .foregroundStyle(topic.tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(topic.title)
                    .font(.headline)

                Text(topic.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func topicHero(for topic: ManualTopic) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            LinearGradient(
                                colors: [topic.tint.opacity(0.22), AppColors.consoleBackgroundEnd.opacity(0.32)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)

                    Image(systemName: topic.icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(topic.tint)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(topic.title)
                        .font(.system(size: 30, weight: .bold, design: .rounded))

                    Text(topic.summary)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Label("\(topic.sections.count) sections", systemImage: "square.grid.2x2")
                Label("\(topic.keywords.count) keywords", systemImage: "tag")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(heroBackground(for: topic))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(topic.tint.opacity(0.18), lineWidth: 1)
        )
    }

    private var sidebarHeaderBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                AppColors.consoleBackgroundStart.opacity(0.85),
                AppColors.consoleBackgroundMid.opacity(0.70)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var detailBackground: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                AppColors.consoleBackgroundMid.opacity(0.05),
                AppColors.consoleBackgroundEnd.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var sectionBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Color(nsColor: .controlBackgroundColor).opacity(0.92),
                Color(nsColor: .underPageBackgroundColor).opacity(0.84)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func heroBackground(for topic: ManualTopic) -> some ShapeStyle {
        LinearGradient(
            colors: [
                topic.tint.opacity(0.18),
                AppColors.consoleBackgroundMid.opacity(0.18),
                AppColors.consoleBackgroundEnd.opacity(0.12)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct ManualTopic: Identifiable, Hashable {
    struct Section: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let paragraphs: [String]
        let bullets: [String]
    }

    let id = UUID()
    let title: String
    let icon: String
    let summary: String
    let sections: [Section]
    let keywords: [String]

    var tint: Color {
        switch title {
        case "Getting Started":
            return Color(red: 0.98, green: 0.54, blue: 0.78)
        case "Multiple Outputs":
            return Color(red: 0.21, green: 0.75, blue: 0.72)
        case "UDP vs TCP":
            return Color(red: 0.38, green: 0.62, blue: 0.95)
        case "Sensors and Sentences":
            return Color(red: 0.64, green: 0.55, blue: 0.95)
        case "Terminology":
            return Color(red: 0.92, green: 0.63, blue: 0.42)
        case "Simulation Model":
            return Color(red: 0.28, green: 0.71, blue: 0.55)
        case "Fault Injection":
            return Color(red: 0.95, green: 0.42, blue: 0.39)
        case "Transport Diagnostics":
            return Color(red: 0.94, green: 0.41, blue: 0.70)
        case "Troubleshooting":
            return Color(red: 0.85, green: 0.48, blue: 0.29)
        default:
            return .accentColor
        }
    }

    var searchBlob: String {
        let sectionText = sections.flatMap { [$0.title] + $0.paragraphs + $0.bullets }.joined(separator: " ")
        return ([title, summary] + keywords + [sectionText]).joined(separator: " ")
    }
}

private extension ManualTopic.Section {
    var accent: Color {
        switch title {
        case "Basic Workflow", "How It Works", "UDP", "Sensors", "Navigation Terms", "Snapshot-Based Engine", "Available Faults", "Where To Look", "Connection Refused":
            return AppColors.consoleLineSecondary
        default:
            return AppColors.consoleLinePrimary
        }
    }
}

private extension ManualTopic {
    static let defaultTopics: [ManualTopic] = [
        ManualTopic(
            title: "Getting Started",
            icon: "play.circle",
            summary: "The shortest path from opening the app to transmitting believable NMEA traffic.",
            sections: [
                .init(
                    title: "Basic Workflow",
                    paragraphs: [
                        "Start in Configuration. Set the primary IP, port, talker ID, and whether the timer should run automatically.",
                        "Enable the sensors that exist on the boat you want to imitate. Then go to the sentence screens and enable only the NMEA outputs you want to transmit.",
                        "Use the Dashboard and console together: the dashboard gives you a live feel for the vessel state, while the console confirms the actual NMEA output."
                    ],
                    bullets: [
                        "Configure endpoints first.",
                        "Enable only the instruments you want to imitate.",
                        "Choose sentence families and intervals.",
                        "Start transmission and watch the transport console."
                    ]
                ),
                .init(
                    title: "What A Good Test Looks Like",
                    paragraphs: [
                        "A good simulation run is internally consistent. Heading, GPS track, hydro data, wind, and transport behavior should all match the same vessel scenario.",
                        "If you want to test receiver robustness, enable fault injection and transport diagnostics instead of editing sentence strings by hand."
                    ],
                    bullets: []
                )
            ],
            keywords: ["start", "setup", "first use", "workflow", "begin"]
        ),
        ManualTopic(
            title: "Multiple Outputs",
            icon: "point.3.filled.connected.trianglepath.dotted",
            summary: "Stream the same simulation to more than one consumer at the same time.",
            sections: [
                .init(
                    title: "How It Works",
                    paragraphs: [
                        "Each enabled output endpoint receives the same generated sentences. This lets one simulation feed several listeners at once.",
                        "The primary output stays synchronized with the top IP and port fields. Additional outputs can use different hosts, ports, and transports."
                    ],
                    bullets: [
                        "Local simulator on 127.0.0.1",
                        "Real device on Wi-Fi or Ethernet",
                        "Logger or protocol bridge on a third endpoint"
                    ]
                ),
                .init(
                    title: "Typical Example",
                    paragraphs: [
                        "One practical setup is UDP to a local app and TCP or UDP to a real device at the same time."
                    ],
                    bullets: [
                        "UDP 127.0.0.1:4950 for a local simulator",
                        "UDP 192.168.1.50:4950 for a real device on the boat network"
                    ]
                ),
                .init(
                    title: "What To Check",
                    paragraphs: [
                        "If one endpoint works and another fails, transport history will show which endpoint refused, waited, or recovered."
                    ],
                    bullets: [
                        "Correct IP address",
                        "Correct port",
                        "Correct transport type",
                        "Receiver is already listening"
                    ]
                )
            ],
            keywords: ["multiple ips", "multi ip", "stream", "endpoint", "simulator and device", "network"]
        ),
        ManualTopic(
            title: "UDP vs TCP",
            icon: "antenna.radiowaves.left.and.right",
            summary: "Choose the transport that matches the receiver instead of treating all listeners the same.",
            sections: [
                .init(
                    title: "UDP",
                    paragraphs: [
                        "UDP is datagram-based. It is simple, common in marine tooling, and works well for feeding multiple listeners that do not require a persistent session."
                    ],
                    bullets: [
                        "Good for local simulator apps",
                        "Good for lightweight listeners",
                        "Good when you want several destinations at once"
                    ]
                ),
                .init(
                    title: "TCP",
                    paragraphs: [
                        "TCP is stream-based. Use it when the receiver expects one persistent socket and ordered delivery.",
                        "The simulator now tracks TCP connecting, waiting, ready, failed, and cooldown behavior so repeated failures are visible."
                    ],
                    bullets: [
                        "Good for devices or tools exposing a TCP listener",
                        "Good when ordered stream delivery matters",
                        "Useful when one target wants TCP and another wants UDP"
                    ]
                )
            ],
            keywords: ["udp", "tcp", "transport", "socket", "listener"]
        ),
        ManualTopic(
            title: "External Reader Compatibility",
            icon: "dot.radiowaves.left.and.right",
            summary: "Use a predictable setup when validating the simulator against another app, chartplotter, or device.",
            sections: [
                .init(
                    title: "Recommended Starting Point",
                    paragraphs: [
                        "When testing a new receiver, start from the most conservative setup instead of enabling everything at once.",
                        "That reduces ambiguity and makes it easier to see whether a mismatch is transport, sentence selection, or data interpretation."
                    ],
                    bullets: [
                        "Use UDP unless the receiver explicitly expects TCP",
                        "Leave fault injection disabled",
                        "Set the timer to 1.0 second",
                        "Keep MWV in Relative mode first",
                        "Enable MWD when you want explicit true wind direction"
                    ]
                ),
                .init(
                    title: "Heading And Wind Checks",
                    paragraphs: [
                        "Many compatibility problems are actually interpretation problems. Receivers often treat relative wind, true wind, magnetic heading, and true heading differently."
                    ],
                    bullets: [
                        "HDG follows magnetic heading",
                        "HDT follows gyro heading",
                        "MWV is relative or true-relative, not absolute wind direction",
                        "MWD is the sentence to compare for absolute true wind direction"
                    ]
                ),
                .init(
                    title: "If Values Still Do Not Match",
                    paragraphs: [
                        "Use the raw NMEA console and compare one sentence family at a time. Do not debug wind, heading, and GPS all at once."
                    ],
                    bullets: [
                        "Check that the receiver is reading the same transport you configured",
                        "Check that the receiver is using the same sentence family you are comparing",
                        "Compare raw MWD, MWV, HDG, HDT, VTG, and RMC before trusting the rendered UI"
                    ]
                )
            ],
            keywords: ["compatibility", "reader", "receiver", "chartplotter", "external app", "mwd", "mwv", "hdg", "hdt"]
        ),
        ManualTopic(
            title: "Sensors and Sentences",
            icon: "slider.horizontal.3",
            summary: "Understand the difference between the instruments you have and the NMEA sentences you choose to emit.",
            sections: [
                .init(
                    title: "Sensors",
                    paragraphs: [
                        "Sensor toggles describe what exists onboard: compass, gyro, GPS, speed log, echo sounder, anemometer, and related hardware."
                    ],
                    bullets: []
                ),
                .init(
                    title: "Sentences",
                    paragraphs: [
                        "Sentence toggles describe what the simulator is allowed to transmit. A sentence may still be suppressed if its required sensors are disabled.",
                        "The UI and engine now follow the same dependency rules, so what you see enabled should match what can actually be emitted."
                    ],
                    bullets: [
                        "MWD and VPW need wind plus heading plus boat-speed context",
                        "VHW can use speed plus compass or gyro information",
                        "GPS sentences depend on GPS being enabled"
                    ]
                )
            ],
            keywords: ["sensor", "sentence", "toggles", "dependencies", "interlock"]
        ),
        ManualTopic(
            title: "Terminology",
            icon: "book.closed",
            summary: "Common marine and NMEA terms used in the simulator.",
            sections: [
                .init(
                    title: "Navigation Terms",
                    paragraphs: [],
                    bullets: [
                        "SOG: Speed over ground",
                        "COG: Course over ground",
                        "TWD: True wind direction",
                        "TWS: True wind speed",
                        "AWA: Apparent wind angle",
                        "AWS: Apparent wind speed",
                        "ROT: Rate of turn",
                        "HDOP / VDOP / PDOP: GPS dilution of precision values"
                    ]
                ),
                .init(
                    title: "Transport Terms",
                    paragraphs: [],
                    bullets: [
                        "Endpoint: one destination host and port",
                        "Connected: transport is currently working",
                        "Waiting: TCP is stalled and waiting to recover",
                        "Cooldown: retry pause after repeated TCP failure"
                    ]
                )
            ],
            keywords: ["glossary", "meaning", "definition", "awa", "tws", "sog", "cog", "dop"]
        ),
        ManualTopic(
            title: "Simulation Model",
            icon: "sailboat",
            summary: "How the engine decides what the virtual vessel is doing from one tick to the next.",
            sections: [
                .init(
                    title: "Snapshot-Based Engine",
                    paragraphs: [
                        "Every timer cycle creates one coherent snapshot. All sentences for that cycle are built from that same state.",
                        "This avoids the common simulator bug where one sentence reflects one set of values and the next sentence reflects a different random set."
                    ],
                    bullets: []
                ),
                .init(
                    title: "Water Track vs Ground Track",
                    paragraphs: [
                        "The simulator now separates water-referenced motion from GPS ground track using a current model.",
                        "That is why a speed log can disagree with GPS speed or course in a believable way."
                    ],
                    bullets: []
                )
            ],
            keywords: ["simulation tick", "snapshot", "movement", "current", "water track", "ground track"]
        ),
        ManualTopic(
            title: "Fault Injection",
            icon: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90",
            summary: "Make the output imperfect on purpose so you can test whether a receiver behaves well under stress.",
            sections: [
                .init(
                    title: "Available Faults",
                    paragraphs: [
                        "Fault injection works in the send path, not by changing your configured sentence list. That means the simulator still models the same vessel state while output quality is intentionally degraded."
                    ],
                    bullets: [
                        "Drop sentences entirely",
                        "Delay sentences by one or more cycles",
                        "Corrupt checksums",
                        "Flip selected sentences into invalid status/data states"
                    ]
                ),
                .init(
                    title: "Why It Matters",
                    paragraphs: [
                        "A navigation receiver that only works with perfect traffic is not trustworthy. Use fault injection to verify recovery, timeout logic, checksum rejection, and invalid-fix handling."
                    ],
                    bullets: []
                )
            ],
            keywords: ["fault", "drop", "delay", "checksum", "invalid", "test robustness"]
        ),
        ManualTopic(
            title: "Transport Diagnostics",
            icon: "waveform.path.ecg",
            summary: "Use the built-in event history instead of guessing why a receiver is not getting data.",
            sections: [
                .init(
                    title: "Where To Look",
                    paragraphs: [
                        "The toolbar shows the latest transport state. The console can switch to a transport-history mode. Configuration also shows recent endpoint events."
                    ],
                    bullets: []
                ),
                .init(
                    title: "Typical Meanings",
                    paragraphs: [],
                    bullets: [
                        "Connected: endpoint is currently healthy",
                        "Warning: missing listener, waiting state, or cooldown",
                        "Error: a harder failure that needs attention",
                        "Idle: nothing active right now"
                    ]
                )
            ],
            keywords: ["diagnostics", "history", "warning", "error", "connected", "idle"]
        ),
        ManualTopic(
            title: "Troubleshooting",
            icon: "wrench.and.screwdriver",
            summary: "What to check when a receiver is not behaving the way you expect.",
            sections: [
                .init(
                    title: "Connection Refused",
                    paragraphs: [
                        "This usually means the simulator is transmitting to a host and port where nothing is listening."
                    ],
                    bullets: [
                        "Verify IP address",
                        "Verify port",
                        "Verify UDP vs TCP",
                        "Start the receiver before transmission"
                    ]
                ),
                .init(
                    title: "GPS Looks Too Clean",
                    paragraphs: [
                        "GPS fix support is simulated and coherent, but it is still synthetic rather than driven by a true satellite-sky geometry model."
                    ],
                    bullets: []
                ),
                .init(
                    title: "One Endpoint Works, Another Does Not",
                    paragraphs: [
                        "That is exactly why multi-endpoint status exists. Check the transport history and compare the endpoint rows in Configuration."
                    ],
                    bullets: []
                )
            ],
            keywords: ["troubleshooting", "receiver", "connection refused", "gps", "multi endpoint"]
        )
    ]
}

#Preview {
    ManualView()
        .frame(width: 1000, height: 700)
}
