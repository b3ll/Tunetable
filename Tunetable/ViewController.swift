//
//  ViewController.swift
//  Tunetable
//
//  Created by Adam Bell on 4/29/22.
//

import Accelerate
import AVFAudio
import AVFoundation
import MediaPlayer
import SDWebImage
import ShazamKit
import SwiftUI
import UIKit

class ViewController: UIViewController, SHSessionDelegate {

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

        restartEverything()
    }

    private func restartEverything() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] success in
            guard success else { return }

            self?.fixupAVAudioSessionWithAirPlay {
                self?.restartMatchingAndStreaming()
            }
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

        let failedToFixAirPlay = { [weak self] (error: Error) in
            self?.showAudioEngineFailure("Failed to fix AirPlay: \(error)")
        }

        do {
            try audioSession.setCategory(.playback)

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                do {
                    try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .measurement, policy: .default, options: .allowAirPlay)
                    completion()
                } catch {
                    failedToFixAirPlay(error)
                }
            }
        } catch {
            failedToFixAirPlay(error)
        }
    }

    private func restartMatchingAndStreaming() {
        do {
            updateCurrentItem(with: nil)

            try initMatchingSession()

            AudioEngine.shared.stop()
            AudioEngine.shared.reset()
            AudioEngine.shared.setup()
            
            try AudioEngine.shared.start()

            AudioEngine.shared.stateChanged { [weak self] state in
                switch state {
                    case .stopped:
                        self?.updateSilenceDetectedState(false)
                        self?.updateCurrentItemIfNeeded(nil)
                    case .invalidInput:
                        DispatchQueue.main.async {
                            self?.showInvalidInputAlert()
                        }
                    case .silenceDetected:
                        // silence, do nothing
                        self?.updateSilenceDetectedState(true)
                        self?.updateCurrentItemIfNeeded(nil)
                    case .matching(let buffer, let audioTime):
                        self?.updateSilenceDetectedState(false)
                        self?.session?.matchStreamingBuffer(buffer, at: audioTime)
                }
            }
        } catch {
            showAudioEngineFailure("Failed to start matching: \(error)")
        }
    }

    private func updateSilenceDetectedState(_ silenceDetected: Bool) {
        if nowPlayingInfo.silenceDetected == silenceDetected {
            return
        }

        DispatchQueue.main.async {
            withAnimation(NowPlayingView.defaultSpringAnimation) {
                self.nowPlayingInfo.silenceDetected = silenceDetected
            }
        }
    }

    private func updateCurrentItemIfNeeded(_ item: NowPlayingItem?) {
        if nowPlayingInfo.currentItem == item {
            return
        }

        DispatchQueue.main.async {
            withAnimation(NowPlayingView.defaultSpringAnimation) {
                self.updateCurrentItem(with: nil)
            }
        }
    }

    private func initMatchingSession() throws {
        self.session = SHSession()
        self.session?.delegate = self
    }

    // MARK: - Remote Control Events

    override func remoteControlReceived(with event: UIEvent?) {
        guard let event = event else {
            return
        }

        switch event.subtype {
            case .remoteControlPause, .remoteControlStop:
                AudioEngine.shared.stop()
            case .remoteControlPlay:
                do {
                    try AudioEngine.shared.start()
                } catch {
                    showAudioEngineFailure("Remote control failed: \(error)")
                }
            default:
                break
        }
    }

    // MARK: - Route Changes

    @objc private func audioRouteChanged(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
            case .newDeviceAvailable, .wakeFromSleep:
                DispatchQueue.main.async { [weak self] in
                    self?.restartEverything()
                }
            default:
                break
        }
    }

    private func showInvalidInputAlert() {
        showErrorAlert(title: "Invalid Input", message: "The input from the turntable is invalid (there appears to be no input). Please try detaching and reattaching your audio interface, or disconnecting from any AirPlay destinations and try again.", showRestartButton: true)
    }

    private func showAudioEngineFailure(_ message: String) {
        showErrorAlert(title: "Audio Engine Failure", message: message, showRestartButton: true)
    }

    private func showErrorAlert(title: String, message: String, showRestartButton: Bool) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        if showRestartButton {
            alert.addAction(UIAlertAction(title: "Try Again", style: .default, handler: { [weak self] _ in
                self?.restartMatchingAndStreaming()
                self?.dismiss(animated: true)
            }))
        } else {
            alert.addAction(UIAlertAction(title: "Okay", style: .default, handler: { [weak self] _ in
                self?.dismiss(animated: true)
            }))
        }
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

        withAnimation(NowPlayingView.defaultSpringAnimation) {
            nowPlayingInfo.currentItem = newItem
        }

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

