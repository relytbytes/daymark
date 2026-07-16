// Daymark astronomy engine (web) — the same low-precision Schlyter/Meeus
// algorithms as the iOS Astronomy.swift, accurate to a few minutes.
// Everything computes locally; nothing here touches the network.
/* eslint-disable no-var */

window.DaymarkAstro = (() => {
  const RAD2DEG = 180 / Math.PI;
  const ZODIAC = [
    "Aries", "Taurus", "Gemini", "Cancer", "Leo", "Virgo",
    "Libra", "Scorpio", "Sagittarius", "Capricorn", "Aquarius", "Pisces",
  ];
  const sinD = (x) => Math.sin(x / RAD2DEG);
  const cosD = (x) => Math.cos(x / RAD2DEG);
  const atan2D = (y, x) => Math.atan2(y, x) * RAD2DEG;
  const norm = (d) => ((d % 360) + 360) % 360;

  const julianDay = (date) => date.getTime() / 86400000 + 2440587.5;

  function solarEclipticLongitude(jd) {
    const t = (jd - 2451545.0) / 36525.0;
    const l0 = norm(280.46646 + 36000.76983 * t);
    const m = norm(357.52911 + 35999.05029 * t);
    const c =
      (1.914602 - 0.004817 * t) * sinD(m) +
      (0.019993 - 0.000101 * t) * sinD(2 * m) +
      0.000289 * sinD(3 * m);
    return norm(l0 + c);
  }

  function moonPosition(jd) {
    const d = jd - 2451543.5;
    const n = norm(125.1228 - 0.0529538083 * d);
    const i = 5.1454;
    const w = norm(318.0634 + 0.1643573223 * d);
    const a = 60.2666;
    const e = 0.0549;
    const m = norm(115.3654 + 13.0649929509 * d);

    let ecc = m + RAD2DEG * e * sinD(m) * (1 + e * cosD(m));
    for (let k = 0; k < 5; k += 1) {
      ecc -= (ecc - RAD2DEG * e * sinD(ecc) - m) / (1 - e * cosD(ecc));
    }
    const xv = a * (cosD(ecc) - e);
    const yv = a * (Math.sqrt(1 - e * e) * sinD(ecc));
    const v = norm(atan2D(yv, xv));
    const r = Math.sqrt(xv * xv + yv * yv);

    const xh = r * (cosD(n) * cosD(v + w) - sinD(n) * sinD(v + w) * cosD(i));
    const yh = r * (sinD(n) * cosD(v + w) + cosD(n) * sinD(v + w) * cosD(i));
    const zh = r * sinD(v + w) * sinD(i);

    let lon = norm(atan2D(yh, xh));
    const lat = atan2D(zh, Math.sqrt(xh * xh + yh * yh));

    const ms = norm(356.047 + 0.9856002585 * d);
    const ws = 282.9404 + 4.70935e-5 * d;
    const ls = norm(ms + ws);
    const lm = norm(m + w + n);
    const dm = norm(lm - ls);
    lon +=
      -1.274 * sinD(m - 2 * dm) +
      0.658 * sinD(2 * dm) -
      0.186 * sinD(ms) -
      0.059 * sinD(2 * m - 2 * dm) -
      0.057 * sinD(m - 2 * dm + ms) +
      0.053 * sinD(m + 2 * dm) +
      0.046 * sinD(2 * dm - ms) +
      0.041 * sinD(m - ms) -
      0.035 * sinD(dm) -
      0.031 * sinD(m + ms);
    return { lon: norm(lon), lat, dist: r };
  }

  const PLANETS = {
    Mercury: { n: [48.3313, 3.24587e-5], i: [7.0047, 5.0e-8], w: [29.1241, 1.01444e-5], a: 0.387098, e: [0.205635, 5.59e-10], m: [168.6562, 4.0923344368] },
    Venus: { n: [76.6799, 2.4659e-5], i: [3.3946, 2.75e-8], w: [54.891, 1.38374e-5], a: 0.72333, e: [0.006773, -1.302e-9], m: [48.0052, 1.6021302244] },
    Mars: { n: [49.5574, 2.11081e-5], i: [1.8497, -1.78e-8], w: [286.5016, 2.92961e-5], a: 1.523688, e: [0.093405, 2.516e-9], m: [18.6021, 0.5240207766] },
    Jupiter: { n: [100.4542, 2.76854e-5], i: [1.303, -1.557e-7], w: [273.8777, 1.64505e-5], a: 5.20256, e: [0.048498, 4.469e-9], m: [19.895, 0.0830853001] },
    Saturn: { n: [113.6634, 2.3898e-5], i: [2.4886, -1.081e-7], w: [339.3939, 2.97661e-5], a: 9.55475, e: [0.055546, -9.499e-9], m: [316.967, 0.0334442282] },
  };

  function planetPosition(name, jd) {
    const el = PLANETS[name];
    if (!el) return null;
    const d = jd - 2451543.5;

    const n = el.n[0] + el.n[1] * d;
    const i = el.i[0] + el.i[1] * d;
    const w = el.w[0] + el.w[1] * d;
    const e = el.e[0] + el.e[1] * d;
    const m = norm(el.m[0] + el.m[1] * d);

    let ecc = m + RAD2DEG * e * sinD(m) * (1 + e * cosD(m));
    for (let k = 0; k < 5; k += 1) {
      ecc -= (ecc - RAD2DEG * e * sinD(ecc) - m) / (1 - e * cosD(ecc));
    }
    const xv = el.a * (cosD(ecc) - e);
    const yv = el.a * (Math.sqrt(1 - e * e) * sinD(ecc));
    const v = norm(atan2D(yv, xv));
    const r = Math.sqrt(xv * xv + yv * yv);

    const xh = r * (cosD(n) * cosD(v + w) - sinD(n) * sinD(v + w) * cosD(i));
    const yh = r * (sinD(n) * cosD(v + w) + cosD(n) * sinD(v + w) * cosD(i));
    const zh = r * sinD(v + w) * sinD(i);

    const ws2 = 282.9404 + 4.70935e-5 * d;
    const es = 0.016709 - 1.151e-9 * d;
    const ms2 = norm(356.047 + 0.9856002585 * d);
    let eccS = ms2 + RAD2DEG * es * sinD(ms2) * (1 + es * cosD(ms2));
    eccS -= (eccS - RAD2DEG * es * sinD(eccS) - ms2) / (1 - es * cosD(eccS));
    const xvS = cosD(eccS) - es;
    const yvS = Math.sqrt(1 - es * es) * sinD(eccS);
    const vS = norm(atan2D(yvS, xvS));
    const rS = Math.sqrt(xvS * xvS + yvS * yvS);
    const lonSun = norm(vS + ws2);
    const xs = rS * cosD(lonSun);
    const ys = rS * sinD(lonSun);

    const xg = xh + xs;
    const yg = yh + ys;
    const zg = zh;
    return {
      lon: norm(atan2D(yg, xg)),
      lat: atan2D(zg, Math.sqrt(xg * xg + yg * yg)),
      dist: Math.sqrt(xg * xg + yg * yg + zg * zg),
    };
  }

  function altitude(eclLon, eclLat, jd, latitude, longitude) {
    const obliquity = 23.4393 - 3.563e-7 * (jd - 2451543.5);
    const x = cosD(eclLon) * cosD(eclLat);
    const y = sinD(eclLon) * cosD(eclLat);
    const z = sinD(eclLat);
    const xe = x;
    const ye = y * cosD(obliquity) - z * sinD(obliquity);
    const ze = y * sinD(obliquity) + z * cosD(obliquity);
    const ra = norm(atan2D(ye, xe));
    const dec = atan2D(ze, Math.sqrt(xe * xe + ye * ye));

    const d = jd - 2451545.0;
    const gmst = norm(280.46061837 + 360.98564736629 * d);
    const lst = norm(gmst + longitude);
    const ha = norm(lst - ra);
    const sinAlt = sinD(latitude) * sinD(dec) + cosD(latitude) * cosD(dec) * cosD(ha);
    return Math.asin(Math.max(-1, Math.min(1, sinAlt))) * RAD2DEG;
  }

  function bodyAltitudeFn(body) {
    if (body === "sun") {
      return (jd, lat, lon) => altitude(solarEclipticLongitude(jd), 0, jd, lat, lon);
    }
    if (body === "moon") {
      return (jd, lat, lon) => {
        const p = moonPosition(jd);
        return altitude(p.lon, p.lat, jd, lat, lon);
      };
    }
    return (jd, lat, lon) => {
      const p = planetPosition(body, jd);
      return p ? altitude(p.lon, p.lat, jd, lat, lon) : -90;
    };
  }

  function crossing(latitude, longitude, date, target, rising, body) {
    const altFn = bodyAltitudeFn(body);
    const dayStart = new Date(date);
    dayStart.setHours(0, 0, 0, 0);
    const step = 240000; // 4 minutes
    let prev = altFn(julianDay(dayStart), latitude, longitude) - target;
    let t = dayStart.getTime() + step;
    const end = dayStart.getTime() + 36 * 3600000;

    while (t <= end) {
      const cur = altFn(julianDay(new Date(t)), latitude, longitude) - target;
      const crossed = rising ? prev < 0 && cur >= 0 : prev > 0 && cur <= 0;
      if (crossed) {
        let lo = t - step;
        let hi = t;
        for (let k = 0; k < 12; k += 1) {
          const mid = lo + (hi - lo) / 2;
          const v = altFn(julianDay(new Date(mid)), latitude, longitude) - target;
          if ((rising && v < 0) || (!rising && v > 0)) lo = mid;
          else hi = mid;
        }
        if (hi >= date.getTime() - 6 * 3600000) return new Date(hi);
      }
      prev = cur;
      t += step;
    }
    return null;
  }

  function phaseName(elongation) {
    if (elongation < 22.5) return "New Moon";
    if (elongation < 67.5) return "Waxing Crescent";
    if (elongation < 112.5) return "First Quarter";
    if (elongation < 157.5) return "Waxing Gibbous";
    if (elongation < 202.5) return "Full Moon";
    if (elongation < 247.5) return "Waning Gibbous";
    if (elongation < 292.5) return "Last Quarter";
    if (elongation < 337.5) return "Waning Crescent";
    return "New Moon";
  }

  function snapshot(latitude, longitude, date = new Date()) {
    const jd = julianDay(date);
    const moon = moonPosition(jd);
    const sunLon = solarEclipticLongitude(jd);
    const elongation = norm(moon.lon - sunLon);
    const illumination = (1 - cosD(elongation)) / 2;

    const sun = {
      sunrise: crossing(latitude, longitude, date, -0.833, true, "sun"),
      sunset: crossing(latitude, longitude, date, -0.833, false, "sun"),
      civilDawn: crossing(latitude, longitude, date, -6, true, "sun"),
      civilDusk: crossing(latitude, longitude, date, -6, false, "sun"),
    };

    // Mercury retrograde: geocentric longitude moving backward day-over-day.
    const mercNow = planetPosition("Mercury", jd);
    const mercLater = planetPosition("Mercury", jd + 1);
    let delta = mercLater.lon - mercNow.lon;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;

    const planets = Object.keys(PLANETS).map((name) => {
      const rise = crossing(latitude, longitude, date, 0, true, name);
      const set = crossing(latitude, longitude, date, 0, false, name);
      let visible = false;
      if (sun.sunset) {
        let endWindow = sun.civilDawn ? sun.civilDawn.getTime() : sun.sunset.getTime() + 9 * 3600000;
        // After midnight "today's dawn" precedes tonight's sunset — night ends at the NEXT dawn.
        if (endWindow <= sun.sunset.getTime()) endWindow += 24 * 3600000;
        const altFn = bodyAltitudeFn(name);
        for (let t = sun.sunset.getTime(); t <= endWindow; t += 1200000) {
          if (altFn(julianDay(new Date(t)), latitude, longitude) > 5) {
            visible = true;
            break;
          }
        }
      }
      return { name, rise, set, visible };
    });

    return {
      sun,
      moon: {
        moonrise: crossing(latitude, longitude, date, 0.125, true, "moon"),
        moonset: crossing(latitude, longitude, date, 0.125, false, "moon"),
        illumination,
        phase: phaseName(elongation),
        ageDays: (elongation / 360) * 29.530588853,
        sign: ZODIAC[Math.floor(norm(moon.lon) / 30) % 12],
      },
      sunSign: ZODIAC[Math.floor(norm(sunLon) / 30) % 12],
      mercuryRetrograde: delta < 0,
      planets,
    };
  }

  /// Equatorial (RA/Dec, degrees) -> horizontal (alt/az, degrees) for an observer now.
  function horizontal(raDeg, decDeg, date, latitude, longitude) {
    const jd = julianDay(date);
    const d = jd - 2451545.0;
    const gmst = norm(280.46061837 + 360.98564736629 * d);
    const lst = norm(gmst + longitude);
    const ha = norm(lst - raDeg);
    const sinAlt = sinD(latitude) * sinD(decDeg) + cosD(latitude) * cosD(decDeg) * cosD(ha);
    const alt = Math.asin(Math.max(-1, Math.min(1, sinAlt))) * RAD2DEG;
    const y = -sinD(ha) * cosD(decDeg);
    const x = cosD(latitude) * sinD(decDeg) - sinD(latitude) * cosD(decDeg) * cosD(ha);
    const az = norm(atan2D(y, x));
    return { alt, az };
  }

  function eclipticToEquatorial(lon, lat, jd) {
    const ob = 23.4393 - 3.563e-7 * (jd - 2451543.5);
    const x = cosD(lon) * cosD(lat);
    const y = sinD(lon) * cosD(lat) * cosD(ob) - sinD(lat) * sinD(ob);
    const z = sinD(lon) * cosD(lat) * sinD(ob) + sinD(lat) * cosD(ob);
    return { ra: norm(atan2D(y, x)), dec: atan2D(z, Math.sqrt(x * x + y * y)) };
  }

  /// Sun, moon, and planets as chart-ready equatorial coordinates.
  function chartBodies(date = new Date()) {
    const jd = julianDay(date);
    const bodies = [];
    const sunEq = eclipticToEquatorial(solarEclipticLongitude(jd), 0, jd);
    bodies.push({ name: "Sun", kind: "sun", ...sunEq });
    const moon = moonPosition(jd);
    const moonEq = eclipticToEquatorial(moon.lon, moon.lat, jd);
    bodies.push({ name: "Moon", kind: "moon", ...moonEq });
    for (const name of Object.keys(PLANETS)) {
      const p = planetPosition(name, jd);
      if (p) bodies.push({ name, kind: "planet", ...eclipticToEquatorial(p.lon, p.lat, jd) });
    }
    return bodies;
  }

  function elongationAt(date) {
    const jd = julianDay(date);
    return norm(moonPosition(jd).lon - solarEclipticLongitude(jd));
  }

  /// Next moment the moon's elongation crosses `target` (0 = new, 180 = full).
  function nextPhase(target, from = new Date()) {
    const delta = (date) => {
      let d = (elongationAt(date) - target) % 360;
      if (d <= -180) d += 360;
      if (d > 180) d -= 360;
      return d;
    };
    let t = from.getTime();
    let prev = delta(new Date(t));
    const step = 6 * 3600000;
    for (let i = 0; i < 31 * 4; i += 1) {
      const next = t + step;
      const cur = delta(new Date(next));
      if (prev < 0 && cur >= 0) {
        let lo = t;
        let hi = next;
        for (let k = 0; k < 20; k += 1) {
          const mid = lo + (hi - lo) / 2;
          if (delta(new Date(mid)) < 0) lo = mid;
          else hi = mid;
        }
        return new Date(hi);
      }
      prev = cur;
      t = next;
    }
    return null;
  }

  const SHOWERS = [
    [1, 3, "Quadrantids", 110, "Sharp overnight peak"],
    [4, 22, "Lyrids", 18, "Best after midnight"],
    [5, 5, "Eta Aquariids", 50, "Pre-dawn, Halley's debris"],
    [7, 30, "Delta Aquariids", 25, "Best from midnight south"],
    [8, 12, "Perseids", 100, "The summer classic"],
    [10, 21, "Orionids", 20, "Pre-dawn, Halley's debris"],
    [11, 17, "Leonids", 15, "Late night into dawn"],
    [12, 13, "Geminids", 150, "The year's strongest"],
    [12, 22, "Ursids", 10, "Quiet, near solstice"],
  ];
  const ECLIPSES = [
    [2026, 8, 28, "Partial lunar eclipse", "Visible from the Americas, evening"],
    [2028, 1, 12, "Partial lunar eclipse", "Visible from the Americas"],
    [2028, 12, 31, "Total lunar eclipse", "Visible from the Americas"],
  ];

  /// The next several sky events, soonest first.
  function upcomingEvents(limit = 6, now = new Date()) {
    const events = [];
    const full = nextPhase(180, now);
    if (full) events.push({ date: full, title: "Full Moon", detail: "Rises around sunset", kind: "moon" });
    const newMoon = nextPhase(0, now);
    if (newMoon) events.push({ date: newMoon, title: "New Moon", detail: "Darkest skies of the month", kind: "moon" });
    const year = now.getFullYear();
    for (const [month, day, name, zhr, note] of SHOWERS) {
      for (const y of [year, year + 1]) {
        const date = new Date(y, month - 1, day, 22);
        if (date >= now && date - now < 370 * 86400000) {
          events.push({ date, title: `${name} peak`, detail: `${note} · up to ${zhr}/hr`, kind: "shower" });
          break;
        }
      }
    }
    for (const [y, m, d, title, note] of ECLIPSES) {
      const date = new Date(y, m - 1, d, 21);
      if (date >= now) events.push({ date, title, detail: note, kind: "eclipse" });
    }
    return events.sort((a, b) => a.date - b.date).slice(0, limit);
  }

  return { snapshot, horizontal, chartBodies, upcomingEvents };
})();
