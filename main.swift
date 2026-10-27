import AVFoundation
import AppKit
import Accelerate
import ServiceManagement

let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
let toleranceCents = 15.0

/// Autocorrelation pitch estimate in Hz, or nil for silence / unpitched noise.
func detectPitch(_ samples: [Float], sampleRate: Double) -> Double? {
    let n = samples.count
    let maxLag = min(Int(sampleRate / 60), n / 2)
    return samples.withUnsafeBufferPointer { buf -> Double? in
        let p = buf.baseAddress!
        func corr(_ lag: Int) -> Float {
            var c: Float = 0
            vDSP_dotpr(p, 1, p + lag, 1, &c, vDSP_Length(n - lag))
            return c
        }
        let energy = corr(0)
        guard energy / Float(n) > 1e-5 else { return nil }
        // Skip the zero-lag lobe so we don't lock onto lag 1.
        var lag = 1
        while lag < maxLag && corr(lag) > 0 { lag += 1 }
        var best = lag, bestCorr: Float = -.infinity
        while lag < maxLag {
            let c = corr(lag)
            if c > bestCorr { bestCorr = c; best = lag }
            lag += 1
        }
        guard best > 1, best < maxLag - 1, bestCorr / energy > 0.4 else { return nil }
        // Parabolic interpolation for sub-sample lag.
        let (a, b, c) = (corr(best - 1), bestCorr, corr(best + 1))
        let shift = Double((a - c) / (2 * (a - 2 * b + c)))
        return sampleRate / (Double(best) + (shift.isFinite ? shift : 0))
    }
}

/// Nearest note name and how far off it is, in cents.
func nearestNote(_ freq: Double) -> (name: String, cents: Double) {
    let midi = 69 + 12 * log2(freq / 440)
    let nearest = midi.rounded()
    return (noteNames[Int(nearest) % 12], (midi - nearest) * 100)
}

func isPerfectC(_ freq: Double) -> Bool {
    let note = nearestNote(freq)
    return note.name == "C" && abs(note.cents) <= toleranceCents
}

if CommandLine.arguments.contains("--selftest") {
    func sine(_ f: Double, _ rate: Double = 48000) -> [Float] {
        (0..<4096).map { Float(sin(2 * .pi * f * Double($0) / rate)) }
    }
    for (f, expectC) in [(261.63, true), (130.81, true), (523.25, true), (293.66, false), (246.94, false), (270.0, false)] {
        let pitch = detectPitch(sine(f), sampleRate: 48000)!
        assert(abs(pitch - f) / f < 0.01, "detected \(pitch) for \(f)")
        assert(isPerfectC(pitch) == expectC, "\(f) Hz: expected C=\(expectC)")
    }
    assert(detectPitch([Float](repeating: 0, count: 4096), sampleRate: 48000) == nil)
    print("selftest passed")
    exit(0)
}

let engine = AVAudioEngine()
var paused = false

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
statusItem.button?.title = "🎤 …"
statusItem.menu = NSMenu()
statusItem.menu!.addItem(withTitle: "Sing a perfect C (±\(Int(toleranceCents))¢, any octave)", action: nil, keyEquivalent: "")
statusItem.menu!.addItem(.separator())

final class PauseToggle: NSObject {
    @objc func toggle(_ item: NSMenuItem) {
        paused.toggle()
        if paused {
            engine.stop()  // releases the mic, so the orange indicator goes away
            statusItem.button?.title = "🎤 ⏸"
        } else {
            do { try engine.start() } catch { statusItem.button?.title = "🎤 ⚠️" }
        }
        item.title = paused ? "Resume" : "Pause"
    }
}

let pauseToggle = PauseToggle()
statusItem.menu!.addItem(withTitle: "Pause", action: #selector(PauseToggle.toggle(_:)), keyEquivalent: "p").target = pauseToggle

final class LoginItemToggle: NSObject {
    @objc func toggle(_ item: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch { NSSound.beep() }
        item.state = service.status == .enabled ? .on : .off
    }
}

// Opt in on first launch only, so turning it off sticks.
if !UserDefaults.standard.bool(forKey: "loginItemConfigured") {
    try? SMAppService.mainApp.register()
    UserDefaults.standard.set(true, forKey: "loginItemConfigured")
}
let loginToggle = LoginItemToggle()
let loginItem = statusItem.menu!.addItem(withTitle: "Launch at Login", action: #selector(LoginItemToggle.toggle(_:)), keyEquivalent: "")
loginItem.target = loginToggle
loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
statusItem.menu!.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")


func startListening() {
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        let title: String
        if let f = detectPitch(samples, sampleRate: format.sampleRate) {
            let note = nearestNote(f)
            title = isPerfectC(f) ? "🎯 C" : String(format: "🎤 %@ %+.0f¢", note.name, note.cents)
        } else {
            title = "🎤 …"
        }
        DispatchQueue.main.async { if !paused { statusItem.button?.title = title } }
    }
    do { try engine.start() } catch { statusItem.button?.title = "🎤 ⚠️" }
}

AVCaptureDevice.requestAccess(for: .audio) { granted in
    DispatchQueue.main.async {
        if granted { startListening() } else { statusItem.button?.title = "🎤 🚫" }
    }
}

app.run()
