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
}

class NowPlayingInfo: ObservableObject {

    @Published var currentItem: NowPlayingItem?

}

struct NowPlayingView: View {

    @EnvironmentObject var nowPlayingInfo: NowPlayingInfo

    var body: some View {
        VStack {
            Spacer()

            AlbumArtWrap(cornerRadius: 4.0, disableWrap: false, disableShadow: false) {
                AlbumArtView(url: nowPlayingInfo.currentItem?.artworkURL)
                    .frame(width: 300, height: 300, alignment: .center)
            }
            .frame(width: 300, height: 300, alignment: .center)

            Text(nowPlayingInfo.currentItem?.title ?? "")
                .font(.headline)

            Text(nowPlayingInfo.currentItem?.artist ?? "")
                .font(.subheadline)

            Spacer()

            AirPlayButton()
                .frame(maxHeight: 64.0)
                .padding(.bottom, 20.0)
        }
        .background(
            WebImage(url: nowPlayingInfo.currentItem?.artworkURL)
                .placeholder {
                    EmptyView()
                }
                .resizable()
                .aspectRatio(1.0, contentMode: .fill)
                .scaleEffect(6.9)
                .blur(radius: 60.0)
                .opacity(nowPlayingInfo.currentItem?.artworkURL != nil ? 1.0 : 0.0)
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

struct NowPlayingView_Previews: PreviewProvider {
    static var previews: some View {
        NowPlayingView().environmentObject(NowPlayingInfo())
    }
}
