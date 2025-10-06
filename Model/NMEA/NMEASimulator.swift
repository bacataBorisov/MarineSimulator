//
//  NMEASimulator.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 7.06.25.
//

import Foundation
import Observation

@Observable
class NMEASimulator {
    
    var ip: String = "127.0.0.1"
    var port: UInt16 = 4950
    var interval: Double = 1.0
    var talkerID: String = "II"
    
    // hydro
    var speed = Metric(min: 7.0, max: 10.0)
    var depth = Metric(min: 4.0, max: 50.0)
    var seaTemp = Metric(min: 22.5, max: 36.0)
    
    // wind
    var twd = Metric(min: 75, max: 90)
    var tws = Metric(min: 8, max: 15)
    var heading = MetricHeading()
    
    // GPS
    
    var gps = GPSData(latitude: 43.0, longitude: 28.0, speedOverGround: 6, courseOverGround: 90)
    
    // Data to be Sent from Configuration Menu (global range)
    var shouldSendWind: Bool = true
    var shouldSendHydro: Bool = true
    var shouldSendCompass: Bool = true
    var shouldSendGPS: Bool = true
    
    
    // isData selected for sending (hydro)
    var sendSpeed = true
    var sendDepth = true
    var sendTemp = true
    var isTimerSelected = true
    
    // isData selected for sending (wind & compass)
    var sendHeading = true
    
    // isData selected for sending (GPS)
    
    var sendGPS = true
    // for the dashboard indicator
    var isTransmitting: Bool = false
    
    // used to alternate between T and R while sending the message
    private var sendRelativeWind = true
    
    // sending to the console log
    var outputMessages: [String] = []
    
    
    //this is the only reference to the UDPClient
    private var udpClient: UDPClient?
    private var timer: Timer?
    
    func configureUDP(ip: String, port: UInt16) {
        self.ip = ip
        self.port = port
        self.udpClient = UDPClient(ip: ip, port: port)
    }
    
    func generateRandomValues() {
        speed.generateRandomValue()
        depth.generateRandomValue()
        seaTemp.generateRandomValue()
        twd.generateRandomValue()
        tws.generateRandomValue()
        heading.generateRandomValue()
    }
    
    func sendAllSelectedNMEA() {
        if sendSpeed {
            sendNMEA(talkerID: talkerID, type: .speed)
        }
        if sendDepth {
            sendNMEA(talkerID: talkerID, type: .depth)
        }
        if sendTemp {
            sendNMEA(talkerID: talkerID, type: .temp)
        }
        
        // if wind and heading are selected - send all the data
        if shouldSendWind && sendHeading {
            let windType: NMEASentenceType = sendRelativeWind ? .apparentWind : .trueWind
            sendNMEA(talkerID: talkerID, type: windType)
            sendRelativeWind.toggle()
        }
        
        //TODO: - if wind is only selected without heading -> send only TWD & TWS
        
        if sendHeading {
            sendNMEA(talkerID: talkerID, type: .heading)
        }
        
        if sendGPS {
            if let sog = speed.value, let cog = heading.value {
                gps.updatePosition(deltaTime: interval, sog: sog, cog: cog)
                sendNMEA(talkerID: talkerID, type: .gps)
            }
        }
    }
    
    func sendNMEA(talkerID: String, type: NMEASentenceType) {
        let sentence = buildNMEASentence(talkerID: talkerID, type: type)
        
        // Send over UDP
        udpClient?.send(sentence)
        
        // Log to console view
        outputMessages.append(sentence)
        
        // Limit to last 100 messages to prevent memory overflow
        if outputMessages.count > 100 {
            outputMessages.removeFirst(outputMessages.count - 100)
        }
    }
    
    private func buildWindSentence(talkerID: String, type: NMEASentenceType) -> String {
        switch type {
        case .trueWind:
            let twa = calculatedTWA ?? 0
            let tws = tws.value ?? 0
            return "$\(talkerID)MWV,\(String(format: "%.f", twa)),T,\(String(format: "%.1f", tws)),N,A"
            
        case .apparentWind:
            let awa = calculatedAWA ?? 0
            let aws = calculatedAWS ?? 0
            return "$\(talkerID)MWV,\(String(format: "%.f", awa)),R,\(String(format: "%.1f", aws)),N,A"
            
        default:
            return ""
        }
    }
    
    private func buildCompassSentence(talkerID: String) -> String {
        let headingString = String(format: "%.1f", heading.value ?? 0)
        return "$\(talkerID)HDG,\(headingString),,,0.0,E"
    }
    
    private func buildHydroSentence(talkerID: String, type: NMEASentenceType) -> String {
        switch type {
        case .speed:
            return "$\(talkerID)VHW,,T,,M,\(String(format: "%.1f", speed.value ?? 0)),N,,K"
        case .depth:
            return "$\(talkerID)DPT,\(String(format: "%.1f", depth.value ?? 0)),0.0"
        case .temp:
            return "$\(talkerID)MTW,\(String(format: "%.1f", seaTemp.value ?? 0)),C"
        default:
            return ""
        }
    }
    
    private func buildGPSSentence(talkerID: String) -> String {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmmss.SS"
        let timeString = formatter.string(from: now)
        
        formatter.dateFormat = "ddMMyy"
        let dateString = formatter.string(from: now)
        
        let latString = FormatKit.formatLatitude(gps.latitude)
        let lonString = FormatKit.formatLongitude(gps.longitude)
        
        let cogString = String(format: "%.1f", gps.courseOverGround)
        let sogString = String(format: "%.1f", gps.speedOverGround)
        
        return "$\(talkerID)RMC,\(timeString),A,\(latString),\(lonString),\(sogString),\(cogString),\(dateString),,,A"
    }
    
    enum NMEASentenceType {
        case speed, depth, temp
        case trueWind, apparentWind, heading
        case gps
    }
    
    private func buildNMEASentence(talkerID: String, type: NMEASentenceType) -> String {
        generateRandomValues()
        
        let sentence: String = {
            switch type {
            case .trueWind, .apparentWind:
                return buildWindSentence(talkerID: talkerID, type: type)
            case .heading:
                return buildCompassSentence(talkerID: talkerID)
            case .speed, .depth, .temp:
                return buildHydroSentence(talkerID: talkerID, type: type)
            case .gps:
                return buildGPSSentence(talkerID: talkerID)
            }
        }()
        
        return addChecksum(to: sentence)
    }
    
    private func addChecksum(to sentence: String) -> String {
        let chars = sentence.dropFirst()
        let checksum = chars.reduce(0) { $0 ^ $1.asciiValue! }
        return "\(sentence)*\(String(format: "%02X", checksum))\r\n"
    }
    
    
    func startSimulation() {
        
        
        configureUDP(ip: ip, port: port)
        stopSimulation() // clear any previous timer
        
        if isTimerSelected {
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.sendAllSelectedNMEA()
            }
            
            // To keep the timer running in common modes (e.g., while dragging UI)
            RunLoop.main.add(timer!, forMode: .common)
        }
        isTransmitting = true
        sendAllSelectedNMEA()
        
    }
    
    func stopSimulation() {
        
        isTransmitting = false
        timer?.invalidate()
        timer = nil
    }
}

// Extend NMEASimulator with wind calculation logic

extension NMEASimulator {
    
    // MARK: - Wind Derived Outputs
    
    var calculatedTWA: Double? {
        guard let twd = twd.value, let heading = heading.value else { return nil }
        let trueDir = normalizeAngle(twd - heading)
        return trueDir
    }
    var calculatedAWS: Double? {
        // Use vector math to estimate AWS based on boat movement and true wind
        guard let tws = tws.value, let twd = twd.value, let heading = heading.value, let bsp = speed.value else { return nil }
        
        let awaRad = toRadians(normalizeAngle(twd - heading))
        
        // Vector addition
        let windX = tws * cos(awaRad)
        let windY = tws * sin(awaRad)
        
        let boatX = bsp
        let boatY = 0.0
        
        let awsX = windX + boatX
        let awsY = windY + boatY
        
        let aws = sqrt(pow(awsX, 2) + pow(awsY, 2))
        return aws
    }
    
    var calculatedAWA: Double? {
        guard let tws = tws.value,
              let twd = twd.value,
              let heading = heading.value,
              let bsp = speed.value else { return nil }
        
        let twa = normalizeAngle(twd - heading)
        let twaRad = toRadians(twa)
        
        // Wind vector
        let windX = tws * cos(twaRad)
        let windY = tws * sin(twaRad)
        
        // Boat vector
        let boatX = bsp
        let boatY = 0.0
        
        // Apparent wind vector (wind - boat)
        let apparentX = windX + boatX
        let apparentY = windY + boatY
        
        let awaRad = atan2(apparentY, apparentX)
        let awa = toDegrees(awaRad)
        
        // Convert to 0...360
        return normalizeAngle(awa)
    }
    
    var calculatedAWD: Double? {
        guard let awa = calculatedAWA, let heading = heading.value else { return nil }
        return normalizeAngle(heading + awa)
    }
    
    
    // MARK: - Formatted Outputs for UI Display
    
    var formattedDepth: String { FormatKit.formattedValue(depth.value, decimals: 1) }
    var formattedSpeed: String { FormatKit.formattedValue(speed.value, decimals: 2) }
    var formattedTemperature: String { FormatKit.formattedValue(seaTemp.value, decimals: 1) }
    var formattedAWA: String { FormatKit.formattedValue(calculatedAWA, decimals: 0) }
    var formattedAWS: String { FormatKit.formattedValue(calculatedAWS, decimals: 1) }
    var formattedAWD: String { FormatKit.formattedValue(calculatedAWD, decimals: 0) }
    var formattedTWA: String { FormatKit.formattedValue(calculatedTWA, decimals: 0) }
    var formattedTWS: String { FormatKit.formattedValue(tws.value, decimals: 1) }
    var formattedTWD: String { FormatKit.formattedValue(twd.value, decimals: 0) }
    
    
    
    
    // MARK: - Helpers
    
    
}
