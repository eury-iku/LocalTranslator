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

    /// マイクを止める（アプリが裏に回ったときに呼ぶ）。録音中だった音は捨てる。
    /// もう一度使うときは warmUp() か start() を呼ぶと、また動き出す。
    func shutDown() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        lock.lock()
        isRecording = false
        nativeSamples.removeAll(keepingCapacity: true)
        lock.unlock()

        // 音を使い終わったことを iPhone に伝える（ほかのアプリの音楽が再開できるようになる）
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 録音を始める。押す少し前の音も含める。
    func start() throws {
        try warmUp()
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

        return Recording(samples: Self.resample(native, from: rate), pressedSeconds: pressedSeconds)
    }

    /// ためてある「押す前の音」を捨てる。録音中は何もしない。
    /// 読み上げの声をマイクが拾っているので、読み上げが終わったときに呼んで、次の録音に混ざらないようにする。
    func discardPreRoll() {
        lock.lock()
        defer { lock.unlock() }
        if !isRecording {
            nativeSamples.removeAll(keepingCapacity: true)
        }
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
}
