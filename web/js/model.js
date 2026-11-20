// The arithmetic the page shares with the R pipeline: distance to cluster
// centres, nearest-centre assignment and projection onto principal components.
// web/test/model.test.js checks these against values computed in R from the
// same JSON.

/** A station's 168 hourly loadings as shares between 0 and 1. */
export function profileOf(data, station) {
  const row = data.profile[station];
  const out = new Float64Array(row.length);
  for (let i = 0; i < row.length; i += 1) out[i] = row[i] / data.scale;
  return out;
}

export function distance(a, b) {
  if (a.length !== b.length) throw new Error(`Length mismatch: ${a.length} and ${b.length}`);
  let sum = 0;
  for (let i = 0; i < a.length; i += 1) {
    const d = a[i] - b[i];
    sum += d * d;
  }
  return Math.sqrt(sum);
}

/** Euclidean distance from a profile to every cluster centre. */
export function distances(profile, centres) {
  return centres.map((centre) => distance(profile, centre));
}

/** Index of the smallest value; the first one wins a tie. */
export function nearest(values) {
  let best = -1;
  for (let i = 0; i < values.length; i += 1) {
    if (Number.isFinite(values[i]) && (best < 0 || values[i] < values[best])) best = i;
  }
  return best;
}

/**
 * How firmly a station belongs to its nearest cluster: the runner-up, and the
 * ratio of the two distances (1 means it sits exactly between two clusters).
 */
export function membership(values) {
  const first = nearest(values);
  const rest = values.map((v, i) => (i === first ? Infinity : v));
  const second = nearest(rest);
  const ratio = second < 0 || values[second] === 0 ? 1 : values[first] / values[second];
  return { first, second, ratio };
}

/** Scores on the exported principal components. */
export function project(profile, pca) {
  return pca.rotation.map((loading) => {
    let sum = 0;
    for (let i = 0; i < profile.length; i += 1) sum += (profile[i] - pca.center[i]) * loading[i];
    return sum;
  });
}

const DAY_NAMES = { Mon: "Monday", Tue: "Tuesday", Wed: "Wednesday", Thu: "Thursday", Fri: "Friday", Sat: "Saturday", Sun: "Sunday" };

/** "Tuesday 09:00" for an hour of the week (0 is Monday 00:00). */
export function hourLabel(index, days) {
  const hour = ((index % 24) + 24) % 24;
  const day = days[Math.floor(index / 24)] ?? days[days.length - 1];
  return `${DAY_NAMES[day] ?? day} ${String(hour).padStart(2, "0")}:00`;
}

/** Station names come in capitals; set them in title case. */
export function titleCase(name) {
  return name.toLowerCase().replace(/(^|[\s(\-'/])([a-zà-ÿ])/g, (_, lead, letter) => lead + letter.toUpperCase());
}

/**
 * Ink-only marker for a cluster. Shape says which way the working day moves
 * the stations; fill says how strongly, or for steady clusters how full.
 */
export function markerFor(group) {
  if (group.movement.startsWith("fills")) return { shape: "up", tone: group.movement.includes("sharply") ? "solid" : "open" };
  if (group.movement.startsWith("empties")) return { shape: "down", tone: group.movement.includes("sharply") ? "solid" : "open" };
  return { shape: "square", tone: group.level === "Full" ? "solid" : group.level === "Empty" ? "open" : "mid" };
}
