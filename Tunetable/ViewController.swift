//
//  ViewController.swift
//  Tunetable
//
//  Created by Adam Bell on 4/29/22.
//

import Accelerate
import AVFAudio
import AVFoundation
import ShazamKit
import UIKit
import SwiftUI
import SDWebImage
import MediaPlayer

class ViewController: UIViewController, SHSessionDelegate {

    let audioEngine = AVAudioEngine()
    var analysisNode: AVAudioMixerNode!
    var outputMixerNode: AVAudioMixerNode!

    let nowPlayingInfo = NowPlayingInfo()

    // The session for the active ShazamKit match request.
    var session: SHSession!

    var currentMatchTimestampOffset: TimeInterval?
    var currentMatchTimestamp: Date? {
        didSet {
            if currentMatchTimestamp != nil {
                // Throttle Shazam requests to 5s. Could be smarter if we knew the duration of the track.
                // TODO: This seems busted?
                self.futureTimestamp = Date(timeIntervalSinceNow: 5.0)
            } else {
                self.futureTimestamp = nil
            }
        }
    }
    var futureTimestamp: Date?

    private var failureCount: Int = 0

    var hostedVC: UIViewController

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        self.hostedVC = UIHostingController(rootView: NowPlayingView().environmentObject(nowPlayingInfo))

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        self.hostedVC = UIHostingController(rootView: NowPlayingView().environmentObject(nowPlayingInfo))

        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        addChild(hostedVC)
        view.addSubview(hostedVC.view)
        hostedVC.didMove(toParent: self)

        UIApplication.shared.beginReceivingRemoteControlEvents()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(audioRouteChanged(notification:)),
                                               name: AVAudioSession.routeChangeNotification,
                                               object: nil)

    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        fixupAVAudioSessionWithAirPlay { [weak self] in
            self?.restartMatchingAndStreaming()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        hostedVC.view.frame = view.bounds
    }

    private func fixupAVAudioSessionWithAirPlay(_ completion: @escaping () -> Void) {
        /**
         Apparently if this app is ever quit when it's connected to AirPlay, subsequent launches will instantly crash.
         This is due to the AVAudioSession being configured with `.playAndRecord`, but when connected to AirPlay the inputs are removed (wat).
         Forcing the category to `.playback` and then switching to `.playAndRecord` after a short duration fixes this crash.

         I guess this app itself only works because it starts out having a category of `.playback` when setting up the AVAudioEngine.

         ¯\_(ツ)_/¯
         */
        let audioSession = AVAudioSession.sharedInstance()

        try? audioSession.setCategory(.playback, mode: .default, policy: .default, options: .allowAirPlay)

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            try? audioSession.setCategory(.playAndRecord, mode: .measurement, policy: .default, options: .allowAirPlay)
            completion()
        }
    }

    func configureAudioEngine() {
        self.analysisNode = AVAudioMixerNode()
        self.outputMixerNode = AVAudioMixerNode()

        let inputFormat = audioEngine.inputNode.inputFormat(forBus: 0)

        if inputFormat.channelCount < 1 {
            showInvalidInputAlert()
            return
        } else if presentedViewController is UIAlertController {
            dismiss(animated: true)
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
                if self?.nowPlayingInfo.currentItem != nil {
                    // silence, do nothing
                    DispatchQueue.main.async {
                        self?.updateCurrentItem(with: nil)
                    }
                }

                if self?.nowPlayingInfo.silenceDetected == false {
                    DispatchQueue.main.async {
                        self?.nowPlayingInfo.silenceDetected = true
                    }
                }
            } else {
                // now we have samples, what's playing?
                self?.addAudio(buffer: buffer, audioTime: audioTime)

                if self?.nowPlayingInfo.silenceDetected == true {
                    DispatchQueue.main.async {
                        self?.nowPlayingInfo.silenceDetected = false
                    }
                }
            }
        }

        audioEngine.connect(outputMixerNode, to: audioEngine.mainMixerNode, format: outputFormat)
    }

    private func addAudio(buffer: AVAudioPCMBuffer, audioTime: AVAudioTime) {
        // This needs some work.
        /* if let _ = currentMatchTimestamp,
           let _ = currentMatchTimestampOffset,
           let futureTimeStamp = futureTimestamp,
           let _ = currentMatch {
            if Date() < futureTimeStamp {
                return
            }
        } */
        session?.matchStreamingBuffer(buffer, at: audioTime)
    }

    private func restartMatchingAndStreaming() {
        do {
            updateCurrentItem(with: nil)

            stopAudioEngine()
            resetAudioEngine()

            configureAudioEngine()

            try startMatching()
        } catch {
            print("Failed to start playback. \(error)")
        }
    }

    private func startMatching() throws {
        self.session = SHSession()
        self.session?.delegate = self

        try startAudioEngine()
    }

    private func startAudioEngine() throws {
        guard !audioEngine.isRunning else { return }
        let audioSession = AVAudioSession.sharedInstance()

        try audioSession.setCategory(.playAndRecord, mode: .measurement, policy: .default, options: .allowAirPlay)
        try audioSession.setPreferredSampleRate(48_000)
        audioSession.requestRecordPermission { [weak self] success in
            guard success, let self = self else { return }
            do {
                try self.audioEngine.start()
            } catch {
                print("Failed to start audio engine: \(error)")
            }
        }
    }

    private func stopAudioEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
    }

    private func resetAudioEngine() {
        analysisNode?.removeTap(onBus: 0)

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

    // MARK: - Route Changes

    @objc private func audioRouteChanged(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
            case .newDeviceAvailable, .oldDeviceUnavailable, .wakeFromSleep:
                DispatchQueue.main.async { [weak self] in
                    self?.restartMatchingAndStreaming()
                }

            case .categoryChange:
                if AVAudioSession.sharedInstance().category == .playAndRecord {
                    DispatchQueue.main.async { [weak self] in
                        self?.restartMatchingAndStreaming()
                    }
                }
            default:
                break
        }
    }

    private func showInvalidInputAlert() {
        let alert = UIAlertController(title: "Invalid Input", message: "The input from the turntable is invalid (there appears to be no input). Please try detaching and reattaching your audio interface, or disconnecting from any AirPlay destinations and try again.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Try Again", style: .default, handler: { [weak self] _ in
            self?.restartMatchingAndStreaming()
        }))
        present(alert, animated: true)
    }

    // MARK: - SHSessionDelegate

    private var bufferedMatchID: String?

    func session(_ session: SHSession, didFind match: SHMatch) {
        guard let firstMatch = match.mediaItems.first else { return }

        // This should hopefully stop random shazam matches causing the now playing info to flicker, slower to match, but should look better?
        // i.e. finding a match, and then finding a new match, and then shazam figuring out it was the original match and flipping back. Now it requires 2 matches before updating.
        if let bufferedMatchID = bufferedMatchID, bufferedMatchID != firstMatch.shazamID {
            self.bufferedMatchID = firstMatch.shazamID
            return
        } else if bufferedMatchID == nil {
            self.bufferedMatchID = firstMatch.shazamID
        }

        DispatchQueue.main.async { [weak self] in
            self?.updateCurrentItem(with: firstMatch)
        }
    }

    func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Only clear things if we've failed to match 3 times in a row.
            if self.failureCount < 3 {
                self.failureCount += 1
            } else {
                self.updateCurrentItem(with: nil)
            }
        }
    }

    // Helpers

    private func updateCurrentItem(with matchedMediaItem: SHMatchedMediaItem?) {
        let newItem: NowPlayingItem?
        if let match = matchedMediaItem {
            newItem = NowPlayingItem(title: match.title, artist: match.artist, artworkURL: match.artworkURL)
        } else {
            newItem = nil
        }

        if newItem == nowPlayingInfo.currentItem {
            return
        }

        self.failureCount = 0
        self.bufferedMatchID = nil

        nowPlayingInfo.currentItem = newItem
        self.updateNowPlaying(with: newItem)
        self.currentMatchTimestampOffset = matchedMediaItem?.predictedCurrentMatchOffset
        self.currentMatchTimestamp = (newItem == nil) ? nil : Date()
    }

    private func updateNowPlaying(with mediaItem: NowPlayingItem?) {
        let infoCenter = MPNowPlayingInfoCenter.default()

        if let mediaItem = mediaItem {
            var nowPlayingInfo: [String: Any] = [
                MPMediaItemPropertyTitle: mediaItem.title ?? "",
                MPMediaItemPropertyArtist: mediaItem.artist ?? ""
            ]

            if let artworkImageURL = mediaItem.artworkURL {
                SDWebImageDownloader.shared.downloadImage(with: artworkImageURL) { image, _, _, _ in
                    if let image = image {
                        nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    }
                    infoCenter.nowPlayingInfo = nowPlayingInfo
                }
            }

            infoCenter.nowPlayingInfo = nowPlayingInfo
        } else {
            infoCenter.nowPlayingInfo = nil
        }
    }

}

