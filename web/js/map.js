// The station map: an ink drawing on a canvas. No tiles and no colour; the
// stations themselves draw the city.

/** Fit kilometre coordinates into a canvas of the given width. North is up. */
export function fitMap(xs, ys, width, pad = 14) {
  let x0 = Infinity; let x1 = -Infinity; let y0 = Infinity; let y1 = -Infinity;
  for (let i = 0; i < xs.length; i += 1) {
    if (xs[i] < x0) x0 = xs[i];
    if (xs[i] > x1) x1 = xs[i];
    if (ys[i] < y0) y0 = ys[i];
    if (ys[i] > y1) y1 = ys[i];
  }
  const spanX = x1 - x0 || 1;
  const spanY = y1 - y0 || 1;
  const scale = (width - 2 * pad) / spanX;
  const height = Math.ceil(spanY * scale + 2 * pad);
  const px = new Float32Array(xs.length);
  const py = new Float32Array(xs.length);
  for (let i = 0; i < xs.length; i += 1) {
    px[i] = pad + (xs[i] - x0) * scale;
    py[i] = pad + (y1 - ys[i]) * scale;
  }
  // The same projection for anything else in kilometre coordinates.
  const toX = (x) => pad + (x - x0) * scale;
  const toY = (y) => pad + (y1 - y) * scale;
  return { width, height, scale, px, py, toX, toY };
}

function ringPath(ctx, ring, layout) {
  ctx.moveTo(layout.toX(ring.x[0]), layout.toY(ring.y[0]));
  for (let i = 1; i < ring.x.length; i += 1) ctx.lineTo(layout.toX(ring.x[i]), layout.toY(ring.y[i]));
  ctx.closePath();
}

/** Waterways as a flat tint and arrondissement boundaries as hairlines. */
function drawBase(ctx, c, base, layout) {
  ctx.fillStyle = c.line;
  ctx.beginPath();
  for (const ring of base.water) ringPath(ctx, ring, layout);
  ctx.fill();
  ctx.strokeStyle = c.line;
  ctx.lineWidth = 1;
  ctx.beginPath();
  for (const ring of base.boundaries) ringPath(ctx, ring, layout);
  ctx.stroke();
}

/** The station closest to a point, or -1 if none is within reach. */
export function nearestPoint(px, py, x, y, reach = 14) {
  let best = -1;
  let bestD = reach * reach;
  for (let i = 0; i < px.length; i += 1) {
    const d = (px[i] - x) ** 2 + (py[i] - y) ** 2;
    if (d <= bestD) { best = i; bestD = d; }
  }
  return best;
}

function palette() {
  const css = getComputedStyle(document.documentElement);
  const get = (name) => css.getPropertyValue(name).trim();
  return { ink: get("--ink"), ink2: get("--ink-2"), line: get("--line"), paper: get("--paper"), sans: get("--sans") };
}

function shapePath(ctx, shape, x, y, s) {
  ctx.beginPath();
  if (shape === "square") {
    ctx.rect(x - s / 2, y - s / 2, s, s);
  } else {
    const h = s * 0.62;
    const dir = shape === "up" ? -1 : 1;
    ctx.moveTo(x, y + dir * h);
    ctx.lineTo(x - s * 0.62, y - dir * h * 0.8);
    ctx.lineTo(x + s * 0.62, y - dir * h * 0.8);
    ctx.closePath();
  }
}

function drawMarker(ctx, c, marker, x, y, s) {
  shapePath(ctx, marker.shape, x, y, s);
  if (marker.tone === "open") {
    ctx.fillStyle = c.paper;
    ctx.fill();
    ctx.strokeStyle = c.ink;
    ctx.lineWidth = 1;
    ctx.stroke();
  } else {
    ctx.fillStyle = marker.tone === "mid" ? c.ink2 : c.ink;
    ctx.fill();
  }
}

/**
 * state: { view: "clusters" | "fill", assign, markers, focus, fill, uphill, selected, base }
 *   base     { water, boundaries }: rings in the stations' coordinates, or null
 *   assign   cluster index per station
 *   markers  marker spec per cluster
 *   focus    cluster index to single out, or null
 *   fill     share of docks holding a bike per station, for the hour shown
 *   uphill   Set of station indices to ring, or null
 */
export function drawMap(canvas, xs, ys, state) {
  const width = Math.max(260, Math.round(canvas.getBoundingClientRect().width || 600));
  const layout = fitMap(xs, ys, width, width < 420 ? 10 : 16);
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  if (canvas.width !== width * dpr || canvas.height !== layout.height * dpr) {
    canvas.width = width * dpr;
    canvas.height = layout.height * dpr;
  }
  const ctx = canvas.getContext("2d");
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  const c = palette();
  ctx.fillStyle = c.paper;
  ctx.fillRect(0, 0, width, layout.height);

  if (state.base) drawBase(ctx, c, state.base, layout);

  const { px, py } = layout;
  const unit = Math.max(3.5, Math.min(6, width / 125));

  if (state.view === "fill") {
    ctx.fillStyle = c.ink;
    for (let i = 0; i < px.length; i += 1) {
      // Area in proportion to the share of docks holding a bike.
      const side = Math.max(1, unit * 1.35 * Math.sqrt(state.fill[i]));
      ctx.fillRect(px[i] - side / 2, py[i] - side / 2, side, side);
    }
  } else {
    // Faded clusters first, so the one in focus is drawn on top.
    if (state.focus !== null) {
      ctx.fillStyle = c.ink2;
      for (let i = 0; i < px.length; i += 1) {
        if (state.assign[i] !== state.focus) ctx.fillRect(px[i] - 0.5, py[i] - 0.5, 1, 1);
      }
    }
    for (let i = 0; i < px.length; i += 1) {
      const g = state.assign[i];
      if (state.focus !== null && g !== state.focus) continue;
      drawMarker(ctx, c, state.markers[g], px[i], py[i], unit);
    }
  }

  if (state.uphill) {
    ctx.strokeStyle = c.ink;
    ctx.lineWidth = 1;
    for (const i of state.uphill) {
      ctx.beginPath();
      ctx.arc(px[i], py[i], unit * 1.15, 0, 2 * Math.PI);
      ctx.stroke();
    }
  }

  if (state.selected >= 0) {
    const x = Math.round(px[state.selected]);
    const y = Math.round(py[state.selected]);
    const s = unit * 1.9;
    ctx.lineWidth = 4;
    ctx.strokeStyle = c.paper;
    ctx.strokeRect(x - s, y - s, 2 * s, 2 * s);
    ctx.lineWidth = 2;
    ctx.strokeStyle = c.ink;
    ctx.strokeRect(x - s, y - s, 2 * s, 2 * s);
  }

  // Scale bar: one kilometre.
  const bar = layout.scale;
  const bx = width - 12 - bar;
  const by = layout.height - 12;
  ctx.strokeStyle = c.ink;
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(bx + 0.5, by - 4); ctx.lineTo(bx + 0.5, by + 0.5); ctx.lineTo(bx + bar + 0.5, by + 0.5); ctx.lineTo(bx + bar + 0.5, by - 4);
  ctx.stroke();
  ctx.fillStyle = c.ink2;
  ctx.font = `11px ${c.sans}`;
  ctx.textAlign = "center";
  ctx.fillText("1 km", bx + bar / 2, by - 6);
  return layout;
}

/** The same marker as inline SVG, for the legend. */
export function markerSvg(marker) {
  const shape = marker.shape === "square"
    ? '<rect x="3" y="3" width="10" height="10"/>'
    : marker.shape === "up" ? '<path d="M8 2L14.5 13H1.5Z"/>' : '<path d="M8 14L14.5 3H1.5Z"/>';
  return `<svg viewBox="0 0 16 16" aria-hidden="true"><g class="${marker.tone}">${shape}</g></svg>`;
}
