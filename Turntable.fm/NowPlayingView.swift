//
//  NowPlayingView.swift
//  Turntable.fm
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

struct NowPlayingView: View {

    @EnvironmentObject var nowPlayingInfo: NowPlayingInfo

    var body: some View {
        VStack {
            Spacer()

            ZStack {
                AlbumArtWrap(cornerRadius: 4.0, disableWrap: false, disableShadow: false) {
                    AlbumArtView(url: nowPlayingInfo.currentItem?.artworkURL, image: nowPlayingInfo.currentItem?.artworkImage)
                        .frame(width: 300, height: 300, alignment: .center)
                }
                .frame(width: 300, height: 300, alignment: .center)

                if nowPlayingInfo.currentItem == nil && !nowPlayingInfo.silenceDetected {
                    ActivityIndicator(isAnimating: true) { activityIndicator in
                        activityIndicator.style = .large
                        activityIndicator.color = .white
                    }
                }
            }

            VStack(spacing: 4.0) {
                Text(nowPlayingInfo.currentItem?.title ?? "")
                    .font(.headline)

                Text(nowPlayingInfo.currentItem?.artist ?? "")
                    .font(.subheadline)
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
        .animation(.spring(response: 0.3, dampingFraction: 1.0, blendDuration: 0.0), value: nowPlayingInfo.currentItem)
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

    static var nowPlayingInfo: NowPlayingInfo = {
        let nowPlayingInfo = NowPlayingInfo()
        nowPlayingInfo.currentItem = NowPlayingItem(title: "Clearest Blue",
                                                    artist: "CHVRCHES",
                                                    artworkImage: UIImage(named: "EveryOpenEye"))
        return nowPlayingInfo
    }()

    static var previews: some View {
        NowPlayingView().environmentObject(nowPlayingInfo)
    }

}
