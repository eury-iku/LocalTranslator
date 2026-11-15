import AVFoundation

/// マイクの音を録って、SenseVoice が使える形（16kHz・モノラル・Float）にする。
///
/// 話し始めが切れないように、マイクは先に動かしておき（warmUp）、
/// ボタンを押す少し前の音（preRollSeconds）から使う。
/// 止めるボタンを押したあとも少しだけ（postRollSeconds）録り続けて、語尾が切れないようにする。
/// 音の変換（48kHz など → 16kHz）は、録り終わってからまとめて 1 回で行う。
final class AudioRecorder: @unchecked Sendable {
    enum RecorderError: LocalizedError {
        case noInput

        var errorDescription: String? {
            switch self {
            case .noInput: return "マイクが見つかりませんでした"
            }
        }
    }

    /// 録れた音
    struct Recording {
        /// 16kHz・モノラルの音
        let samples: [Float]
        /// ボタンを押してから止めるまでの秒数（押し間違いの判定に使う）
        let pressedSeconds: Double
    }

    /// SenseVoice が受け取る音の速さ（1 秒あたりのサンプル数）
    static let sampleRate: Double = 16_000
    /// ボタンを押す前の音を、何秒ぶん使うか
    static let preRollSeconds: Double = 0.5
    /// 止めるボタンを押したあと、何秒録り続けるか
    static let postRollSeconds: Double = 0.3

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    /// マイクの音（マイク本来の速さのまま）。録音していない間は、最後の preRollSeconds ぶんだけ残す。
    private var nativeSamples: [Float] = []
    /// マイク本来の速さ（1 秒あたりのサンプル数）
    private var nativeRate: Double = 48_000
    private var isRecording = false
    private var startedAt = Date()
    /// 確認用に聞き返すための、最後に録った音
    private var player: AVAudioPlayer?
    private(set) var lastRecording: [Float] = []

    /// マイクを使ってよいか聞く。すでに答えていれば、すぐに結果が返る。
    static func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        default:
            return await AVAudioApplication.requestRecordPermission()
        }
    }

    /// すでにマイクの許可があるか（許可を聞く画面は出さない）
    static var hasPermission: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    /// マイクを先に動かしておく。すでに動いていれば何もしない。
    /// 電話などでマイクが止まっていたら、ここで動かし直す。
    func warmUp() throws {
        if engine.isRunning { return }

        let session = AVAudioSession.sharedInstance()
        // あとで読み上げも使うので、録音と再生の両方ができるモードにしておく
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw RecorderError.noInput
        }

        lock.lock()
        nativeRate = inputFormat.sampleRate
        nativeSamples.removeAll(keepingCapacity: true)
        lock.unlock()

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    /// 録音を始める。押す少し前の音も含める。
    func start() throws {
        try warmUp()
        player?.stop()
        lock.lock()
        isRecording = true
        startedAt = Date()
        lock.unlock()
    }

    /// 録音を止めて、録れた音を 16kHz にして返す。語尾のために少し待ってから止める。
    func stop() async -> Recording {
        try? await Task.sleep(for: .seconds(Self.postRollSeconds))

        lock.lock()
        let native = nativeSamples
        let rate = nativeRate
        let pressedSeconds = Date().timeIntervalSince(startedAt) - Self.postRollSeconds
        isRecording = false
        nativeSamples.removeAll(keepingCapacity: true)
        lock.unlock()

        let samples = Self.resample(native, from: rate)
        lastRecording = samples
        return Recording(samples: samples, pressedSeconds: pressedSeconds)
    }

    /// 最後に録った音を流す（確認用）
    func playLast() {
        guard !lastRecording.isEmpty,
              let player = try? AVAudioPlayer(data: Self.wavData(lastRecording, sampleRate: Self.sampleRate))
        else { return }
        self.player = player
        player.play()
    }

    /// マイクから届いた音をためていく（マイクが動いている間、何度も呼ばれる）。
    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }

        lock.lock()
        defer { lock.unlock() }
        nativeSamples.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
        if !isRecording {
            // 録音していない間は、最後の preRollSeconds ぶんだけ残す
            let keep = Int(nativeRate * Self.preRollSeconds)
            if nativeSamples.count > keep {
                nativeSamples.removeFirst(nativeSamples.count - keep)
            }
        }
    }

    /// 音を 16kHz に変換する。全部そろってから、まとめて 1 回で行う。
    private static func resample(_ samples: [Float], from rate: Double) -> [Float] {
        guard !samples.isEmpty else { return [] }
        if rate == sampleRate { return samples }

        guard
            let inFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
            let outFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
            let converter = AVAudioConverter(from: inFormat, to: outFormat),
            let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(samples.count)),
            let outBuffer = AVAudioPCMBuffer(
                pcmFormat: outFormat,
                frameCapacity: AVAudioFrameCount(Double(samples.count) * sampleRate / rate) + 1024)
        else { return [] }

        inBuffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            inBuffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }

        var delivered = false
        var error: NSError?
        converter.convert(to: outBuffer, error: &error) { _, status in
            if delivered {
                // もう渡す音はない（最後まで変換しきってもらう）
                status.pointee = .endOfStream
                return nil
            }
            delivered = true
            status.pointee = .haveData
            return inBuffer
        }
        guard error == nil, let channel = outBuffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(outBuffer.frameLength)))
    }

    /// 音を WAV ファイルの形（16bit）にする。聞き返すときに使う。
    private static func wavData(_ samples: [Float], sampleRate: Double) -> Data {
        var data = Data()
        func add<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let rate = UInt32(sampleRate)
        let byteCount = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); add(UInt32(36) + byteCount)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); add(UInt32(16))
        add(UInt16(1)); add(UInt16(1)); add(rate); add(rate * 2); add(UInt16(2)); add(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); add(byteCount)
        for sample in samples {
            add(Int16(max(-1, min(1, sample)) * Float(Int16.max)))
        }
        return data
    }
}
