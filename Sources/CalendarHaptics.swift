import CoreHaptics

/// カレンダーの手触り。広がるときは行が現れる順に「トトトト」と波打ち、閉じるときはその逆
extension Haptics {
    /// 1ヶ月が広がる：じわっと持ち上がって、行の数だけ細かく波打ち、ふわっと着地
    static func unfold(rows: Int) {
        var events = [hum(at: 0, duration: 0.14, intensity: 0.45, sharpness: 0.12)]
        for k in 0..<max(rows - 1, 1) {
            events.append(tap(at: 0.06 + 0.035 * Double(k), intensity: 0.28 + 0.1 * Float(k), sharpness: 0.55))
        }
        events.append(tap(at: 0.08 + 0.035 * Double(rows), intensity: 0.8, sharpness: 0.4))
        run(events, [CHHapticParameterCurve(parameterID: .hapticIntensityControl,
                                            controlPoints: [.init(relativeTime: 0, value: 0.2), .init(relativeTime: 0.14, value: 1)],
                                            relativeTime: 0)])
    }

    /// 1週間へ畳む：すっと縮んで「コトン」
    static func fold() {
        run([tap(at: 0, intensity: 0.35, sharpness: 0.6),
             tap(at: 0.04, intensity: 0.25, sharpness: 0.6),
             tap(at: 0.13, intensity: 0.85, sharpness: 0.35)])
    }
}
