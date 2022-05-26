//
//  AudioEngine.swift
//  Tunetable
//
//  Created by Adam Bell on 5/20/22.
//

import Accelerate
import AVFAudio
import AVFoundation
import Foundation

class AudioEngine: NSObject {

    enum State {
        case stopped
        case invalidInput
        case silenceDetected
        case matching(audioBuffer: AVAudioPCMBuffer, audioTime: AVAudioTime)
    }

    let audioEngine = AVAudioEngine()
    var analysisNode: AVAudioMixerNode!
    var outputMixerNode: AVAudioMixerNode!
    private var hasTapInstalledOnAnalysisNode: Bool = false

    static let shared = AudioEngine()

    private(set) var state: State = .stopped {
        didSet {
            self._stateChanged?(state)
        }
    }

    private var _stateChanged: ((State) -> Void)?

    func stateChanged(_ stateChanged: ((State) -> Void)?) {
        self._stateChanged = stateChanged
    }

    func setup() {
        self.analysisNode = AVAudioMixerNode()
        self.outputMixerNode = AVAudioMixerNode()

        let inputFormat = audioEngine.inputNode.inputFormat(forBus: 0)

        if inputFormat.channelCount < 1 {
            self.state = .invalidInput
            return
        }

        let analysisOutputFormat = AVAudioFormat(standardFormatWithSampleRate: inputFormat.sampleRate, channels: 1)
        let outputFormat = AVAudioFormat(standardFormatWithSampleRate: inputFormat.sampleRate, channels: 2)

        audioEngine.attach(analysisNode)
        audioEngine.attach(outputMixerNode)

        audioEngine.connect(audioEngine.inputNode, to: [
            AVAudioConnectionPoint(node: analysisNode, bus: 0),
            AVAudioConnectionPoint(node: outputMixerNode, bus: 0)
        ], fromBus: 0, format: inputFormat)

        analysisNode.installTap(onBus: 0,
                                bufferSize: 8192,
                                format: analysisOutputFormat) { [weak self] buffer, audioTime in
            guard let floatData = buffer.floatChannelData else { return }

            let channelCount = Int(buffer.format.channelCount)
            guard channelCount >= 1 else { return }

            // Accelerate is so neat
            let floatDataPointer = UnsafeBufferPointer(start: floatData[0], count: Int(buffer.frameLength))
            let rms = vDSP.rootMeanSquare(floatDataPointer)

            let power = 20 * log10(rms)
            let level = { () -> Float in
                guard power.isFinite else { return 0.0 }
                let minDb: Float = -80.0
                return max(0.0, min((abs(minDb) - abs(power)) / abs(minDb), 1.0))
            }()

            if level < 0.6 {
                self?.state = .silenceDetected
            } else {
                // now we have samples, what's playing?
                self?.state = .matching(audioBuffer: buffer, audioTime: audioTime)
            }
        }

        self.hasTapInstalledOnAnalysisNode = true

        audioEngine.connect(outputMixerNode, to: audioEngine.mainMixerNode, format: outputFormat)
    }

    func start() throws {
        guard !audioEngine.isRunning else { return }

        try self.audioEngine.start()
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
    }

    func reset() {
        if hasTapInstalledOnAnalysisNode {
            analysisNode?.removeTap(onBus: 0)
            self.hasTapInstalledOnAnalysisNode = false
        }

        if let analysisNode = analysisNode, analysisNode.engine != nil {
            audioEngine.disconnectNodeInput(analysisNode)
            audioEngine.detach(analysisNode)
        }

        if let outputMixerNode = outputMixerNode, outputMixerNode.engine != nil {
            audioEngine.disconnectNodeOutput(outputMixerNode)
            audioEngine.disconnectNodeInput(outputMixerNode)
            audioEngine.detach(outputMixerNode)
        }

        audioEngine.disconnectNodeOutput(audioEngine.inputNode)
        audioEngine.disconnectNodeInput(audioEngine.mainMixerNode)

        audioEngine.reset()
    }

}
