import Foundation

extension NMEASimulator {

    static let defaultSentenceIntervals: [NMEASentenceType: TimeInterval] = {
        var d: [NMEASentenceType: TimeInterval] = [:]
        d[.mwv] = 1.0
        d[.mwd] = 1.0
        d[.vpw] = 1.0
        d[.hdg] = 0.1
        d[.hdt] = 0.1
        d[.rot] = 0.1
        d[.dpt] = 1.0
        d[.dbt] = 1.0
        d[.mtw] = 1.0
        d[.vhw] = 1.0
        d[.vbw] = 1.0
        d[.vlw] = 5.0
        d[.rmc] = 1.0
        d[.gga] = 1.0
        d[.vtg] = 1.0
        d[.gll] = 1.0
        d[.gsa] = 5.0
        d[.gsv] = 5.0
        d[.zda] = 1.0
        d[.rmb] = 1.0
        d[.xte] = 1.0
        return d
    }()

    static let defaultTalkerIDs: [NMEASentenceType: String] = [
        .rmc: "GP", .gga: "GP", .vtg: "GP", .gll: "GP",
        .gsa: "GP", .gsv: "GP", .zda: "GP",
        .dpt: "SD", .dbt: "SD",
        .hdg: "HC", .hdt: "HE", .rot: "HE",
        .mwv: "II", .mwd: "II", .vpw: "II",
        .vhw: "II", .vbw: "II", .vlw: "II", .mtw: "II",
        .rmb: "GP", .xte: "GP"
    ]

    func applyHardwareProfile(_ profile: HardwareProfile) {
        guard profile != .custom else {
            selectedProfile = profile
            return
        }

        isApplyingHardwareProfile = true
        defer { isApplyingHardwareProfile = false }

        switch profile {
        case .bngTriton2:
            applyFullInstrumentSensors(hasGyro: true)
            applyAllSentenceToggles(enabled: true)
            applySentenceIntervals(Self.defaultSentenceIntervals)
            applyTalkerIDs(Self.defaultTalkerIDs)
            applyProfileSendInterval(matching: Self.defaultSentenceIntervals)

        case .furunoFI70:
            applyFullInstrumentSensors(hasGyro: false)
            applyAllSentenceToggles(enabled: true)
            sentenceToggles.shouldSendHDT = false
            sentenceToggles.shouldSendROT = false
            let intervals: [NMEASentenceType: TimeInterval] = [
                .mwv: 1.0, .mwd: 1.0, .vpw: 1.0,
                .hdg: 1.0,
                .dpt: 1.0, .dbt: 1.0,
                .mtw: 1.0, .vhw: 1.0, .vbw: 1.0, .vlw: 5.0,
                .rmc: 1.0, .gga: 1.0, .vtg: 1.0, .gll: 1.0,
                .gsa: 5.0, .gsv: 5.0, .zda: 1.0
            ]
            applySentenceIntervals(intervals)
            applyTalkerIDs(Self.defaultTalkerIDs)
            applyProfileSendInterval(matching: intervals)

        case .garminGMI20:
            applyFullInstrumentSensors(hasGyro: true)
            applyAllSentenceToggles(enabled: true)
            sentenceToggles.shouldSendGLL = false
            applySentenceIntervals(Self.defaultSentenceIntervals)
            applyGarminTalkerIDs()
            applyProfileSendInterval(matching: Self.defaultSentenceIntervals)

        case .yachtDevicesGateway:
            applyFullInstrumentSensors(hasGyro: true)
            applyAllSentenceToggles(enabled: true)
            let intervals: [NMEASentenceType: TimeInterval] = [
                .mwv: 1.0, .mwd: 1.0, .vpw: 1.0,
                .hdg: 0.1, .hdt: 0.1, .rot: 0.1,
                .dpt: 1.0, .dbt: 1.0,
                .mtw: 1.0, .vhw: 1.0, .vbw: 1.0, .vlw: 5.0,
                .rmc: 0.2, .gga: 0.2, .vtg: 0.2, .gll: 0.2,
                .gsa: 5.0, .gsv: 5.0, .zda: 0.2
            ]
            applySentenceIntervals(intervals)
            applyTalkerIDs(Self.defaultTalkerIDs)
            applyProfileSendInterval(matching: intervals)

        case .minimalGPS:
            sensorToggles = SensorToggleStates(
                hasAnemometer: false,
                hasCompass: false,
                hasGyro: false,
                hasGPS: true,
                hasEchoSounder: false,
                hasSpeedLog: false,
                hasWaterTempSensor: false
            )
            sentenceToggles = SentenceToggleStates(
                shouldSendMWV: false,
                shouldSendMWD: false,
                shouldSendVPW: false,
                shouldSendHDG: false,
                shouldSendHDT: false,
                shouldSendROT: false,
                shouldSendRMC: true,
                shouldSendGGA: true,
                shouldSendVTG: true,
                shouldSendGLL: false,
                shouldSendGSA: true,
                shouldSendGSV: true,
                shouldSendZDA: true,
                shouldSendDBT: false,
                shouldSendDPT: false,
                shouldSendVHW: false,
                shouldSendVLW: false,
                shouldSendVBW: false,
                shouldSendMTW: false,
                shouldSendRMB: false,
                shouldSendXTE: false
            )
            applySentenceIntervals([
                .rmc: 1.0, .gga: 1.0, .vtg: 1.0,
                .gsa: 5.0, .gsv: 5.0, .zda: 1.0
            ])
            applyGarminTalkerIDs()
            applyProfileSendInterval(matching: [
                .rmc: 1.0, .gga: 1.0, .vtg: 1.0,
                .gsa: 5.0, .gsv: 5.0, .zda: 1.0
            ])

        case .custom:
            break
        }

        sentenceRateMode = .realistic
        selectedProfile = profile
    }

    private func applyProfileSendInterval(matching intervals: [NMEASentenceType: TimeInterval]) {
        let minimumInterval = intervals.values.min() ?? interval
        interval = max(0.1, minimumInterval)
    }

    private func applyFullInstrumentSensors(hasGyro: Bool) {
        sensorToggles = SensorToggleStates(
            hasAnemometer: true,
            hasCompass: true,
            hasGyro: hasGyro,
            hasGPS: true,
            hasEchoSounder: true,
            hasSpeedLog: true,
            hasWaterTempSensor: true
        )
    }

    private func applyAllSentenceToggles(enabled: Bool) {
        sentenceToggles = SentenceToggleStates(
            shouldSendMWV: enabled,
            shouldSendMWD: enabled,
            shouldSendVPW: enabled,
            shouldSendHDG: enabled,
            shouldSendHDT: enabled,
            shouldSendROT: enabled,
            shouldSendRMC: enabled,
            shouldSendGGA: enabled,
            shouldSendVTG: enabled,
            shouldSendGLL: enabled,
            shouldSendGSA: enabled,
            shouldSendGSV: enabled,
            shouldSendZDA: enabled,
            shouldSendDBT: enabled,
            shouldSendDPT: enabled,
            shouldSendVHW: enabled,
            shouldSendVLW: enabled,
            shouldSendVBW: enabled,
            shouldSendMTW: enabled,
            shouldSendRMB: enabled,
            shouldSendXTE: enabled
        )
    }

    private func applySentenceIntervals(_ intervals: [NMEASentenceType: TimeInterval]) {
        sentenceIntervals = Dictionary(
            uniqueKeysWithValues: NMEASentenceType.allCases.map { type in
                (type, intervals[type] ?? Self.defaultSentenceIntervals[type] ?? 1.0)
            }
        )
    }

    private func applyTalkerIDs(_ talkerIDs: [NMEASentenceType: String]) {
        perSentenceTalkerID = Dictionary(
            uniqueKeysWithValues: NMEASentenceType.allCases.map { type in
                (type, talkerIDs[type] ?? Self.defaultTalkerIDs[type] ?? talkerID)
            }
        )
    }

    private func applyGarminTalkerIDs() {
        var garminTalkers = Self.defaultTalkerIDs
        for type in NMEASentenceType.allCases {
            garminTalkers[type] = "GP"
        }
        applyTalkerIDs(garminTalkers)
    }
}
