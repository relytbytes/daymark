//
//  DomeView.swift
//  Daymark
//
//  The Dome: an interactive live sky chart. Opens on the sky overhead
//  right now — an equidistant azimuthal projection centered on the
//  zenith, north at top. Pinch to zoom, drag to pan, tap a star for its
//  name. Star catalog and constellation lines are bundled (skydata.json,
//  derived from public-domain catalogs); positions come from the same
//  astronomy engine the Sky Desk already verifies.
//

import SwiftUI

// MARK: - Bundled catalog

struct SkyCatalog {
    struct Star {
        let ra: Double
        let dec: Double
        let mag: Double
        let bv: Double
        let name: String?
    }

    let stars: [Star]
    let lines: [[[Double]]]

    static let shared: SkyCatalog = load()

    private static func load() -> SkyCatalog {
        guard let url = Bundle.main.url(forResource: "skydata", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawStars = raw["stars"] as? [[Any]],
              let rawLines = raw["lines"] as? [[[Double]]]
        else { return SkyCatalog(stars: [], lines: []) }

        let stars = rawStars.compactMap { entry -> Star? in
            guard entry.count >= 4,
                  let ra = entry[0] as? Double,
                  let dec = entry[1] as? Double,
                  let mag = entry[2] as? Double,
                  let bv = entry[3] as? Double
            else { return nil }
            return Star(ra: ra, dec: dec, mag: mag, bv: bv, name: entry.count > 4 ? entry[4] as? String : nil)
        }
        return SkyCatalog(stars: stars, lines: rawLines)
    }
}

// MARK: - The Dome

struct DomeView: View {
    @State private var zoom: CGFloat = 1
    @State private var steadyZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var steadyPan: CGSize = .zero
    @State private var selected: (name: String, mag: Double, point: CGPoint)?

    private let nightGround = Color(red: 0.043, green: 0.063, blue: 0.125)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                Canvas { canvas, canvasSize in
                    draw(canvas: &canvas, size: canvasSize, date: context.date)
                }
                .frame(width: size, height: size)
                .background(nightGround)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .contentShape(Rectangle())
                .gesture(domeGestures(size: size, date: context.date))
            }
            .aspectRatio(1, contentMode: .fit)
        }
    }

    // MARK: Projection

    private func projection(size: CGSize) -> (radius: CGFloat, center: CGPoint) {
        let side = min(size.width, size.height)
        let radius = (side / 2 - 16) * zoom
        let center = CGPoint(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)
        return (radius, center)
    }

    private func project(ra: Double, dec: Double, date: Date, radius: CGFloat, center: CGPoint) -> CGPoint? {
        let h = Astronomy.horizontal(ra: ra, dec: dec, date: date,
                                     latitude: AppConfig.homeLatitude, longitude: AppConfig.homeLongitude)
        guard h.alt > -1 else { return nil }
        let r = radius * CGFloat((90 - h.alt) / 90)
        let azRad = h.az * .pi / 180
        return CGPoint(x: center.x + r * CGFloat(sin(azRad)), y: center.y - r * CGFloat(cos(azRad)))
    }

    private func starColor(_ bv: Double) -> Color {
        switch bv {
        case ..<0.0: return Color(red: 0.81, green: 0.85, blue: 1.0)
        case ..<0.4: return Color(red: 0.93, green: 0.95, blue: 1.0)
        case ..<0.8: return Color(red: 1.0, green: 0.97, blue: 0.91)
        case ..<1.2: return Color(red: 1.0, green: 0.91, blue: 0.77)
        default: return Color(red: 1.0, green: 0.85, blue: 0.63)
        }
    }

    // MARK: Drawing

    private func draw(canvas: inout GraphicsContext, size: CGSize, date: Date) {
        let (radius, center) = projection(size: size)
        let domeRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

        canvas.clip(to: Path(ellipseIn: domeRect))

        // Constellation lines
        for segment in SkyCatalog.shared.lines {
            var previous: CGPoint?
            for point in segment {
                guard point.count >= 2 else { continue }
                let q = project(ra: point[0], dec: point[1], date: date, radius: radius, center: center)
                if let q, let p = previous, hypot(q.x - p.x, q.y - p.y) < radius * 0.7 {
                    var path = Path()
                    path.move(to: p)
                    path.addLine(to: q)
                    canvas.stroke(path, with: .color(Color(red: 0.47, green: 0.55, blue: 0.75).opacity(0.35)), lineWidth: 1)
                }
                previous = q
            }
        }

        // Stars
        for star in SkyCatalog.shared.stars {
            guard let q = project(ra: star.ra, dec: star.dec, date: date, radius: radius, center: center) else { continue }
            let dot = max(0.5, (5.4 - star.mag) * 0.62) * sqrt(zoom)
            canvas.fill(
                Path(ellipseIn: CGRect(x: q.x - dot / 2, y: q.y - dot / 2, width: dot, height: dot)),
                with: .color(starColor(star.bv))
            )
            if let name = star.name, zoom >= 2 || star.mag < 0.8 {
                canvas.draw(
                    Text(name).font(.system(size: 8.5)).foregroundStyle(Color(red: 0.78, green: 0.83, blue: 0.96).opacity(0.75)),
                    at: CGPoint(x: q.x + dot + 14, y: q.y),
                    anchor: .leading
                )
            }
        }

        // Sun, moon, planets
        for body in Astronomy.chartBodies(date: date) {
            guard let q = project(ra: body.ra, dec: body.dec, date: date, radius: radius, center: center) else { continue }
            let (dot, color): (CGFloat, Color) = switch body.kind {
            case .sun: (14 * sqrt(zoom), Color(red: 1.0, green: 0.84, blue: 0.37))
            case .moon: (12 * sqrt(zoom), Color(red: 0.91, green: 0.93, blue: 0.96))
            case .planet: (5.2 * sqrt(zoom), Color(red: 0.94, green: 0.76, blue: 0.43))
            }
            canvas.fill(
                Path(ellipseIn: CGRect(x: q.x - dot / 2, y: q.y - dot / 2, width: dot, height: dot)),
                with: .color(color)
            )
            canvas.draw(
                Text(body.name.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(body.kind == .planet ? Color(red: 0.94, green: 0.76, blue: 0.43) : Color(red: 0.81, green: 0.84, blue: 0.91)),
                at: CGPoint(x: q.x + dot / 2 + 4, y: q.y),
                anchor: .leading
            )
        }

        // Selection ring + label
        if let selected {
            var ring = Path()
            ring.addEllipse(in: CGRect(x: selected.point.x - 8, y: selected.point.y - 8, width: 16, height: 16))
            canvas.stroke(ring, with: .color(Palette.coral), lineWidth: 1.4)
            canvas.draw(
                Text("\(selected.name) · MAG \(String(format: "%.1f", selected.mag))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white),
                at: CGPoint(x: selected.point.x + 12, y: selected.point.y - 12),
                anchor: .leading
            )
        }

        // Horizon ring + cardinals (drawn unclipped-ish: ring sits at radius)
        var horizon = Path()
        horizon.addEllipse(in: domeRect)
        canvas.stroke(horizon, with: .color(Color(red: 0.78, green: 0.82, blue: 0.9).opacity(0.5)), lineWidth: 1.2)
        for (label, az) in [("N", 0.0), ("E", 90.0), ("S", 180.0), ("W", 270.0)] {
            let rad = az * .pi / 180
            let point = CGPoint(
                x: center.x + (radius - 12) * CGFloat(sin(rad)),
                y: center.y - (radius - 12) * CGFloat(cos(rad))
            )
            canvas.draw(
                Text(label).font(.system(size: 10, weight: .heavy)).foregroundStyle(Color(red: 0.86, green: 0.89, blue: 0.96).opacity(0.85)),
                at: point,
                anchor: .center
            )
        }
    }

    // MARK: Gestures

    private func domeGestures(size: CGFloat, date: Date) -> some Gesture {
        let pinch = MagnificationGesture()
            .onChanged { value in
                zoom = min(4, max(1, steadyZoom * value))
                if zoom == 1 { pan = .zero; steadyPan = .zero }
                clampPan(size: size)
            }
            .onEnded { _ in
                steadyZoom = zoom
                steadyPan = pan
            }
        let drag = DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard zoom > 1 else { return }
                pan = CGSize(width: steadyPan.width + value.translation.width,
                             height: steadyPan.height + value.translation.height)
                clampPan(size: size)
            }
            .onEnded { _ in steadyPan = pan }
        let tap = SpatialTapGesture()
            .onEnded { value in
                selectStar(at: value.location, size: CGSize(width: size, height: size), date: date)
            }
        return tap.simultaneously(with: drag).simultaneously(with: pinch)
    }

    private func clampPan(size: CGFloat) {
        let limit = (size / 2) * (zoom - 1)
        pan.width = max(-limit, min(limit, pan.width))
        pan.height = max(-limit, min(limit, pan.height))
    }

    private func selectStar(at location: CGPoint, size: CGSize, date: Date) {
        let (radius, center) = projection(size: size)
        var best: (name: String, mag: Double, point: CGPoint)?
        var bestDistance: CGFloat = 18
        for star in SkyCatalog.shared.stars {
            guard let name = star.name,
                  let q = project(ra: star.ra, dec: star.dec, date: date, radius: radius, center: center)
            else { continue }
            let distance = hypot(q.x - location.x, q.y - location.y)
            if distance < bestDistance {
                best = (name, star.mag, q)
                bestDistance = distance
            }
        }
        selected = best
    }
}
