//
//  NowPlayingView.swift
//  Tunetable
//
//  Created by Adam Bell on 4/29/22.
//

import AVFAudio
import AVFoundation
import AVKit
import SwiftUI
import SDWebImage
import SDWebImageSwiftUI
import ShazamKit

struct NowPlayingItem: Equatable {

    let title: String?
    let artist: String?
    let artworkURL: URL?
    let artworkImage: UIImage?

    init(title: String?, artist: String?, artworkURL: URL?) {
        self.title = title
        self.artist = artist
        self.artworkURL = artworkURL
        self.artworkImage = nil
    }

    init(title: String?, artist: String?, artworkImage: UIImage?) {
        self.title = title
        self.artist = artist
        self.artworkURL = nil
        self.artworkImage = artworkImage
    }

}

class NowPlayingInfo: ObservableObject {

    @Published var currentItem: NowPlayingItem?
    @Published var silenceDetected: Bool = false

}

let NeedsAudioEngineRestartNotification = Notification.Name(rawValue: "NeedsAudioEngineRestartNotification")

struct NowPlayingView: View {

    @EnvironmentObject var nowPlayingInfo: NowPlayingInfo

    static let defaultSpringAnimation = Animation.spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0.0)

    var body: some View {
        VStack {
            Spacer()

            ZStack {
                AlbumArtWrap(cornerRadius: 4.0, disableWrap: false, disableShadow: false) {
                    AlbumArtView(url: nowPlayingInfo.currentItem?.artworkURL, image: nowPlayingInfo.currentItem?.artworkImage)
                        .frame(width: 300, height: 300, alignment: .center)
                        .overlay(Color.black.opacity(nowPlayingInfo.currentItem == nil || nowPlayingInfo.silenceDetected ? 0.2 : 0.0))
                }
                .frame(width: 300, height: 300, alignment: .center)
                .scaleEffect(nowPlayingInfo.currentItem == nil || nowPlayingInfo.silenceDetected ? 0.8 : 1.0)
                .onTapGesture {
                    if nowPlayingInfo.silenceDetected {
                        NotificationCenter.default.post(name: NeedsAudioEngineRestartNotification, object: nil)
                    }
                }

                if nowPlayingInfo.currentItem == nil && !nowPlayingInfo.silenceDetected {
                    ActivityIndicator(isAnimating: true) { activityIndicator in
                        activityIndicator.style = .large
                        activityIndicator.color = .white
                    }
                }
            }

            VStack(spacing: 4.0) {
                let title = nowPlayingInfo.currentItem?.title ?? ""
                Text(title)
                    .font(.headline)
                    .transition(.opacity)
                    .id("title" + title)

                let subtitle = nowPlayingInfo.currentItem?.artist ?? ""
                Text(subtitle)
                    .font(.subheadline)
                    .transition(.opacity)
                    .id("subtitle" + subtitle)
            }
            .padding(.vertical, 8.0)

            Spacer()

            AirPlayButton()
                .frame(maxHeight: 64.0)
                .padding(.bottom, 20.0)
        }
        .background(
            GeometryReader { geo in
                Group {
                    if let artworkImage = nowPlayingInfo.currentItem?.artworkImage {
                        Image(uiImage: artworkImage)
                            .resizable()
                            .aspectRatio(1.0, contentMode: .fill)
                    } else {
                        WebImage(url: nowPlayingInfo.currentItem?.artworkURL)
                            .placeholder {
                                EmptyView()
                            }
                            .resizable()
                            .aspectRatio(1.0, contentMode: .fill)
                    }
                }
                .frame(width: geo.size.height, height: geo.size.height)
                .position(x: geo.size.width / 2.0, y: geo.size.height / 2.0)
                .blur(radius: 200.0)
                .opacity(nowPlayingInfo.currentItem?.artworkURL != nil || nowPlayingInfo.currentItem?.artworkImage != nil ? 1.0 : 0.0)
                .overlay(Color.white.opacity(0.1).edgesIgnoringSafeArea(.all))
            }
            .edgesIgnoringSafeArea(.all)
        )
        .animation(NowPlayingView.defaultSpringAnimation, value: nowPlayingInfo.currentItem)
        .animation(NowPlayingView.defaultSpringAnimation, value: nowPlayingInfo.silenceDetected)
    }
}

struct AirPlayButton: UIViewRepresentable {

    func makeUIView(context: Context) -> some UIView {
        let routePicker = AVRoutePickerView(frame: .zero)
        routePicker.tintColor = .label
        return routePicker
    }

    func updateUIView(_ uiView: UIViewType, context: Context) {

    }

}

// Why can't I set the size of a ProgressView -_-
struct ActivityIndicator: UIViewRepresentable {

    var isAnimating: Bool
    fileprivate var configuration = { (activityIndicator: UIActivityIndicatorView) in }

    func makeUIView(context: Context) -> UIActivityIndicatorView {
        return UIActivityIndicatorView()
    }

    func updateUIView(_ uiView: UIActivityIndicatorView, context: Context) {
        isAnimating ? uiView.startAnimating() : uiView.stopAnimating()
        configuration(uiView)
    }

}

struct NowPlayingView_Previews: PreviewProvider {

    static let testNowPlayingItem = NowPlayingItem(title: "Clearest Blue",
                                        artist: "CHVRCHES",
                                        artworkImage: UIImage(named: "EveryOpenEye"))

    static var nowPlayingInfo: NowPlayingInfo = {
        let nowPlayingInfo = NowPlayingInfo()
        nowPlayingInfo.currentItem = testNowPlayingItem
        return nowPlayingInfo
    }()

    static var previews: some View {
        NowPlayingView().environmentObject(nowPlayingInfo)
            .onTapGesture {
                if nowPlayingInfo.currentItem == nil {
                    nowPlayingInfo.currentItem = testNowPlayingItem
                    nowPlayingInfo.silenceDetected = false
                } else {
                    nowPlayingInfo.currentItem = nil
                    nowPlayingInfo.silenceDetected = true
                }
            }
    }

}
