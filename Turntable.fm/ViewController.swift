//
//  ViewController.swift
//  Turntable.fm
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
    let analysisNode = AVAudioMixerNode()
    let outputMixerNode = AVAudioMixerNode()

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

        configureAudioEngine()

        UIApplication.shared.beginReceivingRemoteControlEvents()

        do {
            try match()
        } catch {
            print("Failed to start playback. \(error)")
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        hostedVC.view.frame = view.bounds
    }

    func configureAudioEngine() {
        let inputFormat = audioEngine.inputNode.inputFormat(forBus: 0)

        let analysisOutputFormat = AVAudioFormat(standardFormatWithSampleRate: inputFormat.sampleRate, channels: 1)
        let outputFormat = AVAudioFormat(standardFormatWithSampleRate: inputFormat.sampleRate, channels: 2)

        audioEngine.attach(analysisNode)
        audioEngine.attach(outputMixerNode)

        audioEngine.connect(audioEngine.inputNode, to: [
            AVAudioConnectionPoint(node: analysisNode, bus: analysisNode.nextAvailableInputBus),
            AVAudioConnectionPoint(node: outputMixerNode, bus: outputMixerNode.nextAvailableInputBus)
        ], fromBus: 0, format: inputFormat)

        analysisNode.installTap(onBus: 0,
                                bufferSize: 8192,
                                format: analysisOutputFormat) { [weak self] buffer, audioTime in
            guard let floatData = buffer.floatChannelData else { return }

            let channelCount = Int(buffer.format.channelCount)
            guard channelCount >= 1 else { return }

            // Accelerate is so neat
            var rms: Float = 0
            vDSP_rmsqv(floatData[0], 1, &rms, UInt(buffer.frameLength))

            let power = 20 * log10(rms)
            let level = { () -> Float in
                guard power.isFinite else { return 0.0 }
                let minDb: Float = -80.0
                return max(0.0, min((abs(minDb) - abs(power)) / abs(minDb), 1.0))
            }()

            if level < 0.6 {
                // silence, do nothing
                DispatchQueue.main.async {
                    self?.updateCurrentItem(with: nil)
                }
            } else {
                // now we have samples, what's playing?
                self?.addAudio(buffer: buffer, audioTime: audioTime)
            }
        }

        audioEngine.connect(outputMixerNode, to: audioEngine.outputNode, format: outputFormat)
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

    func start() throws {
        guard !audioEngine.isRunning else { return }
        let audioSession = AVAudioSession.sharedInstance()

        try audioSession.setCategory(.playAndRecord, mode: .measurement, policy: .default)
        audioSession.requestRecordPermission { [weak self] success in
            guard success, let self = self else { return }
            try? self.audioEngine.start()
        }
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
    }

    func match(_ catalog: SHCustomCatalog? = nil) throws {
        if session == nil {
            if let catalog = catalog {
                self.session = SHSession(catalog: catalog)
            } else {
                self.session = SHSession()
            }
            self.session?.delegate = self
        }

        try start()
    }

    func updateNowPlaying(with mediaItem: NowPlayingItem?) {
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

    // MARK: - SHSessionDelegate

    func session(_ session: SHSession, didFind match: SHMatch) {
        DispatchQueue.main.async { [weak self] in
            self?.updateCurrentItem(with: match.mediaItems.first)
        }
    }

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

        nowPlayingInfo.currentItem = newItem
        self.updateNowPlaying(with: newItem)
        self.currentMatchTimestampOffset = matchedMediaItem?.predictedCurrentMatchOffset
        self.currentMatchTimestamp = (newItem == nil) ? nil : Date()
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

}

