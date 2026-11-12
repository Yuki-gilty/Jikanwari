import CoreHaptics

/// オンボーディングの手触り。押した瞬間の「パチッ」、組み上がっていく「トトトト」、完成の「ふわっ」
extension Haptics {
    /// はじめる：じわっと持ち上がって、コトッと前へ
    static func begin() {
        run([hum(at: 0, duration: 0.18, intensity: 0.55, sharpness: 0.1),
             tap(at: 0.18, intensity: 0.95, sharpness: 0.5),
             tap(at: 0.27, intensity: 0.3, sharpness: 0.3)],
            [CHHapticParameterCurve(parameterID: .hapticIntensityControl,
                                    controlPoints: [.init(relativeTime: 0, value: 0.1), .init(relativeTime: 0.17, value: 1)],
                                    relativeTime: 0)])
    }

    /// 選んだ：澄んだ「パチッ」と、すぐ後の小さな余韻
    static func choose() {
        run([tap(at: 0, intensity: 0.85, sharpness: 0.65), tap(at: 0.06, intensity: 0.28, sharpness: 0.9)])
    }

    /// どれもとっていない：やわらかく沈む「トン」
    static func none() {
        run([hum(at: 0, duration: 0.07, intensity: 0.35, sharpness: 0.05), tap(at: 0.05, intensity: 0.5, sharpness: 0.15)])
    }

    /// ひとつ戻る
    static func back() { run([tap(at: 0, intensity: 0.4, sharpness: 0.4)]) }

    /// 時間割が組み上がっていく。マスが埋まるたびに、だんだん強く・高くなる「トトトト」
    static func assemble(_ times: [TimeInterval]) {
        guard !times.isEmpty else { return }
        let n = Float(max(times.count - 1, 1))
        run(times.enumerated().map { i, t in
            tap(at: t, intensity: 0.22 + 0.5 * Float(i) / n, sharpness: 0.35 + 0.45 * Float(i) / n)
        })
    }

    /// できあがり：「トン、ターン」と着地して、ふわっと抜ける
    static func success() {
        run([tap(at: 0, intensity: 0.55, sharpness: 0.3),
             tap(at: 0.11, intensity: 1, sharpness: 0.6),
             hum(at: 0.11, duration: 0.4, intensity: 0.5, sharpness: 0.15)],
            [CHHapticParameterCurve(parameterID: .hapticIntensityControl,
                                    controlPoints: [.init(relativeTime: 0.11, value: 1), .init(relativeTime: 0.51, value: 0)],
                                    relativeTime: 0)])
    }
}

extension Haptics {
    /// 読み取りが10%進むごと。進むほど少し強く・高くなる「コツ」
    static func progress(_ tenths: Int) {
        let k = Float(min(max(tenths, 1), 10)) / 10
        run([tap(at: 0, intensity: 0.3 + 0.45 * k, sharpness: 0.4 + 0.4 * k)])
    }
}
