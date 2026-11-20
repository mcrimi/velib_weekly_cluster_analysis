import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { profileOf, distance, distances, nearest, membership, project, hourLabel, titleCase, markerFor } from "../js/model.js";
import { fitMap, nearestPoint, markerSvg } from "../js/map.js";

const load = (path) => JSON.parse(readFileSync(new URL(path, import.meta.url)));
const stations = load("../data/stations.json");
const story = load("../data/story.json");
const fixtures = load("./fixtures.json");
const basemap = load("../data/basemap.json");

test("the export has one week for every station", () => {
  assert.equal(stations.profile.length, stations.name.length);
  assert.equal(stations.profile.length, story.n);
  assert.ok(stations.profile.every((row) => row.length === 168 && row.every((v) => Number.isInteger(v) && v >= 0 && v <= stations.scale)));
  assert.deepEqual(stations.days, ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]);
  for (const key of ["x", "y", "mean"]) assert.equal(stations[key].length, story.n);
  assert.equal(stations.pca.center.length, 168);
  assert.equal(stations.pca.rotation.length, 2);
});

test("distances and nearest centres match R, for every number of clusters", () => {
  assert.ok(fixtures.cases.length >= 40);
  let checked = 0;
  for (const c of fixtures.cases) {
    const profile = profileOf(stations, c.station);
    for (const [k, expected] of Object.entries(c.clusters)) {
      const got = distances(profile, stations.clusters[k].centre);
      assert.equal(got.length, Number(k));
      got.forEach((d, i) => assert.ok(Math.abs(d - expected.distance[i]) < 1e-9, `station ${c.station}, K=${k}`));
      assert.equal(nearest(got), expected.nearest, `station ${c.station}, K=${k}`);
      checked += 1;
    }
  }
  assert.ok(checked >= 200);
});

test("principal component scores match R", () => {
  for (const c of fixtures.cases) {
    const got = project(profileOf(stations, c.station), stations.pca);
    got.forEach((s, i) => assert.ok(Math.abs(s - c.score[i]) < 1e-9, `station ${c.station}`));
    // The scores shipped for display are the unrounded R values to 3 decimals.
    assert.ok(Math.abs(got[0] - stations.score[0][c.station]) < 0.05);
  }
});

test("almost every station is nearest to the centre of its own cluster", () => {
  for (const [k, cl] of Object.entries(stations.clusters)) {
    let same = 0;
    for (let i = 0; i < stations.profile.length; i += 1) {
      if (nearest(distances(profileOf(stations, i), cl.centre)) === cl.assign[i]) same += 1;
    }
    const share = same / stations.profile.length;
    assert.ok(share > 0.995, `K=${k}: ${share}`);
    assert.ok(Math.abs(share - fixtures.agreement[k]) < 1e-12);
    assert.deepEqual(cl.groups.map((g) => g.n), cl.groups.map((_, g) => cl.assign.filter((a) => a === g).length));
  }
});

test("clusters are numbered from fullest to emptiest and named distinctly", () => {
  for (const cl of Object.values(stations.clusters)) {
    const fill = cl.groups.map((g) => g.mean_fill);
    assert.deepEqual(fill, [...fill].sort((a, b) => b - a));
    assert.equal(new Set(cl.groups.map((g) => g.label)).size, cl.groups.length);
    const markers = cl.groups.map((g) => JSON.stringify(markerFor(g)));
    assert.equal(new Set(markers).size, markers.length, "each cluster needs its own marker");
  }
});

test("markers encode movement by shape", () => {
  assert.deepEqual(markerFor({ level: "Full", movement: "steady" }), { shape: "square", tone: "solid" });
  assert.deepEqual(markerFor({ level: "Empty", movement: "steady" }), { shape: "square", tone: "open" });
  assert.deepEqual(markerFor({ level: "Half full", movement: "steady" }), { shape: "square", tone: "mid" });
  assert.deepEqual(markerFor({ level: "Half full", movement: "fills sharply by day" }), { shape: "up", tone: "solid" });
  assert.deepEqual(markerFor({ level: "Full", movement: "empties by day" }), { shape: "down", tone: "open" });
  assert.match(markerSvg({ shape: "up", tone: "open" }), /class="open"/);
});

test("membership finds the runner-up and survives odd input", () => {
  assert.deepEqual(membership([3, 1, 2]), { first: 1, second: 2, ratio: 0.5 });
  assert.deepEqual(membership([2, 2]), { first: 0, second: 1, ratio: 1 });
  assert.deepEqual(membership([5]), { first: 0, second: -1, ratio: 1 });
  assert.deepEqual(membership([0, 0]), { first: 0, second: 1, ratio: 1 });
  assert.equal(nearest([]), -1);
  assert.equal(nearest([NaN, 4]), 1);
  assert.throws(() => distance([1, 2], [1]));
  assert.equal(distance([0, 3], [4, 0]), 5);
});

test("hours of the week are labelled", () => {
  assert.equal(hourLabel(0, stations.days), "Monday 00:00");
  assert.equal(hourLabel(32, stations.days), "Tuesday 08:00");
  assert.equal(hourLabel(167, stations.days), "Sunday 23:00");
});

test("station names are set in title case", () => {
  assert.equal(titleCase("OPERA - CAPUCINES"), "Opera - Capucines");
  assert.equal(titleCase("REPUBLIQUE 1 (BOULOGNE-BILLANCOURT)"), "Republique 1 (Boulogne-Billancourt)");
  assert.equal(titleCase("CHOISY POINT D'IVRY"), "Choisy Point D'Ivry");
  assert.equal(titleCase(""), "");
});

test("the map fits inside its canvas with north up", () => {
  const layout = fitMap(stations.x, stations.y, 600, 16);
  assert.ok(layout.height > 250 && layout.height < 600);
  for (let i = 0; i < layout.px.length; i += 1) {
    assert.ok(layout.px[i] >= 15.9 && layout.px[i] <= 584.1);
    assert.ok(layout.py[i] >= 15.9 && layout.py[i] <= layout.height - 15.9);
  }
  const north = stations.y.indexOf(Math.max(...stations.y));
  assert.ok(Math.abs(layout.py[north] - 16) < 0.01);
  // One kilometre is the same number of pixels in both directions.
  assert.ok(Math.abs(layout.scale - (600 - 32) / (Math.max(...stations.x) - Math.min(...stations.x))) < 1e-9);
});

test("clicks find the nearest station within reach", () => {
  const px = Float32Array.from([10, 50, 90]);
  const py = Float32Array.from([10, 50, 90]);
  assert.equal(nearestPoint(px, py, 52, 47), 1);
  assert.equal(nearestPoint(px, py, 30, 30, 10), -1);
  assert.equal(nearestPoint(new Float32Array(0), new Float32Array(0), 1, 1), -1);
  assert.equal(fitMap([1], [1], 100).px.length, 1);
});

test("the story carries the numbers the page quotes", () => {
  assert.deepEqual(story.validity.map((d) => d.k), [2, 3, 4, 5, 6, 7, 8]);
  assert.equal(story.four.length, 4);
  assert.equal(story.bonus.by_cluster.reduce((sum, c) => sum + c.bonus, 0), story.bonus.n);
  assert.equal(story.four.reduce((sum, g) => sum + g.n, 0), story.n);
  for (const row of story.spatial) assert.ok(row.observed > row.null_max);
  assert.equal(story.pca.loadings[0].length, 168);
});

test("the base map lines up with the stations", () => {
  assert.equal(basemap.boundaries.length, 20);
  assert.ok(basemap.water.length > 10);
  assert.match(basemap.source, /Open Database Licence/);
  const layout = fitMap(stations.x, stations.y, 600, 16);
  // The same projection as the stations: a station's own coordinates land on its pixel.
  assert.ok(Math.abs(layout.toX(stations.x[7]) - layout.px[7]) < 1e-3);
  assert.ok(Math.abs(layout.toY(stations.y[7]) - layout.py[7]) < 1e-3);
  for (const ring of [...basemap.boundaries, ...basemap.water]) {
    assert.equal(ring.x.length, ring.y.length);
    assert.ok(ring.x.length >= 4);
    assert.ok(ring.x.every((x, i) => Number.isFinite(x) && Number.isFinite(ring.y[i])));
    // Closed, and inside the canvas with room to spare.
    assert.equal(ring.x[0], ring.x[ring.x.length - 1]);
    assert.ok(ring.x.every((x) => layout.toX(x) > 0 && layout.toX(x) < 600));
    assert.ok(ring.y.every((y) => layout.toY(y) > 0 && layout.toY(y) < layout.height));
  }
});
