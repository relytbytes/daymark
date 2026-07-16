//
//  SoundCloudWidget.swift
//  Daymark
//
//  SoundCloud's official embed widget in a WKWebView. Their public API
//  registration has been closed for years, so the supported surface is
//  the widget player: it can load any public track, playlist, artist
//  page, or a user's likes, and plays inline. Nothing here needs a key.
//

import SwiftUI
import WebKit

struct SoundCloudWidget: UIViewRepresentable {
    /// Any public SoundCloud URL: artist page, /likes, a set, or a track.
    let resourceURL: String
    var height: CGFloat = 166

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        load(into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.loadedResource != resourceURL {
            load(into: webView)
            context.coordinator.loadedResource = resourceURL
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(loadedResource: resourceURL) }

    final class Coordinator {
        var loadedResource: String
        init(loadedResource: String) { self.loadedResource = loadedResource }
    }

    private func load(into webView: WKWebView) {
        guard let encoded = resourceURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string:
                "https://w.soundcloud.com/player/?url=\(encoded)"
                + "&color=%23c8102e&auto_play=false&hide_related=true"
                + "&show_comments=false&show_user=true&show_reposts=false&visual=false")
        else { return }
        webView.load(URLRequest(url: url))
    }
}


/// RainViewer's embeddable live radar, centered on home.
struct RadarWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.scrollView.isScrollEnabled = false
        let url = URL(string:
            "https://www.rainviewer.com/map.html?loc=\(AppConfig.homeLatitude),\(AppConfig.homeLongitude),8"
            + "&oCS=1&c=3&o=83&lm=1&layer=radar&sm=1&sn=1")!
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
