// Wiring for /velib/: the station map, the station panel and the findings charts.

import { profileOf, distances, membership, project, hourLabel, titleCase, markerFor } from "./model.js";
import { drawMap, nearestPoint, markerSvg } from "./map.js";
import { drawLines, DASHES } from "./charts.js";

const $ = (id) => document.getElementById(id);
const fill = (key, text) => document.querySelectorAll(`[data-fill="${key}"]`).forEach((el) => { el.textContent = text; });
const pct = (p, digits = 0) => (Number.isFinite(p) ? `${(100 * p).toFixed(digits)}%` : "–");
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

const HOURS = 168;
const DAY_TICKS = [0, 24, 48, 72, 96, 120, 144, 168];
const START_STATION = "OPERA - CAPUCINES";
const BASE_NOTE = "North is up. Hairlines are the arrondissements of Paris; the grey band is the Seine, with the canals to the north-east.";

const state = { k: "4", view: "clusters", hour: 32, selected: -1, focus: null, uphill: false, playing: false };
let stations = null;
let story = null;
let basemap = null;
let layout = null;
let timer = null;

const dayBands = () => stations.days.map((label, i) => ({ from: 24 * i, to: 24 * (i + 1), label }));
const clustering = () => stations.clusters[state.k];

/* ---------- Paper settings (shared with the main site) ---------- */

function initPaper(onChange) {
  const KEY = "mcrimi-site";
  const read = () => { try { return JSON.parse(localStorage.getItem(KEY) || "{}") || {}; } catch (e) { return {}; } };
  const root = document.documentElement;
  const buttons = [...document.querySelectorAll("[data-paper]")];
  const show = (paper) => buttons.forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.paper === paper)));
  show(read().paper || "warm");
  buttons.forEach((b) => b.addEventListener("click", () => {
    const paper = b.dataset.paper;
    root.dataset.theme = paper === "night" ? "dark" : "light";
    if (paper === "grey") root.dataset.paper = "grey"; else delete root.dataset.paper;
    try { localStorage.setItem(KEY, JSON.stringify({ ...read(), paper })); } catch (e) { /* private mode: keep it for this visit only */ }
    show(paper);
    onChange();
  }));
  const aa = $("aa");
  const panel = $("panel");
  const toggle = (open) => { panel.hidden = !open; aa.setAttribute("aria-expanded", String(open)); };
  aa.addEventListener("click", () => toggle(panel.hidden));
  document.addEventListener("click", (e) => { if (!panel.hidden && !panel.contains(e.target) && e.target !== aa) toggle(false); });
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") toggle(false); });
}

/* ---------- Map ---------- */

function renderMap() {
  if (!stations) return;
  const cl = clustering();
  const hourFill = new Float32Array(stations.profile.length);
  for (let i = 0; i < hourFill.length; i += 1) hourFill[i] = stations.profile[i][state.hour] / stations.scale;
  layout = drawMap($("stations"), stations.x, stations.y, {
    view: state.view,
    assign: cl.assign,
    markers: cl.groups.map(markerFor),
    focus: state.view === "clusters" ? state.focus : null,
    fill: hourFill,
    uphill: state.uphill ? stations.bonus : null,
    selected: state.selected,
    base: basemap,
  });
  $("map-cap").textContent = state.view === "fill"
    ? `${hourLabel(state.hour, stations.days)}. Each square is a station, and its area is the share of its docks holding a bike. ${BASE_NOTE}`
    : `Each mark is a station, drawn with the marker of its cluster. Click one to see its week. ${BASE_NOTE}`;
}

function renderLegend() {
  const cl = clustering();
  $("legend").innerHTML = cl.groups.map((g, i) => `<li><button type="button" data-group="${i}" aria-pressed="${state.focus === i}">${markerSvg(markerFor(g))}<span>${esc(g.label)}</span><span class="n">${g.n}</span></button></li>`).join("");
}

function renderVerdict() {
  if (!stations || !story) return;
  const k = Number(state.k);
  const v = story.validity.find((row) => row.k === k);
  const b = story.benchmark.find((row) => row.k === k);
  const s = story.spatial.find((row) => row.k === k);
  $("r-k").textContent = k;
  $("r-stability").textContent = v.stability_ari.toFixed(2);
  $("r-silhouette").textContent = v.silhouette.toFixed(2);
  $("r-neighbours").textContent = pct(s.observed);
  const steady = v.stability_ari >= 0.9;
  $("verdict").innerHTML = steady
    ? `A cut into ${k} holds still: re-run on resampled stations, the same groups come back (agreement <strong>${v.stability_ari.toFixed(2)}</strong> out of 1).`
    : `A cut into ${k} is shakier: re-run on resampled stations, the groups shift (agreement <strong>${v.stability_ari.toFixed(2)}</strong> out of 1; its least stable cluster overlaps its re-run counterpart by ${pct(v.weakest_jaccard)}).`;
  $("verdict-fine").textContent = `Simulated data with no clusters at all scores ${b.stability_ari.toFixed(2)} for stability and ${b.silhouette.toFixed(2)} for silhouette. ${pct(s.observed)} of nearest neighbours share a cluster; random labels would give ${pct(s.expected)}.`;
}

/* ---------- Station panel ---------- */

function renderStation() {
  if (!stations || state.selected < 0) return;
  const i = state.selected;
  const cl = clustering();
  const profile = profileOf(stations, i);
  const group = cl.assign[i];
  const dist = distances(profile, cl.centre);
  const fit = membership(dist);
  const [level, workday] = project(profile, stations.pca);
  const hilly = stations.bonusSet.has(i);

  $("station").hidden = false;
  $("s-name").textContent = titleCase(stations.name[i]);
  $("s-cluster").textContent = cl.groups[group].label;
  $("s-mean").textContent = `${pct(stations.mean[i])}${hilly ? " · a bonus station, on high ground" : ""}`;
  // The k-means cluster is the nearest centre in R's unrounded data; after
  // rounding for export the browser can disagree for a handful of stations.
  const other = fit.first === group ? fit.second : fit.first;
  const ratio = fit.first === group ? fit.ratio : 1;
  $("s-fit").textContent = other < 0
    ? "–"
    : ratio > 0.9
      ? `Borderline: almost as close to “${cl.groups[other].label}”. Fill score ${level.toFixed(1)}, working-day score ${workday.toFixed(1)}.`
      : `Clear: ${Math.round((1 / ratio - 1) * 100)}% further from the next cluster, “${cl.groups[other].label}”. Fill score ${level.toFixed(1)}, working-day score ${workday.toFixed(1)}.`;

  const hours = Array.from({ length: HOURS }, (_, h) => h);
  drawLines($("station-chart"), {
    x: [0, HOURS], y: [0, 1], labelWidth: 62, ratio: 0.42,
    xTicks: DAY_TICKS, xBands: dayBands(), cursor: state.hour + 0.5,
    yFormat: (v) => `${Math.round(v * 100)}%`,
    series: [
      { label: "Cluster", x: hours.map((h) => h + 0.5), y: cl.centre[group], dash: DASHES[1] },
      { label: "Station", x: hours.map((h) => h + 0.5), y: Array.from(profile) },
    ],
  });
}

function select(i) {
  if (i < 0 || i >= stations.name.length) return;
  state.selected = i;
  renderMap();
  renderStation();
}

/* ---------- Controls ---------- */

function setHour(hour, fromPlayback = false) {
  state.hour = ((hour % HOURS) + HOURS) % HOURS;
  $("hour").value = state.hour;
  $("hour-out").textContent = stations ? hourLabel(state.hour, stations.days) : "";
  if (!fromPlayback && state.view !== "fill") setView("fill", false);
  renderMap();
  renderStation();
}

function setView(view, redraw = true) {
  state.view = view;
  document.querySelectorAll("#view button").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.view === view)));
  if (view !== "fill") setPlaying(false);
  if (redraw) renderMap();
}

function setPlaying(on) {
  state.playing = on;
  $("play").textContent = on ? "Pause" : "Play the week";
  clearInterval(timer);
  // One hour per tick, stepped: no easing between hours.
  if (on) timer = setInterval(() => setHour(state.hour + 1, true), 160);
}

function setK(k) {
  state.k = String(k);
  state.focus = null;
  document.querySelectorAll("#ks button").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.k === state.k)));
  renderLegend();
  renderVerdict();
  renderMap();
  renderStation();
}

function initControls() {
  $("ks").innerHTML = Object.keys(stations.clusters).map((k) => `<button type="button" data-k="${k}">${k}</button>`).join("");
  $("ks").addEventListener("click", (e) => {
    const b = e.target.closest("button[data-k]");
    if (!b) return;
    setView("clusters", false);
    setK(b.dataset.k);
  });
  $("view").addEventListener("click", (e) => {
    const b = e.target.closest("button[data-view]");
    if (b) setView(b.dataset.view);
  });
  $("hour").addEventListener("input", (e) => { setPlaying(false); setHour(Number(e.target.value)); });
  $("play").addEventListener("click", () => {
    if (!state.playing) setView("fill", false);
    setPlaying(!state.playing);
    renderMap();
  });
  $("uphill").addEventListener("click", () => {
    state.uphill = !state.uphill;
    $("uphill").setAttribute("aria-pressed", String(state.uphill));
    $("uphill").classList.toggle("primary", state.uphill);
    renderMap();
  });
  $("legend").addEventListener("click", (e) => {
    const b = e.target.closest("button[data-group]");
    if (!b) return;
    const g = Number(b.dataset.group);
    state.focus = state.focus === g ? null : g;
    setView("clusters", false);
    renderLegend();
    renderMap();
  });
  $("stations").addEventListener("click", (e) => {
    if (!layout) return;
    const box = e.currentTarget.getBoundingClientRect();
    const scale = layout.width / box.width;
    const hit = nearestPoint(layout.px, layout.py, (e.clientX - box.left) * scale, (e.clientY - box.top) * scale, 16);
    if (hit >= 0) select(hit);
  });
  $("random").addEventListener("click", () => select(Math.floor(Math.random() * stations.name.length)));
  $("controls").addEventListener("submit", (e) => e.preventDefault());
  document.addEventListener("visibilitychange", () => { if (document.hidden) setPlaying(false); });
}

/* ---------- Findings ---------- */

const SHORT = { "Full, steady": "Full", "Empty, steady": "Empty", "Half full, fills sharply by day": "Fills by day", "Half full, empties sharply by day": "Empties by day" };

function drawFindings() {
  if (!story || !stations) return;
  const hours = Array.from({ length: HOURS }, (_, h) => h + 0.5);
  const [first, second] = story.pca.loadings;
  const top = Math.max(...first, ...second.map(Math.abs));
  const bound = Math.ceil(top * 20) / 20;
  drawLines($("loadings-chart"), {
    x: [0, HOURS], y: [-bound, bound], labelWidth: 96, ratio: 0.42,
    xTicks: DAY_TICKS, xBands: dayBands(), yFormat: (v) => v.toFixed(2),
    series: [
      { label: "1: fill level", x: hours, y: first },
      { label: "2: working day", x: hours, y: second, dash: DASHES[1] },
    ],
  });

  const day = Array.from({ length: 24 }, (_, h) => h);
  drawLines($("weekday-chart"), {
    x: [0, 23], y: [0, 1], labelWidth: 104, ratio: 0.7, xLabel: "Hour of a weekday",
    xTicks: [0, 6, 12, 18, 23], xFormat: (v) => `${v}h`, yFormat: (v) => `${Math.round(v * 100)}%`,
    series: story.four.map((g, i) => ({ label: SHORT[g.label] || g.label, x: day, y: g.weekday, dash: DASHES[i % DASHES.length] })),
  });

  const ks = story.spatial.map((d) => d.k);
  const kAxis = { x: [ks[0], ks[ks.length - 1]], xTicks: ks, xLabel: "Number of clusters", ratio: 0.7 };
  drawLines($("spatial-chart"), {
    ...kAxis, y: [0, 1], labelWidth: 84, yFormat: (v) => `${Math.round(v * 100)}%`,
    series: [
      { label: "Stations", x: ks, y: story.spatial.map((d) => d.observed) },
      { label: "Random", x: ks, y: story.spatial.map((d) => d.expected), dash: DASHES[1] },
    ],
    points: story.spatial.map((d) => ({ x: d.k, y: d.observed })),
  });
  drawLines($("stability-chart"), {
    ...kAxis, y: [0.4, 1], labelWidth: 88, yFormat: (v) => v.toFixed(1),
    series: [
      { label: "Stations", x: ks, y: story.validity.map((d) => d.stability_ari) },
      { label: "No clusters", x: ks, y: story.benchmark.map((d) => d.stability_ari), dash: DASHES[1] },
    ],
    points: story.validity.map((d) => ({ x: d.k, y: d.stability_ari })),
  });
  drawLines($("silhouette-chart"), {
    ...kAxis, y: [0, 0.5], labelWidth: 88, yFormat: (v) => v.toFixed(1),
    series: [
      { label: "Stations", x: ks, y: story.validity.map((d) => d.silhouette) },
      { label: "No clusters", x: ks, y: story.benchmark.map((d) => d.silhouette), dash: DASHES[1] },
    ],
    points: story.validity.map((d) => ({ x: d.k, y: d.silhouette })),
  });
}

function fillFindings() {
  const e = story.pca.explained;
  const at = (rows, k) => rows.find((row) => row.k === k);
  fill("pc1", Math.round(100 * e[0]));
  fill("pc2", Math.round(100 * e[1]));
  fill("pc12", Math.round(100 * (e[0] + e[1])));
  fill("nb-observed", Math.round(100 * at(story.spatial, 4).observed));
  fill("nb-expected", Math.round(100 * at(story.spatial, 4).expected));
  fill("nb-max", Math.round(100 * at(story.spatial, 4).null_max));
  fill("bonus-n", story.bonus.n);
  fill("bonus-fill", Math.round(100 * story.bonus.mean_fill_bonus));
  fill("other-fill", Math.round(100 * story.bonus.mean_fill_other));
  fill("bonus-share", Math.round(100 * story.bonus.emptiest_cluster_share));
  fill("sil-max", Math.max(...story.validity.map((d) => d.silhouette)).toFixed(2));
  fill("stab-4", at(story.validity, 4).stability_ari.toFixed(2));
  fill("stab-5", at(story.validity, 5).stability_ari.toFixed(2));
  $("bonus-table").querySelector("tbody").innerHTML = story.four.map((g, i) => {
    const b = story.bonus.by_cluster[i];
    return `<tr><th scope="row">${esc(g.label)}</th><td class="n">${g.n}</td><td class="n">${pct(g.mean_fill)}</td><td class="n">${b.bonus}</td><td class="n">${b.share > 0 && b.share < 0.005 ? "&lt;1%" : pct(b.share)}</td></tr>`;
  }).join("");
}

/* ---------- Start ---------- */

async function load(path) {
  const response = await fetch(path);
  if (!response.ok) throw new Error(`${path}: ${response.status}`);
  return response.json();
}

async function start() {
  initPaper(() => { renderMap(); });
  try {
    [stations, story] = await Promise.all([load("data/stations.json"), load("data/story.json")]);
  } catch (error) {
    console.error(error);
    $("verdict").textContent = "The station data could not be loaded. Reload the page to try again.";
    return;
  }
  stations.bonusSet = new Set(stations.bonus);
  // The base map is a nicety: the page works without it.
  load("data/basemap.json").then((data) => { basemap = data; renderMap(); }).catch((error) => console.warn(error));
  initControls();
  $("hour-out").textContent = hourLabel(state.hour, stations.days);
  setK(state.k);
  select(Math.max(0, stations.name.indexOf(START_STATION)));
  fillFindings();
  drawFindings();

  let width = innerWidth;
  let wait;
  addEventListener("resize", () => {
    if (innerWidth === width) return;
    width = innerWidth;
    clearTimeout(wait);
    wait = setTimeout(() => { renderMap(); renderStation(); drawFindings(); }, 120);
  });
}

start();
