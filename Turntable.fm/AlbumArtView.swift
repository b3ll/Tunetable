//
//  AlbumArtView.swift
//  AlbumArt
//
//  Created by Adam Bell on 10/9/21.
//

import SDWebImageSwiftUI
import SwiftUI

public struct AlbumArtView: View {

    public let image: UIImage?
    public let url: URL?

    public init(url: URL? = nil, image: UIImage? = nil) {
        self.url = url
        self.image = image
    }

    public var body: some View {
        if let url = url {
            WebImage(url: url)
                .resizable()
                .aspectRatio(1.0, contentMode: .fill)
        } else if let image = image  {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(1.0, contentMode: .fill)
        } else {
            Rectangle()
                .foregroundColor(.gray)
        }
    }

}

public struct AlbumArtWrap<Content>: View where Content: View {

    @Environment(\.colorScheme) var colorScheme

    public var content: Content

    public let cornerRadius: Double

    public let disableWrap: Bool

    public let disableShadow: Bool

    public init(cornerRadius: Double = 3.0, disableWrap: Bool = false, disableShadow: Bool = false, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.disableWrap = disableWrap
        self.disableShadow = disableShadow
        self.content = content()
    }

    public var body: some View {
        GeometryReader { geo in
            let scale = (geo.size.width - (geo.size.width * 0.2237 * 0.66)) / 256.0

            content
                .mask(RoundedRectangle(cornerRadius: disableWrap ? 0.0 : cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.black.opacity(0.5), lineWidth: 1.0 * scale)
                        .foregroundColor(.clear)
                        .opacity(disableWrap ? 0.0 : 1.0)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: disableWrap ? 0.0 : cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(disableWrap ? 0.0 : 0.24), lineWidth: 2.0 * scale)
                        .blendMode(.plusLighter)
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .background(
                    RoundedRectangle(cornerRadius: disableWrap ? 0.0 : cornerRadius, style: .continuous)
                        .foregroundColor(colorScheme == .light ? .white : .black)
                        .shadow(radius: disableWrap ? 0.0 : 2.0, y: disableWrap ? 0.0 : 2.0)
                )
        }
    }

}
