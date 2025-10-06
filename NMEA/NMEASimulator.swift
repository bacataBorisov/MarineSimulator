//
//  NMEASimulator.swift
//  NMEASimulator
//
//  Created by Vasil Borisov on 7.06.25.
//

import Foundation
import Observation
import CoreLocation

@Observable
class NMEASimulator {
    
    var sentenceToggles = SentenceToggleStates()
    var sensorToggles = SensorToggleStates()
    
    //MARK: - Network & Connectivity
    var ip: String = "127.0.0.1"
    var port: UInt16 = 4950
    var isTimerSelected = true
    var interval: Double = 1.0 {
        didSet {
            if isTransmitting && isTimerSelected {
                restartTimer()
            }
        }
    }    
    var talkerID: String = "II"
    
    //MARK: - Hydro

    var speed = SimulatedValue(type: .speedLog)
    var depth = SimulatedValue(type: .depth)
    var seaTemp = SimulatedValue(type: .seaTemp)
    

    //MARK: - Wind

    var twd = SimulatedValue(type: .windDirection)
    var tws = SimulatedValue(type: .windSpeed)

    /// used to alternate between T and R while sending the message

    private var sendRelativeWind = true
    //MARK: - Compass

    var heading = SimulatedValue(type: .magneticCompass)
    var gyroHeading = SimulatedValue(type: .gyroCompass)

    //MARK: - GPS & Positioning
    /// GPS Variables
    var gps = GPSData(latitude: 43.0, longitude: 28.0, speedOverGround: 6, courseOverGround: 90)
    let testPosition = CLLocationCoordinate2D(latitude: 43.0, longitude: 28.0)
    // for the dashboard indicator
    var isTransmitting: Bool = false

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
    
    // mechanism to display "--" when value is not selected
    func maskedValue(_ value: Double?, isEnabled: Bool) -> Double? {
        return isEnabled ? value : nil
    }
    
    
    //TODO: - Here, there must be a better way of that to be written
    func generateRandomValues() {
        speed.value = speed.generateRandomValue(shouldGenerate: hasBoatSpeed)
        depth.value = depth.generateRandomValue(shouldGenerate: sensorToggles.hasEchoSounder)
        seaTemp.value = seaTemp.generateRandomValue(shouldGenerate: sensorToggles.hasWaterTempSensor)

        twd.value = twd.generateRandomValue()
        tws.value = tws.generateRandomValue()
        heading.value = heading.generateRandomValue(shouldGenerate: sensorToggles.hasCompass)
        gyroHeading.value = gyroHeading.generateRandomValue(shouldGenerate: sensorToggles.hasGyro)

    }
    
    func sendAllSelectedNMEA() {
        if sensorToggles.hasSpeedLog {
            sendNMEA(talkerID: talkerID, type: .speed)
        }
        if sensorToggles.hasEchoSounder {
            sendNMEA(talkerID: talkerID, type: .depth)
        }
        if sensorToggles.hasWaterTempSensor {
            sendNMEA(talkerID: talkerID, type: .temp)
        }
        
        // WIND INTERLOCK
        if hasAnemometer && (sentenceToggles.shouldSendMWV ||
                             sentenceToggles.shouldSendMWD ||
                             sentenceToggles.shouldSendVPW) {
            if canSendFullWindData {
                let windType: NMEASentenceType = sendRelativeWind ? .apparentWind : .trueWind
                if sentenceToggles.shouldSendMWV {
                    sendNMEA(talkerID: talkerID, type: windType)
                }
                if sentenceToggles.shouldSendMWD {
                    sendNMEA(talkerID: talkerID, type: .mwd)
                }
                if sentenceToggles.shouldSendVPW {
                    sendNMEA(talkerID: talkerID, type: .vpw)
                }
                sendRelativeWind.toggle()
            } else if canSendTrueWind {
                let windType: NMEASentenceType = sendRelativeWind ? .apparentWind : .trueWind
                if sentenceToggles.shouldSendMWV {
                    sendNMEA(talkerID: talkerID, type: windType)
                }
                sendRelativeWind.toggle()
            } else {
                if sentenceToggles.shouldSendMWV {
                    sendNMEA(talkerID: talkerID, type: .apparentWind)
                }
            }
        }
                
        if sensorToggles.hasCompass {
            sendNMEA(talkerID: talkerID, type: .hdg)
        }
        if sensorToggles.hasGyro {
            sendNMEA(talkerID: talkerID, type: .hdt)
            sendNMEA(talkerID: talkerID, type: .rot)
        }
        
        if sensorToggles.hasGPS {

            gps.updatePosition(deltaTime: interval, sog: speed.value ?? 0, cog: heading.value ?? 0)
                sendNMEA(talkerID: talkerID, type: .gps)
            
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
    
    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.sendAllSelectedNMEA()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
}

// MARK: - Interlock Helpers

extension NMEASimulator {
    
    var hasAnemometer: Bool {
        sensorToggles.hasAnemometer
    }

    var hasBoatSpeed: Bool {
        // Consider SOG (GPS) or speed log
        sensorToggles.hasSpeedLog || sensorToggles.hasGPS
    }

    var hasTrueHeading: Bool {
        sensorToggles.hasGyro || sensorToggles.hasCompass
    }

    var canSendTrueWind: Bool {
        hasAnemometer && hasBoatSpeed
    }

    var canSendFullWindData: Bool {
        canSendTrueWind && hasTrueHeading
    }
}
